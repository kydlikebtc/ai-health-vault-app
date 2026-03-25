import SwiftUI
import SwiftData
import UserNotifications

// MARK: - 统一日历条目模型

private enum CalendarItem: Identifiable {
    case visitFollowUp(member: Member, visit: VisitRecord)
    case checkupReview(member: Member, checkup: CheckupReport)
    case customReminder(member: Member, reminder: CustomReminder)

    var id: String {
        switch self {
        case .visitFollowUp(_, let v):  return "v_\(v.id)"
        case .checkupReview(_, let c):  return "c_\(c.id)"
        case .customReminder(_, let r): return "r_\(r.id)"
        }
    }

    var date: Date {
        switch self {
        case .visitFollowUp(_, let v):  return v.followUpDate ?? Date()
        case .checkupReview(_, let c):  return c.nextCheckupDate ?? Date()
        case .customReminder(_, let r): return r.reminderDate
        }
    }

    var member: Member {
        switch self {
        case .visitFollowUp(let m, _):  return m
        case .checkupReview(let m, _):  return m
        case .customReminder(let m, _): return m
        }
    }
}

// MARK: - 随访日历视图

struct FollowUpCalendarView: View {
    @Query(sort: \Member.name) private var members: [Member]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var selectedMonth = Date()
    @State private var notificationGranted = false
    @State private var showNotifDeniedAlert = false
    @State private var showingAddReminder = false

    // MARK: - 聚合所有待办条目

    private var allUpcomingItems: [CalendarItem] {
        let now = Calendar.current.startOfDay(for: Date())
        var items: [CalendarItem] = []
        for member in members {
            for visit in member.visits where (visit.followUpDate ?? .distantPast) >= now {
                items.append(.visitFollowUp(member: member, visit: visit))
            }
            for checkup in member.checkups {
                if let next = checkup.nextCheckupDate, next >= now {
                    items.append(.checkupReview(member: member, checkup: checkup))
                }
            }
            for reminder in member.customReminders where !reminder.isCompleted && reminder.reminderDate >= now {
                items.append(.customReminder(member: member, reminder: reminder))
            }
        }
        return items.sorted { $0.date < $1.date }
    }

    private var itemsInSelectedMonth: [CalendarItem] {
        allUpcomingItems.filter {
            Calendar.current.isDate($0.date, equalTo: selectedMonth, toGranularity: .month)
        }
    }

    private var itemsOutsideSelectedMonth: [CalendarItem] {
        allUpcomingItems.filter {
            !Calendar.current.isDate($0.date, equalTo: selectedMonth, toGranularity: .month)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                monthNavigator.padding()
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
                    HStack(spacing: 12) {
                        Button {
                            showingAddReminder = true
                        } label: {
                            Image(systemName: "plus.circle")
                        }
                        .accessibilityLabel("添加随访提醒")
                        Button {
                            Task { await requestNotifications() }
                        } label: {
                            Image(systemName: notificationGranted ? "bell.fill" : "bell.slash")
                                .foregroundStyle(notificationGranted ? .orange : .secondary)
                        }
                        .accessibilityLabel(notificationGranted ? "通知已开启" : "开启通知权限")
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
                Text("请在「设置 > AI Health Vault > 通知」中开启通知权限以接收提醒。")
            }
            .sheet(isPresented: $showingAddReminder) {
                AddCustomReminderView(members: members)
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
                Image(systemName: "chevron.left").font(.title3)
            }
            Spacer()
            Text(selectedMonth, format: .dateTime.year().month(.wide))
                .font(.headline)
            Spacer()
            Button {
                selectedMonth = Calendar.current.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
            } label: {
                Image(systemName: "chevron.right").font(.title3)
            }
        }
    }

    // MARK: - 主体内容

    @ViewBuilder
    private var content: some View {
        if allUpcomingItems.isEmpty {
            ContentUnavailableView(
                "暂无待办提醒",
                systemImage: "calendar.badge.clock",
                description: Text("可在就医记录中设置复诊日期，或点击 + 添加自定义提醒")
            )
        } else {
            List {
                let thisMonth = itemsInSelectedMonth
                if !thisMonth.isEmpty {
                    Section("本月待办（\(thisMonth.count) 项）") {
                        ForEach(thisMonth) { item in
                            CalendarItemRow(item: item) { reminder in
                                completeCustomReminder(reminder)
                            }
                        }
                    }
                } else {
                    Section {
                        Text("本月暂无待办").foregroundStyle(.secondary).font(.subheadline)
                    }
                }

                let others = itemsOutsideSelectedMonth
                if !others.isEmpty {
                    Section("其他待办（\(others.count) 项）") {
                        ForEach(others.prefix(30)) { item in
                            CalendarItemRow(item: item) { reminder in
                                completeCustomReminder(reminder)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    // MARK: - 操作

    private func requestNotifications() async {
        let granted = await FollowUpNotificationService.shared.requestAuthorization()
        if granted {
            notificationGranted = true
            for member in members {
                await FollowUpNotificationService.shared.syncNotifications(
                    for: member.visits, memberName: member.name
                )
            }
        } else {
            showNotifDeniedAlert = true
        }
    }

    private func completeCustomReminder(_ reminder: CustomReminder) {
        reminder.isCompleted = true
        Task {
            await FollowUpNotificationService.shared.cancelCustomReminder(for: reminder.id)
        }
    }
}

// MARK: - 日历条目行

private struct CalendarItemRow: View {
    let item: CalendarItem
    let onComplete: (CustomReminder) -> Void

    private var daysUntil: Int {
        Calendar.current.dateComponents([.day], from: Date(), to: item.date).day ?? 0
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            typeIcon
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    memberLabel
                    Spacer()
                    urgencyBadge
                }
                dateLabel
                detailLabel
            }
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .trailing) {
            if case .customReminder(_, let reminder) = item {
                Button {
                    onComplete(reminder)
                } label: {
                    Label("完成", systemImage: "checkmark")
                }
                .tint(.green)
            }
        }
    }

    @ViewBuilder
    private var typeIcon: some View {
        let (iconName, color): (String, Color) = {
            switch item {
            case .visitFollowUp:  return ("stethoscope", .blue)
            case .checkupReview:  return ("cross.case.fill", .purple)
            case .customReminder: return ("bell.fill", .orange)
            }
        }()
        Image(systemName: iconName)
            .font(.title3)
            .foregroundStyle(color)
            .frame(width: 28)
    }

    private var memberLabel: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(item.member.gender == .female ? Color.pink : .blue)
                .frame(width: 22, height: 22)
                .overlay {
                    Text(String(item.member.name.prefix(1)))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                }
            Text(itemTitle)
                .font(.subheadline.bold())
        }
    }

    private var itemTitle: String {
        switch item {
        case .visitFollowUp(let m, let v):
            return v.hospitalName.isEmpty ? "\(m.name) 复诊" : v.hospitalName
        case .checkupReview(_, let c):
            return c.reportTitle.isEmpty ? "建议复查" : "复查：\(c.reportTitle)"
        case .customReminder(_, let r):
            return r.title
        }
    }

    private var dateLabel: some View {
        Label(item.date.localizedDateString, systemImage: "calendar")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var detailLabel: some View {
        switch item {
        case .visitFollowUp(_, let v) where !v.department.isEmpty:
            Label(v.department, systemImage: "building.2")
                .font(.caption).foregroundStyle(.secondary)
        case .checkupReview(_, let c) where !c.hospitalName.isEmpty:
            Label(c.hospitalName, systemImage: "building.2")
                .font(.caption).foregroundStyle(.secondary)
        case .customReminder(_, let r) where !r.notes.isEmpty:
            Text(r.notes).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        default:
            EmptyView()
        }
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

// MARK: - 添加自定义提醒

struct AddCustomReminderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let members: [Member]

    @State private var title = ""
    @State private var selectedMember: Member?
    @State private var reminderDate = Date().addingTimeInterval(3600)
    @State private var notes = ""
    @State private var showingValidationError = false

    var body: some View {
        NavigationStack {
            Form {
                Section("提醒信息") {
                    HStack {
                        Text("标题")
                        Spacer()
                        TextField("如：复查血糖", text: $title)
                            .multilineTextAlignment(.trailing)
                    }
                    DatePicker(
                        "提醒时间",
                        selection: $reminderDate,
                        in: Date()...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }

                Section("关联成员（可选）") {
                    Picker("成员", selection: $selectedMember) {
                        Text("不关联").tag(Optional<Member>.none)
                        ForEach(members) { member in
                            Text(member.name).tag(Optional(member))
                        }
                    }
                }

                Section("备注") {
                    TextField("备注...", text: $notes, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }
            }
            .navigationTitle("添加提醒")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("添加") { saveReminder() }
                        .fontWeight(.semibold)
                }
            }
            .alert("请检查输入", isPresented: $showingValidationError) {
                Button("好的") {}
            } message: {
                Text("提醒标题不能为空")
            }
            .onAppear {
                selectedMember = members.first
            }
        }
    }

    private func saveReminder() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            showingValidationError = true
            return
        }
        let reminder = CustomReminder(
            title: trimmed,
            reminderDate: reminderDate,
            notes: notes.trimmingCharacters(in: .whitespaces)
        )
        reminder.member = selectedMember
        modelContext.insert(reminder)

        let memberName = selectedMember?.name ?? "用户"
        Task {
            await FollowUpNotificationService.shared.scheduleCustomReminder(reminder, memberName: memberName)
        }
        dismiss()
    }
}
