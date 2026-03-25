import SwiftData
import Foundation

/// 性别
enum Gender: String, Codable, CaseIterable {
    case male = "male"
    case female = "female"
    case other = "other"

    var displayName: String {
        switch self {
        case .male: return "男"
        case .female: return "女"
        case .other: return "其他"
        }
    }
}

/// 血型
enum BloodType: String, Codable, CaseIterable {
    case aPositive = "A+"
    case aNegative = "A-"
    case bPositive = "B+"
    case bNegative = "B-"
    case abPositive = "AB+"
    case abNegative = "AB-"
    case oPositive = "O+"
    case oNegative = "O-"
    case unknown = "未知"
}

@Model
final class Member {
    @Attribute(.unique) var id: UUID

    // 基本信息
    var name: String
    var birthday: Date?
    var genderRaw: String
    var bloodTypeRaw: String
    var heightCm: Double?       // 身高（厘米）
    var weightKg: Double?       // 体重（公斤）
    var avatarData: Data?       // 头像图片数据
    var notes: String           // 备注

    // 当前健康状况（嵌入属性，避免不必要的关系）
    var allergies: [String]         // 过敏原列表
    var chronicConditions: [String] // 慢性病列表
    var currentHealthNotes: String  // 当前健康状况说明

    // 时间戳
    var createdAt: Date
    var updatedAt: Date

    // 关系
    var family: Family?

    @Relationship(deleteRule: .cascade, inverse: \MedicalHistory.member)
    var medicalHistory: [MedicalHistory]

    @Relationship(deleteRule: .cascade, inverse: \Medication.member)
    var medications: [Medication]

    @Relationship(deleteRule: .cascade, inverse: \CheckupReport.member)
    var checkups: [CheckupReport]

    @Relationship(deleteRule: .cascade, inverse: \VisitRecord.member)
    var visits: [VisitRecord]

    @Relationship(deleteRule: .cascade, inverse: \WearableEntry.member)
    var wearableData: [WearableEntry]

    @Relationship(deleteRule: .cascade, inverse: \DailyLog.member)
    var dailyTracking: [DailyLog]

    init(
        name: String,
        birthday: Date? = nil,
        gender: Gender = .male,
        bloodType: BloodType = .unknown
    ) {
        self.id = UUID()
        self.name = name
        self.birthday = birthday
        self.genderRaw = gender.rawValue
        self.bloodTypeRaw = bloodType.rawValue
        self.notes = ""
        self.allergies = []
        self.chronicConditions = []
        self.currentHealthNotes = ""
        self.createdAt = Date()
        self.updatedAt = Date()
        self.medicalHistory = []
        self.medications = []
        self.checkups = []
        self.visits = []
        self.wearableData = []
        self.dailyTracking = []
    }

    // MARK: - 计算属性

    var gender: Gender {
        get { Gender(rawValue: genderRaw) ?? .other }
        set { genderRaw = newValue.rawValue }
    }

    var bloodType: BloodType {
        get { BloodType(rawValue: bloodTypeRaw) ?? .unknown }
        set { bloodTypeRaw = newValue.rawValue }
    }

    /// 年龄（岁）
    var age: Int? {
        guard let birthday else { return nil }
        return Calendar.current.dateComponents([.year], from: birthday, to: Date()).year
    }

    /// BMI
    var bmi: Double? {
        guard let h = heightCm, let w = weightKg, h > 0 else { return nil }
        let heightM = h / 100.0
        return w / (heightM * heightM)
    }
}
