import Foundation
import StoreKit
import Observation
import os

private let subLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aihealthvault", category: "SubscriptionManager")

// MARK: - Product IDs

enum SubscriptionProductID: String, CaseIterable {
    case premiumMonthly = "com.aihealthvault.premium.monthly"
    case premiumAnnual  = "com.aihealthvault.premium.annual"
    case familyAnnual   = "com.aihealthvault.family.annual"

    var isFamilyShareable: Bool {
        self == .familyAnnual
    }
}

// MARK: - Subscription Status

enum SubscriptionStatus: Equatable {
    /// 新用户或未购买，14 天免费试用期内
    case reverseTrial(daysRemaining: Int)
    /// 有效订阅
    case subscribed(productID: String)
    /// 免费层（试用结束 / 订阅过期）
    case free
    /// 未知（首次加载中）
    case unknown
}

// MARK: - SubscriptionManager

/// StoreKit 2 订阅管理器 — 管理产品加载、购买、订阅状态和 Entitlement
/// 参考 AISettingsManager 架构：@Observable 单例，@MainActor 主线程安全
@Observable
@MainActor
final class SubscriptionManager {

    // MARK: - Singleton

    static let shared = SubscriptionManager()
    private init() {
        Task { await loadProductsAndRefreshStatus() }
    }

    // MARK: - Observed State

    /// 当前可用的订阅产品列表（已按价格排序）
    private(set) var products: [Product] = []

    /// 当前订阅状态
    private(set) var subscriptionStatus: SubscriptionStatus = .unknown

    /// 是否正在处理购买
    private(set) var isPurchasing: Bool = false

    /// 购买或恢复时的错误信息
    private(set) var errorMessage: String?

    // MARK: - Entitlement Check

    /// 检查用户是否有权访问指定 Premium 功能
    func hasAccess(to feature: PremiumFeature) -> Bool {
        switch subscriptionStatus {
        case .subscribed:
            return true
        case .reverseTrial:
            return true  // 试用期内全功能访问
        case .free, .unknown:
            return false
        }
    }

    /// 是否处于有效 Premium 状态（订阅或试用）
    var isPremiumActive: Bool {
        switch subscriptionStatus {
        case .subscribed, .reverseTrial:
            return true
        case .free, .unknown:
            return false
        }
    }

    // MARK: - Products

    /// 加载产品信息并刷新订阅状态
    func loadProductsAndRefreshStatus() async {
        await loadProducts()
        await refreshSubscriptionStatus()
    }

    private func loadProducts() async {
        do {
            let ids = SubscriptionProductID.allCases.map(\.rawValue)
            let fetched = try await Product.products(for: ids)
            // 按价格排序：月付 < 年付 < 家庭年付
            products = fetched.sorted { $0.price < $1.price }
            subLogger.info("已加载 \(fetched.count) 个订阅产品")
        } catch {
            subLogger.error("加载产品失败: \(error.localizedDescription)")
        }
    }

    // MARK: - Status Refresh

    /// 刷新当前用户的订阅状态
    func refreshSubscriptionStatus() async {
        var foundActiveSubscription: Transaction? = nil

        // 遍历所有当前 entitlement
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else {
                subLogger.warning("发现未验证的 entitlement，跳过")
                continue
            }
            guard transaction.productType == .autoRenewable else { continue }

            if !transaction.isUpgraded {
                foundActiveSubscription = transaction
                break
            }
        }

        if let tx = foundActiveSubscription {
            subscriptionStatus = .subscribed(productID: tx.productID)
            subLogger.info("订阅有效: productID=\(tx.productID)")
        } else {
            // 检查是否在 Reverse Trial 期间（首次安装 14 天内）
            subscriptionStatus = checkReverseTrialStatus()
        }
    }

    // MARK: - Reverse Trial

    private enum TrialKeys {
        static let installDate = "subscription_install_date"
    }

    private static let reversTrialDays = 14

    /// 记录首次安装日期（仅设置一次）
    func recordInstallDateIfNeeded() {
        if UserDefaults.standard.object(forKey: TrialKeys.installDate) == nil {
            UserDefaults.standard.set(Date(), forKey: TrialKeys.installDate)
            subLogger.info("记录首次安装日期: \(Date())")
        }
    }

    private func checkReverseTrialStatus() -> SubscriptionStatus {
        guard let installDate = UserDefaults.standard.object(forKey: TrialKeys.installDate) as? Date else {
            // 尚未记录安装日期，说明是真正的新用户，视为试用第一天
            recordInstallDateIfNeeded()
            return .reverseTrial(daysRemaining: Self.reversTrialDays)
        }

        let elapsed = Calendar.current.dateComponents([.day], from: installDate, to: Date()).day ?? 0
        let remaining = Self.reversTrialDays - elapsed

        if remaining > 0 {
            subLogger.info("Reverse Trial: 剩余 \(remaining) 天")
            return .reverseTrial(daysRemaining: remaining)
        } else {
            subLogger.info("Reverse Trial 已结束，降级为 Free")
            return .free
        }
    }

    // MARK: - Purchase

    /// 发起购买
    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        isPurchasing = true
        errorMessage = nil
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    subLogger.error("购买验证失败")
                    errorMessage = String(localized: "purchase_verification_failed")
                    return false
                }
                await transaction.finish()
                await refreshSubscriptionStatus()
                subLogger.info("购买成功: productID=\(transaction.productID)")
                return true

            case .userCancelled:
                subLogger.info("用户取消购买")
                return false

            case .pending:
                subLogger.info("购买待处理（等待家长批准等）")
                errorMessage = String(localized: "purchase_pending")
                return false

            @unknown default:
                return false
            }
        } catch StoreKitError.userCancelled {
            return false
        } catch {
            subLogger.error("购买失败: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Restore

    /// 恢复购买
    func restorePurchases() async {
        isPurchasing = true
        errorMessage = nil
        defer { isPurchasing = false }

        do {
            try await AppStore.sync()
            await refreshSubscriptionStatus()
            subLogger.info("恢复购买完成")
        } catch {
            subLogger.error("恢复购买失败: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Transaction Listener (called from App entry point)

    /// 启动后台 Transaction.updates 监听，返回 Task 供 App 持有
    nonisolated func startTransactionListener() -> Task<Void, Never> {
        Task.detached(priority: .background) { [weak self] in
            for await result in Transaction.updates {
                guard let self else { break }
                switch result {
                case .verified(let transaction):
                    subLogger.info("Transaction update: productID=\(transaction.productID) revocationDate=\(String(describing: transaction.revocationDate))")
                    await transaction.finish()
                    await self.refreshSubscriptionStatus()
                case .unverified(_, let error):
                    subLogger.warning("Unverified transaction update: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Helpers

    /// 找到指定 ProductID 的 Product 对象
    func product(for id: SubscriptionProductID) -> Product? {
        products.first { $0.id == id.rawValue }
    }

    /// 年付节省金额展示字符串（相对月付年化）
    func annualSavingsDisplay() -> String? {
        guard let monthly = product(for: .premiumMonthly),
              let annual = product(for: .premiumAnnual) else { return nil }
        let annualizedMonthly = monthly.price * 12
        let savings = annualizedMonthly - annual.price
        guard savings > 0 else { return nil }
        return annual.priceFormatStyle.format(savings)
    }
}
