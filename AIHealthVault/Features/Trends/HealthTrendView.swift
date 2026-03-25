import SwiftUI
import SwiftData
import Charts

// MARK: - 主趋势视图

struct HealthTrendView: View {
    let member: Member
    @State private var selectedPeriod: TrendPeriod = .month

    /// 一次性按类型分组并排序，避免 body 中多次重复线性扫描
    private var groupedEntries: [WearableMetricType: [WearableEntry]] {
        let cutoff = selectedPeriod.cutoffDate
        let filtered = member.wearableData.filter { $0.recordedAt >= cutoff }
        return Dictionary(grouping: filtered, by: \.metricType)
            .mapValues { $0.sorted { $0.recordedAt < $1.recordedAt } }
    }

    private func entries(for type: WearableMetricType) -> [WearableEntry] {
        groupedEntries[type] ?? []
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 时间范围选择
                Picker("时间范围", selection: $selectedPeriod) {
                    ForEach(TrendPeriod.allCases) { period in
                        Text(period.label).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                // 今日健康摘要
                HealthTodaySummaryCard(member: member, groupedEntries: groupedEntries)
                    .padding(.horizontal)

                // 各项指标图表
                Group {
                    TrendChartSection(
                        title: "体重趋势",
                        icon: "scalemass",
                        color: .blue,
                        isEmpty: entries(for: .weight).isEmpty
                    ) {
                        WeightTrendChart(entries: entries(for: .weight), member: member)
                    }

                    TrendChartSection(
                        title: "血压趋势",
                        icon: "waveform.path.ecg",
                        color: .red,
                        isEmpty: entries(for: .bloodPressure).isEmpty
                    ) {
                        BloodPressureTrendChart(entries: entries(for: .bloodPressure))
                    }

                    TrendChartSection(
                        title: "心率趋势",
                        icon: "heart.fill",
                        color: .pink,
                        isEmpty: entries(for: .heartRate).isEmpty
                    ) {
                        HeartRateTrendChart(entries: entries(for: .heartRate))
                    }

                    TrendChartSection(
                        title: "步数趋势",
                        icon: "figure.walk",
                        color: .green,
                        isEmpty: entries(for: .steps).isEmpty
                    ) {
                        StepsTrendChart(entries: entries(for: .steps), period: selectedPeriod)
                    }

                    TrendChartSection(
                        title: "睡眠趋势",
                        icon: "moon.fill",
                        color: .indigo,
                        isEmpty: entries(for: .sleepHours).isEmpty
                    ) {
                        SleepTrendChart(entries: entries(for: .sleepHours))
                    }

                    TrendChartSection(
                        title: "血氧趋势",
                        icon: "lungs.fill",
                        color: .cyan,
                        isEmpty: entries(for: .bloodOxygen).isEmpty
                    ) {
                        BloodOxygenTrendChart(entries: entries(for: .bloodOxygen))
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle("\(member.name) · 健康趋势")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 今日健康摘要卡片

struct HealthTodaySummaryCard: View {
    let member: Member
    /// 预分组 + 按时间升序排序的字典（由 HealthTrendView.groupedEntries 传入）
    let groupedEntries: [WearableMetricType: [WearableEntry]]

    // 每种指标最近一次读数（字典中最后一条即最新）
    private func latestEntry(for type: WearableMetricType) -> WearableEntry? {
        groupedEntries[type]?.last
    }

    // 相比此前均值的变化描述
    private func changeDescription(for type: WearableMetricType) -> (text: String, isPositive: Bool)? {
        let allOfType = groupedEntries[type] ?? []
        guard allOfType.count >= 3, let latest = allOfType.last else { return nil }

        // 取最近7条的均值（不含最新）作为基准
        let baseline = allOfType.dropLast().suffix(7).map(\.value)
        let avg = baseline.reduce(0, +) / Double(baseline.count)
        let diff = latest.value - avg

        guard abs(diff) > 0.5 else { return nil }

        let diffStr: String
        switch type {
        case .bloodPressure, .heartRate: diffStr = String(format: "%+.0f", diff)
        case .weight: diffStr = String(format: "%+.1f", diff)
        default: diffStr = String(format: "%+.1f", diff)
        }

        // 对于体重/血压/血糖：升高偏负向；对步数/血氧/睡眠：升高偏正向
        let higherIsBetter: Bool
        switch type {
        case .steps, .bloodOxygen, .sleepHours: higherIsBetter = true
        default: higherIsBetter = false
        }

        return (text: diffStr + type.unit, isPositive: diff > 0 == higherIsBetter)
    }

    // 异常判断
    private func isAbnormal(_ entry: WearableEntry) -> Bool {
        switch entry.metricType {
        case .bloodPressure: return entry.value >= 130 || entry.secondaryValue >= 80
        case .heartRate: return entry.value < 60 || entry.value > 100
        case .bloodOxygen: return entry.value < 95
        case .sleepHours: return entry.value < 6
        default: return false
        }
    }

    private let summaryMetrics: [WearableMetricType] = [
        .heartRate, .bloodPressure, .steps, .sleepHours, .bloodOxygen, .weight
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "heart.text.square.fill")
                    .foregroundStyle(.red)
                    .accessibilityHidden(true)
                Text("健康摘要")
                    .font(.headline)
                Spacer()
                Text("最近记录")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            let available = summaryMetrics.compactMap { type -> (WearableMetricType, WearableEntry)? in
                guard let entry = latestEntry(for: type) else { return nil }
                return (type, entry)
            }

            if available.isEmpty {
                HStack {
                    Spacer()
                    Text("此时间段内暂无记录")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 8)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(available, id: \.0) { type, entry in
                        SummaryMetricTile(
                            entry: entry,
                            isAbnormal: isAbnormal(entry),
                            change: changeDescription(for: type)
                        )
                    }
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - 摘要指标小格

struct SummaryMetricTile: View {
    let entry: WearableEntry
    let isAbnormal: Bool
    let change: (text: String, isPositive: Bool)?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: entry.metricType.icon)
                .font(.title3)
                .foregroundStyle(isAbnormal ? .red : entry.metricType.tileColor)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.metricType.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    Text(entry.displayValue)
                        .font(.subheadline.bold())
                        .foregroundStyle(isAbnormal ? .red : .primary)

                    if isAbnormal {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .accessibilityHidden(true)
                    }
                }

                if let change {
                    Text(change.text)
                        .font(.caption2)
                        .foregroundStyle(change.isPositive ? .green : .orange)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            isAbnormal ? Color.red.opacity(0.06) : Color.secondary.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .accessibilityLabel("\(entry.metricType.displayName)：\(entry.displayValue)\(isAbnormal ? "，异常" : "")")
    }
}

// MARK: - WearableMetricType 颜色扩展

private extension WearableMetricType {
    var tileColor: Color {
        switch self {
        case .heartRate: return .pink
        case .bloodOxygen: return .cyan
        case .steps: return .green
        case .sleepHours: return .indigo
        case .bloodPressure: return .red
        case .bloodGlucose: return .orange
        case .bodyTemperature: return .yellow
        case .weight: return .blue
        }
    }
}

// MARK: - 成员选择视图（从 AI 助手页入口时使用）

struct TrendMemberPickerView: View {
    @Query(sort: \Member.name) private var members: [Member]
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMember: Member?

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
                        NavigationLink(destination: HealthTrendView(member: member)) {
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
                                Spacer()
                                Text("\(member.wearableData.count) 条数据")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
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

// MARK: - Preview

#Preview("健康趋势") {
    NavigationStack {
        HealthTrendView(member: MockData.sampleMemberWithTrends)
    }
    .modelContainer(MockData.previewContainer)
}

#Preview("成员选择") {
    TrendMemberPickerView()
        .modelContainer(MockData.previewContainer)
}
