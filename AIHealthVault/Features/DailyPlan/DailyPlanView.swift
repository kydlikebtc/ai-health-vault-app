import SwiftUI
import SwiftData

// MARK: - 每日健康计划卡片（嵌入 MemberDetailView）

struct DailyPlanCard: View {
    let member: Member
    @EnvironmentObject private var healthKitService: HealthKitService

    @Environment(\.modelContext) private var modelContext
    @State private var todayPlan: DailyPlan?
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var showingDetail = false
    @State private var showingHistory = false

    private let aiMgr = AISettingsManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            planContent
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .onAppear { loadTodayPlan() }
        .sheet(isPresented: $showingDetail) {
            if let plan = todayPlan {
                DailyPlanDetailView(plan: plan)
            }
        }
        .sheet(isPresented: $showingHistory) {
            DailyPlanHistoryView(member: member)
        }
    }

    // MARK: - 标题栏

    private var header: some View {
        HStack {
            Label("今日健康计划", systemImage: "heart.text.clipboard")
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer()
            Button {
                showingHistory = true
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - 计划内容区

    @ViewBuilder
    private var planContent: some View {
        if isGenerating {
            HStack(spacing: 12) {
                ProgressView()
                Text("AI 正在生成今日计划…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()
        } else if let plan = todayPlan {
            VStack(alignment: .leading, spacing: 10) {
                // 摘要（前 150 字）
                Text(planSummary(plan.content))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                HStack {
                    Text(plan.generatedAt, style: .relative) + Text(" 前生成")
                    Spacer()
                    Button("查看详情") { showingDetail = true }
                        .font(.subheadline)
                        .foregroundStyle(.accentColor)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let err = errorMessage {
                    Text(err).font(.caption).foregroundStyle(.red)
                }

                generateButton(label: "重新生成", icon: "arrow.clockwise")
            }
            .padding(16)
        } else {
            VStack(spacing: 12) {
                if let err = errorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
                generateButton(label: "生成今日计划", icon: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .padding()
        }
    }

    private func generateButton(label: String, icon: String) -> some View {
        Button {
            Task { await generatePlan() }
        } label: {
            Label(label, systemImage: icon)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.tint.opacity(0.1))
                .foregroundStyle(.tint)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .disabled(isGenerating)
    }

    // MARK: - 操作

    private func loadTodayPlan() {
        let today = Calendar.current.startOfDay(for: Date())
        todayPlan = member.dailyPlans
            .filter { Calendar.current.isDate($0.planDate, inSameDayAs: today) }
            .sorted { $0.generatedAt > $1.generatedAt }
            .first
    }

    private func generatePlan() async {
        guard !isGenerating else { return }
        isGenerating = true
        errorMessage = nil

        let aiService: any AIService = aiMgr.isAPIKeyConfigured && aiMgr.isAIEnabled
            ? ClaudeService.shared
            : MockAIService.dailyPlanMock()

        do {
            let summary: HealthKitTodaySummary? = try? await healthKitService.fetchTodaySummary()
            let content = try await DailyHealthPlanService.shared.generatePlan(
                for: member,
                healthKitSummary: summary,
                aiService: aiService
            )
            let plan = DailyPlan(planDate: Date(), content: content)
            plan.member = member
            modelContext.insert(plan)
            todayPlan = plan
        } catch {
            errorMessage = "生成失败：\(error.localizedDescription)"
        }
        isGenerating = false
    }

    private func planSummary(_ content: String) -> String {
        let stripped = content
            .replacingOccurrences(of: "##", with: "")
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "*", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(stripped.prefix(150))
    }
}

// MARK: - 计划详情视图

struct DailyPlanDetailView: View {
    @Bindable var plan: DailyPlan
    @Environment(\.dismiss) private var dismiss

    private let actionKeys = ["exercise", "diet", "medication", "sleep", "checkup"]
    private let actionLabels: [String: String] = [
        "exercise":   "运动建议",
        "diet":       "今日饮食",
        "medication": "用药提醒",
        "sleep":      "睡眠休息",
        "checkup":    "复查事项",
    ]
    private let actionIcons: [String: String] = [
        "exercise":   "figure.walk",
        "diet":       "fork.knife",
        "medication": "pills",
        "sleep":      "moon.zzz",
        "checkup":    "cross.case",
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 生成信息
                    HStack {
                        Label(plan.generatedAt.formatted(date: .abbreviated, time: .shortened),
                              systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(plan.completedActions.count)/\(actionKeys.count) 完成")
                            .font(.caption.bold())
                            .foregroundStyle(.green)
                    }
                    .padding(.horizontal)

                    // 计划内容（Markdown 渲染）
                    planContentView
                        .padding(.horizontal)

                    // 打卡区
                    VStack(alignment: .leading, spacing: 8) {
                        Text("今日打卡")
                            .font(.headline)
                            .padding(.horizontal)

                        ForEach(actionKeys, id: \.self) { key in
                            checkInRow(key: key)
                        }
                    }
                    .padding(.bottom)
                }
                .padding(.top)
            }
            .navigationTitle("今日健康计划")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var planContentView: some View {
        if let attributed = try? AttributedString(markdown: plan.content,
                                                   options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            Text(attributed)
                .font(.body)
        } else {
            Text(plan.content)
                .font(.body)
        }
    }

    private func checkInRow(key: String) -> some View {
        let done = plan.completedActions.contains(key)
        return Button {
            plan.toggleAction(key)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(done ? .green : .secondary)
                Label(actionLabels[key] ?? key,
                      systemImage: actionIcons[key] ?? "checkmark")
                    .font(.subheadline)
                    .foregroundStyle(done ? .secondary : .primary)
                    .strikethrough(done)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 历史计划视图

struct DailyPlanHistoryView: View {
    let member: Member
    @Environment(\.dismiss) private var dismiss

    private var sortedPlans: [DailyPlan] {
        member.dailyPlans.sorted { $0.planDate > $1.planDate }
    }

    var body: some View {
        NavigationStack {
            Group {
                if sortedPlans.isEmpty {
                    ContentUnavailableView(
                        "暂无历史计划",
                        systemImage: "calendar.badge.clock",
                        description: Text("生成计划后会在这里保存历史记录")
                    )
                } else {
                    List(sortedPlans) { plan in
                        NavigationLink {
                            DailyPlanDetailView(plan: plan)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(plan.planDate, style: .date)
                                    .font(.subheadline.bold())
                                Text("\(plan.completedActions.count) 项已完成")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("历史计划")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}
