import Foundation
import SwiftData

// MARK: - Supporting Types

/// HealthKit 授权状态
enum HealthKitAuthStatus {
    case notDetermined
    case authorized
    case denied
    case restricted

    var displayName: String {
        switch self {
        case .notDetermined: return "未授权"
        case .authorized:    return "已连接"
        case .denied:        return "已拒绝"
        case .restricted:    return "受限制"
        }
    }

    var iconName: String {
        switch self {
        case .notDetermined: return "questionmark.circle"
        case .authorized:    return "checkmark.circle.fill"
        case .denied:        return "xmark.circle.fill"
        case .restricted:    return "exclamationmark.circle.fill"
        }
    }
}

/// 今日健康摘要（从 HealthKit 读取）
struct HealthKitTodaySummary: Sendable {
    var steps: Int?             // 今日步数
    var heartRate: Double?      // 最新心率（bpm）
    var sleepHours: Double?     // 昨晚睡眠时长（小时）
    var weight: Double?         // 最新体重（kg）
    var systolicBP: Double?     // 最新收缩压（mmHg）
    var diastolicBP: Double?    // 最新舒张压（mmHg）
    var bloodOxygen: Double?    // 最新血氧（%）
    var fetchedAt: Date = .now

    var isEmpty: Bool {
        steps == nil && heartRate == nil && sleepHours == nil &&
        weight == nil && systolicBP == nil && bloodOxygen == nil
    }
}

/// 血压读数（辅助结构）
struct BPReading: Sendable {
    let systolic: Double
    let diastolic: Double
}

// MARK: - Service Protocol

/// HealthKit 服务协议——支持真实实现和 Mock 测试两种实现
protocol HealthKitServiceProtocol: AnyObject {
    /// 设备是否支持 HealthKit（模拟器返回 false）
    var isAvailable: Bool { get }
    /// 当前授权状态
    var authorizationStatus: HealthKitAuthStatus { get }
    /// 是否正在同步
    var isSyncing: Bool { get }
    /// 上次成功同步时间
    var lastSyncDate: Date? { get }

    /// 请求 HealthKit 读取权限
    func requestAuthorization() async throws

    /// 获取今日健康摘要（轻量级，不写入 SwiftData）
    func fetchTodaySummary() async throws -> HealthKitTodaySummary

    /// 将 HealthKit 增量数据同步写入 SwiftData，返回新增条目数
    @discardableResult
    func syncToSwiftData(member: Member, context: ModelContext) async throws -> Int

    /// 注册 HealthKit 后台 delivery，有新数据时回调 handler
    func enableBackgroundDelivery(onNewData: @escaping @Sendable () -> Void) async throws
}
