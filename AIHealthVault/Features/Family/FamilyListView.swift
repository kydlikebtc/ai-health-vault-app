import SwiftUI
import SwiftData

struct FamilyListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Member.createdAt, order: .forward) private var members: [Member]

    @State private var showingAddMember = false
    @State private var memberToEdit: Member?
    @State private var searchText = ""
    @State private var showingDeleteAlert = false
    @State private var memberToDelete: Member?

    var filteredMembers: [Member] {
        guard !searchText.isEmpty else { return members }
        return members.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if members.isEmpty {
                    emptyStateView
                } else {
                    memberList
                }
            }
            .navigationTitle("家庭成员")
            .searchable(text: $searchText, prompt: "搜索成员")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddMember = true
                    } label: {
                        Image(systemName: "person.badge.plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddMember) {
                AddEditMemberView()
            }
            .sheet(item: $memberToEdit) { member in
                AddEditMemberView(member: member)
            }
            .alert("删除成员", isPresented: $showingDeleteAlert, presenting: memberToDelete) { member in
                Button("删除", role: .destructive) {
                    deleteMember(member)
                }
                Button("取消", role: .cancel) {}
            } message: { member in
                Text("确定要删除 \(member.name) 的所有健康记录吗？此操作不可撤销。")
            }
        }
    }

    // MARK: - 子视图

    private var memberList: some View {
        List {
            ForEach(filteredMembers) { member in
                NavigationLink(destination: MemberDetailView(member: member)) {
                    MemberRowView(member: member)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        memberToDelete = member
                        showingDeleteAlert = true
                    } label: {
                        Label("删除", systemImage: "trash")
                    }

                    Button {
                        memberToEdit = member
                    } label: {
                        Label("编辑", systemImage: "pencil")
                    }
                    .tint(.blue)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("暂无家庭成员", systemImage: "person.2")
        } description: {
            Text("点击右上角按钮添加家庭成员")
        } actions: {
            Button("添加成员") {
                showingAddMember = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - 操作

    private func deleteMember(_ member: Member) {
        modelContext.delete(member)
    }
}

// MARK: - 成员行视图

struct MemberRowView: View {
    let member: Member

    var body: some View {
        HStack(spacing: 12) {
            // 头像
            avatarView
                .frame(width: 52, height: 52)

            // 信息
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(member.name)
                        .font(.headline)
                    Spacer()
                    if !member.chronicConditions.isEmpty {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                            .accessibilityLabel("有慢性病记录")
                    }
                }

                HStack(spacing: 8) {
                    if let age = member.age {
                        Label("\(age)岁", systemImage: "")
                            .labelStyle(.titleOnly)
                    }
                    Text(member.gender.displayName)
                    if member.bloodType != .unknown {
                        Text(member.bloodType.rawValue)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if !member.chronicConditions.isEmpty {
                    Text(member.chronicConditions.joined(separator: "、"))
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var avatarView: some View {
        if let data = member.avatarData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .clipShape(Circle())
        } else {
            Circle()
                .fill(avatarColor)
                .overlay {
                    Text(String(member.name.prefix(1)))
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                }
        }
    }

    private var avatarColor: Color {
        switch member.gender {
        case .male: return .blue
        case .female: return .pink
        case .other: return .purple
        }
    }
}

// MARK: - Preview

#Preview {
    FamilyListView()
        .modelContainer(MockData.previewContainer)
}
