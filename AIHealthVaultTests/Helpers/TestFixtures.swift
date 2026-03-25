import Foundation
@testable import AIHealthVault

/// 统一的测试数据工厂
/// 使用工厂方法而非静态属性，避免测试间共享可变对象
enum TestFixtures {

    // MARK: - Member

    static func makeMember(
        name: String = "测试用户",
        gender: Gender = .female,
        bloodType: BloodType = .aPositive
    ) -> Member {
        let member = Member(name: name, gender: gender, bloodType: bloodType)
        member.birthday = Calendar.current.date(
            from: DateComponents(year: 1990, month: 6, day: 15)
        )
        member.heightCm = 165
        member.weightKg = 58
        return member
    }

    // MARK: - Medication

    static func makeMedication(
        name: String = "阿司匹林",
        dosage: String = "100mg",
        frequency: MedicationFrequency = .daily
    ) -> Medication {
        Medication(name: name, dosage: dosage, frequency: frequency)
    }

    // MARK: - CheckupReport

    static func makeCheckupReport(
        title: String = "2024年度体检",
        hospital: String = "北京协和医院"
    ) -> CheckupReport {
        let report = CheckupReport(
            checkupDate: Calendar.current.date(from: DateComponents(year: 2024, month: 3, day: 1))!,
            hospitalName: hospital,
            reportTitle: title
        )
        report.summary = "总体状况良好"
        return report
    }

    // MARK: - VisitRecord

    static func makeVisitRecord(
        hospital: String = "上海仁济医院",
        visitType: VisitType = .outpatient
    ) -> VisitRecord {
        let record = VisitRecord(
            visitDate: Calendar.current.date(from: DateComponents(year: 2024, month: 5, day: 20))!,
            visitType: visitType,
            hospitalName: hospital,
            department: "内科"
        )
        record.doctorName = "王医生"
        record.diagnosis = "普通感冒"
        return record
    }

    // MARK: - WearableEntry

    static func makeWearableEntry(
        type: WearableMetricType = .heartRate,
        value: Double = 72,
        secondaryValue: Double = 0
    ) -> WearableEntry {
        WearableEntry(
            metricType: type,
            value: value,
            secondaryValue: secondaryValue,
            source: "Apple Watch"
        )
    }

    static func makeBloodPressureEntry(systolic: Double = 120, diastolic: Double = 80) -> WearableEntry {
        WearableEntry(
            metricType: .bloodPressure,
            value: systolic,
            secondaryValue: diastolic,
            source: "手动录入"
        )
    }

    // MARK: - MedicalHistory

    static func makeMedicalHistory(
        condition: String = "高血压",
        isChronic: Bool = true
    ) -> MedicalHistory {
        MedicalHistory(
            conditionName: condition,
            diagnosedDate: Calendar.current.date(from: DateComponents(year: 2020, month: 1, day: 1)),
            hospitalName: "北京协和医院",
            treatmentSummary: "长期服药控制",
            isChronic: isChronic
        )
    }

    // MARK: - DailyLog

    static func makeDailyLog(date: Date = Date()) -> DailyLog {
        let log = DailyLog(date: date)
        log.moodLevel = MoodLevel.good.rawValue
        log.energyLevel = 4
        log.waterIntakeMl = 2000
        log.exerciseMinutes = 30
        log.sleepHours = 7.5
        return log
    }

    // MARK: - Family

    static func makeFamily(name: String = "我的家庭") -> Family {
        Family(name: name)
    }

    // MARK: - CustomReminder

    static func makeCustomReminder(
        title: String = "复诊提醒",
        reminderDate: Date = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 1, hour: 9))!,
        notes: String = "别忘记带化验单"
    ) -> CustomReminder {
        CustomReminder(title: title, reminderDate: reminderDate, notes: notes)
    }
}
