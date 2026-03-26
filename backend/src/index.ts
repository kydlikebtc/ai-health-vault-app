/**
 * AI Health Vault — Cloudflare Workers Main Entry Point
 *
 * Routes:
 *   POST   /api/ai/proxy                 — AI Proxy (SSE streaming)
 *   OPTIONS /api/ai/proxy                — CORS preflight
 *   POST   /api/storekit/verify          — StoreKit receipt verification
 *   POST   /api/storekit/apple-webhook   — Apple Server Notifications v2
 *   GET    /api/usage/me                 — Usage stats for current user
 *   GET    /health                       — Health check (no auth)
 *
 * Security model:
 *   - All AI and usage endpoints require a valid StoreKit JWS token
 *   - Apple webhook endpoint validates JWS signature from Apple's own cert chain
 *   - No user accounts, no stored credentials, no PHI on server
 */

import type { Env } from './lib/types.js';
import { handleAIProxy, handleAIProxyCORS } from './handlers/aiProxy.js';
import { handleStorekitVerify, handleAppleWebhook } from './handlers/storekit.js';
import { handleUsageMe } from './handlers/usage.js';

// Re-export Durable Object class — Cloudflare requires this from the entry point
export { RateLimiter } from './durable-objects/RateLimiter.js';

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);
    const { pathname } = url;

    // ─── Health check (no auth) ───────────────────────────────────────────
    if (pathname === '/health' && request.method === 'GET') {
      return Response.json({
        status: 'ok',
        version: '1.0.0',
        environment: env.ENVIRONMENT,
        timestamp: new Date().toISOString(),
      });
    }

    // ─── CORS preflight ───────────────────────────────────────────────────
    if (request.method === 'OPTIONS') {
      if (pathname === '/api/ai/proxy') {
        return handleAIProxyCORS();
      }
      return new Response(null, { status: 204 });
    }

    // ─── API routes ───────────────────────────────────────────────────────
    try {
      if (pathname === '/api/ai/proxy') {
        return await handleAIProxy(request, env);
      }

      if (pathname === '/api/storekit/verify') {
        return await handleStorekitVerify(request, env);
      }

      if (pathname === '/api/storekit/apple-webhook') {
        return await handleAppleWebhook(request, env);
      }

      if (pathname === '/api/usage/me') {
        return await handleUsageMe(request, env);
      }

      return new Response(
        JSON.stringify({ error: 'Not found', code: 'not_found' }),
        { status: 404, headers: { 'Content-Type': 'application/json' } }
      );
    } catch (err) {
      // Last-resort error handler — do NOT log request content (PHI risk)
      const message = err instanceof Error ? err.message : 'Internal server error';
      console.error('[Worker] Unhandled error:', message);

      return new Response(
        JSON.stringify({ error: 'Internal server error', code: 'internal_error' }),
        { status: 500, headers: { 'Content-Type': 'application/json' } }
      );
    }
  },
} satisfies ExportedHandler<Env>;
