import XCTest
import SwiftData
@testable import AIHealthVault

/// 所有 SwiftData 单测的基类
/// 每个测试方法使用独立的内存数据库，确保测试间完全隔离
@MainActor
class SwiftDataTestCase: XCTestCase {

    var modelContainer: ModelContainer!
    var modelContext: ModelContext!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let schema = Schema([
            Family.self,
            Member.self,
            MedicalHistory.self,
            Medication.self,
            CheckupReport.self,
            VisitRecord.self,
            WearableEntry.self,
            DailyLog.self,
            CustomReminder.self,
            TermCacheItem.self,
            DailyPlan.self,
            CachedVisitPrep.self,
        ])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        modelContainer = try ModelContainer(for: schema, configurations: [config])
        modelContext = ModelContext(modelContainer)
    }

    override func tearDownWithError() throws {
        modelContainer = nil
        modelContext = nil
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    /// 插入并保存单个对象
    func insertAndSave<T: PersistentModel>(_ object: T) throws {
        modelContext.insert(object)
        try modelContext.save()
    }

    /// 获取所有指定类型的对象
    func fetchAll<T: PersistentModel>(_ type: T.Type) throws -> [T] {
        try modelContext.fetch(FetchDescriptor<T>())
    }
}
