import SwiftUI
import PhotosUI
import Vision

// MARK: - 体检报告 AI 解读视图

struct ReportAnalysisView: View {
    let member: Member

    @State private var viewModel: ReportAnalysisViewModel
    @State private var pickerItem: PhotosPickerItem?
    @State private var showingImageSourceMenu = false
    @State private var showingCamera = false
    @State private var showingOCREditor = false
    @State private var ocrEditText = ""

    init(member: Member) {
        self.member = member
        self._viewModel = State(wrappedValue: ReportAnalysisViewModel(member: member))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                stepIndicator
                imagePickerSection
                if case .extracting = viewModel.phase { extractingView }
                if !viewModel.ocrText.isEmpty { ocrPreviewSection }
                if viewModel.showsAnalysis { analysisSection }
                if case .done = viewModel.phase { disclaimer }
            }
            .padding()
        }
        .navigationTitle("体检报告 AI 解读")
        .navigationBarTitleDisplayMode(.inline)
        // PhotosPicker 变化时触发 OCR
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                guard let data = try? await newItem.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { return }
                viewModel.selectedImage = image
                await viewModel.performOCRThenAnalyze(on: image)
            }
        }
        .sheet(isPresented: $showingCamera) {
            CameraPickerView { image in
                viewModel.selectedImage = image
                Task { await viewModel.performOCRThenAnalyze(on: image) }
            }
        }
        .sheet(isPresented: $showingOCREditor) {
            ocrEditorSheet
        }
    }

    // MARK: - 步骤指示器

    private var stepIndicator: some View {
        HStack(spacing: 0) {
            ForEach(Array(ReportAnalysisViewModel.Step.allCases.enumerated()), id: \.offset) { index, step in
                HStack(spacing: 4) {
                    Circle()
                        .fill(viewModel.currentStep >= step ? Color.blue : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                    Text(step.label)
                        .font(.caption2)
                        .foregroundStyle(viewModel.currentStep >= step ? .primary : .secondary)
                }
                if index < ReportAnalysisViewModel.Step.allCases.count - 1 {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(height: 1)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 4)
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.currentStep)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - 图片选择区域

    private var imagePickerSection: some View {
        VStack(spacing: 12) {
            if let image = viewModel.selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(alignment: .topTrailing) {
                        if case .idle = viewModel.phase {
                            Button {
                                viewModel.selectedImage = nil
                                viewModel.reset()
                                pickerItem = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.white)
                                    .background(Color.black.opacity(0.5), in: Circle())
                            }
                            .accessibilityLabel("清除图片")
                            .padding(8)
                        }
                    }
            } else {
                // 空状态 — 选择图片
                VStack(spacing: 16) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundStyle(.blue.opacity(0.7))
                        .accessibilityHidden(true)

                    Text("拍照或选择体检报告图片")
                        .font(.headline)

                    Text("支持 JPG、PNG、PDF 截图，文字需清晰可读")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 200)
                .background(Color.blue.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.blue.opacity(0.2), style: StrokeStyle(lineWidth: 2, dash: [6]))
                )
            }

            if case .idle = viewModel.phase {
                imagePickers
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var imagePickers: some View {
        HStack(spacing: 12) {
            PhotosPicker(
                selection: $pickerItem,
                matching: .images,
                photoLibrary: .shared()
            ) {
                Label("相册", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                showingCamera = true
            } label: {
                Label("拍照", systemImage: "camera")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - OCR 提取中

    private var extractingView: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("正在识别文字...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - OCR 预览

    private var ocrPreviewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "text.viewfinder")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text("识别到的文字")
                    .font(.headline)
                Spacer()
                if case .idle = viewModel.phase {
                    Button("编辑") {
                        ocrEditText = viewModel.ocrText
                        showingOCREditor = true
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }

            Text(viewModel.ocrText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(5)
                .frame(maxWidth: .infinity, alignment: .leading)

            if viewModel.ocrText.count < 50 {
                Label("文字较少，识别质量可能不佳，建议手动补充", systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            if case .idle = viewModel.phase {
                Button {
                    Task { await viewModel.analyze() }
                } label: {
                    Label("开始 AI 解读", systemImage: "brain.head.profile")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!SubscriptionManager.shared.hasAccess(to: .aiAnalysis))
                .requiresPremium(.aiAnalysis)

                if !SubscriptionManager.shared.hasAccess(to: .aiAnalysis) {
                    Text("升级到 Premium 即可使用 AI 体检解读")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - AI 解读结果

    @ViewBuilder
    private var analysisSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(.purple)
                    .accessibilityHidden(true)
                Text("AI 解读")
                    .font(.headline)
                Spacer()
                if case .analyzing = viewModel.phase {
                    ProgressView()
                        .scaleEffect(0.8)
                }
                if case .done = viewModel.phase {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityLabel("解读完成")
                }
            }

            if viewModel.analysisContent.isEmpty {
                HStack {
                    Spacer()
                    ProgressView("生成中...")
                        .padding()
                    Spacer()
                }
            } else {
                MarkdownAnalysisView(content: viewModel.analysisContent)
            }

            if case .failed(let msg) = viewModel.phase {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                        .accessibilityHidden(true)
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Button("重试") {
                    Task { await viewModel.analyze() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - 免责声明

    private var disclaimer: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("以上解读由 AI 生成，仅供参考，不构成医疗建议。如有异常指标，请及时咨询医生。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - OCR 编辑 Sheet

    private var ocrEditorSheet: some View {
        NavigationStack {
            TextEditor(text: $ocrEditText)
                .font(.callout)
                .padding()
                .navigationTitle("编辑识别文字")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { showingOCREditor = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") {
                            viewModel.ocrText = ocrEditText
                            showingOCREditor = false
                        }
                    }
                }
        }
    }
}

// MARK: - 简易 Markdown 渲染

struct MarkdownAnalysisView: View {
    let content: String

    var body: some View {
        if let attributed = try? AttributedString(
            markdown: content,
            options: .init(interpretedSyntax: .inlinesOnlyPreservingWhitespace)
        ) {
            Text(attributed)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(content)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - 相机选择器（UIImagePickerController 包装）

struct CameraPickerView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture, dismiss: dismiss) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage) -> Void
        let dismiss: DismissAction

        init(onCapture: @escaping (UIImage) -> Void, dismiss: DismissAction) {
            self.onCapture = onCapture
            self.dismiss = dismiss
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.editedImage] as? UIImage ?? info[.originalImage] as? UIImage {
                onCapture(image)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}

// MARK: - ViewModel

@Observable
@MainActor
final class ReportAnalysisViewModel {

    enum Step: Int, CaseIterable, Comparable {
        case selectImage = 0
        case extractText = 1
        case aiAnalysis = 2
        case done = 3

        var label: String {
            switch self {
            case .selectImage: return "选图"
            case .extractText: return "识别"
            case .aiAnalysis: return "解读"
            case .done: return "完成"
            }
        }

        static func < (lhs: Step, rhs: Step) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    enum Phase {
        case idle
        case extracting
        case analyzing
        case done
        case failed(String)
    }

    // MARK: - State

    var selectedImage: UIImage?
    var ocrText: String = ""
    var analysisContent: String = ""
    var phase: Phase = .idle

    var currentStep: Step {
        switch phase {
        case .idle:       return selectedImage == nil ? .selectImage : .extractText
        case .extracting: return .extractText
        case .analyzing:  return .aiAnalysis
        case .done:       return .done
        case .failed:     return ocrText.isEmpty ? .extractText : .aiAnalysis
        }
    }

    var showsAnalysis: Bool {
        switch phase {
        case .analyzing, .done, .failed: return true
        default: return !analysisContent.isEmpty
        }
    }

    // MARK: - Private

    private let member: Member
    private let aiService: any AIService

    init(member: Member, aiService: (any AIService)? = nil) {
        self.member = member
        if let provided = aiService {
            self.aiService = provided
        } else if AISettingsManager.shared.isAPIKeyConfigured {
            self.aiService = ClaudeService()
        } else {
            self.aiService = MockAIService.reportAnalysisMock()
        }
    }

    // MARK: - OCR

    func performOCRThenAnalyze(on image: UIImage) async {
        phase = .extracting
        do {
            ocrText = try await extractText(from: image)
            if AISettingsManager.shared.isAPIKeyConfigured {
                await analyze()
            } else {
                phase = .idle
            }
        } catch {
            ocrText = ""
            phase = .failed("文字识别失败：\(error.localizedDescription)")
        }
    }

    private func extractText(from image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else {
            throw AIError.streamingError("图片格式无效")
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { req, err in
                if let err {
                    continuation.resume(throwing: err)
                    return
                }
                let lines = (req.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                let text = lines.joined(separator: "\n")
                continuation.resume(returning: text)
            }
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - AI Analysis

    func analyze() async {
        guard !ocrText.isEmpty else { return }
        phase = .analyzing
        analysisContent = ""

        let template = PromptLibrary.ReportAnalysis()
        let context = PromptContext(
            memberName: member.name,
            memberAge: member.age,
            medicalHistory: member.chronicConditions,
            currentMedications: member.medications.map(\.name),
            recentCheckupSummary: ocrText,
            userQuery: "请帮我解读以上体检报告"
        )
        let message = AIMessage(role: .user, content: template.buildUserMessage(context: context))

        do {
            for try await chunk in aiService.streamMessage([message], systemPrompt: template.systemPrompt) {
                analysisContent += chunk
            }
            phase = .done
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    // MARK: - Reset

    func reset() {
        ocrText = ""
        analysisContent = ""
        phase = .idle
    }
}

// MARK: - 成员选择入口（从 AI Tab 进入时）

struct ReportAnalysisMemberPickerView: View {
    @Query(sort: \Member.name) private var members: [Member]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if members.isEmpty {
                    ContentUnavailableView(
                        "暂无家庭成员",
                        systemImage: "person.2.slash",
                        description: Text("请先在「家庭」页面添加成员")
                    )
                } else {
                    List(members) { member in
                        NavigationLink(destination: ReportAnalysisView(member: member)) {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(member.gender == .female ? Color.pink : .blue)
                                    .frame(width: 40, height: 40)
                                    .overlay {
                                        Text(String(member.name.prefix(1)))
                                            .font(.headline.bold())
                                            .foregroundStyle(.white)
                                    }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(member.name)
                                        .font(.body.bold())
                                    if let age = member.age {
                                        Text("\(age)岁 · \(member.gender.displayName)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text("\(member.checkups.count) 份报告")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("选择成员")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Preview

// MARK: - 从已有体检报告直接 AI 解读（无需 OCR）

struct ReportAnalysisFromReportView: View {
    let report: CheckupReport
    let member: Member

    @State private var viewModel: ReportAnalysisViewModel
    @Environment(\.dismiss) private var dismiss

    init(report: CheckupReport, member: Member) {
        self.report = report
        self.member = member
        self._viewModel = State(wrappedValue: ReportAnalysisViewModel(member: member))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 报告信息卡片
                HStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.title2)
                        .foregroundStyle(.blue)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(report.reportTitle.isEmpty ? "体检报告" : report.reportTitle)
                            .font(.headline)
                        Text(report.hospitalName.isEmpty ? "" : report.hospitalName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

                if !viewModel.analysisContent.isEmpty || viewModel.showsAnalysis {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "brain.head.profile")
                                .foregroundStyle(.purple)
                                .accessibilityHidden(true)
                            Text("AI 解读").font(.headline)
                            Spacer()
                            if case .analyzing = viewModel.phase { ProgressView().scaleEffect(0.8) }
                            if case .done = viewModel.phase {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .accessibilityLabel("解读完成")
                            }
                        }
                        if viewModel.analysisContent.isEmpty {
                            HStack { Spacer(); ProgressView("生成中...").padding(); Spacer() }
                        } else {
                            MarkdownAnalysisView(content: viewModel.analysisContent)
                        }
                    }
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }

                if case .done = viewModel.phase {
                    HStack(spacing: 10) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text("以上解读由 AI 生成，仅供参考，不构成医疗建议。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding()
        }
        .navigationTitle("AI 解读")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("关闭") { dismiss() }
            }
        }
        .task {
            // 将报告的摘要和异常指标组合成 OCR 文本
            var text = ""
            if !report.summary.isEmpty { text += "摘要：\(report.summary)\n" }
            if !report.abnormalItems.isEmpty {
                text += "异常指标：\(report.abnormalItems.joined(separator: "、"))\n"
            }
            viewModel.ocrText = text.isEmpty ? "（无文字数据）" : text
            await viewModel.analyze()
        }
    }
}

#Preview("报告解读") {
    NavigationStack {
        ReportAnalysisView(member: MockData.sampleMemberWithTrends)
    }
    .modelContainer(MockData.previewContainer)
}

#Preview("成员选择") {
    ReportAnalysisMemberPickerView()
        .modelContainer(MockData.previewContainer)
}
