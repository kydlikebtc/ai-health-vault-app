import SwiftData
import Foundation

/// 可穿戴设备数据类型
enum WearableMetricType: String, Codable, CaseIterable {
    case heartRate = "heart_rate"           // 心率（bpm）
    case bloodOxygen = "blood_oxygen"       // 血氧（%）
    case steps = "steps"                    // 步数
    case sleepHours = "sleep_hours"         // 睡眠时长（小时）
    case bloodPressure = "blood_pressure"   // 血压（收缩/舒张 mmHg）
    case bloodGlucose = "blood_glucose"     // 血糖（mmol/L）
    case bodyTemperature = "body_temp"      // 体温（℃）
    case weight = "weight"                  // 体重（kg）

    var displayName: String {
        switch self {
        case .heartRate: return "心率"
        case .bloodOxygen: return "血氧"
        case .steps: return "步数"
        case .sleepHours: return "睡眠"
        case .bloodPressure: return "血压"
        case .bloodGlucose: return "血糖"
        case .bodyTemperature: return "体温"
        case .weight: return "体重"
        }
    }

    var unit: String {
        switch self {
        case .heartRate: return "bpm"
        case .bloodOxygen: return "%"
        case .steps: return "步"
        case .sleepHours: return "小时"
        case .bloodPressure: return "mmHg"
        case .bloodGlucose: return "mmol/L"
        case .bodyTemperature: return "℃"
        case .weight: return "kg"
        }
    }

    var icon: String {
        switch self {
        case .heartRate: return "heart.fill"
        case .bloodOxygen: return "lungs.fill"
        case .steps: return "figure.walk"
        case .sleepHours: return "moon.fill"
        case .bloodPressure: return "waveform.path.ecg"
        case .bloodGlucose: return "drop.fill"
        case .bodyTemperature: return "thermometer"
        case .weight: return "scalemass"
        }
    }
}

/// 可穿戴设备数据条目
@Model
final class WearableEntry {
    @Attribute(.unique) var id: UUID
    var metricTypeRaw: String   // 指标类型
    var value: Double           // 主值
    var secondaryValue: Double  // 次值（如血压舒张压）
    var recordedAt: Date        // 记录时间
    var source: String          // 数据来源（如 "Apple Watch", "手动录入"）
    var notes: String
    var createdAt: Date

    var member: Member?

    init(
        metricType: WearableMetricType,
        value: Double,
        secondaryValue: Double = 0,
        recordedAt: Date = Date(),
        source: String = "手动录入"
    ) {
        self.id = UUID()
        self.metricTypeRaw = metricType.rawValue
        self.value = value
        self.secondaryValue = secondaryValue
        self.recordedAt = recordedAt
        self.source = source
        self.notes = ""
        self.createdAt = Date()
    }

    var metricType: WearableMetricType {
        get { WearableMetricType(rawValue: metricTypeRaw) ?? .heartRate }
        set { metricTypeRaw = newValue.rawValue }
    }

    /// 格式化显示值
    var displayValue: String {
        switch metricType {
        case .bloodPressure:
            return "\(Int(value))/\(Int(secondaryValue)) \(metricType.unit)"
        case .heartRate, .steps:
            return "\(Int(value)) \(metricType.unit)"
        default:
            return String(format: "%.1f \(metricType.unit)", value)
        }
    }
}
