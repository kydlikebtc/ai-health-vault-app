import SwiftUI
import PhotosUI

// MARK: - 图片画廊区域（嵌入详情页）

struct CheckupImageGallerySection: View {
    let report: CheckupReport
    @State private var fullscreenPath: String?

    var body: some View {
        if !report.attachmentPaths.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Label("报告图片", systemImage: "photo.on.rectangle.angled")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(report.attachmentPaths, id: \.self) { path in
                            Button {
                                fullscreenPath = path
                            } label: {
                                ThumbnailCell(imagePath: path)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("查看图片")
                        }
                    }
                }

                storageFooter
            }
            .fullScreenCover(item: $fullscreenPath) { path in
                FullscreenImageViewer(
                    paths: report.attachmentPaths,
                    initialPath: path
                )
            }
        }
    }

    private var storageFooter: some View {
        let bytes = storageSize
        if bytes > 0 {
            return AnyView(
                Text("已用 \(formattedSize(bytes))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            )
        }
        return AnyView(EmptyView())
    }

    private var storageSize: Int64 {
        // 简单估算：所有路径文件大小之和
        report.attachmentPaths.reduce(Int64(0)) { acc, path in
            let attrs = try? FileManager.default.attributesOfItem(atPath: path)
            return acc + Int64((attrs?[.size] as? Int) ?? 0)
        }
    }

    private func formattedSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - 缩略图单元格

private struct ThumbnailCell: View {
    let imagePath: String
    @State private var thumbnail: UIImage?

    var body: some View {
        Group {
            if let img = thumbnail {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.15))
                    .overlay {
                        ProgressView()
                    }
            }
        }
        .frame(width: 90, height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        thumbnail = await ImageStorageService.shared.loadThumbnail(for: imagePath)
    }
}

// MARK: - 全屏图片查看器

struct FullscreenImageViewer: View {
    let paths: [String]
    let initialPath: String

    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int
    @State private var images: [String: UIImage] = [:]
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    init(paths: [String], initialPath: String) {
        self.paths = paths
        self.initialPath = initialPath
        self._currentIndex = State(wrappedValue: paths.firstIndex(of: initialPath) ?? 0)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentIndex) {
                ForEach(Array(paths.enumerated()), id: \.offset) { index, path in
                    imageCell(for: path)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .onChange(of: currentIndex) { _, _ in
                resetZoom()
            }

            // 关闭按钮
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white)
                    .shadow(radius: 4)
                    .padding()
            }
            .accessibilityLabel("关闭")
        }
        .task {
            await loadImages()
        }
    }

    @ViewBuilder
    private func imageCell(for path: String) -> some View {
        if let img = images[path] {
            Image(uiImage: img)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = lastScale * value
                        }
                        .onEnded { _ in
                            lastScale = scale
                            if scale < 1.0 { resetZoom() }
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            guard scale > 1.0 else { return }
                            offset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                        }
                        .onEnded { _ in
                            lastOffset = offset
                        }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.spring()) { resetZoom() }
                }
        } else {
            ProgressView()
                .tint(.white)
        }
    }

    private func resetZoom() {
        withAnimation(.spring()) {
            scale = 1.0
            lastScale = 1.0
            offset = .zero
            lastOffset = .zero
        }
    }

    private func loadImages() async {
        await withTaskGroup(of: (String, UIImage?).self) { group in
            for path in paths {
                group.addTask {
                    let img = await ImageStorageService.shared.loadImage(at: path)
                    return (path, img)
                }
            }
            for await (path, img) in group {
                if let img { images[path] = img }
            }
        }
    }
}

// MARK: - String + Identifiable（用于 fullScreenCover item:）

extension String: @retroactive Identifiable {
    public var id: String { self }
}
