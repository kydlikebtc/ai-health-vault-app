import SwiftUI

/// AI 配置页面 — 服务模式选择（服务端代理 / BYOK）、API Key 输入（开发者）、用量展示
struct AISettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var apiKeyInput: String = ""
    @State private var isAPIKeyVisible: Bool = false
    @State private var isValidating: Bool = false
    @State private var validationResult: ValidationResult? = nil
    @State private var showClearConfirm = false

    private let aiMgr = AISettingsManager.shared

    enum ValidationResult {
        case success
        case failure(String)
    }

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Service Mode Section
                Section {
                    ForEach(AIServiceMode.allCases, id: \.rawValue) { mode in
                        Button {
                            aiMgr.serviceMode = mode
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mode.displayName)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                    Text(modeDescription(mode))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if aiMgr.serviceMode == mode {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                        .font(.subheadline.weight(.semibold))
                                }
                            }
                        }
                    }
                } header: {
                    Text("AI 服务模式")
                } footer: {
                    Text(aiMgr.serviceMode == .serverProxy
                         ? "服务端代理：API Key 由服务器统一管理，需要有效订阅（Premium 用户每月 50 次）。"
                         : "自带 API Key：直接使用您的 Anthropic API Key，不依赖订阅。适合开发者使用。")
                }

                // MARK: - Proxy URL (serverProxy mode, advanced)
                if aiMgr.serviceMode == .serverProxy {
                    Section {
                        HStack {
                            Text("代理端点")
                                .font(.subheadline)
                            Spacer()
                            TextField("https://...", text: Binding(
                                get: { aiMgr.proxyBaseURL },
                                set: { aiMgr.proxyBaseURL = $0 }
                            ))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        }
                    } header: {
                        Text("高级配置")
                    } footer: {
                        Text("通常无需修改。如需连接自部署代理实例，请修改此 URL。")
                    }
                }

                // MARK: - BYOK API Key Section
                if aiMgr.serviceMode == .byok {
                    Section {
                        if aiMgr.isAPIKeyConfigured {
                            HStack {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(.green)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("API Key 已配置")
                                        .font(.subheadline)
                                    Text(aiMgr.maskedAPIKey())
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }

                            Button(role: .destructive) {
                                showClearConfirm = true
                            } label: {
                                Label("清除 API Key", systemImage: "trash")
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    if isAPIKeyVisible {
                                        TextField("sk-ant-...", text: $apiKeyInput)
                                            .font(.caption.monospaced())
                                            .autocorrectionDisabled()
                                            .textInputAutocapitalization(.never)
                                    } else {
                                        SecureField("sk-ant-...", text: $apiKeyInput)
                                            .font(.caption.monospaced())
                                    }

                                    Button {
                                        isAPIKeyVisible.toggle()
                                    } label: {
                                        Image(systemName: isAPIKeyVisible ? "eye.slash" : "eye")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(isAPIKeyVisible ? "隐藏 API 密钥" : "显示 API 密钥")
                                }

                                if let result = validationResult {
                                    switch result {
                                    case .success:
                                        Label("API Key 有效", systemImage: "checkmark.circle.fill")
                                            .font(.caption)
                                            .foregroundStyle(.green)
                                    case .failure(let msg):
                                        Label(msg, systemImage: "xmark.circle.fill")
                                            .font(.caption)
                                            .foregroundStyle(.red)
                                    }
                                }
                            }

                            Button {
                                Task { await saveAndValidateAPIKey() }
                            } label: {
                                HStack {
                                    if isValidating {
                                        ProgressView().controlSize(.small)
                                        Text("验证中…")
                                    } else {
                                        Text("保存并验证")
                                    }
                                }
                            }
                            .disabled(apiKeyInput.trimmingCharacters(in: .whitespaces).isEmpty || isValidating)
                        }
                    } header: {
                        Text("Anthropic API Key")
                    } footer: {
                        Text("API Key 加密存储在系统 Keychain 中，不会上传至任何服务器。\n前往 console.anthropic.com 获取 API Key。")
                    }
                }

                // MARK: - Feature Toggles
                Section("AI 功能") {
                    Toggle("启用 AI 助手", isOn: Binding(
                        get: { aiMgr.isAIEnabled },
                        set: { aiMgr.isAIEnabled = $0 }
                    ))
                    .disabled(!aiMgr.isAIAvailable)
                }

                // MARK: - Token Usage (BYOK mode only)
                if aiMgr.serviceMode == .byok && aiMgr.isAPIKeyConfigured {
                    Section {
                        LabeledContent("Input Tokens", value: formatTokens(aiMgr.monthlyInputTokens))
                        LabeledContent("Output Tokens", value: formatTokens(aiMgr.monthlyOutputTokens))
                        LabeledContent("合计", value: formatTokens(aiMgr.monthlyTotalTokens))
                        LabeledContent("预估费用", value: aiMgr.estimatedMonthlyCostDisplay)

                        Button(role: .destructive) {
                            aiMgr.resetTokenCounts()
                        } label: {
                            Text("重置用量统计")
                        }
                    } header: {
                        Text("本月 Token 用量")
                    } footer: {
                        Text("每月自动重置。费用基于 claude-haiku-4-5 定价估算，仅供参考。")
                    }
                }
            }
            .navigationTitle("AI 配置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .confirmationDialog("确认清除", isPresented: $showClearConfirm) {
                Button("清除 API Key", role: .destructive) {
                    aiMgr.clearAPIKey()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("清除后 BYOK 模式下 AI 功能将不可用，需重新配置。")
            }
        }
    }

    // MARK: - Helpers

    private func modeDescription(_ mode: AIServiceMode) -> String {
        switch mode {
        case .serverProxy:
            return "需要 Premium 订阅 · 每月 50 次 AI 调用"
        case .byok:
            return "需要 Anthropic API Key · 开发者选项"
        }
    }

    private func saveAndValidateAPIKey() async {
        let key = apiKeyInput.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }

        isValidating = true
        validationResult = nil

        aiMgr.saveAPIKey(key)

        let service = ClaudeService()
        do {
            _ = try await service.sendMessage(
                [AIMessage(role: .user, content: "Hi")],
                systemPrompt: "Reply with one word: OK"
            )
            validationResult = .success
            apiKeyInput = ""
        } catch AIError.invalidAPIKey {
            validationResult = .failure("API Key 无效，请检查后重试")
            aiMgr.clearAPIKey()
        } catch AIError.networkUnavailable {
            validationResult = .success
        } catch {
            validationResult = .failure(error.localizedDescription)
            aiMgr.clearAPIKey()
        }

        isValidating = false
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}

#Preview {
    AISettingsView()
}
