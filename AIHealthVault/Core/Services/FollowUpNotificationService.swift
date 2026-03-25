import UserNotifications
import Foundation

/// 随访提醒通知服务 — 使用 UNUserNotificationCenter 调度本地通知
actor FollowUpNotificationService {

    static let shared = FollowUpNotificationService()

    // MARK: - 权限请求

    /// 请求通知权限（首次调用时弹出系统授权对话框）
    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    // MARK: - 调度随访提醒

    /// 为就诊记录的复诊日期调度本地通知
    /// - Parameters:
    ///   - visit: 包含 followUpDate 的就诊记录
    ///   - memberName: 成员姓名，用于通知内容
    func scheduleNotification(for visit: VisitRecord, memberName: String) async {
        guard let followUpDate = visit.followUpDate else { return }

        // 提前 1 天提醒（当天 09:00）
        guard let notifyDate = Calendar.current.date(byAdding: .day, value: -1, to: followUpDate) else { return }
        var components = Calendar.current.dateComponents([.year, .month, .day], from: notifyDate)
        components.hour = 9
        components.minute = 0

        let content = UNMutableNotificationContent()
        content.title = "明日复诊提醒"
        content.body = "\(memberName) 明天有复诊安排"
        if !visit.hospitalName.isEmpty {
            content.body += "（\(visit.hospitalName)"
            if !visit.department.isEmpty {
                content.body += " · \(visit.department)"
            }
            content.body += "）"
        }
        content.sound = .default
        content.categoryIdentifier = "FOLLOW_UP_REMINDER"

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let identifier = "follow_up_\(visit.id.uuidString)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        let center = UNUserNotificationCenter.current()
        let authorized = await checkAuthorization()
        guard authorized else { return }

        try? await center.add(request)
    }

    /// 取消指定就诊记录的提醒（删除记录时调用）
    func cancelNotification(for visitId: UUID) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["follow_up_\(visitId.uuidString)"])
    }

    // MARK: - 批量同步

    /// 同步所有未来的随访日期通知（App 启动或记录变更时调用）
    func syncNotifications(for visits: [VisitRecord], memberName: String) async {
        guard await checkAuthorization() else { return }

        let center = UNUserNotificationCenter.current()
        // 清除旧的随访通知
        let pending = await center.pendingNotificationRequests()
        let oldIds = pending
            .filter { $0.identifier.hasPrefix("follow_up_") }
            .map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: oldIds)

        // 重新添加未来的随访
        for visit in visits where visit.followUpDate != nil {
            await scheduleNotification(for: visit, memberName: memberName)
        }
    }

    // MARK: - 权限检查

    private func checkAuthorization() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }
}
