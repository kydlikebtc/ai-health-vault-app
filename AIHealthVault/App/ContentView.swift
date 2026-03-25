import SwiftUI

/// 主导航容器 — TabView + NavigationStack 框架
struct ContentView: View {
    @EnvironmentObject private var authService: AuthenticationService

    var body: some View {
        TabView {
            FamilyListView()
                .tabItem {
                    Label("家庭", systemImage: "person.2.fill")
                }

            NavigationStack {
                RecordsView()
            }
            .tabItem {
                Label("记录", systemImage: "list.clipboard.fill")
            }

            NavigationStack {
                AIView()
            }
            .tabItem {
                Label("AI 助手", systemImage: "brain.head.profile")
            }

            NavigationStack {
                SettingsView()
                    .environmentObject(authService)
            }
            .tabItem {
                Label("设置", systemImage: "gearshape.fill")
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthenticationService())
        .environmentObject(HealthKitService())
        .modelContainer(MockData.previewContainer)
}
