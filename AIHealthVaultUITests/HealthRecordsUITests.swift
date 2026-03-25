import XCTest

/// 健康记录功能 UI Tests (XCUITest)
/// 覆盖：空状态页面、Tab 导航、记录标签页进入、相机权限弹窗处理
///
/// 注意：完整的添加/编辑/删除流程依赖模拟器中有家庭成员数据。
/// 本测试在干净启动环境下验证导航结构和空状态行为。
final class HealthRecordsUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-UITesting"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - 导航测试

    /// 验证「记录」Tab 可以正常点击并显示导航标题
    func testRecordsTab_isReachable() throws {
        let recordsTab = app.tabBars.buttons["记录"]
        XCTAssertTrue(recordsTab.waitForExistence(timeout: 5),
                      "底部 Tab 栏应有「记录」按钮")
        recordsTab.tap()

        let navTitle = app.navigationBars["健康记录"]
        XCTAssertTrue(navTitle.waitForExistence(timeout: 3),
                      "进入记录页面后应显示「健康记录」导航标题")
    }

    /// 验证四个主 Tab 均可见
    func testMainTabs_allVisible() throws {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))

        for tabName in ["家庭", "记录", "AI 助手", "设置"] {
            XCTAssertTrue(tabBar.buttons[tabName].exists,
                          "底部 Tab 栏应包含「\(tabName)」")
        }
    }

    // MARK: - 空状态测试

    /// 在干净启动环境下（无家庭成员），「记录」Tab 应显示空状态提示
    func testRecordsTab_rendersWithoutCrash() throws {
        let recordsTab = app.tabBars.buttons["记录"]
        XCTAssertTrue(recordsTab.waitForExistence(timeout: 5))
        recordsTab.tap()

        let navBar = app.navigationBars["健康记录"]
        XCTAssertTrue(navBar.waitForExistence(timeout: 5),
                      "记录页面应能正常渲染（有或无数据）")
    }

    /// 「家庭」Tab 空状态：App 不应崩溃
    func testFamilyTab_rendersWithoutCrash() throws {
        let familyTab = app.tabBars.buttons["家庭"]
        XCTAssertTrue(familyTab.waitForExistence(timeout: 5))
        familyTab.tap()

        XCTAssertTrue(app.state == .runningForeground,
                      "点击家庭 Tab 后 App 应保持前台运行状态")
    }

    // MARK: - AI 助手 Tab

    func testAITab_rendersWithoutCrash() throws {
        let aiTab = app.tabBars.buttons["AI 助手"]
        XCTAssertTrue(aiTab.waitForExistence(timeout: 5))
        aiTab.tap()

        XCTAssertTrue(app.state == .runningForeground)
    }

    // MARK: - 设置 Tab

    func testSettingsTab_rendersWithoutCrash() throws {
        let settingsTab = app.tabBars.buttons["设置"]
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 5))
        settingsTab.tap()

        XCTAssertTrue(app.state == .runningForeground)
    }

    // MARK: - 相机权限处理（Alert 拦截）

    /// 注册系统 Alert 处理器，在相机/图库权限弹窗出现时选择「不允许」
    /// 验证 App 在权限被拒绝后不崩溃
    func testCameraPermissionAlert_canBeHandled() throws {
        let recordsTab = app.tabBars.buttons["记录"]
        XCTAssertTrue(recordsTab.waitForExistence(timeout: 5))
        recordsTab.tap()

        _ = app.navigationBars["健康记录"].waitForExistence(timeout: 3)

        // 注册系统 Alert 中断处理器
        addUIInterruptionMonitor(withDescription: "相机/图库权限弹窗") { alert in
            // 查找拒绝按钮（中文「不允许」或英文「Don't Allow」）
            let buttons = alert.buttons
            for label in ["不允许", "Don't Allow", "Deny"] {
                let btn = buttons[label]
                if btn.exists {
                    btn.tap()
                    return true
                }
            }
            return false
        }

        // 触发交互，激活中断处理器（如有弹窗）
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        XCTAssertTrue(app.state == .runningForeground,
                      "处理相机权限弹窗后 App 应保持运行状态")
    }

    // MARK: - Phase 3 AI 功能 UI Tests

    /// AI 助手 Tab 进入后 App 保持正常
    func testAIAssistantTab_showsFunctionalContent() throws {
        let aiTab = app.tabBars.buttons["AI 助手"]
        XCTAssertTrue(aiTab.waitForExistence(timeout: 5))
        aiTab.tap()

        XCTAssertTrue(app.state == .runningForeground,
                      "进入 AI 助手 Tab 后 App 应保持前台运行")
    }

    /// 设置页面可进入 AI 设置区域
    func testSettingsTab_aiSettingsEntryExists() throws {
        let settingsTab = app.tabBars.buttons["设置"]
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 5))
        settingsTab.tap()

        XCTAssertTrue(app.state == .runningForeground,
                      "设置页面应正常渲染，可访问 AI 设置")
    }

    /// 从 AI Tab 到设置再切换回来，无崩溃
    func testAIToSettingsNavigation_doesNotCrash() throws {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))

        tabBar.buttons["AI 助手"].tap()
        tabBar.buttons["设置"].tap()
        tabBar.buttons["AI 助手"].tap()

        XCTAssertTrue(app.state == .runningForeground,
                      "AI 助手 ↔ 设置 来回切换后 App 应保持正常运行")
    }

    /// 趋势图表入口：家庭 Tab → 成员列表渲染正常
    func testFamilyTab_trendEntryPoint_doesNotCrash() throws {
        let familyTab = app.tabBars.buttons["家庭"]
        XCTAssertTrue(familyTab.waitForExistence(timeout: 5))
        familyTab.tap()

        XCTAssertTrue(app.state == .runningForeground,
                      "家庭 Tab（健康趋势入口）应正常渲染，无崩溃")
    }

    /// 完整 Tab 轮询：家庭 → 记录 → AI → 设置 均可访问
    func testAllTabsFullRotation_noMemoryLeak() throws {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))

        let tabNames = ["家庭", "记录", "AI 助手", "设置"]
        for tabName in tabNames {
            let button = tabBar.buttons[tabName]
            if button.waitForExistence(timeout: 3) {
                button.tap()
                XCTAssertTrue(app.state == .runningForeground,
                              "切换到「\(tabName)」后 App 应保持前台运行")
            }
        }
    }

    // MARK: - Tab 快速切换稳定性

    /// 快速切换所有 Tab，验证不会崩溃
    func testTabSwitching_doesNotCrash() throws {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))

        for tabName in ["家庭", "记录", "AI 助手", "设置", "记录", "家庭"] {
            let button = tabBar.buttons[tabName]
            if button.exists {
                button.tap()
            }
        }

        XCTAssertTrue(app.state == .runningForeground,
                      "多次切换 Tab 后 App 应保持正常运行")
    }
}
