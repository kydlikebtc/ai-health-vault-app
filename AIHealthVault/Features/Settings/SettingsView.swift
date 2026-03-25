import SwiftUI
import SwiftData

/// 应用设置页
struct SettingsView: View {
    @EnvironmentObject private var authService: AuthenticationService
    @Query private var members: [Member]

    var body: some View {
        List {
            Section("账户") {
                LabeledContent("家庭成员数", value: "\(members.count)")
            }

            Section("安全") {
                HStack {
                    Label("生物认证", systemImage: "faceid")
                    Spacer()
                    Text(authService.biometricTypeName)
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }

                Button(role: .destructive) {
                    authService.lock()
                } label: {
                    Label("锁定应用", systemImage: "lock.fill")
                }
            }

            Section("关于") {
                LabeledContent("版本", value: appVersion)
                LabeledContent("构建", value: buildNumber)

                Link(destination: URL(string: "https://github.com/kydlikebtc/ai-health-vault-app")!) {
                    Label("源代码（GitHub）", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            }

            Section("隐私声明") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("数据隐私")
                        .font(.subheadline.bold())
                    Text("所有健康数据存储在您的设备本地。AI 分析时仅发送必要的最小数据集，绝不上传原始医疗记录。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("设置")
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(AuthenticationService())
    }
    .modelContainer(for: [Member.self], inMemory: true)
}
