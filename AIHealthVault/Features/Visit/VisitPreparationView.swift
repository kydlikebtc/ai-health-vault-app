import SwiftUI
import SwiftData

// MARK: - 就诊准备助手主视图

struct VisitPreparationView: View {
    let member: Member

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: VisitPreparationViewModel

    init(member: Member) {
        self.member = member
        self._viewModel = State(wrappedValue: VisitPreparationViewModel(member: member))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    inputSection
                    if viewModel.phase != .idle || !viewModel.result.isEmpty {
                        resultSection
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: viewModel.phase)
                .padding()
            }
            .navigationTitle("就诊准备")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                if !viewModel.result.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button("重新生成") {
                            Task { await viewModel.generate() }
                        }
                        .disabled(viewModel.phase == .generating)
                    }
                }
            }
        }
        .onAppear {
            viewModel.setModelContext(modelContext)
        }
    }

    // MARK: - 输入区域

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 成员信息摘要
            memberSummary

            // 就诊原因输入
            VStack(alignment: .leading, spacing: 8) {
                Label("本次就诊原因 / 主要症状", systemImage: "text.alignleft")
                    .font(.subheadline.bold())

                TextField("例如：最近头痛、血压偏高，想做一次全面检查…", text: $viewModel.visitPurpose, axis: .vertical)
                    .lineLimit(3...6)
                    .padding(12)
                    .background(.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            Button {
                Task { await viewModel.generate() }
            } label: {
                HStack {
                    if viewModel.phase == .generating {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .scaleEffect(0.85)
                    } else {
                        Image(systemName: "sparkles")
                            .accessibilityHidden(true)
                    }
                    Text(viewModel.phase == .generating ? "生成中…" : "生成就诊清单")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(viewModel.visitPurpose.trimmingCharacters(in: .whitespaces).isEmpty
                            ? Color.secondary.opacity(0.3) : Color.orange)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(viewModel.visitPurpose.trimmingCharacters(in: .whitespaces).isEmpty
                      || viewModel.phase == .generating)
        }
    }

    private var memberSummary: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(member.gender == .female ? Color.pink : .blue)
                .frame(width: 44, height: 44)
                .overlay {
                    Text(String(member.name.prefix(1)))
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(member.name)
                    .font(.headline)
                HStack(spacing: 4) {
                    if let age = member.age {
                        Text("\(age)岁")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !member.chronicConditions.isEmpty {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(member.chronicConditions.prefix(2).joined(separator: "、"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer()
        }
        .padding()
        .background(.blue.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - 结果区域

    @ViewBuilder
    private var resultSection: some View {
        switch viewModel.phase {
        case .generating:
            streamingPreview
        case .done:
            prepResultView
        case .failed(let msg):
            errorView(msg)
        case .idle:
            if !viewModel.result.isEmpty { prepResultView }
        }
    }

    private var streamingPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("AI 正在生成…", systemImage: "brain.head.profile")
                .font(.subheadline.bold())
                .foregroundStyle(.orange)
            Text(viewModel.streamingText.isEmpty ? "思考中…" : viewModel.streamingText)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.orange.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var prepResultView: some View {
        VStack(spacing: 12) {
            // 渲染 Markdown 结果
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("就诊准备清单", systemImage: "checklist")
                        .font(.subheadline.bold())
                    Spacer()
                    Text("已离线保存")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(viewModel.result)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.orange.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            Divider()

            // 就诊后快速录入
            postVisitEntrySection
        }
    }

    private func errorView(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .accessibilityHidden(true)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.red)
        }
        .padding()
        .background(.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - 就诊后快速录入

    private var postVisitEntrySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("就诊后快速记录", systemImage: "square.and.pencil")
                .font(.subheadline.bold())

            TextField("诊断结果…", text: $viewModel.postDiagnosis, axis: .vertical)
                .lineLimit(2...4)
                .padding(10)
                .background(.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            TextField("处方/医嘱…", text: $viewModel.postPrescription, axis: .vertical)
                .lineLimit(2...4)
                .padding(10)
                .background(.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            DatePicker("复诊日期（可选）", selection: $viewModel.postFollowUpDate,
                       in: Date()..., displayedComponents: .date)
                .font(.subheadline)

            Toggle("设置复诊提醒", isOn: $viewModel.postScheduleNotification)
                .font(.subheadline)
                .tint(.orange)

            Button {
                Task { await viewModel.savePostVisitRecord() }
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.down")
                        .accessibilityHidden(true)
                    Text("保存就诊记录")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(.green)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(viewModel.postDiagnosis.trimmingCharacters(in: .whitespaces).isEmpty)

            if viewModel.postSaveSuccess {
                Label("就诊记录已保存", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.subheadline)
                    .transition(.opacity)
            }
        }
    }
}

// MARK: - ViewModel

@Observable
@MainActor
final class VisitPreparationViewModel {

    enum Phase: Equatable {
        case idle
        case generating
        case done
        case failed(String)
    }

    // 输入
    var visitPurpose: String = ""

    // 输出
    var result: String = ""
    var streamingText: String = ""
    var phase: Phase = .idle

    // 就诊后快速录入
    var postDiagnosis: String = ""
    var postPrescription: String = ""
    var postFollowUpDate: Date = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
    var postScheduleNotification: Bool = true
    var postSaveSuccess: Bool = false

    private let member: Member
    private let aiService: any AIService
    private var modelContext: ModelContext?

    init(member: Member, aiService: (any AIService)? = nil) {
        self.member = member
        if let provided = aiService {
            self.aiService = provided
        } else {
            self.aiService = AISettingsManager.shared.makeAIService(
                mockFallback: MockAIService.visitPrepMock()
            )
        }
    }

    func setModelContext(_ ctx: ModelContext) {
        self.modelContext = ctx
    }

    // MARK: - 生成就诊清单

    func generate() async {
        let purpose = visitPurpose.trimmingCharacters(in: .whitespaces)
        guard !purpose.isEmpty else { return }

        phase = .generating
        streamingText = ""
        result = ""

        let template = PromptLibrary.VisitPreparation()
        let recentCheckup = member.checkups
            .sorted { $0.checkupDate > $1.checkupDate }
            .prefix(1)
            .map { r in
                let items = r.abnormalItems.isEmpty ? "无异常" : r.abnormalItems.joined(separator: "、")
                return "\(r.reportTitle)（\(r.checkupDate.localizedDateString)）：异常指标 — \(items)"
            }
            .first

        let context = PromptContext(
            memberName: member.name,
            memberAge: member.age,
            medicalHistory: member.chronicConditions,
            currentMedications: member.medications.map(\.name),
            recentCheckupSummary: recentCheckup,
            userQuery: purpose
        )
        let message = AIMessage(role: .user, content: template.buildUserMessage(context: context))

        var fullText = ""
        do {
            for try await chunk in aiService.streamMessage([message], systemPrompt: template.systemPrompt) {
                streamingText += chunk
                fullText += chunk
            }
            result = fullText
            phase = .done

            // 缓存到 SwiftData（离线查看）
            if let ctx = modelContext {
                let prep = CachedVisitPrep(
                    memberName: member.name,
                    purpose: purpose,
                    result: fullText
                )
                ctx.insert(prep)
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }

        streamingText = ""
        AISettingsManager.shared.recordUsage(
            TokenUsage(inputTokens: message.content.count / 4, outputTokens: fullText.count / 4)
        )
    }

    // MARK: - 保存就诊后记录

    func savePostVisitRecord() async {
        guard let ctx = modelContext else { return }

        let diagnosis = postDiagnosis.trimmingCharacters(in: .whitespaces)
        guard !diagnosis.isEmpty else { return }

        let newVisit = VisitRecord(visitDate: Date(), visitType: .outpatient)
        newVisit.diagnosis = diagnosis
        newVisit.prescription = postPrescription.trimmingCharacters(in: .whitespaces)
        newVisit.chiefComplaint = visitPurpose.trimmingCharacters(in: .whitespaces)
        newVisit.followUpDate = postFollowUpDate
        newVisit.member = member
        ctx.insert(newVisit)

        // 调度复诊通知
        if postScheduleNotification {
            await FollowUpNotificationService.shared.scheduleNotification(
                for: newVisit,
                memberName: member.name
            )
        }

        withAnimation { postSaveSuccess = true }
        try? await Task.sleep(for: .seconds(2))
        withAnimation { postSaveSuccess = false }
    }
}

// MARK: - 就诊准备结果缓存（SwiftData，供离线查看）

@Model
final class CachedVisitPrep {
    @Attribute(.unique) var id: UUID
    var memberName: String
    var purpose: String
    var result: String
    var createdAt: Date

    init(memberName: String, purpose: String, result: String) {
        self.id = UUID()
        self.memberName = memberName
        self.purpose = purpose
        self.result = result
        self.createdAt = Date()
    }
}

// MARK: - 成员选择入口

struct VisitPrepMemberPickerView: View {
    @Query(sort: \Member.name) private var members: [Member]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            Group {
                if members.isEmpty {
                    ContentUnavailableView(
                        "暂无家庭成员",
                        systemImage: "person.2.slash",
                        description: Text("请先在「家庭」页面添加成员")
                    )
                } else {
                    List(members) { member in
                        NavigationLink {
                            VisitPreparationViewWithContext(member: member)
                        } label: {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(member.gender == .female ? Color.pink : .blue)
                                    .frame(width: 40, height: 40)
                                    .overlay {
                                        Text(String(member.name.prefix(1)))
                                            .font(.headline.bold())
                                            .foregroundStyle(.white)
                                    }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(member.name)
                                        .font(.body.bold())
                                    if let age = member.age {
                                        Text("\(age)岁 · \(member.gender.displayName)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("选择成员")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}

/// 注入 ModelContext 的包装视图
struct VisitPreparationViewWithContext: View {
    let member: Member
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VisitPreparationView(member: member)
            .onAppear {
                // ViewModel 通过 onAppear 获取 modelContext
            }
    }
}
