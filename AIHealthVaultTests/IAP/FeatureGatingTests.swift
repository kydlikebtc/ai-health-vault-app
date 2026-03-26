import XCTest
import StoreKit
@testable import AIHealthVault

/// TC-GATE-01~07: 功能门控（Feature Gating）测试
///
/// 验证 SubscriptionManager.hasAccess(to:) 和 isPremiumActive 在三种订阅状态
/// （free、subscribed、reverseTrial）下对所有 PremiumFeature 的准确性。
///
/// TC-GATE-07（AI Proxy Usage Metering）依赖 AIH-44，标记为 XCTSkip 等待实现。
@MainActor
final class FeatureGatingTests: IAPTestCase {

    // MARK: - TC-GATE-01: Free 用户无法访问任何 Premium 功能

    /// 验证订阅过期后 Free 用户对所有 PremiumFeature 均无访问权限
    func testTC_GATE_01_freeUserHasNoAccess() async throws {
        // 确保 Free 状态：试用结束（安装日期 > 14 天前）
        setInstallDate(daysAgo: 15)
        await refreshStatus()

        guard case .free = SubscriptionManager.shared.subscriptionStatus else {
            throw XCTSkip("无法设置为 Free 状态，跳过：\(SubscriptionManager.shared.subscriptionStatus)")
        }

        for feature in PremiumFeature.allCases {
            XCTAssertFalse(
                SubscriptionManager.shared.hasAccess(to: feature),
                "Free 用户不应有 \(feature.rawValue) 访问权"
            )
        }
        XCTAssertFalse(SubscriptionManager.shared.isPremiumActive, "Free 用户 isPremiumActive 应为 false")
    }

    // MARK: - TC-GATE-02: 订阅用户可访问所有 Premium 功能

    /// 验证有效订阅用户对所有 PremiumFeature 均有访问权限
    func testTC_GATE_02_subscribedUserHasFullAccess() async throws {
        try simulatePurchase(.premiumMonthly)
        await refreshStatus()

        guard case .subscribed = SubscriptionManager.shared.subscriptionStatus else {
            XCTFail("购买后状态应为 subscribed")
            return
        }

        for feature in PremiumFeature.allCases {
            XCTAssertTrue(
                SubscriptionManager.shared.hasAccess(to: feature),
                "订阅用户应有 \(feature.rawValue) 访问权"
            )
        }
        XCTAssertTrue(SubscriptionManager.shared.isPremiumActive, "订阅用户 isPremiumActive 应为 true")
    }

    // MARK: - TC-GATE-03: 反向试用用户可访问所有 Premium 功能

    /// 验证反向试用期内用户对所有 PremiumFeature 均有访问权限
    func testTC_GATE_03_reverseTrialUserHasFullAccess() async throws {
        // 新用户（无安装日期）→ reverseTrial
        resetInstallDate()
        await refreshStatus()

        guard case .reverseTrial = SubscriptionManager.shared.subscriptionStatus else {
            throw XCTSkip("无法设置为 reverseTrial 状态，跳过：\(SubscriptionManager.shared.subscriptionStatus)")
        }

        for feature in PremiumFeature.allCases {
            XCTAssertTrue(
                SubscriptionManager.shared.hasAccess(to: feature),
                "试用期用户应有 \(feature.rawValue) 访问权"
            )
        }
        XCTAssertTrue(SubscriptionManager.shared.isPremiumActive, "试用期用户 isPremiumActive 应为 true")
    }

    // MARK: - TC-GATE-04: isPremiumActive — Free 状态

    func testTC_GATE_04_isPremiumActive_free() async throws {
        setInstallDate(daysAgo: 20)
        await refreshStatus()

        if case .free = SubscriptionManager.shared.subscriptionStatus {
            XCTAssertFalse(SubscriptionManager.shared.isPremiumActive)
        } else {
            throw XCTSkip("跳过：无法设置为 Free 状态")
        }
    }

    // MARK: - TC-GATE-05: isPremiumActive — subscribed 状态

    func testTC_GATE_05_isPremiumActive_subscribed() async throws {
        try simulatePurchase(.premiumAnnual)
        await refreshStatus()

        XCTAssertTrue(SubscriptionManager.shared.isPremiumActive)
    }

    // MARK: - TC-GATE-06: isPremiumActive — reverseTrial 状态

    func testTC_GATE_06_isPremiumActive_reverseTrial() async throws {
        resetInstallDate()
        await refreshStatus()

        if case .reverseTrial = SubscriptionManager.shared.subscriptionStatus {
            XCTAssertTrue(SubscriptionManager.shared.isPremiumActive)
        } else {
            throw XCTSkip("跳过：无法设置为 reverseTrial 状态")
        }
    }

    // MARK: - TC-GATE-07: AI Proxy Usage Metering（AIH-44 已完成）

    private let mockProxyURL = URL(string: "https://mock.proxy")!

    /// TC-GATE-07-a: Free 用户无 receiptToken，Proxy 直接拒绝（subscription_required）
    func testTC_GATE_07a_freeUserWithoutReceiptDenied() async {
        let service = AIProxyUsageService(proxyBaseURL: mockProxyURL)

        let result = await service.checkProxyAccess(receiptToken: nil)

        guard case .failure(let error) = result else {
            XCTFail("Free 用户应被 Proxy 拒绝")
            return
        }
        XCTAssertEqual(error, .subscriptionRequired, "无 receiptToken 应返回 subscriptionRequired")
    }

    /// TC-GATE-07-b: Free 用户有 receiptToken 但 Proxy 返回 403
    func testTC_GATE_07b_freeUserWith403Response() async {
        let session = MockURLProtocol.makeSession(
            statusCode: 403,
            body: #"{"error":"Active Premium subscription required","code":"subscription_required"}"#
        )
        let service = AIProxyUsageService(proxyBaseURL: mockProxyURL, session: session)

        let result = await service.checkProxyAccess(receiptToken: "free-user-token")

        guard case .failure(let error) = result else {
            XCTFail("Free 用户应被 Proxy 拒绝")
            return
        }
        XCTAssertEqual(error, .subscriptionRequired)
    }

    /// TC-GATE-07-c: Premium 用户在限额内（25/50），Proxy 放通并返回用量统计
    func testTC_GATE_07c_premiumUserWithinLimitAllowed() async {
        let usageJSON = #"{"anonymousId":"abc123","billingMonth":"2026-03","callCount":25,"monthlyLimit":50,"remaining":25}"#
        let session = MockURLProtocol.makeSession(statusCode: 200, body: usageJSON)
        let service = AIProxyUsageService(proxyBaseURL: mockProxyURL, session: session)

        let result = await service.checkProxyAccess(receiptToken: "premium-valid-token")

        guard case .success(let stats) = result else {
            XCTFail("Premium 用户在限额内应被放通，实际：\(result)")
            return
        }
        XCTAssertEqual(stats.callCount, 25)
        XCTAssertEqual(stats.monthlyLimit, 50)
        XCTAssertEqual(stats.remaining, 25)
        XCTAssertFalse(stats.isOverLimit)
    }

    /// TC-GATE-07-d: Premium 用户恰好超出限额（remaining=0），应被限流
    func testTC_GATE_07d_premiumUserOverLimitBlocked() async {
        let usageJSON = #"{"anonymousId":"abc123","billingMonth":"2026-03","callCount":50,"monthlyLimit":50,"remaining":0}"#
        let session = MockURLProtocol.makeSession(statusCode: 200, body: usageJSON)
        let service = AIProxyUsageService(proxyBaseURL: mockProxyURL, session: session)

        let result = await service.checkProxyAccess(receiptToken: "premium-over-limit-token")

        guard case .failure(let error) = result else {
            XCTFail("超限用户应被限流")
            return
        }
        if case .rateLimitExceeded(let current, let limit) = error {
            XCTAssertEqual(current, 50, "当前调用次数应为 50")
            XCTAssertEqual(limit, 50, "月度上限应为 50")
        } else {
            XCTFail("超限应返回 rateLimitExceeded，实际：\(error)")
        }
    }

    /// TC-GATE-07-e: 月初重置 — 新月份 callCount=0，remaining 恢复为 monthlyLimit
    func testTC_GATE_07e_newMonthResetsUsageQuota() async {
        let usageJSON = #"{"anonymousId":"abc123","billingMonth":"2026-04","callCount":0,"monthlyLimit":50,"remaining":50}"#
        let session = MockURLProtocol.makeSession(statusCode: 200, body: usageJSON)
        let service = AIProxyUsageService(proxyBaseURL: mockProxyURL, session: session)

        let result = await service.checkProxyAccess(receiptToken: "premium-new-month-token")

        guard case .success(let stats) = result else {
            XCTFail("月初重置后用户应有完整配额")
            return
        }
        XCTAssertEqual(stats.callCount, 0, "月初重置后调用次数应为 0")
        XCTAssertEqual(stats.remaining, stats.monthlyLimit, "月初重置后剩余次数应等于 monthlyLimit")
        XCTAssertFalse(stats.isOverLimit)
    }

    // MARK: - 功能边界：特定 feature 验证

    /// 验证 createFollowUpReminders 在 Free 状态下不可用（已有提醒不受影响，但不可新建）
    func testFollowUpRemindersGating_freeCannotCreate() async throws {
        setInstallDate(daysAgo: 15)
        await refreshStatus()

        if case .free = SubscriptionManager.shared.subscriptionStatus {
            XCTAssertFalse(
                SubscriptionManager.shared.hasAccess(to: .createFollowUpReminders),
                "Free 用户不能新建随访提醒"
            )
        } else {
            throw XCTSkip("跳过：无法设置为 Free 状态")
        }
    }

    /// 验证 extendedFamilyMembers 在 Free 状态下不可用（最多 2 人）
    func testExtendedFamilyMembersGating_freeIsLimited() async throws {
        setInstallDate(daysAgo: 15)
        await refreshStatus()

        if case .free = SubscriptionManager.shared.subscriptionStatus {
            XCTAssertFalse(
                SubscriptionManager.shared.hasAccess(to: .extendedFamilyMembers),
                "Free 用户家庭成员上限为 2 人，不应有 extendedFamilyMembers 访问权"
            )
        } else {
            throw XCTSkip("跳过：无法设置为 Free 状态")
        }
    }
}
