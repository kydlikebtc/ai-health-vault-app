// ─────────────────────────────────────────────────
// Cloudflare Workers Environment Bindings
// ─────────────────────────────────────────────────

export interface Env {
  // D1 Database
  DB: D1Database;

  // Durable Object — one instance per sha256(original_transaction_id)
  RATE_LIMITER: DurableObjectNamespace;

  // Secrets (set via `wrangler secret put`)
  ANTHROPIC_API_KEY: string;
  APPLE_BUNDLE_ID: string;
  APPLE_ROOT_CERT_PEM: string;  // Apple Root CA G3 PEM for JWS verification

  // Vars
  ENVIRONMENT: string;
  PREMIUM_MONTHLY_LIMIT: string;
  FREE_MONTHLY_LIMIT: string;
  ALERT_DAILY_USER_LIMIT: string;
}

// ─────────────────────────────────────────────────
// AI Proxy
// ─────────────────────────────────────────────────

export type AITier = 'standard' | 'detailed';

export interface AIProxyRequest {
  tier: AITier;
  messages: AIMessage[];
  /** StoreKit 2 JWS token — required for Premium access */
  receiptToken?: string;
}

export interface AIMessage {
  role: 'user' | 'assistant';
  content: string;
}

// Smart Tier → Model mapping
export const MODEL_MAP: Record<AITier, string> = {
  standard: 'claude-haiku-4-5-20251001',
  detailed: 'claude-sonnet-4-6',
};

// ─────────────────────────────────────────────────
// Subscription
// ─────────────────────────────────────────────────

export type SubscriptionTier = 'free' | 'premium' | 'family';
export type SubscriptionStatus = 'active' | 'expired' | 'grace_period' | 'refunded';

export interface SubscriptionRecord {
  anonymous_id: string;
  tier: SubscriptionTier;
  status: SubscriptionStatus;
  expires_at: number | null;
  environment: 'sandbox' | 'production';
  updated_at: number;
}

// ─────────────────────────────────────────────────
// Rate Limiter Durable Object messages
// ─────────────────────────────────────────────────

export interface RateLimitCheckRequest {
  anonymousId: string;
  billingMonth: string;   // 'YYYY-MM'
  monthlyLimit: number;
  dailyAlertLimit: number;
}

export interface RateLimitCheckResponse {
  allowed: boolean;
  currentCount: number;
  /** True if single-day usage exceeded alert threshold */
  alertTriggered: boolean;
}

export interface RateLimitIncrementRequest {
  anonymousId: string;
  billingMonth: string;
  inputTokens: number;
  outputTokens: number;
  latencyMs: number;
  model: string;
  tierUsed: AITier;
  errorCode?: string;
}

// ─────────────────────────────────────────────────
// Apple StoreKit 2 JWS structures
// ─────────────────────────────────────────────────

export interface JWSTransactionPayload {
  transactionId: string;
  originalTransactionId: string;
  bundleId: string;
  productId: string;
  purchaseDate: number;
  originalPurchaseDate: number;
  expiresDate?: number;
  type: 'Auto-Renewable Subscription' | 'Non-Consumable' | 'Consumable';
  environment: 'Sandbox' | 'Production';
  inAppOwnershipType: 'PURCHASED' | 'FAMILY_SHARED';
  subscriptionGroupIdentifier?: string;
}

export interface JWSRenewalInfoPayload {
  originalTransactionId: string;
  autoRenewStatus: number;  // 1 = will renew, 0 = won't
  renewalDate?: number;
  expirationIntent?: number;  // 1=cancelled, 2=billing error, 3=price increase, 4=unavailable
  isInBillingRetryPeriod?: boolean;
  gracePeriodExpiresDate?: number;
}

// Apple Server Notification (v2)
export type AppleNotificationType =
  | 'DID_RENEW'
  | 'EXPIRED'
  | 'REFUND'
  | 'GRACE_PERIOD_EXPIRED'
  | 'DID_CHANGE_RENEWAL_STATUS'
  | 'SUBSCRIBED'
  | 'DID_CHANGE_RENEWAL_PREF'
  | 'OFFER_REDEEMED'
  | 'PRICE_INCREASE'
  | 'REFUND_REVERSED';

export interface AppleNotificationPayload {
  notificationType: AppleNotificationType;
  subtype?: string;
  notificationUUID: string;
  version: string;
  signedDate: number;
  data: {
    appAppleId: number;
    bundleId: string;
    bundleVersion: string;
    environment: 'Sandbox' | 'Production';
    signedTransactionInfo?: string;   // JWS
    signedRenewalInfo?: string;        // JWS
  };
}

// ─────────────────────────────────────────────────
// Usage Metering
// ─────────────────────────────────────────────────

export interface UsageStats {
  anonymousId: string;
  billingMonth: string;
  callCount: number;
  monthlyLimit: number;
  remaining: number;
}

// ─────────────────────────────────────────────────
// API Error response
// ─────────────────────────────────────────────────

export interface APIError {
  error: string;
  code: string;
}

export function jsonError(message: string, code: string, status: number): Response {
  const body: APIError = { error: message, code };
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}
