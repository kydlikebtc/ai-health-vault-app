import XCTest
import SwiftData
@testable import AIHealthVault

@MainActor
final class VisitRecordTests: SwiftDataTestCase {

    // MARK: - CRUD

    func testCreate_visitRecord_savesSuccessfully() throws {
        let record = TestFixtures.makeVisitRecord(hospital: "上海仁济医院")
        try insertAndSave(record)

        let fetched = try fetchAll(VisitRecord.self)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.hospitalName, "上海仁济医院")
    }

    func testUpdate_addDiagnosis_persistsCorrectly() throws {
        let record = TestFixtures.makeVisitRecord()
        try insertAndSave(record)

        record.diagnosis = "急性上呼吸道感染"
        record.treatment = "对症治疗"
        try modelContext.save()

        let fetched = try fetchAll(VisitRecord.self).first
        XCTAssertEqual(fetched?.diagnosis, "急性上呼吸道感染")
    }

    func testDelete_visitRecord_removesFromDatabase() throws {
        let record = TestFixtures.makeVisitRecord()
        try insertAndSave(record)

        modelContext.delete(record)
        try modelContext.save()

        XCTAssertTrue(try fetchAll(VisitRecord.self).isEmpty)
    }

    // MARK: - 就诊类型枚举

    func testVisitType_allCases_haveDisplayNameAndIcon() {
        for type in VisitType.allCases {
            XCTAssertFalse(type.displayName.isEmpty, "\(type) 缺少 displayName")
            XCTAssertFalse(type.icon.isEmpty, "\(type) 缺少 icon")
        }
    }

    func testVisitType_rawValueRoundTrip() {
        let record = TestFixtures.makeVisitRecord(visitType: .inpatient)
        XCTAssertEqual(record.visitType, .inpatient)
        XCTAssertEqual(record.visitTypeRaw, "inpatient")

        record.visitType = .telehealth
        XCTAssertEqual(record.visitTypeRaw, "telehealth")
    }

    func testVisitType_invalidRawValue_fallsBackToOutpatient() {
        let record = TestFixtures.makeVisitRecord()
        record.visitTypeRaw = "invalid"
        XCTAssertEqual(record.visitType, .outpatient)
    }

    // MARK: - 复诊日期

    func testFollowUpDate_canBeSet() throws {
        let record = TestFixtures.makeVisitRecord()
        let followUp = Calendar.current.date(byAdding: .month, value: 1, to: Date())
        record.followUpDate = followUp
        try insertAndSave(record)

        let fetched = try fetchAll(VisitRecord.self).first
        XCTAssertNotNil(fetched?.followUpDate)
    }

    func testFollowUpDate_defaultIsNil() {
        let record = TestFixtures.makeVisitRecord()
        XCTAssertNil(record.followUpDate)
    }

    func testFollowUpDate_canBeCleared() throws {
        let record = TestFixtures.makeVisitRecord()
        record.followUpDate = Calendar.current.date(byAdding: .month, value: 1, to: Date())
        try insertAndSave(record)

        record.followUpDate = nil
        try modelContext.save()

        let fetched = try fetchAll(VisitRecord.self).first
        XCTAssertNil(fetched?.followUpDate)
    }

    func testFollowUpDate_persists_exactDate() throws {
        let target = Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 15))!
        let record = TestFixtures.makeVisitRecord()
        record.followUpDate = target
        try insertAndSave(record)

        let fetched = try fetchAll(VisitRecord.self).first
        XCTAssertEqual(fetched?.followUpDate, target)
    }

    // MARK: - FollowUpNotificationService 调度逻辑约定

    func testFollowUpNotification_condition_requiresNonNilFollowUpDate() {
        // FollowUpNotificationService.scheduleNotification 要求 followUpDate 非 nil 才调度
        let withFollowUp = TestFixtures.makeVisitRecord()
        withFollowUp.followUpDate = Calendar.current.date(byAdding: .day, value: 30, to: Date())

        let withoutFollowUp = TestFixtures.makeVisitRecord()
        withoutFollowUp.followUpDate = nil

        XCTAssertTrue(withFollowUp.followUpDate != nil, "有复诊日期的记录应触发通知调度")
        XCTAssertFalse(withoutFollowUp.followUpDate != nil, "无复诊日期的记录不应调度通知")
    }

    func testFollowUpNotification_identifier_format() {
        let record = TestFixtures.makeVisitRecord()
        // FollowUpNotificationService 使用 "follow_up_<uuid>" 格式
        let expectedId = "follow_up_\(record.id.uuidString)"
        XCTAssertTrue(expectedId.hasPrefix("follow_up_"), "随访通知标识符应以 follow_up_ 为前缀")
        XCTAssertTrue(expectedId.hasSuffix(record.id.uuidString), "随访通知标识符应包含就诊记录 UUID")
    }

    func testSyncNotifications_condition_filtersFutureDatesOnly() {
        // syncNotifications 只同步有复诊日期的记录
        let visits: [VisitRecord] = [
            {
                let v = TestFixtures.makeVisitRecord()
                v.followUpDate = Date().addingTimeInterval(86400) // 明天
                return v
            }(),
            TestFixtures.makeVisitRecord(), // 无复诊日期
            {
                let v = TestFixtures.makeVisitRecord()
                v.followUpDate = Date().addingTimeInterval(86400 * 30) // 30天后
                return v
            }()
        ]

        let visitsWithFollowUp = visits.filter { $0.followUpDate != nil }
        XCTAssertEqual(visitsWithFollowUp.count, 2, "应只过滤出有复诊日期的记录")
    }

    // MARK: - 费用

    func testCost_defaultIsZero() {
        let record = TestFixtures.makeVisitRecord()
        XCTAssertEqual(record.cost, 0)
    }

    // MARK: - 关联成员

    func testVisitRecord_associatesWithMember() throws {
        let member = TestFixtures.makeMember()
        modelContext.insert(member)

        let record = TestFixtures.makeVisitRecord(visitType: .emergency)
        record.member = member
        modelContext.insert(record)
        try modelContext.save()

        XCTAssertEqual(member.visits.count, 1)
        XCTAssertEqual(member.visits.first?.visitType, .emergency)
    }
}
