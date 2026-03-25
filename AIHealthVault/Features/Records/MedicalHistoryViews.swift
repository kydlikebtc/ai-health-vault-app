import SwiftUI
import SwiftData

// MARK: - 既往病史列表

struct MedicalHistoryListView: View {
    @Environment(\.modelContext) private var modelContext
    let member: Member

    @State private var searchText = ""
    @State private var showingAdd = false
    @State private var recordToEdit: MedicalHistory?
    @State private var recordToDelete: MedicalHistory?
    @State private var showingDeleteAlert = false

    private var filteredHistory: [MedicalHistory] {
        let sorted = member.medicalHistory.sorted { $0.createdAt > $1.createdAt }
        guard !searchText.isEmpty else { return sorted }
        return sorted.filter {
            $0.conditionName.localizedCaseInsensitiveContains(searchText) ||
            $0.hospitalName.localizedCaseInsensitiveContains(searchText) ||
            $0.treatmentSummary.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        Group {
            if member.medicalHistory.isEmpty && searchText.isEmpty {
                ContentUnavailableView {
                    Label("暂无既往病史", systemImage: "clock.badge.fill")
                } actions: {
                    Button("添加病史") { showingAdd = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    ForEach(filteredHistory) { history in
                        NavigationLink {
                            MedicalHistoryDetailView(history: history, member: member)
                        } label: {
                            MedicalHistoryRow(history: history)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                recordToDelete = history
                                showingDeleteAlert = true
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            Button {
                                recordToEdit = history
                            } label: {
                                Label("编辑", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                }
            }
        }
        .navigationTitle("既往病史")
        .searchable(text: $searchText, prompt: "搜索病史")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAdd = true } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("添加病史")
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddEditMedicalHistoryView(member: member)
        }
        .sheet(item: $recordToEdit) { record in
            AddEditMedicalHistoryView(member: member, record: record)
        }
        .alert("删除记录", isPresented: $showingDeleteAlert, presenting: recordToDelete) { record in
            Button("删除", role: .destructive) { modelContext.delete(record) }
            Button("取消", role: .cancel) {}
        } message: { record in
            Text("确定要删除「\(record.conditionName)」的病史记录吗？")
        }
    }
}

// MARK: - 既往病史行

struct MedicalHistoryRow: View {
    let history: MedicalHistory

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(history.conditionName)
                    .font(.headline)
                Spacer()
                if history.isChronic {
                    StatusBadge(title: "慢性病", color: .orange)
                }
                if history.isResolved {
                    StatusBadge(title: "已痊愈", color: .green)
                }
            }
            if let date = history.diagnosedDate {
                Label(date.localizedDateString, systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !history.hospitalName.isEmpty {
                Label(history.hospitalName, systemImage: "building.2")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 既往病史详情

struct MedicalHistoryDetailView: View {
    let history: MedicalHistory
    let member: Member
    @State private var showingEdit = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                DetailCard {
                    HStack {
                        Text(history.conditionName)
                            .font(.title2.bold())
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            if history.isChronic {
                                StatusBadge(title: "慢性病", color: .orange)
                            }
                            if history.isResolved {
                                StatusBadge(title: "已痊愈", color: .green)
                            }
                        }
                    }
                }

                DetailCard {
                    if let diagDate = history.diagnosedDate {
                        DetailRow(label: "确诊日期", value: diagDate.localizedDateString, icon: "calendar")
                    }
                    if let resolvedDate = history.resolvedDate {
                        DetailRow(label: "痊愈日期", value: resolvedDate.localizedDateString, icon: "calendar.badge.checkmark")
                    }
                    if !history.hospitalName.isEmpty {
                        DetailRow(label: "就诊医院", value: history.hospitalName, icon: "building.2")
                    }
                    if !history.doctorName.isEmpty {
                        DetailRow(label: "主治医生", value: history.doctorName, icon: "person.fill")
                    }
                    if !history.treatmentSummary.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("治疗摘要", systemImage: "doc.text")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Text(history.treatmentSummary)
                                .font(.body)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("病史详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("编辑") { showingEdit = true }
            }
        }
        .sheet(isPresented: $showingEdit) {
            AddEditMedicalHistoryView(member: member, record: history)
        }
    }
}

// MARK: - 既往病史添加/编辑表单

struct AddEditMedicalHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let member: Member
    let record: MedicalHistory?

    @State private var conditionName = ""
    @State private var hasDiagnosedDate = false
    @State private var diagnosedDate = Date()
    @State private var hasResolvedDate = false
    @State private var resolvedDate = Date()
    @State private var hospitalName = ""
    @State private var doctorName = ""
    @State private var treatmentSummary = ""
    @State private var isChronic = false
    @State private var showingValidationError = false

    init(member: Member, record: MedicalHistory? = nil) {
        self.member = member
        self.record = record
    }

    private var isEditing: Bool { record != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    HStack {
                        Text("病症名称")
                        Spacer()
                        TextField("请输入病症名称", text: $conditionName)
                            .multilineTextAlignment(.trailing)
                    }
                    Toggle("慢性病", isOn: $isChronic)
                }

                Section("时间") {
                    Toggle("设置确诊日期", isOn: $hasDiagnosedDate)
                    if hasDiagnosedDate {
                        DatePicker("确诊日期", selection: $diagnosedDate, in: ...Date(), displayedComponents: .date)
                    }
                    Toggle("已痊愈", isOn: $hasResolvedDate)
                    if hasResolvedDate {
                        DatePicker("痊愈日期", selection: $resolvedDate, in: ...Date(), displayedComponents: .date)
                    }
                }

                Section("医疗信息") {
                    HStack {
                        Text("就诊医院")
                        Spacer()
                        TextField("可选", text: $hospitalName)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("主治医生")
                        Spacer()
                        TextField("可选", text: $doctorName)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section("治疗摘要") {
                    TextField("描述治疗过程和结果...", text: $treatmentSummary, axis: .vertical)
                        .lineLimit(4, reservesSpace: true)
                }
            }
            .navigationTitle(isEditing ? "编辑病史" : "添加病史")
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
                Text("病症名称不能为空")
            }
        }
    }

    private func populateFields() {
        guard let r = record else { return }
        conditionName = r.conditionName
        isChronic = r.isChronic
        hasDiagnosedDate = r.diagnosedDate != nil
        diagnosedDate = r.diagnosedDate ?? Date()
        hasResolvedDate = r.resolvedDate != nil
        resolvedDate = r.resolvedDate ?? Date()
        hospitalName = r.hospitalName
        doctorName = r.doctorName
        treatmentSummary = r.treatmentSummary
    }

    private func saveAction() {
        let trimmed = conditionName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            showingValidationError = true
            return
        }
        if let r = record {
            r.conditionName = trimmed
            r.isChronic = isChronic
            r.diagnosedDate = hasDiagnosedDate ? diagnosedDate : nil
            r.resolvedDate = hasResolvedDate ? resolvedDate : nil
            r.hospitalName = hospitalName.trimmingCharacters(in: .whitespaces)
            r.doctorName = doctorName.trimmingCharacters(in: .whitespaces)
            r.treatmentSummary = treatmentSummary.trimmingCharacters(in: .whitespaces)
        } else {
            let newRecord = MedicalHistory(
                conditionName: trimmed,
                diagnosedDate: hasDiagnosedDate ? diagnosedDate : nil,
                hospitalName: hospitalName.trimmingCharacters(in: .whitespaces),
                treatmentSummary: treatmentSummary.trimmingCharacters(in: .whitespaces),
                isChronic: isChronic
            )
            newRecord.doctorName = doctorName.trimmingCharacters(in: .whitespaces)
            newRecord.resolvedDate = hasResolvedDate ? resolvedDate : nil
            newRecord.member = member
            modelContext.insert(newRecord)
        }
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        MedicalHistoryListView(member: MockData.sampleMember)
    }
    .modelContainer(MockData.previewContainer)
}
