import SwiftUI
import Charts

// MARK: - 时间范围选择

enum TrendPeriod: Int, CaseIterable, Identifiable {
    case week = 7
    case month = 30
    case quarter = 90
    case year = 365

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .week: return "7天"
        case .month: return "30天"
        case .quarter: return "90天"
        case .year: return "1年"
        }
    }

    var cutoffDate: Date {
        Calendar.current.date(byAdding: .day, value: -rawValue, to: Date()) ?? Date()
    }
}

// MARK: - 通用图表区块容器

struct TrendChartSection<ChartContent: View>: View {
    let title: String
    let icon: String
    let color: Color
    let isEmpty: Bool
    @ViewBuilder let chartContent: () -> ChartContent

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.headline)
                Spacer()
            }

            if isEmpty {
                emptyState
            } else {
                chartContent()
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private var emptyState: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "chart.line.downtrend.xyaxis")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
                Text("暂无数据")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 24)
            Spacer()
        }
    }
}

// MARK: - 体重趋势图

struct WeightTrendChart: View {
    let entries: [WearableEntry]
    let member: Member

    private var bmiRefWeight: Double? {
        guard let h = member.heightCm, h > 0 else { return nil }
        let hm = h / 100.0
        return 22.0 * hm * hm   // BMI 22 正常中值
    }

    var body: some View {
        Chart {
            // 正常体重参考带（BMI 18.5-24 范围）
            if let h = member.heightCm, h > 0 {
                let hm = h / 100.0
                let low = 18.5 * hm * hm
                let high = 24.0 * hm * hm
                RectangleMark(
                    xStart: .value("", entries.first?.recordedAt ?? Date()),
                    xEnd: .value("", entries.last?.recordedAt ?? Date()),
                    yStart: .value("低", low),
                    yEnd: .value("高", high)
                )
                .foregroundStyle(.green.opacity(0.08))
            }

            ForEach(entries, id: \.id) { entry in
                AreaMark(
                    x: .value("日期", entry.recordedAt),
                    y: .value("体重", entry.value)
                )
                .foregroundStyle(.blue.opacity(0.12))
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("日期", entry.recordedAt),
                    y: .value("体重 (kg)", entry.value)
                )
                .foregroundStyle(.blue)
                .interpolationMethod(.catmullRom)

                PointMark(
                    x: .value("日期", entry.recordedAt),
                    y: .value("体重", entry.value)
                )
                .foregroundStyle(.blue)
                .symbolSize(20)
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: strideUnit, count: strideCount)) { _ in
                AxisGridLine()
                AxisValueLabel(format: dateFormat)
            }
        }
        .chartYAxisLabel("kg")
        .frame(height: 160)
        .accessibilityLabel("体重趋势折线图")
    }

    private var strideUnit: Calendar.Component {
        entries.count > 60 ? .month : .weekOfYear
    }
    private var strideCount: Int { 1 }
    private var dateFormat: Date.FormatStyle {
        entries.count > 60 ? .dateTime.month(.abbreviated) : .dateTime.month().day()
    }
}

// MARK: - 血压趋势图

struct BloodPressureTrendChart: View {
    let entries: [WearableEntry]

    var body: some View {
        Chart {
            // 正常收缩压参考带（< 120 mmHg）
            RectangleMark(
                xStart: .value("", entries.first?.recordedAt ?? Date()),
                xEnd: .value("", entries.last?.recordedAt ?? Date()),
                yStart: .value("低", 0),
                yEnd: .value("高", 120)
            )
            .foregroundStyle(.green.opacity(0.05))

            ForEach(entries, id: \.id) { entry in
                // 收缩压（主值）
                LineMark(
                    x: .value("日期", entry.recordedAt),
                    y: .value("收缩压", entry.value),
                    series: .value("", "收缩压")
                )
                .foregroundStyle(.red)
                .interpolationMethod(.catmullRom)

                PointMark(
                    x: .value("日期", entry.recordedAt),
                    y: .value("收缩压", entry.value)
                )
                .foregroundStyle(.red)
                .symbolSize(16)

                // 舒张压（次值）
                LineMark(
                    x: .value("日期", entry.recordedAt),
                    y: .value("舒张压", entry.secondaryValue),
                    series: .value("", "舒张压")
                )
                .foregroundStyle(.blue)
                .interpolationMethod(.catmullRom)

                PointMark(
                    x: .value("日期", entry.recordedAt),
                    y: .value("舒张压", entry.secondaryValue)
                )
                .foregroundStyle(.blue)
                .symbolSize(16)
            }

            // 参考线：收缩压 120
            RuleMark(y: .value("正常收缩压", 120))
                .foregroundStyle(.red.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                .annotation(position: .trailing) {
                    Text("120").font(.caption2).foregroundStyle(.red.opacity(0.6))
                }

            // 参考线：舒张压 80
            RuleMark(y: .value("正常舒张压", 80))
                .foregroundStyle(.blue.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                .annotation(position: .trailing) {
                    Text("80").font(.caption2).foregroundStyle(.blue.opacity(0.6))
                }
        }
        .chartLegend(position: .top, alignment: .leading)
        .chartXAxis {
            AxisMarks(values: .automatic) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month().day())
            }
        }
        .chartYAxisLabel("mmHg")
        .frame(height: 180)
        .accessibilityLabel("血压趋势图，红色为收缩压，蓝色为舒张压")
    }
}

// MARK: - 心率趋势图

struct HeartRateTrendChart: View {
    let entries: [WearableEntry]

    var body: some View {
        Chart {
            // 正常心率参考带（60-100 bpm）
            RectangleMark(
                xStart: .value("", entries.first?.recordedAt ?? Date()),
                xEnd: .value("", entries.last?.recordedAt ?? Date()),
                yStart: .value("低", 60),
                yEnd: .value("高", 100)
            )
            .foregroundStyle(.green.opacity(0.08))

            ForEach(entries, id: \.id) { entry in
                LineMark(
                    x: .value("日期", entry.recordedAt),
                    y: .value("心率", entry.value)
                )
                .foregroundStyle(heartRateColor(entry.value))
                .interpolationMethod(.catmullRom)

                PointMark(
                    x: .value("日期", entry.recordedAt),
                    y: .value("心率", entry.value)
                )
                .foregroundStyle(heartRateColor(entry.value))
                .symbolSize(18)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month().day())
            }
        }
        .chartYAxisLabel("bpm")
        .chartYScale(domain: 40...160)
        .frame(height: 160)
        .accessibilityLabel("心率趋势折线图")
    }

    private func heartRateColor(_ bpm: Double) -> Color {
        if bpm < 60 || bpm > 100 { return .orange }
        return .pink
    }
}

// MARK: - 步数趋势图

struct StepsTrendChart: View {
    let entries: [WearableEntry]
    let period: TrendPeriod

    // 按天聚合步数（同一天多条记录累加）
    private var dailySteps: [(date: Date, steps: Double)] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: entries) { entry in
            cal.startOfDay(for: entry.recordedAt)
        }
        return grouped
            .map { (date: $0.key, steps: $0.value.reduce(0) { $0 + $1.value }) }
            .sorted { $0.date < $1.date }
    }

    var body: some View {
        Chart {
            // 目标步数参考线 10000
            RuleMark(y: .value("目标", 10_000))
                .foregroundStyle(.green.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                .annotation(position: .leading) {
                    Text("1万").font(.caption2).foregroundStyle(.green.opacity(0.7))
                }

            ForEach(dailySteps, id: \.date) { item in
                BarMark(
                    x: .value("日期", item.date, unit: .day),
                    y: .value("步数", item.steps)
                )
                .foregroundStyle(item.steps >= 10_000 ? Color.green : Color.blue)
                .cornerRadius(4)
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: xStrideUnit, count: 1)) { _ in
                AxisGridLine()
                AxisValueLabel(format: xDateFormat)
            }
        }
        .chartYAxisLabel("步")
        .frame(height: 160)
        .accessibilityLabel("步数趋势柱状图，绿色表示达到每日1万步目标")
    }

    private var xStrideUnit: Calendar.Component {
        period == .week ? .day : .weekOfYear
    }

    private var xDateFormat: Date.FormatStyle {
        period == .week ? .dateTime.day() : .dateTime.month().day()
    }
}

// MARK: - 睡眠趋势图

struct SleepTrendChart: View {
    let entries: [WearableEntry]

    var body: some View {
        Chart {
            // 推荐睡眠时长参考带（7-9 小时）
            RectangleMark(
                xStart: .value("", entries.first?.recordedAt ?? Date()),
                xEnd: .value("", entries.last?.recordedAt ?? Date()),
                yStart: .value("低", 7),
                yEnd: .value("高", 9)
            )
            .foregroundStyle(.indigo.opacity(0.08))

            ForEach(entries, id: \.id) { entry in
                BarMark(
                    x: .value("日期", entry.recordedAt, unit: .day),
                    y: .value("睡眠", entry.value)
                )
                .foregroundStyle(sleepColor(entry.value))
                .cornerRadius(4)
            }

            // 参考线
            RuleMark(y: .value("推荐最低", 7))
                .foregroundStyle(.indigo.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
        }
        .chartXAxis {
            AxisMarks(values: .automatic) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month().day())
            }
        }
        .chartYAxisLabel("小时")
        .chartYScale(domain: 0...12)
        .frame(height: 160)
        .accessibilityLabel("睡眠时长趋势柱状图，深紫色表示睡眠充足")
    }

    private func sleepColor(_ hours: Double) -> Color {
        switch hours {
        case ..<6: return .red.opacity(0.8)
        case 6..<7: return .orange.opacity(0.8)
        case 7...9: return .indigo.opacity(0.8)
        default: return .yellow.opacity(0.8)
        }
    }
}

// MARK: - 血氧趋势图

struct BloodOxygenTrendChart: View {
    let entries: [WearableEntry]

    var body: some View {
        Chart {
            // 正常血氧参考带（≥ 95%）
            RectangleMark(
                xStart: .value("", entries.first?.recordedAt ?? Date()),
                xEnd: .value("", entries.last?.recordedAt ?? Date()),
                yStart: .value("低", 95),
                yEnd: .value("高", 100)
            )
            .foregroundStyle(.cyan.opacity(0.08))

            ForEach(entries, id: \.id) { entry in
                LineMark(
                    x: .value("日期", entry.recordedAt),
                    y: .value("血氧", entry.value)
                )
                .foregroundStyle(.cyan)
                .interpolationMethod(.catmullRom)

                PointMark(
                    x: .value("日期", entry.recordedAt),
                    y: .value("血氧", entry.value)
                )
                .foregroundStyle(entry.value < 95 ? Color.red : Color.cyan)
                .symbolSize(entry.value < 95 ? 30 : 16)
                .annotation(position: .top) {
                    if entry.value < 95 {
                        Text("⚠️")
                            .font(.caption2)
                    }
                }
            }

            // 预警线 95%
            RuleMark(y: .value("预警线", 95))
                .foregroundStyle(.red.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                .annotation(position: .trailing) {
                    Text("95%").font(.caption2).foregroundStyle(.red.opacity(0.7))
                }
        }
        .chartXAxis {
            AxisMarks(values: .automatic) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month().day())
            }
        }
        .chartYAxisLabel("%")
        .chartYScale(domain: 88...100)
        .frame(height: 160)
        .accessibilityLabel("血氧趋势折线图，低于95%的点标红预警")
    }
}
