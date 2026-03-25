import XCTest
import SwiftData
@testable import AIHealthVault

/// DailyPlan 模型单元测试
/// 覆盖：CRUD、isToday 计算属性、toggleAction 业务逻辑、与 Member 的关联关系
@MainActor
final class DailyPlanTests: SwiftDataTestCase {

    // MARK: - CRUD

    func testCreate_dailyPlan_savesSuccessfully() throws {
        let plan = TestFixtures.makeDailyPlan()
        try insertAndSave(plan)

        let fetched = try fetchAll(DailyPlan.self)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertFalse(fetched.first?.content.isEmpty ?? true)
    }

    func testCreate_multiplePlans_allPersist() throws {
        let dates = [
            Calendar.current.date(byAdding: .day, value: -2, to: Date())!,
            Calendar.current.date(byAdding: .day, value: -1, to: Date())!,
            Date()
        ]
        for date in dates {
            modelContext.insert(TestFixtures.makeDailyPlan(planDate: date))
        }
        try modelContext.save()

        XCTAssertEqual(try fetchAll(DailyPlan.self).count, 3)
    }

    func testUpdate_content_persists() throws {
        let plan = TestFixtures.makeDailyPlan(content: "旧内容")
        try insertAndSave(plan)

        plan.content = "更新后的计划内容"
        try modelContext.save()

        XCTAssertEqual(try fetchAll(DailyPlan.self).first?.content, "更新后的计划内容")
    }

    func testDelete_dailyPlan_removesFromDatabase() throws {
        let plan = TestFixtures.makeDailyPlan()
        try insertAndSave(plan)

        modelContext.delete(plan)
        try modelContext.save()

        XCTAssertTrue(try fetchAll(DailyPlan.self).isEmpty)
    }

    // MARK: - 默认值

    func testInit_id_isUnique() {
        let p1 = DailyPlan(content: "计划A")
        let p2 = DailyPlan(content: "计划B")
        XCTAssertNotEqual(p1.id, p2.id)
    }

    func testInit_completedActions_isEmpty() {
        let plan = DailyPlan(content: "任何内容")
        XCTAssertTrue(plan.completedActions.isEmpty, "新建计划不应有已完成行动")
    }

    func testInit_planDate_isStartOfDay() {
        let plan = DailyPlan(content: "计划")
        let startOfDay = Calendar.current.startOfDay(for: Date())
        XCTAssertEqual(plan.planDate, startOfDay,
                       "planDate 应被规范化为当天 00:00:00")
    }

    func testInit_planDate_customDate_isNormalizedToStartOfDay() {
        let noonYesterday = Calendar.current.date(
            from: DateComponents(year: 2026, month: 3, day: 25, hour: 12, minute: 30)
        )!
        let plan = DailyPlan(planDate: noonYesterday, content: "计划")
        let expected = Calendar.current.startOfDay(for: noonYesterday)
        XCTAssertEqual(plan.planDate, expected, "planDate 应始终为当天 00:00:00，不含时分秒")
    }

    func testInit_generatedAt_isRecentTimestamp() {
        let before = Date()
        let plan = DailyPlan(content: "计划")
        let after = Date()
        XCTAssertGreaterThanOrEqual(plan.generatedAt, before)
        XCTAssertLessThanOrEqual(plan.generatedAt, after)
    }

    func testInit_createdAt_isRecentTimestamp() {
        let before = Date()
        let plan = DailyPlan(content: "计划")
        let after = Date()
        XCTAssertGreaterThanOrEqual(plan.createdAt, before)
        XCTAssertLessThanOrEqual(plan.createdAt, after)
    }

    // MARK: - isToday

    func testIsToday_planDateIsToday_returnsTrue() {
        let plan = DailyPlan(planDate: Date(), content: "今日计划")
        XCTAssertTrue(plan.isToday, "planDate 为今天时 isToday 应为 true")
    }

    func testIsToday_planDateIsYesterday_returnsFalse() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let plan = DailyPlan(planDate: yesterday, content: "昨日计划")
        XCTAssertFalse(plan.isToday, "planDate 为昨天时 isToday 应为 false")
    }

    func testIsToday_planDateIsTomorrow_returnsFalse() {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let plan = DailyPlan(planDate: tomorrow, content: "明日计划")
        XCTAssertFalse(plan.isToday, "planDate 为明天时 isToday 应为 false")
    }

    // MARK: - toggleAction

    func testToggleAction_addNewAction_appendsToList() {
        let plan = DailyPlan(content: "计划")
        plan.toggleAction("morning_walk")
        XCTAssertTrue(plan.completedActions.contains("morning_walk"))
    }

    func testToggleAction_existingAction_removesFromList() {
        let plan = DailyPlan(content: "计划")
        plan.toggleAction("take_medicine")
        plan.toggleAction("take_medicine")  // 再次切换 → 移除
        XCTAssertFalse(plan.completedActions.contains("take_medicine"),
                       "第二次 toggle 应将已完成的行动移出列表")
    }

    func testToggleAction_isIdempotentForAddThenRemoveThenAdd() {
        let plan = DailyPlan(content: "计划")
        plan.toggleAction("drink_water")   // 添加
        plan.toggleAction("drink_water")   // 移除
        plan.toggleAction("drink_water")   // 再添加
        XCTAssertTrue(plan.completedActions.contains("drink_water"),
                      "三次 toggle（奇数次）后行动应在列表中")
    }

    func testToggleAction_multipleActions_trackedIndependently() {
        let plan = DailyPlan(content: "计划")
        plan.toggleAction("walk")
        plan.toggleAction("medicine")
        plan.toggleAction("walk")  // 移除 walk

        XCTAssertFalse(plan.completedActions.contains("walk"))
        XCTAssertTrue(plan.completedActions.contains("medicine"))
    }

    func testToggleAction_completedActions_count() {
        let plan = DailyPlan(content: "计划")
        plan.toggleAction("a")
        plan.toggleAction("b")
        plan.toggleAction("c")
        XCTAssertEqual(plan.completedActions.count, 3)

        plan.toggleAction("b")
        XCTAssertEqual(plan.completedActions.count, 2)
    }

    func testToggleAction_persistsAfterSave() throws {
        let plan = TestFixtures.makeDailyPlan()
        try insertAndSave(plan)

        plan.toggleAction("step_goal")
        try modelContext.save()

        let fetched = try fetchAll(DailyPlan.self).first
        XCTAssertTrue(fetched?.completedActions.contains("step_goal") ?? false,
                      "toggleAction 结果应在保存后持久化")
    }

    // MARK: - 与 Member 的关联关系

    func testDailyPlan_associatesWithMember() throws {
        let member = TestFixtures.makeMember()
        modelContext.insert(member)

        let plan = TestFixtures.makeDailyPlan()
        plan.member = member
        modelContext.insert(plan)
        try modelContext.save()

        let fetched = try fetchAll(DailyPlan.self).first
        XCTAssertNotNil(fetched?.member)
        XCTAssertEqual(fetched?.member?.name, "测试用户")
    }

    func testDailyPlan_memberIsNilByDefault() {
        let plan = TestFixtures.makeDailyPlan()
        XCTAssertNil(plan.member)
    }

    func testMember_cascadeDelete_removesDailyPlans() throws {
        let member = TestFixtures.makeMember()
        modelContext.insert(member)

        let plan = TestFixtures.makeDailyPlan()
        plan.member = member
        modelContext.insert(plan)
        try modelContext.save()

        modelContext.delete(member)
        try modelContext.save()

        XCTAssertTrue(try fetchAll(DailyPlan.self).isEmpty,
                      "删除 Member 后，关联的 DailyPlan 应被级联删除")
    }
}
