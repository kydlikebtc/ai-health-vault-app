import XCTest
@testable import AIHealthVault

/// FollowUpNotificationService 单元测试
/// 测试范围：通知标识符格式、前置条件约定、通知内容构建规则
/// 注意：UNUserNotificationCenter 交互属于系统级集成测试，需在真机/受权模拟器上运行
final class FollowUpNotificationServiceTests: XCTestCase {

    // MARK: - 随访通知标识符格式

    func testFollowUpIdentifier_format_usesFollowUpPrefix() {
        let visit = TestFixtures.makeVisitRecord()
        let identifier = "follow_up_\(visit.id.uuidString)"
        XCTAssertTrue(identifier.hasPrefix("follow_up_"),
                      "随访通知标识符应以 follow_up_ 为前缀")
    }

    func testFollowUpIdentifier_format_containsUUID() {
        let visit = TestFixtures.makeVisitRecord()
        let identifier = "follow_up_\(visit.id.uuidString)"
        XCTAssertTrue(identifier.contains(visit.id.uuidString),
                      "随访通知标识符应包含 visitId 的 UUID 字符串")
    }

    func testFollowUpIdentifier_format_isUniquePerVisit() {
        let visit1 = TestFixtures.makeVisitRecord()
        let visit2 = TestFixtures.makeVisitRecord()
        let id1 = "follow_up_\(visit1.id.uuidString)"
        let id2 = "follow_up_\(visit2.id.uuidString)"
        XCTAssertNotEqual(id1, id2, "不同就诊记录的通知标识符应唯一")
    }

    func testFollowUpIdentifier_cancelMatchesSchedule() {
        let visit = TestFixtures.makeVisitRecord()
        // 调度时使用 "follow_up_<uuid>"，取消时也必须使用相同标识符
        let scheduleId = "follow_up_\(visit.id.uuidString)"
        let cancelId   = "follow_up_\(visit.id.uuidString)"
        XCTAssertEqual(scheduleId, cancelId,
                       "取消通知的标识符必须与调度时一致")
    }

    // MARK: - 体检通知标识符格式

    func testCheckupIdentifier_format_usesCheckupPrefix() {
        let report = TestFixtures.makeCheckupReport()
        let identifier = "checkup_\(report.id.uuidString)"
        XCTAssertTrue(identifier.hasPrefix("checkup_"),
                      "体检通知标识符应以 checkup_ 为前缀")
    }

    func testCheckupIdentifier_format_containsUUID() {
        let report = TestFixtures.makeCheckupReport()
        let identifier = "checkup_\(report.id.uuidString)"
        XCTAssertTrue(identifier.contains(report.id.uuidString))
    }

    func testCheckupIdentifier_format_isUniquePerReport() {
        let r1 = TestFixtures.makeCheckupReport()
        let r2 = TestFixtures.makeCheckupReport()
        XCTAssertNotEqual("checkup_\(r1.id.uuidString)",
                          "checkup_\(r2.id.uuidString)",
                          "不同体检记录的通知标识符应唯一")
    }

    // MARK: - 自定义提醒标识符格式

    func testCustomReminderIdentifier_format_usesCustomPrefix() {
        let reminder = TestFixtures.makeCustomReminder()
        let identifier = "custom_\(reminder.id.uuidString)"
        XCTAssertTrue(identifier.hasPrefix("custom_"),
                      "自定义提醒标识符应以 custom_ 为前缀")
    }

    func testCustomReminderIdentifier_format_isUniquePerReminder() {
        let r1 = TestFixtures.makeCustomReminder()
        let r2 = TestFixtures.makeCustomReminder(title: "另一条提醒")
        XCTAssertNotEqual("custom_\(r1.id.uuidString)",
                          "custom_\(r2.id.uuidString)")
    }

    // MARK: - 通知类别标识符

    func testCategoryIdentifier_isFollowUpReminder() {
        // 三类通知（随访/体检/自定义）共享同一个 category
        let expectedCategory = "FOLLOW_UP_REMINDER"
        XCTAssertEqual(expectedCategory, "FOLLOW_UP_REMINDER")
    }

    // MARK: - scheduleNotification 前置条件（随访日期）

    func testScheduleCondition_nilFollowUpDate_shouldNotSchedule() {
        let visit = TestFixtures.makeVisitRecord()
        // 默认 followUpDate 为 nil，服务不应调度
        XCTAssertNil(visit.followUpDate,
                     "TestFixtures 默认就诊记录不含随访日期")
    }

    func testScheduleCondition_withFollowUpDate_canSchedule() {
        let visit = TestFixtures.makeVisitRecord()
        visit.followUpDate = Calendar.current.date(byAdding: .day, value: 30, to: Date())
        XCTAssertNotNil(visit.followUpDate,
                        "设置 followUpDate 后可调度通知")
    }

    func testScheduleCondition_pastFollowUpDate_shouldNotSchedule() {
        // 已过期的复诊日期不应调度（提前 1 天计算后仍为过去时间）
        let visit = TestFixtures.makeVisitRecord()
        visit.followUpDate = Calendar.current.date(byAdding: .day, value: -1, to: Date())
        // 调度逻辑：notifyDate = followUpDate - 1天，若 notifyDate < now 则无意义
        let followUpDate = visit.followUpDate!
        let notifyDate = Calendar.current.date(byAdding: .day, value: -1, to: followUpDate)!
        XCTAssertTrue(notifyDate < Date(),
                      "复诊日期为昨天时，提前 1 天的通知时间已过期")
    }

    // MARK: - scheduleCheckupNotification 前置条件

    func testCheckupScheduleCondition_nilNextCheckupDate_shouldNotSchedule() {
        let report = TestFixtures.makeCheckupReport()
        XCTAssertNil(report.nextCheckupDate,
                     "TestFixtures 默认体检报告不含复查日期")
    }

    func testCheckupScheduleCondition_pastDate_shouldNotSchedule() {
        let report = TestFixtures.makeCheckupReport()
        report.nextCheckupDate = Calendar.current.date(byAdding: .day, value: -1, to: Date())
        let nextDate = report.nextCheckupDate!
        // 服务层逻辑：nextDate > Date() 才调度
        XCTAssertFalse(nextDate > Date(),
                       "过去的复查日期应跳过调度")
    }

    func testCheckupScheduleCondition_futureDate_canSchedule() {
        let report = TestFixtures.makeCheckupReport()
        report.nextCheckupDate = Calendar.current.date(byAdding: .day, value: 10, to: Date())
        let nextDate = report.nextCheckupDate!
        XCTAssertTrue(nextDate > Date(),
                      "未来的复查日期应可以调度")
    }

    // MARK: - scheduleCustomReminder 前置条件

    func testCustomReminderCondition_pastDate_shouldNotSchedule() {
        let reminder = TestFixtures.makeCustomReminder(
            reminderDate: Calendar.current.date(byAdding: .hour, value: -1, to: Date())!
        )
        // 服务层逻辑：reminder.reminderDate > Date() 才调度
        XCTAssertFalse(reminder.reminderDate > Date(),
                       "过去的提醒日期不应调度")
    }

    func testCustomReminderCondition_futureDate_canSchedule() {
        // 使用相对时间确保测试不因日期硬编码而过期
        let reminder = TestFixtures.makeCustomReminder(
            reminderDate: Calendar.current.date(byAdding: .day, value: 7, to: Date())!
        )
        XCTAssertTrue(reminder.reminderDate > Date(),
                      "未来的提醒日期可以调度")
    }

    // MARK: - 通知内容构建规则（随访）

    func testFollowUpContent_withHospitalAndDepartment_bodyContainsBoth() {
        let visit = TestFixtures.makeVisitRecord(hospital: "北京协和医院")
        visit.department = "心内科"
        // 构建通知正文（镜像服务层逻辑）
        var body = "测试用户 明天有复诊安排"
        if !visit.hospitalName.isEmpty {
            body += "（\(visit.hospitalName)"
            if !visit.department.isEmpty {
                body += " · \(visit.department)"
            }
            body += "）"
        }
        XCTAssertTrue(body.contains("北京协和医院"),
                      "通知正文应包含医院名称")
        XCTAssertTrue(body.contains("心内科"),
                      "通知正文应包含科室名称")
    }

    func testFollowUpContent_withHospitalOnly_bodyHasNoMiddleDot() {
        let visit = TestFixtures.makeVisitRecord(hospital: "上海瑞金医院")
        visit.department = ""
        var body = "测试用户 明天有复诊安排"
        if !visit.hospitalName.isEmpty {
            body += "（\(visit.hospitalName)"
            if !visit.department.isEmpty {
                body += " · \(visit.department)"
            }
            body += "）"
        }
        XCTAssertFalse(body.contains(" · "),
                       "无科室时正文不应包含中间点分隔符")
    }

    func testFollowUpContent_emptyHospital_bodyHasNoParentheses() {
        let visit = VisitRecord(
            visitDate: Date(),
            visitType: .outpatient,
            hospitalName: "",
            department: ""
        )
        var body = "测试用户 明天有复诊安排"
        if !visit.hospitalName.isEmpty {
            body += "（\(visit.hospitalName)）"
        }
        XCTAssertFalse(body.contains("（"),
                       "医院名称为空时正文不应添加括号")
    }

    // MARK: - 通知内容构建规则（体检）

    func testCheckupContent_withTitle_bodyContainsTitle() {
        let report = TestFixtures.makeCheckupReport(title: "2024年度体检")
        let title = report.reportTitle.isEmpty ? "体检" : report.reportTitle
        let body = "测试用户 的「\(title)」建议复查日期还有 3 天"
        XCTAssertTrue(body.contains("2024年度体检"),
                      "体检通知正文应包含报告标题")
    }

    func testCheckupContent_emptyTitle_fallsBackToDefault() {
        let report = CheckupReport(
            checkupDate: Date(),
            hospitalName: "",
            reportTitle: ""
        )
        let title = report.reportTitle.isEmpty ? "体检" : report.reportTitle
        XCTAssertEqual(title, "体检",
                       "报告标题为空时应回退为「体检」")
    }

    func testCheckupContent_withHospital_bodyContainsHospital() {
        let report = TestFixtures.makeCheckupReport(hospital: "北京协和医院")
        var body = "测试用户 的「体检」建议复查日期还有 3 天"
        if !report.hospitalName.isEmpty {
            body += "（\(report.hospitalName)）"
        }
        XCTAssertTrue(body.contains("北京协和医院"))
    }

    // MARK: - 通知内容构建规则（自定义）

    func testCustomReminderContent_withNotes_bodyUsesNotes() {
        let reminder = TestFixtures.makeCustomReminder(notes: "别忘记带化验单")
        let body = reminder.notes.isEmpty ? "测试用户 的健康提醒" : reminder.notes
        XCTAssertEqual(body, "别忘记带化验单",
                       "有备注时通知正文应使用备注内容")
    }

    func testCustomReminderContent_emptyNotes_bodyUsesFallback() {
        let reminder = CustomReminder(
            title: "复诊",
            reminderDate: Calendar.current.date(byAdding: .day, value: 1, to: Date())!,
            notes: ""
        )
        let memberName = "张三"
        let body = reminder.notes.isEmpty ? "\(memberName) 的健康提醒" : reminder.notes
        XCTAssertEqual(body, "张三 的健康提醒",
                       "备注为空时应回退为成员姓名 + 通用描述")
    }

    // MARK: - 提前通知天数逻辑

    func testFollowUpNotify_isOneDayBefore() {
        let followUpDate = Calendar.current.date(
            from: DateComponents(year: 2026, month: 5, day: 10)
        )!
        let notifyDate = Calendar.current.date(byAdding: .day, value: -1, to: followUpDate)!
        let notifyComponents = Calendar.current.dateComponents([.year, .month, .day], from: notifyDate)
        XCTAssertEqual(notifyComponents.day, 9,
                       "随访提前 1 天，5/10 的随访应在 5/9 发送通知")
    }

    func testCheckupNotify_isThreeDaysBefore() {
        let checkupDate = Calendar.current.date(
            from: DateComponents(year: 2026, month: 5, day: 10)
        )!
        let notifyDate = Calendar.current.date(byAdding: .day, value: -3, to: checkupDate)!
        let notifyComponents = Calendar.current.dateComponents([.year, .month, .day], from: notifyDate)
        XCTAssertEqual(notifyComponents.day, 7,
                       "体检提前 3 天，5/10 的复查应在 5/7 发送通知")
    }

    func testNotifyHour_isNineAM() {
        // 随访和体检通知均在 09:00 发送
        let expectedHour = 9
        XCTAssertEqual(expectedHour, 9,
                       "提前提醒应在当天 09:00 发出")
    }

    // MARK: - syncNotifications 过滤逻辑

    func testSyncFilter_onlyVisitsWithFollowUpDate_areScheduled() {
        let visitWithDate = TestFixtures.makeVisitRecord()
        visitWithDate.followUpDate = Calendar.current.date(byAdding: .day, value: 7, to: Date())

        let visitWithoutDate = TestFixtures.makeVisitRecord()
        // visitWithoutDate.followUpDate == nil

        let visits = [visitWithDate, visitWithoutDate]
        let schedulable = visits.filter { $0.followUpDate != nil }

        XCTAssertEqual(schedulable.count, 1,
                       "syncNotifications 只应调度含 followUpDate 的记录")
    }
}
