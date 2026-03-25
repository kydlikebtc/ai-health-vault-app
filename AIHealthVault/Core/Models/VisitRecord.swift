import SwiftData
import Foundation

/// 就诊类型
enum VisitType: String, Codable, CaseIterable {
    case outpatient = "outpatient"    // 门诊
    case inpatient = "inpatient"      // 住院
    case emergency = "emergency"      // 急诊
    case telehealth = "telehealth"    // 远程问诊

    var displayName: String {
        switch self {
        case .outpatient: return "门诊"
        case .inpatient: return "住院"
        case .emergency: return "急诊"
        case .telehealth: return "远程问诊"
        }
    }

    var icon: String {
        switch self {
        case .outpatient: return "stethoscope"
        case .inpatient: return "bed.double"
        case .emergency: return "cross.case"
        case .telehealth: return "video"
        }
    }
}

/// 就医记录
@Model
final class VisitRecord {
    @Attribute(.unique) var id: UUID
    var visitDate: Date         // 就诊日期
    var visitTypeRaw: String    // 就诊类型
    var hospitalName: String    // 医院名称
    var department: String      // 科室
    var doctorName: String      // 医生姓名
    var chiefComplaint: String  // 主诉
    var diagnosis: String       // 诊断结果
    var treatment: String       // 治疗方案
    var prescription: String    // 处方说明
    var followUpDate: Date?     // 复诊日期
    var cost: Double            // 费用（元）
    var createdAt: Date

    var member: Member?

    init(
        visitDate: Date = Date(),
        visitType: VisitType = .outpatient,
        hospitalName: String = "",
        department: String = ""
    ) {
        self.id = UUID()
        self.visitDate = visitDate
        self.visitTypeRaw = visitType.rawValue
        self.hospitalName = hospitalName
        self.department = department
        self.doctorName = ""
        self.chiefComplaint = ""
        self.diagnosis = ""
        self.treatment = ""
        self.prescription = ""
        self.cost = 0
        self.createdAt = Date()
    }

    var visitType: VisitType {
        get { VisitType(rawValue: visitTypeRaw) ?? .outpatient }
        set { visitTypeRaw = newValue.rawValue }
    }
}
