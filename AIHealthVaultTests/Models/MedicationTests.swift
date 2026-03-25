import XCTest
import SwiftData
@testable import AIHealthVault

@MainActor
final class MedicationTests: SwiftDataTestCase {

    // MARK: - CRUD

    func testCreate_medication_savesSuccessfully() throws {
        let med = TestFixtures.makeMedication(name: "阿莫西林", dosage: "500mg")
        try insertAndSave(med)

        let fetched = try fetchAll(Medication.self)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.name, "阿莫西林")
        XCTAssertEqual(fetched.first?.dosage, "500mg")
    }

    func testUpdate_medication_isActiveStatus_persists() throws {
        let med = TestFixtures.makeMedication()
        try insertAndSave(med)

        med.isActive = false
        try modelContext.save()

        let fetched = try fetchAll(Medication.self).first
        XCTAssertFalse(fetched?.isActive ?? true)
    }

    func testDelete_medication_removesFromDatabase() throws {
        let med = TestFixtures.makeMedication()
        try insertAndSave(med)

        modelContext.delete(med)
        try modelContext.save()

        XCTAssertTrue(try fetchAll(Medication.self).isEmpty)
    }

    // MARK: - 频率枚举

    func testFrequency_allCases_haveDisplayName() {
        for freq in MedicationFrequency.allCases {
            XCTAssertFalse(freq.displayName.isEmpty, "\(freq) 缺少 displayName")
        }
    }

    func testFrequency_rawValueRoundTrip() {
        let med = TestFixtures.makeMedication(frequency: .twiceDaily)
        XCTAssertEqual(med.frequency, .twiceDaily)
        XCTAssertEqual(med.frequencyRaw, "twice_daily")

        med.frequency = .asNeeded
        XCTAssertEqual(med.frequencyRaw, "as_needed")
    }

    func testFrequency_invalidRawValue_fallsBackToDaily() {
        let med = TestFixtures.makeMedication()
        med.frequencyRaw = "invalid"
        XCTAssertEqual(med.frequency, .daily)
    }

    // MARK: - 默认值

    func testInit_defaultValues_areCorrect() {
        let med = Medication(name: "测试药")
        XCTAssertTrue(med.isActive)
        XCTAssertEqual(med.purpose, "")
        XCTAssertEqual(med.sideEffects, "")
        XCTAssertNil(med.endDate)
    }

    // MARK: - 关联成员

    func testMedication_associatesWithMember() throws {
        let member = TestFixtures.makeMember()
        modelContext.insert(member)

        let med = TestFixtures.makeMedication(name: "降压药")
        med.member = member
        modelContext.insert(med)
        try modelContext.save()

        XCTAssertEqual(member.medications.count, 1)
        XCTAssertEqual(member.medications.first?.name, "降压药")
    }

    func testMultipleMedications_forSameMember() throws {
        let member = TestFixtures.makeMember()
        modelContext.insert(member)

        let names = ["药A", "药B", "药C"]
        for name in names {
            let med = TestFixtures.makeMedication(name: name)
            med.member = member
            modelContext.insert(med)
        }
        try modelContext.save()

        XCTAssertEqual(member.medications.count, 3)
    }
}
