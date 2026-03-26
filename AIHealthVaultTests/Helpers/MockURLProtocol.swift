import Foundation

/// URLProtocol 子类，用于在测试中拦截 URLSession 请求并返回预设响应。
///
/// 使用方式：
/// ```swift
/// let session = MockURLProtocol.makeSession(statusCode: 200, body: jsonString)
/// let service = MyService(session: session)
/// ```
final class MockURLProtocol: URLProtocol {

    // MARK: - Static request handler

    /// 测试用例通过此 handler 配置每次请求的返回内容。
    /// `nonisolated(unsafe)` 允许在非 actor 上下文的 URLProtocol 回调中访问。
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    // MARK: - URLProtocol overrides

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    // MARK: - Factory

    /// 创建配置了本协议的 URLSession，固定返回指定状态码和 JSON 响应体。
    static func makeSession(
        statusCode: Int,
        body: String,
        url: URL = URL(string: "https://mock.proxy")!
    ) -> URLSession {
        requestHandler = { _ in
            let response = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(body.utf8))
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }
}
