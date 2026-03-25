import XCTest
import SwiftData
@testable import AIHealthVault

@MainActor
final class MedicalHistoryTests: SwiftDataTestCase {

    // MARK: - CRUD

    func testCreate_medicalHistory_savesSuccessfully() throws {
        let history = TestFixtures.makeMedicalHistory(condition: "高血压", isChronic: true)
        try insertAndSave(history)

        let fetched = try fetchAll(MedicalHistory.self)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.conditionName, "高血压")
        XCTAssertTrue(fetched.first?.isChronic ?? false)
    }

    func testUpdate_markResolved_persistsCorrectly() throws {
        let history = TestFixtures.makeMedicalHistory(isChronic: false)
        try insertAndSave(history)

        history.resolvedDate = Date()
        try modelContext.save()

        let fetched = try fetchAll(MedicalHistory.self).first
        XCTAssertNotNil(fetched?.resolvedDate)
        XCTAssertTrue(fetched?.isResolved ?? false)
    }

    func testDelete_medicalHistory_removesFromDatabase() throws {
        let history = TestFixtures.makeMedicalHistory()
        try insertAndSave(history)

        modelContext.delete(history)
        try modelContext.save()

        XCTAssertTrue(try fetchAll(MedicalHistory.self).isEmpty)
    }

    // MARK: - 计算属性

    func testIsResolved_withResolvedDate_returnsTrue() {
        let history = TestFixtures.makeMedicalHistory()
        history.resolvedDate = Date()
        XCTAssertTrue(history.isResolved)
    }

    func testIsResolved_withoutResolvedDate_returnsFalse() {
        let history = TestFixtures.makeMedicalHistory()
        XCTAssertFalse(history.isResolved)
    }

    // MARK: - 关联成员

    func testMedicalHistory_associatesWithMember() throws {
        let member = TestFixtures.makeMember()
        modelContext.insert(member)

        let history = TestFixtures.makeMedicalHistory(condition: "阑尾炎")
        history.member = member
        modelContext.insert(history)
        try modelContext.save()

        XCTAssertEqual(member.medicalHistory.count, 1)
        XCTAssertEqual(member.medicalHistory.first?.conditionName, "阑尾炎")
    }

    func testChronicVsAcute_separatedCorrectly() throws {
        let member = TestFixtures.makeMember()
        modelContext.insert(member)

        let chronic = TestFixtures.makeMedicalHistory(condition: "高血压", isChronic: true)
        chronic.member = member
        modelContext.insert(chronic)

        let acute = TestFixtures.makeMedicalHistory(condition: "阑尾炎", isChronic: false)
        acute.member = member
        modelContext.insert(acute)

        try modelContext.save()

        let chronicCount = member.medicalHistory.filter { $0.isChronic }.count
        let acuteCount = member.medicalHistory.filter { !$0.isChronic }.count
        XCTAssertEqual(chronicCount, 1)
        XCTAssertEqual(acuteCount, 1)
    }
}
