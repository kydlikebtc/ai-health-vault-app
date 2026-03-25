import XCTest
import SwiftData
@testable import AIHealthVault

/// VisitPreparationViewModel 单元测试
/// 覆盖：就诊清单生成（MockAI）、空输入守卫、失败路径、
///       SwiftData CachedVisitPrep 写入、就诊后记录保存逻辑
@MainActor
final class VisitPreparationViewModelTests: SwiftDataTestCase {

    private var member: Member!

    override func setUpWithError() throws {
        try super.setUpWithError()
        member = TestFixtures.makeMember(name: "李明")
        member.chronicConditions = ["高血压", "糖尿病"]
        let med = TestFixtures.makeMedication(name: "二甲双胍")
        med.member = member
        modelContext.insert(member)
        modelContext.insert(med)
        try modelContext.save()
    }

    // MARK: - Helpers

    private func makeSUT(fail: Bool = false) -> (VisitPreparationViewModel, MockAIService) {
        let mock = MockAIService.visitPrepMock()
        mock.streamDelay = 0
        mock.shouldFail = fail
        let sut = VisitPreparationViewModel(member: member, aiService: mock)
        sut.setModelContext(modelContext)
        return (sut, mock)
    }

    // MARK: - generate() 成功路径

    func testGenerate_withMockAI_phaseIsDone() async throws {
        let (sut, _) = makeSUT()
        sut.visitPurpose = "头痛，血压偏高"

        await sut.generate()

        XCTAssertEqual(sut.phase, .done, "生成完成后 phase 应为 .done")
    }

    func testGenerate_withMockAI_resultIsNonEmpty() async throws {
        let (sut, _) = makeSUT()
        sut.visitPurpose = "复查血糖"

        await sut.generate()

        XCTAssertFalse(sut.result.isEmpty, "生成完成后 result 不应为空字符串")
    }

    func testGenerate_withMockAI_resultContainsVisitPrep() async throws {
        let (sut, _) = makeSUT()
        sut.visitPurpose = "例行体检"

        await sut.generate()

        XCTAssertTrue(sut.result.contains("就诊准备"),
                      "Mock 响应应包含「就诊准备」关键词")
    }

    func testGenerate_streamingTextClearedAfterDone() async throws {
        let (sut, _) = makeSUT()
        sut.visitPurpose = "测试流式清理"

        await sut.generate()

        XCTAssertTrue(sut.streamingText.isEmpty,
                      "generate 完成后 streamingText 应被清空")
    }

    func testGenerate_multipleTimes_resultUpdated() async throws {
        let (sut, mock) = makeSUT()
        sut.visitPurpose = "第一次就诊"
        await sut.generate()
        let firstResult = sut.result

        mock.mockResponse = "**第二次就诊准备** 内容已更新"
        sut.visitPurpose = "第二次就诊"
        await sut.generate()

        XCTAssertNotEqual(sut.result, firstResult, "再次调用 generate 应覆盖之前的 result")
    }

    // MARK: - generate() 空输入守卫

    func testGenerate_emptyPurpose_phaseRemainsIdle() async throws {
        let (sut, _) = makeSUT()
        sut.visitPurpose = ""

        await sut.generate()

        XCTAssertEqual(sut.phase, .idle, "空 visitPurpose 不应触发生成，phase 保持 .idle")
    }

    func testGenerate_emptyPurpose_resultRemainsEmpty() async throws {
        let (sut, _) = makeSUT()
        sut.visitPurpose = ""

        await sut.generate()

        XCTAssertTrue(sut.result.isEmpty, "空 visitPurpose 时 result 应保持为空")
    }

    func testGenerate_whitespaceOnlyPurpose_phaseRemainsIdle() async throws {
        let (sut, _) = makeSUT()
        sut.visitPurpose = "   \n\t  "

        await sut.generate()

        XCTAssertEqual(sut.phase, .idle, "纯空白字符串 trim 后为空，不应触发生成")
    }

    // MARK: - generate() 失败路径

    func testGenerate_withFailingAI_phaseIsFailed() async throws {
        let (sut, _) = makeSUT(fail: true)
        sut.visitPurpose = "测试失败场景"

        await sut.generate()

        if case .failed(let msg) = sut.phase {
            XCTAssertFalse(msg.isEmpty, "失败时 phase.failed 应携带非空错误信息")
        } else {
            XCTFail("AI 失败时 phase 应为 .failed，实际：\(sut.phase)")
        }
    }

    func testGenerate_withFailingAI_resultRemainsEmpty() async throws {
        let (sut, _) = makeSUT(fail: true)
        sut.visitPurpose = "失败时不应有结果"

        await sut.generate()

        XCTAssertTrue(sut.result.isEmpty, "AI 失败时 result 应保持为空")
    }

    // MARK: - SwiftData CachedVisitPrep 写入

    func testGenerate_success_writesCachedVisitPrep() async throws {
        let (sut, _) = makeSUT()
        sut.visitPurpose = "高血压复查"

        await sut.generate()

        let cached = try fetchAll(CachedVisitPrep.self)
        XCTAssertFalse(cached.isEmpty, "生成完成后应有 CachedVisitPrep 写入 SwiftData")
    }

    func testGenerate_success_cachedMemberNameIsCorrect() async throws {
        let (sut, _) = makeSUT()
        sut.visitPurpose = "检查"

        await sut.generate()

        let cached = try fetchAll(CachedVisitPrep.self)
        XCTAssertEqual(cached.first?.memberName, "李明",
                       "缓存记录的 memberName 应与成员姓名一致")
    }

    func testGenerate_success_cachedPurposeMatchesInput() async throws {
        let (sut, _) = makeSUT()
        sut.visitPurpose = "血脂偏高，需要咨询"

        await sut.generate()

        let cached = try fetchAll(CachedVisitPrep.self)
        XCTAssertEqual(cached.first?.purpose, "血脂偏高，需要咨询",
                       "缓存记录的 purpose 应与 visitPurpose 一致")
    }

    func testGenerate_success_cachedResultMatchesViewModelResult() async throws {
        let (sut, _) = makeSUT()
        sut.visitPurpose = "验证缓存一致性"

        await sut.generate()

        let cached = try fetchAll(CachedVisitPrep.self)
        XCTAssertEqual(cached.first?.result, sut.result,
                       "SwiftData 缓存的 result 应与 ViewModel.result 完全一致")
    }

    func testGenerate_fail_doesNotWriteCache() async throws {
        let (sut, _) = makeSUT(fail: true)
        sut.visitPurpose = "失败不应写缓存"

        await sut.generate()

        let cached = try fetchAll(CachedVisitPrep.self)
        XCTAssertTrue(cached.isEmpty, "AI 失败时不应向 SwiftData 写入 CachedVisitPrep")
    }

    // MARK: - savePostVisitRecord()

    func testSavePostVisitRecord_withDiagnosis_createsVisitRecord() async throws {
        let (sut, _) = makeSUT()
        sut.visitPurpose = "头痛就诊"
        sut.postDiagnosis = "紧张性头痛"
        sut.postPrescription = "布洛芬 400mg"
        sut.postScheduleNotification = false

        await sut.savePostVisitRecord()

        let visits = try fetchAll(VisitRecord.self)
        XCTAssertFalse(visits.isEmpty, "提供诊断后保存应创建 VisitRecord")
        XCTAssertEqual(visits.first?.diagnosis, "紧张性头痛", "诊断结果应与输入一致")
    }

    func testSavePostVisitRecord_emptyDiagnosis_doesNotSave() async throws {
        let (sut, _) = makeSUT()
        sut.visitPurpose = "测试空诊断"
        sut.postDiagnosis = ""
        sut.postScheduleNotification = false

        await sut.savePostVisitRecord()

        let visits = try fetchAll(VisitRecord.self)
        XCTAssertTrue(visits.isEmpty, "空诊断结果不应创建 VisitRecord")
    }

    func testSavePostVisitRecord_whitespaceOnlyDiagnosis_doesNotSave() async throws {
        let (sut, _) = makeSUT()
        sut.visitPurpose = "测试"
        sut.postDiagnosis = "   "
        sut.postScheduleNotification = false

        await sut.savePostVisitRecord()

        let visits = try fetchAll(VisitRecord.self)
        XCTAssertTrue(visits.isEmpty, "纯空白诊断 trim 后为空，不应创建 VisitRecord")
    }

    func testSavePostVisitRecord_chiefComplaintMatchesVisitPurpose() async throws {
        let (sut, _) = makeSUT()
        sut.visitPurpose = "反复头晕伴耳鸣"
        sut.postDiagnosis = "高血压"
        sut.postScheduleNotification = false

        await sut.savePostVisitRecord()

        let visits = try fetchAll(VisitRecord.self)
        XCTAssertEqual(visits.first?.chiefComplaint, "反复头晕伴耳鸣",
                       "就诊记录的主诉应来自 visitPurpose")
    }

    func testSavePostVisitRecord_prescriptionSaved() async throws {
        let (sut, _) = makeSUT()
        sut.visitPurpose = "测试"
        sut.postDiagnosis = "感冒"
        sut.postPrescription = "布洛芬 400mg，每日 3 次"
        sut.postScheduleNotification = false

        await sut.savePostVisitRecord()

        let visits = try fetchAll(VisitRecord.self)
        XCTAssertEqual(visits.first?.prescription, "布洛芬 400mg，每日 3 次",
                       "处方内容应写入 VisitRecord")
    }
}
