import Foundation
import SwiftData

@Model
final class Category {
    @Attribute(.unique) var id: UUID
    var name: String
    var order: Int
    /// Series in a private category are hidden until the user unlocks with Face ID, Touch ID or the device passcode.
    var isPrivate: Bool = false

    init(name: String, order: Int) {
        self.id = UUID()
        self.name = name
        self.order = order
    }
}
