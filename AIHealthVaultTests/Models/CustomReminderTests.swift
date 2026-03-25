import XCTest
import SwiftData
@testable import AIHealthVault

/// CustomReminder 模型单元测试
@MainActor
final class CustomReminderTests: SwiftDataTestCase {

    // MARK: - CRUD

    func testCreate_customReminder_savesSuccessfully() throws {
        let reminder = TestFixtures.makeCustomReminder(title: "年度体检")
        try insertAndSave(reminder)

        let fetched = try fetchAll(CustomReminder.self)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.title, "年度体检")
    }

    func testUpdate_isCompleted_persists() throws {
        let reminder = TestFixtures.makeCustomReminder()
        try insertAndSave(reminder)

        reminder.isCompleted = true
        try modelContext.save()

        let fetched = try fetchAll(CustomReminder.self).first
        XCTAssertTrue(fetched?.isCompleted ?? false)
    }

    func testDelete_customReminder_removesFromDatabase() throws {
        let reminder = TestFixtures.makeCustomReminder()
        try insertAndSave(reminder)

        modelContext.delete(reminder)
        try modelContext.save()

        XCTAssertTrue(try fetchAll(CustomReminder.self).isEmpty)
    }

    func testCreate_multipleReminders_allPersist() throws {
        let titles = ["体检", "复诊", "打疫苗"]
        for title in titles {
            let r = TestFixtures.makeCustomReminder(title: title)
            modelContext.insert(r)
        }
        try modelContext.save()

        let fetched = try fetchAll(CustomReminder.self)
        XCTAssertEqual(fetched.count, 3)
    }

    // MARK: - 默认值

    func testInit_isCompleted_defaultsFalse() {
        let r = CustomReminder(title: "提醒")
        XCTAssertFalse(r.isCompleted)
    }

    func testInit_notes_defaultsEmpty() {
        let r = CustomReminder(title: "提醒")
        XCTAssertEqual(r.notes, "")
    }

    func testInit_id_isUnique() {
        let r1 = CustomReminder(title: "A")
        let r2 = CustomReminder(title: "B")
        XCTAssertNotEqual(r1.id, r2.id)
    }

    func testInit_reminderDate_defaultsToNow() {
        let before = Date()
        let r = CustomReminder(title: "提醒")
        let after = Date()
        XCTAssertGreaterThanOrEqual(r.reminderDate, before)
        XCTAssertLessThanOrEqual(r.reminderDate, after)
    }

    func testInit_createdAt_isRecentTimestamp() {
        let before = Date()
        let r = CustomReminder(title: "提醒")
        let after = Date()
        XCTAssertGreaterThanOrEqual(r.createdAt, before)
        XCTAssertLessThanOrEqual(r.createdAt, after)
    }

    // MARK: - 自定义初始化参数

    func testInit_customTitle_isStored() {
        let r = TestFixtures.makeCustomReminder(title: "随访日历测试")
        XCTAssertEqual(r.title, "随访日历测试")
    }

    func testInit_customNotes_isStored() {
        let r = TestFixtures.makeCustomReminder(notes: "带身份证")
        XCTAssertEqual(r.notes, "带身份证")
    }

    func testInit_customReminderDate_isStored() {
        let targetDate = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 10))!
        let r = CustomReminder(title: "提醒", reminderDate: targetDate)
        XCTAssertEqual(r.reminderDate, targetDate)
    }

    // MARK: - 与 Member 的关联关系

    func testCustomReminder_associatesWithMember() throws {
        let member = TestFixtures.makeMember()
        modelContext.insert(member)

        let reminder = TestFixtures.makeCustomReminder(title: "心脏科复诊")
        reminder.member = member
        modelContext.insert(reminder)
        try modelContext.save()

        let fetched = try fetchAll(CustomReminder.self).first
        XCTAssertNotNil(fetched?.member)
        XCTAssertEqual(fetched?.member?.name, "测试用户")
    }

    func testCustomReminder_memberIsNilByDefault() {
        let r = TestFixtures.makeCustomReminder()
        XCTAssertNil(r.member)
    }

    func testMultipleReminders_forSameMember() throws {
        let member = TestFixtures.makeMember()
        modelContext.insert(member)

        for i in 1...3 {
            let r = TestFixtures.makeCustomReminder(title: "提醒\(i)")
            r.member = member
            modelContext.insert(r)
        }
        try modelContext.save()

        let allReminders = try fetchAll(CustomReminder.self)
        XCTAssertEqual(allReminders.count, 3)
        XCTAssertTrue(allReminders.allSatisfy { $0.member?.name == "测试用户" })
    }

    // MARK: - 完成状态切换

    func testToggleCompletion_fromFalseToTrue() throws {
        let r = TestFixtures.makeCustomReminder()
        try insertAndSave(r)

        r.isCompleted = true
        try modelContext.save()

        XCTAssertTrue((try fetchAll(CustomReminder.self).first)?.isCompleted ?? false)
    }

    func testToggleCompletion_fromTrueToFalse() throws {
        let r = TestFixtures.makeCustomReminder()
        r.isCompleted = true
        try insertAndSave(r)

        r.isCompleted = false
        try modelContext.save()

        XCTAssertFalse((try fetchAll(CustomReminder.self).first)?.isCompleted ?? true)
    }
}
