import SwiftUI

/// AI 配置页面 — API Key 输入、功能开关、Token 用量展示
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
                // MARK: - API Key Section
                Section {
                    if aiMgr.isAPIKeyConfigured {
                        HStack {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.green)
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

                // MARK: - Feature Toggles
                Section("AI 功能") {
                    Toggle("启用 AI 助手", isOn: Binding(
                        get: { aiMgr.isAIEnabled },
                        set: { aiMgr.isAIEnabled = $0 }
                    ))
                    .disabled(!aiMgr.isAPIKeyConfigured)
                }

                // MARK: - Token Usage
                if aiMgr.isAPIKeyConfigured {
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
                        Text("每月自动重置。费用基于 claude-sonnet-4-6 定价估算，仅供参考。")
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
                Text("清除后 AI 功能将不可用，需重新配置。")
            }
        }
    }

    // MARK: - Actions

    private func saveAndValidateAPIKey() async {
        let key = apiKeyInput.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }

        isValidating = true
        validationResult = nil

        // 先保存到 Keychain
        aiMgr.saveAPIKey(key)

        // 发送一个最小请求验证 Key 有效性
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
            // 无网络时认为 Key 有效（无法验证），保留
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
