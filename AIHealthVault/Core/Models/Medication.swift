import SwiftData
import Foundation

/// 服药频率
enum MedicationFrequency: String, Codable, CaseIterable {
    case once = "once"                 // 一次性
    case daily = "daily"               // 每天
    case twiceDaily = "twice_daily"    // 每天两次
    case thriceDaily = "thrice_daily"  // 每天三次
    case weekly = "weekly"             // 每周
    case asNeeded = "as_needed"        // 按需

    var displayName: String {
        switch self {
        case .once: return "一次性"
        case .daily: return "每天一次"
        case .twiceDaily: return "每天两次"
        case .thriceDaily: return "每天三次"
        case .weekly: return "每周"
        case .asNeeded: return "按需"
        }
    }
}

/// 用药记录
@Model
final class Medication {
    @Attribute(.unique) var id: UUID
    var name: String            // 药品名称
    var dosage: String          // 剂量（如 "500mg"）
    var frequencyRaw: String    // 服药频率
    var startDate: Date         // 开始服药日期
    var endDate: Date?          // 结束日期（nil 表示持续）
    var prescribedBy: String    // 开具医生
    var purpose: String         // 用途说明
    var sideEffects: String     // 已知副作用
    var isActive: Bool          // 是否当前在服用
    var createdAt: Date

    var member: Member?

    init(
        name: String,
        dosage: String = "",
        frequency: MedicationFrequency = .daily,
        startDate: Date = Date(),
        prescribedBy: String = ""
    ) {
        self.id = UUID()
        self.name = name
        self.dosage = dosage
        self.frequencyRaw = frequency.rawValue
        self.startDate = startDate
        self.prescribedBy = prescribedBy
        self.purpose = ""
        self.sideEffects = ""
        self.isActive = true
        self.createdAt = Date()
    }

    var frequency: MedicationFrequency {
        get { MedicationFrequency(rawValue: frequencyRaw) ?? .daily }
        set { frequencyRaw = newValue.rawValue }
    }
}
