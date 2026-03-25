import XCTest
@testable import AIHealthVault

/// PDFExportService 单元测试
/// 测试范围：ExportTimeRange 枚举逻辑、ExportOptions 默认值
/// 注意：generateHealthReport 依赖 UIKit/Core Graphics，需在模拟器完整测试
final class PDFExportServiceTests: XCTestCase {

    // MARK: - ExportTimeRange.rawValue（展示文案稳定性）

    func testExportTimeRange_rawValues_areStable() {
        XCTAssertEqual(ExportTimeRange.threeMonths.rawValue, "近3个月")
        XCTAssertEqual(ExportTimeRange.sixMonths.rawValue, "近6个月")
        XCTAssertEqual(ExportTimeRange.oneYear.rawValue, "近1年")
        XCTAssertEqual(ExportTimeRange.allTime.rawValue, "全部")
    }

    func testExportTimeRange_allCases_haveNonEmptyRawValue() {
        for range in ExportTimeRange.allCases {
            XCTAssertFalse(range.rawValue.isEmpty, "\(range) 缺少 rawValue")
        }
    }

    func testExportTimeRange_allCasesCount_isFour() {
        XCTAssertEqual(ExportTimeRange.allCases.count, 4)
    }

    // MARK: - ExportTimeRange.cutoffDate

    func testCutoffDate_allTime_returnsNil() {
        XCTAssertNil(ExportTimeRange.allTime.cutoffDate, "全部时间段不应有截止日期")
    }

    func testCutoffDate_threeMonths_returnsDateInPast() {
        guard let cutoff = ExportTimeRange.threeMonths.cutoffDate else {
            XCTFail("近3个月应有有效截止日期")
            return
        }
        XCTAssertLessThan(cutoff, Date(), "截止日期应在当前时间之前")
    }

    func testCutoffDate_sixMonths_returnsDateInPast() {
        guard let cutoff = ExportTimeRange.sixMonths.cutoffDate else {
            XCTFail("近6个月应有有效截止日期")
            return
        }
        XCTAssertLessThan(cutoff, Date())
    }

    func testCutoffDate_oneYear_returnsDateInPast() {
        guard let cutoff = ExportTimeRange.oneYear.cutoffDate else {
            XCTFail("近1年应有有效截止日期")
            return
        }
        XCTAssertLessThan(cutoff, Date())
    }

    func testCutoffDate_threeMonths_isAfterSixMonths() {
        // 近3个月的截止日期应晚于近6个月
        guard let threeM = ExportTimeRange.threeMonths.cutoffDate,
              let sixM   = ExportTimeRange.sixMonths.cutoffDate else {
            XCTFail("截止日期不应为 nil")
            return
        }
        XCTAssertGreaterThan(threeM, sixM, "近3个月的截止日期应晚于近6个月")
    }

    func testCutoffDate_sixMonths_isAfterOneYear() {
        guard let sixM  = ExportTimeRange.sixMonths.cutoffDate,
              let oneY  = ExportTimeRange.oneYear.cutoffDate else {
            XCTFail("截止日期不应为 nil")
            return
        }
        XCTAssertGreaterThan(sixM, oneY, "近6个月的截止日期应晚于近1年")
    }

    func testCutoffDate_threeMonths_approximatelyCorrect() {
        guard let cutoff = ExportTimeRange.threeMonths.cutoffDate else { return }
        let expectedDate = Calendar.current.date(byAdding: .month, value: -3, to: Date())!
        // 允许 5 秒误差（测试执行时间差）
        XCTAssertEqual(cutoff.timeIntervalSince1970,
                       expectedDate.timeIntervalSince1970,
                       accuracy: 5.0,
                       "近3个月截止日期应近似于当前时间减3个月")
    }

    func testCutoffDate_oneYear_approximatelyCorrect() {
        guard let cutoff = ExportTimeRange.oneYear.cutoffDate else { return }
        let expectedDate = Calendar.current.date(byAdding: .year, value: -1, to: Date())!
        XCTAssertEqual(cutoff.timeIntervalSince1970,
                       expectedDate.timeIntervalSince1970,
                       accuracy: 5.0)
    }

    // MARK: - ExportOptions 默认值

    func testExportOptions_defaultTimeRange_isOneYear() {
        let options = ExportOptions()
        XCTAssertEqual(options.timeRange, .oneYear)
    }

    func testExportOptions_defaultIncludeMedicalHistory_isTrue() {
        XCTAssertTrue(ExportOptions().includeMedicalHistory)
    }

    func testExportOptions_defaultIncludeMedications_isTrue() {
        XCTAssertTrue(ExportOptions().includeMedications)
    }

    func testExportOptions_defaultIncludeCheckups_isTrue() {
        XCTAssertTrue(ExportOptions().includeCheckups)
    }

    func testExportOptions_defaultIncludeVisits_isTrue() {
        XCTAssertTrue(ExportOptions().includeVisits)
    }

    func testExportOptions_defaultIncludeWearable_isTrue() {
        XCTAssertTrue(ExportOptions().includeWearable)
    }

    func testExportOptions_allSectionsEnabled_byDefault() {
        let opts = ExportOptions()
        let allEnabled = opts.includeMedicalHistory
            && opts.includeMedications
            && opts.includeCheckups
            && opts.includeVisits
            && opts.includeWearable
        XCTAssertTrue(allEnabled, "默认导出选项应启用全部模块")
    }

    func testExportOptions_isMutable() {
        var opts = ExportOptions()
        opts.timeRange = .threeMonths
        opts.includeMedications = false
        XCTAssertEqual(opts.timeRange, .threeMonths)
        XCTAssertFalse(opts.includeMedications)
    }

    // MARK: - 过滤逻辑约定（无需运行 PDF 渲染）

    func testFilterLogic_allTime_includesAllDates() {
        // allTime 的 cutoffDate 为 nil，约定过滤时返回全部
        let cutoff: Date? = ExportTimeRange.allTime.cutoffDate
        let testDate = Date.distantPast
        let included = cutoff == nil || testDate >= cutoff!
        XCTAssertTrue(included, "allTime 应包含所有历史日期")
    }

    func testFilterLogic_threeMonths_excludesOldDates() {
        guard let cutoff = ExportTimeRange.threeMonths.cutoffDate else { return }
        let oldDate = Date.distantPast
        XCTAssertFalse(oldDate >= cutoff, "近3个月过滤应排除早期日期")
    }

    func testFilterLogic_threeMonths_includesRecentDates() {
        guard let cutoff = ExportTimeRange.threeMonths.cutoffDate else { return }
        let recentDate = Date()
        XCTAssertTrue(recentDate >= cutoff, "近3个月过滤应包含近期日期")
    }
}
