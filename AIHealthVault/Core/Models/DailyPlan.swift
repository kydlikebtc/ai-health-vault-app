import SwiftData
import Foundation

/// 每日健康计划 — AI 生成的个性化健康建议，缓存到本地供离线展示
@Model
final class DailyPlan {
    @Attribute(.unique) var id: UUID
    var planDate: Date          // 计划对应的日期（当天 00:00:00）
    var content: String         // AI 生成的计划内容（Markdown 格式）
    var completedActions: [String]  // 已打卡完成的行动项 ID 列表
    var generatedAt: Date       // 生成时间
    var createdAt: Date

    var member: Member?

    init(planDate: Date = Date(), content: String) {
        self.id = UUID()
        self.planDate = Calendar.current.startOfDay(for: planDate)
        self.content = content
        self.completedActions = []
        self.generatedAt = Date()
        self.createdAt = Date()
    }

    var isToday: Bool {
        Calendar.current.isDateInToday(planDate)
    }

    func toggleAction(_ actionKey: String) {
        if completedActions.contains(actionKey) {
            completedActions.removeAll { $0 == actionKey }
        } else {
            completedActions.append(actionKey)
        }
    }
}
