import SwiftUI
import SwiftData

/// 健康记录主页 — 按类型分类展示所有健康记录
struct RecordsView: View {
    @Query(sort: \Member.name) private var members: [Member]
    @State private var selectedMember: Member?

    var body: some View {
        Group {
            if members.isEmpty {
                ContentUnavailableView(
                    "暂无家庭成员",
                    systemImage: "person.2",
                    description: Text("请先在「家庭」标签页添加成员")
                )
            } else {
                recordContent
            }
        }
        .navigationTitle("健康记录")
        .toolbar {
            if !members.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    memberPicker
                }
            }
        }
        .onAppear {
            if selectedMember == nil {
                selectedMember = members.first
            }
        }
        .onChange(of: members) { _, newMembers in
            if selectedMember == nil {
                selectedMember = newMembers.first
            }
        }
    }

    private var memberPicker: some View {
        Menu {
            ForEach(members) { member in
                Button(member.name) {
                    selectedMember = member
                }
            }
        } label: {
            HStack {
                Text(selectedMember?.name ?? "选择成员")
                Image(systemName: "chevron.down")
            }
            .font(.subheadline)
        }
    }

    @ViewBuilder
    private var recordContent: some View {
        if let member = selectedMember {
            RecordCategoryList(member: member)
        }
    }
}

// MARK: - Record Category List

struct RecordCategoryList: View {
    let member: Member

    var body: some View {
        List {
            Section {
                NavigationLink {
                    CheckupListView(member: member)
                } label: {
                    RecordCategoryRow(
                        icon: "stethoscope",
                        color: .blue,
                        title: "体检报告",
                        count: member.checkups.count
                    )
                }

                NavigationLink {
                    MedicationListView(member: member)
                } label: {
                    RecordCategoryRow(
                        icon: "pills.fill",
                        color: .orange,
                        title: "用药记录",
                        count: member.medications.count
                    )
                }

                NavigationLink {
                    VisitListView(member: member)
                } label: {
                    RecordCategoryRow(
                        icon: "cross.case.fill",
                        color: .red,
                        title: "就医记录",
                        count: member.visits.count
                    )
                }

                NavigationLink {
                    MedicalHistoryListView(member: member)
                } label: {
                    RecordCategoryRow(
                        icon: "clock.badge.fill",
                        color: .purple,
                        title: "既往病史",
                        count: member.medicalHistory.count
                    )
                }
            } header: {
                Text("\(member.name) 的记录")
            }

            Section("健康追踪") {
                NavigationLink {
                    WearableListView(member: member)
                } label: {
                    RecordCategoryRow(
                        icon: "applewatch",
                        color: .green,
                        title: "体征数据",
                        count: member.wearableData.count
                    )
                }

                NavigationLink {
                    DailyLogListView(member: member)
                } label: {
                    RecordCategoryRow(
                        icon: "calendar.badge.plus",
                        color: .teal,
                        title: "日常追踪",
                        count: member.dailyTracking.count
                    )
                }
            }
        }
    }
}

struct RecordCategoryRow: View {
    let icon: String
    let color: Color
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.15))
                .foregroundStyle(color)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(title)
                .font(.body)

            Spacer()

            Text("\(count)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Placeholder Sub-views (Phase 2 will fill these)

struct CheckupListView: View {
    let member: Member
    var body: some View {
        List(member.checkups) { report in
            VStack(alignment: .leading, spacing: 4) {
                Text(report.reportTitle.isEmpty ? "体检报告" : report.reportTitle)
                    .font(.headline)
                Text(report.checkupDate.localizedDateString)
                    .font(.caption).foregroundStyle(.secondary)
                if !report.hospitalName.isEmpty {
                    Text(report.hospitalName)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
        .navigationTitle("体检报告")
        .overlay {
            if member.checkups.isEmpty {
                ContentUnavailableView("暂无体检报告", systemImage: "stethoscope")
            }
        }
    }
}

struct MedicationListView: View {
    let member: Member
    var body: some View {
        List(member.medications) { med in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(med.name).font(.headline)
                    Spacer()
                    if med.isActive {
                        Text("服用中").font(.caption).foregroundStyle(.green)
                    }
                }
                Text("\(med.dosage) · \(med.frequency.displayName)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
        .navigationTitle("用药记录")
        .overlay {
            if member.medications.isEmpty {
                ContentUnavailableView("暂无用药记录", systemImage: "pills.fill")
            }
        }
    }
}

struct VisitListView: View {
    let member: Member
    var body: some View {
        List(member.visits) { visit in
            VStack(alignment: .leading, spacing: 4) {
                Text(visit.hospitalName.isEmpty ? "就医记录" : visit.hospitalName).font(.headline)
                Text("\(visit.visitDate.localizedDateString) · \(visit.visitType.displayName)")
                    .font(.caption).foregroundStyle(.secondary)
                if !visit.diagnosis.isEmpty {
                    Text(visit.diagnosis).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
        .navigationTitle("就医记录")
        .overlay {
            if member.visits.isEmpty {
                ContentUnavailableView("暂无就医记录", systemImage: "cross.case.fill")
            }
        }
    }
}

struct MedicalHistoryListView: View {
    let member: Member
    var body: some View {
        List(member.medicalHistory) { history in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(history.conditionName).font(.headline)
                    Spacer()
                    if history.isChronic {
                        Text("慢性病").font(.caption).foregroundStyle(.orange)
                    }
                }
                if let date = history.diagnosedDate {
                    Text(date.localizedDateString).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
        .navigationTitle("既往病史")
        .overlay {
            if member.medicalHistory.isEmpty {
                ContentUnavailableView("暂无既往病史", systemImage: "clock.badge.fill")
            }
        }
    }
}

struct WearableListView: View {
    let member: Member
    var body: some View {
        List(member.wearableData.sorted { $0.recordedAt > $1.recordedAt }) { entry in
            HStack {
                Image(systemName: entry.metricType.icon)
                    .foregroundStyle(.green)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.metricType.displayName).font(.headline)
                    Text(entry.recordedAt.localizedDateString).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(entry.displayValue).font(.subheadline.monospacedDigit())
            }
            .padding(.vertical, 2)
        }
        .navigationTitle("体征数据")
        .overlay {
            if member.wearableData.isEmpty {
                ContentUnavailableView("暂无体征数据", systemImage: "applewatch")
            }
        }
    }
}

struct DailyLogListView: View {
    let member: Member
    var body: some View {
        List(member.dailyTracking.sorted { $0.date > $1.date }) { log in
            HStack {
                Text(log.mood.emoji).font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(log.date.localizedDateString).font(.headline)
                    Text("运动 \(log.exerciseMinutes) 分钟 · 饮水 \(log.waterIntakeMl) ml")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
        .navigationTitle("日常追踪")
        .overlay {
            if member.dailyTracking.isEmpty {
                ContentUnavailableView("暂无日常追踪记录", systemImage: "calendar.badge.plus")
            }
        }
    }
}

#Preview {
    NavigationStack {
        RecordsView()
    }
    .modelContainer(for: [Member.self, Family.self], inMemory: true)
}
