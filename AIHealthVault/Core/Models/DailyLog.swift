import SwiftData
import Foundation

/// 情绪状态
enum MoodLevel: Int, Codable, CaseIterable {
    case veryBad = 1
    case bad = 2
    case neutral = 3
    case good = 4
    case veryGood = 5

    var displayName: String {
        switch self {
        case .veryBad: return "很差"
        case .bad: return "较差"
        case .neutral: return "一般"
        case .good: return "良好"
        case .veryGood: return "很好"
        }
    }

    var emoji: String {
        switch self {
        case .veryBad: return "😢"
        case .bad: return "😕"
        case .neutral: return "😐"
        case .good: return "😊"
        case .veryGood: return "😄"
        }
    }
}

/// 日常健康追踪日志
@Model
final class DailyLog {
    @Attribute(.unique) var id: UUID
    var date: Date              // 日期
    var moodLevel: Int          // 情绪（1-5，使用 MoodLevel rawValue）
    var energyLevel: Int        // 精力水平（1-5）
    var waterIntakeMl: Int      // 饮水量（毫升）
    var exerciseMinutes: Int    // 运动时长（分钟）
    var sleepHours: Double      // 睡眠时长（小时）
    var symptoms: [String]      // 当天症状列表
    var notes: String           // 自由文本备注
    var createdAt: Date

    var member: Member?

    init(date: Date = Date()) {
        self.id = UUID()
        self.date = Calendar.current.startOfDay(for: date)
        self.moodLevel = MoodLevel.neutral.rawValue
        self.energyLevel = 3
        self.waterIntakeMl = 0
        self.exerciseMinutes = 0
        self.sleepHours = 0
        self.symptoms = []
        self.notes = ""
        self.createdAt = Date()
    }

    var mood: MoodLevel {
        get { MoodLevel(rawValue: moodLevel) ?? .neutral }
        set { moodLevel = newValue.rawValue }
    }
}
