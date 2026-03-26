import SwiftUI
import SwiftData

/// 应用设置页
struct SettingsView: View {
    @EnvironmentObject private var authService: AuthenticationService
    @EnvironmentObject private var healthKitService: HealthKitService
    @Query private var members: [Member]

    @State private var showHealthKitAlert = false
    @State private var healthKitAlertMessage = ""

    // AI Settings
    @State private var showAISettings = false
    @State private var showPaywall = false
    @State private var subManager = SubscriptionManager.shared

    var body: some View {
        List {
            Section("账户") {
                LabeledContent("家庭成员数", value: "\(members.count)")
            }

            // MARK: - Subscription Section
            Section {
                subscriptionStatusRow

                if subManager.isPremiumActive {
                    Button {
                        if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack {
                            Label("管理订阅", systemImage: "arrow.up.right")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                } else {
                    Button {
                        showPaywall = true
                    } label: {
                        Label("升级到 Premium", systemImage: "crown.fill")
                            .foregroundStyle(.blue)
                    }
                }
            } header: {
                Text("订阅")
            }

            // MARK: - HealthKit Section
            Section {
                healthKitStatusRow
                if healthKitService.isAvailable {
                    if healthKitService.authorizationStatus == .notDetermined {
                        Button {
                            Task { await requestHealthKitAuth() }
                        } label: {
                            Label("连接 Apple Health", systemImage: "heart.text.square")
                        }
                    }
                    if let lastSync = healthKitService.lastSyncDate {
                        LabeledContent("上次同步", value: lastSync.localizedRelativeString)
                    }
                    if healthKitService.isSyncing {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("正在同步…").foregroundStyle(.secondary).font(.subheadline)
                        }
                    }
                }
            } header: {
                Text("Apple Health")
            } footer: {
                if !healthKitService.isAvailable {
                    Text("此设备或模拟器不支持 HealthKit")
                } else if healthKitService.authorizationStatus == .denied {
                    Text("已拒绝 Apple Health 权限。请前往「设置 → 健康 → 数据访问与设备」中重新授权")
                }
            }

            // MARK: - AI Section
            Section {
                Button {
                    showAISettings = true
                } label: {
                    HStack {
                        Label("Claude AI 配置", systemImage: "brain.head.profile")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                }
                .foregroundStyle(.primary)

                let aiMgr = AISettingsManager.shared
                Toggle("启用 AI 功能", isOn: Binding(
                    get: { aiMgr.isAIEnabled },
                    set: { aiMgr.isAIEnabled = $0 }
                ))

                // 服务端代理模式：展示 AI 服务模式和调用上限
                if aiMgr.serviceMode == .serverProxy && subManager.isPremiumActive {
                    LabeledContent("AI 模式", value: "服务端代理")
                    LabeledContent("本月调用上限", value: "50 次")
                } else if aiMgr.serviceMode == .byok && aiMgr.isAPIKeyConfigured {
                    LabeledContent("AI 模式", value: "BYOK")
                    LabeledContent("本月 Token 用量", value: "\(aiMgr.monthlyTotalTokens)")
                    LabeledContent("预估费用", value: aiMgr.estimatedMonthlyCostDisplay)
                }
            } header: {
                Text("AI 助手")
            } footer: {
                let aiMgr = AISettingsManager.shared
                if !aiMgr.isAIAvailable {
                    if aiMgr.serviceMode == .serverProxy {
                        Text("需要 Premium 订阅才能使用 AI 功能。请升级订阅或在 AI 配置中切换为 BYOK 模式。")
                    } else {
                        Text("未配置 API Key，AI 功能不可用。请点击上方进行配置。")
                    }
                }
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
        .sheet(isPresented: $showAISettings) {
            AISettingsView()
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .alert("HealthKit", isPresented: $showHealthKitAlert) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(healthKitAlertMessage)
        }
    }

    // MARK: - Subviews

    private var subscriptionStatusRow: some View {
        HStack {
            switch subManager.subscriptionStatus {
            case .subscribed(let productID):
                let isFamily = productID == SubscriptionProductID.familyAnnual.rawValue
                Image(systemName: isFamily ? "person.3.fill" : "crown.fill")
                    .foregroundStyle(.yellow)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Premium 已激活")
                    Text(isFamily ? "家庭年付" : (productID.contains("annual") ? "年付" : "月付"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .reverseTrial(let daysRemaining):
                Image(systemName: "clock.fill")
                    .foregroundStyle(.orange)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("免费试用中")
                    Text("剩余 \(daysRemaining) 天")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .free:
                Image(systemName: "crown")
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                Text("免费套餐")
            case .unknown:
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                Text("加载中…")
            }
        }
    }

    private var healthKitStatusRow: some View {
        HStack {
            Image(systemName: healthKitService.isAvailable
                  ? healthKitService.authorizationStatus.iconName
                  : "iphone.slash")
                .foregroundStyle(statusColor)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Apple Health 连接")
                    .font(.body)
                Text(healthKitService.isAvailable
                     ? healthKitService.authorizationStatus.displayName
                     : "不支持")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusColor: Color {
        guard healthKitService.isAvailable else { return .secondary }
        switch healthKitService.authorizationStatus {
        case .authorized:    return .green
        case .denied:        return .red
        case .restricted:    return .orange
        case .notDetermined: return .secondary
        }
    }

    // MARK: - Actions

    private func requestHealthKitAuth() async {
        do {
            try await healthKitService.requestAuthorization()
        } catch {
            healthKitAlertMessage = "授权失败：\(error.localizedDescription)"
            showHealthKitAlert = true
        }
    }

    // MARK: - Helpers

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}

// MARK: - Date Extension (local)

private extension Date {
    var localizedRelativeString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: self, relativeTo: .now)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(AuthenticationService())
            .environmentObject(HealthKitService())
    }
    .modelContainer(for: [Member.self], inMemory: true)
}
