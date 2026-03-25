import SwiftUI
import SwiftData

// MARK: - 体检报告列表

struct CheckupListView: View {
    @Environment(\.modelContext) private var modelContext
    let member: Member

    @State private var searchText = ""
    @State private var showingAdd = false
    @State private var recordToEdit: CheckupReport?
    @State private var recordToDelete: CheckupReport?
    @State private var showingDeleteAlert = false

    private var filteredCheckups: [CheckupReport] {
        let sorted = member.checkups.sorted { $0.checkupDate > $1.checkupDate }
        guard !searchText.isEmpty else { return sorted }
        return sorted.filter {
            $0.reportTitle.localizedCaseInsensitiveContains(searchText) ||
            $0.hospitalName.localizedCaseInsensitiveContains(searchText) ||
            $0.summary.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        Group {
            if member.checkups.isEmpty && searchText.isEmpty {
                ContentUnavailableView {
                    Label("暂无体检报告", systemImage: "stethoscope")
                } actions: {
                    Button("添加报告") { showingAdd = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    ForEach(filteredCheckups) { report in
                        NavigationLink {
                            CheckupDetailView(report: report, member: member)
                        } label: {
                            CheckupRow(report: report)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                recordToDelete = report
                                showingDeleteAlert = true
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            Button {
                                recordToEdit = report
                            } label: {
                                Label("编辑", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                }
            }
        }
        .navigationTitle("体检报告")
        .searchable(text: $searchText, prompt: "搜索体检报告")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAdd = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddEditCheckupView(member: member)
        }
        .sheet(item: $recordToEdit) { record in
            AddEditCheckupView(member: member, report: record)
        }
        .alert("删除记录", isPresented: $showingDeleteAlert, presenting: recordToDelete) { record in
            Button("删除", role: .destructive) { modelContext.delete(record) }
            Button("取消", role: .cancel) {}
        } message: { record in
            Text("确定要删除「\(record.reportTitle.isEmpty ? "体检报告" : record.reportTitle)」吗？")
        }
    }
}

// MARK: - 体检报告行

struct CheckupRow: View {
    let report: CheckupReport

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(report.reportTitle.isEmpty ? "体检报告" : report.reportTitle)
                    .font(.headline)
                Spacer()
                if report.hasAbnormalItems {
                    StatusBadge(title: "有异常", color: .red)
                }
            }
            Label(report.checkupDate.localizedDateString, systemImage: "calendar")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !report.hospitalName.isEmpty {
                Label(report.hospitalName, systemImage: "building.2")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 体检报告详情

struct CheckupDetailView: View {
    let report: CheckupReport
    let member: Member
    @State private var showingEdit = false
    @State private var showingAIAnalysis = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                DetailCard {
                    HStack {
                        Text(report.reportTitle.isEmpty ? "体检报告" : report.reportTitle)
                            .font(.title2.bold())
                        Spacer()
                        if report.hasAbnormalItems {
                            StatusBadge(title: "有异常", color: .red)
                        }
                    }
                }

                DetailCard {
                    DetailRow(label: "体检日期", value: report.checkupDate.localizedDateString, icon: "calendar")
                    if !report.hospitalName.isEmpty {
                        DetailRow(label: "体检机构", value: report.hospitalName, icon: "building.2")
                    }
                }

                if !report.abnormalItems.isEmpty {
                    DetailCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("异常指标", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption.bold())
                                .foregroundStyle(.red)
                            ForEach(report.abnormalItems, id: \.self) { item in
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(.red)
                                        .frame(width: 6, height: 6)
                                    Text(item)
                                        .font(.body)
                                }
                            }
                        }
                    }
                }

                if !report.summary.isEmpty {
                    DetailCard {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("摘要/医生建议", systemImage: "doc.text")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Text(report.summary)
                                .font(.body)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("体检详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack {
                    Button {
                        showingAIAnalysis = true
                    } label: {
                        Label("AI 解读", systemImage: "brain.head.profile")
                    }
                    Button("编辑") { showingEdit = true }
                }
            }
        }
        .sheet(isPresented: $showingEdit) {
            AddEditCheckupView(member: member, report: report)
        }
        .sheet(isPresented: $showingAIAnalysis) {
            NavigationStack {
                ReportAnalysisFromReportView(report: report, member: member)
            }
        }
    }
}

// MARK: - 体检报告添加/编辑表单

struct AddEditCheckupView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let member: Member
    let report: CheckupReport?

    @State private var reportTitle = ""
    @State private var checkupDate = Date()
    @State private var hospitalName = ""
    @State private var summary = ""
    @State private var abnormalItemsText = ""
    @State private var showingValidationError = false

    init(member: Member, report: CheckupReport? = nil) {
        self.member = member
        self.report = report
    }

    private var isEditing: Bool { report != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    HStack {
                        Text("报告标题")
                        Spacer()
                        TextField("如：2025年度体检", text: $reportTitle)
                            .multilineTextAlignment(.trailing)
                    }
                    DatePicker("体检日期", selection: $checkupDate, in: ...Date(), displayedComponents: .date)
                    HStack {
                        Text("体检机构")
                        Spacer()
                        TextField("可选", text: $hospitalName)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section("异常指标") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("多个指标用换行分隔")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("如：总胆固醇偏高", text: $abnormalItemsText, axis: .vertical)
                            .lineLimit(4, reservesSpace: true)
                    }
                    .padding(.vertical, 2)
                }

                Section("摘要/医生建议") {
                    TextField("医生建议和整体评估...", text: $summary, axis: .vertical)
                        .lineLimit(4, reservesSpace: true)
                }
            }
            .navigationTitle(isEditing ? "编辑报告" : "添加报告")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEditing ? "保存" : "添加") { saveAction() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear { populateFields() }
            .alert("请检查输入", isPresented: $showingValidationError) {
                Button("好的") {}
            } message: {
                Text("报告标题不能为空")
            }
        }
    }

    private func populateFields() {
        guard let r = report else { return }
        reportTitle = r.reportTitle
        checkupDate = r.checkupDate
        hospitalName = r.hospitalName
        summary = r.summary
        abnormalItemsText = r.abnormalItems.joined(separator: "\n")
    }

    private func saveAction() {
        let trimmedTitle = reportTitle.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty else {
            showingValidationError = true
            return
        }
        let abnormalItems = abnormalItemsText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        if let r = report {
            r.reportTitle = trimmedTitle
            r.checkupDate = checkupDate
            r.hospitalName = hospitalName.trimmingCharacters(in: .whitespaces)
            r.summary = summary.trimmingCharacters(in: .whitespaces)
            r.abnormalItems = abnormalItems
        } else {
            let newReport = CheckupReport(
                checkupDate: checkupDate,
                hospitalName: hospitalName.trimmingCharacters(in: .whitespaces),
                reportTitle: trimmedTitle
            )
            newReport.summary = summary.trimmingCharacters(in: .whitespaces)
            newReport.abnormalItems = abnormalItems
            newReport.member = member
            modelContext.insert(newReport)
        }
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        CheckupListView(member: MockData.sampleMember)
    }
    .modelContainer(MockData.previewContainer)
}
