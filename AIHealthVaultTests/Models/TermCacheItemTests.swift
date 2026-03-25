import XCTest
import SwiftData
@testable import AIHealthVault

/// TermCacheItem 模型单元测试
/// 覆盖：CRUD、默认值、hitCount 缓存统计、语言字段
@MainActor
final class TermCacheItemTests: SwiftDataTestCase {

    // MARK: - CRUD

    func testCreate_termCacheItem_savesSuccessfully() throws {
        let item = TestFixtures.makeTermCacheItem(term: "肌酐")
        try insertAndSave(item)

        let fetched = try fetchAll(TermCacheItem.self)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.term, "肌酐")
    }

    func testCreate_storesExplanation() throws {
        let explanation = "肌酐是肌肉代谢的产物，反映肾功能"
        let item = TestFixtures.makeTermCacheItem(term: "肌酐", explanation: explanation)
        try insertAndSave(item)

        XCTAssertEqual(try fetchAll(TermCacheItem.self).first?.explanation, explanation)
    }

    func testUpdate_explanation_persists() throws {
        let item = TestFixtures.makeTermCacheItem(term: "血糖")
        try insertAndSave(item)

        item.explanation = "更新后的解释内容"
        try modelContext.save()

        XCTAssertEqual(try fetchAll(TermCacheItem.self).first?.explanation, "更新后的解释内容")
    }

    func testDelete_termCacheItem_removesFromDatabase() throws {
        let item = TestFixtures.makeTermCacheItem()
        try insertAndSave(item)

        modelContext.delete(item)
        try modelContext.save()

        XCTAssertTrue(try fetchAll(TermCacheItem.self).isEmpty)
    }

    func testCreate_multipleItems_allPersist() throws {
        let terms = ["血糖", "血压", "体重指数"]
        for term in terms {
            modelContext.insert(TestFixtures.makeTermCacheItem(term: term))
        }
        try modelContext.save()

        XCTAssertEqual(try fetchAll(TermCacheItem.self).count, 3)
    }

    // MARK: - 默认值

    func testInit_hitCount_defaultsToOne() {
        let item = TermCacheItem(term: "血糖", explanation: "解释")
        XCTAssertEqual(item.hitCount, 1, "新建缓存条目的 hitCount 应默认为 1（首次写入即为一次命中）")
    }

    func testInit_language_defaultsToZh() {
        let item = TermCacheItem(term: "血糖", explanation: "解释")
        XCTAssertEqual(item.language, "zh", "默认语言应为中文")
    }

    func testInit_language_canBeSetToEnglish() {
        let item = TermCacheItem(term: "Creatinine", explanation: "...", language: "en")
        XCTAssertEqual(item.language, "en")
    }

    func testInit_createdAt_isRecentTimestamp() {
        let before = Date()
        let item = TermCacheItem(term: "血糖", explanation: "解释")
        let after = Date()
        XCTAssertGreaterThanOrEqual(item.createdAt, before)
        XCTAssertLessThanOrEqual(item.createdAt, after)
    }

    func testInit_lastAccessedAt_isRecentTimestamp() {
        let before = Date()
        let item = TermCacheItem(term: "血糖", explanation: "解释")
        let after = Date()
        XCTAssertGreaterThanOrEqual(item.lastAccessedAt, before)
        XCTAssertLessThanOrEqual(item.lastAccessedAt, after)
    }

    func testInit_term_isStoredCorrectly() {
        let item = TermCacheItem(term: "高血压", explanation: "解释")
        XCTAssertEqual(item.term, "高血压")
    }

    // MARK: - hitCount 缓存统计

    func testHitCount_increment_persists() throws {
        let item = TestFixtures.makeTermCacheItem(term: "血压")
        try insertAndSave(item)

        item.hitCount += 1
        item.hitCount += 1
        try modelContext.save()

        XCTAssertEqual(try fetchAll(TermCacheItem.self).first?.hitCount, 3,
                       "初始 hitCount=1，两次自增后应为 3")
    }

    func testLastAccessedAt_update_persists() throws {
        let item = TestFixtures.makeTermCacheItem()
        try insertAndSave(item)

        let newAccessDate = Calendar.current.date(byAdding: .hour, value: 1, to: Date())!
        item.lastAccessedAt = newAccessDate
        try modelContext.save()

        let fetched = try fetchAll(TermCacheItem.self).first
        XCTAssertEqual(fetched?.lastAccessedAt.timeIntervalSince1970,
                       newAccessDate.timeIntervalSince1970,
                       accuracy: 1.0)
    }

    // MARK: - 不同语言条目共存

    func testMultipleLanguages_canCoexist() throws {
        let zhItem = TermCacheItem(term: "血糖", explanation: "中文解释", language: "zh")
        let enItem = TermCacheItem(term: "Glucose", explanation: "English explanation", language: "en")
        modelContext.insert(zhItem)
        modelContext.insert(enItem)
        try modelContext.save()

        let all = try fetchAll(TermCacheItem.self)
        XCTAssertEqual(all.count, 2)
        XCTAssertTrue(all.contains { $0.language == "zh" })
        XCTAssertTrue(all.contains { $0.language == "en" })
    }

    // MARK: - 字段完整性

    func testAllFields_areAccessibleAfterSave() throws {
        let item = TermCacheItem(term: "尿酸", explanation: "嘌呤代谢的最终产物", language: "zh")
        try insertAndSave(item)

        let fetched = try fetchAll(TermCacheItem.self).first!
        XCTAssertEqual(fetched.term, "尿酸")
        XCTAssertEqual(fetched.explanation, "嘌呤代谢的最终产物")
        XCTAssertEqual(fetched.language, "zh")
        XCTAssertEqual(fetched.hitCount, 1)
        XCTAssertNotNil(fetched.createdAt)
        XCTAssertNotNil(fetched.lastAccessedAt)
    }
}
