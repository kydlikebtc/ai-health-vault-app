import SwiftUI
import SwiftData
import PhotosUI

// MARK: - 体检报告列表

struct CheckupListView: View {
    @Environment(\.modelContext) private var modelContext
    let member: Member

    @State private var searchText = ""
    @State private var showingAdd = false
    @State private var recordToEdit: CheckupReport?
    @State private var recordToDelete: CheckupReport?
    @State private var showingDeleteAlert = false

    private var filteredCheckups: [CheckupReport] {
        let sorted = member.checkups.sorted { $0.checkupDate > $1.checkupDate }
        guard !searchText.isEmpty else { return sorted }
        return sorted.filter {
            $0.reportTitle.localizedCaseInsensitiveContains(searchText) ||
            $0.hospitalName.localizedCaseInsensitiveContains(searchText) ||
            $0.summary.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        Group {
            if member.checkups.isEmpty && searchText.isEmpty {
                ContentUnavailableView {
                    Label("暂无体检报告", systemImage: "stethoscope")
                } actions: {
                    Button("添加报告") { showingAdd = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    ForEach(filteredCheckups) { report in
                        NavigationLink {
                            CheckupDetailView(report: report, member: member)
                        } label: {
                            CheckupRow(report: report)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                recordToDelete = report
                                showingDeleteAlert = true
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            Button {
                                recordToEdit = report
                            } label: {
                                Label("编辑", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                }
            }
        }
        .navigationTitle("体检报告")
        .searchable(text: $searchText, prompt: "搜索体检报告")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAdd = true } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("添加体检报告")
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddEditCheckupView(member: member)
        }
        .sheet(item: $recordToEdit) { record in
            AddEditCheckupView(member: member, report: record)
        }
        .alert("删除记录", isPresented: $showingDeleteAlert, presenting: recordToDelete) { record in
            Button("删除", role: .destructive) { modelContext.delete(record) }
            Button("取消", role: .cancel) {}
        } message: { record in
            Text("确定要删除「\(record.reportTitle.isEmpty ? "体检报告" : record.reportTitle)」吗？")
        }
    }
}

// MARK: - 体检报告行

struct CheckupRow: View {
    let report: CheckupReport

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(report.reportTitle.isEmpty ? "体检报告" : report.reportTitle)
                    .font(.headline)
                Spacer()
                if report.hasAbnormalItems {
                    StatusBadge(title: "有异常", color: .red)
                }
            }
            Label(report.checkupDate.localizedDateString, systemImage: "calendar")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !report.hospitalName.isEmpty {
                Label(report.hospitalName, systemImage: "building.2")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 体检报告详情

struct CheckupDetailView: View {
    let report: CheckupReport
    let member: Member
    @State private var showingEdit = false
    @State private var showingAIAnalysis = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                DetailCard {
                    HStack {
                        Text(report.reportTitle.isEmpty ? "体检报告" : report.reportTitle)
                            .font(.title2.bold())
                        Spacer()
                        if report.hasAbnormalItems {
                            StatusBadge(title: "有异常", color: .red)
                        }
                    }
                }

                DetailCard {
                    DetailRow(label: "体检日期", value: report.checkupDate.localizedDateString, icon: "calendar")
                    if !report.hospitalName.isEmpty {
                        DetailRow(label: "体检机构", value: report.hospitalName, icon: "building.2")
                    }
                }

                if !report.abnormalItems.isEmpty {
                    DetailCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("异常指标", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption.bold())
                                .foregroundStyle(.red)
                            ForEach(report.abnormalItems, id: \.self) { item in
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(.red)
                                        .frame(width: 6, height: 6)
                                    Text(item)
                                        .font(.body)
                                }
                            }
                        }
                    }
                }

                if !report.summary.isEmpty {
                    DetailCard {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("摘要/医生建议", systemImage: "doc.text")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Text(report.summary)
                                .font(.body)
                        }
                    }
                }

                // 图片附件画廊
                if !report.attachmentPaths.isEmpty {
                    DetailCard {
                        CheckupImageGallerySection(report: report)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("体检详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack {
                    Button {
                        showingAIAnalysis = true
                    } label: {
                        Label("AI 解读", systemImage: "brain.head.profile")
                    }
                    Button("编辑") { showingEdit = true }
                }
            }
        }
        .sheet(isPresented: $showingEdit) {
            AddEditCheckupView(member: member, report: report)
        }
        .sheet(isPresented: $showingAIAnalysis) {
            NavigationStack {
                ReportAnalysisFromReportView(report: report, member: member)
            }
        }
    }
}

// MARK: - 体检报告添加/编辑表单

struct AddEditCheckupView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let member: Member
    let report: CheckupReport?

    @State private var reportTitle = ""
    @State private var checkupDate = Date()
    @State private var hospitalName = ""
    @State private var summary = ""
    @State private var abnormalItemsText = ""

    // 图片相关状态
    @State private var existingImagePaths: [String] = []
    @State private var pendingImages: [UIImage] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showingCamera = false
    @State private var showingImageSourceMenu = false
    @State private var imageToPreview: UIImage?

    // 反馈
    @State private var showingValidationError = false
    @State private var blurWarning = false
    @State private var isSaving = false

    init(member: Member, report: CheckupReport? = nil) {
        self.member = member
        self.report = report
    }

    private var isEditing: Bool { report != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    HStack {
                        Text("报告标题")
                        Spacer()
                        TextField("如：2025年度体检", text: $reportTitle)
                            .multilineTextAlignment(.trailing)
                    }
                    DatePicker("体检日期", selection: $checkupDate, in: ...Date(), displayedComponents: .date)
                    HStack {
                        Text("体检机构")
                        Spacer()
                        TextField("可选", text: $hospitalName)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section("报告图片") {
                    imagePickerRow
                    if !existingImagePaths.isEmpty || !pendingImages.isEmpty {
                        imageThumbnailGrid
                    }
                }

                Section("异常指标") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("多个指标用换行分隔")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("如：总胆固醇偏高", text: $abnormalItemsText, axis: .vertical)
                            .lineLimit(4, reservesSpace: true)
                    }
                    .padding(.vertical, 2)
                }

                Section("摘要/医生建议") {
                    TextField("医生建议和整体评估...", text: $summary, axis: .vertical)
                        .lineLimit(4, reservesSpace: true)
                }
            }
            .navigationTitle(isEditing ? "编辑报告" : "添加报告")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button(isEditing ? "保存" : "添加") { Task { await saveAction() } }
                            .fontWeight(.semibold)
                    }
                }
            }
            .onAppear { populateFields() }
            .alert("请检查输入", isPresented: $showingValidationError) {
                Button("好的") {}
            } message: {
                Text("报告标题不能为空")
            }
            .alert("图片质量提示", isPresented: $blurWarning) {
                Button("继续使用") {}
                Button("重新拍摄", role: .cancel) { pendingImages.removeLast() }
            } message: {
                Text("图片可能模糊或光线不足，建议重新拍摄以确保 AI 识别准确。")
            }
            .sheet(isPresented: $showingCamera) {
                CameraPickerView { image in
                    handleNewImage(image)
                }
            }
            .photosPicker(
                isPresented: $showingImageSourceMenu,
                selection: $pickerItems,
                maxSelectionCount: 5,
                matching: .images
            )
            .onChange(of: pickerItems) { _, newItems in
                Task { await loadPickedImages(newItems) }
            }
        }
    }

    // MARK: - 图片选择行

    private var imagePickerRow: some View {
        HStack {
            Label("添加图片", systemImage: "camera.badge.plus")
                .foregroundStyle(.blue)
            Spacer()
            Menu {
                Button {
                    showingCamera = true
                } label: {
                    Label("拍照", systemImage: "camera")
                }
                Button {
                    showingImageSourceMenu = true
                } label: {
                    Label("从相册选取", systemImage: "photo.on.rectangle")
                }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.blue)
                    .font(.title3)
            }
        }
    }

    // MARK: - 已有/待添加图片缩略图

    private var imageThumbnailGrid: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                // 已有图片（编辑模式）
                ForEach(existingImagePaths, id: \.self) { path in
                    ExistingImageThumb(path: path) {
                        existingImagePaths.removeAll { $0 == path }
                    }
                }
                // 待保存的新图片
                ForEach(Array(pendingImages.enumerated()), id: \.offset) { idx, img in
                    PendingImageThumb(image: img) {
                        pendingImages.remove(at: idx)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - 逻辑

    private func populateFields() {
        guard let r = report else { return }
        reportTitle = r.reportTitle
        checkupDate = r.checkupDate
        hospitalName = r.hospitalName
        summary = r.summary
        abnormalItemsText = r.abnormalItems.joined(separator: "\n")
        existingImagePaths = r.attachmentPaths
    }

    private func handleNewImage(_ image: UIImage) {
        pendingImages.append(image)
        Task {
            let acceptable = await ImageStorageService.shared.isAcceptableQuality(image)
            if !acceptable {
                await MainActor.run { blurWarning = true }
            }
        }
    }

    private func loadPickedImages(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { continue }
            await MainActor.run { handleNewImage(image) }
        }
        await MainActor.run { pickerItems = [] }
    }

    private func saveAction() async {
        let trimmedTitle = reportTitle.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty else {
            showingValidationError = true
            return
        }
        isSaving = true
        defer { isSaving = false }

        let abnormalItems = abnormalItemsText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        if let r = report {
            // 编辑模式：删除被用户移除的旧图片
            let removed = r.attachmentPaths.filter { !existingImagePaths.contains($0) }
            for path in removed {
                await ImageStorageService.shared.delete(imagePath: path)
            }

            // 保存新增图片（使用已有 id，保证目录一致）
            var newPaths: [String] = []
            var ocrTexts: [String] = []
            for image in pendingImages {
                if let path = try? await ImageStorageService.shared.save(image: image, for: r.id) {
                    newPaths.append(path)
                }
                if let text = try? await ImageStorageService.shared.extractText(from: image),
                   !text.isEmpty {
                    ocrTexts.append(text)
                }
            }

            r.reportTitle = trimmedTitle
            r.checkupDate = checkupDate
            r.hospitalName = hospitalName.trimmingCharacters(in: .whitespaces)
            r.summary = summary.trimmingCharacters(in: .whitespaces)
            r.abnormalItems = abnormalItems
            r.attachmentPaths = existingImagePaths + newPaths
            if !ocrTexts.isEmpty {
                r.rawText = (r.rawText.isEmpty ? "" : r.rawText + "\n\n") + ocrTexts.joined(separator: "\n\n")
            }
        } else {
            // 新建模式：先创建对象获取 id，再用该 id 保存图片，保证路径与 id 一致
            let newReport = CheckupReport(
                checkupDate: checkupDate,
                hospitalName: hospitalName.trimmingCharacters(in: .whitespaces),
                reportTitle: trimmedTitle
            )
            newReport.summary = summary.trimmingCharacters(in: .whitespaces)
            newReport.abnormalItems = abnormalItems
            newReport.member = member

            var newPaths: [String] = []
            var ocrTexts: [String] = []
            for image in pendingImages {
                if let path = try? await ImageStorageService.shared.save(image: image, for: newReport.id) {
                    newPaths.append(path)
                }
                if let text = try? await ImageStorageService.shared.extractText(from: image),
                   !text.isEmpty {
                    ocrTexts.append(text)
                }
            }

            newReport.attachmentPaths = newPaths
            newReport.rawText = ocrTexts.joined(separator: "\n\n")
            modelContext.insert(newReport)
        }
        dismiss()
    }
}

// MARK: - 已存图片缩略图（可删除）

private struct ExistingImageThumb: View {
    let path: String
    let onDelete: () -> Void
    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let img = image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.secondary.opacity(0.15)
                        .overlay { ProgressView() }
                }
            }
            .frame(width: 80, height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white, .red)
                    .font(.callout)
            }
            .accessibilityLabel("删除图片")
            .offset(x: 6, y: -6)
        }
        .task {
            image = await ImageStorageService.shared.loadThumbnail(for: path)
        }
    }
}

// MARK: - 待保存图片缩略图（可删除）

private struct PendingImageThumb: View {
    let image: UIImage
    let onDelete: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 80, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .bottomLeading) {
                    Text("待保存")
                        .font(.caption2)
                        .padding(3)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(4)
                }

            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white, .red)
                    .font(.callout)
            }
            .accessibilityLabel("删除图片")
            .offset(x: 6, y: -6)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        CheckupListView(member: MockData.sampleMember)
    }
    .modelContainer(MockData.previewContainer)
}
