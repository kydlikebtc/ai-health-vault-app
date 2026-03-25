import SwiftUI

// MARK: - Health Export View

struct HealthExportView: View {
    let member: Member
    @Environment(\.dismiss) private var dismiss

    @State private var options          = ExportOptions()
    @State private var isGenerating     = false
    @State private var exportURL: URL?
    @State private var showingShare     = false
    @State private var errorMessage: String?
    @State private var showingError     = false

    var body: some View {
        NavigationStack {
            Form {
                timeRangeSection
                dataTypesSection
                infoSection
                generateSection
            }
            .navigationTitle("导出健康报告")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
            .sheet(isPresented: $showingShare) {
                if let url = exportURL {
                    ShareSheetView(items: [url]) {
                        // 分享完成后清理临时文件
                        try? FileManager.default.removeItem(at: url)
                        exportURL = nil
                    }
                }
            }
            .alert("生成失败", isPresented: $showingError) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "未知错误，请重试。")
            }
        }
    }

    // MARK: - Form Sections

    private var timeRangeSection: some View {
        Section("时间范围") {
            Picker("导出范围", selection: $options.timeRange) {
                ForEach(ExportTimeRange.allCases, id: \.self) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
        }
    }

    private var dataTypesSection: some View {
        Section("包含数据") {
            Toggle(isOn: $options.includeMedicalHistory) {
                Label("既往病史", systemImage: "clock.arrow.circlepath")
            }
            Toggle(isOn: $options.includeMedications) {
                Label("用药记录", systemImage: "pills.fill")
            }
            Toggle(isOn: $options.includeCheckups) {
                Label("体检报告", systemImage: "doc.text.magnifyingglass")
            }
            Toggle(isOn: $options.includeVisits) {
                Label("就医记录", systemImage: "stethoscope")
            }
            Toggle(isOn: $options.includeWearable) {
                Label("健康趋势图", systemImage: "chart.line.uptrend.xyaxis")
            }
        }
    }

    private var infoSection: some View {
        Section {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                    .padding(.top, 1)
                    .accessibilityHidden(true)
                Text("将为「\(member.name)」生成 PDF 健康档案，可通过 AirDrop、邮件、消息等方式分享。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var generateSection: some View {
        Section {
            Button(action: generatePDF) {
                HStack {
                    Spacer()
                    if isGenerating {
                        ProgressView()
                            .padding(.trailing, 6)
                        Text("生成中…")
                            .fontWeight(.semibold)
                    } else {
                        Image(systemName: "arrow.down.doc.fill")
                            .padding(.trailing, 4)
                            .accessibilityHidden(true)
                        Text("生成 PDF 并分享")
                            .fontWeight(.semibold)
                    }
                    Spacer()
                }
                .foregroundStyle(isGenerating ? .secondary : .blue)
            }
            .disabled(isGenerating)
        }
    }

    // MARK: - PDF Generation

    private func generatePDF() {
        isGenerating = true
        Task { @MainActor in
            do {
                let url = try PDFExportService.shared.generateHealthReport(
                    for: member,
                    options: options
                )
                exportURL    = url
                isGenerating = false
                showingShare = true
            } catch {
                isGenerating  = false
                errorMessage  = error.localizedDescription
                showingError  = true
            }
        }
    }
}

// MARK: - ShareSheet Wrapper

/// UIActivityViewController 的 SwiftUI 包装，支持分享 URL / 文本等内容。
struct ShareSheetView: UIViewControllerRepresentable {
    let items: [Any]
    var onCompletion: (() -> Void)?

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.completionWithItemsHandler = { _, _, _, _ in
            onCompletion?()
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Preview

#Preview {
    HealthExportView(member: MockData.sampleMember)
        .modelContainer(MockData.previewContainer)
}
