import XCTest
import SwiftData
@testable import AIHealthVault

/// HealthKitService Mock 测试
///
/// 使用 MockHealthKitService 测试 HealthKitServiceProtocol 的所有协议方法。
/// 不依赖真实 HealthKit 框架，可在模拟器和 CI 环境中运行。
final class HealthKitServiceTests: XCTestCase {

    var sut: MockHealthKitService!
    var container: ModelContainer!
    var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        sut = MockHealthKitService()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: Member.self, configurations: config)
        context = ModelContext(container)
    }

    override func tearDown() async throws {
        sut.reset()
        sut = nil
        context = nil
        container = nil
        try await super.tearDown()
    }

    // MARK: - 初始状态

    func testInitialState_isAvailable() {
        XCTAssertTrue(sut.isAvailable)
    }

    func testInitialState_authorizationIsNotDetermined() {
        XCTAssertEqual(sut.authorizationStatus, .notDetermined)
    }

    func testInitialState_isNotSyncing() {
        XCTAssertFalse(sut.isSyncing)
    }

    func testInitialState_lastSyncDateIsNil() {
        XCTAssertNil(sut.lastSyncDate)
    }

    // MARK: - requestAuthorization

    func testRequestAuthorization_success_setsStatusToAuthorized() async throws {
        sut.shouldAuthorize = true
        try await sut.requestAuthorization()
        XCTAssertEqual(sut.authorizationStatus, .authorized)
    }

    func testRequestAuthorization_denied_setsStatusToDenied() async throws {
        sut.shouldAuthorize = false
        try await sut.requestAuthorization()
        XCTAssertEqual(sut.authorizationStatus, .denied)
    }

    func testRequestAuthorization_error_throws() async {
        sut.shouldThrowError = true
        do {
            try await sut.requestAuthorization()
            XCTFail("应抛出错误")
        } catch {
            XCTAssertTrue(error is MockHealthKitService.MockError)
        }
    }

    func testRequestAuthorization_incrementsCallCount() async throws {
        try await sut.requestAuthorization()
        try await sut.requestAuthorization()
        XCTAssertEqual(sut.requestAuthorizationCallCount, 2)
    }

    // MARK: - fetchTodaySummary

    func testFetchTodaySummary_returnsStub() async throws {
        let summary = try await sut.fetchTodaySummary()
        XCTAssertEqual(summary.steps, 8432)
        XCTAssertEqual(summary.heartRate, 72.0)
        XCTAssertEqual(summary.sleepHours, 7.5)
        XCTAssertEqual(summary.weight, 68.5)
        XCTAssertEqual(summary.bloodOxygen, 98.2)
    }

    func testFetchTodaySummary_customStub_returnsCustomData() async throws {
        sut.stubbedSummary = HealthKitTodaySummary(steps: 12000, heartRate: 65.0, sleepHours: 8.0)
        let summary = try await sut.fetchTodaySummary()
        XCTAssertEqual(summary.steps, 12000)
        XCTAssertNil(summary.weight)
    }

    func testFetchTodaySummary_error_throws() async {
        sut.shouldThrowError = true
        do {
            _ = try await sut.fetchTodaySummary()
            XCTFail("应抛出错误")
        } catch {
            XCTAssertTrue(error is MockHealthKitService.MockError)
        }
    }

    func testFetchTodaySummary_incrementsCallCount() async throws {
        _ = try await sut.fetchTodaySummary()
        _ = try await sut.fetchTodaySummary()
        XCTAssertEqual(sut.fetchTodaySummaryCallCount, 2)
    }

    func testFetchTodaySummary_emptyStub_isEmptyReturnsTrue() async throws {
        sut.stubbedSummary = HealthKitTodaySummary()
        let summary = try await sut.fetchTodaySummary()
        XCTAssertTrue(summary.isEmpty)
    }

    // MARK: - syncToSwiftData

    func testSyncToSwiftData_returnsStubCount() async throws {
        let member = Member(name: "测试成员", dateOfBirth: Date(), gender: .male)
        context.insert(member)
        let count = try await sut.syncToSwiftData(member: member, context: context)
        XCTAssertEqual(count, 3)
    }

    func testSyncToSwiftData_customSyncCount() async throws {
        sut.stubbedSyncCount = 10
        let member = Member(name: "测试成员", dateOfBirth: Date(), gender: .male)
        context.insert(member)
        let count = try await sut.syncToSwiftData(member: member, context: context)
        XCTAssertEqual(count, 10)
    }

    func testSyncToSwiftData_updatesLastSyncDate() async throws {
        let before = Date()
        let member = Member(name: "测试成员", dateOfBirth: Date(), gender: .male)
        context.insert(member)
        try await sut.syncToSwiftData(member: member, context: context)
        XCTAssertNotNil(sut.lastSyncDate)
        XCTAssertGreaterThanOrEqual(sut.lastSyncDate!, before)
    }

    func testSyncToSwiftData_error_throws() async {
        sut.shouldThrowError = true
        let member = Member(name: "测试成员", dateOfBirth: Date(), gender: .male)
        context.insert(member)
        do {
            try await sut.syncToSwiftData(member: member, context: context)
            XCTFail("应抛出错误")
        } catch {
            XCTAssertTrue(error is MockHealthKitService.MockError)
        }
    }

    func testSyncToSwiftData_incrementsCallCount() async throws {
        let member = Member(name: "测试成员", dateOfBirth: Date(), gender: .male)
        context.insert(member)
        try await sut.syncToSwiftData(member: member, context: context)
        XCTAssertEqual(sut.syncToSwiftDataCallCount, 1)
    }

    // MARK: - enableBackgroundDelivery

    func testEnableBackgroundDelivery_success_doesNotThrow() async {
        do {
            try await sut.enableBackgroundDelivery(onNewData: {})
        } catch {
            XCTFail("不应抛出错误: \(error)")
        }
    }

    func testEnableBackgroundDelivery_error_throws() async {
        sut.shouldThrowError = true
        do {
            try await sut.enableBackgroundDelivery(onNewData: {})
            XCTFail("应抛出错误")
        } catch {
            XCTAssertTrue(error is MockHealthKitService.MockError)
        }
    }

    func testEnableBackgroundDelivery_incrementsCallCount() async throws {
        try await sut.enableBackgroundDelivery(onNewData: {})
        XCTAssertEqual(sut.enableBackgroundDeliveryCallCount, 1)
    }

    // MARK: - reset()

    func testReset_clearsCallCounts() async throws {
        try await sut.requestAuthorization()
        _ = try await sut.fetchTodaySummary()
        sut.reset()
        XCTAssertEqual(sut.requestAuthorizationCallCount, 0)
        XCTAssertEqual(sut.fetchTodaySummaryCallCount, 0)
    }

    func testReset_restoresDefaultState() async throws {
        sut.shouldThrowError = true
        sut.shouldAuthorize = false
        sut.reset()
        XCTAssertFalse(sut.shouldThrowError)
        XCTAssertTrue(sut.shouldAuthorize)
        XCTAssertEqual(sut.authorizationStatus, .notDetermined)
    }

    // MARK: - HealthKitTodaySummary.isEmpty

    func testTodaySummary_isEmpty_whenAllNil() {
        let summary = HealthKitTodaySummary()
        XCTAssertTrue(summary.isEmpty)
    }

    func testTodaySummary_isNotEmpty_whenStepsPresent() {
        let summary = HealthKitTodaySummary(steps: 100)
        XCTAssertFalse(summary.isEmpty)
    }

    // MARK: - HealthKitAuthStatus.displayName

    func testAuthStatus_displayName_notDetermined() {
        XCTAssertEqual(HealthKitAuthStatus.notDetermined.displayName, "未授权")
    }

    func testAuthStatus_displayName_authorized() {
        XCTAssertEqual(HealthKitAuthStatus.authorized.displayName, "已连接")
    }

    func testAuthStatus_displayName_denied() {
        XCTAssertEqual(HealthKitAuthStatus.denied.displayName, "已拒绝")
    }

    func testAuthStatus_displayName_restricted() {
        XCTAssertEqual(HealthKitAuthStatus.restricted.displayName, "受限制")
    }
}
