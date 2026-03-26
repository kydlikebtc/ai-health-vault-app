import XCTest
import StoreKit
import StoreKitTest
@testable import AIHealthVault

/// IAP 测试基类 — 所有 StoreKit 测试的共同基础设施
///
/// 每个测试方法在独立的 SKTestSession 中运行：
/// - 使用 AIHealthVault.storekit 配置模拟产品
/// - disableDialogs = true 绕过购买弹窗，测试完全自动化
/// - setUp 时清空所有交易并重置 SubscriptionManager 单例状态
/// - tearDown 时还原 UserDefaults 安装日期（反向试用逻辑）
@MainActor
class IAPTestCase: XCTestCase {

    var session: SKTestSession!

    // MARK: - Lifecycle

    override func setUp() async throws {
        try await super.setUp()

        do {
            session = try SKTestSession(configurationFileNamed: "AIHealthVault")
        } catch {
            throw XCTSkip("SKTestSession 不可用（需要 iOS Simulator）: \(error)")
        }

        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()

        // 清理反向试用的安装日期，确保每个测试从干净状态开始
        resetInstallDate()

        // 重新加载产品并刷新 SubscriptionManager 状态
        await SubscriptionManager.shared.loadProductsAndRefreshStatus()
    }

    override func tearDown() async throws {
        session?.clearTransactions()
        session = nil
        resetInstallDate()
        try await super.tearDown()
    }

    // MARK: - Helpers

    /// 清除反向试用安装日期
    func resetInstallDate() {
        UserDefaults.standard.removeObject(forKey: "subscription_install_date")
    }

    /// 设置安装日期为指定天数之前（模拟试用进度）
    func setInstallDate(daysAgo: Int) {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        UserDefaults.standard.set(date, forKey: "subscription_install_date")
    }

    /// 通过 SKTestSession 模拟购买并刷新状态
    func simulatePurchase(_ productID: SubscriptionProductID) throws {
        try session.buyProduct(productIdentifier: productID.rawValue)
        // 注意：调用后需 await refreshStatus() 让 SubscriptionManager 读取新 entitlement
    }

    /// 让 SubscriptionManager 重新读取当前 entitlement
    func refreshStatus() async {
        await SubscriptionManager.shared.refreshSubscriptionStatus()
    }

    /// 通过 SKTestSession 模拟订阅过期并刷新状态
    func simulateExpiry(_ productID: SubscriptionProductID) throws {
        try session.expireSubscription(productIdentifier: productID.rawValue)
    }

    /// 断言当前订阅状态
    func assertStatus(
        _ expected: SubscriptionStatus,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            SubscriptionManager.shared.subscriptionStatus,
            expected,
            file: file,
            line: line
        )
    }
}
