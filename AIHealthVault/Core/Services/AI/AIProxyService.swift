import Foundation
import StoreKit
import os

private let proxyLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aihealthvault", category: "AIProxyService")

// MARK: - AI Proxy Service

/// AI Server Proxy 服务 — 通过 Cloudflare Workers 调用 Anthropic API
/// 认证方式：StoreKit 2 JWS Receipt（Bearer token）
/// 服务端负责：订阅验证、用量限流（50次/月）、API Key 管理
actor AIProxyService: AIService {

    // MARK: - Singleton

    static let shared = AIProxyService()

    // MARK: - Constants

    private enum API {
        static let proxyPath = "/api/ai/proxy"
    }

    // MARK: - State

    private let session: URLSession

    // 客户端侧令牌桶限流：额外防护
    private var requestTimestamps: [Date] = []
    private let rateLimitWindow: TimeInterval = 60
    private let maxRequestsPerWindow = 10

    // MARK: - Init

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - AIService Protocol

    nonisolated var isConfigured: Bool {
        SubscriptionManager.shared.isPremiumActive
    }

    func sendMessage(
        _ messages: [AIMessage],
        systemPrompt: String?
    ) async throws -> (content: String, usage: TokenUsage) {
        let receiptToken = try await resolvedReceiptToken()
        let proxyURL = try resolvedProxyURL()
        try checkClientRateLimit()
        recordRequest()

        let body = buildRequestBody(messages: messages, systemPrompt: systemPrompt, stream: false)
        let request = try buildURLRequest(
            url: proxyURL.appendingPathComponent(API.proxyPath),
            body: body, receiptToken: receiptToken, stream: false
        )

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)

        let decoded = try JSONDecoder().decode(ProxyResponse.self, from: data)
        guard let textBlock = decoded.content.first(where: { $0.type == "text" }) else {
            throw AIError.streamingError("代理响应中没有文本内容")
        }

        let usage = TokenUsage(
            inputTokens: decoded.usage?.inputTokens ?? 0,
            outputTokens: decoded.usage?.outputTokens ?? 0
        )
        proxyLogger.info("代理请求成功: inputTokens=\(usage.inputTokens) outputTokens=\(usage.outputTokens)")
        return (content: textBlock.text, usage: usage)
    }

    nonisolated func streamMessage(
        _ messages: [AIMessage],
        systemPrompt: String?
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let receiptToken = try await self.resolvedReceiptToken()
                    let proxyURL = try await self.resolvedProxyURL()
                    try await self.checkClientRateLimit()
                    await self.recordRequest()

                    let body = await self.buildRequestBody(messages: messages, systemPrompt: systemPrompt, stream: true)
                    let request = try await self.buildURLRequest(
                        url: proxyURL.appendingPathComponent(API.proxyPath),
                        body: body, receiptToken: receiptToken, stream: true
                    )

                    let (bytes, response) = try await self.session.bytes(for: request)
                    try self.validateHTTPResponse(response, data: nil)

                    // 解析 SSE 流（格式与 Anthropic 直连相同）
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let jsonStr = String(line.dropFirst(6))
                        guard jsonStr != "[DONE]" else { break }

                        guard let lineData = jsonStr.data(using: .utf8),
                              let event = try? JSONDecoder().decode(StreamEvent.self, from: lineData) else {
                            continue
                        }

                        if event.type == "content_block_delta",
                           let delta = event.delta,
                           delta.type == "text_delta",
                           let text = delta.text {
                            continuation.yield(text)
                        }

                        if event.type == "message_stop" { break }
                    }
                    proxyLogger.info("代理流式请求完成")
                    continuation.finish()
                } catch {
                    proxyLogger.error("代理流式请求失败: \(error.localizedDescription)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Private Helpers

    private func resolvedReceiptToken() async throws -> String {
        guard let token = await SubscriptionManager.shared.currentReceiptToken() else {
            proxyLogger.warning("无法获取 StoreKit receipt token，用户可能未订阅")
            throw AIError.notConfigured
        }
        return token
    }

    private func resolvedProxyURL() throws -> URL {
        let urlString = AISettingsManager.shared.proxyBaseURL
        guard !urlString.isEmpty, let url = URL(string: urlString) else {
            throw AIError.requestFailed(statusCode: 0, message: "无效的代理 URL: \(urlString)")
        }
        return url
    }

    private func checkClientRateLimit() throws {
        let now = Date()
        let windowStart = now.addingTimeInterval(-rateLimitWindow)
        requestTimestamps = requestTimestamps.filter { $0 > windowStart }
        if requestTimestamps.count >= maxRequestsPerWindow {
            throw AIError.rateLimited(retryAfter: Int(rateLimitWindow))
        }
    }

    private func recordRequest() {
        requestTimestamps.append(Date())
    }

    private func buildRequestBody(
        messages: [AIMessage],
        systemPrompt: String?,
        stream: Bool
    ) -> [String: Any] {
        var body: [String: Any] = [
            "tier": "standard",
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] },
            "stream": stream
        ]
        if let system = systemPrompt, !system.isEmpty {
            body["system"] = system
        }
        return body
    }

    private func buildURLRequest(
        url: URL,
        body: [String: Any],
        receiptToken: String,
        stream: Bool
    ) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(receiptToken)", forHTTPHeaderField: "Authorization")
        if stream {
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func validateHTTPResponse(_ response: URLResponse, data: Data?) throws {
        guard let http = response as? HTTPURLResponse else { return }
        proxyLogger.debug("代理响应状态码: \(http.statusCode)")
        switch http.statusCode {
        case 200...299: return
        case 401:
            throw AIError.invalidAPIKey
        case 403:
            throw AIError.notConfigured
        case 429:
            let retryAfter = (http.allHeaderFields["Retry-After"] as? String).flatMap(Int.init)
            throw AIError.rateLimited(retryAfter: retryAfter)
        case 400:
            let message = extractErrorMessage(from: data) ?? "请求参数错误"
            throw AIError.requestFailed(statusCode: 400, message: message)
        default:
            let message = extractErrorMessage(from: data) ?? "服务器错误"
            throw AIError.requestFailed(statusCode: http.statusCode, message: message)
        }
    }

    private func extractErrorMessage(from data: Data?) -> String? {
        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String else {
            return nil
        }
        return message
    }
}

// MARK: - Codable Response Types

private struct ProxyResponse: Decodable {
    let content: [ContentBlock]
    let usage: UsageBlock?

    struct ContentBlock: Decodable {
        let type: String
        let text: String
    }

    struct UsageBlock: Decodable {
        let inputTokens: Int
        let outputTokens: Int

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
        }
    }
}

private struct StreamEvent: Decodable {
    let type: String
    let delta: Delta?

    struct Delta: Decodable {
        let type: String
        let text: String?
    }
}
