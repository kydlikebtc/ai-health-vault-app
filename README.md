# AI Health Vault

**一款以本地数据优先的 iOS 家庭健康档案管理应用，由 Claude AI 赋能。**
*A privacy-first iOS family health records app, powered by Claude AI.*

[![iOS](https://img.shields.io/badge/iOS-17.0%2B-blue?logo=apple)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange?logo=swift)](https://swift.org)
[![SwiftUI](https://img.shields.io/badge/SwiftUI-5.0-blue)](https://developer.apple.com/xcode/swiftui/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

---

## 产品愿景 / Vision

让家庭健康数据管理像记笔记一样简单，让 AI 成为你的私人健康顾问——**数据始终留在你手中**。

> Make family health data management as simple as taking notes, and let AI be your personal health advisor — **data always stays with you**.

---

## 功能特性 / Features

### Phase 1 — 家庭健康档案基础 (Foundation)
- **家庭成员管理** — 支持最多 10 位家庭成员，独立健康档案
- **Face ID / Touch ID 认证** — 本地生物认证，保护隐私数据
- **6 种健康记录类型** — 体检报告、用药记录、就医记录、既往病史、可穿戴数据、日常日志
- **全局搜索** — 跨记录类型实时搜索，支持模糊匹配

### Phase 2 — HealthKit 集成 (Health Integration)
- **Apple Health 双向同步** — 步数、心率、睡眠、血氧等核心指标
- **健康趋势图表** — 基于 Swift Charts 的可视化趋势分析
- **后台数据同步** — HKObserverQuery 实时监听，静默更新

### Phase 3 — AI 健康助手 (AI-Powered)
- **体检报告 AI 解读** — Claude API 将晦涩指标转为通俗建议
- **就诊准备助手** — AI 生成问诊问题清单，最大化就诊价值
- **医学术语解读** — 长按任意术语，AI 实时通俗解释
- **药物识别与查询** — 识别药物信息、相互作用、注意事项
- **个性化对话上下文** — AI 结合成员完整健康档案进行个性化对话
- **OCR 体检报告** — 相机拍照 + Vision 框架自动提取报告文字

### Phase 4 — 数据导出与协作 (Export & Sharing)
- **PDF 导出** — 一键生成专业健康报告 PDF，含趋势图表
- **随访提醒** — 智能随访日历 + 本地通知
- **CloudKit 同步（可选）** — 用户主动开启，跨设备数据备份

---

## 技术栈 / Tech Stack

| 层次 | 技术选型 |
|------|---------|
| UI Framework | SwiftUI 5 (iOS 17+) |
| 数据持久化 | SwiftData (本地优先，无云端强依赖) |
| 并发模型 | Swift 6 Strict Concurrency + `@MainActor` |
| 健康数据 | HealthKit + HKObserverQuery |
| AI 能力 | Claude API (Anthropic) |
| 图表 | Swift Charts |
| OCR | Vision Framework |
| 图片存储 | FileManager + UIGraphicsImageRenderer |
| 认证 | LocalAuthentication (Face ID / Touch ID) |
| 构建配置 | XcodeGen (`project.yml`) |
| 测试 | XCTest + Swift Testing |

---

## 架构概述 / Architecture

本项目采用 MVVM 分层架构，详见 [docs/TECHNICAL.md](docs/TECHNICAL.md)。

```
┌─────────────────────────────────────────────┐
│              UI Layer (SwiftUI)              │
│  Family · Records · AI · Settings           │
└────────────────────┬────────────────────────┘
                     │
┌────────────────────▼────────────────────────┐
│           ViewModel Layer (MVVM)            │
│        @Observable / @StateObject           │
└──────┬─────────────┬──────────────┬─────────┘
       │             │              │
┌──────▼──┐  ┌───────▼───┐  ┌──────▼──────────┐
│SwiftData│  │ Services  │  │  External APIs  │
│(Local)  │  │HealthKit  │  │  Claude API     │
│         │  │ AI Service│  │  CloudKit (opt) │
└─────────┘  └───────────┘  └─────────────────┘
```

**核心设计原则：**
- 数据本地优先 — SwiftData 为主，CloudKit 为可选增强
- AI 作为可选层 — 无网络时核心功能完全可用
- 隐私保护 — PHI 数据使用 `os.Logger` 的 `.private` 隐私级别

---

## 快速开始 / Quick Start

### 环境要求 / Requirements

- macOS 15.0+ (Sequoia)
- Xcode 16.0+
- iOS 17.0+ 设备或模拟器
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

### 构建步骤 / Build

```bash
# 1. Clone 仓库
git clone https://github.com/kydlikebtc/ai-health-vault-app.git
cd ai-health-vault-app

# 2. 生成 Xcode 项目（必须，.xcodeproj 不在版本控制中）
xcodegen generate

# 3. 打开 Xcode 项目
open AIHealthVault.xcodeproj

# 4. 选择 target 设备，Command+R 运行
```

### AI 功能配置 / AI Setup (可选)

如需启用 Claude AI 功能，在应用 **Settings → AI 设置** 中填写 Anthropic API Key。
获取 API Key：前往 [Anthropic Console](https://console.anthropic.com)

> AI 功能为可选增强，不影响核心健康记录功能的使用。

---

## 项目结构 / Project Structure

```
AIHealthVault/
├── App/
│   ├── AIHealthVaultApp.swift      # App 入口，SwiftData ModelContainer 配置
│   ├── ContentView.swift           # TabView 主导航
│   └── LockScreenView.swift        # Face ID 认证锁屏
├── Core/
│   ├── Models/                     # SwiftData @Model 实体定义
│   │   ├── Family.swift
│   │   ├── Member.swift
│   │   ├── CheckupReport.swift     # 体检报告（含 rawText OCR 文本）
│   │   ├── Medication.swift
│   │   ├── VisitRecord.swift
│   │   ├── WearableEntry.swift
│   │   └── DailyLog.swift
│   └── Services/
│       ├── AI/                     # AI 服务抽象层
│       │   ├── AIService.swift     # Protocol 定义
│       │   ├── ClaudeService.swift # Anthropic API 实现
│       │   ├── MockAIService.swift # 测试 Mock
│       │   └── PromptLibrary.swift # 提示词模板管理
│       ├── ImageStorageService.swift   # 图片存储 + OCR
│       └── FollowUpNotificationService.swift
├── Features/
│   ├── Family/                     # 家庭成员管理
│   ├── Records/                    # 健康记录（含全局搜索）
│   ├── AI/                         # AI 助手对话界面
│   ├── Visit/                      # 就诊准备 + 随访日历
│   ├── ReportAnalysis/             # 体检报告 AI 解读
│   └── Export/                     # PDF 导出与分享
├── Resources/
│   └── Assets.xcassets
├── docs/
│   ├── PRD.md                      # 产品需求文档
│   ├── TECHNICAL.md                # 技术架构文档
│   ├── TESTING.md                  # 测试规范
│   └── USER_GUIDE.md               # 用户手册
└── project.yml                     # XcodeGen 配置
```

---

## 文档索引 / Documentation

| 文档 | 描述 |
|------|------|
| [docs/PRD.md](docs/PRD.md) | 产品需求文档，功能规格与验收标准 |
| [docs/TECHNICAL.md](docs/TECHNICAL.md) | 技术架构、设计决策、关键实现细节 |
| [docs/TESTING.md](docs/TESTING.md) | 测试策略、覆盖率要求、测试运行指南 |
| [docs/USER_GUIDE.md](docs/USER_GUIDE.md) | 终端用户功能使用说明 |
| [CONTRIBUTING.md](CONTRIBUTING.md) | 开发者贡献指南 |

---

## 贡献 / Contributing

欢迎提交 Issue 和 Pull Request！详见 [CONTRIBUTING.md](CONTRIBUTING.md)。

---

## 许可证 / License

本项目采用 [MIT 许可证](LICENSE)。
