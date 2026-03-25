import SwiftData
import Foundation

/// 用于 SwiftUI Preview 和测试的 Mock 数据工厂
@MainActor
enum MockData {

    // MARK: - 预览用 ModelContainer

    static var previewContainer: ModelContainer = {
        let schema = Schema([
            Family.self,
            Member.self,
            MedicalHistory.self,
            Medication.self,
            CheckupReport.self,
            VisitRecord.self,
            WearableEntry.self,
            DailyLog.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        seedSampleData(into: container)
        return container
    }()

    // MARK: - 预填充示例数据

    static func seedSampleData(into container: ModelContainer) {
        let context = container.mainContext
        let family = Family(name: "张家")

        let dad = makeMember(
            name: "张大海",
            age: 48,
            gender: .male,
            bloodType: .aPositive,
            height: 175,
            weight: 78
        )
        dad.chronicConditions = ["高血压", "高血脂"]
        dad.allergies = ["青霉素"]

        let mom = makeMember(
            name: "李美华",
            age: 45,
            gender: .female,
            bloodType: .bPositive,
            height: 162,
            weight: 58
        )

        let child = makeMember(
            name: "张小明",
            age: 12,
            gender: .male,
            bloodType: .abPositive,
            height: 155,
            weight: 45
        )

        // 为爸爸添加用药记录
        let med = Medication(
            name: "氨氯地平片",
            dosage: "5mg",
            frequency: .daily,
            startDate: Calendar.current.date(byAdding: .month, value: -6, to: Date())!,
            prescribedBy: "王医生"
        )
        med.purpose = "控制高血压"
        dad.medications.append(med)

        // 为爸爸添加就诊记录
        let visit = VisitRecord(
            visitDate: Calendar.current.date(byAdding: .day, value: -30, to: Date())!,
            visitType: .outpatient,
            hospitalName: "北京协和医院",
            department: "心内科"
        )
        visit.doctorName = "王主任"
        visit.diagnosis = "原发性高血压"
        visit.treatment = "继续服用降压药，低盐饮食"
        dad.visits.append(visit)

        // 为妈妈添加体检报告
        let checkup = CheckupReport(
            checkupDate: Calendar.current.date(byAdding: .month, value: -2, to: Date())!,
            hospitalName: "体检中心",
            reportTitle: "2025年度健康体检"
        )
        checkup.summary = "整体健康状况良好，建议增加运动。"
        checkup.abnormalItems = ["总胆固醇偏高"]
        mom.checkups.append(checkup)

        // 可穿戴数据示例
        let heartRate = WearableEntry(
            metricType: .heartRate,
            value: 72,
            recordedAt: Date(),
            source: "Apple Watch"
        )
        dad.wearableData.append(heartRate)

        // 日常日志示例
        let log = DailyLog(date: Date())
        log.mood = .good
        log.energyLevel = 4
        log.waterIntakeMl = 1500
        log.exerciseMinutes = 30
        log.sleepHours = 7.5
        dad.dailyTracking.append(log)

        family.members.append(contentsOf: [dad, mom, child])
        context.insert(family)
    }

    // MARK: - 辅助

    private static func makeMember(
        name: String,
        age: Int,
        gender: Gender,
        bloodType: BloodType,
        height: Double,
        weight: Double
    ) -> Member {
        let m = Member(name: name, gender: gender, bloodType: bloodType)
        var components = DateComponents()
        components.year = Calendar.current.component(.year, from: Date()) - age
        m.birthday = Calendar.current.date(from: components)
        m.heightCm = height
        m.weightKg = weight
        return m
    }

    // MARK: - 单体 Preview 辅助

    static var sampleMember: Member {
        makeMember(name: "张大海", age: 48, gender: .male, bloodType: .aPositive, height: 175, weight: 78)
    }

    static var sampleFamily: Family {
        let f = Family(name: "张家")
        f.members = [
            makeMember(name: "张大海", age: 48, gender: .male, bloodType: .aPositive, height: 175, weight: 78),
            makeMember(name: "李美华", age: 45, gender: .female, bloodType: .bPositive, height: 162, weight: 58),
            makeMember(name: "张小明", age: 12, gender: .male, bloodType: .abPositive, height: 155, weight: 45)
        ]
        return f
    }
}
