import SwiftUI
import SwiftData

/// AI 助手主页 — 接入 Claude API（Phase 3）
struct AIView: View {
    @Query(sort: \Member.name) private var members: [Member]
    @State private var selectedFeature: AIFeature?
    @State private var showAPIKeySetup = false

    private let aiMgr = AISettingsManager.shared

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

        /// 是否为 Claude AI 对话功能（false = 独立页面或 coming soon）
        var usesClaude: Bool {
            switch self {
            case .reportAnalysis, .visitPrep, .medicineInfo, .healthPlan: return true
            case .trendAnalysis: return false // 使用独立图表页面
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                statusBanner

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    ForEach(AIFeature.allCases) { feature in
                        AIFeatureCard(feature: feature, isAvailable: true) {
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
            if feature == .trendAnalysis {
                TrendMemberPickerView()
            } else if feature == .reportAnalysis {
                ReportAnalysisMemberPickerView()
            } else if feature == .visitPrep {
                VisitPrepMemberPickerView()
            } else if feature.usesClaude {
                let service: any AIService = aiMgr.makeAIService(
                    mockFallback: AIView.previewMock(for: feature)
                )
                AIConversationView(feature: feature, aiService: service)
            } else {
                AIFeaturePlaceholderView(feature: feature)
            }
        }
        .sheet(isPresented: $showAPIKeySetup) {
            AISettingsView()
        }
    }

    // MARK: - Mock 分发（Preview / 无 API Key 开发调试）

    /// 根据 AI 功能选择对应的 Mock 服务，使 Preview 展示与功能匹配的示例回复
    private static func previewMock(for feature: AIFeature) -> MockAIService {
        switch feature {
        case .reportAnalysis: return .reportAnalysisMock()
        case .visitPrep:      return .visitPrepMock()
        case .medicineInfo:   return .medicineInfoMock()
        case .healthPlan:     return .dailyPlanMock()
        case .trendAnalysis:  return .reportAnalysisMock() // trendAnalysis 走独立图表页，不进此路径
        }
    }

    // MARK: - Status Banner

    @ViewBuilder
    private var statusBanner: some View {
        if !aiMgr.isAIAvailable {
            Button { showAPIKeySetup = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: aiMgr.serviceMode == .serverProxy ? "lock.fill" : "key.fill")
                        .font(.title2)
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(aiMgr.serviceMode == .serverProxy ? "需要 Premium 订阅以启用 AI" : "配置 API Key 以启用 AI")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("点击此处前往设置")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .padding()
                .background(.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
        } else {
            HStack(spacing: 12) {
                Image(systemName: "brain.head.profile")
                    .font(.title2)
                    .foregroundStyle(.purple)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Claude AI 已就绪")
                        .font(.headline)
                    Text("本月已用 \(aiMgr.monthlyTotalTokens) tokens")
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
}

struct AIFeatureCard: View {
    let feature: AIView.AIFeature
    let isAvailable: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: feature.icon)
                        .font(.title2)
                        .foregroundStyle(feature.color)
                        .accessibilityHidden(true)
                    Spacer()
                    if isAvailable {
                        Text("已上线")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(feature.color.opacity(0.15))
                            .foregroundStyle(feature.color)
                            .clipShape(Capsule())
                    }
                }

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
            .opacity(isAvailable ? 1.0 : 0.75)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - AI Conversation View

/// 通用 Claude AI 对话界面 — 支持流式响应展示
struct AIConversationView: View {
    let feature: AIView.AIFeature
    let aiService: any AIService

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Member.name) private var members: [Member]

    @State private var selectedMember: Member?
    @State private var userInput: String = ""
    @State private var streamingResponse: String = ""
    @State private var isStreaming: Bool = false
    @State private var errorMessage: String?
    @State private var messages: [AIMessage] = []

    private let aiMgr = AISettingsManager.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !members.isEmpty {
                    memberPicker.padding(.horizontal).padding(.top, 12)
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(messages.enumerated()), id: \.offset) { _, msg in
                                MessageBubble(message: msg)
                            }
                            if isStreaming {
                                StreamingBubble(text: streamingResponse).id("streaming")
                            }
                            if let error = errorMessage {
                                ErrorBubble(message: error).id("error")
                            }
                        }
                        .padding()
                    }
                    .onChange(of: streamingResponse) { _, _ in
                        // 流式接收时不使用动画，避免高频 token 到达时动画积压导致卡顿
                        proxy.scrollTo("streaming", anchor: .bottom)
                    }
                }

                Divider()
                inputBar
            }
            .navigationTitle(feature.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private var memberPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(members) { member in
                    Button {
                        selectedMember = member
                    } label: {
                        Text(member.name)
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(selectedMember?.id == member.id ? feature.color : Color.secondary.opacity(0.1))
                            .foregroundStyle(selectedMember?.id == member.id ? .white : .primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 12) {
            TextField("输入问题…", text: $userInput, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 20))

            Button {
                Task { await sendMessage() }
            } label: {
                Image(systemName: isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(isStreaming ? .red : (userInput.isEmpty ? .secondary : feature.color))
            }
            .accessibilityLabel(isStreaming ? "停止生成" : "发送")
            .disabled(!isStreaming && userInput.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func sendMessage() async {
        let text = userInput.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        userInput = ""
        errorMessage = nil

        messages.append(AIMessage(role: .user, content: text))
        isStreaming = true
        streamingResponse = ""
        var fullResponse = ""

        do {
            let systemPrompt = buildSystemPrompt()
            for try await chunk in aiService.streamMessage(messages, systemPrompt: systemPrompt) {
                streamingResponse += chunk
                fullResponse += chunk
            }
            let assistantMsg = AIMessage(role: .assistant, content: fullResponse)
            messages.append(assistantMsg)
            // 记录 token 用量（估算）
            let usage = TokenUsage(inputTokens: text.count / 4, outputTokens: fullResponse.count / 4)
            await MainActor.run { aiMgr.recordUsage(usage) }
        } catch {
            errorMessage = error.localizedDescription
        }

        streamingResponse = ""
        isStreaming = false
    }

    private func buildSystemPrompt() -> String {
        let base: String
        switch feature {
        case .reportAnalysis: base = PromptLibrary.ReportAnalysis().systemPrompt
        case .visitPrep:      base = PromptLibrary.VisitPreparation().systemPrompt
        case .trendAnalysis:  base = PromptLibrary.TrendAnalysis().systemPrompt
        case .medicineInfo:   base = PromptLibrary.MedicineInfo().systemPrompt
        case .healthPlan:     base = PromptLibrary.DailyHealthPlan().systemPrompt
        }
        return base + memberContextSection()
    }

    /// 将选中成员的健康档案附加到系统提示词，让 AI 在整个对话中都有个性化上下文
    private func memberContextSection() -> String {
        guard let member = selectedMember else { return "" }
        var lines: [String] = ["\n\n---\n当前用户健康档案（仅供本次对话参考）："]
        lines.append("姓名：\(member.name)\(member.age.map { "，\($0)岁" } ?? "")")
        if member.bloodType != .unknown {
            lines.append("血型：\(member.bloodType.rawValue)")
        }
        if !member.allergies.isEmpty {
            lines.append("过敏原：\(member.allergies.joined(separator: "、"))")
        }
        let histories = member.medicalHistory.map(\.conditionName)
        if !histories.isEmpty {
            lines.append("既往病史：\(histories.joined(separator: "、"))")
        }
        let meds = member.medications.filter(\.isActive).map { m in
            m.dosage.isEmpty ? m.name : "\(m.name) \(m.dosage)"
        }
        if !meds.isEmpty {
            lines.append("当前用药：\(meds.joined(separator: "、"))")
        }
        if let latest = member.checkups.sorted(by: { $0.checkupDate > $1.checkupDate }).first,
           !latest.summary.isEmpty {
            lines.append("最近体检摘要：\(String(latest.summary.prefix(200)))")
        }
        lines.append("---")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Message Components

private struct MessageBubble: View {
    let message: AIMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }
            Text(message.content)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(message.role == .user ? Color.blue : Color.secondary.opacity(0.1))
                .foregroundStyle(message.role == .user ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            if message.role == .assistant { Spacer(minLength: 60) }
        }
    }
}

private struct StreamingBubble: View {
    let text: String

    var body: some View {
        HStack {
            (text.isEmpty
                ? AnyView(HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle().frame(width: 6, height: 6).foregroundStyle(.secondary).opacity(0.6)
                    }
                }
                .accessibilityLabel("AI 正在响应"))
                : AnyView(Text(text))
            )
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            Spacer(minLength: 60)
        }
    }
}

private struct ErrorBubble: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .accessibilityHidden(true)
            Text(message).font(.caption).foregroundStyle(.red)
        }
        .padding()
        .background(.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
