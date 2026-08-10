import XCTest

/// UI coverage for the About sheet (issue #15): opening, bundle-derived
/// version/build display, Licenses & Notices navigation, dismissal via
/// "Acknowledged", and the alternate-icon toggle where supported.
///
/// `WorkspaceView` presents the About sheet from two different toolbar
/// layouts: a direct `toolbar.about` button on regular (iPad) width, and an
/// "About XSky" item inside the `toolbar.more` overflow menu on compact
/// (iPhone) width. `openAbout` tries the direct button first and falls back
/// to the overflow menu, so the same test bodies exercise the same About
/// sheet regardless of size class. Running the suite against both an
/// iPhone 17 Pro (compact) and iPad 7th generation (regular) destination
/// gives coverage of both toolbar layouts without needing separate test
/// bodies.
final class AboutSheetUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset"]
        app.launch()
        waitForChart(app)
        return app
    }

    /// Wait for the catalog to finish loading, matching the pattern used by
    /// `XSkyAppUITests` — the toolbar isn't reliably interactive beforehand.
    private func waitForChart(_ app: XCUIApplication) {
        XCTAssertTrue(
            app.otherElements["chart.canvas"].firstMatch
                .waitForExistence(timeout: 20)
                || app.images["chart.canvas"].firstMatch.waitForExistence(
                    timeout: 5)
                || app.descendants(matching: .any)["chart.canvas"].firstMatch
                    .waitForExistence(timeout: 5),
            "chart did not appear")
    }

    /// Open the About sheet from the toolbar and wait for it to appear.
    ///
    /// On compact (iPhone) layouts "About" lives inside the "More"
    /// (`toolbar.more`) overflow menu rather than as a direct toolbar
    /// button, so open that menu first when present.
    @discardableResult
    private func openAbout(_ app: XCUIApplication) -> XCUIElement {
        let moreButton = app.buttons["toolbar.more"]
        if moreButton.waitForExistence(timeout: 3) {
            moreButton.tap()
            let aboutMenuItem = app.buttons["About XSky"]
            XCTAssertTrue(aboutMenuItem.waitForExistence(timeout: 5))
            aboutMenuItem.tap()
        } else {
            let aboutButton = app.buttons["toolbar.about"]
            XCTAssertTrue(aboutButton.waitForExistence(timeout: 20))
            aboutButton.tap()
        }
        let sheet = app.descendants(matching: .any)["about"].firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "About sheet did not appear")
        return sheet
    }

    // 1: opening the About sheet from the toolbar
    @MainActor
    func testOpenAboutSheet() throws {
        let app = launch()
        openAbout(app)
        XCTAssertTrue(app.staticTexts["about.version"].waitForExistence(timeout: 5))
    }

    // 2: version/build text is nonempty and shaped like a real
    // bundle-derived readout, never a value hardcoded in the test.
    //
    // The UI test runner and the app under test install into separate
    // simulator containers, so there is no reliable on-disk path from the
    // test bundle to the app bundle's Info.plist to compare against
    // directly. Instead this asserts the label matches the
    // "Version <short> (build <build>)" shape produced by `AboutView`,
    // with non-placeholder values, which is enough to catch a missing or
    // broken bundle lookup without baking in specific version numbers.
    @MainActor
    func testVersionMatchesBundle() throws {
        let app = launch()
        openAbout(app)

        let versionLabel = app.staticTexts["about.version"]
        XCTAssertTrue(versionLabel.waitForExistence(timeout: 5))
        let text = versionLabel.label
        XCTAssertFalse(text.isEmpty, "version label should not be empty")

        let pattern = #"^Version (\S+) \(build (\S+)\)$"#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..., in: text)
        guard
            let match = regex.firstMatch(in: text, range: range),
            let shortRange = Range(match.range(at: 1), in: text),
            let buildRange = Range(match.range(at: 2), in: text)
        else {
            XCTFail("version label '\(text)' did not match the expected 'Version X (build Y)' shape")
            return
        }
        XCTAssertNotEqual(
            text[shortRange], "?", "marketing version should be resolved, not the '?' fallback")
        XCTAssertNotEqual(
            text[buildRange], "?", "build number should be resolved, not the '?' fallback")
    }

    // 3: navigate to Licenses & Notices and back
    @MainActor
    func testNavigateToLicensesAndBack() throws {
        let app = launch()
        openAbout(app)

        let licensesLink = app.buttons["about.licensesLink"]
        XCTAssertTrue(licensesLink.waitForExistence(timeout: 5))
        licensesLink.tap()

        let licenses = app.descendants(matching: .any)["licenses"].firstMatch
        XCTAssertTrue(licenses.waitForExistence(timeout: 5), "Licenses & Notices did not appear")

        // Navigate back to the About screen.
        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(backButton.waitForExistence(timeout: 5))
        backButton.tap()

        XCTAssertTrue(
            app.staticTexts["about.version"].waitForExistence(timeout: 5),
            "did not return to the About screen")
    }

    // 4: dismiss the sheet via "Acknowledged"
    @MainActor
    func testDismissViaAcknowledged() throws {
        let app = launch()
        openAbout(app)

        let done = app.buttons["about.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()

        let sheet = app.descendants(matching: .any)["about"].firstMatch
        XCTAssertFalse(
            sheet.waitForExistence(timeout: 3), "About sheet should have been dismissed")
        XCTAssertTrue(
            app.buttons["toolbar.about"].waitForExistence(timeout: 5)
                || app.buttons["toolbar.more"].waitForExistence(timeout: 5),
            "workspace toolbar should be visible again after dismissal")
    }

    // 5: alternate-icon toggle, skipped conditionally when unsupported
    // rather than asserted flakily.
    @MainActor
    func testAlternateIconToggleReflectsState() throws {
        let app = launch()
        openAbout(app)

        let toggle = app.switches["about.originalIconToggle"]
        guard toggle.waitForExistence(timeout: 3) else {
            throw XCTSkip(
                "Alternate icon toggle not present — simulator/target does not support alternate icons")
        }

        let initial = toggle.value as? String
        XCTAssertNotNil(initial, "toggle should report an on/off state")

        toggle.tap()

        // Alternate icon changes trigger a system confirmation alert on
        // some simulator/OS combinations; if the app is backgrounded by
        // that system UI without our control, treat this as unsupported
        // in this environment rather than failing.
        if app.state != .runningForeground {
            throw XCTSkip(
                "System alternate-icon confirmation UI took over — cannot reliably assert state in this environment")
        }

        let alert = app.alerts.firstMatch
        if alert.waitForExistence(timeout: 2) {
            // Dismiss whatever confirmation the system presented so the
            // toggle state settles, then just verify it flipped.
            if alert.buttons.count > 0 {
                alert.buttons.element(boundBy: alert.buttons.count - 1).tap()
            }
        }

        let after = toggle.value as? String
        XCTAssertNotEqual(
            initial, after,
            "toggle state should change after tapping, or the test should have skipped")
    }
}
