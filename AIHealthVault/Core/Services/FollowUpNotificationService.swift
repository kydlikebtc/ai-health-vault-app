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

    // MARK: - 体检复查提醒

    /// 为体检报告的建议复查日期调度本地通知
    func scheduleCheckupNotification(for checkup: CheckupReport, memberName: String) async {
        guard let nextDate = checkup.nextCheckupDate, nextDate > Date() else { return }
        guard await checkAuthorization() else { return }

        // 提前 3 天提醒（09:00）
        guard let notifyDate = Calendar.current.date(byAdding: .day, value: -3, to: nextDate) else { return }
        var components = Calendar.current.dateComponents([.year, .month, .day], from: notifyDate)
        components.hour = 9
        components.minute = 0

        let content = UNMutableNotificationContent()
        content.title = "建议复查提醒"
        let title = checkup.reportTitle.isEmpty ? "体检" : checkup.reportTitle
        content.body = "\(memberName) 的「\(title)」建议复查日期还有 3 天"
        if !checkup.hospitalName.isEmpty {
            content.body += "（\(checkup.hospitalName)）"
        }
        content.sound = .default
        content.categoryIdentifier = "FOLLOW_UP_REMINDER"

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let identifier = "checkup_\(checkup.id.uuidString)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// 取消指定体检记录的提醒
    func cancelCheckupNotification(for checkupId: UUID) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["checkup_\(checkupId.uuidString)"])
    }

    // MARK: - 自定义提醒

    /// 为自定义提醒调度本地通知
    func scheduleCustomReminder(_ reminder: CustomReminder, memberName: String) async {
        guard reminder.reminderDate > Date() else { return }
        guard await checkAuthorization() else { return }

        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.notes.isEmpty ? "\(memberName) 的健康提醒" : reminder.notes
        content.sound = .default
        content.categoryIdentifier = "FOLLOW_UP_REMINDER"

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.reminderDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let identifier = "custom_\(reminder.id.uuidString)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// 取消自定义提醒通知
    func cancelCustomReminder(for reminderId: UUID) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["custom_\(reminderId.uuidString)"])
    }

    // MARK: - 权限检查

    private func checkAuthorization() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }
}
