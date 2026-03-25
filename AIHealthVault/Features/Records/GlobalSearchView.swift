import SwiftUI

// MARK: - 搜索结果模型

/// 跨分类健康记录搜索结果
enum HealthSearchResult: Identifiable {
    case checkup(CheckupReport)
    case medication(Medication)
    case visit(VisitRecord)
    case history(MedicalHistory)
    case dailyLog(DailyLog)

    var id: String {
        switch self {
        case .checkup(let r):    return "checkup-\(r.id)"
        case .medication(let m): return "medication-\(m.id)"
        case .visit(let v):      return "visit-\(v.id)"
        case .history(let h):    return "history-\(h.id)"
        case .dailyLog(let l):   return "dailylog-\(l.id)"
        }
    }

    /// 用于结果按时间降序排列
    var sortDate: Date {
        switch self {
        case .checkup(let r):    return r.checkupDate
        case .medication(let m): return m.startDate
        case .visit(let v):      return v.visitDate
        case .history(let h):    return h.diagnosedDate ?? h.createdAt
        case .dailyLog(let l):   return l.date
        }
    }

    var category: String {
        switch self {
        case .checkup:    return "体检报告"
        case .medication: return "用药记录"
        case .visit:      return "就医记录"
        case .history:    return "既往病史"
        case .dailyLog:   return "日常追踪"
        }
    }

    var categoryIcon: String {
        switch self {
        case .checkup:    return "stethoscope"
        case .medication: return "pills.fill"
        case .visit:      return "cross.case.fill"
        case .history:    return "clock.badge.fill"
        case .dailyLog:   return "calendar.badge.plus"
        }
    }

    var categoryColor: Color {
        switch self {
        case .checkup:    return .blue
        case .medication: return .orange
        case .visit:      return .red
        case .history:    return .purple
        case .dailyLog:   return .teal
        }
    }

    var title: String {
        switch self {
        case .checkup(let r):
            return r.reportTitle.isEmpty ? "体检报告" : r.reportTitle
        case .medication(let m):
            return m.name
        case .visit(let v):
            return v.hospitalName.isEmpty ? "就医记录" : v.hospitalName
        case .history(let h):
            return h.conditionName
        case .dailyLog(let l):
            return l.date.formatted(date: .abbreviated, time: .omitted)
        }
    }

    var subtitle: String {
        switch self {
        case .checkup(let r):
            return r.hospitalName
        case .medication(let m):
            return m.dosage.isEmpty ? m.purpose : m.dosage
        case .visit(let v):
            return v.diagnosis.isEmpty ? v.department : v.diagnosis
        case .history(let h):
            return h.isChronic ? "慢性病" : (h.isResolved ? "已痊愈" : "进行中")
        case .dailyLog(let l):
            return l.notes.isEmpty ? (l.symptoms.isEmpty ? "无备注" : l.symptoms.joined(separator: "、")) : String(l.notes.prefix(50))
        }
    }

    /// 跨分类搜索逻辑（提取为静态方法以便单元测试）
    static func search(query: String, in member: Member) -> [HealthSearchResult] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        var all: [HealthSearchResult] = []

        // 体检报告：标题、机构、摘要
        all += member.checkups
            .filter { r in
                r.reportTitle.lowercased().contains(q) ||
                r.hospitalName.lowercased().contains(q) ||
                r.summary.lowercased().contains(q)
            }
            .map { .checkup($0) }

        // 用药记录：药名、用途、开具医生
        all += member.medications
            .filter { m in
                m.name.lowercased().contains(q) ||
                m.purpose.lowercased().contains(q) ||
                m.prescribedBy.lowercased().contains(q)
            }
            .map { .medication($0) }

        // 就医记录：医院、医生、诊断、主诉
        all += member.visits
            .filter { v in
                v.hospitalName.lowercased().contains(q) ||
                v.doctorName.lowercased().contains(q) ||
                v.diagnosis.lowercased().contains(q) ||
                v.chiefComplaint.lowercased().contains(q)
            }
            .map { .visit($0) }

        // 既往病史：病症名、治疗摘要、医生
        all += member.medicalHistory
            .filter { h in
                h.conditionName.lowercased().contains(q) ||
                h.treatmentSummary.lowercased().contains(q) ||
                h.doctorName.lowercased().contains(q)
            }
            .map { .history($0) }

        // 日常追踪：备注、症状标签
        all += member.dailyTracking
            .filter { l in
                l.notes.lowercased().contains(q) ||
                l.symptoms.contains(where: { $0.lowercased().contains(q) })
            }
            .map { .dailyLog($0) }

        return all.sorted { $0.sortDate > $1.sortDate }
    }
}

// MARK: - 搜索视图

/// 跨分类全局健康记录搜索
struct GlobalSearchView: View {
    let member: Member
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespaces)
    }

    /// 搜索结果：按时间降序，覆盖体检/用药/就医/病史/日志五大分类
    var searchResults: [HealthSearchResult] {
        HealthSearchResult.search(query: trimmedQuery, in: member)
    }

    var body: some View {
        NavigationStack {
            Group {
                if trimmedQuery.isEmpty {
                    emptyQueryView
                } else if searchResults.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    resultsList
                }
            }
            .navigationTitle("搜索健康记录")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "搜索 \(member.name) 的健康记录"
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private var emptyQueryView: some View {
        ContentUnavailableView(
            "搜索健康记录",
            systemImage: "magnifyingglass",
            description: Text("输入关键词，跨分类搜索体检、用药、就医、病史等记录")
        )
    }

    private var resultsList: some View {
        List(searchResults) { result in
            NavigationLink {
                destinationView(for: result)
            } label: {
                SearchResultRow(result: result)
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func destinationView(for result: HealthSearchResult) -> some View {
        switch result {
        case .checkup(let r):
            CheckupDetailView(report: r, member: member)
        case .medication(let m):
            MedicationDetailView(medication: m, member: member)
        case .visit(let v):
            VisitDetailView(visit: v, member: member)
        case .history(let h):
            MedicalHistoryDetailView(history: h, member: member)
        case .dailyLog(let l):
            DailyLogDetailView(log: l, member: member)
        }
    }
}

// MARK: - 搜索结果行

struct SearchResultRow: View {
    let result: HealthSearchResult

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: result.categoryIcon)
                .frame(width: 32, height: 32)
                .background(result.categoryColor.opacity(0.15))
                .foregroundStyle(result.categoryColor)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                Text(result.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(result.category)
                .font(.caption2)
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(result.categoryColor)
                .clipShape(Capsule())
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(result.category)：\(result.title)，\(result.subtitle)")
    }
}
