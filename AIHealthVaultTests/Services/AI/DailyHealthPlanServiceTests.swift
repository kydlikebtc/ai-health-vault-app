import XCTest
import SwiftData
@testable import AIHealthVault

/// DailyHealthPlanService 单元测试
/// 通过 MockAIService / SpyAIService 验证计划生成逻辑与上下文构建行为
@MainActor
final class DailyHealthPlanServiceTests: SwiftDataTestCase {

    private var sut: DailyHealthPlanService!
    private var mockAI: MockAIService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        sut = DailyHealthPlanService()
        mockAI = MockAIService()
        mockAI.streamDelay = 0
    }

    override func tearDownWithError() throws {
        sut = nil
        mockAI = nil
        try super.tearDownWithError()
    }

    // MARK: - 基础生成

    func testGeneratePlan_returnsAIContent() async throws {
        let member = TestFixtures.makeMember()
        try insertAndSave(member)
        mockAI.mockResponse = "## 今日健康计划\n- 步行 30 分钟"

        let content = try await sut.generatePlan(
            for: member,
            healthKitSummary: nil,
            aiService: mockAI
        )

        XCTAssertEqual(content, "## 今日健康计划\n- 步行 30 分钟")
    }

    func testGeneratePlan_withNilHealthKitSummary_succeeds() async throws {
        let member = TestFixtures.makeMember()
        try insertAndSave(member)

        let content = try await sut.generatePlan(
            for: member,
            healthKitSummary: nil,
            aiService: mockAI
        )

        XCTAssertFalse(content.isEmpty)
    }

    func testGeneratePlan_withHealthKitSummary_succeeds() async throws {
        let member = TestFixtures.makeMember()
        try insertAndSave(member)
        var summary = HealthKitTodaySummary()
        summary.steps = 5000
        summary.heartRate = 72
        summary.sleepHours = 7.5

        let content = try await sut.generatePlan(
            for: member,
            healthKitSummary: summary,
            aiService: mockAI
        )

        XCTAssertFalse(content.isEmpty)
    }

    // MARK: - 错误传播

    func testGeneratePlan_propagatesNetworkError() async {
        let member = TestFixtures.makeMember()
        try? insertAndSave(member)
        mockAI.shouldFail = true
        mockAI.errorToThrow = .networkUnavailable

        do {
            _ = try await sut.generatePlan(
                for: member,
                healthKitSummary: nil,
                aiService: mockAI
            )
            XCTFail("应抛出 networkUnavailable 错误")
        } catch AIError.networkUnavailable {
            // 预期
        } catch {
            XCTFail("预期 networkUnavailable，实际: \(error)")
        }
    }

    func testGeneratePlan_propagatesRateLimitError() async {
        let member = TestFixtures.makeMember()
        try? insertAndSave(member)
        mockAI.shouldFail = true
        mockAI.errorToThrow = .rateLimited(retryAfter: 30)

        do {
            _ = try await sut.generatePlan(
                for: member,
                healthKitSummary: nil,
                aiService: mockAI
            )
            XCTFail("应抛出 rateLimited 错误")
        } catch AIError.rateLimited(let seconds) {
            XCTAssertEqual(seconds, 30)
        } catch {
            XCTFail("预期 rateLimited，实际: \(error)")
        }
    }

    // MARK: - 上下文构建验证（通过 SpyAIService）

    func testGeneratePlan_sendsOneUserMessage() async throws {
        let spy = SpyAIService()
        let member = TestFixtures.makeMember()
        try insertAndSave(member)

        _ = try await sut.generatePlan(
            for: member,
            healthKitSummary: nil,
            aiService: spy
        )

        XCTAssertEqual(spy.capturedMessages.count, 1)
        XCTAssertEqual(spy.capturedMessages.first?.role, .user)
    }

    func testGeneratePlan_passesSystemPrompt() async throws {
        let spy = SpyAIService()
        let member = TestFixtures.makeMember()
        try insertAndSave(member)

        _ = try await sut.generatePlan(
            for: member,
            healthKitSummary: nil,
            aiService: spy
        )

        XCTAssertNotNil(spy.capturedSystemPrompt, "应传递系统提示词")
        XCTAssertFalse(spy.capturedSystemPrompt?.isEmpty ?? true)
    }

    func testGeneratePlan_contextIncludesMemberName() async throws {
        let spy = SpyAIService()
        let member = TestFixtures.makeMember(name: "张三")
        try insertAndSave(member)

        _ = try await sut.generatePlan(
            for: member,
            healthKitSummary: nil,
            aiService: spy
        )

        let userMsg = spy.capturedMessages.first?.content ?? ""
        XCTAssertTrue(userMsg.contains("张三"), "提示词应包含成员姓名")
    }

    func testGeneratePlan_contextIncludesActiveMedication() async throws {
        let spy = SpyAIService()
        let member = TestFixtures.makeMember()
        let med = TestFixtures.makeMedication(name: "阿司匹林")
        member.medications.append(med)
        try insertAndSave(member)

        _ = try await sut.generatePlan(
            for: member,
            healthKitSummary: nil,
            aiService: spy
        )

        let userMsg = spy.capturedMessages.first?.content ?? ""
        XCTAssertTrue(userMsg.contains("阿司匹林"), "提示词应包含当前用药名称")
    }

    func testGeneratePlan_contextIncludesChronicCondition() async throws {
        let spy = SpyAIService()
        let member = TestFixtures.makeMember()
        member.chronicConditions = ["高血压", "糖尿病"]
        try insertAndSave(member)

        _ = try await sut.generatePlan(
            for: member,
            healthKitSummary: nil,
            aiService: spy
        )

        let userMsg = spy.capturedMessages.first?.content ?? ""
        XCTAssertTrue(userMsg.contains("高血压"), "提示词应包含慢性病信息")
        XCTAssertTrue(userMsg.contains("糖尿病"), "提示词应包含全部慢性病")
    }

    func testGeneratePlan_contextIncludesAllergy() async throws {
        let spy = SpyAIService()
        let member = TestFixtures.makeMember()
        member.allergies = ["青霉素"]
        try insertAndSave(member)

        _ = try await sut.generatePlan(
            for: member,
            healthKitSummary: nil,
            aiService: spy
        )

        let userMsg = spy.capturedMessages.first?.content ?? ""
        XCTAssertTrue(userMsg.contains("青霉素"), "提示词应包含过敏原信息")
    }

    func testGeneratePlan_contextIncludesHealthKitSteps() async throws {
        let spy = SpyAIService()
        let member = TestFixtures.makeMember()
        try insertAndSave(member)
        var summary = HealthKitTodaySummary()
        summary.steps = 8000

        _ = try await sut.generatePlan(
            for: member,
            healthKitSummary: summary,
            aiService: spy
        )

        let userMsg = spy.capturedMessages.first?.content ?? ""
        XCTAssertTrue(userMsg.contains("8000"), "提示词应包含 HealthKit 步数")
    }

    func testGeneratePlan_contextIncludesHealthKitHeartRate() async throws {
        let spy = SpyAIService()
        let member = TestFixtures.makeMember()
        try insertAndSave(member)
        var summary = HealthKitTodaySummary()
        summary.heartRate = 65

        _ = try await sut.generatePlan(
            for: member,
            healthKitSummary: summary,
            aiService: spy
        )

        let userMsg = spy.capturedMessages.first?.content ?? ""
        XCTAssertTrue(userMsg.contains("65"), "提示词应包含心率数据")
    }

    func testGeneratePlan_emptySummary_usesDefaultQuery() async throws {
        let spy = SpyAIService()
        let member = TestFixtures.makeMember()
        try insertAndSave(member)
        // isEmpty == true when all fields are nil
        let emptySummary = HealthKitTodaySummary()

        _ = try await sut.generatePlan(
            for: member,
            healthKitSummary: emptySummary,
            aiService: spy
        )

        let userMsg = spy.capturedMessages.first?.content ?? ""
        XCTAssertTrue(userMsg.contains("请根据"), "空 HealthKit 摘要时应退回到默认提示语")
    }

    func testGeneratePlan_withAbnormalCheckupItems_includesInContext() async throws {
        let spy = SpyAIService()
        let member = TestFixtures.makeMember()
        let report = TestFixtures.makeCheckupReport()
        report.abnormalItems = ["总胆固醇偏高", "血糖临界"]
        member.checkups.append(report)
        try insertAndSave(member)

        _ = try await sut.generatePlan(
            for: member,
            healthKitSummary: nil,
            aiService: spy
        )

        let userMsg = spy.capturedMessages.first?.content ?? ""
        XCTAssertTrue(userMsg.contains("总胆固醇偏高") || userMsg.contains("血糖临界"),
                      "提示词应包含最近体检的异常指标")
    }
}

// MARK: - SpyAIService

/// 捕获传入参数以供断言，不发出真实网络请求
private final class SpyAIService: AIService, @unchecked Sendable {
    var isConfigured = true
    private(set) var capturedMessages: [AIMessage] = []
    private(set) var capturedSystemPrompt: String?

    func sendMessage(
        _ messages: [AIMessage],
        systemPrompt: String?
    ) async throws -> (content: String, usage: TokenUsage) {
        capturedMessages = messages
        capturedSystemPrompt = systemPrompt
        return ("Mock 健康计划内容", TokenUsage(inputTokens: 50, outputTokens: 100))
    }

    nonisolated func streamMessage(
        _ messages: [AIMessage],
        systemPrompt: String?
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}
