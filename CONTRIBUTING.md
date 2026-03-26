# 贡献指南 / Contributing Guide

感谢你对 AI Health Vault 的关注！本文档说明如何搭建开发环境、提交代码以及参与项目。

---

## 开发环境要求 / Requirements

| 工具 | 版本要求 | 安装方式 |
|------|---------|---------|
| macOS | 15.0+ (Sequoia) | — |
| Xcode | 16.0+ | App Store |
| XcodeGen | 任意版本 | `brew install xcodegen` |
| SwiftLint（可选）| 任意版本 | `brew install swiftlint` |

---

## 构建步骤 / Build Setup

本项目使用 **XcodeGen** 管理 Xcode 项目文件（`.xcodeproj` 不纳入版本控制）。

```bash
# 1. Fork 并 Clone 仓库
git clone https://github.com/<your-username>/ai-health-vault-app.git
cd ai-health-vault-app

# 2. 生成 Xcode 项目（每次 pull 后如有 project.yml 变更，需重新生成）
xcodegen generate

# 3. 打开项目
open AIHealthVault.xcodeproj

# 4. 选择 AIHealthVault target 和模拟器，Command+R 运行
```

> **注意：** 每次拉取最新代码后，若 `project.yml` 有变更，请重新运行 `xcodegen generate`。

---

## 代码规范 / Code Style

### Swift 版本
- 使用 **Swift 6** Strict Concurrency，确保编译器静态并发安全
- 所有 UI 状态操作标注 `@MainActor`
- Service 层使用 `actor` 隔离共享状态

### 不可变性原则
```swift
// 不推荐：直接修改对象
func updateMember(_ member: Member, name: String) {
    member.name = name  // 对 SwiftData @Model 的直接修改需在 @MainActor 内
}

// 推荐：在正确隔离上下文中操作
@MainActor
func updateMemberName(_ member: Member, name: String) {
    member.name = name
}
```

### 日志规范
```swift
import os
// 文件级私有 logger，PHI 数据使用 .private
private let logger = Logger(subsystem: "com.aihealthvault.app", category: "RecordsView")
logger.debug("Loaded \(records.count) records for member \(member.name, privacy: .private)")
```

- **不得**在提交的代码中留有 `print()` 语句
- 使用 `os.Logger` 替代所有调试输出

### 文件大小
- 单文件建议不超过 **400 行**，最大不超过 **800 行**
- 按 Feature/Domain 组织文件，避免按类型归类

---

## 测试要求 / Testing

- 单元测试覆盖率要求 **≥ 80%**
- 所有新功能必须附带对应的 XCTest 测试
- 运行测试：`Command+U`（Xcode）或 `xcodebuild test -scheme AIHealthVault -destination 'platform=iOS Simulator,name=iPhone 16'`

详见 [docs/TESTING.md](docs/TESTING.md)。

---

## PR 流程 / Pull Request Workflow

### 1. 创建分支
```bash
# Feature
git checkout -b feat/your-feature-name

# Bug Fix
git checkout -b fix/issue-description

# Documentation
git checkout -b docs/update-readme
```

### 2. Commit 规范

遵循 [Conventional Commits](https://www.conventionalcommits.org/) 格式：

```
<type>: <description>

<optional body>
```

| Type | 用途 |
|------|------|
| `feat` | 新功能 |
| `fix` | Bug 修复 |
| `refactor` | 重构（不改变功能） |
| `perf` | 性能优化 |
| `test` | 测试相关 |
| `docs` | 文档更新 |
| `chore` | 构建配置、依赖管理 |
| `ui` | 界面调整（不含逻辑） |

示例：
```
feat(ai): 添加药物识别功能

使用 Vision 框架 + Claude API 识别药物包装上的信息，
提供用法用量、相互作用和注意事项说明。
```

### 3. 提交 PR

- PR 标题遵循 commit 规范
- 描述中说明：改动原因、实现方案、测试方式
- 确保所有测试通过
- 无 `print()` 语句残留
- 如有 `project.yml` 变更，需说明原因

### 4. Code Review

- PR 需至少 1 位 reviewer approve 后方可合并
- 使用 squash merge 保持 main 分支历史整洁

---

## 安全注意事项 / Security

- **不得**在代码中硬编码 API Key、密码或任何敏感信息
- API Key 通过应用 Settings 界面由用户自行配置，存储在 `UserDefaults`（加密）
- 如发现安全漏洞，请通过 Issue 私密报告（标记 Security label）

---

## 问题反馈 / Issues

- 使用 GitHub Issues 报告 bug 或提功能建议
- Bug 报告请附上：iOS 版本、复现步骤、期望行为、实际行为
- 功能请求请说明使用场景和价值

---

感谢你的贡献！🎉
