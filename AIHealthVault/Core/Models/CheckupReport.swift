import SwiftData
import Foundation

/// 体检报告
@Model
final class CheckupReport {
    @Attribute(.unique) var id: UUID
    var checkupDate: Date       // 体检日期
    var hospitalName: String    // 体检机构
    var reportTitle: String     // 报告标题（如 "2024年度体检"）
    var summary: String         // 摘要/医生建议
    var abnormalItems: [String] // 异常指标列表
    var attachmentPaths: [String] // 附件路径（PDF、图片）
    var createdAt: Date

    var member: Member?

    init(
        checkupDate: Date = Date(),
        hospitalName: String = "",
        reportTitle: String = ""
    ) {
        self.id = UUID()
        self.checkupDate = checkupDate
        self.hospitalName = hospitalName
        self.reportTitle = reportTitle
        self.summary = ""
        self.abnormalItems = []
        self.attachmentPaths = []
        self.createdAt = Date()
    }

    var hasAbnormalItems: Bool { !abnormalItems.isEmpty }
}
