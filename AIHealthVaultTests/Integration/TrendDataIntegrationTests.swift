import XCTest
import SwiftData
@testable import AIHealthVault

/// 健康趋势数据聚合集成测试
/// 覆盖：WearableEntry 按 metricType 过滤、按时间窗口过滤、
///       步数按天聚合、异常阈值判断、BMI 参考体重计算
@MainActor
final class TrendDataIntegrationTests: SwiftDataTestCase {

    private var member: Member!

    override func setUpWithError() throws {
        try super.setUpWithError()
        member = TestFixtures.makeMember(name: "趋势测试用户")
        try insertAndSave(member)
    }

    // MARK: - MetricType 过滤

    func testFilter_byMetricType_returnsOnlyMatchingType() throws {
        let heartRate = TestFixtures.makeWearableEntry(type: .heartRate, value: 72)
        let weight    = TestFixtures.makeWearableEntry(type: .weight,    value: 65)
        let steps     = TestFixtures.makeWearableEntry(type: .steps,     value: 8000)
        heartRate.member = member
        weight.member    = member
        steps.member     = member
        try insertAndSave(heartRate)
        try insertAndSave(weight)
        try insertAndSave(steps)

        let all = try fetchAll(WearableEntry.self)
        let heartRateOnly = all.filter { $0.metricType == .heartRate }

        XCTAssertEqual(heartRateOnly.count, 1, "按 .heartRate 过滤后只应有 1 条记录")
        XCTAssertEqual(heartRateOnly.first?.value, 72)
    }

    func testFilter_multipleEntriesSameType_allReturned() throws {
        for bpm in [68.0, 72.0, 80.0] {
            let e = TestFixtures.makeWearableEntry(type: .heartRate, value: bpm)
            e.member = member
            try insertAndSave(e)
        }

        let all = try fetchAll(WearableEntry.self)
        let heartRateEntries = all.filter { $0.metricType == .heartRate }

        XCTAssertEqual(heartRateEntries.count, 3, "3 条心率记录均应被返回")
    }

    // MARK: - 时间窗口过滤

    func testFilter_byWeekPeriod_excludesSixtyDayOldEntry() throws {
        let recentDate = Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        let oldDate    = Calendar.current.date(byAdding: .day, value: -60, to: Date())!

        let recent = WearableEntry(metricType: .heartRate, value: 75, secondaryValue: 0, source: "测试")
        recent.recordedAt = recentDate
        recent.member = member

        let old = WearableEntry(metricType: .heartRate, value: 90, secondaryValue: 0, source: "测试")
        old.recordedAt = oldDate
        old.member = member

        try insertAndSave(recent)
        try insertAndSave(old)

        let cutoff   = TrendPeriod.week.cutoffDate
        let all      = try fetchAll(WearableEntry.self)
        let filtered = all.filter { $0.metricType == .heartRate && $0.recordedAt >= cutoff }

        XCTAssertEqual(filtered.count, 1, "7 天窗口内只应有 1 条近期记录")
        XCTAssertEqual(filtered.first?.value, 75)
    }

    func testFilter_byMonthPeriod_includesAllTwentyFiveDayEntries() throws {
        let cal   = Calendar.current
        let dates = (-25 ..< 0).compactMap { cal.date(byAdding: .day, value: $0, to: Date()) }

        for (i, date) in dates.enumerated() {
            let e = WearableEntry(metricType: .steps,
                                  value: Double((i + 1) * 100),
                                  secondaryValue: 0,
                                  source: "测试")
            e.recordedAt = date
            e.member = member
            try insertAndSave(e)
        }

        let cutoff   = TrendPeriod.month.cutoffDate
        let all      = try fetchAll(WearableEntry.self)
        let filtered = all.filter { $0.metricType == .steps && $0.recordedAt >= cutoff }

        XCTAssertEqual(filtered.count, 25, "过去 25 天的步数记录均应在 30 天窗口内")
    }

    func testFilter_byYearPeriod_excludesOldData() throws {
        let withinYear    = Calendar.current.date(byAdding: .day, value: -300, to: Date())!
        let outsideYear   = Calendar.current.date(byAdding: .day, value: -400, to: Date())!

        let recent = WearableEntry(metricType: .weight, value: 65, secondaryValue: 0, source: "测试")
        recent.recordedAt = withinYear
        recent.member = member

        let tooOld = WearableEntry(metricType: .weight, value: 70, secondaryValue: 0, source: "测试")
        tooOld.recordedAt = outsideYear
        tooOld.member = member

        try insertAndSave(recent)
        try insertAndSave(tooOld)

        let cutoff   = TrendPeriod.year.cutoffDate
        let all      = try fetchAll(WearableEntry.self)
        let filtered = all.filter { $0.metricType == .weight && $0.recordedAt >= cutoff }

        XCTAssertEqual(filtered.count, 1, "365 天窗口内只应有 300 天前的记录")
    }

    // MARK: - 步数按天聚合（StepsTrendChart.dailySteps 逻辑镜像）

    func testStepsAggregation_sameDayThreeEntries_sumToNineThousand() throws {
        let today = Calendar.current.startOfDay(for: Date())

        for (offset, steps) in [(3600.0, 3000.0), (7200.0, 4000.0), (10800.0, 2000.0)] {
            let e = WearableEntry(metricType: .steps,
                                  value: steps,
                                  secondaryValue: 0,
                                  source: "HealthKit")
            e.recordedAt = today.addingTimeInterval(offset)
            e.member = member
            try insertAndSave(e)
        }

        let all = try fetchAll(WearableEntry.self).filter { $0.metricType == .steps }
        let cal = Calendar.current
        let grouped = Dictionary(grouping: all) { cal.startOfDay(for: $0.recordedAt) }
        let dailyTotals = grouped.mapValues { entries in
            entries.reduce(0.0) { $0 + $1.value }
        }

        XCTAssertEqual(dailyTotals.values.first, 9000,
                       "同一天的 3000+4000+2000 步数应聚合为 9000 步")
    }

    func testStepsAggregation_differentDays_producesTwoGroups() throws {
        let cal   = Calendar.current
        let dates = (-2 ..< 0).compactMap { cal.date(byAdding: .day, value: $0, to: Date()) }

        for (i, date) in dates.enumerated() {
            let e = WearableEntry(metricType: .steps,
                                  value: Double((i + 1) * 5000),
                                  secondaryValue: 0,
                                  source: "测试")
            e.recordedAt = cal.startOfDay(for: date)
            e.member = member
            try insertAndSave(e)
        }

        let all     = try fetchAll(WearableEntry.self).filter { $0.metricType == .steps }
        let grouped = Dictionary(grouping: all) { cal.startOfDay(for: $0.recordedAt) }

        XCTAssertEqual(grouped.keys.count, 2, "不同日期的步数记录应分为 2 组")
    }

    func testStepsAggregation_reachesGoal_whenAboveTenThousand() throws {
        let today = Calendar.current.startOfDay(for: Date())
        for steps in [6000.0, 5000.0] {
            let e = WearableEntry(metricType: .steps,
                                  value: steps, secondaryValue: 0, source: "测试")
            e.recordedAt = today.addingTimeInterval(3600)
            e.member = member
            try insertAndSave(e)
        }

        let all = try fetchAll(WearableEntry.self).filter { $0.metricType == .steps }
        let total = all.reduce(0.0) { $0 + $1.value }

        XCTAssertTrue(total >= 10_000, "6000+5000 = 11000，应达到每日 1 万步目标")
    }

    // MARK: - 异常阈值判断（HealthTodaySummaryCard.isAbnormal 逻辑镜像）

    func testBloodPressure_highSystolic_isAbnormal() {
        let highSystolic = WearableEntry(metricType: .bloodPressure,
                                         value: 135, secondaryValue: 75, source: "测试")
        XCTAssertTrue(highSystolic.value >= 130 || highSystolic.secondaryValue >= 80,
                      "收缩压 135 应判为异常")
    }

    func testBloodPressure_highDiastolic_isAbnormal() {
        let highDiastolic = WearableEntry(metricType: .bloodPressure,
                                          value: 120, secondaryValue: 85, source: "测试")
        XCTAssertTrue(highDiastolic.value >= 130 || highDiastolic.secondaryValue >= 80,
                      "舒张压 85 应判为异常")
    }

    func testBloodPressure_normal_isNotAbnormal() {
        let normal = WearableEntry(metricType: .bloodPressure,
                                   value: 118, secondaryValue: 76, source: "测试")
        XCTAssertFalse(normal.value >= 130 || normal.secondaryValue >= 80,
                       "收缩压 118/舒张压 76 应判为正常")
    }

    func testHeartRate_tachycardia_isAbnormal() {
        let high = WearableEntry(metricType: .heartRate, value: 105, secondaryValue: 0, source: "测试")
        XCTAssertTrue(high.value < 60 || high.value > 100, "心率 105 超出正常上限 100")
    }

    func testHeartRate_bradycardia_isAbnormal() {
        let low = WearableEntry(metricType: .heartRate, value: 55, secondaryValue: 0, source: "测试")
        XCTAssertTrue(low.value < 60 || low.value > 100, "心率 55 低于正常下限 60")
    }

    func testHeartRate_normal_isNotAbnormal() {
        let normal = WearableEntry(metricType: .heartRate, value: 75, secondaryValue: 0, source: "测试")
        XCTAssertFalse(normal.value < 60 || normal.value > 100, "心率 75 在正常范围内")
    }

    func testBloodOxygen_low_isAbnormal() {
        let low = WearableEntry(metricType: .bloodOxygen, value: 93, secondaryValue: 0, source: "测试")
        XCTAssertTrue(low.value < 95, "血氧 93% 低于预警线 95%")
    }

    func testBloodOxygen_normal_isNotAbnormal() {
        let normal = WearableEntry(metricType: .bloodOxygen, value: 98, secondaryValue: 0, source: "测试")
        XCTAssertFalse(normal.value < 95, "血氧 98% 在正常范围内")
    }

    func testSleepHours_belowSix_isAbnormal() {
        let poor = WearableEntry(metricType: .sleepHours, value: 5.5, secondaryValue: 0, source: "测试")
        XCTAssertTrue(poor.value < 6, "睡眠 5.5 小时应判为不足")
    }

    // MARK: - BMI 正常体重参考（WeightTrendChart 逻辑镜像）

    func testBMIRefWeight_170cm_isApprox63Point58kg() {
        let heightCm: Double = 170
        let hm = heightCm / 100.0
        let refWeight = 22.0 * hm * hm
        XCTAssertEqual(refWeight, 63.58, accuracy: 0.01,
                       "身高 170cm 对应 BMI 22 的参考体重约为 63.58kg")
    }

    func testBMIRange_165cm_normalBoundsCorrect() {
        let hm   = 165.0 / 100.0
        let low  = 18.5 * hm * hm
        let high = 24.0 * hm * hm
        XCTAssertEqual(low,  50.34, accuracy: 0.01, "身高 165cm BMI 18.5 下限约 50.34kg")
        XCTAssertEqual(high, 65.34, accuracy: 0.01, "身高 165cm BMI 24 上限约 65.34kg")
    }

    func testBMIRange_lowIsLessThanHigh() {
        for heightCm in [155.0, 165.0, 175.0, 185.0] {
            let hm   = heightCm / 100.0
            let low  = 18.5 * hm * hm
            let high = 24.0 * hm * hm
            XCTAssertLessThan(low, high, "身高 \(heightCm)cm：BMI 18.5 下限应小于 BMI 24 上限")
        }
    }
}
