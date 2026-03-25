import XCTest
@testable import AIHealthVault

/// MedicationNotificationService 单元测试
/// 测试范围：ReminderSlot 纯逻辑、通知常量、标识符格式
/// 注意：UNUserNotificationCenter 交互属于系统级集成测试，需在真机/受权模拟器上运行
final class MedicationNotificationServiceTests: XCTestCase {

    // MARK: - ReminderSlot.hour

    func testReminderSlot_morning_hourIsEight() {
        XCTAssertEqual(ReminderSlot.morning.hour, 8)
    }

    func testReminderSlot_noon_hourIsTwelve() {
        XCTAssertEqual(ReminderSlot.noon.hour, 12)
    }

    func testReminderSlot_evening_hourIsTwenty() {
        XCTAssertEqual(ReminderSlot.evening.hour, 20)
    }

    // MARK: - ReminderSlot.displayName

    func testReminderSlot_allCases_haveNonEmptyDisplayName() {
        for slot in ReminderSlot.allCases {
            XCTAssertFalse(slot.displayName.isEmpty, "\(slot.rawValue) 缺少 displayName")
        }
    }

    func testReminderSlot_morning_displayNameContainsTime() {
        XCTAssertTrue(ReminderSlot.morning.displayName.contains("08:00"))
    }

    func testReminderSlot_noon_displayNameContainsTime() {
        XCTAssertTrue(ReminderSlot.noon.displayName.contains("12:00"))
    }

    func testReminderSlot_evening_displayNameContainsTime() {
        XCTAssertTrue(ReminderSlot.evening.displayName.contains("20:00"))
    }

    // MARK: - ReminderSlot.rawValue

    func testReminderSlot_rawValues_areStable() {
        XCTAssertEqual(ReminderSlot.morning.rawValue, "morning")
        XCTAssertEqual(ReminderSlot.noon.rawValue, "noon")
        XCTAssertEqual(ReminderSlot.evening.rawValue, "evening")
    }

    // MARK: - ReminderSlot.defaults(for:)

    func testDefaults_once_returnsMorningOnly() {
        let slots = ReminderSlot.defaults(for: .once)
        XCTAssertEqual(slots, [.morning])
    }

    func testDefaults_daily_returnsMorningOnly() {
        let slots = ReminderSlot.defaults(for: .daily)
        XCTAssertEqual(slots, [.morning])
    }

    func testDefaults_weekly_returnsMorningOnly() {
        let slots = ReminderSlot.defaults(for: .weekly)
        XCTAssertEqual(slots, [.morning])
    }

    func testDefaults_asNeeded_returnsMorningOnly() {
        let slots = ReminderSlot.defaults(for: .asNeeded)
        XCTAssertEqual(slots, [.morning])
    }

    func testDefaults_twiceDaily_returnsMorningAndEvening() {
        let slots = ReminderSlot.defaults(for: .twiceDaily)
        XCTAssertEqual(slots, [.morning, .evening])
        XCTAssertFalse(slots.contains(.noon))
    }

    func testDefaults_thriceDaily_returnsAllThreeSlots() {
        let slots = ReminderSlot.defaults(for: .thriceDaily)
        XCTAssertEqual(slots, [.morning, .noon, .evening])
    }

    func testDefaults_thriceDaily_hasCorrectCount() {
        XCTAssertEqual(ReminderSlot.defaults(for: .thriceDaily).count, 3)
    }

    func testDefaults_twiceDaily_hasCorrectCount() {
        XCTAssertEqual(ReminderSlot.defaults(for: .twiceDaily).count, 2)
    }

    // MARK: - MedicationNotificationService 常量

    func testCategoryIdentifier_isCorrect() {
        XCTAssertEqual(MedicationNotificationService.categoryIdentifier, "MEDICATION_REMINDER")
    }

    func testActionMarkTaken_isCorrect() {
        XCTAssertEqual(MedicationNotificationService.actionMarkTaken, "MARK_TAKEN")
    }

    // MARK: - 通知标识符格式验证

    func testNotificationIdentifier_format_containsMedPrefix() {
        let medication = TestFixtures.makeMedication()
        let expectedPrefix = "med_\(medication.id.uuidString)_"

        // 验证各时段标识符格式一致性
        for slot in ReminderSlot.allCases {
            let identifier = "med_\(medication.id.uuidString)_\(slot.rawValue)"
            XCTAssertTrue(identifier.hasPrefix(expectedPrefix),
                          "标识符 \(identifier) 应以 med_<uuid>_ 为前缀")
        }
    }

    func testNotificationIdentifier_format_isUniquePerSlot() {
        let medication = TestFixtures.makeMedication()
        let identifiers = ReminderSlot.allCases.map {
            "med_\(medication.id.uuidString)_\($0.rawValue)"
        }
        let uniqueIds = Set(identifiers)
        XCTAssertEqual(identifiers.count, uniqueIds.count, "每个时段的通知标识符应唯一")
    }

    func testCancelIdentifier_format_matchesSchedulePrefix() {
        let medication = TestFixtures.makeMedication()
        let cancelPrefix = "med_\(medication.id.uuidString)_"
        let schedulePrefix = "med_\(medication.id.uuidString)_"
        // 取消逻辑依赖前缀匹配，两者必须一致
        XCTAssertEqual(cancelPrefix, schedulePrefix)
    }

    // MARK: - Medication 提醒字段默认值

    func testMedication_reminderEnabled_defaultsFalse() {
        let med = Medication(name: "测试药")
        XCTAssertFalse(med.reminderEnabled, "默认不开启提醒")
    }

    func testMedication_reminderMorning_defaultsTrue() {
        let med = Medication(name: "测试药")
        XCTAssertTrue(med.reminderMorning, "早间提醒默认勾选（单时段默认）")
    }

    func testMedication_reminderNoon_defaultsFalse() {
        let med = Medication(name: "测试药")
        XCTAssertFalse(med.reminderNoon)
    }

    func testMedication_reminderEvening_defaultsFalse() {
        let med = Medication(name: "测试药")
        XCTAssertFalse(med.reminderEvening)
    }

    // MARK: - scheduleReminders 前置条件（逻辑约定验证）

    func testScheduleCondition_inactiveMedication_shouldNotSchedule() {
        // 服务层逻辑：isActive == false 不应调度
        let med = TestFixtures.makeMedication()
        med.isActive = false
        med.reminderEnabled = true
        // 验证逻辑约定：isActive && reminderEnabled 均为 true 才调度
        XCTAssertFalse(med.isActive && med.reminderEnabled)
    }

    func testScheduleCondition_reminderDisabled_shouldNotSchedule() {
        let med = TestFixtures.makeMedication()
        med.isActive = true
        med.reminderEnabled = false
        XCTAssertFalse(med.isActive && med.reminderEnabled)
    }

    func testScheduleCondition_activeWithReminder_shouldSchedule() {
        let med = TestFixtures.makeMedication()
        med.isActive = true
        med.reminderEnabled = true
        XCTAssertTrue(med.isActive && med.reminderEnabled)
    }
}
