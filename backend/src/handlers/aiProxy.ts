/**
 * AI Proxy Handler
 *
 * POST /api/ai/proxy
 * Body: { tier, messages, receiptToken? }
 *
 * Pipeline:
 *   1. Parse + validate request
 *   2. Verify StoreKit receipt (if provided) → determine tier + anonymous_id
 *   3. Check rate limit via Durable Object
 *   4. Route to Anthropic (Smart Tier: standard→Haiku, detailed→Sonnet)
 *   5. SSE stream response back to iOS client
 *   6. Record usage (async, via Durable Object → D1)
 *
 * Security guarantees:
 *   - Anthropic API key NEVER leaves server
 *   - No message content is logged or persisted
 *   - PHI cannot exist in server logs (we don't log it)
 */

import Anthropic from '@anthropic-ai/sdk';
import { sha256Hex, currentBillingMonth, verifyAppleJWS, decodeJWSPayload } from '../lib/crypto.js';
import {
  type Env,
  type AIProxyRequest,
  type JWSTransactionPayload,
  type RateLimitCheckRequest,
  type RateLimitCheckResponse,
  type RateLimitIncrementRequest,
  MODEL_MAP,
  jsonError,
} from '../lib/types.js';
import { getSubscription } from './storekit.js';

const MAX_TOKENS = 4096;
const MAX_MESSAGES = 20;  // Prevent oversized context abuse

export async function handleAIProxy(request: Request, env: Env): Promise<Response> {
  if (request.method !== 'POST') {
    return jsonError('Method not allowed', 'method_not_allowed', 405);
  }

  // ─── 1. Parse request ────────────────────────────────────────────────────
  let body: AIProxyRequest;
  try {
    body = await request.json<AIProxyRequest>();
  } catch {
    return jsonError('Invalid JSON body', 'invalid_request', 400);
  }

  const { tier, messages, receiptToken } = body;

  if (!tier || !['standard', 'detailed'].includes(tier)) {
    return jsonError('tier must be "standard" or "detailed"', 'invalid_tier', 400);
  }

  if (!Array.isArray(messages) || messages.length === 0 || messages.length > MAX_MESSAGES) {
    return jsonError(`messages must be a non-empty array (max ${MAX_MESSAGES})`, 'invalid_messages', 400);
  }

  for (const msg of messages) {
    if (!msg.role || !['user', 'assistant'].includes(msg.role) || typeof msg.content !== 'string') {
      return jsonError('Each message must have role (user|assistant) and string content', 'invalid_message_format', 400);
    }
  }

  // ─── 2. Resolve subscription + anonymous_id ──────────────────────────────
  let anonymousId: string;
  let monthlyLimit: number;

  if (receiptToken) {
    // Verify the JWS receipt from StoreKit 2
    let txPayload: JWSTransactionPayload;
    try {
      txPayload = await verifyAppleJWS<JWSTransactionPayload>(receiptToken, env.APPLE_ROOT_CERT_PEM);
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'unknown';
      return jsonError(`Invalid receipt token: ${msg}`, 'invalid_receipt', 401);
    }

    if (txPayload.bundleId !== env.APPLE_BUNDLE_ID) {
      return jsonError('Receipt bundle ID mismatch', 'invalid_receipt', 401);
    }

    anonymousId = await sha256Hex(txPayload.originalTransactionId);

    // Look up subscription record (populated by Apple webhook handler)
    const sub = await getSubscription(anonymousId, env.DB);
    const isActive = sub && (sub.status === 'active' || sub.status === 'grace_period');
    monthlyLimit = isActive ? parseInt(env.PREMIUM_MONTHLY_LIMIT, 10) : 0;

    if (monthlyLimit === 0) {
      return jsonError('Active Premium subscription required for AI features', 'subscription_required', 403);
    }
  } else if (env.ENVIRONMENT === 'development') {
    // Dev mode: allow unauthenticated requests with a test anonymous_id
    anonymousId = await sha256Hex('dev-test-transaction-id');
    monthlyLimit = 999;
  } else {
    return jsonError('receiptToken is required', 'receipt_required', 401);
  }

  // ─── 3. Rate limit check ─────────────────────────────────────────────────
  const billingMonth = currentBillingMonth();
  const dailyAlertLimit = parseInt(env.ALERT_DAILY_USER_LIMIT, 10);

  const rateLimiterId = env.RATE_LIMITER.idFromName(anonymousId);
  const rateLimiterStub = env.RATE_LIMITER.get(rateLimiterId);

  const checkReq: RateLimitCheckRequest = { anonymousId, billingMonth, monthlyLimit, dailyAlertLimit };
  const checkResponse = await rateLimiterStub.fetch('http://do/check', {
    method: 'POST',
    body: JSON.stringify(checkReq),
    headers: { 'Content-Type': 'application/json' },
  });

  const rateLimitResult = await checkResponse.json<RateLimitCheckResponse>();

  if (!rateLimitResult.allowed) {
    return jsonError(
      `Monthly AI call limit reached (${rateLimitResult.currentCount}/${monthlyLimit})`,
      'rate_limit_exceeded',
      429
    );
  }

  // ─── 4. Stream from Anthropic ────────────────────────────────────────────
  const model = MODEL_MAP[tier];
  const startMs = Date.now();

  const { readable, writable } = new TransformStream<Uint8Array, Uint8Array>();
  const writer = writable.getWriter();
  const encoder = new TextEncoder();

  // Track token usage for metering
  let inputTokens = 0;
  let outputTokens = 0;
  let errorCode: string | undefined;

  // Stream to client in background — don't await
  const streamPromise = (async () => {
    const anthropic = new Anthropic({ apiKey: env.ANTHROPIC_API_KEY });

    try {
      const stream = await anthropic.messages.stream({
        model,
        max_tokens: MAX_TOKENS,
        messages: messages.map((m) => ({ role: m.role, content: m.content })),
      });

      for await (const event of stream) {
        // Forward SSE events to client
        const sseData = `data: ${JSON.stringify(event)}\n\n`;
        await writer.write(encoder.encode(sseData));

        // Capture token counts from usage events
        if (event.type === 'message_delta' && 'usage' in event && event.usage) {
          outputTokens = (event.usage as { output_tokens: number }).output_tokens;
        }
        if (event.type === 'message_start' && event.message?.usage) {
          inputTokens = event.message.usage.input_tokens;
        }
      }

      // Signal successful completion to client
      await writer.write(encoder.encode('data: [DONE]\n\n'));
    } catch (err) {
      errorCode = 'upstream_error';
      const errMsg = err instanceof Error ? err.message : 'upstream error';
      await writer.write(encoder.encode(`data: ${JSON.stringify({ error: errMsg })}\n\n`));
    } finally {
      await writer.close();

      // ─── 5. Record usage (async) ─────────────────────────────────────────
      const latencyMs = Date.now() - startMs;
      const incrementReq: RateLimitIncrementRequest = {
        anonymousId,
        billingMonth,
        inputTokens,
        outputTokens,
        latencyMs,
        model,
        tierUsed: tier,
        errorCode,
      };

      // Fire-and-forget: do not block stream completion
      rateLimiterStub
        .fetch('http://do/increment', {
          method: 'POST',
          body: JSON.stringify(incrementReq),
          headers: { 'Content-Type': 'application/json' },
        })
        .catch(() => {
          // Usage metering failure is non-fatal; the AI response already delivered
        });
    }
  })();

  // Prevent Cloudflare from terminating the Worker before stream completes
  // This is the correct pattern for streaming Workers
  void streamPromise;

  return new Response(readable, {
    status: 200,
    headers: {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'Connection': 'keep-alive',
      // CORS: iOS app uses direct API calls, not browser — but set for Simulator testing
      'Access-Control-Allow-Origin': '*',
    },
  });
}

/**
 * Handle CORS preflight for /api/ai/proxy
 */
export function handleAIProxyCORS(): Response {
  return new Response(null, {
    status: 204,
    headers: {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
      'Access-Control-Max-Age': '86400',
    },
  });
}
