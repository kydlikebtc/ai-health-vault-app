import SwiftData
import Foundation

/// 自定义提醒 — 用户手动添加的日历事项
@Model
final class CustomReminder {
    @Attribute(.unique) var id: UUID
    var title: String           // 提醒标题
    var reminderDate: Date      // 提醒时间
    var notes: String           // 备注
    var isCompleted: Bool       // 是否已完成（打卡）
    var createdAt: Date

    var member: Member?

    init(
        title: String,
        reminderDate: Date = Date(),
        notes: String = ""
    ) {
        self.id = UUID()
        self.title = title
        self.reminderDate = reminderDate
        self.notes = notes
        self.isCompleted = false
        self.createdAt = Date()
    }
}
