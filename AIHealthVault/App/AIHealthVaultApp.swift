import SwiftUI
import SwiftData

@main
struct AIHealthVaultApp: App {
    @StateObject private var authService = AuthenticationService()

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
            } else {
                LockScreenView()
                    .environmentObject(authService)
            }
        }
    }
}
