//
//  HuckApp.swift
//  HuckUITests
//

import XCTest

/// Launching the app the way UI tests need it, and the gestures and
/// navigation they share.
extension XCUIApplication {
    /// The app over its bundled fixtures, so nothing touches the network.
    @MainActor
    static func launchedWithFixtures() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-HuckFixtures"]
        app.launch()
        return app
    }

    /// Searches Users for `username` and opens their profile.
    @MainActor
    func openProfile(of username: String) {
        tabBars.buttons["Search"].tap()
        let field = searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText(username + "\n")
        let users = buttons["Users"]
        XCTAssertTrue(users.waitForExistence(timeout: 10))
        users.tap()
        let result = staticTexts[username].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 15))
        result.tap()
    }

    /// Drags the content up by `distance`, holding before lifting so it stops
    /// where the drag ends rather than flinging on.
    @MainActor
    func scrollUp(by distance: CGFloat) {
        let start = windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
        let end = start.withOffset(CGVector(dx: 0, dy: -distance))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.5)
    }

    /// Flicks the content up, for getting a long way down a list.
    @MainActor
    func flickUp() {
        let start = windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
        let end = start.withOffset(CGVector(dx: 0, dy: -600))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0)
    }

    /// Goes back one level in the current navigation stack.
    @MainActor
    func goBack() {
        navigationBars.buttons.element(boundBy: 0).tap()
    }

    /// Lets in-flight work settle — a recording session's fetches, say — for
    /// up to `seconds`.
    func pause(_ seconds: TimeInterval) {
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "pause")], timeout: seconds)
    }
}
