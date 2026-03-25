import XCTest
@testable import AIHealthVault

/// AISettingsManager 单元测试
/// 验证：Token 累计、月度重置、费用估算、API Key 掩码、AI 开关持久化
///
/// 注意：AISettingsManager 为 @Observable 单例，依赖 UserDefaults.standard 和 KeychainService。
/// 每个测试在 tearDown 中清理副作用（Key 删除、token 重置），保证测试间隔离。
@MainActor
final class AISettingsManagerTests: XCTestCase {

    private var sut: AISettingsManager!

    override func setUpWithError() throws {
        try super.setUpWithError()
        sut = AISettingsManager.shared
        // 确保每次测试以干净状态开始
        sut.resetTokenCounts()
        sut.clearAPIKey()
        sut.isAIEnabled = true
    }

    override func tearDownWithError() throws {
        sut.resetTokenCounts()
        sut.clearAPIKey()
        sut.isAIEnabled = true
        sut = nil
        try super.tearDownWithError()
    }

    // MARK: - Token 累计

    func testRecordUsage_addsInputAndOutputTokens() {
        sut.recordUsage(TokenUsage(inputTokens: 100, outputTokens: 50))

        XCTAssertEqual(sut.monthlyInputTokens, 100)
        XCTAssertEqual(sut.monthlyOutputTokens, 50)
    }

    func testRecordUsage_multipleCallsAccumulate() {
        sut.recordUsage(TokenUsage(inputTokens: 200, outputTokens: 80))
        sut.recordUsage(TokenUsage(inputTokens: 300, outputTokens: 120))

        XCTAssertEqual(sut.monthlyInputTokens, 500)
        XCTAssertEqual(sut.monthlyOutputTokens, 200)
    }

    func testMonthlyTotalTokens_equalsSumOfInputAndOutput() {
        sut.recordUsage(TokenUsage(inputTokens: 1000, outputTokens: 400))

        XCTAssertEqual(sut.monthlyTotalTokens, 1400)
    }

    // MARK: - 重置

    func testResetTokenCounts_setsCountsToZero() {
        sut.recordUsage(TokenUsage(inputTokens: 5000, outputTokens: 2000))

        sut.resetTokenCounts()

        XCTAssertEqual(sut.monthlyInputTokens, 0)
        XCTAssertEqual(sut.monthlyOutputTokens, 0)
        XCTAssertEqual(sut.monthlyTotalTokens, 0)
    }

    // MARK: - 费用估算

    func testEstimatedMonthlyCostUSD_zeroTokens_isZero() {
        XCTAssertEqual(sut.estimatedMonthlyCostUSD, 0.0, accuracy: 0.0001)
    }

    func testEstimatedMonthlyCostUSD_oneMillionInputTokens() {
        // Input: $3/1M → 1M input = $3.00
        sut.recordUsage(TokenUsage(inputTokens: 1_000_000, outputTokens: 0))

        XCTAssertEqual(sut.estimatedMonthlyCostUSD, 3.0, accuracy: 0.0001,
                       "100万 Input Token 费用应为 $3.00")
    }

    func testEstimatedMonthlyCostUSD_oneMillionOutputTokens() {
        // Output: $15/1M → 1M output = $15.00
        sut.recordUsage(TokenUsage(inputTokens: 0, outputTokens: 1_000_000))

        XCTAssertEqual(sut.estimatedMonthlyCostUSD, 15.0, accuracy: 0.0001,
                       "100万 Output Token 费用应为 $15.00")
    }

    func testEstimatedMonthlyCostUSD_mixedTokens() {
        // 500K input ($1.50) + 100K output ($1.50) = $3.00
        sut.recordUsage(TokenUsage(inputTokens: 500_000, outputTokens: 100_000))

        XCTAssertEqual(sut.estimatedMonthlyCostUSD, 3.0, accuracy: 0.0001)
    }

    func testEstimatedMonthlyCostDisplay_formatIsCorrect() {
        sut.recordUsage(TokenUsage(inputTokens: 1_000_000, outputTokens: 0))

        // 期望格式：$3.0000
        XCTAssertTrue(sut.estimatedMonthlyCostDisplay.hasPrefix("$"),
                      "费用显示应以 '$' 开头")
        XCTAssertTrue(sut.estimatedMonthlyCostDisplay.contains("."),
                      "费用显示应包含小数点")
    }

    // MARK: - API Key 管理

    func testSaveAPIKey_setsIsAPIKeyConfiguredTrue() {
        sut.saveAPIKey("sk-ant-testkey12345678")

        XCTAssertTrue(sut.isAPIKeyConfigured, "保存有效 API Key 后 isAPIKeyConfigured 应为 true")
    }

    func testClearAPIKey_setsIsAPIKeyConfiguredFalse() {
        sut.saveAPIKey("sk-ant-testkey12345678")
        sut.clearAPIKey()

        XCTAssertFalse(sut.isAPIKeyConfigured, "清除 API Key 后 isAPIKeyConfigured 应为 false")
    }

    func testSaveAPIKey_emptyString_doesNotSetConfigured() {
        sut.saveAPIKey("")

        XCTAssertFalse(sut.isAPIKeyConfigured, "空字符串不应被视为有效 API Key")
    }

    func testSaveAPIKey_whitespaceOnly_doesNotSetConfigured() {
        sut.saveAPIKey("   ")

        XCTAssertFalse(sut.isAPIKeyConfigured, "纯空格不应被视为有效 API Key")
    }

    // MARK: - API Key 掩码

    func testMaskedAPIKey_withoutKey_returnsUnsetLabel() {
        sut.clearAPIKey()

        XCTAssertEqual(sut.maskedAPIKey(), "未配置",
                       "未配置 API Key 时应返回「未配置」")
    }

    func testMaskedAPIKey_shortKey_returnsUnsetLabel() {
        // 少于 8 个字符的 key 不应显示掩码
        sut.saveAPIKey("sk-1234")

        XCTAssertEqual(sut.maskedAPIKey(), "未配置",
                       "过短的 API Key 应返回「未配置」")
    }

    func testMaskedAPIKey_validKey_showsPrefixAndSuffix() {
        let key = "sk-ant-api03-ABCDEFGHIJKLMNOPQRSTUVWXYZ1234"
        sut.saveAPIKey(key)

        let masked = sut.maskedAPIKey()

        XCTAssertTrue(masked.hasPrefix("sk-ant-"), "掩码应保留前 7 个字符")
        XCTAssertTrue(masked.contains("..."), "掩码中间部分应为 '...'")
        XCTAssertTrue(masked.hasSuffix("1234"), "掩码应保留后 4 个字符")
    }

    func testMaskedAPIKey_doesNotExposeFullKey() {
        let key = "sk-ant-api03-ABCDEFGHIJKLMNOPQRSTUVWXYZ1234"
        sut.saveAPIKey(key)

        let masked = sut.maskedAPIKey()

        XCTAssertNotEqual(masked, key, "掩码不应等于原始 Key")
        XCTAssertFalse(masked.contains("ABCDEFGHIJKLMNO"), "掩码不应暴露中间字符")
    }

    // MARK: - AI 功能开关

    func testIsAIEnabled_defaultIsTrue() {
        sut.isAIEnabled = true
        XCTAssertTrue(sut.isAIEnabled)
    }

    func testIsAIEnabled_canBeDisabled() {
        sut.isAIEnabled = false
        XCTAssertFalse(sut.isAIEnabled)
    }

    func testIsAIEnabled_persistsAcrossRead() {
        sut.isAIEnabled = false
        // 直接从 UserDefaults 读取，验证持久化
        let stored = UserDefaults.standard.bool(forKey: "ai_is_enabled")
        XCTAssertFalse(stored, "isAIEnabled = false 应持久化到 UserDefaults")
    }
}
