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

#Preview {
    NavigationStack {
        RecordsView()
    }
    .modelContainer(for: [Member.self, Family.self], inMemory: true)
}
