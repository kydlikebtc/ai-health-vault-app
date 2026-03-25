import XCTest
import SwiftData
@testable import AIHealthVault

@MainActor
final class WearableEntryTests: SwiftDataTestCase {

    // MARK: - CRUD

    func testCreate_heartRateEntry_savesCorrectly() throws {
        let entry = TestFixtures.makeWearableEntry(type: .heartRate, value: 72)
        try insertAndSave(entry)

        let fetched = try fetchAll(WearableEntry.self)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.value, 72)
        XCTAssertEqual(fetched.first?.metricType, .heartRate)
    }

    func testCreate_allMetricTypes_persistCorrectly() throws {
        for type in WearableMetricType.allCases {
            let entry = TestFixtures.makeWearableEntry(type: type, value: 50)
            try insertAndSave(entry)
        }
        let count = try fetchAll(WearableEntry.self).count
        XCTAssertEqual(count, WearableMetricType.allCases.count)
    }

    func testDelete_entry_removesFromDatabase() throws {
        let entry = TestFixtures.makeWearableEntry()
        try insertAndSave(entry)

        modelContext.delete(entry)
        try modelContext.save()

        XCTAssertTrue(try fetchAll(WearableEntry.self).isEmpty)
    }

    // MARK: - 显示值格式化

    func testDisplayValue_bloodPressure_showsBothValues() {
        let entry = TestFixtures.makeBloodPressureEntry(systolic: 120, diastolic: 80)
        XCTAssertEqual(entry.displayValue, "120/80 mmHg")
    }

    func testDisplayValue_heartRate_showsIntegerWithUnit() {
        let entry = TestFixtures.makeWearableEntry(type: .heartRate, value: 75)
        XCTAssertEqual(entry.displayValue, "75 bpm")
    }

    func testDisplayValue_steps_showsIntegerWithUnit() {
        let entry = TestFixtures.makeWearableEntry(type: .steps, value: 8500)
        XCTAssertEqual(entry.displayValue, "8500 步")
    }

    func testDisplayValue_bloodOxygen_showsOneDecimalPlace() {
        let entry = TestFixtures.makeWearableEntry(type: .bloodOxygen, value: 98.5)
        XCTAssertEqual(entry.displayValue, "98.5 %")
    }

    func testDisplayValue_bloodGlucose_showsOneDecimalPlace() {
        let entry = TestFixtures.makeWearableEntry(type: .bloodGlucose, value: 5.6)
        XCTAssertEqual(entry.displayValue, "5.6 mmol/L")
    }

    // MARK: - 枚举属性

    func testMetricType_rawValueRoundTrip() {
        let entry = TestFixtures.makeWearableEntry(type: .bloodOxygen)
        XCTAssertEqual(entry.metricType, .bloodOxygen)
        XCTAssertEqual(entry.metricTypeRaw, "blood_oxygen")

        entry.metricType = .sleepHours
        XCTAssertEqual(entry.metricTypeRaw, "sleep_hours")
    }

    func testMetricType_invalidRawValue_fallsBackToHeartRate() {
        let entry = TestFixtures.makeWearableEntry()
        entry.metricTypeRaw = "invalid"
        XCTAssertEqual(entry.metricType, .heartRate)
    }

    // MARK: - displayName & unit

    func testAllMetricTypes_haveDisplayNameAndUnit() {
        for type in WearableMetricType.allCases {
            XCTAssertFalse(type.displayName.isEmpty, "\(type) 缺少 displayName")
            XCTAssertFalse(type.unit.isEmpty, "\(type) 缺少 unit")
            XCTAssertFalse(type.icon.isEmpty, "\(type) 缺少 icon")
        }
    }

    // MARK: - 关联成员

    func testEntry_associatesCorrectlyWithMember() throws {
        let member = TestFixtures.makeMember()
        modelContext.insert(member)

        let entry = TestFixtures.makeWearableEntry(type: .heartRate, value: 80)
        entry.member = member
        modelContext.insert(entry)
        try modelContext.save()

        XCTAssertEqual(member.wearableData.count, 1)
        XCTAssertEqual(member.wearableData.first?.value, 80)
    }
}
