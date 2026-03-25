import SwiftData
import Foundation

/// 医学术语本地缓存条目 — 避免重复调用 AI 接口解释相同术语
@Model
final class TermCacheItem {
    @Attribute(.unique) var term: String   // 术语（查询键，唯一）
    var explanation: String                // AI 生成的通俗解释
    var language: String                   // 识别语言（"zh" / "en"）
    var hitCount: Int                      // 被查询次数，用于 LRU 淘汰
    var createdAt: Date
    var lastAccessedAt: Date

    init(term: String, explanation: String, language: String = "zh") {
        self.term = term
        self.explanation = explanation
        self.language = language
        self.hitCount = 1
        self.createdAt = Date()
        self.lastAccessedAt = Date()
    }
}
