import XCTest
import SwiftData
@testable import AIHealthVault

@MainActor
final class CheckupReportTests: SwiftDataTestCase {

    // MARK: - CRUD

    func testCreate_checkupReport_savesSuccessfully() throws {
        let report = TestFixtures.makeCheckupReport(title: "2024年度体检", hospital: "北京协和医院")
        try insertAndSave(report)

        let fetched = try fetchAll(CheckupReport.self)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.reportTitle, "2024年度体检")
        XCTAssertEqual(fetched.first?.hospitalName, "北京协和医院")
    }

    func testUpdate_addAbnormalItems_persistsCorrectly() throws {
        let report = TestFixtures.makeCheckupReport()
        try insertAndSave(report)

        report.abnormalItems = ["血糖偏高", "尿酸偏高"]
        try modelContext.save()

        let fetched = try fetchAll(CheckupReport.self).first
        XCTAssertEqual(fetched?.abnormalItems.count, 2)
        XCTAssertTrue(fetched?.abnormalItems.contains("血糖偏高") ?? false)
    }

    func testDelete_checkupReport_removesFromDatabase() throws {
        let report = TestFixtures.makeCheckupReport()
        try insertAndSave(report)

        modelContext.delete(report)
        try modelContext.save()

        XCTAssertTrue(try fetchAll(CheckupReport.self).isEmpty)
    }

    // MARK: - 计算属性

    func testHasAbnormalItems_withAbnormalItems_returnsTrue() {
        let report = TestFixtures.makeCheckupReport()
        report.abnormalItems = ["血糖偏高"]
        XCTAssertTrue(report.hasAbnormalItems)
    }

    func testHasAbnormalItems_withEmptyList_returnsFalse() {
        let report = TestFixtures.makeCheckupReport()
        XCTAssertFalse(report.hasAbnormalItems)
    }

    // MARK: - 附件

    func testAttachmentPaths_canStoreMultiplePaths() throws {
        let report = TestFixtures.makeCheckupReport()
        report.attachmentPaths = ["/path/to/report1.pdf", "/path/to/scan.jpg"]
        try insertAndSave(report)

        let fetched = try fetchAll(CheckupReport.self).first
        XCTAssertEqual(fetched?.attachmentPaths.count, 2)
    }

    // MARK: - 关联成员

    func testCheckupReport_associatesWithMember() throws {
        let member = TestFixtures.makeMember()
        modelContext.insert(member)

        let report = TestFixtures.makeCheckupReport(title: "2024体检")
        report.member = member
        modelContext.insert(report)
        try modelContext.save()

        XCTAssertEqual(member.checkups.count, 1)
        XCTAssertEqual(member.checkups.first?.reportTitle, "2024体检")
    }

    func testMultipleReports_perMember_allAssociated() throws {
        let member = TestFixtures.makeMember()
        modelContext.insert(member)

        for year in [2022, 2023, 2024] {
            let report = TestFixtures.makeCheckupReport(title: "\(year)年体检")
            report.member = member
            modelContext.insert(report)
        }
        try modelContext.save()

        XCTAssertEqual(member.checkups.count, 3)
    }
}
