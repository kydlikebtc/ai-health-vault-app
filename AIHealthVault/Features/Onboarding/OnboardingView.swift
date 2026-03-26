import SwiftUI
import StoreKit

// MARK: - OnboardingView

/// 首次启动引导页面 — 展示 Premium 体验价值、试用倒计时和隐私承诺
/// 仅在用户首次安装后展示一次（通过 UserDefaults 记录）
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var subManager = SubscriptionManager.shared
    @State private var currentPage = 0
    @State private var isPurchasing = false

    private let totalPages = 3

    var body: some View {
        ZStack {
            // 背景渐变
            LinearGradient(
                colors: [Color.blue.opacity(0.08), Color(.systemBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // 页面内容
                TabView(selection: $currentPage) {
                    welcomePage.tag(0)
                    featuresPage.tag(1)
                    privacyPage.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: currentPage)

                // 页面指示器
                HStack(spacing: 8) {
                    ForEach(0..<totalPages, id: \.self) { index in
                        Capsule()
                            .fill(index == currentPage ? Color.blue : Color(.tertiarySystemFill))
                            .frame(width: index == currentPage ? 20 : 8, height: 8)
                            .animation(.spring(response: 0.3), value: currentPage)
                    }
                }
                .padding(.bottom, 24)

                // 底部操作区
                bottomActionArea
                    .padding(.horizontal, 24)
                    .padding(.bottom, 48)
            }
        }
    }

    // MARK: - Page 1: Welcome

    private var welcomePage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 80))
                .foregroundStyle(
                    LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .padding(.bottom, 8)

            VStack(spacing: 12) {
                Text("欢迎使用 AI Health Vault")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)

                Text("您的家庭健康数据，安全存储在设备本地。\nAI 为您解读报告，守护全家健康。")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .padding(.horizontal, 32)

            // 试用倒计时
            trialCountdownBadge

            Spacer()
            Spacer()
        }
    }

    // MARK: - Page 2: Features

    private var featuresPage: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("14 天内免费体验全部功能")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            VStack(spacing: 16) {
                FeatureHighlightRow(
                    icon: "waveform.path.ecg",
                    color: .blue,
                    title: "AI 报告解读",
                    description: "体检报告、血检结果自动解析，每月最多 50 次"
                )
                FeatureHighlightRow(
                    icon: "stethoscope",
                    color: .purple,
                    title: "就诊准备",
                    description: "根据症状和历史记录，智能生成就诊问题清单"
                )
                FeatureHighlightRow(
                    icon: "chart.xyaxis.line",
                    color: .green,
                    title: "健康趋势分析",
                    description: "血压、血糖等指标长期趋势，发现潜在风险"
                )
                FeatureHighlightRow(
                    icon: "person.2.fill",
                    color: .orange,
                    title: "家庭管理",
                    description: "最多 10 名家庭成员，全家健康一手掌握"
                )
            }
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    // MARK: - Page 3: Privacy

    private var privacyPage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            VStack(spacing: 12) {
                Text("您的数据，只属于您")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text("我们的隐私承诺")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                PrivacyPromiseRow(icon: "iphone", text: "所有健康数据存储在设备本地，不上传服务器")
                PrivacyPromiseRow(icon: "xmark.shield", text: "不售卖数据，不用于广告，绝无例外")
                PrivacyPromiseRow(icon: "cloud.fill", text: "iCloud 同步使用您自己的 Apple ID，我们无法访问")
                PrivacyPromiseRow(icon: "trash", text: "AI 处理时仅发送最小必要数据，处理后即丢弃")
            }
            .padding(.horizontal, 24)

            Text("符合 HIPRA 2025 健康数据保护法规")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            Spacer()
        }
    }

    // MARK: - Trial Countdown Badge

    private var trialCountdownBadge: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.badge.checkmark.fill")
                .foregroundStyle(.white)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text("14 天免费试用已激活")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                if case .reverseTrial(let days) = subManager.subscriptionStatus {
                    Text("剩余 \(days) 天 · 到期后自动降级为免费版")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                } else {
                    Text("立即体验全部 Premium 功能")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            LinearGradient(colors: [.blue, .blue.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 32)
    }

    // MARK: - Bottom Action Area

    private var bottomActionArea: some View {
        VStack(spacing: 12) {
            if currentPage < totalPages - 1 {
                Button {
                    withAnimation { currentPage += 1 }
                } label: {
                    Text("继续")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                // 最后一页：开始使用
                Button {
                    markOnboardingComplete()
                    dismiss()
                } label: {
                    Text("开始使用 · 免费试用 14 天")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    // 订阅后直接开始
                    Task {
                        if let product = subManager.product(for: .premiumAnnual) {
                            await subManager.purchase(product)
                        }
                        markOnboardingComplete()
                        dismiss()
                    }
                } label: {
                    Text("立即订阅 Premium")
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                }
            }

            // 已有账号 / 跳过
            Button {
                markOnboardingComplete()
                dismiss()
            } label: {
                Text(currentPage < totalPages - 1 ? "跳过" : "稍后订阅")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private func markOnboardingComplete() {
        UserDefaults.standard.set(true, forKey: OnboardingView.hasSeenOnboardingKey)
    }

    static let hasSeenOnboardingKey = "onboarding_has_seen_v1"
}

// MARK: - Supporting Views

private struct FeatureHighlightRow: View {
    let icon: String
    let color: Color
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct PrivacyPromiseRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.blue)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer()
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingView()
}
