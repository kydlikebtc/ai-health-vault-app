# AI Health Vault iOS App — 测试策略

---

## 1. 测试哲学与总原则

AI Health Vault 处理用户最敏感的健康数据，测试策略遵循以下原则：

- **隐私优先**：测试数据严禁使用真实健康数据，全部使用 mock/fixture
- **离线可用**：所有核心功能测试必须能在无网络环境下运行
- **真实性保障**：UI 测试覆盖完整用户流程，而非碎片化交互

---

## 2. 测试金字塔

```
          /\
         /E2E\         ← 少量：关键用户流程 (XCUITest)
        /------\
       /Integration\   ← 中量：跨层交互、SwiftData 集成 (XCTest)
      /------------\
     /  Unit Tests  \  ← 大量：业务逻辑、模型、服务 (XCTest)
    /--------------  \
```

**当前实际分布（共 509 个测试用例）：**

| 层级          | 用例数 | 比例   | 工具         |
|---------------|--------|--------|--------------|
| Unit Tests    | 469    | 92%    | XCTest       |
| Integration   | 26     | 5%     | XCTest       |
| UI/E2E Tests  | 14     | 3%     | XCUITest     |

---

## 3. 测试工具选型

### 3.1 主框架（Apple 原生）

| 工具         | 用途                          | 理由                                   |
|--------------|-------------------------------|----------------------------------------|
| **XCTest**   | Unit + Integration 测试        | 与 Xcode 深度集成，Swift 并发原生支持    |
| **XCUITest** | UI 自动化测试                  | 官方支持，AccessibilityIdentifier 稳定  |

### 3.2 辅助工具（按需引入）

| 工具              | 用途                  | 引入时机                               |
|-------------------|-----------------------|----------------------------------------|
| **Quick/Nimble**  | BDD 风格测试语法       | 如果团队更习惯 given/when/then          |
| **OHHTTPStubs**   | 网络请求拦截 mock      | 已用协议 mock 代替，暂不引入            |
| **SnapshotTesting**| 截图回归测试          | UI 稳定后，防止视觉回归                |

> **决策原则**：优先使用 Apple 原生工具，第三方库仅在原生工具无法满足时引入。
> Phase 3 AI 测试通过协议抽象 mock 代替网络拦截，避免引入额外依赖。

---

## 4. HealthKit 测试策略

HealthKit 访问需要系统授权，测试环境受限，采用分层 mock 策略：

### 4.1 协议抽象 Mock（已实施）

```swift
// 定义抽象协议，解耦真实 HealthKit 依赖
protocol HealthDataProviding {
    func fetchStepCount(date: Date) async throws -> Int
    func fetchHeartRate(startDate: Date, endDate: Date) async throws -> [HKQuantitySample]
    func requestAuthorization(types: Set<HKObjectType>) async throws -> Bool
}

// 生产实现
struct HealthKitProvider: HealthDataProviding { ... }

// 测试 Mock（HealthKitServiceTests.swift 中使用）
struct MockHealthDataProvider: HealthDataProviding {
    var stubbedStepCount: Int = 8000
    var shouldThrowError: Bool = false

    func fetchStepCount(date: Date) async throws -> Int {
        if shouldThrowError { throw HealthError.unauthorized }
        return stubbedStepCount
    }
}
```

### 4.2 测试场景矩阵

| 场景                    | 测试方式              | 说明                        |
|-------------------------|-----------------------|-----------------------------|
| 授权成功，数据正常       | MockHealthDataProvider | 主路径测试                   |
| 授权被拒绝               | MockHealthDataProvider | 错误处理路径                 |
| 数据为空                 | MockHealthDataProvider | 空状态 UI 渲染               |
| 授权成功，真实数据采集   | 真机手动测试           | TestFlight 测试阶段验证      |

---

## 5. SwiftData 测试隔离方案

### 5.1 内存数据库基类（已实施）

```swift
// AIHealthVaultTests/Helpers/SwiftDataTestCase.swift
// 每个测试用例使用独立内存数据库
class SwiftDataTestCase: XCTestCase {
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!

    @MainActor
    override func setUpWithError() throws {
        let schema = Schema([
            Member.self,
            WearableEntry.self,
            Medication.self,
            CheckupReport.self,
            MedicalHistory.self,
            DailyLog.self,
            VisitRecord.self,
            CustomReminder.self,
            DailyPlan.self,
            TermCacheItem.self,
            TrendPeriod.self,
            CachedVisitPrep.self
        ])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true  // 关键：内存数据库，测试隔离
        )
        modelContainer = try ModelContainer(for: schema, configurations: [config])
        modelContext = ModelContext(modelContainer)
    }

    override func tearDownWithError() throws {
        modelContainer = nil
        modelContext = nil
    }
}
```

### 5.2 隔离原则

- **每个测试函数**：独立 `ModelContainer`，避免测试间数据污染
- **异步操作**：使用 `async/await` + `XCTestExpectation` 处理异步 SwiftData 操作
- **并发安全**：遵循 Swift 6 严格并发规则，所有 `@Model` 操作在 `@MainActor` 上执行

---

## 6. AI 功能测试方案（Claude API）

### 6.1 Mock 策略（已实施）

Phase 3 的 AI 功能测试采用双层 mock 策略：

```swift
// MockAIService：预设响应，无 API 调用（验证输出格式）
struct MockAIService: AIService {
    var mockResponse: String = "{}"
    var shouldThrow: Bool = false

    func generateResponse(prompt: String) async throws -> String {
        if shouldThrow { throw AIError.apiKeyMissing }
        return mockResponse
    }
}

// SpyAIService（DailyHealthPlanServiceTests/AI/ 使用）：
// 捕获实际传入的 prompt 内容，验证上下文构建逻辑是否正确注入成员信息/用药数据
class SpyAIService: AIService {
    private(set) var capturedPrompts: [String] = []

    func generateResponse(prompt: String) async throws -> String {
        capturedPrompts.append(prompt)
        return mockPlanJSON
    }
}
```

> **注意**：`TermExplanationService` 在无 API Key 时自动使用 `MockAIService.termExplanationMock()`，CI 环境无需配置密钥。

### 6.2 AI 测试分级

| 级别         | 描述                           | 测试类型      | 当前实施                       |
|--------------|--------------------------------|---------------|--------------------------------|
| L1 Mock      | 完全 mock，无 API 调用          | Unit Test     | MockAIService                  |
| L2 Spy       | 捕获 prompt，验证上下文构建     | Unit Test     | SpyAIService (AIH-28)          |
| L3 Contract  | 验证请求格式/响应解析正确性      | Integration   | PromptLibraryTests             |
| L4 Real API  | 真实 API 调用（CI 中跳过）      | 手动/Staging  | 无 API Key 时自动降级 Mock      |

---

## 7. 无障碍测试清单

- [ ] 所有交互元素具有 `accessibilityIdentifier` 和 `accessibilityLabel`
- [ ] 支持 VoiceOver 导航完整用户流程
- [ ] 动态字体（Dynamic Type）从 `xSmall` 到 `xxxLarge` 无布局溢出
- [ ] 颜色对比度符合 WCAG AA 标准（最低 4.5:1）
- [ ] 不依赖颜色作为唯一信息载体
- [ ] 触摸目标最小尺寸 44×44pt

---

## 8. 性能基准

| 指标                  | 目标值          | 测量方法                    |
|-----------------------|-----------------|-----------------------------|
| 冷启动时间            | < 2 秒          | `XCTMetric` + `measure {}` |
| 首页渲染完成          | < 1 秒          | Instruments Time Profiler   |
| SwiftData 查询（1000条）| < 100ms       | XCTest measure              |
| 内存占用（正常使用）   | < 100 MB        | Instruments Allocations     |
| Claude API 响应超时   | > 30s 显示提示   | UI 测试验证                  |

```swift
// XCTest 性能基准示例
func testMemberFetchPerformance() {
    measure(metrics: [XCTClockMetric()]) {
        let descriptor = FetchDescriptor<Member>()
        _ = try? modelContext.fetch(descriptor)
    }
}
```

---

## 9. 构建与运行测试

### 9.1 XcodeGen 项目生成

测试 target 通过 `project.yml` 配置，添加新测试文件后需重新生成项目：

```bash
# 安装 XcodeGen（如未安装）
brew install xcodegen

# 在项目根目录生成 .xcodeproj
cd "/Users/kyd/AI Health Vault"
xcodegen generate
```

> **重要**：新增测试文件后必须运行 `xcodegen generate`，否则 Xcode 不会识别新文件。

### 9.2 命令行运行测试

```bash
# 运行所有单元 + 集成测试
xcodebuild test \
  -scheme "AIHealthVault" \
  -destination "platform=iOS Simulator,name=iPhone 16,OS=18.0" \
  -enableCodeCoverage YES \
  -resultBundlePath TestResults.xcresult

# 仅运行 UI 测试
xcodebuild test \
  -scheme "AIHealthVault" \
  -destination "platform=iOS Simulator,name=iPhone 16,OS=18.0" \
  -only-testing:AIHealthVaultUITests

# 运行特定测试文件（示例）
xcodebuild test \
  -scheme "AIHealthVault" \
  -destination "platform=iOS Simulator,name=iPhone 16,OS=18.0" \
  -only-testing:AIHealthVaultTests/HealthKitServiceTests

# 查看覆盖率报告
xcrun xccov view --report --json TestResults.xcresult
```

---

## 10. CI 集成（GitHub Actions）

```yaml
# .github/workflows/test.yml
name: iOS Tests

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: macos-15

    steps:
      - uses: actions/checkout@v4

      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_16.app

      - name: Generate Xcode Project
        run: xcodegen generate

      - name: Build and Test (Unit + Integration)
        run: |
          xcodebuild test \
            -scheme "AIHealthVault" \
            -destination "platform=iOS Simulator,name=iPhone 16,OS=18.0" \
            -enableCodeCoverage YES \
            -resultBundlePath TestResults.xcresult

      - name: Check Coverage
        run: |
          xcrun xccov view --report --json TestResults.xcresult | \
          python3 scripts/check_coverage.py --threshold 80

      - name: Upload Results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: test-results
          path: TestResults.xcresult

  ui-tests:
    runs-on: macos-15
    # UI 测试单独 job，避免阻塞单测快速反馈
    if: github.ref == 'refs/heads/main' || github.event_name == 'pull_request'
    steps:
      - uses: actions/checkout@v4
      - name: Generate Xcode Project
        run: xcodegen generate
      - name: UI Tests
        run: |
          xcodebuild test \
            -scheme "AIHealthVault" \
            -destination "platform=iOS Simulator,name=iPhone 16,OS=18.0" \
            -only-testing:AIHealthVaultUITests
```

---

## 11. Phase 测试覆盖详情

### 11.1 Phase 1 — 核心数据模型与认证（已完成）

**覆盖范围：** SwiftData @Model 基础 CRUD、本地认证（Face ID）、图片存储

| 测试文件                                         | 用例数 | 覆盖内容                                    |
|--------------------------------------------------|--------|---------------------------------------------|
| `Models/MemberTests.swift`                       | 14     | 成员创建/读取/更新/删除、字段验证            |
| `Models/MedicationTests.swift`                   | 9      | 药品模型字段、关联关系                       |
| `Models/MedicalHistoryTests.swift`               | 7      | 病史记录模型约束                             |
| `Services/AuthenticationServiceTests.swift`      | 9      | Face ID mock、密码回退、认证状态             |
| `Services/ImageStorageServiceTests.swift`        | 24     | 图片存储/加载/删除、沙盒路径隔离             |
| `Integration/SwiftDataIntegrationTests.swift`    | 6      | 跨模型关联、事务一致性                       |

**Phase 1 小计：69 个用例**

---

### 11.2 Phase 2 — HealthKit 集成（已完成）

**覆盖范围：** HealthKit 数据获取、可穿戴设备数据模型、授权流程

**Mock 策略：** 协议抽象 `MockHealthDataProvider`，完全离线运行，覆盖授权成功/拒绝/数据为空三条路径

| 测试文件                               | 用例数 | 覆盖内容                                        |
|----------------------------------------|--------|-------------------------------------------------|
| `Services/HealthKitServiceTests.swift` | 29     | 步数/心率/血氧读取、授权请求、错误处理、数据聚合 |
| `Models/WearableEntryTests.swift`      | 12     | WearableEntry 模型、数据类型枚举、时间范围验证   |

**Phase 2 小计：41 个用例**

---

### 11.3 Phase 3 — AI 分析功能（已完成）

**覆盖范围：** Claude API 集成、健康报告分析、就诊准备、趋势分析、术语解释

**Mock 策略：**
- `MockAIService`：预设响应，验证输出格式和状态机流转
- `SpyAIService`：捕获实际 prompt，验证上下文构建逻辑（成员信息/用药数据是否正确注入）

| 测试文件                                          | 用例数 | 覆盖内容                                       |
|---------------------------------------------------|--------|------------------------------------------------|
| `Services/AI/AIServiceTests.swift`                | 23     | API Key 验证、请求格式、响应解析、错误处理      |
| `Services/AI/PromptLibraryTests.swift`            | 31     | prompt 模板正确性、参数替换、边界条件           |
| `Services/AI/DailyHealthPlanServiceTests.swift`   | 15     | 上下文构建验证（SpyAIService）、成员/用药注入   |
| `Services/AI/ReportAnalysisViewModelTests.swift`  | 23     | 报告分析 ViewModel 状态机、加载/成功/错误状态   |
| `Services/AI/TermExplanationServiceTests.swift`   | 12     | 术语缓存命中/写入、空输入守卫、AI 回落          |
| `Services/DailyHealthPlanServiceTests.swift`      | 13     | 健康计划输出格式验证、日期边界                  |
| `Services/VisitPreparationViewModelTests.swift`   | 20     | 就诊准备生成、CachedVisitPrep 缓存逻辑          |
| `Models/TrendPeriodTests.swift`                   | 17     | 趋势周期模型、聚合计算、时间跨度                |
| `Models/VisitRecordTests.swift`                   | 15     | 就诊记录字段、AI 摘要关联                       |
| `Models/CheckupReportTests.swift`                 | 8      | 体检报告模型、图片关联                          |
| `Models/TermCacheItemTests.swift`                 | 15     | 缓存条目、hitCount/lastAccessedAt、trim 归一化 |
| `Integration/TrendDataIntegrationTests.swift`     | 20     | 趋势数据跨模型查询、聚合一致性                  |

**Phase 3 小计：212 个用例**

> **注意**：`DailyHealthPlanServiceTests` 在两个路径各有一个文件，类名不同，互补：
> - `Services/`：`DailyPlanServiceOutputTests` — 验证输出格式
> - `Services/AI/`：`DailyHealthPlanServiceTests` — 验证上下文构建（使用 SpyAIService）

---

### 11.4 Phase 4 — 通知、导出与高级功能（已完成）

**覆盖范围：** 用药提醒、随访通知、PDF 导出、自定义提醒、全局搜索、AI 用量管理

| 测试文件                                            | 用例数 | 覆盖内容                                        |
|-----------------------------------------------------|--------|-------------------------------------------------|
| `Services/MedicationNotificationServiceTests.swift` | 28     | 通知调度、重复规则、取消/重新调度、权限处理      |
| `Services/FollowUpNotificationServiceTests.swift`   | 30     | 随访提醒、提前天数配置、多成员通知              |
| `Services/PDFExportServiceTests.swift`              | 22     | PDF 生成、健康数据嵌入、多页布局、文件命名       |
| `Services/GlobalSearchTests.swift`                  | 24     | 跨模型搜索、关键词匹配、空结果处理、搜索排序     |
| `Services/AISettingsManagerTests.swift`             | 20     | Token 累计、月度重置、费用估算、API Key 掩码/安全性 |
| `Models/CustomReminderTests.swift`                  | 17     | 自定义提醒模型、重复类型、有效期                |
| `Models/DailyPlanTests.swift`                       | 22     | 每日计划模型、完成状态、关联成员                |
| `Models/DailyLogTests.swift`                        | 10     | 每日日志字段、时间戳                            |

**Phase 4 小计：173 个用例**

---

### 11.5 UI 测试（持续补充中）

| 测试文件                                           | 用例数 | 覆盖内容                                       |
|----------------------------------------------------|--------|------------------------------------------------|
| `AIHealthVaultUITests/AIHealthVaultUITests.swift`  | 1      | App 启动验证                                   |
| `AIHealthVaultUITests/HealthRecordsUITests.swift`  | 13     | Tab 导航、空状态展示、相机权限、AI UI 流程      |

**UI 小计：14 个用例**

---

## 12. 质量门禁（Quality Gates）

| 检查项               | 要求             | 执行时机               |
|----------------------|------------------|------------------------|
| Unit Test 覆盖率      | ≥ 80%            | PR 合并前 (CI)         |
| 所有 @Model 类有测试  | 100%             | Code Review 检查        |
| UI 关键路径覆盖       | 必须通过         | PR 合并到 main 前       |
| 性能回归              | 无超出基准 20%    | Release 前手动验证      |
| 无障碍检查            | VoiceOver 可用   | 每次 UI 变更后         |
| 编译警告              | 0 个新增警告      | CI 强制检查             |

---

## 13. 测试数据管理

```swift
// AIHealthVaultTests/Helpers/TestFixtures.swift
// 统一测试数据工厂，避免各测试文件重复定义
enum TestFixtures {
    static func makeMember(name: String = "测试用户") -> Member { ... }
    static func makeWearableEntry(date: Date = .now) -> WearableEntry { ... }
    static func makeMedication(name: String = "阿司匹林") -> Medication { ... }
    static func makeCheckupReport() -> CheckupReport { ... }
    static func makeVisitRecord() -> VisitRecord { ... }
    static func makeCustomReminder() -> CustomReminder { ... }
    static func makeDailyPlan() -> DailyPlan { ... }
    static func makeTermCacheItem(term: String = "血糖") -> TermCacheItem { ... }
}
```

---

## 14. 实际文件结构

```
AIHealthVaultTests/               # Unit + Integration Test Target
├── Helpers/
│   ├── SwiftDataTestCase.swift   # 内存数据库基类（含全量 @Model schema）
│   └── TestFixtures.swift        # 统一测试数据工厂
├── Models/                       # @Model 类单元测试（11 个文件，146 个用例）
│   ├── MemberTests.swift
│   ├── WearableEntryTests.swift
│   ├── MedicationTests.swift
│   ├── CheckupReportTests.swift
│   ├── MedicalHistoryTests.swift
│   ├── DailyLogTests.swift
│   ├── VisitRecordTests.swift
│   ├── CustomReminderTests.swift
│   ├── DailyPlanTests.swift
│   ├── TermCacheItemTests.swift
│   └── TrendPeriodTests.swift
├── Integration/                  # 跨模型集成测试（2 个文件，26 个用例）
│   ├── SwiftDataIntegrationTests.swift
│   └── TrendDataIntegrationTests.swift
└── Services/                     # 服务层单元测试（10 个文件 + AI 子目录）
    ├── AuthenticationServiceTests.swift
    ├── HealthKitServiceTests.swift
    ├── ImageStorageServiceTests.swift
    ├── MedicationNotificationServiceTests.swift
    ├── FollowUpNotificationServiceTests.swift
    ├── PDFExportServiceTests.swift
    ├── GlobalSearchTests.swift
    ├── AISettingsManagerTests.swift
    ├── VisitPreparationViewModelTests.swift
    ├── DailyHealthPlanServiceTests.swift  # 输出格式验证（DailyPlanServiceOutputTests）
    └── AI/                               # AI 服务专项测试（5 个文件，104 个用例）
        ├── AIServiceTests.swift
        ├── PromptLibraryTests.swift
        ├── DailyHealthPlanServiceTests.swift  # 上下文构建验证（SpyAIService）
        ├── ReportAnalysisViewModelTests.swift
        └── TermExplanationServiceTests.swift

AIHealthVaultUITests/             # UI Test Target（2 个文件，14 个用例）
├── AIHealthVaultUITests.swift    # 启动测试
└── HealthRecordsUITests.swift    # Tab 导航/空状态/相机权限/AI UI
```

---

*文档版本：2.0 | 维护者：QA Engineer | 最后更新：2026-03-26*
