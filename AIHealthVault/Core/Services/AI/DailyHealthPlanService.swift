import Foundation
import SwiftData

/// 每日健康计划生成服务
/// 汇聚 HealthKit、DailyLog、用药、体检数据，调用 AI 生成个性化建议
actor DailyHealthPlanService {

    static let shared = DailyHealthPlanService()

    // MARK: - 生成计划

    /// 为指定成员生成今日健康计划
    /// - Parameters:
    ///   - member: 目标成员
    ///   - healthKitSummary: 今日 HealthKit 数据（可为 nil，如权限未授权）
    ///   - aiService: AI 服务实例
    /// - Returns: 生成的计划内容（Markdown 格式）
    func generatePlan(
        for member: Member,
        healthKitSummary: HealthKitTodaySummary?,
        aiService: any AIService
    ) async throws -> String {
        let context = buildContext(member: member, healthKitSummary: healthKitSummary)
        let template = PromptLibrary.DailyHealthPlan()
        let userMessage = template.buildUserMessage(context: context)

        let (content, _) = try await aiService.sendMessage(
            [AIMessage(role: .user, content: userMessage)],
            systemPrompt: template.systemPrompt
        )
        return content
    }

    // MARK: - 构建提示词上下文

    private func buildContext(member: Member,
                              healthKitSummary: HealthKitTodaySummary?) -> PromptContext {
        // 当前活跃用药
        let medications = member.medications
            .filter { $0.isActive }
            .map { med -> String in
                var desc = med.name
                if !med.dosage.isEmpty { desc += "（\(med.dosage)）" }
                desc += "，\(med.frequency.displayName)"
                return desc
            }

        // 慢性病 + 过敏史 → 医疗背景
        var medicalHistory = member.chronicConditions
        if !member.allergies.isEmpty {
            medicalHistory.append("过敏：\(member.allergies.joined(separator: "、"))")
        }
        if !member.currentHealthNotes.isEmpty {
            medicalHistory.append(member.currentHealthNotes)
        }

        // 最近体检异常指标
        let recentAbnormal = member.checkups
            .filter { !$0.abnormalItems.isEmpty }
            .sorted { $0.checkupDate > $1.checkupDate }
            .prefix(1)
            .flatMap { $0.abnormalItems }
            .prefix(5)
            .joined(separator: "、")

        // 今日 DailyLog
        let todayLog = member.dailyTracking.first {
            Calendar.current.isDateInToday($0.date)
        }

        // 组装今日数据描述作为 userQuery
        var queryParts: [String] = []
        if let summary = healthKitSummary, !summary.isEmpty {
            var hkParts: [String] = []
            if let steps = summary.steps {
                hkParts.append("步数 \(steps) 步")
            }
            if let hr = summary.heartRate {
                hkParts.append("心率 \(Int(hr)) bpm")
            }
            if let sleep = summary.sleepHours {
                hkParts.append("睡眠 \(String(format: "%.1f", sleep)) 小时")
            }
            if !hkParts.isEmpty {
                queryParts.append("HealthKit 数据：\(hkParts.joined(separator: "，"))")
            }
        }

        if let log = todayLog {
            queryParts.append("今日情绪：\(log.mood.displayName)（\(log.mood.emoji)），精力：\(log.energyLevel)/5")
            if !log.symptoms.isEmpty {
                queryParts.append("今日症状：\(log.symptoms.joined(separator: "、"))")
            }
            if log.exerciseMinutes > 0 {
                queryParts.append("已运动 \(log.exerciseMinutes) 分钟")
            }
            if log.waterIntakeMl > 0 {
                queryParts.append("已饮水 \(log.waterIntakeMl) ml")
            }
        }

        if !recentAbnormal.isEmpty {
            queryParts.append("近期体检异常：\(recentAbnormal)")
        }

        if queryParts.isEmpty {
            queryParts.append("请根据我的健康状况制定今日计划")
        }

        return PromptContext(
            memberName: member.name,
            memberAge: member.age,
            medicalHistory: medicalHistory,
            currentMedications: medications,
            recentCheckupSummary: recentAbnormal.isEmpty ? nil : recentAbnormal,
            userQuery: queryParts.joined(separator: "\n"),
            additionalData: [:]
        )
    }
}
