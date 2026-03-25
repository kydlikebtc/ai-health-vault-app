import SwiftUI
import SwiftData
import UserNotifications

// MARK: - 随访日历视图

struct FollowUpCalendarView: View {
    @Query(sort: \Member.name) private var members: [Member]
    @Environment(\.dismiss) private var dismiss

    @State private var selectedMonth = Date()
    @State private var notificationGranted: Bool = false
    @State private var showNotifDeniedAlert = false

    private var upcomingVisits: [(member: Member, visit: VisitRecord)] {
        members.flatMap { member in
            member.visits
                .filter { v in
                    guard let d = v.followUpDate else { return false }
                    return d >= Calendar.current.startOfDay(for: Date())
                }
                .map { (member, $0) }
        }
        .sorted { a, b in
            (a.visit.followUpDate ?? Date()) < (b.visit.followUpDate ?? Date())
        }
    }

    private var visitsInSelectedMonth: [(member: Member, visit: VisitRecord)] {
        upcomingVisits.filter { pair in
            guard let d = pair.visit.followUpDate else { return false }
            return Calendar.current.isDate(d, equalTo: selectedMonth, toGranularity: .month)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                monthNavigator
                    .padding()
                Divider()
                content
            }
            .navigationTitle("随访日历")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await requestNotifications() }
                    } label: {
                        Image(systemName: notificationGranted ? "bell.fill" : "bell.slash")
                            .foregroundStyle(notificationGranted ? .orange : .secondary)
                    }
                }
            }
            .alert("通知权限被拒绝", isPresented: $showNotifDeniedAlert) {
                Button("去设置") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("请在「设置 > AI Health Vault > 通知」中开启通知权限以接收复诊提醒。")
            }
            .task {
                let settings = await UNUserNotificationCenter.current().notificationSettings()
                notificationGranted = settings.authorizationStatus == .authorized
            }
        }
    }

    // MARK: - 月份导航

    private var monthNavigator: some View {
        HStack {
            Button {
                selectedMonth = Calendar.current.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3)
            }
            Spacer()
            Text(selectedMonth, format: .dateTime.year().month(.wide))
                .font(.headline)
            Spacer()
            Button {
                selectedMonth = Calendar.current.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3)
            }
        }
    }

    // MARK: - 主体内容

    @ViewBuilder
    private var content: some View {
        if upcomingVisits.isEmpty {
            ContentUnavailableView(
                "暂无复诊安排",
                systemImage: "calendar.badge.clock",
                description: Text("在「就医记录」中添加复诊日期后，会在这里显示")
            )
        } else {
            List {
                // 本月
                let thisMonth = visitsInSelectedMonth
                if !thisMonth.isEmpty {
                    Section("本月复诊（\(thisMonth.count) 项）") {
                        ForEach(thisMonth, id: \.visit.id) { pair in
                            FollowUpRow(member: pair.member, visit: pair.visit)
                        }
                    }
                } else {
                    Section {
                        Text("本月暂无复诊安排")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                }

                // 全部未来
                let others = upcomingVisits.filter { pair in
                    !Calendar.current.isDate(
                        pair.visit.followUpDate ?? Date(),
                        equalTo: selectedMonth,
                        toGranularity: .month
                    )
                }
                if !others.isEmpty {
                    Section("其他待复诊（\(others.count) 项）") {
                        ForEach(others.prefix(20), id: \.visit.id) { pair in
                            FollowUpRow(member: pair.member, visit: pair.visit)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    // MARK: - 请求通知权限

    private func requestNotifications() async {
        let granted = await FollowUpNotificationService.shared.requestAuthorization()
        if granted {
            notificationGranted = true
            // 批量同步所有成员的随访通知
            for member in members {
                await FollowUpNotificationService.shared.syncNotifications(
                    for: member.visits,
                    memberName: member.name
                )
            }
        } else {
            showNotifDeniedAlert = true
        }
    }
}

// MARK: - 随访行

private struct FollowUpRow: View {
    let member: Member
    let visit: VisitRecord

    private var daysUntil: Int {
        guard let d = visit.followUpDate else { return 0 }
        return Calendar.current.dateComponents([.day], from: Date(), to: d).day ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle()
                    .fill(member.gender == .female ? Color.pink : .blue)
                    .frame(width: 28, height: 28)
                    .overlay {
                        Text(String(member.name.prefix(1)))
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                    }
                Text(member.name)
                    .font(.subheadline.bold())
                Spacer()
                urgencyBadge
            }

            if let d = visit.followUpDate {
                Label(d.localizedDateString, systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !visit.hospitalName.isEmpty {
                Label("\(visit.hospitalName)\(visit.department.isEmpty ? "" : " · \(visit.department)")",
                      systemImage: "building.2")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !visit.diagnosis.isEmpty {
                Text("诊断：\(visit.diagnosis)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var urgencyBadge: some View {
        let days = daysUntil
        let (text, color): (String, Color) = {
            if days <= 0 { return ("今天", .red) }
            if days == 1 { return ("明天", .orange) }
            if days <= 7 { return ("\(days)天后", .yellow) }
            return ("\(days)天后", .secondary)
        }()
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
