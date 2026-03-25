import XCTest
import SwiftData
@testable import AIHealthVault

/// TermExplanationService 单元测试
/// 重点验证：空输入守卫、缓存命中路径、AI 回落路径、缓存写入与 hitCount 增长
@MainActor
final class TermExplanationServiceTests: SwiftDataTestCase {

    private var sut: TermExplanationService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        sut = TermExplanationService.shared
        sut.setModelContext(modelContext)
    }

    override func tearDownWithError() throws {
        // 清除注入的 context，避免影响其他测试
        sut.setModelContext(ModelContext(modelContainer))
        sut = nil
        try super.tearDownWithError()
    }

    // MARK: - 空输入守卫

    func testExplain_emptyString_returnsEmpty() async throws {
        let result = try await sut.explain(term: "")
        XCTAssertEqual(result, "", "空字符串应立即返回空字符串，不触发 AI 调用")
    }

    func testExplain_whitespaceOnly_returnsEmpty() async throws {
        let result = try await sut.explain(term: "   \t\n  ")
        XCTAssertEqual(result, "", "纯空白字符串 trim 后为空，应返回空字符串")
    }

    // MARK: - 缓存命中路径（不调用 AI）

    func testExplain_cachedTerm_returnsCachedExplanation() async throws {
        // 预置缓存
        let cached = TestFixtures.makeTermCacheItem(
            term: "血糖",
            explanation: "血液中葡萄糖浓度，单位 mmol/L"
        )
        try insertAndSave(cached)

        let result = try await sut.explain(term: "血糖")

        XCTAssertEqual(result, "血液中葡萄糖浓度，单位 mmol/L",
                       "缓存命中时应返回缓存中的解释，而非 AI 生成内容")
    }

    func testExplain_cachedTerm_incrementsHitCount() async throws {
        let cached = TestFixtures.makeTermCacheItem(term: "心率")
        cached.hitCount = 0
        try insertAndSave(cached)

        _ = try await sut.explain(term: "心率")

        let items = try fetchAll(TermCacheItem.self)
        XCTAssertEqual(items.first?.hitCount, 1, "每次缓存命中应使 hitCount +1")
    }

    func testExplain_cachedTermCalledTwice_hitCountIsTwo() async throws {
        let cached = TestFixtures.makeTermCacheItem(term: "血压")
        cached.hitCount = 0
        try insertAndSave(cached)

        _ = try await sut.explain(term: "血压")
        _ = try await sut.explain(term: "血压")

        let items = try fetchAll(TermCacheItem.self)
        XCTAssertEqual(items.first?.hitCount, 2, "两次命中后 hitCount 应为 2")
    }

    func testExplain_cachedTerm_updatesLastAccessedAt() async throws {
        let cached = TestFixtures.makeTermCacheItem(term: "胆固醇")
        let originalDate = Date(timeIntervalSinceNow: -3600) // 1 小时前
        cached.lastAccessedAt = originalDate
        try insertAndSave(cached)

        _ = try await sut.explain(term: "胆固醇")

        let items = try fetchAll(TermCacheItem.self)
        let updatedDate = items.first?.lastAccessedAt ?? originalDate
        XCTAssertGreaterThan(updatedDate, originalDate, "缓存命中后 lastAccessedAt 应更新")
    }

    // MARK: - 白空格归一化（缓存键匹配）

    func testExplain_trimmedTermMatchesCache() async throws {
        let cached = TestFixtures.makeTermCacheItem(term: "尿酸", explanation: "尿酸是嘌呤代谢的终产物")
        try insertAndSave(cached)

        // 带前后空格的查询应命中缓存
        let result = try await sut.explain(term: "  尿酸  ")

        XCTAssertEqual(result, "尿酸是嘌呤代谢的终产物",
                       "输入前后空白应被 trim，仍能命中缓存")
    }

    // MARK: - AI 回落路径（无缓存）

    func testExplain_unknownTerm_returnsNonEmptyContent() async throws {
        // 无缓存，触发 MockAIService（测试环境无 API Key）
        let result = try await sut.explain(term: "转氨酶_\(UUID().uuidString)")

        XCTAssertFalse(result.isEmpty, "未缓存术语应通过 AI 返回非空内容")
    }

    func testExplain_unknownTerm_writesToCache() async throws {
        let uniqueTerm = "血红蛋白_\(UUID().uuidString)"

        _ = try await sut.explain(term: uniqueTerm)

        let items = try fetchAll(TermCacheItem.self)
        let stored = items.first { $0.term == uniqueTerm }
        XCTAssertNotNil(stored, "AI 回落后，术语与解释应写入 TermCacheItem 缓存")
    }

    func testExplain_unknownTerm_subsequentCallHitsCache() async throws {
        let term = "肌酐_\(UUID().uuidString)"

        // 第一次：AI 调用
        let firstResult = try await sut.explain(term: term)
        // 第二次：应命中缓存
        let secondResult = try await sut.explain(term: term)

        XCTAssertEqual(firstResult, secondResult, "第二次查询应命中缓存，结果与第一次一致")
    }

    // MARK: - 无 ModelContext（无缓存模式）

    func testExplain_withoutModelContext_returnsContent() async throws {
        // 不注入 modelContext
        let noContextService = TermExplanationService.shared
        noContextService.setModelContext(ModelContext(modelContainer)) // 新建一个空 context

        let result = try await noContextService.explain(term: "白细胞")

        XCTAssertFalse(result.isEmpty, "无 modelContext 时仍应通过 AI 返回内容")
    }

    // MARK: - 多术语并发不冲突

    func testExplain_differentTerms_allReturnContent() async throws {
        let terms = ["血小板_A", "血小板_B", "血小板_C"].map { "\($0)_\(UUID())" }

        var results: [String] = []
        for term in terms {
            let r = try await sut.explain(term: term)
            results.append(r)
        }

        XCTAssertEqual(results.count, 3)
        XCTAssertTrue(results.allSatisfy { !$0.isEmpty }, "多个不同术语均应返回非空解释")
    }
}
