import Foundation

// MARK: - Response Models

/// AI Proxy 月度用量统计（来自 GET /api/usage/me）
struct AIProxyUsageStats: Decodable, Sendable {
    let anonymousId: String
    let billingMonth: String
    let callCount: Int
    let monthlyLimit: Int
    let remaining: Int

    /// 是否已达到或超出本月限额
    var isOverLimit: Bool { remaining <= 0 }
}

// MARK: - Errors

/// AI Proxy 访问错误
enum AIProxyError: LocalizedError, Equatable, Sendable {
    /// 403: 无有效订阅（Free 用户或无 receiptToken）
    case subscriptionRequired
    /// remaining=0 时：已超出本月配额（current, limit）
    case rateLimitExceeded(Int, Int)
    /// 401: StoreKit JWS receipt 无效
    case invalidReceipt
    /// 5xx: 服务器错误
    case serverError(Int)
    /// 网络层错误
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .subscriptionRequired:
            return "需要有效订阅才能使用 AI 功能"
        case .rateLimitExceeded(let current, let limit):
            return "本月 AI 调用次数已达上限（\(current)/\(limit)）"
        case .invalidReceipt:
            return "订阅凭证无效，请重新登录"
        case .serverError(let code):
            return "服务器错误（\(code)），请稍后重试"
        case .networkError(let msg):
            return "网络错误：\(msg)"
        }
    }
}

// MARK: - Protocol

/// AI Proxy 用量服务协议（可注入测试 session）
protocol AIProxyUsageServiceProtocol: Sendable {
    /// 查询当月用量统计（需有效 receiptToken）
    func fetchUsageStats(receiptToken: String) async throws -> AIProxyUsageStats
    /// 检查 Proxy 访问权限：无 token → subscriptionRequired；超限 → rateLimitExceeded
    func checkProxyAccess(receiptToken: String?) async -> Result<AIProxyUsageStats, AIProxyError>
}

// MARK: - Implementation

/// AI Proxy 用量服务 — 封装对 Cloudflare Workers `/api/usage/me` 的调用
final class AIProxyUsageService: AIProxyUsageServiceProtocol, Sendable {

    private let proxyBaseURL: URL
    private let session: URLSession

    init(proxyBaseURL: URL, session: URLSession = .shared) {
        self.proxyBaseURL = proxyBaseURL
        self.session = session
    }

    func fetchUsageStats(receiptToken: String) async throws -> AIProxyUsageStats {
        var components = URLComponents(
            url: proxyBaseURL.appendingPathComponent("api/usage/me"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "receiptToken", value: receiptToken)]

        guard let url = components.url else {
            throw AIProxyError.networkError("无效的 URL")
        }

        let (data, response) = try await session.data(from: url)

        guard let http = response as? HTTPURLResponse else {
            throw AIProxyError.networkError("无效的 HTTP 响应")
        }

        switch http.statusCode {
        case 200:
            return try JSONDecoder().decode(AIProxyUsageStats.self, from: data)
        case 401:
            throw AIProxyError.invalidReceipt
        case 403:
            throw AIProxyError.subscriptionRequired
        case 429:
            throw AIProxyError.rateLimitExceeded(0, 0)
        default:
            throw AIProxyError.serverError(http.statusCode)
        }
    }

    func checkProxyAccess(receiptToken: String?) async -> Result<AIProxyUsageStats, AIProxyError> {
        guard let token = receiptToken, !token.isEmpty else {
            return .failure(.subscriptionRequired)
        }

        do {
            let stats = try await fetchUsageStats(receiptToken: token)
            if stats.isOverLimit {
                return .failure(.rateLimitExceeded(stats.callCount, stats.monthlyLimit))
            }
            return .success(stats)
        } catch let error as AIProxyError {
            return .failure(error)
        } catch {
            return .failure(.networkError(error.localizedDescription))
        }
    }
}
