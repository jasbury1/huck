//
//  LaunchTests.swift
//  HuckUITests
//

import XCTest

/// A smoke test: the app launches over its fixtures and shows its tab bar.
final class LaunchTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchShowsTheTabBar() {
        let app = XCUIApplication.launchedWithFixtures()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
    }
}
