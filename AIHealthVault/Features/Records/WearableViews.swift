import SwiftUI
import SwiftData

// MARK: - 体征数据列表

struct WearableListView: View {
    @Environment(\.modelContext) private var modelContext
    let member: Member

    @State private var searchText = ""
    @State private var selectedMetricType: WearableMetricType?
    @State private var showingAdd = false
    @State private var recordToEdit: WearableEntry?
    @State private var recordToDelete: WearableEntry?
    @State private var showingDeleteAlert = false

    private var filteredEntries: [WearableEntry] {
        var list = member.wearableData.sorted { $0.recordedAt > $1.recordedAt }
        if let type = selectedMetricType {
            list = list.filter { $0.metricType == type }
        }
        guard !searchText.isEmpty else { return list }
        return list.filter {
            $0.metricType.displayName.localizedCaseInsensitiveContains(searchText) ||
            $0.source.localizedCaseInsensitiveContains(searchText) ||
            $0.notes.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        Group {
            if member.wearableData.isEmpty && searchText.isEmpty {
                ContentUnavailableView {
                    Label("暂无体征数据", systemImage: "applewatch")
                } actions: {
                    Button("添加数据") { showingAdd = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    ForEach(filteredEntries) { entry in
                        WearableRow(entry: entry)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    recordToDelete = entry
                                    showingDeleteAlert = true
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                                Button {
                                    recordToEdit = entry
                                } label: {
                                    Label("编辑", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                    }
                }
            }
        }
        .navigationTitle("体征数据")
        .searchable(text: $searchText, prompt: "搜索体征记录")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button("全部") { selectedMetricType = nil }
                    Divider()
                    ForEach(WearableMetricType.allCases, id: \.self) { type in
                        Button {
                            selectedMetricType = type
                        } label: {
                            HStack {
                                Text(type.displayName)
                                if selectedMetricType == type {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                        Text(selectedMetricType?.displayName ?? "筛选")
                            .font(.subheadline)
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showingAdd = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddEditWearableView(member: member)
        }
        .sheet(item: $recordToEdit) { record in
            AddEditWearableView(member: member, entry: record)
        }
        .alert("删除记录", isPresented: $showingDeleteAlert, presenting: recordToDelete) { record in
            Button("删除", role: .destructive) { modelContext.delete(record) }
            Button("取消", role: .cancel) {}
        } message: { _ in
            Text("确定要删除这条体征数据吗？")
        }
    }
}

// MARK: - 体征数据行

struct WearableRow: View {
    let entry: WearableEntry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.metricType.icon)
                .font(.title3)
                .foregroundStyle(.green)
                .frame(width: 36, height: 36)
                .background(.green.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.metricType.displayName)
                    .font(.headline)
                HStack(spacing: 8) {
                    Text(entry.recordedAt.localizedDateString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !entry.source.isEmpty && entry.source != "手动录入" {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(entry.source)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            Text(entry.displayValue)
                .font(.subheadline.monospacedDigit().bold())
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 体征数据添加/编辑表单

struct AddEditWearableView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let member: Member
    let entry: WearableEntry?

    @State private var metricType: WearableMetricType = .heartRate
    @State private var valueText = ""
    @State private var secondaryValueText = ""
    @State private var recordedAt = Date()
    @State private var source = "手动录入"
    @State private var notes = ""
    @State private var showingValidationError = false
    @State private var validationMessage = ""

    init(member: Member, entry: WearableEntry? = nil) {
        self.member = member
        self.entry = entry
    }

    private var isEditing: Bool { entry != nil }
    private var isBloodPressure: Bool { metricType == .bloodPressure }

    private let sourceOptions = ["手动录入", "Apple Watch", "血压计", "血糖仪", "体重秤", "其他设备"]

    var body: some View {
        NavigationStack {
            Form {
                Section("指标类型") {
                    Picker("类型", selection: $metricType) {
                        ForEach(WearableMetricType.allCases, id: \.self) { type in
                            HStack {
                                Image(systemName: type.icon)
                                Text(type.displayName)
                            }
                            .tag(type)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                Section("数值（\(metricType.unit)）") {
                    if isBloodPressure {
                        HStack {
                            Text("收缩压")
                            Spacer()
                            TextField("mmHg", text: $valueText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                        HStack {
                            Text("舒张压")
                            Spacer()
                            TextField("mmHg", text: $secondaryValueText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                    } else {
                        HStack {
                            Text(metricType.displayName)
                            Spacer()
                            TextField(metricType.unit, text: $valueText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                            Text(metricType.unit)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("记录信息") {
                    DatePicker("记录时间", selection: $recordedAt, in: ...Date())
                    Picker("数据来源", selection: $source) {
                        ForEach(sourceOptions, id: \.self) { s in
                            Text(s).tag(s)
                        }
                    }
                }

                Section("备注") {
                    TextField("可选备注...", text: $notes, axis: .vertical)
                        .lineLimit(2, reservesSpace: true)
                }
            }
            .navigationTitle(isEditing ? "编辑体征" : "添加体征")
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
                Text(validationMessage)
            }
        }
    }

    private func populateFields() {
        guard let e = entry else { return }
        metricType = e.metricType
        valueText = String(format: e.metricType == .heartRate || e.metricType == .steps ? "%.0f" : "%.1f", e.value)
        secondaryValueText = e.secondaryValue > 0 ? "\(Int(e.secondaryValue))" : ""
        recordedAt = e.recordedAt
        source = e.source
        notes = e.notes
    }

    private func saveAction() {
        guard let value = Double(valueText.replacingOccurrences(of: ",", with: ".")), value > 0 else {
            validationMessage = "请输入有效的数值"
            showingValidationError = true
            return
        }
        var secondaryValue = 0.0
        if isBloodPressure {
            guard let sv = Double(secondaryValueText), sv > 0 else {
                validationMessage = "请输入有效的舒张压"
                showingValidationError = true
                return
            }
            secondaryValue = sv
        }

        if let e = entry {
            e.metricTypeRaw = metricType.rawValue
            e.value = value
            e.secondaryValue = secondaryValue
            e.recordedAt = recordedAt
            e.source = source
            e.notes = notes.trimmingCharacters(in: .whitespaces)
        } else {
            let newEntry = WearableEntry(
                metricType: metricType,
                value: value,
                secondaryValue: secondaryValue,
                recordedAt: recordedAt,
                source: source
            )
            newEntry.notes = notes.trimmingCharacters(in: .whitespaces)
            newEntry.member = member
            modelContext.insert(newEntry)
        }
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        WearableListView(member: MockData.sampleMember)
    }
    .modelContainer(MockData.previewContainer)
}
