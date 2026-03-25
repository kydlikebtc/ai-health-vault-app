import XCTest
@testable import AIHealthVault

/// TrendPeriod 枚举测试
/// 覆盖：rawValue、label、cutoffDate 时间计算、allCases 顺序
@MainActor
final class TrendPeriodTests: XCTestCase {

    // MARK: - rawValue

    func testWeek_rawValueIsSeven() {
        XCTAssertEqual(TrendPeriod.week.rawValue, 7)
    }

    func testMonth_rawValueIsThirty() {
        XCTAssertEqual(TrendPeriod.month.rawValue, 30)
    }

    func testQuarter_rawValueIsNinety() {
        XCTAssertEqual(TrendPeriod.quarter.rawValue, 90)
    }

    func testYear_rawValueIs365() {
        XCTAssertEqual(TrendPeriod.year.rawValue, 365)
    }

    // MARK: - label

    func testLabels_matchExpectedChinese() {
        XCTAssertEqual(TrendPeriod.week.label, "7天")
        XCTAssertEqual(TrendPeriod.month.label, "30天")
        XCTAssertEqual(TrendPeriod.quarter.label, "90天")
        XCTAssertEqual(TrendPeriod.year.label, "1年")
    }

    // MARK: - Identifiable

    func testId_equalsRawValue() {
        for period in TrendPeriod.allCases {
            XCTAssertEqual(period.id, period.rawValue,
                           "\(period.label).id 应等于其 rawValue")
        }
    }

    // MARK: - allCases

    func testAllCasesCount_isFour() {
        XCTAssertEqual(TrendPeriod.allCases.count, 4)
    }

    func testAllCasesOrder_shortestToLongest() {
        let cases = TrendPeriod.allCases
        XCTAssertEqual(cases[0], .week)
        XCTAssertEqual(cases[1], .month)
        XCTAssertEqual(cases[2], .quarter)
        XCTAssertEqual(cases[3], .year)
    }

    // MARK: - cutoffDate

    func testWeek_cutoffDateApproximatelySevenDaysAgo() {
        let cutoff = TrendPeriod.week.cutoffDate
        let expected = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        XCTAssertEqual(cutoff.timeIntervalSince1970,
                       expected.timeIntervalSince1970,
                       accuracy: 2,
                       "week.cutoffDate 应约等于 7 天前")
    }

    func testMonth_cutoffDateApproximatelyThirtyDaysAgo() {
        let cutoff = TrendPeriod.month.cutoffDate
        let expected = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        XCTAssertEqual(cutoff.timeIntervalSince1970,
                       expected.timeIntervalSince1970,
                       accuracy: 2,
                       "month.cutoffDate 应约等于 30 天前")
    }

    func testQuarter_cutoffDateApproximatelyNinetyDaysAgo() {
        let cutoff = TrendPeriod.quarter.cutoffDate
        let expected = Calendar.current.date(byAdding: .day, value: -90, to: Date())!
        XCTAssertEqual(cutoff.timeIntervalSince1970,
                       expected.timeIntervalSince1970,
                       accuracy: 2,
                       "quarter.cutoffDate 应约等于 90 天前")
    }

    func testYear_cutoffDateApproximately365DaysAgo() {
        let cutoff = TrendPeriod.year.cutoffDate
        let expected = Calendar.current.date(byAdding: .day, value: -365, to: Date())!
        XCTAssertEqual(cutoff.timeIntervalSince1970,
                       expected.timeIntervalSince1970,
                       accuracy: 2,
                       "year.cutoffDate 应约等于 365 天前")
    }

    func testAllPeriods_cutoffDateIsInPast() {
        for period in TrendPeriod.allCases {
            XCTAssertLessThan(period.cutoffDate, Date(),
                              "\(period.label).cutoffDate 应早于当前时间")
        }
    }

    // MARK: - 数据过滤场景验证

    func testCutoffDate_weekWindow_includesRecentEntry() {
        let threeDaysAgo = Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        XCTAssertGreaterThanOrEqual(threeDaysAgo, TrendPeriod.week.cutoffDate,
                                    "3 天前的数据应在 7 天窗口内")
    }

    func testCutoffDate_weekWindow_excludesOldEntry() {
        let sixtyDaysAgo = Calendar.current.date(byAdding: .day, value: -60, to: Date())!
        XCTAssertLessThan(sixtyDaysAgo, TrendPeriod.week.cutoffDate,
                          "60 天前的数据应被 7 天窗口过滤掉")
    }

    func testCutoffDate_monthWindow_includesTwentyNineDayEntry() {
        let twentyNineDaysAgo = Calendar.current.date(byAdding: .day, value: -29, to: Date())!
        XCTAssertGreaterThanOrEqual(twentyNineDaysAgo, TrendPeriod.month.cutoffDate,
                                    "29 天前的条目应在 30 天窗口内")
    }

    func testCutoffDate_periodsAreOrdered() {
        // 窗口越长，cutoffDate 越早
        XCTAssertLessThan(TrendPeriod.year.cutoffDate, TrendPeriod.quarter.cutoffDate)
        XCTAssertLessThan(TrendPeriod.quarter.cutoffDate, TrendPeriod.month.cutoffDate)
        XCTAssertLessThan(TrendPeriod.month.cutoffDate, TrendPeriod.week.cutoffDate)
    }
}
