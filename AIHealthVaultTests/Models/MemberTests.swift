import XCTest
import SwiftData
@testable import AIHealthVault

@MainActor
final class MemberTests: SwiftDataTestCase {

    // MARK: - CRUD

    func testCreate_withValidData_savesSuccessfully() throws {
        let member = TestFixtures.makeMember(name: "张三")
        try insertAndSave(member)

        let fetched = try fetchAll(Member.self)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.name, "张三")
    }

    func testCreate_multipleMembers_allPersisted() throws {
        for i in 1...5 {
            try insertAndSave(TestFixtures.makeMember(name: "成员\(i)"))
        }
        let fetched = try fetchAll(Member.self)
        XCTAssertEqual(fetched.count, 5)
    }

    func testUpdate_name_persistsCorrectly() throws {
        let member = TestFixtures.makeMember(name: "旧名")
        try insertAndSave(member)

        member.name = "新名"
        try modelContext.save()

        let fetched = try fetchAll(Member.self).first
        XCTAssertEqual(fetched?.name, "新名")
    }

    func testDelete_removesFromDatabase() throws {
        let member = TestFixtures.makeMember()
        try insertAndSave(member)

        modelContext.delete(member)
        try modelContext.save()

        let remaining = try fetchAll(Member.self)
        XCTAssertTrue(remaining.isEmpty)
    }

    // MARK: - 计算属性

    func testAge_withBirthday_calculatesCorrectly() {
        let member = TestFixtures.makeMember()
        // 1990-06-15 出生，2026年应该是35岁
        XCTAssertNotNil(member.age)
        XCTAssertGreaterThan(member.age!, 0)
    }

    func testAge_withoutBirthday_returnsNil() {
        let member = Member(name: "无生日")
        XCTAssertNil(member.age)
    }

    func testBMI_withHeightAndWeight_calculatesCorrectly() {
        let member = TestFixtures.makeMember()
        // 165cm, 58kg → BMI ≈ 21.3
        XCTAssertNotNil(member.bmi)
        XCTAssertEqual(member.bmi!, 21.3, accuracy: 0.1)
    }

    func testBMI_withoutHeight_returnsNil() {
        let member = Member(name: "无身高")
        member.weightKg = 60
        XCTAssertNil(member.bmi)
    }

    func testBMI_withZeroHeight_returnsNil() {
        let member = Member(name: "零身高")
        member.heightCm = 0
        member.weightKg = 60
        XCTAssertNil(member.bmi)
    }

    // MARK: - 枚举属性

    func testGender_rawValueRoundTrip() {
        let member = TestFixtures.makeMember(gender: .female)
        XCTAssertEqual(member.gender, .female)
        XCTAssertEqual(member.genderRaw, "female")

        member.gender = .male
        XCTAssertEqual(member.genderRaw, "male")
    }

    func testBloodType_rawValueRoundTrip() {
        let member = TestFixtures.makeMember(bloodType: .oPositive)
        XCTAssertEqual(member.bloodType, .oPositive)

        member.bloodType = .abNegative
        XCTAssertEqual(member.bloodTypeRaw, "AB-")
    }

    func testGender_invalidRawValue_fallsBackToOther() {
        let member = Member(name: "测试")
        member.genderRaw = "invalid_value"
        XCTAssertEqual(member.gender, .other)
    }

    // MARK: - 关系（Cascade Delete）

    func testDelete_member_cascadeDeletesRelatedRecords() throws {
        let member = TestFixtures.makeMember()
        modelContext.insert(member)

        let medication = TestFixtures.makeMedication()
        medication.member = member
        modelContext.insert(medication)

        let checkup = TestFixtures.makeCheckupReport()
        checkup.member = member
        modelContext.insert(checkup)

        try modelContext.save()

        // 删除成员
        modelContext.delete(member)
        try modelContext.save()

        // 关联记录也应被级联删除
        XCTAssertTrue(try fetchAll(Member.self).isEmpty)
        XCTAssertTrue(try fetchAll(Medication.self).isEmpty)
        XCTAssertTrue(try fetchAll(CheckupReport.self).isEmpty)
    }

    // MARK: - 默认值

    func testInit_defaultValues_areCorrect() {
        let member = Member(name: "默认值测试")
        XCTAssertEqual(member.notes, "")
        XCTAssertTrue(member.allergies.isEmpty)
        XCTAssertTrue(member.chronicConditions.isEmpty)
        XCTAssertEqual(member.currentHealthNotes, "")
        XCTAssertTrue(member.medicalHistory.isEmpty)
        XCTAssertTrue(member.medications.isEmpty)
        XCTAssertTrue(member.checkups.isEmpty)
        XCTAssertTrue(member.visits.isEmpty)
        XCTAssertTrue(member.wearableData.isEmpty)
        XCTAssertTrue(member.dailyTracking.isEmpty)
    }
}
