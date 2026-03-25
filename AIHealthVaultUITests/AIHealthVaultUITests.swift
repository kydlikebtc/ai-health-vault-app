import XCTest

final class AIHealthVaultUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - 启动测试

    func testAppLaunch_completesWithoutCrash() throws {
        // 验证 App 可以正常启动
        XCTAssertTrue(app.state == .runningForeground)
    }
}
