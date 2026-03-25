import SwiftUI
import SwiftData
import os

private let wearableLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aihealthvault", category: "WearableViews")

// MARK: - 体征数据列表

struct WearableListView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var healthKitService: HealthKitService
    let member: Member

    @State private var searchText = ""
    @State private var selectedMetricType: WearableMetricType?
    @State private var showingAdd = false
    @State private var recordToEdit: WearableEntry?
    @State private var recordToDelete: WearableEntry?
    @State private var showingDeleteAlert = false
    @State private var showSyncError = false
    @State private var syncErrorMessage = ""

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
            if member.wearableData.isEmpty && searchText.isEmpty && !healthKitService.isAvailable {
                ContentUnavailableView {
                    Label("暂无体征数据", systemImage: "applewatch")
                } actions: {
                    Button("添加数据") { showingAdd = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    // 今日健康摘要卡片（仅 HealthKit 已授权时显示）
                    if healthKitService.isAvailable && healthKitService.authorizationStatus == .authorized {
                        Section {
                            TodayHealthSummaryCard(member: member)
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                .listRowBackground(Color.clear)
                        }
                    }

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
                            .accessibilityHidden(true)
                        Text(selectedMetricType?.displayName ?? "筛选")
                            .font(.subheadline)
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                HStack {
                    if healthKitService.isAvailable && healthKitService.authorizationStatus == .authorized {
                        Button {
                            Task { await syncFromHealthKit() }
                        } label: {
                            if healthKitService.isSyncing {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }
                        }
                        .accessibilityLabel("从 HealthKit 同步数据")
                        .disabled(healthKitService.isSyncing)
                    }
                    Button { showingAdd = true } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("添加体征数据")
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
        .alert("同步失败", isPresented: $showSyncError) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(syncErrorMessage)
        }
        .task {
            // App 进入页面时自动拉取增量数据
            await autoSync()
        }
    }

    // MARK: - Actions

    private func syncFromHealthKit() async {
        do {
            let newCount = try await healthKitService.syncToSwiftData(member: member, context: modelContext)
            wearableLogger.info("手动同步完成，新增 \(newCount, format: .decimal) 条")
        } catch {
            syncErrorMessage = error.localizedDescription
            showSyncError = true
        }
    }

    private func autoSync() async {
        guard healthKitService.isAvailable,
              healthKitService.authorizationStatus == .authorized,
              !healthKitService.isSyncing
        else { return }
        try? await healthKitService.syncToSwiftData(member: member, context: modelContext)
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
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.metricType.displayName)
                    .font(.headline)
                HStack(spacing: 8) {
                    Text(entry.recordedAt.localizedDateString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if entry.isFromHealthKit {
                        Label("Apple Health", systemImage: "heart.text.square.fill")
                            .font(.caption2)
                            .foregroundStyle(.pink)
                            .labelStyle(.titleAndIcon)
                    } else if !entry.source.isEmpty && entry.source != "手动录入" {
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

// MARK: - Today Health Summary Card

/// 今日健康摘要卡片——展示从 HealthKit 读取的当日关键指标
struct TodayHealthSummaryCard: View {
    @EnvironmentObject private var healthKitService: HealthKitService
    let member: Member

    @State private var summary: HealthKitTodaySummary? = nil
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("今日健康", systemImage: "heart.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(.pink)
                Spacer()
                if isLoading {
                    ProgressView().controlSize(.mini)
                } else {
                    Button {
                        Task { await fetchSummary() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("刷新今日健康数据")
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 8)

            if let summary, !summary.isEmpty {
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 12
                ) {
                    if let steps = summary.steps {
                        SummaryMetricCell(icon: "figure.walk", color: .green, label: "步数",
                                          value: "\(steps)", unit: "步")
                    }
                    if let hr = summary.heartRate {
                        SummaryMetricCell(icon: "heart.fill", color: .red, label: "心率",
                                          value: String(format: "%.0f", hr), unit: "bpm")
                    }
                    if let sleep = summary.sleepHours {
                        SummaryMetricCell(icon: "moon.fill", color: .indigo, label: "睡眠",
                                          value: String(format: "%.1f", sleep), unit: "小时")
                    }
                    if let weight = summary.weight {
                        SummaryMetricCell(icon: "scalemass", color: .orange, label: "体重",
                                          value: String(format: "%.1f", weight), unit: "kg")
                    }
                    if let sys = summary.systolicBP, let dia = summary.diastolicBP {
                        SummaryMetricCell(icon: "waveform.path.ecg", color: .blue, label: "血压",
                                          value: "\(Int(sys))/\(Int(dia))", unit: "mmHg")
                    }
                    if let oxygen = summary.bloodOxygen {
                        SummaryMetricCell(icon: "lungs.fill", color: .teal, label: "血氧",
                                          value: String(format: "%.1f", oxygen), unit: "%")
                    }
                }
                .padding([.horizontal, .bottom])
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .task { await fetchSummary() }
    }

    private func fetchSummary() async {
        guard healthKitService.isAvailable, healthKitService.authorizationStatus == .authorized else { return }
        isLoading = true
        summary = try? await healthKitService.fetchTodaySummary()
        isLoading = false
    }
}

// MARK: - Summary Metric Cell

private struct SummaryMetricCell: View {
    let icon: String
    let color: Color
    let label: String
    let value: String
    let unit: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(value)
                .font(.subheadline.monospacedDigit().bold())
            Text("\(label)·\(unit)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        WearableListView(member: MockData.sampleMember)
            .environmentObject(HealthKitService())
    }
    .modelContainer(MockData.previewContainer)
}
