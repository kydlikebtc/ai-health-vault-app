import Foundation

/// Mock AI 服务 — 用于单元测试和 SwiftUI Preview
/// 不发出真实网络请求，返回预设响应
final class MockAIService: AIService, @unchecked Sendable {

    // MARK: - Configuration

    var mockResponse: String = "这是 AI 的模拟回复。在实际使用中，Claude 会根据您的健康数据提供专业分析。"
    var mockUsage = TokenUsage(inputTokens: 150, outputTokens: 80)
    var shouldFail = false
    var errorToThrow: AIError = .notConfigured
    var streamDelay: UInt64 = 50_000_000 // 50ms，模拟 SSE 逐 token 延迟

    // MARK: - AIService

    var isConfigured: Bool = true

    func sendMessage(
        _ messages: [AIMessage],
        systemPrompt: String?
    ) async throws -> (content: String, usage: TokenUsage) {
        try await Task.sleep(nanoseconds: 300_000_000) // 模拟 300ms 网络延迟
        if shouldFail { throw errorToThrow }
        return (content: mockResponse, usage: mockUsage)
    }

    nonisolated func streamMessage(
        _ messages: [AIMessage],
        systemPrompt: String?
    ) -> AsyncThrowingStream<String, Error> {
        let chunks = mockResponse.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        let delay = streamDelay
        let shouldFail = self.shouldFail
        let errorToThrow = self.errorToThrow

        return AsyncThrowingStream { continuation in
            Task {
                if shouldFail {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    continuation.finish(throwing: errorToThrow)
                    return
                }

                for (index, chunk) in chunks.enumerated() {
                    try? await Task.sleep(nanoseconds: delay)
                    let text = index == 0 ? chunk : " \(chunk)"
                    continuation.yield(text)
                }
                continuation.finish()
            }
        }
    }
}

// MARK: - 预设医疗场景 Mock 响应

extension MockAIService {

    static func reportAnalysisMock() -> MockAIService {
        let mock = MockAIService()
        mock.mockResponse = """
        **体检报告解读**

        根据您提供的体检数据，以下是关键指标分析：

        **✅ 正常指标**
        - 血压：120/80 mmHg（正常范围）
        - 空腹血糖：5.2 mmol/L（正常）
        - BMI：22.5（正常体重范围）

        **⚠️ 需关注指标**
        - 总胆固醇：5.8 mmol/L（略高于参考值 5.2）
        - 建议：减少饱和脂肪摄入，适当增加有氧运动

        **📋 建议**
        1. 保持现有生活方式中的健康习惯
        2. 6个月后复查血脂
        3. 如有不适，及时就医

        *以上分析仅供参考，具体诊断请咨询医生。*
        """
        return mock
    }

    static func visitPrepMock() -> MockAIService {
        let mock = MockAIService()
        mock.mockResponse = """
        **就诊准备清单**

        根据您的健康档案，为本次就诊准备了以下内容：

        **📋 需携带材料**
        - 身份证和医保卡
        - 近3个月体检报告
        - 当前用药清单（阿托伐他汀 10mg）

        **💬 建议向医生说明**
        - 症状持续时间及变化规律
        - 近期饮食和运动变化
        - 药物服用情况和不适反应

        **❓ 建议提问**
        1. 胆固醇升高的主要原因是什么？
        2. 是否需要调整用药剂量？
        3. 饮食方面有哪些具体建议？

        祝您就诊顺利！
        """
        return mock
    }

    static func termExplanationMock() -> MockAIService {
        let mock = MockAIService()
        mock.mockResponse = "该术语是一项常见的医学检测指标。正常范围因年龄和性别有所差异，建议结合报告中的参考值范围和您的整体健康状况进行综合判断。如指标偏高或偏低，通常需要配合饮食调整或复查，具体处理请咨询医生。"
        return mock
    }

    static func dailyPlanMock() -> MockAIService {
        let mock = MockAIService()
        mock.mockResponse = """
        ## 今日健康计划

        ### 今日饮食
        - 早餐：全麦面包 + 低脂牛奶，避免高糖食品
        - 午餐：以蔬菜为主，搭配适量优质蛋白（鸡肉/鱼）
        - 晚餐：清淡为主，八分饱，21:00 后避免进食

        ### 运动建议
        - 建议步行 30 分钟（当前步数目标：8000步）
        - 可做简单拉伸 10 分钟改善循环

        ### 注意事项
        - 保持充足饮水（建议 1500-2000ml）
        - 睡前 1 小时放下手机，确保 7-8 小时睡眠
        - 如有不适请及时就医，以上建议仅供参考
        """
        return mock
    }
}
