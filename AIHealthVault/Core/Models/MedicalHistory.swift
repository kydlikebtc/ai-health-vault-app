import SwiftData
import Foundation

/// 既往病史记录
@Model
final class MedicalHistory {
    @Attribute(.unique) var id: UUID
    var conditionName: String   // 病症名称
    var diagnosedDate: Date?    // 确诊日期
    var resolvedDate: Date?     // 痊愈日期（nil 表示持续中）
    var hospitalName: String    // 就诊医院
    var doctorName: String      // 主治医生
    var treatmentSummary: String // 治疗摘要
    var isChronic: Bool         // 是否为慢性病
    var createdAt: Date

    var member: Member?

    init(
        conditionName: String,
        diagnosedDate: Date? = nil,
        hospitalName: String = "",
        treatmentSummary: String = "",
        isChronic: Bool = false
    ) {
        self.id = UUID()
        self.conditionName = conditionName
        self.diagnosedDate = diagnosedDate
        self.hospitalName = hospitalName
        self.doctorName = ""
        self.treatmentSummary = treatmentSummary
        self.isChronic = isChronic
        self.createdAt = Date()
    }

    var isResolved: Bool { resolvedDate != nil }
}
