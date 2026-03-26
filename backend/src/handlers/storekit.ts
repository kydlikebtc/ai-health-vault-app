/**
 * StoreKit 2 Server-Side Verification Handler
 *
 * Endpoints:
 *   POST /api/storekit/verify          — iOS client verifies a receipt
 *   POST /api/storekit/apple-webhook   — Apple Server-to-Server Notifications v2
 *
 * Design decisions:
 *   - No user accounts: Apple ID + original_transaction_id is the identity
 *   - anonymous_id = sha256(original_transaction_id) — never store raw tx IDs
 *   - Subscription status drives AI access in real-time
 *   - Grace period users retain Premium access (Apple standard behavior)
 */

import { verifyAppleJWS, decodeJWSPayload, sha256Hex } from '../lib/crypto.js';
import {
  type Env,
  type JWSTransactionPayload,
  type JWSRenewalInfoPayload,
  type AppleNotificationPayload,
  type SubscriptionRecord,
  type SubscriptionTier,
  type SubscriptionStatus,
  jsonError,
} from '../lib/types.js';

// ─────────────────────────────────────────────────────────────────────────────
// Client-facing: verify a StoreKit 2 receipt
// Called by iOS app on launch or after purchase to sync server state
// ─────────────────────────────────────────────────────────────────────────────

export async function handleStorekitVerify(request: Request, env: Env): Promise<Response> {
  if (request.method !== 'POST') {
    return jsonError('Method not allowed', 'method_not_allowed', 405);
  }

  let body: { receiptToken: string };
  try {
    body = await request.json<{ receiptToken: string }>();
  } catch {
    return jsonError('Invalid JSON body', 'invalid_request', 400);
  }

  const { receiptToken } = body;
  if (!receiptToken || typeof receiptToken !== 'string') {
    return jsonError('receiptToken is required', 'invalid_request', 400);
  }

  let txPayload: JWSTransactionPayload;
  try {
    txPayload = await verifyAppleJWS<JWSTransactionPayload>(receiptToken, env.APPLE_ROOT_CERT_PEM);
  } catch (err) {
    const msg = err instanceof Error ? err.message : 'unknown';
    return jsonError(`Receipt verification failed: ${msg}`, 'invalid_receipt', 401);
  }

  if (txPayload.bundleId !== env.APPLE_BUNDLE_ID) {
    return jsonError('Bundle ID mismatch', 'invalid_receipt', 401);
  }

  const anonymousId = await sha256Hex(txPayload.originalTransactionId);

  // Determine tier from product ID
  const tier = productIdToTier(txPayload.productId);

  // Determine status from expiry date
  const now = Math.floor(Date.now() / 1000);
  const expiresAt = txPayload.expiresDate ? Math.floor(txPayload.expiresDate / 1000) : null;
  const status: SubscriptionStatus = resolveStatus(expiresAt, now, null);

  // Upsert into D1
  await upsertSubscription(
    {
      anonymous_id: anonymousId,
      tier,
      status,
      expires_at: expiresAt,
      original_tx_id_hash: anonymousId,
      environment: txPayload.environment === 'Sandbox' ? 'sandbox' : 'production',
      updated_at: now,
    },
    env.DB
  );

  return Response.json({
    tier,
    status,
    expiresAt,
    anonymousId,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Apple Server-to-Server Notifications webhook
// Apple sends JWS-signed notifications for subscription lifecycle events
// ─────────────────────────────────────────────────────────────────────────────

export async function handleAppleWebhook(request: Request, env: Env): Promise<Response> {
  if (request.method !== 'POST') {
    return jsonError('Method not allowed', 'method_not_allowed', 405);
  }

  let rawBody: string;
  try {
    rawBody = await request.text();
  } catch {
    return jsonError('Failed to read request body', 'invalid_request', 400);
  }

  // Apple sends the entire notification as a signed JWS payload
  let notificationPayload: AppleNotificationPayload;
  try {
    notificationPayload = await verifyAppleJWS<AppleNotificationPayload>(rawBody, env.APPLE_ROOT_CERT_PEM);
  } catch (err) {
    const msg = err instanceof Error ? err.message : 'unknown';
    return jsonError(`Webhook JWS verification failed: ${msg}`, 'invalid_signature', 401);
  }

  const { notificationUUID, notificationType, subtype, data } = notificationPayload;

  if (data.bundleId !== env.APPLE_BUNDLE_ID) {
    return jsonError('Bundle ID mismatch', 'invalid_bundle', 400);
  }

  // ─── Idempotency check ───────────────────────────────────────────────────
  const existing = await env.DB.prepare(
    'SELECT notification_uuid FROM apple_notifications_log WHERE notification_uuid = ?'
  )
    .bind(notificationUUID)
    .first<{ notification_uuid: string }>();

  if (existing) {
    // Already processed — return 200 to prevent Apple from retrying
    return Response.json({ status: 'already_processed', notificationUUID });
  }

  // ─── Decode transaction JWS ──────────────────────────────────────────────
  let anonymousId: string | null = null;
  let newStatus: SubscriptionStatus = 'active';
  let newTier: SubscriptionTier = 'free';
  let expiresAt: number | null = null;

  if (data.signedTransactionInfo) {
    try {
      const txPayload = await verifyAppleJWS<JWSTransactionPayload>(
        data.signedTransactionInfo,
        env.APPLE_ROOT_CERT_PEM
      );
      anonymousId = await sha256Hex(txPayload.originalTransactionId);
      newTier = productIdToTier(txPayload.productId);
      expiresAt = txPayload.expiresDate ? Math.floor(txPayload.expiresDate / 1000) : null;
    } catch {
      // Log and continue — we'll still record the notification
    }
  }

  // Decode renewal info for grace period detection
  let isInBillingRetry = false;
  let gracePeriodExpiresAt: number | null = null;

  if (data.signedRenewalInfo) {
    try {
      const renewalPayload = decodeJWSPayload<JWSRenewalInfoPayload>(data.signedRenewalInfo);
      isInBillingRetry = renewalPayload.isInBillingRetryPeriod ?? false;
      gracePeriodExpiresAt = renewalPayload.gracePeriodExpiresDate
        ? Math.floor(renewalPayload.gracePeriodExpiresDate / 1000)
        : null;
    } catch {
      // Non-fatal: renewal info decode failure
    }
  }

  // ─── Map notification type to subscription status ────────────────────────
  const now = Math.floor(Date.now() / 1000);

  switch (notificationType) {
    case 'SUBSCRIBED':
    case 'DID_RENEW':
      newStatus = 'active';
      break;

    case 'GRACE_PERIOD_EXPIRED':
      newStatus = 'expired';
      break;

    case 'EXPIRED':
      if (isInBillingRetry && gracePeriodExpiresAt && gracePeriodExpiresAt > now) {
        // Within grace period — keep Premium access
        newStatus = 'grace_period';
        expiresAt = gracePeriodExpiresAt;
      } else {
        newStatus = 'expired';
      }
      break;

    case 'REFUND':
    case 'REFUND_REVERSED':
      newStatus = subtype === 'REFUND' || notificationType === 'REFUND' ? 'refunded' : 'active';
      break;

    case 'DID_CHANGE_RENEWAL_STATUS':
      // Auto-renewal turned off — subscription still active until expiry
      newStatus = resolveStatus(expiresAt, now, null);
      break;

    default:
      // Other events (price increase consent, offer redeemed, etc.) — keep current status
      if (anonymousId) {
        const current = await getSubscription(anonymousId, env.DB);
        if (current) {
          newStatus = current.status;
          newTier = current.tier;
        }
      }
  }

  // ─── Upsert subscription + log notification ──────────────────────────────
  const batch = env.DB.batch([
    ...(anonymousId
      ? [
          env.DB.prepare(
            `INSERT INTO subscriptions (anonymous_id, tier, status, expires_at, original_tx_id_hash, environment, updated_at)
             VALUES (?, ?, ?, ?, ?, ?, ?)
             ON CONFLICT(anonymous_id)
             DO UPDATE SET tier = excluded.tier, status = excluded.status,
               expires_at = excluded.expires_at, environment = excluded.environment,
               updated_at = excluded.updated_at`
          ).bind(
            anonymousId,
            newTier,
            newStatus,
            expiresAt,
            anonymousId,
            data.environment === 'Sandbox' ? 'sandbox' : 'production',
            now
          ),
        ]
      : []),
    env.DB.prepare(
      `INSERT INTO apple_notifications_log
         (notification_uuid, notification_type, subtype, anonymous_id, received_at, processed)
       VALUES (?, ?, ?, ?, ?, 1)`
    ).bind(notificationUUID, notificationType, subtype ?? null, anonymousId, now),
  ]);

  await batch;

  return Response.json({ status: 'ok', notificationType, anonymousId });
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared helpers (also used by aiProxy.ts)
// ─────────────────────────────────────────────────────────────────────────────

export async function getSubscription(
  anonymousId: string,
  db: D1Database
): Promise<SubscriptionRecord | null> {
  return db
    .prepare('SELECT * FROM subscriptions WHERE anonymous_id = ?')
    .bind(anonymousId)
    .first<SubscriptionRecord>();
}

async function upsertSubscription(sub: SubscriptionRecord & { original_tx_id_hash: string }, db: D1Database): Promise<void> {
  await db
    .prepare(
      `INSERT INTO subscriptions (anonymous_id, tier, status, expires_at, original_tx_id_hash, environment, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(anonymous_id)
       DO UPDATE SET tier = excluded.tier, status = excluded.status,
         expires_at = excluded.expires_at, environment = excluded.environment,
         updated_at = excluded.updated_at`
    )
    .bind(
      sub.anonymous_id,
      sub.tier,
      sub.status,
      sub.expires_at,
      sub.original_tx_id_hash,
      sub.environment,
      sub.updated_at
    )
    .run();
}

function productIdToTier(productId: string): SubscriptionTier {
  if (productId.includes('family')) return 'family';
  if (productId.includes('premium')) return 'premium';
  return 'free';
}

function resolveStatus(
  expiresAt: number | null,
  now: number,
  gracePeriodExpiresAt: number | null
): SubscriptionStatus {
  if (!expiresAt) return 'active';  // lifetime or free
  if (expiresAt > now) return 'active';
  if (gracePeriodExpiresAt && gracePeriodExpiresAt > now) return 'grace_period';
  return 'expired';
}
