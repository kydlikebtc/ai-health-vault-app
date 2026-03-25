import XCTest
import SwiftData
@testable import AIHealthVault

/// DailyHealthPlanService 输出验证测试
/// 使用 MockAIService 替代真实 Claude API，验证服务层的调用协议和错误传播
/// 上下文构建验证详见 Services/AI/DailyHealthPlanServiceTests.swift
final class DailyPlanServiceOutputTests: XCTestCase {

    private var mock: MockAIService!
    private let sut = DailyHealthPlanService.shared

    override func setUp() {
        super.setUp()
        mock = MockAIService()
    }

    override func tearDown() {
        mock = nil
        super.tearDown()
    }

    // MARK: - generatePlan 基础场景

    func testGeneratePlan_returnsNonEmptyContent() async throws {
        let member = TestFixtures.makeMember()
        let content = try await sut.generatePlan(
            for: member,
            healthKitSummary: nil,
            aiService: mock
        )
        XCTAssertFalse(content.isEmpty, "generatePlan 应返回非空内容")
    }

    func testGeneratePlan_returnsConfiguredMockResponse() async throws {
        let member = TestFixtures.makeMember()
        mock.mockResponse = "## 今日健康计划\n- 早餐后服药\n- 步行 30 分钟\n- 饮水 2L"
        let content = try await sut.generatePlan(
            for: member,
            healthKitSummary: nil,
            aiService: mock
        )
        XCTAssertEqual(content, mock.mockResponse,
                       "generatePlan 应透传 AIService 返回的内容，不做二次加工")
    }

    func testGeneratePlan_withNilHealthKitSummary_doesNotThrow() async throws {
        let member = TestFixtures.makeMember()
        let content = try await sut.generatePlan(
            for: member,
            healthKitSummary: nil,
            aiService: mock
        )
        XCTAssertFalse(content.isEmpty, "HealthKit 数据为 nil 时仍应返回有效内容")
    }

    // MARK: - generatePlan with HealthKit 数据

    func testGeneratePlan_withFullHealthKitSummary_succeeds() async throws {
        let member = TestFixtures.makeMember()
        let summary = HealthKitTodaySummary(
            steps: 8432,
            heartRate: 72.0,
            sleepHours: 7.5,
            weight: 68.5,
            bloodOxygen: 98.2
        )
        let content = try await sut.generatePlan(
            for: member,
            healthKitSummary: summary,
            aiService: mock
        )
        XCTAssertFalse(content.isEmpty, "传入 HealthKit 摘要时 generatePlan 应正常返回")
    }

    func testGeneratePlan_withEmptyHealthKitSummary_succeeds() async throws {
        let member = TestFixtures.makeMember()
        let summary = HealthKitTodaySummary()  // isEmpty == true
        let content = try await sut.generatePlan(
            for: member,
            healthKitSummary: summary,
            aiService: mock
        )
        XCTAssertFalse(content.isEmpty, "空的 HealthKit 摘要应被忽略，计划仍应生成")
    }

    func testGeneratePlan_withPartialHealthKitSummary_succeeds() async throws {
        let member = TestFixtures.makeMember()
        // 只有步数，无心率/睡眠
        let summary = HealthKitTodaySummary(steps: 5000)
        let content = try await sut.generatePlan(
            for: member,
            healthKitSummary: summary,
            aiService: mock
        )
        XCTAssertFalse(content.isEmpty)
    }

    // MARK: - generatePlan 与成员健康数据

    func testGeneratePlan_memberWithChronicConditions_succeeds() async throws {
        let member = TestFixtures.makeMember()
        member.chronicConditions = ["高血压", "糖尿病"]
        let content = try await sut.generatePlan(
            for: member,
            healthKitSummary: nil,
            aiService: mock
        )
        XCTAssertFalse(content.isEmpty, "有慢性病记录的成员应能正常生成计划")
    }

    func testGeneratePlan_memberWithAllergies_succeeds() async throws {
        let member = TestFixtures.makeMember()
        member.allergies = ["青霉素", "海鲜"]
        let content = try await sut.generatePlan(
            for: member,
            healthKitSummary: nil,
            aiService: mock
        )
        XCTAssertFalse(content.isEmpty, "有过敏记录的成员应能正常生成计划")
    }

    func testGeneratePlan_memberWithNoBirthday_succeeds() async throws {
        // birthday 为 nil 时 member.age 为 nil，上下文构建不应崩溃
        let member = Member(name: "无生日用户")
        let content = try await sut.generatePlan(
            for: member,
            healthKitSummary: nil,
            aiService: mock
        )
        XCTAssertFalse(content.isEmpty, "未设置生日的成员也应能正常生成计划")
    }

    // MARK: - 错误传播

    func testGeneratePlan_whenAINotConfigured_throwsError() async {
        let member = TestFixtures.makeMember()
        mock.shouldFail = true
        mock.errorToThrow = .notConfigured

        do {
            _ = try await sut.generatePlan(for: member, healthKitSummary: nil, aiService: mock)
            XCTFail("AI 未配置时应抛出错误")
        } catch AIError.notConfigured {
            // 预期：服务层应透传 AIError
        } catch {
            XCTFail("预期 AIError.notConfigured，实际: \(error)")
        }
    }

    func testGeneratePlan_whenNetworkUnavailable_throwsError() async {
        let member = TestFixtures.makeMember()
        mock.shouldFail = true
        mock.errorToThrow = .networkUnavailable

        do {
            _ = try await sut.generatePlan(for: member, healthKitSummary: nil, aiService: mock)
            XCTFail("网络不可用时应抛出错误")
        } catch AIError.networkUnavailable {
            // 预期
        } catch {
            XCTFail("预期 networkUnavailable，实际: \(error)")
        }
    }

    func testGeneratePlan_whenRateLimited_throwsError() async {
        let member = TestFixtures.makeMember()
        mock.shouldFail = true
        mock.errorToThrow = .rateLimited(retryAfter: 60)

        do {
            _ = try await sut.generatePlan(for: member, healthKitSummary: nil, aiService: mock)
            XCTFail("被限速时应抛出错误")
        } catch AIError.rateLimited(let after) {
            XCTAssertEqual(after, 60)
        } catch {
            XCTFail("预期 rateLimited，实际: \(error)")
        }
    }

    // MARK: - 多次调用稳定性

    func testGeneratePlan_calledMultipleTimes_alwaysReturnsContent() async throws {
        let member = TestFixtures.makeMember()
        for i in 1...3 {
            mock.mockResponse = "第 \(i) 次计划内容"
            let content = try await sut.generatePlan(
                for: member,
                healthKitSummary: nil,
                aiService: mock
            )
            XCTAssertEqual(content, "第 \(i) 次计划内容",
                           "第 \(i) 次调用应返回正确内容")
        }
    }
}
