import Foundation
import Observation

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

    /// API Key 是否已配置
    private(set) var isAPIKeyConfigured: Bool = false

    /// 本月已使用的 Input Token 数
    private(set) var monthlyInputTokens: Int = 0

    /// 本月已使用的 Output Token 数
    private(set) var monthlyOutputTokens: Int = 0

    /// 上次重置 Token 计数的月份（格式：yyyy-MM）
    private var tokenResetMonth: String = ""

    // MARK: - Computed

    var monthlyTotalTokens: Int { monthlyInputTokens + monthlyOutputTokens }

    /// 预估本月费用（美元），基于 claude-sonnet-4-6 定价
    /// Input: $3/1M tokens, Output: $15/1M tokens
    var estimatedMonthlyCostUSD: Double {
        let inputCost = Double(monthlyInputTokens) / 1_000_000 * 3.0
        let outputCost = Double(monthlyOutputTokens) / 1_000_000 * 15.0
        return inputCost + outputCost
    }

    var estimatedMonthlyCostDisplay: String {
        String(format: "$%.4f", estimatedMonthlyCostUSD)
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
        static let monthlyInputTokens = "ai_monthly_input_tokens"
        static let monthlyOutputTokens = "ai_monthly_output_tokens"
        static let tokenResetMonth = "ai_token_reset_month"
    }

    private func loadFromStorage() {
        isAIEnabled = UserDefaults.standard.object(forKey: Keys.isAIEnabled) as? Bool ?? true
        isAPIKeyConfigured = KeychainService.shared.exists(.claudeAPIKey)
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
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: Date())
    }
}
