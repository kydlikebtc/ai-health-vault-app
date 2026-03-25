import XCTest
@testable import AIHealthVault

/// MockAIService 单元测试 — 验证 AIService 协议行为、Mock 状态控制
final class AIServiceTests: XCTestCase {

    private var mock: MockAIService!

    override func setUp() {
        super.setUp()
        mock = MockAIService()
    }

    override func tearDown() {
        mock = nil
        super.tearDown()
    }

    // MARK: - isConfigured

    func testIsConfigured_defaultIsTrue() {
        XCTAssertTrue(mock.isConfigured, "MockAIService 默认应已配置")
    }

    func testIsConfigured_canBeSetToFalse() {
        mock.isConfigured = false
        XCTAssertFalse(mock.isConfigured)
    }

    // MARK: - sendMessage 成功场景

    func testSendMessage_returnsDefaultMockResponse() async throws {
        let messages = [AIMessage(role: .user, content: "你好")]
        let (content, _) = try await mock.sendMessage(messages, systemPrompt: nil)
        XCTAssertFalse(content.isEmpty, "默认 mock 回复不应为空")
    }

    func testSendMessage_returnsConfiguredMockResponse() async throws {
        mock.mockResponse = "测试专用回复"
        let messages = [AIMessage(role: .user, content: "ping")]
        let (content, _) = try await mock.sendMessage(messages, systemPrompt: nil)
        XCTAssertEqual(content, "测试专用回复")
    }

    func testSendMessage_returnsConfiguredTokenUsage() async throws {
        mock.mockUsage = TokenUsage(inputTokens: 100, outputTokens: 50)
        let messages = [AIMessage(role: .user, content: "test")]
        let (_, usage) = try await mock.sendMessage(messages, systemPrompt: nil)
        XCTAssertEqual(usage.inputTokens, 100)
        XCTAssertEqual(usage.outputTokens, 50)
        XCTAssertEqual(usage.total, 150)
    }

    func testSendMessage_acceptsSystemPrompt() async throws {
        let messages = [AIMessage(role: .user, content: "test")]
        // 有系统提示词时不应抛出异常
        let (content, _) = try await mock.sendMessage(messages, systemPrompt: "你是一个医疗助手")
        XCTAssertFalse(content.isEmpty)
    }

    func testSendMessage_acceptsMultipleMessages() async throws {
        let messages = [
            AIMessage(role: .user, content: "问题1"),
            AIMessage(role: .assistant, content: "回答1"),
            AIMessage(role: .user, content: "追问"),
        ]
        let (content, _) = try await mock.sendMessage(messages, systemPrompt: nil)
        XCTAssertFalse(content.isEmpty)
    }

    // MARK: - sendMessage 失败场景

    func testSendMessage_throwsWhenShouldFail() async {
        mock.shouldFail = true
        mock.errorToThrow = .notConfigured
        do {
            _ = try await mock.sendMessage([AIMessage(role: .user, content: "test")], systemPrompt: nil)
            XCTFail("shouldFail=true 时应抛出错误")
        } catch AIError.notConfigured {
            // 预期
        } catch {
            XCTFail("预期 AIError.notConfigured，实际: \(error)")
        }
    }

    func testSendMessage_throwsRateLimited() async {
        mock.shouldFail = true
        mock.errorToThrow = .rateLimited(retryAfter: 30)
        do {
            _ = try await mock.sendMessage([AIMessage(role: .user, content: "test")], systemPrompt: nil)
            XCTFail("应抛出 rateLimited 错误")
        } catch AIError.rateLimited(let retryAfter) {
            XCTAssertEqual(retryAfter, 30)
        } catch {
            XCTFail("预期 rateLimited，实际: \(error)")
        }
    }

    func testSendMessage_throwsRequestFailed() async {
        mock.shouldFail = true
        mock.errorToThrow = .requestFailed(statusCode: 500, message: "Internal Server Error")
        do {
            _ = try await mock.sendMessage([AIMessage(role: .user, content: "test")], systemPrompt: nil)
            XCTFail("应抛出 requestFailed 错误")
        } catch AIError.requestFailed(let code, let msg) {
            XCTAssertEqual(code, 500)
            XCTAssertEqual(msg, "Internal Server Error")
        } catch {
            XCTFail("预期 requestFailed，实际: \(error)")
        }
    }

    // MARK: - streamMessage 成功场景

    func testStreamMessage_yieldsChunks() async throws {
        mock.mockResponse = "健康 数据 分析"
        mock.streamDelay = 0 // 测试中不等待
        let stream = mock.streamMessage([AIMessage(role: .user, content: "test")], systemPrompt: nil)

        var chunks: [String] = []
        for try await chunk in stream {
            chunks.append(chunk)
        }

        XCTAssertFalse(chunks.isEmpty, "流式响应应产出 chunk")
        let joined = chunks.joined()
        XCTAssertTrue(joined.contains("健康") || joined.contains("数据") || joined.contains("分析"),
                      "流式响应合并后应包含原始文本内容")
    }

    func testStreamMessage_throwsWhenShouldFail() async {
        mock.shouldFail = true
        mock.errorToThrow = .networkUnavailable
        mock.streamDelay = 0

        let stream = mock.streamMessage([AIMessage(role: .user, content: "test")], systemPrompt: nil)

        do {
            for try await _ in stream { /* 等待流结束 */ }
            XCTFail("shouldFail=true 时流应抛出错误")
        } catch AIError.networkUnavailable {
            // 预期
        } catch {
            XCTFail("预期 networkUnavailable，实际: \(error)")
        }
    }

    // MARK: - TokenUsage 计算

    func testTokenUsage_totalEqualsInputPlusOutput() {
        let usage = TokenUsage(inputTokens: 200, outputTokens: 100)
        XCTAssertEqual(usage.total, 300)
    }

    func testTokenUsage_zeroValues() {
        let usage = TokenUsage(inputTokens: 0, outputTokens: 0)
        XCTAssertEqual(usage.total, 0)
    }

    // MARK: - AIError 本地化描述

    func testAIError_notConfigured_hasDescription() {
        XCTAssertFalse(AIError.notConfigured.errorDescription?.isEmpty ?? true)
    }

    func testAIError_invalidAPIKey_hasDescription() {
        XCTAssertFalse(AIError.invalidAPIKey.errorDescription?.isEmpty ?? true)
    }

    func testAIError_rateLimited_withSeconds_includesSeconds() {
        let desc = AIError.rateLimited(retryAfter: 60).errorDescription ?? ""
        XCTAssertTrue(desc.contains("60"), "包含重试秒数的 rateLimited 描述应含数字 60")
    }

    func testAIError_rateLimited_withoutSeconds_hasDescription() {
        XCTAssertFalse(AIError.rateLimited(retryAfter: nil).errorDescription?.isEmpty ?? true)
    }

    func testAIError_requestFailed_includesStatusCode() {
        let desc = AIError.requestFailed(statusCode: 404, message: "Not Found").errorDescription ?? ""
        XCTAssertTrue(desc.contains("404"), "requestFailed 描述应包含状态码")
    }

    func testAIError_contextTooLong_hasDescription() {
        XCTAssertFalse(AIError.contextTooLong.errorDescription?.isEmpty ?? true)
    }

    // MARK: - 预设 Mock 工厂

    func testReportAnalysisMock_isConfiguredAndResponds() async throws {
        let reportMock = MockAIService.reportAnalysisMock()
        XCTAssertTrue(reportMock.isConfigured)
        let (content, _) = try await reportMock.sendMessage(
            [AIMessage(role: .user, content: "解读体检报告")], systemPrompt: nil
        )
        XCTAssertTrue(content.contains("体检报告"), "reportAnalysisMock 应返回体检相关内容")
    }

    func testVisitPrepMock_isConfiguredAndResponds() async throws {
        let visitMock = MockAIService.visitPrepMock()
        let (content, _) = try await visitMock.sendMessage(
            [AIMessage(role: .user, content: "准备就诊")], systemPrompt: nil
        )
        XCTAssertFalse(content.isEmpty, "visitPrepMock 应返回非空内容")
    }

    func testTermExplanationMock_isConfiguredAndResponds() async throws {
        let termMock = MockAIService.termExplanationMock()
        let (content, _) = try await termMock.sendMessage(
            [AIMessage(role: .user, content: "血糖")], systemPrompt: nil
        )
        XCTAssertFalse(content.isEmpty, "termExplanationMock 应返回非空内容")
    }
}
