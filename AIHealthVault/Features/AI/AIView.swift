import SwiftUI
import SwiftData

/// AI 助手主页 — Phase 3 将接入 Claude API
struct AIView: View {
    @Query(sort: \Member.name) private var members: [Member]
    @State private var selectedFeature: AIFeature?

    enum AIFeature: String, CaseIterable, Identifiable {
        case reportAnalysis = "报告解读"
        case trendAnalysis = "趋势分析"
        case visitPrep = "就诊准备"
        case medicineInfo = "药物识别"
        case healthPlan = "每日健康计划"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .reportAnalysis: return "doc.text.magnifyingglass"
            case .trendAnalysis: return "chart.line.uptrend.xyaxis"
            case .visitPrep: return "stethoscope"
            case .medicineInfo: return "pills.fill"
            case .healthPlan: return "calendar.badge.checkmark"
            }
        }

        var color: Color {
            switch self {
            case .reportAnalysis: return .blue
            case .trendAnalysis: return .green
            case .visitPrep: return .orange
            case .medicineInfo: return .purple
            case .healthPlan: return .teal
            }
        }

        var description: String {
            switch self {
            case .reportAnalysis: return "拍照上传体检报告，AI 提取关键指标并用通俗语言解释"
            case .trendAnalysis: return "分析健康指标历史变化趋势，发现潜在风险"
            case .visitPrep: return "根据症状和历史记录生成就诊清单"
            case .medicineInfo: return "识别药物，查询相互作用，生成用药提醒"
            case .healthPlan: return "基于综合健康数据生成个性化每日健康建议"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                comingSoonBanner

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    ForEach(AIFeature.allCases) { feature in
                        AIFeatureCard(feature: feature) {
                            selectedFeature = feature
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle("AI 助手")
        .sheet(item: $selectedFeature) { feature in
            AIFeaturePlaceholderView(feature: feature)
        }
    }

    private var comingSoonBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "brain.head.profile")
                .font(.title2)
                .foregroundStyle(.purple)
            VStack(alignment: .leading, spacing: 2) {
                Text("Claude AI 即将上线")
                    .font(.headline)
                Text("Phase 3 将集成 Anthropic Claude API")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(.purple.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}

struct AIFeatureCard: View {
    let feature: AIView.AIFeature
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: feature.icon)
                    .font(.title2)
                    .foregroundStyle(feature.color)

                Text(feature.rawValue)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)

                Text(feature.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(feature.color.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

struct AIFeaturePlaceholderView: View {
    let feature: AIView.AIFeature
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: feature.icon)
                    .font(.system(size: 60))
                    .foregroundStyle(feature.color)

                Text(feature.rawValue)
                    .font(.title2.bold())

                Text(feature.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Text("此功能将在 Phase 3（Claude API 集成）阶段实现")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding()
                    .background(.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding()
            .navigationTitle(feature.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        AIView()
    }
    .modelContainer(for: [Member.self], inMemory: true)
}
