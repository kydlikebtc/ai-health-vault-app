# AI Health Vault Backend — 部署文档

Cloudflare Workers AI Proxy + StoreKit 服务端验证后端部署指南。

## 前置条件

- Cloudflare 账号（Workers Paid 套餐，月 $5 起）
- Node.js 20+，npm 10+
- Wrangler CLI：`npm install -g wrangler`
- Anthropic API Key（已有）
- Apple Developer 账号（已配置 StoreKit 2）

## 1. 初始化项目

```bash
cd backend
npm install
npx wrangler login
```

## 2. 创建 D1 数据库

```bash
# 创建 D1 数据库
npx wrangler d1 create ai-health-vault-db

# 输出示例：
# database_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

将输出的 `database_id` 填入 `wrangler.toml`：

```toml
[[d1_databases]]
binding = "DB"
database_name = "ai-health-vault-db"
database_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"  # ← 填这里
```

## 3. 运行数据库迁移

```bash
# 本地开发环境
npm run db:migrate

# 生产环境
npm run db:migrate:remote
```

## 4. 配置 Cloudflare Secrets

```bash
# Anthropic API Key（必须）
npx wrangler secret put ANTHROPIC_API_KEY
# 输入: sk-ant-xxxxxxxxxx

# Apple Bundle ID（必须）
npx wrangler secret put APPLE_BUNDLE_ID
# 输入: com.yourcompany.aihealthvault

# Apple Root CA G3 PEM（必须）
# 从 https://www.apple.com/certificateauthority/ 下载 "Apple Root CA - G3 Root"
# 转换为 PEM 后粘贴
npx wrangler secret put APPLE_ROOT_CERT_PEM
```

### 获取 Apple Root CA G3 PEM

```bash
# 下载 Apple Root CA G3 DER
curl -o AppleRootCAG3.cer https://www.apple.com/appleca/AppleRootCAG3.cer

# 转换为 PEM
openssl x509 -in AppleRootCAG3.cer -inform DER -out AppleRootCAG3.pem -outform PEM

# 查看内容（复制粘贴到 wrangler secret put）
cat AppleRootCAG3.pem
```

## 5. 配置 Apple StoreKit Server Notifications

在 App Store Connect 中配置 Server Notifications URL：

1. App Store Connect → 你的 App → App 信息 → App Store Server Notifications
2. 设置 Production URL：`https://ai-health-vault-backend.<your-account>.workers.dev/api/storekit/apple-webhook`
3. 设置 Sandbox URL（同上，用于测试）
4. 选择版本：**Version 2**（JWS 格式，本项目使用）

## 6. 本地开发

```bash
npm run dev
# Worker 运行于 http://localhost:8787
```

开发模式下 `ENVIRONMENT=development`，AI Proxy 不强制要求 receiptToken（方便本地测试）。

测试 AI Proxy：

```bash
curl -X POST http://localhost:8787/api/ai/proxy \
  -H "Content-Type: application/json" \
  -d '{
    "tier": "standard",
    "messages": [{"role": "user", "content": "解释一下白细胞计数偏高是什么意思？"}]
  }'
```

## 7. 部署到生产

```bash
npm run deploy

# 输出:
# https://ai-health-vault-backend.<your-account>.workers.dev
```

## 8. iOS 客户端集成

在 iOS 端修改 `ClaudeService`，将 API 调用指向 Workers：

```swift
// 生产环境
static let proxyBaseURL = "https://ai-health-vault-backend.<your-account>.workers.dev"

// 调用示例
let response = try await URLSession.shared.data(from: "\(proxyBaseURL)/api/ai/proxy") {
    request.httpBody = try JSONEncoder().encode(AIProxyRequest(
        tier: .standard,
        messages: messages,
        receiptToken: currentReceiptToken  // 从 StoreKit 2 获取
    ))
}
```

## API 参考

### POST /api/ai/proxy

AI 代理端点，SSE 流式响应。

**请求体：**
```json
{
  "tier": "standard",      // "standard" | "detailed"
  "messages": [
    {"role": "user", "content": "..."}
  ],
  "receiptToken": "..."    // StoreKit 2 JWS token（生产环境必须）
}
```

**响应：** `text/event-stream`，Anthropic SDK 标准 SSE 格式

**错误码：**
- `401 invalid_receipt` — StoreKit token 无效或已过期
- `403 subscription_required` — 无活跃 Premium 订阅
- `429 rate_limit_exceeded` — 已达本月调用上限

### POST /api/storekit/verify

客户端上传 StoreKit receipt，服务端写入订阅状态。购买/恢复购买后调用。

### POST /api/storekit/apple-webhook

Apple Server-to-Server Notification webhook，处理：
- `DID_RENEW` — 续订成功
- `EXPIRED` — 订阅到期
- `REFUND` — 退款
- `GRACE_PERIOD_EXPIRED` — 宽限期结束

### GET /api/usage/me?receiptToken=<JWS>

返回当月 AI 调用统计：

```json
{
  "anonymousId": "sha256hex...",
  "billingMonth": "2026-03",
  "callCount": 12,
  "monthlyLimit": 50,
  "remaining": 38
}
```

## 监控与告警

Cloudflare Workers 提供内置监控。以下情况需关注：

| 场景 | 处理 |
|------|------|
| 单用户单日 > 15 次 | `alertTriggered=true`（当前仅记录，可接 Workers Analytics） |
| 全局错误率 > 2% | Cloudflare Workers 仪表盘 → Errors 面板 |
| 月 AI 成本 > 120% 预算 | Anthropic Console → Usage 页面设置告警 |

## API Key 轮换

零停机轮换步骤：

```bash
# 1. 在 Anthropic Console 生成新 Key
# 2. 更新 Cloudflare Secret（自动部署，零停机）
npx wrangler secret put ANTHROPIC_API_KEY
# 输入新 Key
# 3. 验证新 Key 生效后，在 Anthropic Console 吊销旧 Key
```

## 数据隐私说明

- **服务端不存储任何 PHI**：AI 请求内容处理后立即丢弃
- **anonymous_id**：`sha256(original_transaction_id)`，无法反推用户身份
- **D1 日志字段**：仅含 `ts, anonymous_id, model, tokens, latency_ms, error_code`
- **Apple 通知**：仅存 `notificationUUID` 和 `notificationType`，不存交易详情
