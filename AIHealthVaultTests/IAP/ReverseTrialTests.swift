import XCTest
import StoreKit
@testable import AIHealthVault

/// TC-RT-01~05: 反向试用（Reverse Trial）测试
///
/// AI Health Vault 的 Reverse Trial 策略：
/// - 新用户安装后享受 14 天完整 Premium 体验
/// - 第 14 天结束后自动降级为 Free 层
/// - 降级后已有随访提醒继续触发，但不可新建（CEO 决策）
/// - 试用期内购买订阅立即生效，切换为 subscribed 状态
@MainActor
final class ReverseTrialTests: IAPTestCase {

    // MARK: - TC-RT-01: 新安装 — 立即进入反向试用

    /// 验证首次安装（无安装日期记录）时状态为 reverseTrial(daysRemaining: 14)
    func testTC_RT_01_freshInstall_isReverseTrial14Days() async throws {
        // setUp 已清除安装日期；refreshStatus 会调用 recordInstallDateIfNeeded()
        resetInstallDate()
        await refreshStatus()

        if case .reverseTrial(let days) = SubscriptionManager.shared.subscriptionStatus {
            XCTAssertEqual(days, 14, "全新安装应剩余 14 天试用")
        } else {
            XCTFail("新用户状态应为 reverseTrial，实际: \(SubscriptionManager.shared.subscriptionStatus)")
        }

        XCTAssertTrue(SubscriptionManager.shared.isPremiumActive, "试用期内 isPremiumActive 应为 true")
    }

    // MARK: - TC-RT-02: 安装 7 天后 — 剩余 7 天

    /// 验证安装 7 天后状态为 reverseTrial(daysRemaining: 7)
    func testTC_RT_02_after7Days_remaining7() async throws {
        setInstallDate(daysAgo: 7)
        await refreshStatus()

        if case .reverseTrial(let days) = SubscriptionManager.shared.subscriptionStatus {
            XCTAssertEqual(days, 7, "安装 7 天后应剩余 7 天试用")
        } else {
            XCTFail("安装 7 天后状态应为 reverseTrial，实际: \(SubscriptionManager.shared.subscriptionStatus)")
        }
    }

    // MARK: - TC-RT-03: 安装 14 天后 — 降级为 Free

    /// 验证安装满 14 天（或更多）后状态降级为 .free
    func testTC_RT_03_after14Days_degradesToFree() async throws {
        setInstallDate(daysAgo: 14)
        await refreshStatus()

        XCTAssertEqual(
            SubscriptionManager.shared.subscriptionStatus,
            .free,
            "安装满 14 天后应降级为 free"
        )
        XCTAssertFalse(SubscriptionManager.shared.isPremiumActive, "降级后 isPremiumActive 应为 false")
    }

    /// 验证安装 30 天后（远超试用期）状态仍为 .free
    func testTC_RT_03b_after30Days_stillFree() async throws {
        setInstallDate(daysAgo: 30)
        await refreshStatus()

        XCTAssertEqual(SubscriptionManager.shared.subscriptionStatus, .free)
    }

    // MARK: - TC-RT-04: 试用期内购买 — 切换为 subscribed

    /// 验证在反向试用期内购买订阅后状态立即切换为 subscribed
    func testTC_RT_04_purchaseDuringTrial_becomesSubscribed() async throws {
        // 处于试用第 7 天
        setInstallDate(daysAgo: 7)
        await refreshStatus()

        guard case .reverseTrial = SubscriptionManager.shared.subscriptionStatus else {
            throw XCTSkip("无法设置 reverseTrial 状态，跳过")
        }

        // 在试用期内购买
        try simulatePurchase(.premiumAnnual)
        await refreshStatus()

        // 购买后状态应切换为 subscribed，不再是 reverseTrial
        assertStatus(.subscribed(productID: SubscriptionProductID.premiumAnnual.rawValue))
        XCTAssertTrue(SubscriptionManager.shared.isPremiumActive)
    }

    // MARK: - TC-RT-05: 降级后随访提醒门控（CEO 决策验证）

    /// 验证降级为 Free 后：
    /// - createFollowUpReminders 功能不可访问（不可新建）
    /// - 其他 Premium 功能同样不可访问
    /// 注：已有随访提醒继续触发的逻辑由 FollowUpNotificationService 控制，
    ///     在 DowngradeIntegrityTests 中验证。
    func testTC_RT_05_afterDowngrade_cannotCreateReminders() async throws {
        // 模拟试用结束
        setInstallDate(daysAgo: 15)
        await refreshStatus()

        guard case .free = SubscriptionManager.shared.subscriptionStatus else {
            throw XCTSkip("无法设置为 free 状态，跳过")
        }

        // 降级后不可新建随访提醒（门控由 hasAccess 控制）
        XCTAssertFalse(
            SubscriptionManager.shared.hasAccess(to: .createFollowUpReminders),
            "TC-RT-05: 降级后不应能新建随访提醒"
        )

        // 降级后所有 AI 功能不可访问
        XCTAssertFalse(SubscriptionManager.shared.hasAccess(to: .aiAnalysis), "AI 分析应被门控")
        XCTAssertFalse(SubscriptionManager.shared.hasAccess(to: .visitPreparation), "就诊准备应被门控")
        XCTAssertFalse(SubscriptionManager.shared.hasAccess(to: .pdfExport), "PDF 导出应被门控")
    }

    // MARK: - 边界测试：试用第 1 天和第 13 天

    func testBoundary_day1_remaining13() async throws {
        setInstallDate(daysAgo: 1)
        await refreshStatus()

        if case .reverseTrial(let days) = SubscriptionManager.shared.subscriptionStatus {
            XCTAssertEqual(days, 13, "安装第 2 天（过了 1 天）应剩余 13 天")
        } else {
            XCTFail("状态应为 reverseTrial，实际: \(SubscriptionManager.shared.subscriptionStatus)")
        }
    }

    func testBoundary_day13_remaining1() async throws {
        setInstallDate(daysAgo: 13)
        await refreshStatus()

        if case .reverseTrial(let days) = SubscriptionManager.shared.subscriptionStatus {
            XCTAssertEqual(days, 1, "安装第 14 天应剩余 1 天")
        } else {
            XCTFail("状态应为 reverseTrial，实际: \(SubscriptionManager.shared.subscriptionStatus)")
        }
    }

    // MARK: - 幂等性：recordInstallDateIfNeeded 只记录一次

    /// 验证 recordInstallDateIfNeeded() 多次调用不会更新安装日期
    func testRecordInstallDate_isIdempotent() async throws {
        // 记录安装日期
        SubscriptionManager.shared.recordInstallDateIfNeeded()
        let firstDate = UserDefaults.standard.object(forKey: "subscription_install_date") as? Date
        XCTAssertNotNil(firstDate, "应记录安装日期")

        // 等待 1 秒后再次调用，日期不应改变
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        SubscriptionManager.shared.recordInstallDateIfNeeded()
        let secondDate = UserDefaults.standard.object(forKey: "subscription_install_date") as? Date

        XCTAssertEqual(
            firstDate?.timeIntervalSince1970,
            secondDate?.timeIntervalSince1970,
            "recordInstallDateIfNeeded 多次调用不应更新日期"
        )
    }
}
