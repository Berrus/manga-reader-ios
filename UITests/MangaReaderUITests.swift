import XCTest

final class MangaReaderUITests: XCTestCase {
    private func launch(mode: String = "paged", empty: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleInterfaceStyle", "Dark"]
        app.launchEnvironment["UI_TESTING"] = "1"
        app.launchEnvironment["READER_MODE"] = mode
        app.launchEnvironment["EMPTY_LIBRARY"] = empty ? "1" : "0"
        app.launch()
        return app
    }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func openSample(_ app: XCUIApplication) {
        let book = app.descendants(matching: .any).matching(identifier: "manga-Moonlit Express").firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 30), "Sample CBZ should import into library")
        book.tap()
        let start = app.buttons["resumeReading"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()
        XCTAssertTrue(app.staticTexts["readerPageCount"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.images["readerImage"].waitForExistence(timeout: 20), "Actual page image should decode")
    }

    func testLibraryAndPagedReader() {
        let app = launch()
        let book = app.descendants(matching: .any).matching(identifier: "manga-Moonlit Express").firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 30))
        screenshot("01-library")
        openSample(app)
        XCTAssertEqual(app.staticTexts["readerPageCount"].label, "1 / 4")
        XCTAssertFalse(app.buttons["Next chapter"].isEnabled)
        screenshot("02-paged-reader")
        let pageSlider = app.sliders["Page"]
        XCTAssertTrue(pageSlider.exists)
        pageSlider.adjust(toNormalizedSliderPosition: 1)
        let lastPage = NSPredicate(format: "label == %@", "4 / 4")
        expectation(for: lastPage, evaluatedWith: app.staticTexts["readerPageCount"])
        waitForExpectations(timeout: 10)
    }

    func testWebtoonReader() {
        let app = launch(mode: "webtoon")
        let book = app.descendants(matching: .any).matching(identifier: "manga-Moonlit Express").firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 30))
        book.tap()
        app.buttons["resumeReading"].tap()
        XCTAssertTrue(app.staticTexts["readerPageCount"].waitForExistence(timeout: 10))
        // SwiftUI images expose the explicitly labelled loaded page.
        XCTAssertTrue(app.images["webtoonImage"].firstMatch.waitForExistence(timeout: 20))
        screenshot("03-webtoon-reader")
    }

    func testEmptyLibrary() {
        let app = launch(empty: true)
        XCTAssertTrue(app.staticTexts["Your library is empty"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Import"].exists)
        screenshot("04-empty-library")
    }
}
