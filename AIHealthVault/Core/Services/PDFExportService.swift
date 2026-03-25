import UIKit
import SwiftUI

// MARK: - Export Types

enum ExportTimeRange: String, CaseIterable {
    case threeMonths = "近3个月"
    case sixMonths = "近6个月"
    case oneYear = "近1年"
    case allTime = "全部"

    var cutoffDate: Date? {
        switch self {
        case .threeMonths: return Calendar.current.date(byAdding: .month, value: -3, to: Date())
        case .sixMonths:   return Calendar.current.date(byAdding: .month, value: -6, to: Date())
        case .oneYear:     return Calendar.current.date(byAdding: .year, value: -1, to: Date())
        case .allTime:     return nil
        }
    }
}

struct ExportOptions {
    var timeRange: ExportTimeRange = .oneYear
    var includeMedicalHistory: Bool = true
    var includeMedications: Bool = true
    var includeCheckups: Bool = true
    var includeVisits: Bool = true
    var includeWearable: Bool = true
}

// MARK: - PDF Export Service

/// Generates a multi-page A4 health report PDF for a Member.
/// Must run on the main actor because ImageRenderer and UIKit drawing are main-thread-only.
@MainActor
final class PDFExportService {
    static let shared = PDFExportService()
    private init() {}

    private let pageWidth: CGFloat  = 595.2   // A4 @ 72 dpi
    private let pageHeight: CGFloat = 841.8
    private let margin: CGFloat     = 40.0

    private var contentWidth: CGFloat { pageWidth - 2 * margin }

    // MARK: - Entry Point

    func generateHealthReport(for member: Member, options: ExportOptions) throws -> URL {
        // Pre-render chart images BEFORE entering the PDF renderer context to avoid
        // Core Graphics context conflicts between ImageRenderer and UIGraphicsPDFRenderer.
        let chartImages = buildChartImages(member: member, options: options)

        let dateString = Date().formatted(.dateTime.year().month().day())
        let fileName   = "\(member.name)_健康报告_\(dateString).pdf"
        let tempURL    = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        let bounds   = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)

        try renderer.writePDF(to: tempURL) { [self] ctx in
            // --- Cover page ---
            ctx.beginPage()
            drawCoverPage(member: member, options: options, context: ctx)

            // --- Content pages ---
            ctx.beginPage()
            var y: CGFloat = margin

            // 既往病史
            if options.includeMedicalHistory {
                let items = filteredHistory(member.medicalHistory, options: options)
                if !items.isEmpty {
                    y = drawSectionHeader("既往病史", y: y, context: ctx)
                    for item in items {
                        if y + 58 > pageHeight - margin { ctx.beginPage(); y = margin }
                        y = drawHistoryRow(item, y: y, context: ctx)
                    }
                    y += 16
                }
            }

            // 用药记录
            if options.includeMedications {
                let items = filteredMedications(member.medications, options: options)
                if !items.isEmpty {
                    if y + 80 > pageHeight - margin { ctx.beginPage(); y = margin }
                    y = drawSectionHeader("用药记录", y: y, context: ctx)
                    for item in items {
                        if y + 58 > pageHeight - margin { ctx.beginPage(); y = margin }
                        y = drawMedicationRow(item, y: y, context: ctx)
                    }
                    y += 16
                }
            }

            // 体检报告
            if options.includeCheckups {
                let items = filteredCheckups(member.checkups, options: options)
                if !items.isEmpty {
                    if y + 80 > pageHeight - margin { ctx.beginPage(); y = margin }
                    y = drawSectionHeader("体检报告", y: y, context: ctx)
                    for item in items {
                        if y + 70 > pageHeight - margin { ctx.beginPage(); y = margin }
                        y = drawCheckupRow(item, y: y, context: ctx)
                    }
                    y += 16
                }
            }

            // 就医记录
            if options.includeVisits {
                let items = filteredVisits(member.visits, options: options)
                if !items.isEmpty {
                    if y + 80 > pageHeight - margin { ctx.beginPage(); y = margin }
                    y = drawSectionHeader("就医记录", y: y, context: ctx)
                    for item in items {
                        if y + 70 > pageHeight - margin { ctx.beginPage(); y = margin }
                        y = drawVisitRow(item, y: y, context: ctx)
                    }
                    y += 16
                }
            }

            // 健康趋势图（pre-rendered）
            if !chartImages.isEmpty {
                ctx.beginPage()
                y = margin
                y = drawSectionHeader("健康趋势图", y: y, context: ctx)
                for (title, image) in chartImages {
                    let aspectH = contentWidth * (image.size.height / image.size.width)
                    if y + aspectH + 28 > pageHeight - margin { ctx.beginPage(); y = margin }
                    let labelAttr: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 11, weight: .medium),
                        .foregroundColor: UIColor.secondaryLabel
                    ]
                    NSAttributedString(string: title, attributes: labelAttr)
                        .draw(at: CGPoint(x: margin, y: y))
                    y += 17
                    image.draw(in: CGRect(x: margin, y: y, width: contentWidth, height: aspectH))
                    y += aspectH + 16
                }
            }

            // 页脚免责声明（最后一页）
            let footerAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 8),
                .foregroundColor: UIColor.tertiaryLabel
            ]
            let footerStr = NSAttributedString(
                string: "本报告由 AI Health Vault 生成，仅供个人健康记录参考，不代替专业医疗建议。",
                attributes: footerAttr
            )
            let footerW = footerStr.size().width
            footerStr.draw(at: CGPoint(x: (pageWidth - footerW) / 2, y: pageHeight - margin + 8))
        }

        return tempURL
    }

    // MARK: - Chart Image Pre-rendering

    private func buildChartImages(member: Member, options: ExportOptions) -> [(String, UIImage)] {
        guard options.includeWearable else { return [] }
        let cutoff = options.timeRange.cutoffDate
        let data   = member.wearableData.filter { cutoff == nil || $0.recordedAt >= cutoff! }

        var result: [(String, UIImage)] = []

        let chartWidth: CGFloat  = 515
        let chartHeight: CGFloat = 200

        func render<V: View>(_ view: V) -> UIImage? {
            let sized = view
                .frame(width: chartWidth, height: chartHeight)
                .background(Color(.systemBackground))
            let r = ImageRenderer(content: sized)
            r.scale = 2.0
            return r.uiImage
        }

        let weightEntries = data.filter { $0.metricType == .weight }.sorted { $0.recordedAt < $1.recordedAt }
        if !weightEntries.isEmpty, let img = render(WeightTrendChart(entries: weightEntries, member: member)) {
            result.append(("体重趋势", img))
        }

        let hrEntries = data.filter { $0.metricType == .heartRate }.sorted { $0.recordedAt < $1.recordedAt }
        if !hrEntries.isEmpty, let img = render(HeartRateTrendChart(entries: hrEntries)) {
            result.append(("心率趋势", img))
        }

        let bpEntries = data.filter { $0.metricType == .bloodPressure }.sorted { $0.recordedAt < $1.recordedAt }
        if !bpEntries.isEmpty, let img = render(BloodPressureTrendChart(entries: bpEntries)) {
            result.append(("血压趋势", img))
        }

        let stepsEntries = data.filter { $0.metricType == .steps }.sorted { $0.recordedAt < $1.recordedAt }
        if !stepsEntries.isEmpty, let img = render(StepsTrendChart(entries: stepsEntries, period: .month)) {
            result.append(("步数趋势", img))
        }

        let spo2Entries = data.filter { $0.metricType == .bloodOxygen }.sorted { $0.recordedAt < $1.recordedAt }
        if !spo2Entries.isEmpty, let img = render(BloodOxygenTrendChart(entries: spo2Entries)) {
            result.append(("血氧趋势", img))
        }

        return result
    }

    // MARK: - Cover Page

    private func drawCoverPage(member: Member, options: ExportOptions, context: UIGraphicsPDFRendererContext) {
        let cgCtx = context.cgContext

        // Header band
        cgCtx.setFillColor(UIColor.systemBlue.withAlphaComponent(0.07).cgColor)
        cgCtx.fill(CGRect(x: 0, y: 0, width: pageWidth, height: 225))

        // Heart icon
        let heartAttr: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 52, weight: .ultraLight),
            .foregroundColor: UIColor.systemBlue
        ]
        let heartStr = NSAttributedString(string: "♥", attributes: heartAttr)
        let heartW   = heartStr.size().width
        heartStr.draw(at: CGPoint(x: (pageWidth - heartW) / 2, y: 56))

        // Title
        let titleAttr: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 26, weight: .bold),
            .foregroundColor: UIColor.label
        ]
        let titleStr = NSAttributedString(string: "健康档案报告", attributes: titleAttr)
        let titleW   = titleStr.size().width
        titleStr.draw(at: CGPoint(x: (pageWidth - titleW) / 2, y: 126))

        // Member name
        let nameAttr: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 16),
            .foregroundColor: UIColor.secondaryLabel
        ]
        let nameStr = NSAttributedString(string: member.name, attributes: nameAttr)
        let nameW   = nameStr.size().width
        nameStr.draw(at: CGPoint(x: (pageWidth - nameW) / 2, y: 163))

        // Divider
        cgCtx.setStrokeColor(UIColor.separator.cgColor)
        cgCtx.setLineWidth(0.5)
        cgCtx.move(to: CGPoint(x: margin, y: 212))
        cgCtx.addLine(to: CGPoint(x: pageWidth - margin, y: 212))
        cgCtx.strokePath()

        // Info grid (2 columns)
        var infoY: CGFloat = 236
        let col1: CGFloat = margin
        let col2: CGFloat = pageWidth / 2 + 10

        func kv(_ label: String, _ value: String, x: CGFloat, y: CGFloat) {
            let lAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: UIColor.tertiaryLabel]
            let vAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: UIColor.label]
            NSAttributedString(string: label, attributes: lAttr).draw(at: CGPoint(x: x, y: y))
            NSAttributedString(string: value, attributes: vAttr).draw(at: CGPoint(x: x, y: y + 13))
        }

        if let age = member.age { kv("年龄", "\(age)岁", x: col1, y: infoY) }
        kv("性别", member.gender.displayName, x: col2, y: infoY); infoY += 42

        if member.bloodType != .unknown { kv("血型", member.bloodType.rawValue, x: col1, y: infoY) }
        if let h = member.heightCm { kv("身高", "\(Int(h)) cm", x: col2, y: infoY) }; infoY += 42

        if let w = member.weightKg { kv("体重", "\(Int(w)) kg", x: col1, y: infoY) }
        if let bmi = member.bmi { kv("BMI", String(format: "%.1f", bmi), x: col2, y: infoY) }; infoY += 42

        if !member.chronicConditions.isEmpty {
            kv("慢性病", member.chronicConditions.joined(separator: "、"), x: col1, y: infoY); infoY += 42
        }
        if !member.allergies.isEmpty {
            kv("过敏史", member.allergies.joined(separator: "、"), x: col1, y: infoY); infoY += 42
        }
        if !member.currentHealthNotes.isEmpty {
            kv("当前状况", member.currentHealthNotes, x: col1, y: infoY)
        }

        // Metadata footer
        let metaAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: UIColor.tertiaryLabel]
        let metaText = "生成日期：\(Date().formatted(.dateTime.year().month().day()))  ·  时间范围：\(options.timeRange.rawValue)  ·  AI Health Vault"
        let metaStr  = NSAttributedString(string: metaText, attributes: metaAttr)
        let metaW    = metaStr.size().width
        metaStr.draw(at: CGPoint(x: (pageWidth - metaW) / 2, y: pageHeight - margin - 4))
    }

    // MARK: - Section Header

    @discardableResult
    private func drawSectionHeader(_ title: String, y: CGFloat, context: UIGraphicsPDFRendererContext) -> CGFloat {
        let cgCtx = context.cgContext
        cgCtx.setFillColor(UIColor.systemBlue.cgColor)
        cgCtx.fill(CGRect(x: margin, y: y, width: 4, height: 18))

        let attr: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 13, weight: .bold),
            .foregroundColor: UIColor.label
        ]
        NSAttributedString(string: title, attributes: attr).draw(at: CGPoint(x: margin + 10, y: y + 1))

        cgCtx.setStrokeColor(UIColor.separator.cgColor)
        cgCtx.setLineWidth(0.5)
        cgCtx.move(to: CGPoint(x: margin, y: y + 24))
        cgCtx.addLine(to: CGPoint(x: pageWidth - margin, y: y + 24))
        cgCtx.strokePath()

        return y + 34
    }

    // MARK: - Row Renderers

    @discardableResult
    private func drawHistoryRow(_ item: MedicalHistory, y: CGFloat, context: UIGraphicsPDFRendererContext) -> CGFloat {
        let rowH: CGFloat = 52
        let cgCtx = context.cgContext
        cgCtx.setFillColor(UIColor.secondarySystemBackground.cgColor)
        cgCtx.fill(CGRect(x: margin, y: y, width: contentWidth, height: rowH))

        let titleAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: UIColor.label]
        let badge = item.isChronic ? "  慢性" : (item.isResolved ? "  已愈" : "")
        NSAttributedString(string: item.conditionName + badge, attributes: titleAttr)
            .draw(at: CGPoint(x: margin + 8, y: y + 7))

        var subParts: [String] = []
        if let d = item.diagnosedDate { subParts.append(d.formatted(.dateTime.year().month().day())) }
        if !item.hospitalName.isEmpty  { subParts.append(item.hospitalName) }
        if !item.doctorName.isEmpty    { subParts.append(item.doctorName) }
        let subAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: UIColor.secondaryLabel]
        NSAttributedString(string: subParts.joined(separator: " · "), attributes: subAttr)
            .draw(at: CGPoint(x: margin + 8, y: y + 27))

        return y + rowH + 4
    }

    @discardableResult
    private func drawMedicationRow(_ item: Medication, y: CGFloat, context: UIGraphicsPDFRendererContext) -> CGFloat {
        let rowH: CGFloat = 52
        let cgCtx = context.cgContext
        cgCtx.setFillColor(UIColor.secondarySystemBackground.cgColor)
        cgCtx.fill(CGRect(x: margin, y: y, width: contentWidth, height: rowH))

        let titleAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: UIColor.label]
        let titleText = item.dosage.isEmpty ? item.name : "\(item.name)  \(item.dosage)"
        NSAttributedString(string: titleText, attributes: titleAttr).draw(at: CGPoint(x: margin + 8, y: y + 7))

        let statusColor = item.isActive ? UIColor.systemGreen : UIColor.tertiaryLabel
        let statusAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: statusColor]
        let statusStr = NSAttributedString(string: item.isActive ? "● 服用中" : "● 已停用", attributes: statusAttr)
        statusStr.draw(at: CGPoint(x: pageWidth - margin - statusStr.size().width - 4, y: y + 9))

        var parts = [item.frequency.displayName, "开始 \(item.startDate.formatted(.dateTime.year().month().day()))"]
        if !item.prescribedBy.isEmpty { parts.insert("医生：\(item.prescribedBy)", at: 1) }
        let subAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: UIColor.secondaryLabel]
        NSAttributedString(string: parts.joined(separator: " · "), attributes: subAttr)
            .draw(at: CGPoint(x: margin + 8, y: y + 27))

        return y + rowH + 4
    }

    @discardableResult
    private func drawCheckupRow(_ item: CheckupReport, y: CGFloat, context: UIGraphicsPDFRendererContext) -> CGFloat {
        let rowH: CGFloat = 64
        let cgCtx = context.cgContext
        let bgColor = item.hasAbnormalItems
            ? UIColor.systemRed.withAlphaComponent(0.04)
            : UIColor.secondarySystemBackground
        cgCtx.setFillColor(bgColor.cgColor)
        cgCtx.fill(CGRect(x: margin, y: y, width: contentWidth, height: rowH))

        let titleAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: UIColor.label]
        let title = item.reportTitle.isEmpty ? "体检报告" : item.reportTitle
        NSAttributedString(string: title, attributes: titleAttr).draw(at: CGPoint(x: margin + 8, y: y + 6))

        let infoAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: UIColor.secondaryLabel]
        var infoParts = [item.checkupDate.formatted(.dateTime.year().month().day())]
        if !item.hospitalName.isEmpty { infoParts.append(item.hospitalName) }
        NSAttributedString(string: infoParts.joined(separator: " · "), attributes: infoAttr)
            .draw(at: CGPoint(x: margin + 8, y: y + 24))

        if !item.abnormalItems.isEmpty {
            let abnAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: UIColor.systemRed]
            let abnText = "⚠ 异常：" + item.abnormalItems.prefix(4).joined(separator: "、")
            NSAttributedString(string: abnText, attributes: abnAttr)
                .draw(in: CGRect(x: margin + 8, y: y + 44, width: contentWidth - 16, height: 14))
        } else if !item.summary.isEmpty {
            let sumAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: UIColor.tertiaryLabel]
            NSAttributedString(string: item.summary, attributes: sumAttr)
                .draw(in: CGRect(x: margin + 8, y: y + 44, width: contentWidth - 16, height: 14))
        }

        return y + rowH + 4
    }

    @discardableResult
    private func drawVisitRow(_ item: VisitRecord, y: CGFloat, context: UIGraphicsPDFRendererContext) -> CGFloat {
        let rowH: CGFloat = 64
        let cgCtx = context.cgContext
        cgCtx.setFillColor(UIColor.secondarySystemBackground.cgColor)
        cgCtx.fill(CGRect(x: margin, y: y, width: contentWidth, height: rowH))

        let titleAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: UIColor.label]
        let titleText = [item.visitType.displayName, item.hospitalName].filter { !$0.isEmpty }.joined(separator: " · ")
        NSAttributedString(string: titleText, attributes: titleAttr).draw(at: CGPoint(x: margin + 8, y: y + 6))

        var parts = [item.visitDate.formatted(.dateTime.year().month().day())]
        if !item.department.isEmpty  { parts.append(item.department) }
        if !item.doctorName.isEmpty  { parts.append(item.doctorName) }
        let dateAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: UIColor.secondaryLabel]
        NSAttributedString(string: parts.joined(separator: " · "), attributes: dateAttr)
            .draw(at: CGPoint(x: margin + 8, y: y + 24))

        if !item.diagnosis.isEmpty {
            let diagAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: UIColor.tertiaryLabel]
            NSAttributedString(string: "诊断：\(item.diagnosis)", attributes: diagAttr)
                .draw(in: CGRect(x: margin + 8, y: y + 44, width: contentWidth - 16, height: 14))
        }

        return y + rowH + 4
    }

    // MARK: - Data Filtering

    private func filteredHistory(_ items: [MedicalHistory], options: ExportOptions) -> [MedicalHistory] {
        let sorted = items.sorted { $0.createdAt > $1.createdAt }
        guard let cutoff = options.timeRange.cutoffDate else { return sorted }
        return sorted.filter { $0.createdAt >= cutoff }
    }

    private func filteredMedications(_ items: [Medication], options: ExportOptions) -> [Medication] {
        let sorted = items.sorted { $0.startDate > $1.startDate }
        guard let cutoff = options.timeRange.cutoffDate else { return sorted }
        return sorted.filter { $0.startDate >= cutoff || $0.isActive }
    }

    private func filteredCheckups(_ items: [CheckupReport], options: ExportOptions) -> [CheckupReport] {
        let sorted = items.sorted { $0.checkupDate > $1.checkupDate }
        guard let cutoff = options.timeRange.cutoffDate else { return sorted }
        return sorted.filter { $0.checkupDate >= cutoff }
    }

    private func filteredVisits(_ items: [VisitRecord], options: ExportOptions) -> [VisitRecord] {
        let sorted = items.sorted { $0.visitDate > $1.visitDate }
        guard let cutoff = options.timeRange.cutoffDate else { return sorted }
        return sorted.filter { $0.visitDate >= cutoff }
    }
}
