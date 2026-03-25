import SwiftData
import Foundation

/// 医学术语通俗解读服务 — 带本地 SwiftData 缓存，减少重复 API 调用
@MainActor
final class TermExplanationService {

    static let shared = TermExplanationService()

    private var modelContext: ModelContext?
    private let aiService: any AIService

    private init() {
        if AISettingsManager.shared.isAPIKeyConfigured && AISettingsManager.shared.isAIEnabled {
            self.aiService = ClaudeService()
        } else {
            self.aiService = MockAIService.termExplanationMock()
        }
    }

    func setModelContext(_ ctx: ModelContext) {
        modelContext = ctx
    }

    // MARK: - 查询术语

    /// 返回术语的通俗解释，优先命中本地缓存。
    func explain(term: String) async throws -> String {
        let normalized = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "" }

        // 1. 查询缓存
        if let cached = try? cachedExplanation(for: normalized) {
            return cached
        }

        // 2. 调用 AI
        let template = PromptLibrary.TermExplanation()
        let context = PromptContext(userQuery: normalized)
        let message = AIMessage(role: .user, content: template.buildUserMessage(context: context))
        let (explanation, usage) = try await aiService.sendMessage([message], systemPrompt: template.systemPrompt)

        AISettingsManager.shared.recordUsage(usage)

        // 3. 写入缓存
        if let ctx = modelContext {
            let item = TermCacheItem(term: normalized, explanation: explanation)
            ctx.insert(item)
        }

        return explanation
    }

    // MARK: - 私有：缓存查询

    private func cachedExplanation(for term: String) throws -> String? {
        guard let ctx = modelContext else { return nil }
        let descriptor = FetchDescriptor<TermCacheItem>(
            predicate: #Predicate { $0.term == term }
        )
        guard let item = try ctx.fetch(descriptor).first else { return nil }

        // 更新访问统计
        item.hitCount += 1
        item.lastAccessedAt = Date()

        return item.explanation
    }
}
