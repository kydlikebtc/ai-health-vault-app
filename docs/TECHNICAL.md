# AI Health Vault — 技术架构文档

**版本：** v2.0
**日期：** 2026-03-26
**作者：** iOS Developer Agent
**面向读者：** iOS 工程师、架构师、技术评审者

---

## 1. 产品概述（技术视角）

AI Health Vault 是一款以**本地数据为核心**的 iOS 家庭健康档案管理应用。与传统健康 App 的云端同步模式不同，本应用优先保障用户数据主权：所有健康数据默认存储在设备本地，AI 分析能力作为可选增强层叠加，而非系统核心依赖。

**关键技术决策：**

| 决策 | 选型 | 理由 |
|------|------|------|
| 数据层 | SwiftData | iOS 17 原生持久化，与 SwiftUI 深度集成，无第三方依赖 |
| UI 框架 | SwiftUI | 声明式 UI，支持 Preview，与 SwiftData 配合流畅 |
| 并发模型 | Swift 6 strict concurrency | 避免数据竞争，actor 隔离服务，@MainActor 保护 UI 状态 |
| 认证 | LocalAuthentication + iOS Data Protection | 生物认证开发成本低，iOS 文件加密零配置 |
| 健康数据 | HealthKit | Phase 2 完成，协议抽象以支持 Mock 测试 |
| AI 能力 | Claude API（claude-sonnet-4-6） | Phase 3 完成，流式输出 + Token 计量 |
| 图片 OCR | Vision 框架 | 本地推理，无隐私泄露风险 |
| 云同步 | CloudKit（可选） | Phase 4 规划，默认关闭，用户主动开启 |

---

## 2. 系统架构

### 2.1 整体架构分层

```
┌─────────────────────────────────────────────────────────────────────┐
│                        UI Layer (SwiftUI)                           │
│  Family  Records  AI助手  每日计划  趋势  随访  导出  设置            │
└────────────────────────────┬────────────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────────────┐
│                      ViewModel / Service Layer                      │
│   @Observable / @StateObject / actor（Swift 6 strict concurrency）  │
└──────────┬────────────────┬──────────────────┬──────────────────────┘
           │                │                  │
┌──────────▼──┐   ┌─────────▼──────┐   ┌──────▼──────────────────────┐
│  SwiftData  │   │  Local Services│   │  External APIs              │
│  (Local DB) │   │  HealthKit     │   │  Claude API（Phase 3 已完成）│
│  12 个模型  │   │  Auth          │   │  CloudKit（Phase 4 规划中）  │
│             │   │  Notification  │   │                             │
│             │   │  ImageStorage  │   │                             │
│             │   │  PDFExport     │   │                             │
└─────────────┘   └────────────────┘   └─────────────────────────────┘
```

### 2.2 项目目录结构

```
AIHealthVault/
├── App/
│   ├── AIHealthVaultApp.swift       # App 入口，ModelContainer + 通知 Delegate + HealthKit 授权
│   ├── ContentView.swift            # TabView 主导航（4 个 Tab）
│   └── LockScreenView.swift         # 认证锁屏界面
├── Core/
│   ├── Models/                      # SwiftData @Model 定义（共 10 个独立模型文件）
│   │   ├── Family.swift             # Family 聚合根
│   │   ├── Member.swift             # 家庭成员
│   │   ├── MedicalHistory.swift     # 既往病史
│   │   ├── Medication.swift         # 用药记录
│   │   ├── CheckupReport.swift      # 体检报告（含 CheckupItem 子模型）
│   │   ├── VisitRecord.swift        # 就医记录
│   │   ├── WearableEntry.swift      # 可穿戴数据（含 HealthKit 同步）
│   │   ├── DailyLog.swift           # 日常追踪
│   │   ├── CustomReminder.swift     # 自定义提醒（用户手动添加）
│   │   ├── DailyPlan.swift          # 每日健康计划（AI 生成，本地缓存）
│   │   ├── TermCacheItem.swift      # 医学术语解释缓存（减少重复 AI 调用）
│   │   └── MockData.swift           # Preview 用 Mock 数据
│   ├── Services/
│   │   ├── AuthenticationService.swift          # Face ID / PIN 认证（@Observable，单例）
│   │   ├── HealthKitService.swift               # HealthKit 协议定义 + 辅助类型
│   │   ├── HealthKitServiceImpl.swift           # 真实 HealthKit 实现（@MainActor）
│   │   ├── MockHealthKitService.swift           # 测试 Mock 实现
│   │   ├── ImageStorageService.swift            # 体检图片存储 + 缩略图 + OCR（actor）
│   │   ├── MedicationNotificationService.swift  # 用药提醒通知服务（actor）
│   │   ├── FollowUpNotificationService.swift    # 随访提醒通知服务（actor）
│   │   ├── PDFExportService.swift               # 健康报告 PDF 导出（@MainActor）
│   │   └── AI/
│   │       ├── AIService.swift                  # AI 服务协议（Sendable + async/await）
│   │       ├── ClaudeService.swift              # Claude API 实现（actor，流式输出）
│   │       ├── MockAIService.swift              # AI 测试 Mock 实现
│   │       ├── AISettingsManager.swift          # AI 功能开关 + Token 计量（@Observable）
│   │       ├── KeychainService.swift            # Keychain 安全存储（API Key）
│   │       ├── DailyHealthPlanService.swift     # 每日健康计划生成（actor）
│   │       ├── TermExplanationService.swift     # 术语解释 + SwiftData 缓存（@MainActor）
│   │       └── PromptLibrary.swift              # 医疗场景提示词集中管理
│   └── Utils/
│       └── DateExtensions.swift
├── Features/
│   ├── Family/
│   │   ├── FamilyListView.swift
│   │   ├── MemberDetailView.swift
│   │   └── AddEditMemberView.swift
│   ├── Records/
│   │   ├── RecordsView.swift                    # 记录主列表（含筛选）
│   │   ├── CheckupViews.swift                   # 体检记录 CRUD
│   │   ├── CheckupImageViews.swift              # 体检报告图片管理 + Vision OCR
│   │   ├── MedicationViews.swift                # 用药记录 CRUD
│   │   ├── VisitViews.swift                     # 就医记录 CRUD
│   │   ├── DailyLogViews.swift                  # 日常追踪 CRUD
│   │   ├── MedicalHistoryViews.swift            # 既往病史 CRUD
│   │   ├── WearableViews.swift                  # 可穿戴数据展示
│   │   ├── GlobalSearchView.swift               # 跨模型全局搜索（AIH-28）
│   │   ├── TermLookupView.swift                 # 医学术语通俗解读（AI + 本地缓存）
│   │   └── SharedRecordComponents.swift         # 公用 UI 组件
│   ├── AI/
│   │   └── AIView.swift                         # AI 功能主入口
│   ├── DailyPlan/
│   │   └── DailyPlanView.swift                  # 每日健康计划（AI 生成 + 打卡）
│   ├── ReportAnalysis/
│   │   └── ReportAnalysisView.swift             # 体检报告 AI 解读
│   ├── Trends/
│   │   ├── HealthTrendView.swift                # 健康趋势分析（Swift Charts）
│   │   └── TrendChartComponents.swift           # 趋势图表组件
│   ├── Visit/
│   │   ├── FollowUpCalendarView.swift           # 随访日历
│   │   └── VisitPreparationView.swift           # 就诊准备 AI 助手（含 CachedVisitPrep 模型）
│   ├── Export/
│   │   └── HealthExportView.swift               # 健康报告 PDF 导出 UI
│   └── Settings/
│       ├── SettingsView.swift                   # 设置主页
│       └── AISettingsView.swift                 # AI 设置（API Key + Token 用量）
└── Resources/
    └── Assets.xcassets
```

> **注意：** `CachedVisitPrep`（就诊准备缓存模型）定义在 `VisitPreparationView.swift` 末部，而非独立模型文件。后续重构时建议迁移至 `Core/Models/`。

---

## 3. 核心数据模型

### 3.1 数据模型关系图

```
Family
  └── [Member]              (一对多，@Relationship)
        ├── [MedicalHistory]
        ├── [Medication]
        ├── [CheckupReport]
        │     └── [CheckupItem]   (体检指标条目，内嵌)
        ├── [VisitRecord]
        ├── [WearableEntry]       (含 hkSourceId 用于 HealthKit 去重)
        ├── [DailyLog]
        ├── [CustomReminder]      (用户手动添加的提醒事项)
        └── [DailyPlan]           (AI 生成的每日健康计划，按日期索引)

独立模型（无关联关系）：
  TermCacheItem              (术语解释缓存，按 term 唯一索引)
  CachedVisitPrep            (就诊准备 AI 结果缓存)
```

### 3.2 ModelContainer 配置（实际代码）

```swift
// AIHealthVaultApp.swift — 实际 Schema 列表
let schema = Schema([
    Family.self,
    Member.self,
    MedicalHistory.self,
    Medication.self,
    CheckupReport.self,
    VisitRecord.self,
    WearableEntry.self,
    DailyLog.self,
    TermCacheItem.self,
    CachedVisitPrep.self,
    CustomReminder.self,
    DailyPlan.self,
])
let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
// 注：CloudKit 同步尚未启用（Phase 4），cloudKitDatabase 保持默认 .none
```

**测试环境：** 使用 `isStoredInMemoryOnly: true`，每个测试用例独立容器，无数据污染。

### 3.3 WearableEntry 设计要点

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

**增量同步策略：** 使用 `HKAnchoredObjectQuery` 获取增量数据，锚点以 `UserDefaults` 持久化（Key 格式：`hk_anchor_<memberId>_<dataType>`）。同步时先按 `hkSourceId` 去重，避免重复写入。

### 3.4 DailyPlan 设计要点

```swift
@Model
final class DailyPlan {
    @Attribute(.unique) var id: UUID
    var planDate: Date             // 以当天 00:00:00 为键
    var content: String            // AI 生成内容（Markdown 格式）
    var completedActions: [String] // 已打卡行动项 ID 列表
    var generatedAt: Date
    var member: Member?
}
```

**缓存策略：** 每位成员每日至多生成一次，已有计划则展示缓存，用户可手动触发重新生成。

### 3.5 TermCacheItem 设计要点

```swift
@Model
final class TermCacheItem {
    @Attribute(.unique) var term: String   // 查询键（唯一）
    var explanation: String
    var language: String                   // "zh" / "en"
    var hitCount: Int                      // 命中次数（LRU 淘汰参考）
    var createdAt: Date
    var lastAccessedAt: Date
}
```

**淘汰策略：** 当前未实现自动淘汰，`hitCount` 和 `lastAccessedAt` 为未来 LRU 清理预留。

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
- `AuthenticationService` 以 `@Observable` + 单例形式注入

### 4.2 HealthKit 服务（协议隔离）

采用协议抽象隔离真实 HealthKit：

```swift
protocol HealthKitServiceProtocol: AnyObject {
    var isAvailable: Bool { get }              // 模拟器返回 false
    var authorizationStatus: HealthKitAuthStatus { get }
    var isSyncing: Bool { get }
    var lastSyncDate: Date? { get }

    func requestAuthorization() async throws
    func fetchTodaySummary() async throws -> HealthKitTodaySummary
    @discardableResult
    func syncToSwiftData(member: Member, context: ModelContext) async throws -> Int
    func enableBackgroundDelivery(onNewData: @escaping @Sendable () -> Void) async throws
}
```

**读取的 HealthKit 数据类型：**
- `HKQuantityType(.stepCount)` — 步数
- `HKQuantityType(.heartRate)` — 心率
- `HKCategoryType(.sleepAnalysis)` — 睡眠分析
- `HKQuantityType(.bodyMass)` — 体重
- `HKCorrelationType(.bloodPressure)` — 血压（收缩压 + 舒张压）
- `HKQuantityType(.oxygenSaturation)` — 血氧

**后台同步机制：**
- `App 启动时` 主动拉取 `HealthKitTodaySummary`（轻量级，不写 SwiftData）
- `enableBackgroundDelivery` 注册 `HKObserverQuery`，有新数据写入时回调
- `syncToSwiftData` 使用 `HKAnchoredObjectQuery` 增量同步，返回新增条目数

**今日摘要并发优化：** 使用 `async let` 并发抓取 6 项指标，整体延迟约等于最慢单项：

```swift
async let steps     = fetchTodaySteps()
async let heartRate = fetchLatestHeartRate()
async let sleep     = fetchLastNightSleep()
// ... 其余 3 项
let (s, hr, sl, w, bp, ox) = try await (steps, heartRate, sleep, weight, bp, oxygen)
```

### 4.3 AI 服务架构（Phase 3 已完成）

#### 4.3.1 服务协议

```swift
protocol AIService: AnyObject, Sendable {
    var isConfigured: Bool { get }

    // 完整响应（等待全文）
    func sendMessage(_ messages: [AIMessage], systemPrompt: String?) async throws
        -> (content: String, usage: TokenUsage)

    // 流式响应（逐 token 返回，用于长文本生成）
    func streamMessage(_ messages: [AIMessage], systemPrompt: String?)
        -> AsyncThrowingStream<String, Error>
}
```

#### 4.3.2 ClaudeService 实现要点

```swift
actor ClaudeService: AIService {
    // 使用模型：claude-sonnet-4-6
    // 最大 Token：4096
    // 限流：令牌桶，每分钟最多 60 次请求
    // 流式响应：解析 SSE 格式（"data: {...}" 逐行解析）
    // 错误码映射：401 → .invalidAPIKey, 429 → .rateLimited, 413 → .contextTooLong
}
```

#### 4.3.3 API Key 管理

```
用户在 AISettingsView 输入 API Key
  → KeychainService.save(_:for:)
  → kSecClassGenericPassword（kSecAttrAccessibleWhenUnlockedThisDeviceOnly）
  → AISettingsManager.isAPIKeyConfigured 更新
```

API Key 仅存于 Keychain，从不写入 UserDefaults 或 SwiftData。

#### 4.3.4 服务选择策略

```swift
// 全局服务路由（各使用方的模式）
let aiService: any AIService =
    AISettingsManager.shared.isAPIKeyConfigured && AISettingsManager.shared.isAIEnabled
    ? ClaudeService.shared
    : MockAIService.xxx()   // 根据场景选择对应 Mock
```

#### 4.3.5 Token 计量

`AISettingsManager` 记录每月 Input/Output Token 用量，基于 claude-sonnet-4-6 定价预估费用：
- Input: $3.00 / 1M tokens
- Output: $15.00 / 1M tokens
- 每月初自动重置，数据持久化于 UserDefaults

#### 4.3.6 提示词管理（PromptLibrary）

所有医疗场景提示词集中在 `PromptLibrary` 枚举，通过 `PromptTemplate` 协议约束：

| 场景 | 类型 | 输出格式 |
|------|------|---------|
| 体检报告解读 | `ReportAnalysis` | Markdown（正常/需关注/建议） |
| 就诊准备 | `VisitPreparation` | Markdown（准备清单） |
| 每日健康计划 | `DailyHealthPlan` | Markdown（行动项列表） |
| 术语解释 | `TermExplanation` | 纯文本（通俗解释） |

### 4.4 图片存储与 OCR（ImageStorageService）

```swift
actor ImageStorageService {
    // 存储路径：Documents/CheckupImages/<reportId>/<uuid>.jpg
    // 缩略图：Documents/CheckupImages/<reportId>/<uuid>_thumb.jpg
    // JPEG 质量：原图 0.85，缩略图 0.70
    // 缩略图尺寸：240×320 pt

    nonisolated func loadImage(at path: String) -> UIImage?
    // 标记 nonisolated：纯磁盘读取，允许多图并发加载
}
```

**OCR 实现：** 使用 `Vision.VNRecognizeTextRequest`，本地推理，识别语言自动检测（中英文），结果结构化提取后传入 AI 进行解读。

### 4.5 通知服务

#### 用药提醒（MedicationNotificationService）

```swift
actor MedicationNotificationService {
    // 通知 ID 格式：med_<medicationUUID>_<slot>
    // 提醒时段：早 08:00 / 中 12:00 / 晚 20:00
    // 通知类别：MEDICATION_REMINDER（含"已服用"交互操作）
    // "已服用" 响应：AppNotificationDelegate 在 App 前台处理
}
```

通知类别在 `AIHealthVaultApp.init()` 中注册，确保应用生命周期内始终生效。

#### 随访提醒（FollowUpNotificationService）

```swift
actor FollowUpNotificationService {
    // 提前 1 天在 09:00 触发本地通知
    // 通知 ID 格式：follow_up_<visitUUID>
    // 删除就诊记录时自动取消对应通知
}
```

### 4.6 PDF 导出（PDFExportService）

```swift
@MainActor
final class PDFExportService {
    // 页面规格：A4 @ 72 dpi（595.2 × 841.8 pt）
    // 渲染器：UIGraphicsPDFRenderer
    // 导出内容：封面 + 成员档案 + 各类健康记录（按时间范围筛选）
    // 关键设计：Swift Charts 图表使用 ImageRenderer 预渲染为 UIImage，
    //           避免与 UIGraphicsPDFRenderer 的 Core Graphics 上下文冲突
}
```

导出的时间范围（`ExportTimeRange`）：近 3 个月 / 近 6 个月 / 近 1 年 / 全部。

---

## 5. 关键技术约束

### 5.1 Swift 6 并发合规（实际使用模式）

**actor 隔离（适合有状态的后台服务）：**
- `ClaudeService` — API 调用 + 限流状态
- `DailyHealthPlanService` — 计划生成
- `ImageStorageService` — 磁盘读写（纯读方法标记 `nonisolated`，允许并发）
- `MedicationNotificationService` — 通知调度
- `FollowUpNotificationService` — 通知调度

**@MainActor（适合 UI 绑定服务）：**
- `HealthKitService` — `@Published` 属性驱动 UI
- `AISettingsManager` — `@Observable`，Token 计量 UI 联动
- `TermExplanationService` — 访问 `ModelContext`（SwiftData 要求 Main Actor）
- `PDFExportService` — `UIGraphicsPDFRenderer` + `ImageRenderer` 要求主线程

**nonisolated 混合优化：**

```swift
// ImageStorageService：纯磁盘读取不需要 actor 隔离
nonisolated func loadImage(at path: String) -> UIImage? {
    UIImage(contentsOfFile: path)
}
```

**规则：**
- `@Model` 类仅在 `@MainActor` 上访问
- `ModelContext` 不跨 Actor 传递
- 网络请求在后台 Task 执行，结果回到 `@MainActor` 更新 UI

### 5.2 隐私与数据安全

| 层级 | 保护手段 |
|------|---------|
| 应用层 | LocalAuthentication（Face ID / Touch ID / PIN） |
| 数据层 | iOS 文件系统加密（Data Protection，`NSFileProtectionComplete`） |
| 传输层 | Claude API 调用使用 HTTPS，API Key 存储于 Keychain |
| 图片 | 存储于本地沙盒，不上传任何服务器 |
| AI 数据传输 | 只传结构化数据（指标名称+数值），不传图片，不传身份信息 |

### 5.3 离线能力矩阵

| 功能 | 离线可用 | 说明 |
|------|---------|------|
| 健康记录 CRUD | ✅ | 完全本地 SwiftData |
| 家庭成员管理 | ✅ | 完全本地 |
| HealthKit 数据读取 | ✅ | 本地 API 调用 |
| 本地通知提醒 | ✅ | UserNotifications 框架 |
| OCR 识别 | ✅ | Vision 框架，本地推理 |
| 健康趋势图表 | ✅ | 本地 SwiftData 数据 |
| AI 术语解释（已缓存） | ✅ | TermCacheItem 本地命中 |
| AI 解读 / 计划生成 | ❌ | 需要调用 Claude API |
| iCloud 同步 | ❌ | Phase 4，尚未实现 |

### 5.4 性能目标

| 指标 | 目标 | 测量方法 |
|------|------|---------|
| 冷启动时间 | < 2s | `XCTClockMetric` |
| 记录列表加载（10,000 条） | < 500ms | SwiftData FetchDescriptor |
| SwiftUI 列表滚动帧率 | 60fps | Instruments Time Profiler |
| 内存占用（正常使用） | < 100MB | Instruments Allocations |
| Claude API 超时阈值 | 30s | 超时后展示重试提示 |
| HealthKit 今日摘要抓取 | < 500ms | 6 项并发 async let |

**已实施的性能优化：**
- `DateFormatter` 实例缓存（避免列表滚动时重复创建）
- `ImageStorageService.loadImage` 标记 `nonisolated`（多图并发加载）
- 趋势视图数据聚合与日历视图数据聚合分离（减少重复计算）
- AI 流式输出移除逐 token 滚动动画（减少渲染压力）

---

## 6. 开发阶段规划

### Phase 1 — Foundation ✅ 已完成

| Issue | 内容 | 状态 |
|-------|------|------|
| AIH-10 | Xcode 项目初始化 + SwiftUI 架构 + 本地认证 | Done |
| AIH-11 | SwiftData 数据模型 + 家庭成员管理 UI | Done |
| AIH-14 | 全部 6 种健康记录类型 CRUD + 搜索筛选 | Done |

### Phase 2 — Core Health Records ✅ 已完成

| Issue | 内容 | 状态 |
|-------|------|------|
| AIH-15 | HealthKit 集成 + HKAnchoredObjectQuery 增量同步 | Done |
| AIH-28 | 全局健康记录搜索（跨模型） | Done |
| — | 相机 OCR 体检报告识别（Vision + ImageStorageService） | Done |

**实际实现细节：**
- 使用 `HKAnchoredObjectQuery` 替代全量拉取，锚点持久化至 UserDefaults
- `HealthKitTodaySummary` 使用 `async let` 并发抓取 6 类指标
- 模拟器自动降级（`isAvailable == false`），所有 HealthKit 调用为空操作

### Phase 3 — AI Intelligence ✅ 已完成

| 内容 | 状态 |
|------|------|
| Claude API 集成（ClaudeService，流式输出 + 令牌桶限流） | Done |
| API Key Keychain 安全存储 + AISettingsManager Token 计量 | Done |
| 体检报告 AI 解读（ReportAnalysisView + PromptLibrary.ReportAnalysis） | Done |
| 健康趋势图表（HealthTrendView + Swift Charts） | Done |
| 就诊准备助手（VisitPreparationView + CachedVisitPrep） | Done |
| 医学术语通俗解读（TermExplanationService + TermCacheItem 缓存） | Done |
| 每日健康计划生成（DailyHealthPlanService + DailyPlan 本地缓存） | Done（AIH-27） |

**Claude API 数据流：**
```
用户触发 AI 功能
  → 检查 AISettingsManager.isAPIKeyConfigured
  → 从 KeychainService 读取 API Key
  → ClaudeService 令牌桶限流检查（60次/分钟）
  → POST https://api.anthropic.com/v1/messages（HTTPS）
  → 流式：SSE 逐行解析 → AsyncThrowingStream<String>
  → 完整：JSON 解码 ClaudeResponse
  → AISettingsManager.recordUsage(usage) 更新 Token 计量
  → 结果写入 SwiftData 缓存（如适用）
```

### Phase 4 — Polish & Launch 🔄 进行中

| 内容 | 状态 |
|------|------|
| 用药提醒（MedicationNotificationService，3 时段 + "已服用"交互） | Done（AIH-25） |
| 随访日历提醒（FollowUpNotificationService，提前 1 天通知） | Done（AIH-25） |
| 健康摘要 PDF 导出（PDFExportService，A4 多页，Swift Charts 预渲染） | Done |
| iCloud 家庭同步（CloudKit，默认关闭） | 待实现 |
| App Store 提审准备 | 待实现 |

---

## 7. 测试策略摘要

详细测试策略见 [docs/TESTING.md](TESTING.md)。

**核心原则：**
- 测试数据禁止使用真实健康数据，全部使用 Fixture / Mock
- HealthKit 依赖通过 `HealthKitServiceProtocol` Mock 隔离
- Claude API 依赖通过 `AIService` 协议 Mock 隔离（`MockAIService`）
- SwiftData 测试使用内存数据库（`ModelConfiguration(isStoredInMemoryOnly: true)`）

**测试金字塔目标：**
- Unit Tests（70%）：数据模型、业务逻辑、工具函数
- Integration Tests（20%）：跨层交互、Service 集成
- UI/E2E Tests（10%）：关键用户流程（XCUITest）

---

## 8. 已知技术风险

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| HealthKit 模拟器不可用 | Phase 2 开发效率受影响 | `isAvailable` 检查 + `MockHealthKitService` 全功能 Mock |
| Swift 6 严格并发报错 | 编译期错误增多 | 已全面启用，`actor` + `@MainActor` + `nonisolated` 三层模式 |
| SwiftData 大数据量查询性能 | 10,000+ 条记录时可能卡顿 | FetchDescriptor 分页 + `sortBy` 索引优化 |
| Claude API 延迟不可控 | 用户体验受损 | 30s 超时 + 流式输出减少感知延迟 + 重试提示 |
| HealthKit 后台唤醒限制 | iOS 系统可能延迟/合并唤醒 | 以 App 激活主动拉取为主，后台 delivery 为辅 |
| PDF 渲染与 Swift Charts 上下文冲突 | PDF 图表内容异常 | `ImageRenderer` 预渲染图表为 `UIImage`，再嵌入 PDF |
| `CachedVisitPrep` 定义位置不规范 | 代码可维护性降低 | 建议迁移至 `Core/Models/` 独立文件 |

---

## 9. 代码仓库

- **GitHub：** https://github.com/kydlikebtc/ai-health-vault-app
- **开发分支策略：** `main`（稳定）/ `develop`（集成）/ `feature/xxx`（功能分支）
- **CI：** GitHub Actions（macOS 15 + Xcode 16）
  - Push/PR 触发单元 + 集成测试
  - `main` 分支合并额外触发 UI 测试

---

*文档版本：2.0 | 更新者：iOS Developer Agent | 最后更新：2026-03-26*
