import UIKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

/// 图片存储与处理服务 — 管理体检报告附件图片的存盘、缩略图生成、OCR 识别
actor ImageStorageService {

    static let shared = ImageStorageService()

    // MARK: - 常量

    private let thumbnailSize = CGSize(width: 240, height: 320)
    private let thumbnailSuffix = "_thumb"
    private let jpegQuality: CGFloat = 0.85
    private let thumbnailJpegQuality: CGFloat = 0.70

    // MARK: - 目录

    private var baseDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CheckupImages", isDirectory: true)
    }

    private func reportDirectory(for reportId: UUID) -> URL {
        baseDirectory.appendingPathComponent(reportId.uuidString, isDirectory: true)
    }

    // MARK: - 保存图片

    /// 将图片写入磁盘，同时生成缩略图。返回原图路径。
    func save(image: UIImage, for reportId: UUID) throws -> String {
        let dir = reportDirectory(for: reportId)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let filename = "\(UUID().uuidString).jpg"
        let originalURL = dir.appendingPathComponent(filename)
        let thumbURL = dir.appendingPathComponent(thumbnailFilename(from: filename))

        guard let originalData = image.jpegData(compressionQuality: jpegQuality) else {
            throw ImageStorageError.encodingFailed
        }
        try originalData.write(to: originalURL)

        // 生成缩略图
        let thumb = resized(image: image, to: thumbnailSize)
        if let thumbData = thumb.jpegData(compressionQuality: thumbnailJpegQuality) {
            try? thumbData.write(to: thumbURL)
        }

        return originalURL.path
    }

    // MARK: - 读取图片
    // nonisolated：纯磁盘读取，不访问可变 actor 状态，允许调用方并发加载多张图片

    nonisolated func loadImage(at path: String) -> UIImage? {
        UIImage(contentsOfFile: path)
    }

    nonisolated func loadThumbnail(for imagePath: String) -> UIImage? {
        let thumbPath = thumbnailPath(from: imagePath)
        return UIImage(contentsOfFile: thumbPath) ?? UIImage(contentsOfFile: imagePath)
    }

    // MARK: - 删除图片

    func delete(imagePath: String) {
        let fm = FileManager.default
        try? fm.removeItem(atPath: imagePath)
        try? fm.removeItem(atPath: thumbnailPath(from: imagePath))
    }

    func deleteAll(for reportId: UUID) {
        let dir = reportDirectory(for: reportId)
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - OCR 文字识别

    /// 对图片执行 Vision OCR，返回提取的文字。支持中英文混合。
    func extractText(from image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else {
            throw ImageStorageError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { req, err in
                if let err {
                    continuation.resume(throwing: err)
                    return
                }
                let lines = (req.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines.joined(separator: "\n"))
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

    // MARK: - 图片质量检测

    /// 返回图片模糊程度评分（0 = 极模糊，1 = 清晰）。
    /// 基于拉普拉斯方差法：清晰图片边缘对比度高，方差大。
    nonisolated func blurScore(of image: UIImage) -> Double {
        guard let cgImage = image.cgImage else { return 0 }
        let ciImage = CIImage(cgImage: cgImage)

        // 先灰度化，再做边缘检测
        let grayscale = ciImage.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 0.0
        ])
        let edges = grayscale.applyingFilter("CIEdges", parameters: [
            kCIInputIntensityKey: 1.0
        ])

        let context = CIContext()
        guard let output = context.createCGImage(edges, from: edges.extent) else { return 0 }

        // 计算亮度均值作为边缘强度的代理指标
        let width = output.width
        let height = output.height
        guard width > 0, height > 0,
              let data = output.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return 0 }

        let bytesPerPixel = output.bitsPerPixel / 8
        let totalPixels = width * height
        var sum: Double = 0

        for i in 0..<totalPixels {
            let offset = i * bytesPerPixel
            let r = Double(ptr[offset])
            sum += r
        }

        let mean = sum / Double(totalPixels) / 255.0
        // 映射到 0-1：边缘响应越高说明越清晰
        return min(mean * 4.0, 1.0)
    }

    /// 判断图片是否达到可用质量（score > 0.05 即可接受）
    nonisolated func isAcceptableQuality(_ image: UIImage) -> Bool {
        blurScore(of: image) > 0.05
    }

    // MARK: - 存储统计

    func storageBytes(for reportId: UUID) -> Int64 {
        let dir = reportDirectory(for: reportId)
        guard let enumerator = FileManager.default.enumerator(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            total += Int64(size)
        }
        return total
    }

    // MARK: - 辅助

    private func thumbnailFilename(from filename: String) -> String {
        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        return "\(base)\(thumbnailSuffix).\(ext)"
    }

    nonisolated private func thumbnailPath(from imagePath: String) -> String {
        let base = (imagePath as NSString).deletingPathExtension
        let ext = (imagePath as NSString).pathExtension
        return "\(base)\(thumbnailSuffix).\(ext)"
    }

    private func resized(image: UIImage, to targetSize: CGSize) -> UIImage {
        let ratio = min(targetSize.width / image.size.width,
                        targetSize.height / image.size.height)
        let newSize = CGSize(width: image.size.width * ratio,
                             height: image.size.height * ratio)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

// MARK: - Error

enum ImageStorageError: LocalizedError {
    case encodingFailed
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .encodingFailed: return "图片编码失败，请重试"
        case .invalidImage:   return "图片格式无效"
        }
    }
}
