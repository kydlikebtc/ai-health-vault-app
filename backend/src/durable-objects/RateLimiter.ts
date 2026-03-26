/**
 * RateLimiter Durable Object
 *
 * One instance per sha256(original_transaction_id).
 * Cloudflare routes all requests for the same key to the same singleton JS object,
 * providing strong consistency without transactions or locking.
 *
 * State stored in DO persistent storage (not D1) for:
 *   - Sub-millisecond latency on every AI request
 *   - Atomic counter increments (single-threaded per instance)
 *   - Automatic recovery across restarts (DO persistent storage survives eviction)
 */

import type { Env, RateLimitCheckRequest, RateLimitCheckResponse, RateLimitIncrementRequest } from '../lib/types.js';

interface DailyCount {
  date: string;   // 'YYYY-MM-DD'
  count: number;
}

interface MonthlyState {
  month: string;  // 'YYYY-MM'
  count: number;
}

export class RateLimiter implements DurableObject {
  private state: DurableObjectState;
  private env: Env;

  constructor(state: DurableObjectState, env: Env) {
    this.state = state;
    this.env = env;
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === 'POST' && url.pathname === '/check') {
      return this.handleCheck(request);
    }

    if (request.method === 'POST' && url.pathname === '/increment') {
      return this.handleIncrement(request);
    }

    return new Response('Not found', { status: 404 });
  }

  /**
   * Check if the user is within their monthly limit before making an AI call.
   * Called synchronously before proxying to Anthropic.
   */
  private async handleCheck(request: Request): Promise<Response> {
    const body = await request.json<RateLimitCheckRequest>();
    const { billingMonth, monthlyLimit, dailyAlertLimit } = body;

    const monthly = await this.getMonthlyState(billingMonth);
    const daily = await this.getDailyCount();

    const allowed = monthly.count < monthlyLimit;
    const alertTriggered = daily.count >= dailyAlertLimit;

    const result: RateLimitCheckResponse = {
      allowed,
      currentCount: monthly.count,
      alertTriggered,
    };

    return Response.json(result);
  }

  /**
   * Record a completed AI call — increments both daily and monthly counters,
   * and writes a usage log row to D1 asynchronously (fire-and-forget).
   */
  private async handleIncrement(request: Request): Promise<Response> {
    const body = await request.json<RateLimitIncrementRequest>();
    const { anonymousId, billingMonth, inputTokens, outputTokens, latencyMs, model, tierUsed, errorCode } = body;

    // Increment monthly counter
    const monthly = await this.getMonthlyState(billingMonth);
    monthly.count += 1;
    await this.state.storage.put(`monthly:${billingMonth}`, monthly);

    // Increment daily counter
    const daily = await this.getDailyCount();
    daily.count += 1;
    await this.state.storage.put(`daily:${daily.date}`, daily);

    // Update D1 usage_logs and monthly_usage_counts asynchronously
    // waitUntil extends the request lifetime without blocking the response
    this.state.waitUntil(
      this.writeUsageToD1({
        anonymousId,
        billingMonth,
        inputTokens,
        outputTokens,
        latencyMs,
        model,
        tierUsed,
        errorCode: errorCode ?? null,
        monthlyCount: monthly.count,
      })
    );

    return Response.json({ success: true, newCount: monthly.count });
  }

  // ─── Persistent state helpers ──────────────────────────────────────────────

  private async getMonthlyState(billingMonth: string): Promise<MonthlyState> {
    const key = `monthly:${billingMonth}`;
    const stored = await this.state.storage.get<MonthlyState>(key);
    return stored ?? { month: billingMonth, count: 0 };
  }

  private async getDailyCount(): Promise<DailyCount> {
    const today = new Date().toISOString().slice(0, 10); // 'YYYY-MM-DD'
    const key = `daily:${today}`;
    const stored = await this.state.storage.get<DailyCount>(key);
    return stored ?? { date: today, count: 0 };
  }

  // ─── D1 write (async, non-blocking) ───────────────────────────────────────

  private async writeUsageToD1(params: {
    anonymousId: string;
    billingMonth: string;
    inputTokens: number;
    outputTokens: number;
    latencyMs: number;
    model: string;
    tierUsed: string;
    errorCode: string | null;
    monthlyCount: number;
  }): Promise<void> {
    const now = Math.floor(Date.now() / 1000);

    // Insert usage log row
    await this.env.DB.prepare(
      `INSERT INTO usage_logs
        (anonymous_id, ts, model, tier_used, input_tokens, output_tokens, latency_ms, error_code, billing_month)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`
    )
      .bind(
        params.anonymousId,
        now,
        params.model,
        params.tierUsed,
        params.inputTokens,
        params.outputTokens,
        params.latencyMs,
        params.errorCode,
        params.billingMonth
      )
      .run();

    // Upsert monthly_usage_counts for fast metering queries
    await this.env.DB.prepare(
      `INSERT INTO monthly_usage_counts (anonymous_id, billing_month, call_count, last_updated)
       VALUES (?, ?, ?, ?)
       ON CONFLICT(anonymous_id, billing_month)
       DO UPDATE SET call_count = excluded.call_count, last_updated = excluded.last_updated`
    )
      .bind(params.anonymousId, params.billingMonth, params.monthlyCount, now)
      .run();
  }
}
