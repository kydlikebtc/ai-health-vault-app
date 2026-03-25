import SwiftUI
import SwiftData

// MARK: - 日常追踪列表

struct DailyLogListView: View {
    @Environment(\.modelContext) private var modelContext
    let member: Member

    @State private var searchText = ""
    @State private var showingAdd = false
    @State private var recordToEdit: DailyLog?
    @State private var recordToDelete: DailyLog?
    @State private var showingDeleteAlert = false

    private var filteredLogs: [DailyLog] {
        let sorted = member.dailyTracking.sorted { $0.date > $1.date }
        guard !searchText.isEmpty else { return sorted }
        return sorted.filter {
            $0.notes.localizedCaseInsensitiveContains(searchText) ||
            $0.symptoms.contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        Group {
            if member.dailyTracking.isEmpty && searchText.isEmpty {
                ContentUnavailableView {
                    Label("暂无日常追踪记录", systemImage: "calendar.badge.plus")
                } actions: {
                    Button("记录今天") { showingAdd = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    ForEach(filteredLogs) { log in
                        NavigationLink {
                            DailyLogDetailView(log: log, member: member)
                        } label: {
                            DailyLogRow(log: log)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                recordToDelete = log
                                showingDeleteAlert = true
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            Button {
                                recordToEdit = log
                            } label: {
                                Label("编辑", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                }
            }
        }
        .navigationTitle("日常追踪")
        .searchable(text: $searchText, prompt: "搜索日志")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAdd = true } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("添加日志")
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddEditDailyLogView(member: member)
        }
        .sheet(item: $recordToEdit) { record in
            AddEditDailyLogView(member: member, log: record)
        }
        .alert("删除记录", isPresented: $showingDeleteAlert, presenting: recordToDelete) { record in
            Button("删除", role: .destructive) { modelContext.delete(record) }
            Button("取消", role: .cancel) {}
        } message: { record in
            Text("确定要删除 \(record.date.localizedDateString) 的日志吗？")
        }
    }
}

// MARK: - 日常追踪行

struct DailyLogRow: View {
    let log: DailyLog

    var body: some View {
        HStack(spacing: 12) {
            Text(log.mood.emoji)
                .font(.title2)
                .frame(width: 36)
                .accessibilityLabel(log.mood.displayName)

            VStack(alignment: .leading, spacing: 4) {
                Text(log.date.localizedDateString)
                    .font(.headline)
                HStack(spacing: 12) {
                    if log.exerciseMinutes > 0 {
                        Label("\(log.exerciseMinutes)分钟", systemImage: "figure.run")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if log.waterIntakeMl > 0 {
                        Label("\(log.waterIntakeMl)ml", systemImage: "drop.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if log.sleepHours > 0 {
                        Label(String(format: "%.1fh", log.sleepHours), systemImage: "moon.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if !log.symptoms.isEmpty {
                StatusBadge(title: "\(log.symptoms.count)个症状", color: .orange)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 日常追踪详情

struct DailyLogDetailView: View {
    let log: DailyLog
    let member: Member
    @State private var showingEdit = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 整体状态卡片
                DetailCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(log.date.localizedDateString)
                                .font(.title2.bold())
                            Text("\(log.mood.emoji) \(log.mood.displayName)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }

                // 数值指标
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    MetricTile(
                        icon: "figure.run",
                        color: .blue,
                        value: "\(log.exerciseMinutes)",
                        unit: "分钟",
                        label: "运动时长"
                    )
                    MetricTile(
                        icon: "drop.fill",
                        color: .cyan,
                        value: "\(log.waterIntakeMl)",
                        unit: "毫升",
                        label: "饮水量"
                    )
                    MetricTile(
                        icon: "moon.fill",
                        color: .indigo,
                        value: String(format: "%.1f", log.sleepHours),
                        unit: "小时",
                        label: "睡眠时长"
                    )
                    MetricTile(
                        icon: "bolt.fill",
                        color: .yellow,
                        value: "\(log.energyLevel)",
                        unit: "/ 5",
                        label: "精力水平"
                    )
                }

                if !log.symptoms.isEmpty {
                    DetailCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("今日症状", systemImage: "bandage")
                                .font(.caption.bold())
                                .foregroundStyle(.orange)
                            ForEach(log.symptoms, id: \.self) { symptom in
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(.orange)
                                        .frame(width: 6, height: 6)
                                    Text(symptom)
                                        .font(.body)
                                }
                            }
                        }
                    }
                }

                if !log.notes.isEmpty {
                    DetailCard {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("日志备注", systemImage: "note.text")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Text(log.notes)
                                .font(.body)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("日志详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("编辑") { showingEdit = true }
            }
        }
        .sheet(isPresented: $showingEdit) {
            AddEditDailyLogView(member: member, log: log)
        }
    }
}

// MARK: - 指标卡片

struct MetricTile: View {
    let icon: String
    let color: Color
    let value: String
    let unit: String
    let label: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.12), in: Circle())
                .accessibilityHidden(true)

            Text(value + " " + unit)
                .font(.subheadline.monospacedDigit().bold())

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label)：\(value) \(unit)")
    }
}

// MARK: - 日常追踪添加/编辑表单

struct AddEditDailyLogView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let member: Member
    let log: DailyLog?

    @State private var date = Calendar.current.startOfDay(for: Date())
    @State private var mood: MoodLevel = .neutral
    @State private var energyLevel = 3
    @State private var sleepHoursText = ""
    @State private var waterText = ""
    @State private var exerciseText = ""
    @State private var symptomsText = ""
    @State private var notes = ""

    init(member: Member, log: DailyLog? = nil) {
        self.member = member
        self.log = log
    }

    private var isEditing: Bool { log != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("日期") {
                    DatePicker("日期", selection: $date, in: ...Date(), displayedComponents: .date)
                }

                Section("今日状态") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("心情")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            ForEach(MoodLevel.allCases, id: \.self) { level in
                                Button {
                                    mood = level
                                } label: {
                                    Text(level.emoji)
                                        .font(.title)
                                        .opacity(mood == level ? 1.0 : 0.3)
                                }
                                .buttonStyle(.plain)
                                if level != .veryGood {
                                    Spacer()
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .padding(.vertical, 2)

                    HStack {
                        Text("精力水平")
                        Spacer()
                        Picker("精力", selection: $energyLevel) {
                            ForEach(1...5, id: \.self) { level in
                                Text("\(level)").tag(level)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                    }
                }

                Section("健康数据") {
                    HStack {
                        Label("睡眠", systemImage: "moon.fill")
                        Spacer()
                        TextField("小时", text: $sleepHoursText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("小时").foregroundStyle(.secondary)
                    }
                    HStack {
                        Label("饮水", systemImage: "drop.fill")
                        Spacer()
                        TextField("0", text: $waterText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("毫升").foregroundStyle(.secondary)
                    }
                    HStack {
                        Label("运动", systemImage: "figure.run")
                        Spacer()
                        TextField("0", text: $exerciseText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("分钟").foregroundStyle(.secondary)
                    }
                }

                Section("症状") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("多个症状用换行分隔")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("如：头痛、疲倦", text: $symptomsText, axis: .vertical)
                            .lineLimit(3, reservesSpace: true)
                    }
                    .padding(.vertical, 2)
                }

                Section("备注") {
                    TextField("今日备注...", text: $notes, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }
            }
            .navigationTitle(isEditing ? "编辑日志" : "记录今天")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEditing ? "保存" : "记录") { saveAction() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear { populateFields() }
        }
    }

    private func populateFields() {
        guard let l = log else { return }
        date = l.date
        mood = l.mood
        energyLevel = l.energyLevel
        sleepHoursText = l.sleepHours > 0 ? String(format: "%.1f", l.sleepHours) : ""
        waterText = l.waterIntakeMl > 0 ? "\(l.waterIntakeMl)" : ""
        exerciseText = l.exerciseMinutes > 0 ? "\(l.exerciseMinutes)" : ""
        symptomsText = l.symptoms.joined(separator: "\n")
        notes = l.notes
    }

    private func saveAction() {
        let symptoms = symptomsText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        if let l = log {
            l.date = date
            l.mood = mood
            l.energyLevel = energyLevel
            l.sleepHours = Double(sleepHoursText.replacingOccurrences(of: ",", with: ".")) ?? 0
            l.waterIntakeMl = Int(waterText) ?? 0
            l.exerciseMinutes = Int(exerciseText) ?? 0
            l.symptoms = symptoms
            l.notes = notes.trimmingCharacters(in: .whitespaces)
        } else {
            let newLog = DailyLog(date: date)
            newLog.mood = mood
            newLog.energyLevel = energyLevel
            newLog.sleepHours = Double(sleepHoursText.replacingOccurrences(of: ",", with: ".")) ?? 0
            newLog.waterIntakeMl = Int(waterText) ?? 0
            newLog.exerciseMinutes = Int(exerciseText) ?? 0
            newLog.symptoms = symptoms
            newLog.notes = notes.trimmingCharacters(in: .whitespaces)
            newLog.member = member
            modelContext.insert(newLog)
        }
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DailyLogListView(member: MockData.sampleMember)
    }
    .modelContainer(MockData.previewContainer)
}
