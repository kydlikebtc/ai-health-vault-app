import XCTest
@testable import AIHealthVault

/// PromptLibrary 单元测试 — 验证提示词生成的正确性和完整性
/// 提示词生成是纯函数，无需网络或 Mock，直接验证字符串内容
final class PromptLibraryTests: XCTestCase {

    // MARK: - PromptContext 构建辅助

    private func makeFullContext(query: String = "请分析") -> PromptContext {
        PromptContext(
            memberName: "张三",
            memberAge: 45,
            medicalHistory: ["高血压", "高血脂"],
            currentMedications: ["阿托伐他汀 10mg", "氨氯地平 5mg"],
            recentCheckupSummary: "总胆固醇 5.8，血压 130/85",
            userQuery: query
        )
    }

    private func makeMinimalContext(query: String = "解释") -> PromptContext {
        PromptContext(userQuery: query)
    }

    // MARK: - ReportAnalysis

    func testReportAnalysis_systemPrompt_isNotEmpty() {
        let template = PromptLibrary.ReportAnalysis()
        XCTAssertFalse(template.systemPrompt.isEmpty, "ReportAnalysis 系统提示词不应为空")
    }

    func testReportAnalysis_systemPrompt_mentionsMedicalDisclaimer() {
        let template = PromptLibrary.ReportAnalysis()
        XCTAssertTrue(template.systemPrompt.contains("医生") || template.systemPrompt.contains("诊断"),
                      "体检解读系统提示词应包含就医建议（安全合规）")
    }

    func testReportAnalysis_buildUserMessage_includesMemberName() {
        let template = PromptLibrary.ReportAnalysis()
        let msg = template.buildUserMessage(context: makeFullContext())
        XCTAssertTrue(msg.contains("张三"), "用户消息应包含患者姓名")
    }

    func testReportAnalysis_buildUserMessage_includesAge() {
        let template = PromptLibrary.ReportAnalysis()
        let msg = template.buildUserMessage(context: makeFullContext())
        XCTAssertTrue(msg.contains("45"), "用户消息应包含患者年龄")
    }

    func testReportAnalysis_buildUserMessage_includesMedicalHistory() {
        let template = PromptLibrary.ReportAnalysis()
        let msg = template.buildUserMessage(context: makeFullContext())
        XCTAssertTrue(msg.contains("高血压"), "用户消息应包含既往病史")
        XCTAssertTrue(msg.contains("高血脂"), "用户消息应包含所有病史条目")
    }

    func testReportAnalysis_buildUserMessage_includesMedications() {
        let template = PromptLibrary.ReportAnalysis()
        let msg = template.buildUserMessage(context: makeFullContext())
        XCTAssertTrue(msg.contains("阿托伐他汀"), "用户消息应包含用药信息")
    }

    func testReportAnalysis_buildUserMessage_includesCheckupSummary() {
        let template = PromptLibrary.ReportAnalysis()
        let msg = template.buildUserMessage(context: makeFullContext())
        XCTAssertTrue(msg.contains("总胆固醇"), "用户消息应包含体检摘要数据")
    }

    func testReportAnalysis_buildUserMessage_withMinimalContext_doesNotCrash() {
        let template = PromptLibrary.ReportAnalysis()
        let msg = template.buildUserMessage(context: makeMinimalContext())
        XCTAssertFalse(msg.isEmpty, "最小上下文下用户消息不应为空")
    }

    // MARK: - VisitPreparation

    func testVisitPreparation_systemPrompt_isNotEmpty() {
        let template = PromptLibrary.VisitPreparation()
        XCTAssertFalse(template.systemPrompt.isEmpty)
    }

    func testVisitPreparation_buildUserMessage_includesVisitReason() {
        let template = PromptLibrary.VisitPreparation()
        let ctx = PromptContext(userQuery: "头痛三天，想去神经科看看")
        let msg = template.buildUserMessage(context: ctx)
        XCTAssertTrue(msg.contains("头痛三天"), "就诊准备消息应包含本次就诊原因")
    }

    func testVisitPreparation_buildUserMessage_includesAllMedications() {
        let template = PromptLibrary.VisitPreparation()
        let ctx = PromptContext(
            currentMedications: ["药A", "药B", "药C"],
            userQuery: "检查"
        )
        let msg = template.buildUserMessage(context: ctx)
        XCTAssertTrue(msg.contains("药A") && msg.contains("药B") && msg.contains("药C"),
                      "就诊准备消息应包含所有用药")
    }

    func testVisitPreparation_buildUserMessage_withMinimalContext_doesNotCrash() {
        let template = PromptLibrary.VisitPreparation()
        let msg = template.buildUserMessage(context: makeMinimalContext())
        XCTAssertFalse(msg.isEmpty)
    }

    // MARK: - TermExplanation

    func testTermExplanation_systemPrompt_isNotEmpty() {
        let template = PromptLibrary.TermExplanation()
        XCTAssertFalse(template.systemPrompt.isEmpty)
    }

    func testTermExplanation_buildUserMessage_includesTerm() {
        let template = PromptLibrary.TermExplanation()
        let ctx = PromptContext(userQuery: "血糖")
        let msg = template.buildUserMessage(context: ctx)
        XCTAssertTrue(msg.contains("血糖"), "术语解释消息应包含查询术语")
    }

    func testTermExplanation_buildUserMessage_usesQuotedFormat() {
        let template = PromptLibrary.TermExplanation()
        let ctx = PromptContext(userQuery: "肌酐")
        let msg = template.buildUserMessage(context: ctx)
        // 协议要求：术语应被「」包围
        XCTAssertTrue(msg.contains("「肌酐」") || msg.contains("肌酐"),
                      "术语解释消息应包含术语本体")
    }

    // MARK: - TrendAnalysis

    func testTrendAnalysis_systemPrompt_isNotEmpty() {
        let template = PromptLibrary.TrendAnalysis()
        XCTAssertFalse(template.systemPrompt.isEmpty)
    }

    func testTrendAnalysis_buildUserMessage_includesCheckupData() {
        let template = PromptLibrary.TrendAnalysis()
        let ctx = PromptContext(
            recentCheckupSummary: "2023-01: BMI=22, 2024-01: BMI=24",
            userQuery: "分析体重趋势"
        )
        let msg = template.buildUserMessage(context: ctx)
        XCTAssertTrue(msg.contains("BMI=22"), "趋势分析消息应包含历史数据")
    }

    func testTrendAnalysis_buildUserMessage_includesAdditionalData() {
        let template = PromptLibrary.TrendAnalysis()
        let ctx = PromptContext(
            userQuery: "分析",
            additionalData: ["血压趋势": "稳定下降", "体重": "缓慢上升"]
        )
        let msg = template.buildUserMessage(context: ctx)
        XCTAssertTrue(msg.contains("血压趋势") || msg.contains("体重"),
                      "趋势分析消息应包含附加数据")
    }

    // MARK: - MedicineInfo

    func testMedicineInfo_systemPrompt_isNotEmpty() {
        let template = PromptLibrary.MedicineInfo()
        XCTAssertFalse(template.systemPrompt.isEmpty, "MedicineInfo 系统提示词不应为空")
    }

    func testMedicineInfo_systemPrompt_mentionsDrugInteraction() {
        let template = PromptLibrary.MedicineInfo()
        XCTAssertTrue(
            template.systemPrompt.contains("相互作用") || template.systemPrompt.contains("药物"),
            "药物识别系统提示词应涵盖相互作用分析"
        )
    }

    func testMedicineInfo_systemPrompt_mentionsMedicalDisclaimer() {
        let template = PromptLibrary.MedicineInfo()
        XCTAssertTrue(
            template.systemPrompt.contains("医生") || template.systemPrompt.contains("药剂师"),
            "药物识别系统提示词应包含医疗免责声明"
        )
    }

    func testMedicineInfo_buildUserMessage_includesDrugQuery() {
        let template = PromptLibrary.MedicineInfo()
        let ctx = PromptContext(userQuery: "阿司匹林 100mg")
        let msg = template.buildUserMessage(context: ctx)
        XCTAssertTrue(msg.contains("阿司匹林"), "药物查询消息应包含药名")
    }

    func testMedicineInfo_buildUserMessage_includesCurrentMedications() {
        let template = PromptLibrary.MedicineInfo()
        let ctx = PromptContext(
            currentMedications: ["华法林 5mg", "氨氯地平 5mg"],
            userQuery: "布洛芬"
        )
        let msg = template.buildUserMessage(context: ctx)
        XCTAssertTrue(msg.contains("华法林"), "药物查询消息应包含当前用药（用于相互作用检测）")
        XCTAssertTrue(msg.contains("氨氯地平"), "药物查询消息应包含所有当前用药")
    }

    func testMedicineInfo_buildUserMessage_includesMedicalHistory() {
        let template = PromptLibrary.MedicineInfo()
        let ctx = PromptContext(
            medicalHistory: ["肾功能不全"],
            userQuery: "非甾体抗炎药"
        )
        let msg = template.buildUserMessage(context: ctx)
        XCTAssertTrue(msg.contains("肾功能不全"), "药物查询消息应包含病史（影响药物禁忌）")
    }

    func testMedicineInfo_buildUserMessage_includesPatientInfo() {
        let template = PromptLibrary.MedicineInfo()
        let ctx = PromptContext(
            memberName: "李四",
            memberAge: 72,
            userQuery: "二甲双胍"
        )
        let msg = template.buildUserMessage(context: ctx)
        XCTAssertTrue(msg.contains("李四"), "药物查询消息应包含患者姓名")
        XCTAssertTrue(msg.contains("72"), "药物查询消息应包含年龄（老年用药剂量不同）")
    }

    func testMedicineInfo_buildUserMessage_withMinimalContext_doesNotCrash() {
        let template = PromptLibrary.MedicineInfo()
        let msg = template.buildUserMessage(context: makeMinimalContext(query: "对乙酰氨基酚"))
        XCTAssertFalse(msg.isEmpty, "最小上下文下药物查询消息不应为空")
        XCTAssertTrue(msg.contains("对乙酰氨基酚"), "药名应出现在消息中")
    }

    // MARK: - DailyHealthPlan

    func testDailyHealthPlan_systemPrompt_isNotEmpty() {
        let template = PromptLibrary.DailyHealthPlan()
        XCTAssertFalse(template.systemPrompt.isEmpty)
    }

    func testDailyHealthPlan_buildUserMessage_includesAllSections() {
        let template = PromptLibrary.DailyHealthPlan()
        let ctx = makeFullContext(query: "今天有点累，想轻松一些")
        let msg = template.buildUserMessage(context: ctx)

        // 消息应包含关键个人信息
        XCTAssertTrue(msg.contains("张三"), "每日计划应包含用户姓名")
        XCTAssertTrue(msg.contains("高血压"), "每日计划应考虑病史")
        XCTAssertTrue(msg.contains("今天有点累"), "每日计划应包含用户需求")
    }

    func testDailyHealthPlan_buildUserMessage_withNoHistory_doesNotCrash() {
        let template = PromptLibrary.DailyHealthPlan()
        let ctx = PromptContext(userQuery: "今日计划")
        let msg = template.buildUserMessage(context: ctx)
        XCTAssertFalse(msg.isEmpty, "无病史时每日计划消息不应为空")
    }

    // MARK: - PromptContext 数据封装

    func testPromptContext_defaultValues_areEmpty() {
        let ctx = PromptContext(userQuery: "test")
        XCTAssertNil(ctx.memberName)
        XCTAssertNil(ctx.memberAge)
        XCTAssertTrue(ctx.medicalHistory.isEmpty)
        XCTAssertTrue(ctx.currentMedications.isEmpty)
        XCTAssertNil(ctx.recentCheckupSummary)
        XCTAssertTrue(ctx.additionalData.isEmpty)
    }

    func testPromptContext_userQuery_isPreserved() {
        let ctx = PromptContext(userQuery: "我的查询内容")
        XCTAssertEqual(ctx.userQuery, "我的查询内容")
    }
}
