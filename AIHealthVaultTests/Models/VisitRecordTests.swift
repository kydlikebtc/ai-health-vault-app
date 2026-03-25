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
