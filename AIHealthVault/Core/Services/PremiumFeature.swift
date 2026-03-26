import Foundation

/// Premium 功能枚举 — 定义所有需要 Paywall 检查的功能
///
/// 用法：
/// ```swift
/// if SubscriptionManager.shared.hasAccess(to: .aiAnalysis) {
///     // 显示 AI 功能
/// } else {
///     // 显示 Paywall
/// }
/// ```
enum PremiumFeature: String, CaseIterable {
    /// AI 体检报告解读
    case aiAnalysis = "ai_analysis"
    /// AI 就诊准备
    case visitPreparation = "visit_preparation"
    /// AI 每日健康计划
    case dailyPlan = "daily_plan"
    /// AI 趋势分析
    case trendAnalysis = "trend_analysis"
    /// PDF 健康报告导出
    case pdfExport = "pdf_export"
    /// 随访提醒（新建，已有的在 Free 层继续触发）
    case createFollowUpReminders = "create_follow_up_reminders"
    /// 家庭成员超过 2 人
    case extendedFamilyMembers = "extended_family_members"

    var localizedName: String {
        switch self {
        case .aiAnalysis:             return String(localized: "feature_ai_analysis")
        case .visitPreparation:       return String(localized: "feature_visit_preparation")
        case .dailyPlan:              return String(localized: "feature_daily_plan")
        case .trendAnalysis:          return String(localized: "feature_trend_analysis")
        case .pdfExport:              return String(localized: "feature_pdf_export")
        case .createFollowUpReminders: return String(localized: "feature_follow_up_reminders")
        case .extendedFamilyMembers:  return String(localized: "feature_extended_family")
        }
    }

    var systemImage: String {
        switch self {
        case .aiAnalysis:             return "brain.head.profile"
        case .visitPreparation:       return "stethoscope"
        case .dailyPlan:              return "calendar.badge.checkmark"
        case .trendAnalysis:          return "chart.xyaxis.line"
        case .pdfExport:              return "doc.richtext"
        case .createFollowUpReminders: return "bell.badge"
        case .extendedFamilyMembers:  return "person.3.fill"
        }
    }
}
