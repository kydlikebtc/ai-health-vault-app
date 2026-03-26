import Foundation
import Observation

// MARK: - AI Service Mode

/// AI 服务模式：服务端代理（默认）或自带 API Key（开发者选项）
enum AIServiceMode: String, CaseIterable {
    /// 通过 Cloudflare Workers 代理调用（需要有效订阅）
    case serverProxy = "server_proxy"
    /// 直接使用用户提供的 Anthropic API Key
    case byok = "byok"

    var displayName: String {
        switch self {
        case .serverProxy: return "服务端代理（推荐）"
        case .byok: return "自带 API Key（开发者）"
        }
    }
}

/// AI 设置管理器 — 管理 AI 功能开关、API Key 状态和 Token 用量
/// 使用 iOS 17 @Observable 宏，比 ObservableObject 更高效
@Observable
@MainActor
final class AISettingsManager {

    // MARK: - Singleton

    static let shared = AISettingsManager()
    private init() {
        loadFromStorage()
    }

    // MARK: - Observed State

    /// AI 功能总开关
    var isAIEnabled: Bool = true {
        didSet { UserDefaults.standard.set(isAIEnabled, forKey: Keys.isAIEnabled) }
    }

    /// AI 服务模式（默认：serverProxy）
    var serviceMode: AIServiceMode = .serverProxy {
        didSet { UserDefaults.standard.set(serviceMode.rawValue, forKey: Keys.serviceMode) }
    }

    /// Cloudflare Workers 代理 URL
    var proxyBaseURL: String = "https://ai-proxy.aihealthvault.app" {
        didSet { UserDefaults.standard.set(proxyBaseURL, forKey: Keys.proxyBaseURL) }
    }

    /// API Key 是否已配置（仅 BYOK 模式下有意义）
    private(set) var isAPIKeyConfigured: Bool = false

    /// 本月已使用的 Input Token 数
    private(set) var monthlyInputTokens: Int = 0

    /// 本月已使用的 Output Token 数
    private(set) var monthlyOutputTokens: Int = 0

    /// 上次重置 Token 计数的月份（格式：yyyy-MM）
    private var tokenResetMonth: String = ""

    // MARK: - Computed

    var monthlyTotalTokens: Int { monthlyInputTokens + monthlyOutputTokens }

    /// AI 功能是否可用（考虑服务模式和订阅/API Key 状态）
    var isAIAvailable: Bool {
        guard isAIEnabled else { return false }
        switch serviceMode {
        case .serverProxy:
            return SubscriptionManager.shared.isPremiumActive
        case .byok:
            return isAPIKeyConfigured
        }
    }

    /// 预估本月费用（美元），基于 claude-haiku-4-5 定价（仅 BYOK 模式下显示）
    /// Input: $0.25/1M tokens, Output: $1.25/1M tokens
    var estimatedMonthlyCostUSD: Double {
        let inputCost = Double(monthlyInputTokens) / 1_000_000 * 0.25
        let outputCost = Double(monthlyOutputTokens) / 1_000_000 * 1.25
        return inputCost + outputCost
    }

    var estimatedMonthlyCostDisplay: String {
        String(format: "$%.4f", estimatedMonthlyCostUSD)
    }

    // MARK: - Service Factory

    /// 创建当前配置下的 AI 服务实例
    /// - Parameter mockFallback: 无法使用真实服务时的 Mock 实现
    /// - Returns: 合适的 AIService 实现
    func makeAIService(mockFallback: any AIService) -> any AIService {
        guard isAIEnabled else { return mockFallback }
        switch serviceMode {
        case .serverProxy:
            guard SubscriptionManager.shared.isPremiumActive else { return mockFallback }
            return AIProxyService.shared
        case .byok:
            guard isAPIKeyConfigured else { return mockFallback }
            return ClaudeService()
        }
    }

    // MARK: - API Key Management

    func saveAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespaces)
        let success = KeychainService.shared.save(trimmed, for: .claudeAPIKey)
        isAPIKeyConfigured = success && !trimmed.isEmpty
    }

    func clearAPIKey() {
        KeychainService.shared.delete(.claudeAPIKey)
        isAPIKeyConfigured = false
    }

    func maskedAPIKey() -> String {
        guard let key = KeychainService.shared.load(.claudeAPIKey), key.count > 8 else {
            return "未配置"
        }
        let prefix = String(key.prefix(7))
        let suffix = String(key.suffix(4))
        return "\(prefix)...\(suffix)"
    }

    // MARK: - Token Tracking

    func recordUsage(_ usage: TokenUsage) {
        resetIfNewMonth()
        monthlyInputTokens += usage.inputTokens
        monthlyOutputTokens += usage.outputTokens
        persistTokenCounts()
    }

    func resetTokenCounts() {
        monthlyInputTokens = 0
        monthlyOutputTokens = 0
        tokenResetMonth = currentMonthKey()
        persistTokenCounts()
    }

    // MARK: - Persistence

    private enum Keys {
        static let isAIEnabled = "ai_is_enabled"
        static let serviceMode = "ai_service_mode"
        static let proxyBaseURL = "ai_proxy_base_url"
        static let monthlyInputTokens = "ai_monthly_input_tokens"
        static let monthlyOutputTokens = "ai_monthly_output_tokens"
        static let tokenResetMonth = "ai_token_reset_month"
    }

    private func loadFromStorage() {
        isAIEnabled = UserDefaults.standard.object(forKey: Keys.isAIEnabled) as? Bool ?? true
        isAPIKeyConfigured = KeychainService.shared.exists(.claudeAPIKey)

        if let modeRaw = UserDefaults.standard.string(forKey: Keys.serviceMode),
           let mode = AIServiceMode(rawValue: modeRaw) {
            serviceMode = mode
        }
        if let savedURL = UserDefaults.standard.string(forKey: Keys.proxyBaseURL), !savedURL.isEmpty {
            proxyBaseURL = savedURL
        }

        tokenResetMonth = UserDefaults.standard.string(forKey: Keys.tokenResetMonth) ?? ""
        resetIfNewMonth()
        monthlyInputTokens = UserDefaults.standard.integer(forKey: Keys.monthlyInputTokens)
        monthlyOutputTokens = UserDefaults.standard.integer(forKey: Keys.monthlyOutputTokens)
    }

    private func persistTokenCounts() {
        UserDefaults.standard.set(monthlyInputTokens, forKey: Keys.monthlyInputTokens)
        UserDefaults.standard.set(monthlyOutputTokens, forKey: Keys.monthlyOutputTokens)
        UserDefaults.standard.set(tokenResetMonth, forKey: Keys.tokenResetMonth)
    }

    private func resetIfNewMonth() {
        let current = currentMonthKey()
        if tokenResetMonth != current {
            monthlyInputTokens = 0
            monthlyOutputTokens = 0
            tokenResetMonth = current
            persistTokenCounts()
        }
    }

    private func currentMonthKey() -> String {
        AISettingsManager.monthKeyFormatter.string(from: Date())
    }

    private static let monthKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        return f
    }()
}
