import XCTest

final class MangaReaderUITests: XCTestCase {
    private func launch(mode: String = "paged", empty: Bool = false, remoteNext: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleInterfaceStyle", "Dark"]
        app.launchEnvironment["UI_TESTING"] = "1"
        app.launchEnvironment["UI_TEST_REMOTE_NEXT"] = remoteNext ? "1" : "0"
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
    func testSettingsScreenLoads() {
        let app = launch(empty: true)
        let settings = app.buttons["Settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        let customSources = app.switches["Enable custom sources"]
        for _ in 0..<4 where !customSources.exists { app.swipeUp() }
        XCTAssertTrue(customSources.exists)
    }

    func testNextUndownloadedChapterRoutesToStreaming() {
        let app = launch(remoteNext: true)
        openSample(app)
        let next = app.buttons["Next chapter"]
        XCTAssertTrue(next.isEnabled)
        next.tap()
        XCTAssertTrue(app.staticTexts["Source unavailable"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Couldn't open this file."].exists)
    }

    func testBulkLibrarySelection() {
        let app = launch()
        XCTAssertTrue(app.buttons["librarySelection"].waitForExistence(timeout: 30))
        app.buttons["librarySelection"].tap()
        let book = app.buttons["select-Moonlit Express"]
        XCTAssertTrue(book.waitForExistence(timeout: 10))
        book.tap()
        XCTAssertEqual(app.staticTexts["librarySelectionCount"].label, "1 selected")
        screenshot("05-bulk-library-selection")
        app.buttons["librarySelection"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "manga-Moonlit Express").firstMatch.exists)
    }

    func testAutoscrollStopsWhenAppLeavesForeground() {
        let app = launch(mode: "webtoon")
        let book = app.descendants(matching: .any).matching(identifier: "manga-Moonlit Express").firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 30))
        book.tap()
        app.buttons["resumeReading"].tap()
        XCTAssertTrue(app.images["webtoonImage"].firstMatch.waitForExistence(timeout: 20))
        let control = app.buttons["readerAutoscroll"]
        XCTAssertTrue(control.waitForExistence(timeout: 10))
        control.tap()
        XCTAssertTrue(app.buttons["Pause autoscroll"].exists)
        screenshot("06-webtoon-autoscroll")
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["Start autoscroll"].waitForExistence(timeout: 10))
    }

    func testFeedAndUpdatesEmptyStates() {
        let app = launch(empty: true)
        let feed = app.buttons["Feed"].firstMatch
        XCTAssertTrue(feed.waitForExistence(timeout: 10))
        feed.tap()
        XCTAssertTrue(app.staticTexts["Build your feed"].waitForExistence(timeout: 10))
        screenshot("07-feed-empty")
        app.buttons["Settings"].firstMatch.tap()
        app.buttons["Updates"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["No updates yet"].waitForExistence(timeout: 10))
    }

    func testAppStoreSourceBoundaries() throws {
        #if APP_STORE
        let app = launch(empty: true)
        app.buttons["Browse"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Import your comics in Library, or add a personal Komga server in Settings."].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Online"].exists)
        XCTAssertFalse(app.staticTexts["MangaDex"].exists)
        app.buttons["Settings"].firstMatch.tap()
        let custom = app.switches["Enable custom sources"]
        for _ in 0..<4 where !custom.exists { app.swipeUp() }
        XCTAssertTrue(custom.exists)
        if (custom.value as? String) == "0" { custom.tap() }
        let repositories = app.buttons["Source repositories"]
        for _ in 0..<4 where !repositories.exists { app.swipeUp() }
        XCTAssertTrue(repositories.exists)
        XCTAssertTrue(app.buttons["Servers"].firstMatch.exists)
        screenshot("08-app-store-personal-library")
        #else
        throw XCTSkip("Only the AppStore configuration excludes built-in public providers.")
        #endif
    }

}
