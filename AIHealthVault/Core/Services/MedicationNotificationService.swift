import UserNotifications
import Foundation

// MARK: - 提醒时段

enum ReminderSlot: String, CaseIterable {
    case morning = "morning"   // 早：08:00
    case noon    = "noon"      // 中：12:00
    case evening = "evening"   // 晚：20:00

    var hour: Int {
        switch self {
        case .morning: return 8
        case .noon:    return 12
        case .evening: return 20
        }
    }

    var displayName: String {
        switch self {
        case .morning: return "早（08:00）"
        case .noon:    return "中（12:00）"
        case .evening: return "晚（20:00）"
        }
    }

    /// 每种频率对应的默认提醒时段
    static func defaults(for frequency: MedicationFrequency) -> Set<ReminderSlot> {
        switch frequency {
        case .once, .daily, .weekly, .asNeeded:
            return [.morning]
        case .twiceDaily:
            return [.morning, .evening]
        case .thriceDaily:
            return [.morning, .noon, .evening]
        }
    }
}

// MARK: - 通知类别常量

extension MedicationNotificationService {
    static let categoryIdentifier = "MEDICATION_REMINDER"
    static let actionMarkTaken    = "MARK_TAKEN"
}

// MARK: - 用药提醒通知服务

/// 基于 UserNotifications 框架的用药提醒服务
/// - 通知标识符格式：`med_<uuid>_<slot>`
/// - 通知类别：`MEDICATION_REMINDER`，包含「已服用」操作
actor MedicationNotificationService {

    static let shared = MedicationNotificationService()

    // MARK: - 权限

    func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    // MARK: - 调度用药提醒

    /// 为一条用药记录调度本地通知
    /// - Parameters:
    ///   - medication: 用药记录（需 isActive == true 且 reminderEnabled == true）
    ///   - memberName: 成员姓名，用于通知正文
    func scheduleReminders(for medication: Medication, memberName: String) async {
        guard medication.isActive, medication.reminderEnabled else { return }
        guard await checkAuthorization() else { return }

        // 先取消旧通知再重建，避免重复
        await cancelReminders(for: medication.id)

        let center = UNUserNotificationCenter.current()
        let slots = activeSlots(for: medication)

        for slot in slots {
            guard let request = buildRequest(medication: medication,
                                             memberName: memberName,
                                             slot: slot) else { continue }
            try? await center.add(request)
        }
    }

    /// 批量同步成员的所有用药提醒（App 启动或数据变更时调用）
    func syncReminders(for medications: [Medication], memberName: String) async {
        guard await checkAuthorization() else { return }

        // 清除该成员所有旧的用药通知
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let oldIds = pending
            .filter { $0.identifier.hasPrefix("med_") }
            .map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: oldIds)

        for medication in medications where medication.isActive && medication.reminderEnabled {
            await scheduleReminders(for: medication, memberName: memberName)
        }
    }

    /// 取消指定用药记录的所有提醒
    func cancelReminders(for medicationId: UUID) async {
        let prefix = "med_\(medicationId.uuidString)_"
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ids = pending
            .filter { $0.identifier.hasPrefix(prefix) }
            .map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    // MARK: - 通知类别注册

    /// 注册「已服用」通知操作类别（在 App 启动时调用一次）
    nonisolated func registerNotificationCategory() {
        let takenAction = UNNotificationAction(
            identifier: MedicationNotificationService.actionMarkTaken,
            title: "已服用",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: MedicationNotificationService.categoryIdentifier,
            actions: [takenAction],
            intentIdentifiers: [],
            options: .customDismissAction
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    // MARK: - Private helpers

    private func activeSlots(for medication: Medication) -> [ReminderSlot] {
        var slots: [ReminderSlot] = []
        if medication.reminderMorning { slots.append(.morning) }
        if medication.reminderNoon    { slots.append(.noon) }
        if medication.reminderEvening { slots.append(.evening) }
        // 若全未勾选，回退到频率默认值
        if slots.isEmpty {
            slots = Array(ReminderSlot.defaults(for: medication.frequency))
        }
        return slots
    }

    private func buildRequest(medication: Medication,
                              memberName: String,
                              slot: ReminderSlot) -> UNNotificationRequest? {
        let content = UNMutableNotificationContent()
        content.title = "用药提醒"
        var body = "\(memberName) 该服用 \(medication.name)"
        if !medication.dosage.isEmpty {
            body += "（\(medication.dosage)）"
        }
        content.body = body
        content.sound = .default
        content.categoryIdentifier = MedicationNotificationService.categoryIdentifier
        // 传递元数据，供通知响应处理器使用
        content.userInfo = [
            "medicationId": medication.id.uuidString,
            "memberName": memberName,
            "slot": slot.rawValue
        ]

        let trigger = makeTrigger(for: medication, slot: slot)
        let identifier = "med_\(medication.id.uuidString)_\(slot.rawValue)"
        return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    }

    private func makeTrigger(for medication: Medication,
                             slot: ReminderSlot) -> UNNotificationTrigger {
        var components = DateComponents()
        components.hour   = slot.hour
        components.minute = 0

        switch medication.frequency {
        case .weekly:
            // 在开始日期对应的星期几重复
            let weekday = Calendar.current.component(.weekday, from: medication.startDate)
            components.weekday = weekday
            return UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        case .once:
            // 当天对应时段触发一次
            let startComponents = Calendar.current.dateComponents([.year, .month, .day], from: medication.startDate)
            components.year  = startComponents.year
            components.month = startComponents.month
            components.day   = startComponents.day
            return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        case .asNeeded:
            // 按需不自动调度；调用方应在 scheduleReminders 之前检查 reminderEnabled
            return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        default:
            // daily / twiceDaily / thriceDaily — 每天重复
            return UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        }
    }

    private func checkAuthorization() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized ||
               settings.authorizationStatus == .provisional
    }
}
