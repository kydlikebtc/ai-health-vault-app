import SwiftUI
import SwiftData

// MARK: - 用药记录列表

struct MedicationListView: View {
    @Environment(\.modelContext) private var modelContext
    let member: Member

    @State private var searchText = ""
    @State private var showOnlyActive = false
    @State private var showingAdd = false
    @State private var recordToEdit: Medication?
    @State private var recordToDelete: Medication?
    @State private var showingDeleteAlert = false

    private var filteredMedications: [Medication] {
        var list = member.medications.sorted { $0.createdAt > $1.createdAt }
        if showOnlyActive {
            list = list.filter { $0.isActive }
        }
        guard !searchText.isEmpty else { return list }
        return list.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.prescribedBy.localizedCaseInsensitiveContains(searchText) ||
            $0.purpose.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        Group {
            if member.medications.isEmpty && searchText.isEmpty {
                ContentUnavailableView {
                    Label("暂无用药记录", systemImage: "pills.fill")
                } actions: {
                    Button("添加药物") { showingAdd = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    ForEach(filteredMedications) { med in
                        NavigationLink {
                            MedicationDetailView(medication: med, member: member)
                        } label: {
                            MedicationRow(medication: med)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                recordToDelete = med
                                showingDeleteAlert = true
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            Button {
                                recordToEdit = med
                            } label: {
                                Label("编辑", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                }
            }
        }
        .navigationTitle("用药记录")
        .searchable(text: $searchText, prompt: "搜索药物")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Toggle(isOn: $showOnlyActive) {
                    Text("仅在用")
                }
                .toggleStyle(.button)
                .tint(.green)
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showingAdd = true } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("添加药物")
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddEditMedicationView(member: member)
        }
        .sheet(item: $recordToEdit) { record in
            AddEditMedicationView(member: member, medication: record)
        }
        .alert("删除记录", isPresented: $showingDeleteAlert, presenting: recordToDelete) { record in
            Button("删除", role: .destructive) { modelContext.delete(record) }
            Button("取消", role: .cancel) {}
        } message: { record in
            Text("确定要删除「\(record.name)」的用药记录吗？")
        }
    }
}

// MARK: - 用药记录行

struct MedicationRow: View {
    let medication: Medication

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(medication.name)
                    .font(.headline)
                Spacer()
                StatusBadge(
                    title: medication.isActive ? "服用中" : "已停药",
                    color: medication.isActive ? .green : .secondary
                )
            }
            HStack(spacing: 8) {
                if !medication.dosage.isEmpty {
                    Label(medication.dosage, systemImage: "pills")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(medication.frequency.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !medication.prescribedBy.isEmpty {
                Label(medication.prescribedBy, systemImage: "person.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 用药记录详情

struct MedicationDetailView: View {
    let medication: Medication
    let member: Member
    @State private var showingEdit = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                DetailCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(medication.name)
                                .font(.title2.bold())
                            if !medication.purpose.isEmpty {
                                Text(medication.purpose)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        StatusBadge(
                            title: medication.isActive ? "服用中" : "已停药",
                            color: medication.isActive ? .green : .secondary
                        )
                    }
                }

                DetailCard {
                    if !medication.dosage.isEmpty {
                        DetailRow(label: "剂量", value: medication.dosage, icon: "pills")
                    }
                    DetailRow(label: "频率", value: medication.frequency.displayName, icon: "clock")
                    DetailRow(label: "开始日期", value: medication.startDate.localizedDateString, icon: "calendar")
                    if let endDate = medication.endDate {
                        DetailRow(label: "结束日期", value: endDate.localizedDateString, icon: "calendar.badge.checkmark")
                    }
                    if !medication.prescribedBy.isEmpty {
                        DetailRow(label: "开具医生", value: medication.prescribedBy, icon: "person.fill")
                    }
                }

                // 提醒状态卡片
                DetailCard {
                    HStack {
                        Label("用药提醒", systemImage: medication.reminderEnabled ? "bell.fill" : "bell.slash")
                            .font(.subheadline.bold())
                            .foregroundStyle(medication.reminderEnabled ? .orange : .secondary)
                        Spacer()
                        Text(medication.reminderEnabled ? "已开启" : "未开启")
                            .font(.caption)
                            .foregroundStyle(medication.reminderEnabled ? .orange : .secondary)
                    }
                    if medication.reminderEnabled {
                        let slots = [
                            (medication.reminderMorning, "早 08:00"),
                            (medication.reminderNoon,    "中 12:00"),
                            (medication.reminderEvening, "晚 20:00"),
                        ].filter(\.0).map(\.1)
                        if !slots.isEmpty {
                            Text(slots.joined(separator: "  ·  "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !medication.sideEffects.isEmpty {
                    DetailCard {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("已知副作用", systemImage: "exclamationmark.triangle")
                                .font(.caption.bold())
                                .foregroundStyle(.orange)
                            Text(medication.sideEffects)
                                .font(.body)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("药物详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("编辑") { showingEdit = true }
            }
        }
        .sheet(isPresented: $showingEdit) {
            AddEditMedicationView(member: member, medication: medication)
        }
    }
}

// MARK: - 用药记录添加/编辑表单

struct AddEditMedicationView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let member: Member
    let medication: Medication?

    @State private var name = ""
    @State private var dosage = ""
    @State private var frequency: MedicationFrequency = .daily
    @State private var startDate = Date()
    @State private var hasEndDate = false
    @State private var endDate = Date()
    @State private var prescribedBy = ""
    @State private var purpose = ""
    @State private var sideEffects = ""
    @State private var isActive = true
    @State private var reminderEnabled = false
    @State private var reminderMorning = true
    @State private var reminderNoon    = false
    @State private var reminderEvening = false
    @State private var showingValidationError = false

    init(member: Member, medication: Medication? = nil) {
        self.member = member
        self.medication = medication
    }

    private var isEditing: Bool { medication != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("药物信息") {
                    HStack {
                        Text("药品名称")
                        Spacer()
                        TextField("请输入药品名称", text: $name)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("剂量")
                        Spacer()
                        TextField("如：500mg", text: $dosage)
                            .multilineTextAlignment(.trailing)
                    }
                    Picker("服药频率", selection: $frequency) {
                        ForEach(MedicationFrequency.allCases, id: \.self) { f in
                            Text(f.displayName).tag(f)
                        }
                    }
                    .onChange(of: frequency) { _, newFreq in
                        applyDefaultReminderSlots(for: newFreq)
                    }
                }

                Section("时间") {
                    DatePicker("开始日期", selection: $startDate, in: ...Date(), displayedComponents: .date)
                    Toggle("设置结束日期", isOn: $hasEndDate)
                    if hasEndDate {
                        DatePicker("结束日期", selection: $endDate, in: startDate..., displayedComponents: .date)
                    }
                    Toggle("当前在服用", isOn: $isActive)
                }

                // 提醒设置（按需服药不支持自动提醒）
                if frequency != .asNeeded {
                    Section {
                        Toggle(isOn: $reminderEnabled) {
                            Label("开启用药提醒", systemImage: "bell")
                        }
                        .tint(.orange)

                        if reminderEnabled {
                            Toggle("早（08:00）", isOn: $reminderMorning)
                            Toggle("中（12:00）", isOn: $reminderNoon)
                            Toggle("晚（20:00）", isOn: $reminderEvening)
                        }
                    } header: {
                        Text("提醒设置")
                    } footer: {
                        if reminderEnabled {
                            Text("系统将在选定时间推送本地通知，通知中可标记"已服用"。")
                        }
                    }
                }

                Section("医疗信息") {
                    HStack {
                        Text("开具医生")
                        Spacer()
                        TextField("可选", text: $prescribedBy)
                            .multilineTextAlignment(.trailing)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("用途说明")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("描述用药目的...", text: $purpose, axis: .vertical)
                            .lineLimit(2, reservesSpace: true)
                    }
                    .padding(.vertical, 2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("副作用")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("已知副作用...", text: $sideEffects, axis: .vertical)
                            .lineLimit(2, reservesSpace: true)
                    }
                    .padding(.vertical, 2)
                }
            }
            .navigationTitle(isEditing ? "编辑药物" : "添加药物")
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
                Text("药品名称不能为空")
            }
        }
    }

    private func populateFields() {
        guard let m = medication else { return }
        name = m.name
        dosage = m.dosage
        frequency = m.frequency
        startDate = m.startDate
        hasEndDate = m.endDate != nil
        endDate = m.endDate ?? Date()
        prescribedBy = m.prescribedBy
        purpose = m.purpose
        sideEffects = m.sideEffects
        isActive = m.isActive
        reminderEnabled = m.reminderEnabled
        reminderMorning = m.reminderMorning
        reminderNoon = m.reminderNoon
        reminderEvening = m.reminderEvening
    }

    /// 切换频率时重置为该频率的默认提醒时段
    private func applyDefaultReminderSlots(for freq: MedicationFrequency) {
        let defaults = ReminderSlot.defaults(for: freq)
        reminderMorning = defaults.contains(.morning)
        reminderNoon    = defaults.contains(.noon)
        reminderEvening = defaults.contains(.evening)
    }

    private func saveAction() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            showingValidationError = true
            return
        }
        let target: Medication
        if let m = medication {
            m.name = trimmed
            m.dosage = dosage.trimmingCharacters(in: .whitespaces)
            m.frequency = frequency
            m.startDate = startDate
            m.endDate = hasEndDate ? endDate : nil
            m.prescribedBy = prescribedBy.trimmingCharacters(in: .whitespaces)
            m.purpose = purpose.trimmingCharacters(in: .whitespaces)
            m.sideEffects = sideEffects.trimmingCharacters(in: .whitespaces)
            m.isActive = isActive
            m.reminderEnabled = reminderEnabled
            m.reminderMorning = reminderMorning
            m.reminderNoon = reminderNoon
            m.reminderEvening = reminderEvening
            target = m
        } else {
            let newMed = Medication(
                name: trimmed,
                dosage: dosage.trimmingCharacters(in: .whitespaces),
                frequency: frequency,
                startDate: startDate,
                prescribedBy: prescribedBy.trimmingCharacters(in: .whitespaces)
            )
            newMed.endDate = hasEndDate ? endDate : nil
            newMed.purpose = purpose.trimmingCharacters(in: .whitespaces)
            newMed.sideEffects = sideEffects.trimmingCharacters(in: .whitespaces)
            newMed.isActive = isActive
            newMed.reminderEnabled = reminderEnabled
            newMed.reminderMorning = reminderMorning
            newMed.reminderNoon = reminderNoon
            newMed.reminderEvening = reminderEvening
            newMed.member = member
            modelContext.insert(newMed)
            target = newMed
        }

        // 异步调度或取消通知
        let memberName = member.name
        Task {
            if target.reminderEnabled && target.isActive {
                await MedicationNotificationService.shared.scheduleReminders(
                    for: target, memberName: memberName
                )
            } else {
                await MedicationNotificationService.shared.cancelReminders(for: target.id)
            }
        }

        dismiss()
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        MedicationListView(member: MockData.sampleMember)
    }
    .modelContainer(MockData.previewContainer)
}
