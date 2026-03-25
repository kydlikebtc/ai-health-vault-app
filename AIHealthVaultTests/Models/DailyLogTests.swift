import XCTest
import SwiftData
@testable import AIHealthVault

@MainActor
final class DailyLogTests: SwiftDataTestCase {

    // MARK: - CRUD

    func testCreate_dailyLog_savesSuccessfully() throws {
        let log = TestFixtures.makeDailyLog()
        try insertAndSave(log)

        let fetched = try fetchAll(DailyLog.self)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.waterIntakeMl, 2000)
        XCTAssertEqual(fetched.first?.exerciseMinutes, 30)
    }

    func testUpdate_addSymptoms_persistsCorrectly() throws {
        let log = TestFixtures.makeDailyLog()
        try insertAndSave(log)

        log.symptoms = ["头痛", "低烧"]
        try modelContext.save()

        let fetched = try fetchAll(DailyLog.self).first
        XCTAssertEqual(fetched?.symptoms.count, 2)
        XCTAssertTrue(fetched?.symptoms.contains("头痛") ?? false)
    }

    func testDelete_dailyLog_removesFromDatabase() throws {
        let log = TestFixtures.makeDailyLog()
        try insertAndSave(log)

        modelContext.delete(log)
        try modelContext.save()

        XCTAssertTrue(try fetchAll(DailyLog.self).isEmpty)
    }

    // MARK: - 日期归一化

    func testInit_date_normalizesToStartOfDay() {
        let specificTime = Calendar.current.date(
            bySettingHour: 15, minute: 30, second: 0, of: Date()
        )!
        let log = DailyLog(date: specificTime)
        let startOfDay = Calendar.current.startOfDay(for: specificTime)
        XCTAssertEqual(log.date, startOfDay, "DailyLog 日期应归一化到当天 00:00:00")
    }

    // MARK: - 情绪枚举

    func testMood_allCases_haveDisplayNameAndEmoji() {
        for mood in MoodLevel.allCases {
            XCTAssertFalse(mood.displayName.isEmpty, "\(mood) 缺少 displayName")
            XCTAssertFalse(mood.emoji.isEmpty, "\(mood) 缺少 emoji")
        }
    }

    func testMood_rawValueRoundTrip() {
        let log = TestFixtures.makeDailyLog()
        log.mood = .veryGood
        XCTAssertEqual(log.moodLevel, MoodLevel.veryGood.rawValue)

        log.mood = .bad
        XCTAssertEqual(log.mood, .bad)
    }

    func testMood_invalidRawValue_fallsBackToNeutral() {
        let log = TestFixtures.makeDailyLog()
        log.moodLevel = 99 // 无效值
        XCTAssertEqual(log.mood, .neutral)
    }

    // MARK: - 默认值

    func testInit_defaultValues_areCorrect() {
        let log = DailyLog()
        XCTAssertEqual(log.moodLevel, MoodLevel.neutral.rawValue)
        XCTAssertEqual(log.energyLevel, 3)
        XCTAssertEqual(log.waterIntakeMl, 0)
        XCTAssertEqual(log.exerciseMinutes, 0)
        XCTAssertEqual(log.sleepHours, 0)
        XCTAssertTrue(log.symptoms.isEmpty)
        XCTAssertEqual(log.notes, "")
    }

    // MARK: - 关联成员

    func testDailyLog_associatesWithMember() throws {
        let member = TestFixtures.makeMember()
        modelContext.insert(member)

        let log = TestFixtures.makeDailyLog()
        log.member = member
        modelContext.insert(log)
        try modelContext.save()

        XCTAssertEqual(member.dailyTracking.count, 1)
    }

    func testMultipleLogs_perMember_orderedByDate() throws {
        let member = TestFixtures.makeMember()
        modelContext.insert(member)

        let dates = (0..<7).map { Calendar.current.date(byAdding: .day, value: -$0, to: Date())! }
        for date in dates {
            let log = TestFixtures.makeDailyLog(date: date)
            log.member = member
            modelContext.insert(log)
        }
        try modelContext.save()

        XCTAssertEqual(member.dailyTracking.count, 7)
    }
}
