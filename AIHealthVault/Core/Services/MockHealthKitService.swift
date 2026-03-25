import Foundation
import SwiftData

/// HealthKit 服务的 Mock 实现，用于单元测试
/// - 不依赖 HealthKit 框架，可在模拟器和测试目标中安全使用
/// - 返回固定的预设数据，便于测试断言
final class MockHealthKitService: HealthKitServiceProtocol {

    // MARK: - Config

    /// 是否模拟授权成功（默认 true）
    var shouldAuthorize = true
    /// 是否模拟抛出错误
    var shouldThrowError = false
    /// 预置的今日摘要（可在测试中自定义）
    var stubbedSummary = HealthKitTodaySummary(
        steps: 8432,
        heartRate: 72.0,
        sleepHours: 7.5,
        weight: 68.5,
        systolicBP: 118,
        diastolicBP: 76,
        bloodOxygen: 98.2
    )
    /// syncToSwiftData 返回的模拟新增条目数
    var stubbedSyncCount = 3

    // MARK: - Protocol State

    let isAvailable: Bool = true
    private(set) var authorizationStatus: HealthKitAuthStatus = .notDetermined
    private(set) var isSyncing = false
    private(set) var lastSyncDate: Date? = nil

    // MARK: - Call Tracking (供测试断言)

    private(set) var requestAuthorizationCallCount = 0
    private(set) var fetchTodaySummaryCallCount = 0
    private(set) var syncToSwiftDataCallCount = 0
    private(set) var enableBackgroundDeliveryCallCount = 0

    // MARK: - Protocol Methods

    func requestAuthorization() async throws {
        requestAuthorizationCallCount += 1
        if shouldThrowError { throw MockError.simulated }
        authorizationStatus = shouldAuthorize ? .authorized : .denied
    }

    func fetchTodaySummary() async throws -> HealthKitTodaySummary {
        fetchTodaySummaryCallCount += 1
        if shouldThrowError { throw MockError.simulated }
        return stubbedSummary
    }

    @discardableResult
    func syncToSwiftData(member: Member, context: ModelContext) async throws -> Int {
        syncToSwiftDataCallCount += 1
        if shouldThrowError { throw MockError.simulated }
        isSyncing = true
        defer { isSyncing = false }
        lastSyncDate = .now
        return stubbedSyncCount
    }

    func enableBackgroundDelivery(onNewData: @escaping @Sendable () -> Void) async throws {
        enableBackgroundDeliveryCallCount += 1
        if shouldThrowError { throw MockError.simulated }
    }

    // MARK: - Helpers

    enum MockError: Error {
        case simulated
    }

    func reset() {
        shouldAuthorize = true
        shouldThrowError = false
        authorizationStatus = .notDetermined
        requestAuthorizationCallCount = 0
        fetchTodaySummaryCallCount = 0
        syncToSwiftDataCallCount = 0
        enableBackgroundDeliveryCallCount = 0
    }
}
