/**
 * Usage Metering API
 *
 * GET /api/usage/me?receiptToken=<JWS>
 *   Returns current month usage stats for the authenticated user.
 *   Used by iOS app to show "X of 50 AI calls used this month".
 *
 * No PHI is returned — only anonymous aggregated counts.
 */

import { verifyAppleJWS, sha256Hex, currentBillingMonth } from '../lib/crypto.js';
import { type Env, type JWSTransactionPayload, type UsageStats, jsonError } from '../lib/types.js';

export async function handleUsageMe(request: Request, env: Env): Promise<Response> {
  if (request.method !== 'GET') {
    return jsonError('Method not allowed', 'method_not_allowed', 405);
  }

  const url = new URL(request.url);
  const receiptToken = url.searchParams.get('receiptToken');

  if (!receiptToken) {
    return jsonError('receiptToken query parameter is required', 'invalid_request', 400);
  }

  let txPayload: JWSTransactionPayload;
  try {
    txPayload = await verifyAppleJWS<JWSTransactionPayload>(receiptToken, env.APPLE_ROOT_CERT_PEM);
  } catch (err) {
    const msg = err instanceof Error ? err.message : 'unknown';
    return jsonError(`Invalid receipt: ${msg}`, 'invalid_receipt', 401);
  }

  if (txPayload.bundleId !== env.APPLE_BUNDLE_ID) {
    return jsonError('Bundle ID mismatch', 'invalid_receipt', 401);
  }

  const anonymousId = await sha256Hex(txPayload.originalTransactionId);
  const billingMonth = currentBillingMonth();

  // Query monthly usage count from D1
  const row = await env.DB.prepare(
    'SELECT call_count FROM monthly_usage_counts WHERE anonymous_id = ? AND billing_month = ?'
  )
    .bind(anonymousId, billingMonth)
    .first<{ call_count: number }>();

  const callCount = row?.call_count ?? 0;
  const monthlyLimit = parseInt(env.PREMIUM_MONTHLY_LIMIT, 10);

  const stats: UsageStats = {
    anonymousId,
    billingMonth,
    callCount,
    monthlyLimit,
    remaining: Math.max(0, monthlyLimit - callCount),
  };

  return Response.json(stats, {
    headers: {
      // Short cache — iOS refreshes this on app launch, not per-request
      'Cache-Control': 'private, max-age=60',
    },
  });
}
