-- AI Health Vault D1 Database Schema
-- Migration: 0001_initial_schema
-- IMPORTANT: No PHI (Protected Health Information) is stored here.
-- All records use anonymous_id derived from sha256(original_transaction_id).

-- ─────────────────────────────────────────────────
-- Table: subscriptions
-- Stores subscription status verified from Apple StoreKit 2.
-- Keyed by anonymous_id to avoid linking health data to identity.
-- ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS subscriptions (
  anonymous_id       TEXT NOT NULL PRIMARY KEY,  -- sha256(original_transaction_id)
  tier               TEXT NOT NULL DEFAULT 'free', -- 'free' | 'premium' | 'family'
  status             TEXT NOT NULL DEFAULT 'active', -- 'active' | 'expired' | 'grace_period' | 'refunded'
  expires_at         INTEGER,  -- Unix timestamp (seconds), NULL for free tier
  original_tx_id_hash TEXT NOT NULL,  -- same as anonymous_id, kept for clarity
  environment        TEXT NOT NULL DEFAULT 'production', -- 'sandbox' | 'production'
  updated_at         INTEGER NOT NULL DEFAULT (unixepoch())
);

CREATE INDEX IF NOT EXISTS idx_subscriptions_expires_at ON subscriptions(expires_at);

-- ─────────────────────────────────────────────────
-- Table: usage_logs
-- Per-request AI usage records for metering and billing.
-- Strictly no PHI: no message content, no user identifiers beyond anonymous_id.
-- ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS usage_logs (
  id                 INTEGER PRIMARY KEY AUTOINCREMENT,
  anonymous_id       TEXT NOT NULL,        -- sha256(original_transaction_id)
  ts                 INTEGER NOT NULL,     -- Unix timestamp (seconds)
  model              TEXT NOT NULL,        -- e.g. 'claude-haiku-4-5-20251001'
  tier_used          TEXT NOT NULL,        -- 'standard' | 'detailed'
  input_tokens       INTEGER NOT NULL DEFAULT 0,
  output_tokens      INTEGER NOT NULL DEFAULT 0,
  latency_ms         INTEGER NOT NULL DEFAULT 0,
  error_code         TEXT,                 -- NULL on success, e.g. 'upstream_error'
  billing_month      TEXT NOT NULL         -- 'YYYY-MM' for monthly reset partitioning
);

CREATE INDEX IF NOT EXISTS idx_usage_logs_anon_month ON usage_logs(anonymous_id, billing_month);
CREATE INDEX IF NOT EXISTS idx_usage_logs_ts ON usage_logs(ts);

-- ─────────────────────────────────────────────────
-- Table: monthly_usage_counts
-- Aggregated call counts per user per month.
-- Updated atomically by the rate limiter Durable Object.
-- ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS monthly_usage_counts (
  anonymous_id       TEXT NOT NULL,
  billing_month      TEXT NOT NULL,        -- 'YYYY-MM'
  call_count         INTEGER NOT NULL DEFAULT 0,
  last_updated       INTEGER NOT NULL DEFAULT (unixepoch()),
  PRIMARY KEY (anonymous_id, billing_month)
);

-- ─────────────────────────────────────────────────
-- Table: apple_notifications_log
-- Audit log for Apple Server-to-Server notifications.
-- Helps detect duplicate delivery and debug webhook issues.
-- ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS apple_notifications_log (
  notification_uuid  TEXT NOT NULL PRIMARY KEY,  -- Apple's notificationUUID
  notification_type  TEXT NOT NULL,  -- DID_RENEW | EXPIRED | REFUND | GRACE_PERIOD_EXPIRED | etc.
  subtype            TEXT,
  anonymous_id       TEXT,           -- sha256(original_transaction_id) if available
  received_at        INTEGER NOT NULL DEFAULT (unixepoch()),
  processed          INTEGER NOT NULL DEFAULT 1  -- 1 = success, 0 = failed
);

CREATE INDEX IF NOT EXISTS idx_apple_notif_anon ON apple_notifications_log(anonymous_id);
