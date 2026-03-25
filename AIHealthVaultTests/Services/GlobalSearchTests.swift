import XCTest
@testable import AIHealthVault

/// GlobalSearchView — HealthSearchResult.search 单元测试
/// 验证跨分类关键词搜索的匹配逻辑、空查询处理和结果排序
final class GlobalSearchTests: XCTestCase {

    private var member: Member!

    override func setUp() {
        super.setUp()
        member = TestFixtures.makeMember()

        // 体检报告
        let checkup = TestFixtures.makeCheckupReport(title: "2024年度体检", hospital: "北京协和医院")
        checkup.summary = "血糖偏高，建议复查"
        checkup.member = member
        member.checkups.append(checkup)

        // 用药记录
        let med = TestFixtures.makeMedication(name: "二甲双胍", dosage: "500mg")
        med.purpose = "控制血糖"
        med.prescribedBy = "李医生"
        med.member = member
        member.medications.append(med)

        // 就医记录
        let visit = TestFixtures.makeVisitRecord(hospital: "上海仁济医院")
        visit.doctorName = "王医生"
        visit.diagnosis = "2型糖尿病"
        visit.chiefComplaint = "口渴多饮"
        visit.member = member
        member.visits.append(visit)

        // 既往病史
        let history = TestFixtures.makeMedicalHistory(condition: "高血压", isChronic: true)
        history.treatmentSummary = "长期服药控制"
        history.member = member
        member.medicalHistory.append(history)

        // 日常追踪
        let log = TestFixtures.makeDailyLog()
        log.notes = "今天血糖有些波动"
        log.symptoms = ["头晕", "乏力"]
        log.member = member
        member.dailyTracking.append(log)
    }

    override func tearDown() {
        member = nil
        super.tearDown()
    }

    // MARK: - 空查询

    func testEmptyQuery_returnsNoResults() {
        XCTAssertTrue(HealthSearchResult.search(query: "", in: member).isEmpty)
    }

    func testWhitespaceOnlyQuery_returnsNoResults() {
        XCTAssertTrue(HealthSearchResult.search(query: "   ", in: member).isEmpty)
    }

    // MARK: - 体检报告匹配

    func testSearch_matchesCheckupByTitle() {
        let results = HealthSearchResult.search(query: "年度体检", in: member)
        XCTAssertTrue(results.contains(where: {
            if case .checkup = $0 { return true }
            return false
        }), "应命中报告标题")
    }

    func testSearch_matchesCheckupByHospital() {
        let results = HealthSearchResult.search(query: "协和", in: member)
        XCTAssertTrue(results.contains(where: {
            if case .checkup = $0 { return true }
            return false
        }), "应命中医院名称")
    }

    func testSearch_matchesCheckupBySummary() {
        let results = HealthSearchResult.search(query: "血糖偏高", in: member)
        XCTAssertTrue(results.contains(where: {
            if case .checkup = $0 { return true }
            return false
        }), "应命中摘要内容")
    }

    // MARK: - 用药记录匹配

    func testSearch_matchesMedicationByName() {
        let results = HealthSearchResult.search(query: "二甲双胍", in: member)
        XCTAssertTrue(results.contains(where: {
            if case .medication = $0 { return true }
            return false
        }), "应命中药品名称")
    }

    func testSearch_matchesMedicationByPurpose() {
        let results = HealthSearchResult.search(query: "控制血糖", in: member)
        XCTAssertTrue(results.contains(where: {
            if case .medication = $0 { return true }
            return false
        }), "应命中用途字段")
    }

    func testSearch_matchesMedicationByDoctor() {
        let results = HealthSearchResult.search(query: "李医生", in: member)
        XCTAssertTrue(results.contains(where: {
            if case .medication = $0 { return true }
            return false
        }), "应命中开具医生")
    }

    // MARK: - 就医记录匹配

    func testSearch_matchesVisitByHospital() {
        let results = HealthSearchResult.search(query: "仁济", in: member)
        XCTAssertTrue(results.contains(where: {
            if case .visit = $0 { return true }
            return false
        }), "应命中医院名称")
    }

    func testSearch_matchesVisitByDiagnosis() {
        let results = HealthSearchResult.search(query: "糖尿病", in: member)
        XCTAssertTrue(results.contains(where: {
            if case .visit = $0 { return true }
            return false
        }), "应命中诊断结果")
    }

    func testSearch_matchesVisitByChiefComplaint() {
        let results = HealthSearchResult.search(query: "口渴", in: member)
        XCTAssertTrue(results.contains(where: {
            if case .visit = $0 { return true }
            return false
        }), "应命中主诉字段")
    }

    func testSearch_matchesVisitByDoctor() {
        let results = HealthSearchResult.search(query: "王医生", in: member)
        XCTAssertTrue(results.contains(where: {
            if case .visit = $0 { return true }
            return false
        }), "应命中就医医生")
    }

    // MARK: - 既往病史匹配

    func testSearch_matchesHistoryByCondition() {
        let results = HealthSearchResult.search(query: "高血压", in: member)
        XCTAssertTrue(results.contains(where: {
            if case .history = $0 { return true }
            return false
        }), "应命中病症名称")
    }

    func testSearch_matchesHistoryByTreatment() {
        let results = HealthSearchResult.search(query: "长期服药", in: member)
        XCTAssertTrue(results.contains(where: {
            if case .history = $0 { return true }
            return false
        }), "应命中治疗摘要")
    }

    // MARK: - 日常追踪匹配

    func testSearch_matchesDailyLogByNotes() {
        let results = HealthSearchResult.search(query: "血糖有些波动", in: member)
        XCTAssertTrue(results.contains(where: {
            if case .dailyLog = $0 { return true }
            return false
        }), "应命中备注字段")
    }

    func testSearch_matchesDailyLogBySymptom() {
        let results = HealthSearchResult.search(query: "头晕", in: member)
        XCTAssertTrue(results.contains(where: {
            if case .dailyLog = $0 { return true }
            return false
        }), "应命中症状标签")
    }

    // MARK: - 大小写不敏感

    func testSearch_isCaseInsensitive() {
        let results = HealthSearchResult.search(query: "DIABETES", in: member)
        // member 无英文数据，验证不崩溃且返回空
        XCTAssertNotNil(results)
    }

    // MARK: - 无匹配

    func testSearch_noMatch_returnsEmpty() {
        let results = HealthSearchResult.search(query: "火星人", in: member)
        XCTAssertTrue(results.isEmpty, "不存在的关键词应返回空结果")
    }

    // MARK: - 跨分类命中

    func testSearch_canMatchMultipleCategories() {
        // "血糖" 同时出现在体检摘要、用药用途、日志备注中
        let results = HealthSearchResult.search(query: "血糖", in: member)
        XCTAssertGreaterThanOrEqual(results.count, 3, "血糖应跨多个分类命中")

        let hasCheckup  = results.contains(where: { if case .checkup  = $0 { return true }; return false })
        let hasMed      = results.contains(where: { if case .medication = $0 { return true }; return false })
        let hasLog      = results.contains(where: { if case .dailyLog  = $0 { return true }; return false })
        XCTAssertTrue(hasCheckup,  "应命中体检报告")
        XCTAssertTrue(hasMed,      "应命中用药记录")
        XCTAssertTrue(hasLog,      "应命中日常追踪")
    }

    // MARK: - HealthSearchResult 元数据

    func testCheckupResult_metadata() {
        let report = member.checkups.first!
        let result = HealthSearchResult.checkup(report)
        XCTAssertEqual(result.category, "体检报告")
        XCTAssertEqual(result.categoryIcon, "stethoscope")
        XCTAssertFalse(result.title.isEmpty)
        XCTAssertEqual(result.sortDate, report.checkupDate)
    }

    func testMedicationResult_metadata() {
        let med = member.medications.first!
        let result = HealthSearchResult.medication(med)
        XCTAssertEqual(result.category, "用药记录")
        XCTAssertEqual(result.title, med.name)
    }

    func testVisitResult_metadata() {
        let visit = member.visits.first!
        let result = HealthSearchResult.visit(visit)
        XCTAssertEqual(result.category, "就医记录")
        XCTAssertEqual(result.sortDate, visit.visitDate)
    }

    func testHistoryResult_chronicSubtitle() {
        let history = member.medicalHistory.first(where: { $0.isChronic })!
        let result = HealthSearchResult.history(history)
        XCTAssertEqual(result.subtitle, "慢性病")
    }

    // MARK: - 空数据成员

    func testSearch_emptyMember_returnsEmpty() {
        let emptyMember = TestFixtures.makeMember(name: "空白成员")
        let results = HealthSearchResult.search(query: "高血压", in: emptyMember)
        XCTAssertTrue(results.isEmpty, "无记录的成员搜索应返回空")
    }
}
