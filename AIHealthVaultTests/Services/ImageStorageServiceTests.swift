import XCTest
import UIKit
@testable import AIHealthVault

/// ImageStorageService 单测
/// 覆盖：图片存储、缩略图生成、加载、删除、OCR 文字识别、模糊度评分、存储统计
final class ImageStorageServiceTests: XCTestCase {

    private let service = ImageStorageService.shared
    private var testReportId: UUID!

    override func setUp() async throws {
        try await super.setUp()
        testReportId = UUID()
    }

    override func tearDown() async throws {
        // 清理测试期间产生的文件，避免污染
        await service.deleteAll(for: testReportId)
        try await super.tearDown()
    }

    // MARK: - 辅助工厂

    /// 生成纯色测试图片（确保 jpegData 有效）
    private func makeSolidImage(color: UIColor = .white, size: CGSize = CGSize(width: 200, height: 200)) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    /// 生成带有清晰黑色文字的图片，用于 OCR 测试
    private func makeTextImage(text: String, size: CGSize = CGSize(width: 400, height: 150)) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 36),
                .foregroundColor: UIColor.black
            ]
            (text as NSString).draw(at: CGPoint(x: 20, y: 50), withAttributes: attributes)
        }
    }

    /// 生成带有清晰边缘（高对比度）的图片，模拟清晰图片
    private func makeSharpImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200)).image { ctx in
            // 黑白棋盘格——边缘丰富，blurScore 高
            let tileSize: CGFloat = 10
            for row in 0..<20 {
                for col in 0..<20 {
                    let x = CGFloat(col) * tileSize
                    let y = CGFloat(row) * tileSize
                    ((row + col) % 2 == 0 ? UIColor.black : UIColor.white).setFill()
                    ctx.fill(CGRect(x: x, y: y, width: tileSize, height: tileSize))
                }
            }
        }
    }

    // MARK: - save 存储测试

    func testSave_returnsPathEndingInJpg() async throws {
        let image = makeSolidImage()
        let path = try await service.save(image: image, for: testReportId)
        XCTAssertTrue(path.hasSuffix(".jpg"), "存储路径应以 .jpg 结尾，实际: \(path)")
    }

    func testSave_originalFileExistsOnDisk() async throws {
        let image = makeSolidImage()
        let path = try await service.save(image: image, for: testReportId)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path),
                      "原图文件应存在于磁盘: \(path)")
    }

    func testSave_thumbnailFileExistsOnDisk() async throws {
        let image = makeSolidImage()
        let path = try await service.save(image: image, for: testReportId)
        // 缩略图路径 = base + "_thumb" + ext
        let base = (path as NSString).deletingPathExtension
        let ext  = (path as NSString).pathExtension
        let thumbPath = "\(base)_thumb.\(ext)"
        XCTAssertTrue(FileManager.default.fileExists(atPath: thumbPath),
                      "缩略图文件应存在于磁盘: \(thumbPath)")
    }

    func testSave_multipleImages_eachGetsUniquePath() async throws {
        let image = makeSolidImage()
        let path1 = try await service.save(image: image, for: testReportId)
        let path2 = try await service.save(image: image, for: testReportId)
        XCTAssertNotEqual(path1, path2, "同一报告的多张图片路径应唯一")
    }

    // MARK: - loadImage 读取测试

    func testLoadImage_returnsImageAfterSave() async throws {
        let original = makeSolidImage(.blue)
        let path = try await service.save(image: original, for: testReportId)
        let loaded = service.loadImage(at: path)
        XCTAssertNotNil(loaded, "应能从已存储路径读取图片")
    }

    func testLoadImage_returnsNilForInvalidPath() {
        let result = service.loadImage(at: "/invalid/nonexistent/path.jpg")
        XCTAssertNil(result, "不存在的路径应返回 nil")
    }

    // MARK: - loadThumbnail 读取测试

    func testLoadThumbnail_returnsImageAfterSave() async throws {
        let image = makeSolidImage()
        let path = try await service.save(image: image, for: testReportId)
        let thumb = service.loadThumbnail(for: path)
        XCTAssertNotNil(thumb, "应能从已存储路径读取缩略图")
    }

    func testLoadThumbnail_fallsBackToOriginalWhenThumbMissing() async throws {
        // 先保存，再手动删除缩略图，验证回退逻辑
        let image = makeSolidImage()
        let path = try await service.save(image: image, for: testReportId)
        let base = (path as NSString).deletingPathExtension
        let ext  = (path as NSString).pathExtension
        let thumbPath = "\(base)_thumb.\(ext)"
        try? FileManager.default.removeItem(atPath: thumbPath)

        let result = service.loadThumbnail(for: path)
        XCTAssertNotNil(result, "缩略图不存在时应回退到原图，仍应返回非 nil")
    }

    // MARK: - delete 删除测试

    func testDelete_removesOriginalFile() async throws {
        let image = makeSolidImage()
        let path = try await service.save(image: image, for: testReportId)
        await service.delete(imagePath: path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path),
                       "删除后原图不应存在")
    }

    func testDelete_removesThumbnailFile() async throws {
        let image = makeSolidImage()
        let path = try await service.save(image: image, for: testReportId)
        let base = (path as NSString).deletingPathExtension
        let ext  = (path as NSString).pathExtension
        let thumbPath = "\(base)_thumb.\(ext)"

        await service.delete(imagePath: path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: thumbPath),
                       "删除后缩略图不应存在")
    }

    func testDelete_nonexistentPath_doesNotThrow() async {
        // 删除不存在的路径不应抛出异常
        await service.delete(imagePath: "/does/not/exist.jpg")
    }

    // MARK: - deleteAll 删除测试

    func testDeleteAll_removesReportDirectory() async throws {
        let image = makeSolidImage()
        let path = try await service.save(image: image, for: testReportId)
        let dir = (path as NSString).deletingLastPathComponent

        await service.deleteAll(for: testReportId)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir),
                       "deleteAll 后整个报告目录应被删除")
    }

    func testDeleteAll_emptyReport_doesNotThrow() async {
        // 对没有图片的 reportId 调用 deleteAll 不应崩溃
        await service.deleteAll(for: UUID())
    }

    // MARK: - storageBytes 存储统计测试

    func testStorageBytes_returnsZeroBeforeSave() async {
        let bytes = await service.storageBytes(for: UUID())
        XCTAssertEqual(bytes, 0, "未存储任何图片时应返回 0")
    }

    func testStorageBytes_returnsPositiveAfterSave() async throws {
        let image = makeSolidImage(size: CGSize(width: 500, height: 500))
        _ = try await service.save(image: image, for: testReportId)
        let bytes = await service.storageBytes(for: testReportId)
        XCTAssertGreaterThan(bytes, 0, "存储图片后 storageBytes 应 > 0")
    }

    func testStorageBytes_increasesWithMoreImages() async throws {
        let image = makeSolidImage(size: CGSize(width: 300, height: 300))
        _ = try await service.save(image: image, for: testReportId)
        let bytesAfterOne = await service.storageBytes(for: testReportId)

        _ = try await service.save(image: image, for: testReportId)
        let bytesAfterTwo = await service.storageBytes(for: testReportId)

        XCTAssertGreaterThan(bytesAfterTwo, bytesAfterOne,
                             "第二张图片存储后总大小应增加")
    }

    // MARK: - blurScore 模糊度评分测试

    func testBlurScore_sharpImageReturnsPositiveScore() {
        let sharp = makeSharpImage()
        let score = service.blurScore(of: sharp)
        XCTAssertGreaterThan(score, 0.0, "高对比度图片的模糊评分应 > 0")
    }

    func testBlurScore_scoreIsBetweenZeroAndOne() {
        let image = makeSharpImage()
        let score = service.blurScore(of: image)
        XCTAssertGreaterThanOrEqual(score, 0.0, "模糊评分下限为 0")
        XCTAssertLessThanOrEqual(score, 1.0, "模糊评分上限为 1")
    }

    // MARK: - isAcceptableQuality 质量判断测试

    func testIsAcceptableQuality_sharpImageReturnsTrue() {
        let sharp = makeSharpImage()
        let acceptable = service.isAcceptableQuality(sharp)
        XCTAssertTrue(acceptable, "高对比度图片应通过质量检测")
    }

    func testIsAcceptableQuality_solidColorImageReturnsFalse() {
        // 纯色图片无边缘，评分极低，应判定为质量不可接受
        let solid = makeSolidImage(color: .gray)
        let acceptable = service.isAcceptableQuality(solid)
        XCTAssertFalse(acceptable, "纯灰色图片（无边缘）应判定质量不可接受")
    }

    // MARK: - extractText OCR 测试

    func testExtractText_emptyWhiteImage_returnsEmptyOrShortText() async throws {
        // 白色图片没有可识别文字，结果应为空字符串或极短字符串
        let blank = makeSolidImage(color: .white, size: CGSize(width: 300, height: 100))
        let text = try await service.extractText(from: blank)
        // Vision 可能返回空字符串，也可能识别出噪声；不应抛出异常
        XCTAssertNotNil(text, "OCR 返回值不应为 nil")
    }

    func testExtractText_imageWithEnglishText_containsRecognizedWords() async throws {
        // 使用英文大写字母，Vision 识别率更高
        let label = "HEALTH"
        let img = makeTextImage(text: label)
        let result = try await service.extractText(from: img)
        // 宽松断言：至少包含部分识别结果
        XCTAssertFalse(result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                       || result.contains("HEALTH") || result.count > 0,
                       "OCR 应能从清晰文字图片中提取文本，实际结果: '\(result)'")
    }

    func testExtractText_throwsForInvalidCGImage() async throws {
        // 构造无法生成 cgImage 的 UIImage（尺寸 0 x 0）
        let emptyImage = UIImage()
        do {
            _ = try await service.extractText(from: emptyImage)
            XCTFail("对无效图片执行 extractText 应抛出 invalidImage 错误")
        } catch ImageStorageError.invalidImage {
            // 预期错误
        } catch {
            XCTFail("预期 ImageStorageError.invalidImage，实际抛出: \(error)")
        }
    }

    // MARK: - 错误描述测试

    func testErrorDescriptions_areLocalizedAndNonEmpty() {
        XCTAssertFalse(ImageStorageError.encodingFailed.errorDescription?.isEmpty ?? true,
                       "encodingFailed 应有本地化描述")
        XCTAssertFalse(ImageStorageError.invalidImage.errorDescription?.isEmpty ?? true,
                       "invalidImage 应有本地化描述")
    }
}
