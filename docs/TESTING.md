# AI Health Vault iOS App — 测试策略

> **文件路径（待放置）：** `docs/TESTING.md`
> **状态：** 草稿，待 AIH-10 Xcode 项目初始化完成后集成到 repo

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
       /Integration\   ← 中量：跨层交互、API 集成 (XCTest)
      /------------\
     /  Unit Tests  \  ← 大量：业务逻辑、模型、工具函数 (XCTest)
    /--------------  \
```

| 层级          | 比例目标 | 工具                    | 速度   |
|---------------|----------|-------------------------|--------|
| Unit Tests    | 70%      | XCTest                  | < 5ms  |
| Integration   | 20%      | XCTest + TestContainers | < 500ms|
| UI/E2E Tests  | 10%      | XCUITest                | < 30s  |

---

## 3. 测试工具选型

### 3.1 主框架（Apple 原生）

| 工具         | 用途                          | 理由                                   |
|--------------|-------------------------------|----------------------------------------|
| **XCTest**   | Unit + Integration 测试        | 与 Xcode 深度集成，Swift 并发原生支持    |
| **XCUITest** | UI 自动化测试                  | 官方支持，AccessibilityIdentifier 稳定  |

### 3.2 辅助工具（按需引入）

| 工具              | 用途                  | 引入时机                     |
|-------------------|-----------------------|------------------------------|
| **Quick/Nimble**  | BDD 风格测试语法       | 如果团队更习惯 given/when/then |
| **OHHTTPStubs**   | 网络请求拦截 mock      | Claude API 集成测试 (Phase 3) |
| **SnapshotTesting**| 截图回归测试          | UI 稳定后，防止视觉回归       |

> **决策原则**：优先使用 Apple 原生工具，第三方库仅在原生工具无法满足时引入。

---

## 4. HealthKit 测试策略

HealthKit 访问需要系统授权，测试环境受限，采用分层 mock 策略：

### 4.1 协议抽象 Mock（推荐）

```swift
// 定义抽象协议，解耦真实 HealthKit 依赖
protocol HealthDataProviding {
    func fetchStepCount(date: Date) async throws -> Int
    func fetchHeartRate(startDate: Date, endDate: Date) async throws -> [HKQuantitySample]
    func requestAuthorization(types: Set<HKObjectType>) async throws -> Bool
}

// 生产实现
struct HealthKitProvider: HealthDataProviding { ... }

// 测试 Mock
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

### 5.1 内存数据库（推荐）

```swift
// 测试基类：每个测试用例使用独立内存数据库
class SwiftDataTestCase: XCTestCase {
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!

    @MainActor
    override func setUpWithError() throws {
        let schema = Schema([
            FamilyMember.self,
            HealthRecord.self,
            Medication.self
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

### 6.1 Mock Claude API Responses

```swift
// 定义 AI 服务协议
protocol AIAnalysisService {
    func analyzeHealthReport(_ imageData: Data) async throws -> HealthReportAnalysis
    func interpretSymptoms(_ symptoms: [String]) async throws -> MedicalInterpretation
}

// 测试 Mock
struct MockAIAnalysisService: AIAnalysisService {
    var mockAnalysis: HealthReportAnalysis

    func analyzeHealthReport(_ imageData: Data) async throws -> HealthReportAnalysis {
        return mockAnalysis  // 返回预定义结果，无网络请求
    }
}
```

### 6.2 AI 测试分级

| 级别         | 描述                           | 测试类型      |
|--------------|--------------------------------|---------------|
| L1 Mock      | 完全 mock，无 API 调用          | Unit Test     |
| L2 Contract  | 验证请求格式/响应解析正确性      | Integration   |
| L3 Real API  | 真实 API 调用（CI 中跳过）      | 手动/Staging  |

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
func testFamilyMemberFetchPerformance() {
    measure(metrics: [XCTClockMetric()]) {
        // 测量 SwiftData 批量查询性能
        let descriptor = FetchDescriptor<FamilyMember>()
        _ = try? modelContext.fetch(descriptor)
    }
}
```

---

## 9. CI 集成建议（GitHub Actions）

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

      - name: Build and Test (Unit + Integration)
        run: |
          xcodebuild test \
            -scheme "AIHealthVault" \
            -destination "platform=iOS Simulator,name=iPhone 16,OS=18.0" \
            -testPlan "UnitAndIntegration" \
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
      - name: UI Tests
        run: |
          xcodebuild test \
            -scheme "AIHealthVault" \
            -destination "platform=iOS Simulator,name=iPhone 16,OS=18.0" \
            -testPlan "UITests"
```

---

## 10. Phase 1 测试计划

### 10.1 家庭成员 CRUD 测试用例

```swift
class FamilyMemberCRUDTests: SwiftDataTestCase {

    // 创建
    func testCreateFamilyMember_withValidData_savesSuccessfully() async throws {
        let member = FamilyMember(name: "张三", relationship: .spouse, birthDate: Date())
        modelContext.insert(member)
        try modelContext.save()

        let members = try modelContext.fetch(FetchDescriptor<FamilyMember>())
        XCTAssertEqual(members.count, 1)
        XCTAssertEqual(members.first?.name, "张三")
    }

    // 读取
    func testFetchFamilyMembers_returnsCorrectCount() async throws {
        // Given
        for i in 1...3 {
            let member = FamilyMember(name: "成员\(i)", relationship: .child, birthDate: Date())
            modelContext.insert(member)
        }
        try modelContext.save()

        // When
        let members = try modelContext.fetch(FetchDescriptor<FamilyMember>())

        // Then
        XCTAssertEqual(members.count, 3)
    }

    // 更新
    func testUpdateFamilyMember_changesName_persistsCorrectly() async throws {
        let member = FamilyMember(name: "旧名", relationship: .self_, birthDate: Date())
        modelContext.insert(member)
        try modelContext.save()

        member.name = "新名"
        try modelContext.save()

        let updated = try modelContext.fetch(FetchDescriptor<FamilyMember>()).first
        XCTAssertEqual(updated?.name, "新名")
    }

    // 删除
    func testDeleteFamilyMember_removesFromDatabase() async throws {
        let member = FamilyMember(name: "待删除", relationship: .parent, birthDate: Date())
        modelContext.insert(member)
        try modelContext.save()

        modelContext.delete(member)
        try modelContext.save()

        let remaining = try modelContext.fetch(FetchDescriptor<FamilyMember>())
        XCTAssertTrue(remaining.isEmpty)
    }

    // 验证：必填字段
    func testCreateFamilyMember_withEmptyName_throwsValidationError() {
        // 验证数据模型约束
        XCTAssertThrowsError(try FamilyMember.validate(name: "")) { error in
            XCTAssertEqual(error as? ValidationError, .emptyName)
        }
    }
}
```

### 10.2 SwiftData 模型验证测试

```swift
class SwiftDataModelTests: SwiftDataTestCase {

    func testFamilyMemberModel_hasRequiredProperties() {
        // 验证 @Model 类属性存在且类型正确
        let member = FamilyMember(name: "测试", relationship: .spouse, birthDate: Date())
        XCTAssertNotNil(member.id)
        XCTAssertFalse(member.name.isEmpty)
        XCTAssertNotNil(member.createdAt)
    }

    func testHealthRecord_associatesCorrectlyWithMember() async throws {
        let member = FamilyMember(name: "张三", relationship: .self_, birthDate: Date())
        modelContext.insert(member)

        let record = HealthRecord(type: .bloodPressure, date: Date(), member: member)
        modelContext.insert(record)
        try modelContext.save()

        XCTAssertEqual(member.healthRecords.count, 1)
        XCTAssertEqual(record.member?.name, "张三")
    }
}
```

### 10.3 本地认证（Face ID）测试场景

```swift
// 协议抽象，使 Face ID 可 mock
protocol LocalAuthenticationProviding {
    func authenticateWithBiometrics(reason: String) async throws -> Bool
    var isBiometricsAvailable: Bool { get }
}

class LocalAuthenticationTests: XCTestCase {

    func testAuthentication_whenBiometricsAvailable_showsFaceIDPrompt() async {
        let mockAuth = MockLocalAuth(biometricsAvailable: true, authResult: true)
        let viewModel = LockScreenViewModel(authProvider: mockAuth)

        await viewModel.authenticate()

        XCTAssertTrue(viewModel.isAuthenticated)
    }

    func testAuthentication_whenBiometricsFail_showsErrorState() async {
        let mockAuth = MockLocalAuth(biometricsAvailable: true, authResult: false)
        let viewModel = LockScreenViewModel(authProvider: mockAuth)

        await viewModel.authenticate()

        XCTAssertFalse(viewModel.isAuthenticated)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testAuthentication_whenBiometricsUnavailable_showsPasscodeFallback() async {
        let mockAuth = MockLocalAuth(biometricsAvailable: false, authResult: false)
        let viewModel = LockScreenViewModel(authProvider: mockAuth)

        XCTAssertFalse(viewModel.canUseBiometrics)
        XCTAssertTrue(viewModel.shouldShowPasscodeOption)
    }
}
```

### 10.4 基础导航测试（XCUITest）

```swift
class NavigationUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--skip-authentication"]
        app.launch()
    }

    func testTabBarNavigation_allTabsAccessible() {
        // 验证 TabBar 四个主要入口均可点击
        XCTAssertTrue(app.tabBars.buttons["家庭"].exists)
        XCTAssertTrue(app.tabBars.buttons["健康"].exists)
        XCTAssertTrue(app.tabBars.buttons["AI 助手"].exists)
        XCTAssertTrue(app.tabBars.buttons["设置"].exists)
    }

    func testAddFamilyMember_completesSuccessfully() {
        app.tabBars.buttons["家庭"].tap()
        app.navigationBars.buttons["添加成员"].tap()

        let nameField = app.textFields["memberName"]
        nameField.tap()
        nameField.typeText("李四")

        app.buttons["保存"].tap()

        XCTAssertTrue(app.cells["李四"].exists)
    }

    func testFamilyMemberDetail_showsCorrectInformation() {
        // 假设已有测试数据
        app.tabBars.buttons["家庭"].tap()
        app.cells.firstMatch.tap()

        XCTAssertTrue(app.navigationBars["成员详情"].exists)
    }
}
```

---

## 11. 质量门禁（Quality Gates）

| 检查项               | 要求             | 执行时机               |
|----------------------|------------------|------------------------|
| Unit Test 覆盖率      | ≥ 80%            | PR 合并前 (CI)         |
| 所有 @Model 类有测试  | 100%             | Code Review 检查        |
| UI 关键路径覆盖       | 必须通过         | PR 合并到 main 前       |
| 性能回归              | 无超出基准 20%    | Release 前手动验证      |
| 无障碍检查            | VoiceOver 可用   | 每次 UI 变更后         |
| 编译警告              | 0 个新增警告      | CI 强制检查             |

---

## 12. 测试数据管理

```swift
// 统一的测试 Fixtures
enum TestFixtures {
    static let sampleMember = FamilyMemberFixture(
        name: "测试用户",
        relationship: .self_,
        birthDate: Calendar.current.date(from: DateComponents(year: 1990, month: 1, day: 1))!
    )

    static let sampleHealthRecord = HealthRecordFixture(
        type: .bloodPressure,
        values: ["systolic": 120, "diastolic": 80],
        date: Date()
    )

    static let sampleMedication = MedicationFixture(
        name: "阿司匹林",
        dosage: "100mg",
        frequency: .daily
    )
}
```

---

## 13. 文件结构（待 AIH-10 完成后执行）

```
AIHealthVaultTests/               # Unit + Integration Test Target
├── Models/
│   ├── FamilyMemberTests.swift
│   ├── HealthRecordTests.swift
│   └── MedicationTests.swift
├── ViewModels/
│   ├── FamilyListViewModelTests.swift
│   └── LockScreenViewModelTests.swift
├── Services/
│   ├── HealthKitServiceTests.swift
│   └── AIAnalysisServiceTests.swift
├── Mocks/
│   ├── MockHealthDataProvider.swift
│   ├── MockAIAnalysisService.swift
│   └── MockLocalAuth.swift
├── Helpers/
│   ├── SwiftDataTestCase.swift     # 基类：内存数据库
│   └── TestFixtures.swift          # 测试数据
└── AIHealthVaultTests.xctestplan

AIHealthVaultUITests/             # UI Test Target
├── Navigation/
│   └── NavigationUITests.swift
├── FamilyManagement/
│   └── FamilyMemberUITests.swift
├── Authentication/
│   └── LockScreenUITests.swift
└── AIHealthVaultUITests.xctestplan
```

---

*文档版本：1.0 | 创建者：QA Engineer | 最后更新：2026-03-25*
