import SwiftUI
import SwiftData

struct MemberDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let member: Member

    @State private var showingEdit   = false
    @State private var showingExport = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerCard
                healthSummaryCard
                DailyPlanCard(member: member)
                recordSectionsGrid
            }
            .padding()
        }
        .navigationTitle(member.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 4) {
                    Button {
                        showingExport = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    Button("编辑") { showingEdit = true }
                }
            }
        }
        .sheet(isPresented: $showingEdit) {
            AddEditMemberView(member: member)
        }
        .sheet(isPresented: $showingExport) {
            HealthExportView(member: member)
        }
    }

    // MARK: - 头部卡片

    private var headerCard: some View {
        HStack(spacing: 16) {
            // 头像
            avatarView
                .frame(width: 72, height: 72)

            VStack(alignment: .leading, spacing: 6) {
                Text(member.name)
                    .font(.title2.bold())

                HStack(spacing: 12) {
                    if let age = member.age {
                        infoChip("\(age)岁", icon: "calendar")
                    }
                    infoChip(member.gender.displayName, icon: "person")
                    if member.bloodType != .unknown {
                        infoChip(member.bloodType.rawValue, icon: "drop.fill")
                    }
                }

                if let h = member.heightCm, let w = member.weightKg {
                    HStack(spacing: 12) {
                        infoChip("\(Int(h))cm", icon: "ruler")
                        infoChip("\(Int(w))kg", icon: "scalemass")
                        if let bmi = member.bmi {
                            infoChip(String(format: "BMI %.1f", bmi), icon: "chart.bar")
                        }
                    }
                }
            }

            Spacer()
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - 健康摘要卡片

    @ViewBuilder
    private var healthSummaryCard: some View {
        let hasInfo = !member.allergies.isEmpty || !member.chronicConditions.isEmpty || !member.currentHealthNotes.isEmpty
        if hasInfo {
            VStack(alignment: .leading, spacing: 12) {
                Text("健康摘要")
                    .font(.headline)

                if !member.chronicConditions.isEmpty {
                    tagRow(title: "慢性病", items: member.chronicConditions, color: .orange)
                }
                if !member.allergies.isEmpty {
                    tagRow(title: "过敏", items: member.allergies, color: .red)
                }
                if !member.currentHealthNotes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("当前状况")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Text(member.currentHealthNotes)
                            .font(.callout)
                    }
                }
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: - 记录分类入口网格

    private var recordSectionsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            RecordCategoryCard(
                title: "用药记录",
                icon: "pills.fill",
                count: member.medications.count,
                color: .blue,
                destination: AnyView(MedicationListView(member: member))
            )
            RecordCategoryCard(
                title: "体检报告",
                icon: "doc.text.magnifyingglass",
                count: member.checkups.count,
                color: .green,
                destination: AnyView(CheckupListView(member: member))
            )
            RecordCategoryCard(
                title: "就医记录",
                icon: "stethoscope",
                count: member.visits.count,
                color: .purple,
                destination: AnyView(VisitListView(member: member))
            )
            RecordCategoryCard(
                title: "健康数据",
                icon: "heart.text.square.fill",
                count: member.wearableData.count,
                color: .red,
                destination: AnyView(WearableListView(member: member))
            )
            RecordCategoryCard(
                title: "既往病史",
                icon: "clock.arrow.circlepath",
                count: member.medicalHistory.count,
                color: .orange,
                destination: AnyView(MedicalHistoryListView(member: member))
            )
            RecordCategoryCard(
                title: "日常日志",
                icon: "calendar.badge.checkmark",
                count: member.dailyTracking.count,
                color: .teal,
                destination: AnyView(DailyLogListView(member: member))
            )
            RecordCategoryCard(
                title: "健康趋势",
                icon: "chart.line.uptrend.xyaxis",
                count: member.wearableData.count,
                color: .green,
                destination: AnyView(HealthTrendView(member: member))
            )
        }
    }

    // MARK: - 辅助视图

    @ViewBuilder
    private var avatarView: some View {
        if let data = member.avatarData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .clipShape(Circle())
        } else {
            Circle()
                .fill(member.gender == .female ? Color.pink : .blue)
                .overlay {
                    Text(String(member.name.prefix(1)))
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                }
        }
    }

    private func infoChip(_ text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.12), in: Capsule())
        .foregroundStyle(.secondary)
    }

    private func tagRow(title: String, items: [String], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            FlowLayout(items: items) { item in
                Text(item)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(color.opacity(0.15), in: Capsule())
                    .foregroundStyle(color)
            }
        }
    }
}

// MARK: - 记录分类卡片

struct RecordCategoryCard: View {
    let title: String
    let icon: String
    let count: Int
    let color: Color
    let destination: AnyView

    var body: some View {
        NavigationLink(destination: destination) {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                    .frame(width: 44, height: 44)
                    .background(color.opacity(0.12), in: Circle())
                    .accessibilityHidden(true)

                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)

                Text("\(count) 条记录")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 流式布局（Tag 排列）

struct FlowLayout<Item: Hashable, Content: View>: View {
    let items: [Item]
    let content: (Item) -> Content

    @State private var totalHeight: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            self.generateContent(in: geo)
        }
        .frame(height: totalHeight)
    }

    private func generateContent(in geometry: GeometryProxy) -> some View {
        var width: CGFloat = 0
        var height: CGFloat = 0

        return ZStack(alignment: .topLeading) {
            ForEach(items, id: \.self) { item in
                content(item)
                    .padding(.trailing, 6)
                    .padding(.bottom, 6)
                    .alignmentGuide(.leading) { d in
                        if abs(width - d.width) > geometry.size.width {
                            width = 0
                            height -= d.height + 6
                        }
                        let result = width
                        if item == items.last {
                            width = 0
                        } else {
                            width -= d.width + 6
                        }
                        return result
                    }
                    .alignmentGuide(.top) { _ in
                        let result = height
                        if item == items.last {
                            height = 0
                        }
                        return result
                    }
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear.onAppear {
                    totalHeight = geo.size.height
                }
            }
        )
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        MemberDetailView(member: MockData.sampleMember)
    }
    .modelContainer(MockData.previewContainer)
}
