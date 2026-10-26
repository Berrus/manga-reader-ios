import Foundation
import SwiftData

@Model
final class Category {
    @Attribute(.unique) var id: UUID
    var name: String
    var order: Int

    init(name: String, order: Int) {
        self.id = UUID()
        self.name = name
        self.order = order
    }
}
