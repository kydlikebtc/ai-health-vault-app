import SwiftUI
import SwiftData

// MARK: - 就医记录列表

struct VisitListView: View {
    @Environment(\.modelContext) private var modelContext
    let member: Member

    @State private var searchText = ""
    @State private var showingAdd = false
    @State private var recordToEdit: VisitRecord?
    @State private var recordToDelete: VisitRecord?
    @State private var showingDeleteAlert = false

    private var filteredVisits: [VisitRecord] {
        let sorted = member.visits.sorted { $0.visitDate > $1.visitDate }
        guard !searchText.isEmpty else { return sorted }
        return sorted.filter {
            $0.hospitalName.localizedCaseInsensitiveContains(searchText) ||
            $0.department.localizedCaseInsensitiveContains(searchText) ||
            $0.diagnosis.localizedCaseInsensitiveContains(searchText) ||
            $0.doctorName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        Group {
            if member.visits.isEmpty && searchText.isEmpty {
                ContentUnavailableView {
                    Label("暂无就医记录", systemImage: "cross.case.fill")
                } actions: {
                    Button("添加记录") { showingAdd = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    ForEach(filteredVisits) { visit in
                        NavigationLink {
                            VisitDetailView(visit: visit, member: member)
                        } label: {
                            VisitRow(visit: visit)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                recordToDelete = visit
                                showingDeleteAlert = true
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            Button {
                                recordToEdit = visit
                            } label: {
                                Label("编辑", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                }
            }
        }
        .navigationTitle("就医记录")
        .searchable(text: $searchText, prompt: "搜索就医记录")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAdd = true } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("添加就医记录")
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddEditVisitView(member: member)
        }
        .sheet(item: $recordToEdit) { record in
            AddEditVisitView(member: member, visit: record)
        }
        .alert("删除记录", isPresented: $showingDeleteAlert, presenting: recordToDelete) { record in
            Button("删除", role: .destructive) { modelContext.delete(record) }
            Button("取消", role: .cancel) {}
        } message: { record in
            Text("确定要删除这条就医记录吗？")
        }
    }
}

// MARK: - 就医记录行

struct VisitRow: View {
    let visit: VisitRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(visit.hospitalName.isEmpty ? "就医记录" : visit.hospitalName)
                    .font(.headline)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: visit.visitType.icon)
                        .accessibilityHidden(true)
                    Text(visit.visitType.displayName)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Label(visit.visitDate.localizedDateString, systemImage: "calendar")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !visit.department.isEmpty {
                Label(visit.department, systemImage: "stethoscope")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !visit.diagnosis.isEmpty {
                Text(visit.diagnosis)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 就医记录详情

struct VisitDetailView: View {
    let visit: VisitRecord
    let member: Member
    @State private var showingEdit = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                DetailCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(visit.hospitalName.isEmpty ? "就医记录" : visit.hospitalName)
                                .font(.title2.bold())
                            if !visit.department.isEmpty {
                                Text(visit.department)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            HStack(spacing: 4) {
                                Image(systemName: visit.visitType.icon)
                                    .accessibilityHidden(true)
                                Text(visit.visitType.displayName)
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }

                DetailCard {
                    DetailRow(label: "就诊日期", value: visit.visitDate.localizedDateString, icon: "calendar")
                    if !visit.doctorName.isEmpty {
                        DetailRow(label: "主治医生", value: visit.doctorName, icon: "person.fill")
                    }
                    if visit.cost > 0 {
                        DetailRow(label: "费用", value: String(format: "¥%.2f", visit.cost), icon: "yensign.circle")
                    }
                    if let followUp = visit.followUpDate {
                        DetailRow(label: "复诊日期", value: followUp.localizedDateString, icon: "calendar.badge.clock")
                    }
                }

                if !visit.chiefComplaint.isEmpty || !visit.diagnosis.isEmpty {
                    DetailCard {
                        if !visit.chiefComplaint.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Label("主诉", systemImage: "text.bubble")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                Text(visit.chiefComplaint)
                                    .font(.body)
                            }
                        }
                        if !visit.diagnosis.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Label("诊断结果", systemImage: "stethoscope")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                Text(visit.diagnosis)
                                    .font(.body)
                            }
                        }
                    }
                }

                if !visit.treatment.isEmpty || !visit.prescription.isEmpty {
                    DetailCard {
                        if !visit.treatment.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Label("治疗方案", systemImage: "cross.case")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                Text(visit.treatment)
                                    .font(.body)
                            }
                        }
                        if !visit.prescription.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Label("处方说明", systemImage: "pills")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                Text(visit.prescription)
                                    .font(.body)
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("就诊详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("编辑") { showingEdit = true }
            }
        }
        .sheet(isPresented: $showingEdit) {
            AddEditVisitView(member: member, visit: visit)
        }
    }
}

// MARK: - 就医记录添加/编辑表单

struct AddEditVisitView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let member: Member
    let visit: VisitRecord?

    @State private var visitDate = Date()
    @State private var visitType: VisitType = .outpatient
    @State private var hospitalName = ""
    @State private var department = ""
    @State private var doctorName = ""
    @State private var chiefComplaint = ""
    @State private var diagnosis = ""
    @State private var treatment = ""
    @State private var prescription = ""
    @State private var hasFollowUp = false
    @State private var followUpDate = Date()
    @State private var costText = ""
    @State private var showingValidationError = false

    init(member: Member, visit: VisitRecord? = nil) {
        self.member = member
        self.visit = visit
    }

    private var isEditing: Bool { visit != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    DatePicker("就诊日期", selection: $visitDate, in: ...Date(), displayedComponents: .date)
                    Picker("就诊类型", selection: $visitType) {
                        ForEach(VisitType.allCases, id: \.self) { type in
                            Label(type.displayName, systemImage: type.icon).tag(type)
                        }
                    }
                    HStack {
                        Text("医院名称")
                        Spacer()
                        TextField("请输入医院名称", text: $hospitalName)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("科室")
                        Spacer()
                        TextField("可选", text: $department)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("医生姓名")
                        Spacer()
                        TextField("可选", text: $doctorName)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section("诊疗内容") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("主诉")
                            .font(.caption).foregroundStyle(.secondary)
                        TextField("主要症状描述...", text: $chiefComplaint, axis: .vertical)
                            .lineLimit(2, reservesSpace: true)
                    }
                    .padding(.vertical, 2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("诊断结果")
                            .font(.caption).foregroundStyle(.secondary)
                        TextField("医生诊断...", text: $diagnosis, axis: .vertical)
                            .lineLimit(2, reservesSpace: true)
                    }
                    .padding(.vertical, 2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("治疗方案")
                            .font(.caption).foregroundStyle(.secondary)
                        TextField("治疗方案...", text: $treatment, axis: .vertical)
                            .lineLimit(2, reservesSpace: true)
                    }
                    .padding(.vertical, 2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("处方说明")
                            .font(.caption).foregroundStyle(.secondary)
                        TextField("处方详情...", text: $prescription, axis: .vertical)
                            .lineLimit(2, reservesSpace: true)
                    }
                    .padding(.vertical, 2)
                }

                Section("其他") {
                    HStack {
                        Text("费用（元）")
                        Spacer()
                        TextField("0", text: $costText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                    Toggle("设置复诊日期", isOn: $hasFollowUp)
                    if hasFollowUp {
                        DatePicker("复诊日期", selection: $followUpDate, in: visitDate..., displayedComponents: .date)
                    }
                }
            }
            .navigationTitle(isEditing ? "编辑记录" : "添加记录")
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
                Text("医院名称不能为空")
            }
        }
    }

    private func populateFields() {
        guard let v = visit else { return }
        visitDate = v.visitDate
        visitType = v.visitType
        hospitalName = v.hospitalName
        department = v.department
        doctorName = v.doctorName
        chiefComplaint = v.chiefComplaint
        diagnosis = v.diagnosis
        treatment = v.treatment
        prescription = v.prescription
        hasFollowUp = v.followUpDate != nil
        followUpDate = v.followUpDate ?? Date()
        costText = v.cost > 0 ? String(format: "%.2f", v.cost) : ""
    }

    private func saveAction() {
        let trimmedHospital = hospitalName.trimmingCharacters(in: .whitespaces)
        guard !trimmedHospital.isEmpty else {
            showingValidationError = true
            return
        }
        let cost = Double(costText.replacingOccurrences(of: ",", with: ".")) ?? 0

        if let v = visit {
            v.visitDate = visitDate
            v.visitType = visitType
            v.hospitalName = trimmedHospital
            v.department = department.trimmingCharacters(in: .whitespaces)
            v.doctorName = doctorName.trimmingCharacters(in: .whitespaces)
            v.chiefComplaint = chiefComplaint.trimmingCharacters(in: .whitespaces)
            v.diagnosis = diagnosis.trimmingCharacters(in: .whitespaces)
            v.treatment = treatment.trimmingCharacters(in: .whitespaces)
            v.prescription = prescription.trimmingCharacters(in: .whitespaces)
            v.followUpDate = hasFollowUp ? followUpDate : nil
            v.cost = cost
        } else {
            let newVisit = VisitRecord(
                visitDate: visitDate,
                visitType: visitType,
                hospitalName: trimmedHospital,
                department: department.trimmingCharacters(in: .whitespaces)
            )
            newVisit.doctorName = doctorName.trimmingCharacters(in: .whitespaces)
            newVisit.chiefComplaint = chiefComplaint.trimmingCharacters(in: .whitespaces)
            newVisit.diagnosis = diagnosis.trimmingCharacters(in: .whitespaces)
            newVisit.treatment = treatment.trimmingCharacters(in: .whitespaces)
            newVisit.prescription = prescription.trimmingCharacters(in: .whitespaces)
            newVisit.followUpDate = hasFollowUp ? followUpDate : nil
            newVisit.cost = cost
            newVisit.member = member
            modelContext.insert(newVisit)
        }
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        VisitListView(member: MockData.sampleMember)
    }
    .modelContainer(MockData.previewContainer)
}
