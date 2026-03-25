import SwiftData
import Foundation

private extension Double {
    func rounded(to places: Int) -> Double {
        let factor = pow(10.0, Double(places))
        return (self * factor).rounded() / factor
    }
}

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

        // 为爸爸生成 90 天历史可穿戴数据（用于趋势图 Preview）
        dad.wearableData.append(contentsOf: makeTrendWearableData(for: dad, days: 90))

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

    // MARK: - 趋势数据生成（模拟90天历史记录）

    /// 为指定成员生成多天的各项可穿戴指标记录，模拟真实波动
    static func makeTrendWearableData(for member: Member, days: Int) -> [WearableEntry] {
        let cal = Calendar.current
        var entries: [WearableEntry] = []

        // 基准值（结合成员特征）
        let baseWeight = member.weightKg ?? 70.0
        let baseSystolic: Double = member.chronicConditions.contains("高血压") ? 138 : 118
        let baseDiastolic: Double = member.chronicConditions.contains("高血压") ? 88 : 76

        for dayOffset in stride(from: -(days - 1), through: 0, by: 1) {
            guard let date = cal.date(byAdding: .day, value: dayOffset, to: cal.startOfDay(for: Date())) else { continue }

            // 体重（缓慢下降趋势 + 小波动）
            let weightNoise = Double.random(in: -0.4...0.4)
            let weightTrend = Double(dayOffset + days) / Double(days) * 1.5  // 最近比90天前轻~1.5kg
            entries.append(WearableEntry(
                metricType: .weight,
                value: (baseWeight + weightTrend + weightNoise).rounded(to: 1),
                recordedAt: date.addingTimeInterval(7 * 3600),  // 早7点
                source: "手动录入"
            ))

            // 血压（每3天一次）
            if dayOffset % 3 == 0 {
                let sNoise = Double.random(in: -8...8)
                let dNoise = Double.random(in: -5...5)
                entries.append(WearableEntry(
                    metricType: .bloodPressure,
                    value: (baseSystolic + sNoise).rounded(),
                    secondaryValue: (baseDiastolic + dNoise).rounded(),
                    recordedAt: date.addingTimeInterval(8 * 3600),
                    source: "血压计"
                ))
            }

            // 心率（每天）
            let hrNoise = Double.random(in: -10...10)
            entries.append(WearableEntry(
                metricType: .heartRate,
                value: (72 + hrNoise).rounded(),
                recordedAt: date.addingTimeInterval(8.5 * 3600),
                source: "Apple Watch"
            ))

            // 步数（每天，周末略多）
            let isWeekend = cal.isDateInWeekend(date)
            let baseSteps: Double = isWeekend ? 9500 : 7200
            let stepsNoise = Double.random(in: -2000...3000)
            entries.append(WearableEntry(
                metricType: .steps,
                value: max(500, baseSteps + stepsNoise).rounded(),
                recordedAt: date.addingTimeInterval(22 * 3600),  // 晚10点汇总
                source: "Apple Health"
            ))

            // 睡眠（每天）
            let sleepNoise = Double.random(in: -1.5...1.0)
            entries.append(WearableEntry(
                metricType: .sleepHours,
                value: max(4.0, min(10.0, 7.2 + sleepNoise)).rounded(to: 1),
                recordedAt: date.addingTimeInterval(7.5 * 3600),
                source: "Apple Watch"
            ))

            // 血氧（每3天一次）
            if dayOffset % 3 == 0 {
                let spo2Noise = Double.random(in: -2...1)
                entries.append(WearableEntry(
                    metricType: .bloodOxygen,
                    value: min(100, max(93, 97 + spo2Noise)).rounded(to: 1),
                    recordedAt: date.addingTimeInterval(8 * 3600),
                    source: "Apple Watch"
                ))
            }
        }

        return entries
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

    /// 带完整趋势数据的成员（用于 HealthTrendView Preview）
    @MainActor
    static var sampleMemberWithTrends: Member {
        let m = makeMember(name: "张大海", age: 48, gender: .male, bloodType: .aPositive, height: 175, weight: 78)
        m.chronicConditions = ["高血压", "高血脂"]
        m.wearableData = makeTrendWearableData(for: m, days: 90)
        return m
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
