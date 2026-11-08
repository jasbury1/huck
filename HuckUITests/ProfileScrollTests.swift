//
//  ProfileScrollTests.swift
//  HuckUITests
//

import XCTest

/// Guards the profile page's scrolling: its pinned tab bar, and the per-tab
/// scroll positions kept as you switch tabs. Like every UI test these need the
/// network, so they run with `make test-ui` rather than in CI.
final class ProfileScrollTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Holding a scroll right where the tab bar pins once froze the page in a
    /// layout feedback loop: pinning resized the scroll view, which unpinned
    /// the bar, which resized it back, forever. It took a finger held still at
    /// that point, so this holds a drag at each point around it, then checks
    /// the app still responds.
    ///
    /// Run it on a device: the loop has only ever reproduced on one. In the
    /// simulator (iOS 27.2) this passes even with the bug put back, because
    /// the scroll view's insets don't flip there.
    @MainActor
    func testHoldingAtThePinPointDoesNotFreeze() {
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Account"].tap()

        // The signed-out page offers only Recently Viewed; a profile, Posts.
        let recentlyViewed = app.buttons["Recently viewed"]
        XCTAssertTrue(recentlyViewed.waitForExistence(timeout: 10) || app.buttons["Posts"].waitForExistence(timeout: 10))
        let pill = recentlyViewed.exists ? recentlyViewed : app.buttons["Posts"]
        let navigationBar = app.navigationBars.firstMatch
        // How far the page scrolls before the bar pins under the nav bar.
        let pinDistance = pill.frame.minY - navigationBar.frame.maxY

        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        for overshoot in stride(from: -24.0, through: 24.0, by: 4.0) {
            // Each attempt starts from the top of the page, so it ends a known
            // distance down rather than adding to the last one.
            let top = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            top.press(forDuration: 0.05, thenDragTo: start, withVelocity: .fast, thenHoldForDuration: 0.3)
            let end = start.withOffset(CGVector(dx: 0, dy: -(pinDistance + overshoot)))
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 1)
        }

        // A frozen main thread can't switch tabs.
        app.tabBars.buttons["Feed"].tap()
        XCTAssertTrue(
            app.tabBars.buttons["Feed"].wait(for: \.isSelected, toEqual: true, timeout: 5),
            "The app stopped responding after holding a scroll at the tab bar's pin point."
        )
    }

    /// Switching tabs rebuilds the incoming list, which estimates the heights
    /// of rows it hasn't laid out, so restoring a saved offset once landed on
    /// different rows. Each tab must come back with its rows exactly where
    /// they were left.
    @MainActor
    func testSwitchingTabsKeepsEachTabsScrollPosition() throws {
        let app = XCUIApplication()
        app.launch()
        openProfile(of: "pg", in: app)

        let posts = app.buttons["Posts"]
        let comments = app.buttons["Comments"]
        XCTAssertTrue(posts.waitForExistence(timeout: 15))
        XCTAssertTrue(app.cells.firstMatch.waitForExistence(timeout: 15) || app.staticTexts.count > 10)

        // Pin the bar, with part of the list scrolled under it.
        scrollUp(app, by: 500)
        let leftPosts = try firstRow(below: posts, in: app)

        comments.tap()
        let pinnedY = posts.frame.minY
        // A tab never scrolled opens at its top, with the bar still pinned.
        XCTAssertEqual(posts.frame.minY, pinnedY, accuracy: 1)
        scrollUp(app, by: 300)
        let leftComments = try firstRow(below: posts, in: app)

        for _ in 0..<2 {
            posts.tap()
            try assertRow(leftPosts, isBackIn: app, below: posts)
            comments.tap()
            try assertRow(leftComments, isBackIn: app, below: posts)
        }
    }

    // MARK: - Helpers

    /// A text row: its label, and where its top sat.
    private struct Row {
        let label: String
        let minY: CGFloat
    }

    @MainActor
    private func openProfile(of username: String, in app: XCUIApplication) {
        app.tabBars.buttons["Search"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText(username + "\n")
        let users = app.buttons["Users"]
        XCTAssertTrue(users.waitForExistence(timeout: 10))
        users.tap()
        let result = app.staticTexts[username].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 15))
        result.tap()
    }

    @MainActor
    private func scrollUp(_ app: XCUIApplication, by distance: CGFloat) {
        let start = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
        let end = start.withOffset(CGVector(dx: 0, dy: -distance))
        // Held before lifting, so the list stops where the drag ends.
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.5)
    }

    /// The topmost title-length text that sits wholly below the tab bar —
    /// long enough to be unique, unlike a score or a timestamp.
    @MainActor
    private func firstRow(below pill: XCUIElement, in app: XCUIApplication) throws -> Row {
        let barBottom = pill.frame.maxY
        let screenBottom = app.windows.firstMatch.frame.maxY
        // Rows expose their text as buttons or static text, depending on
        // whether they're tappable.
        let texts = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label MATCHES %@", "(?s).{20,}"))
            .allElementsBoundByIndex
            .filter { $0.frame.minY > barBottom + 8 && $0.frame.maxY < screenBottom }
            .sorted { $0.frame.minY < $1.frame.minY }
        let first = try XCTUnwrap(texts.first, "No rows below the tab bar.")
        return Row(label: first.label, minY: first.frame.minY)
    }

    @MainActor
    private func assertRow(_ row: Row, isBackIn app: XCUIApplication, below pill: XCUIElement) throws {
        let text = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", row.label))
            .firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 5), "“\(row.label)” didn't come back.")
        XCTAssertEqual(text.frame.minY, row.minY, accuracy: 1, "“\(row.label)” came back in a different place.")
    }
}
