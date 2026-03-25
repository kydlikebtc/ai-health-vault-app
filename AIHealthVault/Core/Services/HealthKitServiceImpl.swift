import Foundation
import HealthKit
import SwiftData
import os

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aihealthvault", category: "HealthKit")

// MARK: - HealthKitService

/// HealthKit 服务的真实实现
/// - 在模拟器上 isAvailable == false，所有方法均为空操作
/// - 使用 HKAnchoredObjectQuery 实现增量同步，避免重复写入
/// - 通过 UserDefaults 持久化每个成员、每种指标的同步锚点
@MainActor
final class HealthKitService: ObservableObject, HealthKitServiceProtocol {

    // MARK: - Published Properties

    @Published private(set) var authorizationStatus: HealthKitAuthStatus = .notDetermined
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncDate: Date? = nil

    // MARK: - Internal

    let isAvailable = HKHealthStore.isHealthDataAvailable()
    private let store = HKHealthStore()

    // MARK: - HealthKit Types

    /// 请求读取权限的类型集合
    private var readTypes: Set<HKObjectType> {
        [
            HKQuantityType(.stepCount),
            HKQuantityType(.heartRate),
            HKCategoryType(.sleepAnalysis),
            HKQuantityType(.bodyMass),
            HKCorrelationType(.bloodPressure),
            HKQuantityType(.oxygenSaturation),
        ]
    }

    /// 可用于 ObserverQuery 的采样类型（不含 Correlation）
    private var observableTypes: [HKSampleType] {
        [
            HKQuantityType(.stepCount),
            HKQuantityType(.heartRate),
            HKCategoryType(.sleepAnalysis),
            HKQuantityType(.bodyMass),
            HKQuantityType(.bloodPressureSystolic),
            HKQuantityType(.oxygenSaturation),
        ]
    }

    // MARK: - Authorization

    func requestAuthorization() async throws {
        guard isAvailable else {
            logger.debug("设备不支持 HealthKit（模拟器），跳过授权")
            return
        }
        try await store.requestAuthorization(toShare: [], read: readTypes)
        refreshAuthorizationStatus()
        logger.info("授权请求完成，状态: \(self.authorizationStatus.displayName, privacy: .public)")
    }

    private func refreshAuthorizationStatus() {
        let stepType = HKQuantityType(.stepCount)
        switch store.authorizationStatus(for: stepType) {
        case .notDetermined:     authorizationStatus = .notDetermined
        case .sharingAuthorized: authorizationStatus = .authorized
        case .sharingDenied:     authorizationStatus = .denied
        @unknown default:        authorizationStatus = .restricted
        }
    }

    // MARK: - Today Summary

    /// 读取今日健康摘要（轻量级，并发抓取所有指标）
    func fetchTodaySummary() async throws -> HealthKitTodaySummary {
        guard isAvailable else {
            logger.debug("不可用，返回空摘要")
            return HealthKitTodaySummary()
        }
        async let steps      = fetchTodaySteps()
        async let heartRate  = fetchLatestHeartRate()
        async let sleep      = fetchLastNightSleep()
        async let weight     = fetchLatestWeight()
        async let bp         = fetchLatestBloodPressure()
        async let oxygen     = fetchLatestBloodOxygen()

        let (s, hr, sl, w, bpResult, ox) = try await (steps, heartRate, sleep, weight, bp, oxygen)
        logger.info("摘要抓取完成: 步数=\(s ?? -1, format: .decimal), 心率=\(hr ?? -1, format: .decimal), 睡眠=\(sl ?? -1, format: .decimal)h")
        return HealthKitTodaySummary(
            steps:       s,
            heartRate:   hr,
            sleepHours:  sl,
            weight:      w,
            systolicBP:  bpResult?.systolic,
            diastolicBP: bpResult?.diastolic,
            bloodOxygen: ox
        )
    }

    // MARK: - SwiftData Sync

    /// 增量同步 HealthKit 数据到 SwiftData，返回新增条目数
    func syncToSwiftData(member: Member, context: ModelContext) async throws -> Int {
        guard isAvailable else { return 0 }
        isSyncing = true
        defer { isSyncing = false }

        var total = 0
        total += try await syncSteps(member: member, context: context)
        total += try await syncHeartRate(member: member, context: context)
        total += try await syncSleep(member: member, context: context)
        total += try await syncWeight(member: member, context: context)
        total += try await syncBloodPressure(member: member, context: context)
        total += try await syncBloodOxygen(member: member, context: context)

        if total > 0 {
            try context.save()
        }
        lastSyncDate = .now
        logger.info("同步完成，新增 \(total, format: .decimal) 条记录")
        return total
    }

    // MARK: - Background Delivery

    /// 为所有指标注册后台 delivery，有新数据时调用 onNewData
    /// 注意：需要在 Xcode Project → Capabilities 中开启 Background Modes → Background Delivery
    func enableBackgroundDelivery(onNewData: @escaping @Sendable () -> Void) async throws {
        guard isAvailable else { return }
        for sampleType in observableTypes {
            let query = HKObserverQuery(sampleType: sampleType, predicate: nil) { _, completionHandler, error in
                if let error {
                    logger.error("Observer 回调错误 (\(sampleType.identifier, privacy: .public)): \(error.localizedDescription, privacy: .public)")
                } else {
                    logger.debug("检测到新数据: \(sampleType.identifier, privacy: .public)")
                    onNewData()
                }
                completionHandler()
            }
            store.execute(query)
            try await store.enableBackgroundDelivery(for: sampleType, frequency: .immediate)
            logger.debug("后台 delivery 已启用: \(sampleType.identifier, privacy: .public)")
        }
    }

    // MARK: - Individual Fetch Methods

    private func fetchTodaySteps() async throws -> Int? {
        let type = HKQuantityType(.stepCount)
        let startOfDay = Calendar.current.startOfDay(for: .now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: .now, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error { continuation.resume(throwing: error); return }
                let count = statistics?.sumQuantity()?.doubleValue(for: .count())
                continuation.resume(returning: count.map { Int($0) })
            }
            store.execute(query)
        }
    }

    private func fetchLatestHeartRate() async throws -> Double? {
        let type = HKQuantityType(.heartRate)
        let predicate = HKQuery.predicateForSamples(withStart: Date(timeIntervalSinceNow: -86400), end: nil)
        return try await fetchLatestQuantitySample(type: type, predicate: predicate, unit: HKUnit(from: "count/min"))
    }

    private func fetchLastNightSleep() async throws -> Double? {
        let type = HKCategoryType(.sleepAnalysis)
        let predicate = HKQuery.predicateForSamples(withStart: Date(timeIntervalSinceNow: -86400), end: nil)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                guard let samples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: nil); return
                }
                // 汇总所有睡眠阶段（排除 inBed 和 awake）
                let asleepValues: Set<Int> = [
                    HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                    HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                    HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                ]
                let totalSeconds = samples
                    .filter { asleepValues.contains($0.value) }
                    .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                let hours = totalSeconds / 3600.0
                continuation.resume(returning: hours > 0 ? hours : nil)
            }
            store.execute(query)
        }
    }

    private func fetchLatestWeight() async throws -> Double? {
        let type = HKQuantityType(.bodyMass)
        return try await fetchLatestQuantitySample(type: type, predicate: nil, unit: .gramUnit(with: .kilo))
    }

    private func fetchLatestBloodPressure() async throws -> BPReading? {
        let type = HKCorrelationType(.bloodPressure)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKCorrelationQuery(type: type, predicate: nil, samplePredicates: nil) { _, correlations, error in
                if let error { continuation.resume(throwing: error); return }
                guard let correlation = correlations?.sorted(by: { $0.endDate > $1.endDate }).first else {
                    continuation.resume(returning: nil); return
                }
                let mmHg = HKUnit.millimeterOfMercury()
                let systolicSample = correlation.objects(for: HKQuantityType(.bloodPressureSystolic)).first as? HKQuantitySample
                let diastolicSample = correlation.objects(for: HKQuantityType(.bloodPressureDiastolic)).first as? HKQuantitySample
                guard let sys = systolicSample, let dia = diastolicSample else {
                    continuation.resume(returning: nil); return
                }
                continuation.resume(returning: BPReading(
                    systolic: sys.quantity.doubleValue(for: mmHg),
                    diastolic: dia.quantity.doubleValue(for: mmHg)
                ))
            }
            self.store.execute(query)
        }
    }

    private func fetchLatestBloodOxygen() async throws -> Double? {
        let type = HKQuantityType(.oxygenSaturation)
        let raw = try await fetchLatestQuantitySample(type: type, predicate: nil, unit: .percent())
        return raw.map { $0 * 100 }  // HealthKit 存储 0.0-1.0，转为 %
    }

    /// 通用：抓取最新单值 HKQuantitySample
    private func fetchLatestQuantitySample(
        type: HKQuantityType,
        predicate: NSPredicate?,
        unit: HKUnit
    ) async throws -> Double? {
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: [sort]) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil); return
                }
                continuation.resume(returning: sample.quantity.doubleValue(for: unit))
            }
            self.store.execute(query)
        }
    }

    // MARK: - Individual Sync Methods

    private func syncSteps(member: Member, context: ModelContext) async throws -> Int {
        let type = HKQuantityType(.stepCount)
        let (samples, anchor) = try await fetchAnchoredSamples(type: type, memberID: member.id, metricKey: "steps")
        var count = 0
        for case let sample as HKQuantitySample in samples {
            guard !entryExists(healthKitId: sample.uuid.uuidString, in: context) else { continue }
            let entry = WearableEntry(
                metricType: .steps,
                value: sample.quantity.doubleValue(for: .count()),
                recordedAt: sample.endDate,
                source: "Apple Health"
            )
            entry.healthKitSampleId = sample.uuid.uuidString
            entry.member = member
            context.insert(entry)
            count += 1
        }
        if let anchor { saveAnchor(anchor, memberID: member.id, metricKey: "steps") }
        return count
    }

    private func syncHeartRate(member: Member, context: ModelContext) async throws -> Int {
        let type = HKQuantityType(.heartRate)
        let unit = HKUnit(from: "count/min")
        let (samples, anchor) = try await fetchAnchoredSamples(type: type, memberID: member.id, metricKey: "heartRate")
        var count = 0
        for case let sample as HKQuantitySample in samples {
            guard !entryExists(healthKitId: sample.uuid.uuidString, in: context) else { continue }
            let entry = WearableEntry(
                metricType: .heartRate,
                value: sample.quantity.doubleValue(for: unit),
                recordedAt: sample.endDate,
                source: "Apple Health"
            )
            entry.healthKitSampleId = sample.uuid.uuidString
            entry.member = member
            context.insert(entry)
            count += 1
        }
        if let anchor { saveAnchor(anchor, memberID: member.id, metricKey: "heartRate") }
        return count
    }

    private func syncSleep(member: Member, context: ModelContext) async throws -> Int {
        let type = HKCategoryType(.sleepAnalysis)
        let (samples, anchor) = try await fetchAnchoredSamples(type: type, memberID: member.id, metricKey: "sleep")
        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
        ]
        var count = 0
        for case let sample as HKCategorySample in samples where asleepValues.contains(sample.value) {
            guard !entryExists(healthKitId: sample.uuid.uuidString, in: context) else { continue }
            let hours = sample.endDate.timeIntervalSince(sample.startDate) / 3600.0
            let entry = WearableEntry(
                metricType: .sleepHours,
                value: hours,
                recordedAt: sample.endDate,
                source: "Apple Health"
            )
            entry.healthKitSampleId = sample.uuid.uuidString
            entry.member = member
            context.insert(entry)
            count += 1
        }
        if let anchor { saveAnchor(anchor, memberID: member.id, metricKey: "sleep") }
        return count
    }

    private func syncWeight(member: Member, context: ModelContext) async throws -> Int {
        let type = HKQuantityType(.bodyMass)
        let (samples, anchor) = try await fetchAnchoredSamples(type: type, memberID: member.id, metricKey: "weight")
        var count = 0
        for case let sample as HKQuantitySample in samples {
            guard !entryExists(healthKitId: sample.uuid.uuidString, in: context) else { continue }
            let entry = WearableEntry(
                metricType: .weight,
                value: sample.quantity.doubleValue(for: .gramUnit(with: .kilo)),
                recordedAt: sample.endDate,
                source: "Apple Health"
            )
            entry.healthKitSampleId = sample.uuid.uuidString
            entry.member = member
            context.insert(entry)
            count += 1
        }
        if let anchor { saveAnchor(anchor, memberID: member.id, metricKey: "weight") }
        return count
    }

    private func syncBloodPressure(member: Member, context: ModelContext) async throws -> Int {
        let type = HKCorrelationType(.bloodPressure)
        let (samples, anchor) = try await fetchAnchoredSamples(type: type, memberID: member.id, metricKey: "bloodPressure")
        let mmHg = HKUnit.millimeterOfMercury()
        var count = 0
        for case let correlation as HKCorrelation in samples {
            guard !entryExists(healthKitId: correlation.uuid.uuidString, in: context) else { continue }
            let systolicSample = correlation.objects(for: HKQuantityType(.bloodPressureSystolic)).first as? HKQuantitySample
            let diastolicSample = correlation.objects(for: HKQuantityType(.bloodPressureDiastolic)).first as? HKQuantitySample
            guard let sys = systolicSample, let dia = diastolicSample else { continue }
            let entry = WearableEntry(
                metricType: .bloodPressure,
                value: sys.quantity.doubleValue(for: mmHg),
                secondaryValue: dia.quantity.doubleValue(for: mmHg),
                recordedAt: correlation.endDate,
                source: "Apple Health"
            )
            entry.healthKitSampleId = correlation.uuid.uuidString
            entry.member = member
            context.insert(entry)
            count += 1
        }
        if let anchor { saveAnchor(anchor, memberID: member.id, metricKey: "bloodPressure") }
        return count
    }

    private func syncBloodOxygen(member: Member, context: ModelContext) async throws -> Int {
        let type = HKQuantityType(.oxygenSaturation)
        let (samples, anchor) = try await fetchAnchoredSamples(type: type, memberID: member.id, metricKey: "bloodOxygen")
        var count = 0
        for case let sample as HKQuantitySample in samples {
            guard !entryExists(healthKitId: sample.uuid.uuidString, in: context) else { continue }
            let percentage = sample.quantity.doubleValue(for: .percent()) * 100
            let entry = WearableEntry(
                metricType: .bloodOxygen,
                value: percentage,
                recordedAt: sample.endDate,
                source: "Apple Health"
            )
            entry.healthKitSampleId = sample.uuid.uuidString
            entry.member = member
            context.insert(entry)
            count += 1
        }
        if let anchor { saveAnchor(anchor, memberID: member.id, metricKey: "bloodOxygen") }
        return count
    }

    // MARK: - Anchor Helpers

    /// 使用 HKAnchoredObjectQuery 抓取锚点之后的增量数据
    private func fetchAnchoredSamples(
        type: HKObjectType,
        memberID: UUID,
        metricKey: String
    ) async throws -> ([HKSample], HKQueryAnchor?) {
        let anchor = loadAnchor(memberID: memberID, metricKey: metricKey)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: type,
                predicate: nil,
                anchor: anchor,
                limit: HKObjectQueryNoLimit
            ) { _, samples, _, newAnchor, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: (samples ?? [], newAnchor))
            }
            store.execute(query)
        }
    }

    private func anchorDefaultsKey(memberID: UUID, metricKey: String) -> String {
        "hk_anchor_\(memberID.uuidString)_\(metricKey)"
    }

    private func loadAnchor(memberID: UUID, metricKey: String) -> HKQueryAnchor? {
        let key = anchorDefaultsKey(memberID: memberID, metricKey: metricKey)
        guard let data = UserDefaults.standard.data(forKey: key),
              let anchor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
        else { return nil }
        return anchor
    }

    private func saveAnchor(_ anchor: HKQueryAnchor, memberID: UUID, metricKey: String) {
        let key = anchorDefaultsKey(memberID: memberID, metricKey: metricKey)
        let data = try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true)
        UserDefaults.standard.set(data, forKey: key)
    }

    // MARK: - SwiftData Dedup Helpers

    /// 检查是否已存在相同 healthKitSampleId 的条目（双重保险，防止锚点丢失后重复插入）
    private func entryExists(healthKitId: String, in context: ModelContext) -> Bool {
        let predicate = #Predicate<WearableEntry> { entry in
            entry.healthKitSampleId == healthKitId
        }
        let descriptor = FetchDescriptor<WearableEntry>(predicate: predicate)
        return (try? context.fetch(descriptor))?.isEmpty == false
    }
}
