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

    // MARK: - TC-GATE-07: AI Proxy Usage Metering（依赖 AIH-44）

    /// AI Proxy 用量限制门控验证
    /// 状态：等待 AIH-44（Cloudflare Workers AI Proxy）完成后实现
    func testTC_GATE_07_aiProxyUsageMeteringGating() throws {
        throw XCTSkip("TC-GATE-07 依赖 AIH-44 (AI Proxy Usage Metering API)，待 AIH-44 完成后实现")
        // 实现计划：
        // 1. Mock AI Proxy 响应，模拟当月已消耗 50 次
        // 2. 验证 Free 用户：请求被 Proxy 拒绝（403 / 超限错误）
        // 3. 验证 Premium 用户（50次内）：请求被 Proxy 放通
        // 4. 验证 Premium 用户（超 50 次）：请求被 Proxy 限流
        // 5. 月初重置：新月份开始后限流计数器归零
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
