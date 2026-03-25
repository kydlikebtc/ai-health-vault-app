import SwiftUI
import SwiftData

@main
struct AIHealthVaultApp: App {
    @StateObject private var authService = AuthenticationService()
    @StateObject private var healthKitService = HealthKitService()

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
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("无法创建 ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            if authService.isAuthenticated {
                ContentView()
                    .modelContainer(modelContainer)
                    .environmentObject(authService)
                    .environmentObject(healthKitService)
                    .task {
                        // App 启动时请求授权（若尚未授权）
                        if healthKitService.isAvailable &&
                           healthKitService.authorizationStatus == .notDetermined {
                            try? await healthKitService.requestAuthorization()
                        }
                        // 启动后台 delivery
                        if healthKitService.isAvailable &&
                           healthKitService.authorizationStatus == .authorized {
                            try? await healthKitService.enableBackgroundDelivery {
                                print("[App] HealthKit 后台通知：有新数据")
                            }
                        }
                    }
            } else {
                LockScreenView()
                    .environmentObject(authService)
            }
        }
    }
}
