//
//  FixtureRecording.swift
//  HuckUITests
//

import XCTest

/// Records the fixtures the other UI tests replay, by driving the app over
/// the real network with recording on. Not a test: it's skipped unless
/// `HUCK_RECORD_FIXTURES` is set, which `scripts/record-fixtures.sh` does
/// before copying the recording into `Huck/Fixtures.bundle`.
///
/// Everything a replayed test does must have been done here first, or its
/// requests find no fixture. So when a UI test starts going somewhere new,
/// add the trip to this scenario and re-record.
final class FixtureRecording: XCTestCase {
    @MainActor
    func testRecordFixtures() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["HUCK_RECORD_FIXTURES"] == "1",
            "Records fixtures over the network. Run scripts/record-fixtures.sh."
        )
        continueAfterFailure = true

        let app = XCUIApplication()
        app.launchArguments = ["-HuckRecordFixtures"]
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 15))

        // The launch warm-up: the main feeds' lists and most of their stories.
        app.pause(20)

        // The front page's first stories' threads, then a few screens down.
        // The Feed tab opens on its list of feeds.
        app.staticTexts["Top Stories"].firstMatch.tapIfPresent()
        app.pause(3)
        let threads = app.buttons.matching(identifier: "story.comments")
        for index in 0..<3 where threads.element(boundBy: index).waitForExistence(timeout: 5) {
            threads.element(boundBy: index).tap()
            app.pause(6)
            app.flickUp()
            app.pause(2)
            app.goBack()
            app.pause(1)
        }
        for _ in 0..<3 { app.flickUp() }
        app.pause(3)

        // The signed-out Account page.
        app.tabBars.buttons["Account"].tap()
        app.pause(3)

        // A profile with a long history: several pages of posts and comments.
        app.openProfile(of: "pg")
        app.pause(5)

        // Their public favorites, a news.ycombinator.com page.
        let favorites = app.buttons["Favorites"]
        if favorites.waitForExistence(timeout: 5) {
            favorites.tap()
            app.pause(6)
            app.goBack()
            app.pause(1)
        }
        for _ in 0..<6 {
            app.flickUp()
            app.pause(1.5)
        }
        app.buttons["Comments"].tap()
        app.pause(3)
        for _ in 0..<6 {
            app.flickUp()
            app.pause(1.5)
        }

        // Story and comment search.
        app.tabBars.buttons["Search"].tap()
        let field = app.searchFields.firstMatch
        if field.waitForExistence(timeout: 5) {
            field.tap()
            field.buttons["Clear text"].firstMatch.tapIfPresent()
            field.typeText("swift\n")
            for tab in ["Stories", "Comments"] {
                app.buttons[tab].tapIfPresent()
                app.pause(4)
            }
        }
        app.pause(3)
    }
}

private extension XCUIElement {
    func tapIfPresent() {
        if exists { tap() }
    }
}
