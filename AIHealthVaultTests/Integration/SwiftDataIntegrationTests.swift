import XCTest
import SwiftData
@testable import AIHealthVault

/// 集成测试：验证跨模型关系、完整 CRUD 链路、以及 SwiftData 约束
@MainActor
final class SwiftDataIntegrationTests: SwiftDataTestCase {

    // MARK: - 家庭 → 成员完整链路

    func testFamily_withMultipleMembers_allRelationshipsCorrect() throws {
        let family = TestFixtures.makeFamily(name: "张家")
        modelContext.insert(family)

        let members = ["张父", "张母", "张子"].map { name -> Member in
            let m = TestFixtures.makeMember(name: name)
            m.family = family
            return m
        }
        members.forEach { modelContext.insert($0) }
        try modelContext.save()

        let savedFamily = try fetchAll(Family.self).first
        XCTAssertEqual(savedFamily?.members.count, 3)
        XCTAssertTrue(savedFamily?.members.map(\.name).contains("张父") ?? false)
    }

    // MARK: - 成员 → 全类型健康记录

    func testMember_withAllRecordTypes_completeCRUDChain() throws {
        let member = TestFixtures.makeMember(name: "全记录用户")
        modelContext.insert(member)

        // 各类记录挂载到同一成员
        let medication = TestFixtures.makeMedication()
        medication.member = member
        modelContext.insert(medication)

        let checkup = TestFixtures.makeCheckupReport()
        checkup.member = member
        modelContext.insert(checkup)

        let visit = TestFixtures.makeVisitRecord()
        visit.member = member
        modelContext.insert(visit)

        let history = TestFixtures.makeMedicalHistory()
        history.member = member
        modelContext.insert(history)

        let wearable = TestFixtures.makeWearableEntry(type: .heartRate, value: 72)
        wearable.member = member
        modelContext.insert(wearable)

        let log = TestFixtures.makeDailyLog()
        log.member = member
        modelContext.insert(log)

        try modelContext.save()

        // 验证所有关联
        let saved = try fetchAll(Member.self).first
        XCTAssertEqual(saved?.medications.count, 1)
        XCTAssertEqual(saved?.checkups.count, 1)
        XCTAssertEqual(saved?.visits.count, 1)
        XCTAssertEqual(saved?.medicalHistory.count, 1)
        XCTAssertEqual(saved?.wearableData.count, 1)
        XCTAssertEqual(saved?.dailyTracking.count, 1)
    }

    // MARK: - Cascade Delete 完整链路

    func testDelete_member_cascadeDeletesAllRecordTypes() throws {
        let member = TestFixtures.makeMember()
        modelContext.insert(member)

        // 创建每种类型的记录
        [TestFixtures.makeMedication()].forEach {
            $0.member = member
            modelContext.insert($0)
        }
        [TestFixtures.makeCheckupReport()].forEach {
            $0.member = member
            modelContext.insert($0)
        }
        [TestFixtures.makeVisitRecord()].forEach {
            $0.member = member
            modelContext.insert($0)
        }
        [TestFixtures.makeMedicalHistory()].forEach {
            $0.member = member
            modelContext.insert($0)
        }
        [TestFixtures.makeWearableEntry()].forEach {
            $0.member = member
            modelContext.insert($0)
        }
        [TestFixtures.makeDailyLog()].forEach {
            $0.member = member
            modelContext.insert($0)
        }

        try modelContext.save()

        // 删除成员
        modelContext.delete(member)
        try modelContext.save()

        // 所有关联记录应被级联删除
        XCTAssertTrue(try fetchAll(Member.self).isEmpty)
        XCTAssertTrue(try fetchAll(Medication.self).isEmpty)
        XCTAssertTrue(try fetchAll(CheckupReport.self).isEmpty)
        XCTAssertTrue(try fetchAll(VisitRecord.self).isEmpty)
        XCTAssertTrue(try fetchAll(MedicalHistory.self).isEmpty)
        XCTAssertTrue(try fetchAll(WearableEntry.self).isEmpty)
        XCTAssertTrue(try fetchAll(DailyLog.self).isEmpty)
    }

    // MARK: - 数据隔离性（多成员不互相干扰）

    func testRecords_belongToCorrectMember_noLeakage() throws {
        let memberA = TestFixtures.makeMember(name: "成员A")
        let memberB = TestFixtures.makeMember(name: "成员B")
        modelContext.insert(memberA)
        modelContext.insert(memberB)

        // A 有 2 条用药记录，B 有 1 条
        for i in 1...2 {
            let med = TestFixtures.makeMedication(name: "A的药\(i)")
            med.member = memberA
            modelContext.insert(med)
        }
        let medB = TestFixtures.makeMedication(name: "B的药")
        medB.member = memberB
        modelContext.insert(medB)

        try modelContext.save()

        XCTAssertEqual(memberA.medications.count, 2)
        XCTAssertEqual(memberB.medications.count, 1)
        XCTAssertFalse(memberA.medications.map(\.name).contains("B的药"))
    }

    // MARK: - 大批量数据性能

    func testFetch_1000WearableEntries_completesInReasonableTime() throws {
        let member = TestFixtures.makeMember()
        modelContext.insert(member)

        for i in 0..<1000 {
            let entry = WearableEntry(
                metricType: .steps,
                value: Double(i * 100),
                recordedAt: Calendar.current.date(byAdding: .day, value: -i, to: Date())!
            )
            entry.member = member
            modelContext.insert(entry)
        }
        try modelContext.save()

        measure(metrics: [XCTClockMetric()]) {
            _ = try? fetchAll(WearableEntry.self)
        }
    }

    // MARK: - WearableEntry 多类型汇总

    func testWearableData_multipleTypes_canBeFilteredByType() throws {
        let member = TestFixtures.makeMember()
        modelContext.insert(member)

        let types: [(WearableMetricType, Double)] = [
            (.heartRate, 72), (.heartRate, 75), (.bloodOxygen, 98),
            (.steps, 8000), (.bloodPressure, 120)
        ]
        for (type, value) in types {
            let entry = TestFixtures.makeWearableEntry(type: type, value: value)
            entry.member = member
            modelContext.insert(entry)
        }
        try modelContext.save()

        let heartRateEntries = member.wearableData.filter { $0.metricType == .heartRate }
        XCTAssertEqual(heartRateEntries.count, 2)

        let avgHeartRate = heartRateEntries.map(\.value).reduce(0, +) / Double(heartRateEntries.count)
        XCTAssertEqual(avgHeartRate, 73.5, accuracy: 0.01)
    }
}
