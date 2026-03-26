import Foundation

// MARK: - PromptTemplate Protocol

/// 提示词模板协议 — 所有医疗场景提示词必须遵循
protocol PromptTemplate {
    /// 系统提示词（设定 AI 角色和规则）
    var systemPrompt: String { get }
    /// 根据上下文构建用户消息
    func buildUserMessage(context: PromptContext) -> String
}

// MARK: - Prompt Context

/// 构建提示词所需的上下文数据
struct PromptContext: Sendable {
    var memberName: String?
    var memberAge: Int?
    var medicalHistory: [String]
    var currentMedications: [String]
    var recentCheckupSummary: String?
    var userQuery: String
    var additionalData: [String: String]

    init(
        memberName: String? = nil,
        memberAge: Int? = nil,
        medicalHistory: [String] = [],
        currentMedications: [String] = [],
        recentCheckupSummary: String? = nil,
        userQuery: String,
        additionalData: [String: String] = [:]
    ) {
        self.memberName = memberName
        self.memberAge = memberAge
        self.medicalHistory = medicalHistory
        self.currentMedications = currentMedications
        self.recentCheckupSummary = recentCheckupSummary
        self.userQuery = userQuery
        self.additionalData = additionalData
    }
}

// MARK: - Prompt Library

/// 所有医疗场景提示词的集中管理
enum PromptLibrary {

    // MARK: - 体检报告解读

    struct ReportAnalysis: PromptTemplate {
        let systemPrompt = """
        你是一位专业的健康顾问助手，具备丰富的医学知识。你的任务是帮助用户理解体检报告中的各项指标。

        工作原则：
        1. 使用通俗易懂的中文解释医学术语，避免过度专业化
        2. 客观分析数据，不夸大风险也不掩盖问题
        3. 对于异常指标，给出实际可行的生活建议
        4. 始终提醒用户：AI 分析仅供参考，具体诊断请咨询医生
        5. 保护用户隐私，不存储或传播任何健康数据
        6. 如遇紧急情况指标（如严重心脏问题），明确建议立即就医

        回复格式：使用 Markdown，分「正常指标」「需关注指标」「建议」三部分。
        """

        func buildUserMessage(context: PromptContext) -> String {
            var parts: [String] = []

            if let name = context.memberName {
                parts.append("患者：\(name)\(context.memberAge.map { "，\($0)岁" } ?? "")")
            }

            if !context.medicalHistory.isEmpty {
                parts.append("既往病史：\(context.medicalHistory.joined(separator: "、"))")
            }

            if !context.currentMedications.isEmpty {
                parts.append("当前用药：\(context.currentMedications.joined(separator: "、"))")
            }

            if let checkup = context.recentCheckupSummary {
                parts.append("体检数据：\n\(checkup)")
            }

            parts.append("请帮我解读以上体检报告，重点说明各指标含义和健康建议。")

            return parts.joined(separator: "\n")
        }
    }

    // MARK: - 就诊准备助手

    struct VisitPreparation: PromptTemplate {
        let systemPrompt = """
        你是一位贴心的就诊准备助手，帮助患者做好看医生的准备工作。

        工作原则：
        1. 根据患者的健康档案和本次就诊原因，生成个性化准备清单
        2. 列出需要携带的材料和需要告知医生的信息
        3. 提供有针对性的问题建议，帮助患者充分利用就诊时间
        4. 语气温和友好，减轻患者焦虑
        5. 如症状描述提示紧急情况，优先建议急诊

        回复格式：使用 Markdown，分「携带材料」「需告知医生」「建议提问」三部分。
        """

        func buildUserMessage(context: PromptContext) -> String {
            var parts: [String] = []

            if let name = context.memberName {
                parts.append("患者：\(name)\(context.memberAge.map { "，\($0)岁" } ?? "")")
            }

            if !context.medicalHistory.isEmpty {
                parts.append("既往病史：\(context.medicalHistory.joined(separator: "、"))")
            }

            if !context.currentMedications.isEmpty {
                parts.append("当前用药：\(context.currentMedications.joined(separator: "、"))")
            }

            if let checkup = context.recentCheckupSummary {
                parts.append("近期体检摘要：\(checkup)")
            }

            parts.append("本次就诊原因：\(context.userQuery)")
            parts.append("请帮我制定就诊准备清单。")

            return parts.joined(separator: "\n")
        }
    }

    // MARK: - 医学术语通俗解读

    struct TermExplanation: PromptTemplate {
        let systemPrompt = """
        你是一位医学科普专家，擅长将复杂的医学术语转化为普通人能理解的语言。

        工作原则：
        1. 用简单的比喻和日常语言解释医学术语
        2. 说明该指标的正常范围和临床意义
        3. 如果指标异常，说明可能的原因和影响
        4. 给出实用的日常调整建议
        5. 保持简洁，每个术语解释控制在 200 字以内

        回复格式：直接解释，无需使用标题分隔。
        """

        func buildUserMessage(context: PromptContext) -> String {
            return "请用通俗语言解释医学术语：「\(context.userQuery)」\n如有数值，请说明是否正常以及含义。"
        }
    }

    // MARK: - 健康趋势分析

    struct TrendAnalysis: PromptTemplate {
        let systemPrompt = """
        你是一位数据驱动的健康分析师，专注于分析健康指标的长期变化趋势。

        工作原则：
        1. 识别指标的上升、下降或稳定趋势
        2. 结合时间维度分析变化速度是否令人担忧
        3. 关联多项指标，发现潜在的健康模式
        4. 提供基于趋势的预防建议
        5. 用数据说话，避免主观臆断

        回复格式：使用 Markdown，包含「趋势摘要」「风险提示」「改善建议」。
        """

        func buildUserMessage(context: PromptContext) -> String {
            var parts = ["以下是健康指标历史数据："]
            if let data = context.recentCheckupSummary {
                parts.append(data)
            }
            for (key, value) in context.additionalData {
                parts.append("\(key)：\(value)")
            }
            parts.append(context.userQuery)
            return parts.joined(separator: "\n")
        }
    }

    // MARK: - 药物识别与相互作用查询

    struct MedicineInfo: PromptTemplate {
        let systemPrompt = """
        你是一位专业的临床药学顾问，帮助用户了解药物信息和识别潜在的药物相互作用。

        工作原则：
        1. 提供药物的基本信息：适应症、常见剂量、服用时间和注意事项
        2. 重点分析药物与当前用药的潜在相互作用，按严重程度（严重/中度/轻微）分级提示
        3. 列出常见副作用和需要立即就医的警示症状
        4. 给出服药时间建议（饭前/饭后/特定时间）和储存注意事项
        5. 对于严重相互作用，明确建议在调整用药前咨询医生或药剂师
        6. 不建议患者自行停药或调整剂量，所有用药变更需经医生批准

        重要免责声明：AI 提供的药物信息仅供参考，不能替代专业药剂师和医生的建议。
        回复格式：使用 Markdown，分「药物概述」「相互作用」「服用建议」「注意事项」四部分。
        """

        func buildUserMessage(context: PromptContext) -> String {
            var parts: [String] = []

            if let name = context.memberName {
                parts.append("患者：\(name)\(context.memberAge.map { "，\($0)岁" } ?? "")")
            }

            if !context.currentMedications.isEmpty {
                parts.append("当前用药：\(context.currentMedications.joined(separator: "、"))")
            }

            if !context.medicalHistory.isEmpty {
                parts.append("既往病史：\(context.medicalHistory.joined(separator: "、"))")
            }

            parts.append("药物查询：\(context.userQuery)")
            parts.append("请分析该药物信息并检查与当前用药的相互作用。")

            return parts.joined(separator: "\n")
        }
    }

    // MARK: - 每日健康计划

    struct DailyHealthPlan: PromptTemplate {
        let systemPrompt = """
        你是一位个性化健康计划师，根据用户的健康状况制定每日健康建议。

        工作原则：
        1. 综合考虑用户的年龄、病史、用药情况
        2. 提供具体可执行的建议，而非泛泛而谈
        3. 平衡饮食、运动、睡眠、压力管理四个维度
        4. 考虑用药禁忌（如服用某些药物时的运动限制）
        5. 目标是让用户今天就能开始行动

        回复格式：使用 Markdown，分「今日饮食」「运动建议」「注意事项」三部分，简洁实用。
        """

        func buildUserMessage(context: PromptContext) -> String {
            var parts: [String] = []

            if let name = context.memberName {
                parts.append("用户：\(name)\(context.memberAge.map { "，\($0)岁" } ?? "")")
            }

            if !context.medicalHistory.isEmpty {
                parts.append("健康状况：\(context.medicalHistory.joined(separator: "、"))")
            }

            if !context.currentMedications.isEmpty {
                parts.append("当前用药：\(context.currentMedications.joined(separator: "、"))")
            }

            parts.append("今天的具体需求：\(context.userQuery)")
            parts.append("请为我制定今日健康计划。")

            return parts.joined(separator: "\n")
        }
    }
}
