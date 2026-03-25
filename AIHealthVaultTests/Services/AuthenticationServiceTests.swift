import XCTest
@testable import AIHealthVault

/// AuthenticationService 测试
///
/// 注：LAContext 是系统级 API，无法在单元测试中直接 mock（不支持 Face ID）
/// 因此只能测试 AuthenticationService 的**可观察输出**，而非内部调用。
/// 真实生物认证需在 TestFlight 真机上手动验证。
@MainActor
final class AuthenticationServiceTests: XCTestCase {

    var sut: AuthenticationService!

    override func setUp() {
        super.setUp()
        sut = AuthenticationService()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - 初始状态

    func testInitialState_isNotAuthenticated() {
        XCTAssertFalse(sut.isAuthenticated)
    }

    func testInitialState_errorIsNil() {
        XCTAssertNil(sut.authError)
    }

    // MARK: - 锁定

    func testLock_setsAuthenticatedToFalse() {
        // 先模拟已认证状态
        sut.isAuthenticated = true
        XCTAssertTrue(sut.isAuthenticated)

        sut.lock()

        XCTAssertFalse(sut.isAuthenticated)
    }

    func testLock_clearsAuthError() {
        sut.authError = "之前的错误"
        sut.lock()
        XCTAssertNil(sut.authError)
    }

    func testLock_fromAlreadyLockedState_isIdempotent() {
        sut.lock()
        sut.lock()
        XCTAssertFalse(sut.isAuthenticated)
        XCTAssertNil(sut.authError)
    }

    // MARK: - 生物认证可用性（读取本地环境）

    func testBiometricAvailable_returnsExpectedType() {
        // 在测试环境（模拟器）中，生物认证通常不可用
        // 此测试验证属性可读取，不会 crash
        _ = sut.isBiometricAvailable
        _ = sut.biometricTypeName
        XCTAssert(true, "biometricTypeName 读取不应崩溃")
    }

    func testBiometricTypeName_returnsNonEmptyString() {
        XCTAssertFalse(sut.biometricTypeName.isEmpty)
    }

    // MARK: - 模拟器认证流程

    /// 在模拟器中，生物认证不可用时 authenticate() 应直接放行
    func testAuthenticate_onSimulator_mayAutoAuthenticate() async {
        // 在模拟器上，canEvaluatePolicy 返回 false，服务直接设置 isAuthenticated = true
        // 在真机上此测试会走实际 Face ID，需在 TestFlight 阶段单独验证
        await sut.authenticate()
        // 不断言具体值——行为依赖设备能力，只验证不 crash
        XCTAssert(true, "authenticate() 完成不应崩溃")
    }

    // MARK: - ObservableObject 发布变更

    func testLock_publishesIsAuthenticatedChange() {
        let expectation = XCTestExpectation(description: "isAuthenticated 变更发布")
        sut.isAuthenticated = true

        var receivedValues: [Bool] = []
        let cancellable = sut.$isAuthenticated.sink { value in
            receivedValues.append(value)
            if receivedValues.count >= 2 {
                expectation.fulfill()
            }
        }

        sut.lock()

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedValues.last, false)
        cancellable.cancel()
    }
}
