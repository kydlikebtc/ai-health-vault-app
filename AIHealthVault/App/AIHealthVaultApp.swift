import SwiftUI
import SwiftData
import StoreKit
import UserNotifications
import os

private let appLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aihealthvault", category: "App")

@main
struct AIHealthVaultApp: App {
    @StateObject private var authService = AuthenticationService()
    @StateObject private var healthKitService = HealthKitService()
    @StateObject private var notificationDelegate = AppNotificationDelegate()

    /// 持有 Transaction.updates 监听任务，防止被提前释放
    @State private var transactionListenerTask: Task<Void, Never>?

    /// SwiftData ModelContainer — 包含所有健康数据模型
    private let modelContainer: ModelContainer = {
        let schema = Schema([
            Family.self,
            Member.self,
            MedicalHistory.self,
            Medication.self,
            CheckupReport.self,
            VisitRecord.self,
            WearableEntry.self,
            DailyLog.self,
            TermCacheItem.self,
            CachedVisitPrep.self,
            CustomReminder.self,
            DailyPlan.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("无法创建 ModelContainer: \(error)")
        }
    }()

    init() {
        // 注册「已服用」通知操作类别（必须在 App 启动时执行）
        MedicationNotificationService.shared.registerNotificationCategory()
        // 记录首次安装日期，用于 Reverse Trial 计时
        SubscriptionManager.shared.recordInstallDateIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            if authService.isAuthenticated {
                ContentView()
                    .modelContainer(modelContainer)
                    .environmentObject(authService)
                    .environmentObject(healthKitService)
                    .task {
                        // 设置通知 delegate，使前台也能展示 banner
                        UNUserNotificationCenter.current().delegate = notificationDelegate

                        // 启动 StoreKit 2 Transaction.updates 监听（App 生命周期内持续运行）
                        transactionListenerTask = SubscriptionManager.shared.startTransactionListener()
                        appLogger.info("Transaction.updates 监听已启动")

                        // App 启动时请求授权（若尚未授权）
                        if healthKitService.isAvailable &&
                           healthKitService.authorizationStatus == .notDetermined {
                            try? await healthKitService.requestAuthorization()
                        }
                        // 启动后台 delivery
                        if healthKitService.isAvailable &&
                           healthKitService.authorizationStatus == .authorized {
                            try? await healthKitService.enableBackgroundDelivery {
                                appLogger.debug("HealthKit 后台通知：有新数据")
                            }
                        }
                    }
                    .onDisappear {
                        transactionListenerTask?.cancel()
                        transactionListenerTask = nil
                    }
            } else {
                LockScreenView()
                    .environmentObject(authService)
            }
        }
    }
}

// MARK: - 通知 Delegate

/// 处理前台通知展示及「已服用」操作响应
@MainActor
final class AppNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, ObservableObject {

    /// App 在前台时仍显示 banner + sound
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// 处理通知操作（「已服用」按钮）
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.actionIdentifier == MedicationNotificationService.actionMarkTaken {
            let userInfo = response.notification.request.content.userInfo
            let medId = userInfo["medicationId"] as? String ?? "unknown"
            let slot  = userInfo["slot"] as? String ?? ""
            appLogger.info("用药已标记为已服用 — medicationId=\(medId) slot=\(slot)")
        }
        completionHandler()
    }
}
