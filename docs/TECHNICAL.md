# AI Health Vault — 技术架构文档

**版本：** v1.0
**日期：** 2026-03-25
**作者：** Product Manager
**面向读者：** iOS 工程师、架构师、技术评审者

---

## 1. 产品概述（技术视角）

AI Health Vault 是一款以**本地数据为核心**的 iOS 家庭健康档案管理应用。与传统健康 App 的云端同步模式不同，本应用优先保障用户数据主权：所有健康数据默认存储在设备本地，AI 分析能力作为可选增强层叠加，而非系统核心依赖。

**关键技术决策：**

| 决策 | 选型 | 理由 |
|------|------|------|
| 数据层 | SwiftData | iOS 17 原生持久化，与 SwiftUI 深度集成，无第三方依赖 |
| UI 框架 | SwiftUI | 声明式 UI，支持 Preview，与 SwiftData 配合流畅 |
| 并发模型 | Swift 6 strict concurrency | 避免数据竞争，@MainActor 隔离 UI 状态 |
| 认证 | LocalAuthentication + iOS Data Protection | 生物认证开发成本低，iOS 文件加密零配置 |
| 健康数据 | HealthKit | Phase 2 引入，协议抽象以支持 Mock 测试 |
| AI 能力 | Claude API | Phase 3 引入，仅传输结构化数据，不传图片 |
| 云同步 | CloudKit (可选) | Phase 4 引入，默认关闭，用户主动开启 |

---

## 2. 系统架构

### 2.1 整体架构分层

```
┌─────────────────────────────────────────────────────────┐
│                      UI Layer (SwiftUI)                  │
│  Features/Family  Features/Records  Features/AI  Settings│
└──────────────────────────┬──────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────┐
│                   ViewModel Layer                        │
│        MVVM Pattern + @Observable / @StateObject         │
└──────────┬───────────────┬───────────────┬──────────────┘
           │               │               │
┌──────────▼──┐  ┌─────────▼──┐  ┌────────▼─────────────┐
│  SwiftData  │  │  Services  │  │   External APIs       │
│  (Local DB) │  │ HealthKit  │  │   Claude API (Phase3) │
│             │  │ Auth       │  │   CloudKit (Phase4)   │
│             │  │ AI Service │  │                       │
└─────────────┘  └────────────┘  └───────────────────────┘
```

### 2.2 项目目录结构

```
AIHealthVault/
├── App/
│   ├── AIHealthVaultApp.swift       # App 入口，ModelContainer 配置
│   ├── ContentView.swift            # TabView 主导航
│   └── LockScreenView.swift         # 认证锁屏界面
├── Core/
│   ├── Models/                      # SwiftData @Model 定义
│   │   ├── Family.swift             # Family 聚合根
│   │   ├── Member.swift             # 家庭成员
│   │   ├── MedicalHistory.swift     # 既往病史
│   │   ├── Medication.swift         # 用药记录
│   │   ├── CheckupReport.swift      # 体检报告
│   │   ├── VisitRecord.swift        # 就医记录
│   │   ├── WearableEntry.swift      # 可穿戴数据（含HealthKit同步）
│   │   ├── DailyLog.swift           # 日常追踪
│   │   └── MockData.swift           # Preview 用 Mock 数据
│   ├── Services/
│   │   ├── AuthenticationService.swift      # Face ID / PIN 认证
│   │   ├── HealthKitService.swift           # HealthKit 协议定义
│   │   ├── HealthKitServiceImpl.swift       # 真实 HealthKit 实现
│   │   └── MockHealthKitService.swift       # 测试 Mock 实现
│   └── Utils/
│       └── DateExtensions.swift
├── Features/
│   ├── Family/
│   │   ├── FamilyListView.swift
│   │   ├── MemberDetailView.swift
│   │   └── AddEditMemberView.swift
│   ├── Records/
│   │   ├── RecordsView.swift                # 记录主列表（含筛选）
│   │   ├── CheckupViews.swift               # 体检记录 CRUD
│   │   ├── MedicationViews.swift            # 用药记录 CRUD
│   │   ├── VisitViews.swift                 # 就医记录 CRUD
│   │   ├── DailyLogViews.swift              # 日常追踪 CRUD
│   │   ├── MedicalHistoryViews.swift        # 既往病史 CRUD
│   │   ├── WearableViews.swift              # 可穿戴数据展示
│   │   └── SharedRecordComponents.swift     # 公用 UI 组件
│   ├── AI/
│   │   └── AIView.swift                     # AI 功能占位（Phase 3）
│   └── Settings/
│       └── SettingsView.swift
└── Resources/
    └── Assets.xcassets
```

---

## 3. 核心数据模型

### 3.1 数据模型关系图

```
Family
  └── [Member]          (一对多，@Relationship)
        ├── profile:    MemberProfile   (内嵌值类型)
        ├── healthStatus: HealthStatus  (内嵌值类型)
        ├── [MedicalHistory]            (一对多)
        ├── [Medication]                (一对多)
        ├── [CheckupReport]
        │     └── [CheckupItem]         (体检指标条目)
        ├── [VisitRecord]
        ├── [WearableEntry]             (含 hkSourceId 用于去重)
        └── [DailyLog]
```

### 3.2 WearableEntry 设计要点

`WearableEntry` 同时支持手动录入和 HealthKit 自动同步：

```swift
@Model
class WearableEntry {
    @Attribute(.unique) var id: UUID
    var dataType: WearableDataType    // 步数/心率/睡眠/体重/血压/血氧
    var value: Double
    var unit: String
    var recordedAt: Date
    var source: DataSource            // .manual | .healthKit
    var hkSourceId: String?           // HKSample UUID，用于去重
    var member: Member?
}
```

**去重策略：** 同步时先查询 `hkSourceId`，若已存在则跳过，避免重复写入。

### 3.3 数据持久化配置

```swift
// App 入口处配置 ModelContainer
let schema = Schema([
    Family.self, Member.self,
    MedicalHistory.self, Medication.self,
    CheckupReport.self, CheckupItem.self,
    VisitRecord.self, WearableEntry.self, DailyLog.self
])
let config = ModelConfiguration(
    schema: schema,
    isStoredInMemoryOnly: false,    // 生产环境持久化
    cloudKitDatabase: .none         // Phase 4 开启 CloudKit 前保持 .none
)
```

**测试环境：** 使用 `isStoredInMemoryOnly: true`，每个测试用例独立容器，无数据污染。

---

## 4. 核心服务设计

### 4.1 认证服务（AuthenticationService）

认证流程采用状态机模型：

```
未认证 → [生物认证] → 已认证
         ↓ 失败3次
         [PIN 认证] → 已认证
                      ↓ App 后台 > 5分钟
                      重新锁定
```

- 使用 `LocalAuthentication.LAContext` 请求 Face ID / Touch ID
- PIN 以加密形式存储于 iOS Keychain（非 SwiftData）
- `AuthenticationService` 以单例形式注入，支持 `@Observable` 状态监听

### 4.2 HealthKit 服务（协议隔离）

采用协议抽象隔离真实 HealthKit，解耦测试依赖：

```swift
protocol HealthKitService {
    func requestAuthorization() async throws
    func fetchDailyStepCount(for date: Date) async throws -> Int
    func fetchHeartRate(from start: Date, to end: Date) async throws -> [HKQuantitySample]
    func fetchSleepAnalysis(from start: Date, to end: Date) async throws -> [HKCategorySample]
    func observeNewData(handler: @escaping () -> Void)
}
```

- **生产实现**（`HealthKitServiceImpl`）：调用真实 HealthKit API，处理模拟器不可用场景
- **测试实现**（`MockHealthKitService`）：返回预设数据，无系统权限要求

**后台同步机制：**
- 使用 `HKObserverQuery` 注册后台 delivery
- 触发条件：HealthKit 有新数据写入 + 每次 App 激活时主动拉取
- 同步频率 OQ-1（待 iOS Dev 确认）：建议每日刷新，避免过度消耗电量

### 4.3 AI 服务（Phase 3 预留）

```swift
protocol AIAnalysisService {
    func analyzeHealthReport(_ indicators: [CheckupItem]) async throws -> HealthReportAnalysis
    func generateVisitSummary(for member: Member) async throws -> VisitSummary
}
```

数据传输原则：
- **只传结构化数据**（指标名称 + 数值），不传原始图片
- **不传用户身份信息**（姓名、生日等敏感字段脱敏或不传）
- 首次使用前展示数据使用说明，用户主动确认

---

## 5. 关键技术约束

### 5.1 Swift 6 并发合规

- 所有 `@Model` 类仅在 `@MainActor` 上访问
- `ModelContext` 不跨 Actor 传递
- 网络请求（Claude API、HealthKit）在后台 Task 执行，结果回到 `@MainActor` 更新 UI

### 5.2 隐私与数据安全

| 层级 | 保护手段 |
|------|---------|
| 应用层 | LocalAuthentication（Face ID / Touch ID / PIN） |
| 数据层 | iOS 文件系统加密（Data Protection，`NSFileProtectionComplete`） |
| 传输层 | Claude API 调用使用 HTTPS，用户 API Key 存储于 Keychain |
| 图片 | 存储于本地沙盒，不上传任何服务器 |

### 5.3 离线能力矩阵

| 功能 | 离线可用 | 说明 |
|------|---------|------|
| 健康记录 CRUD | ✅ | 完全本地 SwiftData |
| 家庭成员管理 | ✅ | 完全本地 |
| HealthKit 数据读取 | ✅ | 本地 API 调用 |
| 本地通知提醒 | ✅ | UserNotifications 框架 |
| OCR 识别 | ✅ | Vision 框架，本地推理 |
| AI 解读 | ❌ | 需要调用 Claude API |
| iCloud 同步 | ❌ | 需要网络 |

### 5.4 性能目标

| 指标 | 目标 | 测量方法 |
|------|------|---------|
| 冷启动时间 | < 2s | `XCTClockMetric` |
| 记录列表加载（10,000 条） | < 500ms | SwiftData FetchDescriptor |
| SwiftUI 列表滚动帧率 | 60fps | Instruments Time Profiler |
| 内存占用（正常使用） | < 100MB | Instruments Allocations |
| Claude API 超时阈值 | 30s | 超时后展示重试提示 |

---

## 6. 开发阶段规划

### Phase 1 — Foundation（第 1-2 周）✅ 已完成

| Issue | 内容 | 状态 |
|-------|------|------|
| AIH-10 | Xcode 项目初始化 + SwiftUI 架构 + 本地认证 | Done |
| AIH-11 | SwiftData 数据模型 + 家庭成员管理 UI | Done |
| AIH-14 | 全部 6 种健康记录类型 CRUD + 搜索筛选 | Done |

**Phase 1 验收标准：**
- [ ] 所有 P0 用户故事验收标准 100% 通过
- [ ] Unit Test 覆盖率 ≥ 80%
- [ ] 冷启动 < 2s（iPhone 12 测试）
- [ ] 无崩溃（模拟器 + 真机）

### Phase 2 — Core Health Records（第 3-4 周）

| Issue | 内容 | 关联 OQ |
|-------|------|---------|
| AIH-15 | HealthKit 集成 + 后台同步（已完成） | OQ-1 |
| 待创建 | 相机 OCR 体检报告识别（Vision 框架） | OQ-3, OQ-4 |
| 待创建 | 数据全局搜索 | — |

**关键决策待确认（OQ）：**
- OQ-1：HealthKit 刷新频率（iOS Dev 确认）
- OQ-3：图片存储上限策略（PM + iOS Dev）
- OQ-4：OCR 识别准确率不足时的降级方案（iOS Dev）

### Phase 3 — AI Intelligence（第 5-6 周）

| 内容 | 关联 OQ |
|------|---------|
| Claude API 集成 + 体检报告 AI 解读 | OQ-2 |
| 健康趋势分析图表（Swift Charts） | — |
| 就诊准备助手 | — |
| 健康数据通俗解读 + 分享 | — |

**关键决策待确认：**
- OQ-2：Claude API Key 存储方案（用户自备 vs App 内置）

### Phase 4 — Polish & Launch（第 7-8 周）

| 内容 | 关联 OQ |
|------|---------|
| 用药 / 随访本地推送提醒 | — |
| iCloud 家庭同步（可选，默认关闭） | OQ-5 |
| 健康摘要 PDF 导出 | — |
| App Store 提审准备 | — |

---

## 7. 测试策略摘要

详细测试策略见 [docs/TESTING.md](TESTING.md)。

**核心原则：**
- 测试数据禁止使用真实健康数据，全部使用 Fixture / Mock
- HealthKit 和 Claude API 依赖通过协议 Mock 隔离
- SwiftData 测试使用内存数据库（`isStoredInMemoryOnly: true`）

**测试金字塔目标：**
- Unit Tests（70%）：数据模型、业务逻辑、工具函数
- Integration Tests（20%）：跨层交互、Service 集成
- UI/E2E Tests（10%）：关键用户流程（XCUITest）

---

## 8. 已知技术风险

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| HealthKit 模拟器不可用 | Phase 2 开发效率受影响 | 协议 Mock 支持完整功能开发，真机验证 |
| Swift 6 严格并发报错 | 编译期错误增多 | 尽早启用，边写边修，避免后期大规模重构 |
| SwiftData 大数据量查询性能 | 10,000+ 条记录时可能卡顿 | FetchDescriptor 分页 + 索引优化 |
| Claude API 延迟不可控 | 用户体验受损 | 30s 超时 + 明确加载态 + 重试机制 |
| HealthKit 后台唤醒限制 | iOS 系统可能延迟/合并唤醒 | 以主动拉取为主，后台 delivery 为辅 |

---

## 9. 代码仓库

- **GitHub：** https://github.com/kydlikebtc/ai-health-vault-app
- **开发分支策略：** `main`（稳定）/ `develop`（集成）/ `feature/xxx`（功能分支）
- **CI：** GitHub Actions（macOS 15 + Xcode 16）
  - Push/PR 触发单元 + 集成测试
  - `main` 分支合并额外触发 UI 测试

---

*文档版本：1.0 | 创建者：Product Manager | 最后更新：2026-03-25*
