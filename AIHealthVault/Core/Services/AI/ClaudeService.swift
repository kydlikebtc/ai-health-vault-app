import Foundation

/// Claude API 服务实现 — 通过 REST API 调用 Anthropic Claude
/// 遵循 Swift 6 strict concurrency，所有状态变更通过 actor 隔离
actor ClaudeService: AIService {

    // MARK: - Constants

    private enum API {
        static let baseURL = "https://api.anthropic.com/v1"
        static let messagesEndpoint = "/messages"
        static let model = "claude-sonnet-4-6"
        static let maxTokens = 4096
        static let anthropicVersion = "2023-06-01"
    }

    // MARK: - State

    private let keychain = KeychainService.shared
    private let session: URLSession

    // 令牌桶限流：每分钟最多 60 次请求
    private var requestTimestamps: [Date] = []
    private let rateLimitWindow: TimeInterval = 60
    private let maxRequestsPerWindow = 60

    // MARK: - Init

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - AIService Protocol

    nonisolated var isConfigured: Bool {
        KeychainService.shared.exists(.claudeAPIKey)
    }

    func sendMessage(
        _ messages: [AIMessage],
        systemPrompt: String?
    ) async throws -> (content: String, usage: TokenUsage) {
        let apiKey = try resolvedAPIKey()
        try checkRateLimit()
        recordRequest()

        let body = buildRequestBody(messages: messages, systemPrompt: systemPrompt, stream: false)
        let request = try buildURLRequest(body: body, apiKey: apiKey, stream: false)

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)

        let decoded = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        guard let textBlock = decoded.content.first(where: { $0.type == "text" }) else {
            throw AIError.streamingError("响应中没有文本内容")
        }

        let usage = TokenUsage(
            inputTokens: decoded.usage.inputTokens,
            outputTokens: decoded.usage.outputTokens
        )
        return (content: textBlock.text, usage: usage)
    }

    nonisolated func streamMessage(
        _ messages: [AIMessage],
        systemPrompt: String?
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let apiKey = try await self.resolvedAPIKey()
                    try await self.checkRateLimit()
                    await self.recordRequest()

                    let body = await self.buildRequestBody(messages: messages, systemPrompt: systemPrompt, stream: true)
                    let request = try await self.buildURLRequest(body: body, apiKey: apiKey, stream: true)

                    let (bytes, response) = try await self.session.bytes(for: request)
                    try self.validateHTTPResponse(response, data: nil)

                    // 解析 SSE 流：每行格式为 "data: {...}" 或 "data: [DONE]"
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

                        if event.type == "message_stop" {
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Private Helpers

    private func resolvedAPIKey() throws -> String {
        guard let key = keychain.load(.claudeAPIKey), !key.isEmpty else {
            throw AIError.notConfigured
        }
        return key
    }

    private func checkRateLimit() throws {
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
            "model": API.model,
            "max_tokens": API.maxTokens,
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] },
            "stream": stream
        ]
        if let system = systemPrompt, !system.isEmpty {
            body["system"] = system
        }
        return body
    }

    private func buildURLRequest(
        body: [String: Any],
        apiKey: String,
        stream: Bool
    ) throws -> URLRequest {
        guard let url = URL(string: API.baseURL + API.messagesEndpoint) else {
            throw AIError.requestFailed(statusCode: 0, message: "无效的 API URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(API.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        if stream {
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func validateHTTPResponse(_ response: URLResponse, data: Data?) throws {
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200...299: return
        case 401:
            throw AIError.invalidAPIKey
        case 429:
            let retryAfter = (http.allHeaderFields["Retry-After"] as? String).flatMap(Int.init)
            throw AIError.rateLimited(retryAfter: retryAfter)
        case 400:
            let message = extractErrorMessage(from: data) ?? "请求参数错误"
            if message.contains("too long") || message.contains("context") {
                throw AIError.contextTooLong
            }
            throw AIError.requestFailed(statusCode: 400, message: message)
        default:
            let message = extractErrorMessage(from: data) ?? "未知错误"
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

private struct ClaudeResponse: Decodable {
    let content: [ContentBlock]
    let usage: UsageBlock

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
