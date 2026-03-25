import Foundation

// MARK: - Message Types

struct AIMessage: Sendable, Codable {
    enum Role: String, Sendable, Codable {
        case user
        case assistant
    }

    let role: Role
    let content: String

    init(role: Role, content: String) {
        self.role = role
        self.content = content
    }
}

// MARK: - Token Usage

struct TokenUsage: Sendable, Codable {
    let inputTokens: Int
    let outputTokens: Int

    var total: Int { inputTokens + outputTokens }
}

// MARK: - AI Errors

enum AIError: LocalizedError, Sendable {
    case notConfigured
    case invalidAPIKey
    case rateLimited(retryAfter: Int?)
    case networkUnavailable
    case requestFailed(statusCode: Int, message: String)
    case streamingError(String)
    case contextTooLong

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "AI 功能未配置，请在设置中输入 API Key"
        case .invalidAPIKey:
            return "API Key 无效，请检查后重试"
        case .rateLimited(let retryAfter):
            if let seconds = retryAfter {
                return "请求过于频繁，请 \(seconds) 秒后重试"
            }
            return "请求过于频繁，请稍后重试"
        case .networkUnavailable:
            return "网络不可用，请检查网络连接后重试"
        case .requestFailed(let code, let message):
            return "请求失败（\(code)）：\(message)"
        case .streamingError(let detail):
            return "流式响应出错：\(detail)"
        case .contextTooLong:
            return "内容过长，请减少输入后重试"
        }
    }
}

// MARK: - AI Service Protocol

/// AI 服务协议 — 所有实现（真实 / Mock）必须遵循此协议
/// 遵循 Swift 6 strict concurrency：Sendable + async/await
protocol AIService: AnyObject, Sendable {
    /// 判断服务是否已配置（API Key 已设置）
    var isConfigured: Bool { get }

    /// 发送消息并等待完整响应
    /// - Parameters:
    ///   - messages: 对话历史
    ///   - systemPrompt: 系统提示词（可选）
    /// - Returns: 模型回复文本 + Token 用量
    func sendMessage(
        _ messages: [AIMessage],
        systemPrompt: String?
    ) async throws -> (content: String, usage: TokenUsage)

    /// 发送消息并以流式方式接收响应（逐 token 返回）
    /// - Parameters:
    ///   - messages: 对话历史
    ///   - systemPrompt: 系统提示词（可选）
    /// - Returns: 异步字符串流
    func streamMessage(
        _ messages: [AIMessage],
        systemPrompt: String?
    ) -> AsyncThrowingStream<String, Error>
}
