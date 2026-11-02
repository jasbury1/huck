//
//  LaunchTests.swift
//  HuckUITests
//

import XCTest

/// A smoke test: the app launches and shows its tab bar. UI tests need the
/// network, so CI runs only the unit tests; run these with `make test-ui`.
final class LaunchTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchShowsTheTabBar() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
    }
}
