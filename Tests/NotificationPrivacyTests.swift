import XCTest
@testable import MangaReader

final class NotificationPrivacyTests: XCTestCase {
    func testDefaultNotificationDoesNotExposeTitle() {
        let message = UpdateNoticeText.body(count: 3, title: "Private reading title", showDetails: false)
        XCTAssertFalse(message.contains("Private"))
        XCTAssertEqual(message, "3 new chapters in your library.")
    }
    func testDetailsAreExplicitAndBounded() {
        let message = UpdateNoticeText.body(count: 1, title: String(repeating: "x", count: 1000), showDetails: true)
        XCTAssertTrue(message.hasSuffix("1 new chapter in your library."))
        XCTAssertLessThan(message.count, 200)
    }
}
