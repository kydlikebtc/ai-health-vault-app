import SwiftData
import Foundation

@Model
final class Family {
    var name: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Member.family)
    var members: [Member]

    init(name: String = "我的家庭") {
        self.name = name
        self.createdAt = Date()
        self.members = []
    }
}
