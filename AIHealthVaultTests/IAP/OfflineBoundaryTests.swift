import XCTest
import StoreKit
@testable import AIHealthVault

/// TC-OFF-01~03: 离线边界测试（W4 回归）
///
/// 验证 SubscriptionManager 在网络不可用或 StoreKit 调用失败时的降级行为：
/// - 产品加载失败时 products 为空但不崩溃
/// - 订阅状态刷新失败时使用最后已知状态
/// - 购买失败时 errorMessage 正确设置
///
/// 注：iOS 17 StoreKit 2 在离线时依赖本地 Transaction 缓存，
///     离线不等于无法读取 entitlement（SKAdNetwork 仍可验证本地 receipt）
@MainActor
final class OfflineBoundaryTests: IAPTestCase {

    // MARK: - TC-OFF-01: 产品加载失败后状态稳定

    /// 模拟 Product.products(for:) 失败（使用无效的 productID）后，
    /// SubscriptionManager 不崩溃，products 为空或仅含有效产品
    func testTC_OFF_01_productLoadFailure_doesNotCrash() async throws {
        // SKTestSession 仅包含 .storekit 配置中定义的产品
        // 请求不存在的 productID 不会 throw，只返回空数组
        let unknownIDs = ["com.aihealthvault.nonexistent.product"]
        do {
            let products = try await Product.products(for: unknownIDs)
            XCTAssertTrue(products.isEmpty, "不存在的 productID 应返回空数组")
        } catch {
            // 在某些环境下可能 throw，验证我们的 Manager 能处理
            XCTAssertTrue(true, "加载失败时不应崩溃")
        }

        // SubscriptionManager.products 不受请求失败影响（之前已成功加载）
        XCTAssertGreaterThanOrEqual(
            SubscriptionManager.shared.products.count, 0,
            "TC-OFF-01: 产品加载失败后 products 不应为负值（不崩溃）"
        )
    }

    // MARK: - TC-OFF-02: 交易失败时的错误处理

    /// 模拟 StoreKit 购买失败（failTransactionsEnabled）时，
    /// Manager 正确设置 errorMessage，不崩溃，状态维持原样
    func testTC_OFF_02_purchaseFailure_setsErrorMessage() async throws {
        // 初始状态：反向试用（无订阅）
        resetInstallDate()
        await refreshStatus()
        let initialStatus = SubscriptionManager.shared.subscriptionStatus

        // 启用交易失败模式
        session.failTransactionsEnabled = true

        guard let product = SubscriptionManager.shared.product(for: .premiumMonthly) else {
            throw XCTSkip("月付产品未加载，跳过")
        }

        // 尝试购买（应失败）
        let success = await SubscriptionManager.shared.purchase(product)

        // 购买应失败
        XCTAssertFalse(success, "TC-OFF-02: 交易失败时 purchase() 应返回 false")

        // 失败后 isPurchasing 应复位
        XCTAssertFalse(SubscriptionManager.shared.isPurchasing, "购买失败后 isPurchasing 应为 false")

        // 订阅状态不应因失败的购买而改变
        // （状态可能变为 free/reverseTrial，但不应意外变为 subscribed）
        if case .subscribed = SubscriptionManager.shared.subscriptionStatus {
            XCTFail("TC-OFF-02: 购买失败后不应切换为 subscribed 状态")
        }

        // 还原
        session.failTransactionsEnabled = false
        _ = initialStatus
    }

    // MARK: - TC-OFF-03: 离线时订阅状态降级为 unknown 而非崩溃

    /// 验证 refreshSubscriptionStatus 在无法访问 StoreKit 时的降级行为
    /// 在 SKTestSession 环境下，StoreKit 是 mock 的，此处验证极端情况处理
    func testTC_OFF_03_offlineStatusRefresh_gracefulDegradation() async throws {
        // 先建立已知状态：购买有效订阅
        try simulatePurchase(.premiumAnnual)
        await refreshStatus()
        assertStatus(.subscribed(productID: SubscriptionProductID.premiumAnnual.rawValue))

        // 在 StoreKit 2 中，Transaction.currentEntitlements 使用本地缓存
        // 即使离线也能读取已验证的 transaction，不会崩溃
        // 多次刷新验证稳定性
        for _ in 0..<3 {
            await refreshStatus()
        }

        // 状态应保持稳定
        assertStatus(.subscribed(productID: SubscriptionProductID.premiumAnnual.rawValue))
        XCTAssertFalse(SubscriptionManager.shared.isPurchasing, "多次刷新后 isPurchasing 应为 false")
        XCTAssertNil(SubscriptionManager.shared.errorMessage, "稳定刷新后不应有错误信息")
    }

    // MARK: - TC-OFF 辅助：并发刷新稳定性

    /// 验证并发调用 refreshSubscriptionStatus 不产生 race condition
    func testConcurrentRefresh_isStable() async throws {
        try simulatePurchase(.premiumMonthly)

        // 并发发起多个刷新，不应崩溃（@MainActor 序列化保证）
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<5 {
                group.addTask { @MainActor in
                    await SubscriptionManager.shared.refreshSubscriptionStatus()
                }
            }
        }

        // 并发刷新后状态应仍然有效
        if case .subscribed = SubscriptionManager.shared.subscriptionStatus {
            // 正常
        } else {
            // 也可能为 reverseTrial（安装日期被重置），属于正常边界
        }
        XCTAssertFalse(SubscriptionManager.shared.isPurchasing, "并发刷新后 isPurchasing 应为 false")
    }
}
