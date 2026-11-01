import XCTest

/// UI tests for the primary iPad landscape workflows
/// (DELIVERY_ACCEPTANCE.md). Each test launches with `-uitest-reset` for
/// a deterministic starting state unless it is exercising restoration.
final class XSkyAppUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    private func launch(reset: Bool = true, extraArguments: [String] = [])
        -> XCUIApplication
    {
        let app = XCUIApplication()
        app.launchArguments =
            (reset ? ["-uitest-reset"] : []) + extraArguments
        app.launch()
        return app
    }

    private func waitForChart(_ app: XCUIApplication) {
        XCTAssertTrue(
            app.otherElements["chart.canvas"].firstMatch
                .waitForExistence(timeout: 20)
                || app.images["chart.canvas"].firstMatch.waitForExistence(
                    timeout: 5)
                || app.descendants(matching: .any)["chart.canvas"].firstMatch
                    .waitForExistence(timeout: 5),
            "chart did not appear")
        showSidebar(app)
        // catalog load finished when the YBS row shows its count
        XCTAssertTrue(
            app.staticTexts["9,096 objects"].waitForExistence(timeout: 20))
    }

    /// The sidebar starts hidden after a reset; a relaunch restores it.
    private func showSidebar(_ app: XCUIApplication) {
        let sidebar = app.descendants(matching: .any)["sidebar"].firstMatch
        if sidebar.exists { return }
        app.buttons["toolbar.sidebar"].tap()
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5), "sidebar did not open")
    }

    /// Scroll the lazy sidebar list until an element exists.
    private func scrollSidebar(
        _ app: XCUIApplication, to element: XCUIElement
    ) -> Bool {
        for _ in 0..<6 {
            if element.exists { return true }
            app.descendants(matching: .any)["sidebar"].firstMatch.swipeUp()
        }
        return element.waitForExistence(timeout: 3)
    }

    private func labelCount(_ app: XCUIApplication, is expected: String) -> Bool {
        scrollSidebar(app, to: app.staticTexts[expected])
    }

    private func search(_ app: XCUIApplication, _ query: String) {
        let field = app.textFields["search.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        // keystrokes sent while the keyboard is still appearing can be
        // dropped; wait for it and retype if the text did not land
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        field.typeText(query)
        if field.value as? String != query {
            field.typeText(query)
        }
        XCTAssertEqual(field.value as? String, query)
        let results = app.descendants(matching: .any)["search.results"]
        XCTAssertTrue(results.waitForExistence(timeout: 10))
        let first = results.buttons.firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.tap()
    }

    // 1: launch → chart appears with default YBS/RNGC layers
    @MainActor
    func testLaunchShowsChartWithDefaultCatalogs() throws {
        let app = launch()
        waitForChart(app)
        XCTAssertTrue(app.staticTexts["chart.centerReadout"].exists)
        XCTAssertEqual(
            app.switches["sidebar.catalog.YBS"].value as? String, "1")
        XCTAssertEqual(
            app.switches["sidebar.catalog.RNGC"].value as? String, "1")
        XCTAssertEqual(
            app.switches["sidebar.catalog.QSO"].value as? String, "0")
    }

    // 2: search M 31 → center/select → inspector shows RNGC data
    @MainActor
    func testSearchM31ShowsInspector() throws {
        let app = launch()
        waitForChart(app)
        search(app, "M 31")
        let name = app.staticTexts["inspector.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        XCTAssertEqual(name.label, "M 31")
        XCTAssertTrue(
            app.staticTexts["Revised New General Catalog of Non-Stellar Objects"]
                .exists)
    }

    // 3: search Sirius → YBS details visible
    @MainActor
    func testSearchSiriusShowsYBSDetails() throws {
        let app = launch()
        waitForChart(app)
        search(app, "Sirius")
        let name = app.staticTexts["inspector.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        XCTAssertEqual(name.label, "Sirius")
        XCTAssertTrue(
            app.staticTexts["Yale Catalog of Bright Stars"].exists)
        XCTAssertTrue(app.staticTexts["HR 2491"].exists)
    }

    // 4: toggle layers and verify the state survives relaunch
    @MainActor
    func testLayerTogglesSurviveRelaunch() throws {
        let app = launch()
        waitForChart(app)
        app.switches["sidebar.layer.boundaries"].switches.firstMatch.tap()
        app.switches["sidebar.layer.outlines"].switches.firstMatch.tap()
        app.switches["sidebar.layer.grid"].switches.firstMatch.tap()
        XCTAssertEqual(
            app.switches["sidebar.layer.boundaries"].value as? String, "1")
        XCTAssertEqual(
            app.switches["sidebar.layer.grid"].value as? String, "0")
        // give the debounced persist a moment
        Thread.sleep(forTimeInterval: 1.5)

        app.terminate()
        let relaunched = launch(reset: false)
        waitForChart(relaunched)
        XCTAssertEqual(
            relaunched.switches["sidebar.layer.boundaries"].value as? String,
            "1")
        XCTAssertEqual(
            relaunched.switches["sidebar.layer.outlines"].value as? String,
            "1")
        XCTAssertEqual(
            relaunched.switches["sidebar.layer.grid"].value as? String, "0")
    }

    // 5: pan and pinch, then undo and redo
    @MainActor
    func testPanPinchUndoRedo() throws {
        let app = launch()
        waitForChart(app)
        let readout = app.staticTexts["chart.centerReadout"]
        let initial = readout.label

        let chart = app.otherElements["chart.canvas"].firstMatch
        let start = chart.coordinate(
            withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5))
        let end = chart.coordinate(
            withNormalizedOffset: CGVector(dx: 0.35, dy: 0.35))
        start.press(forDuration: 0.05, thenDragTo: end)

        XCTAssertNotEqual(readout.label, initial, "pan did not move center")
        let afterPan = readout.label

        chart.pinch(withScale: 1.6, velocity: 1.5)
        let field = app.staticTexts["chart.fieldReadout"].label

        app.buttons["toolbar.undo"].tap()  // undo zoom
        XCTAssertNotEqual(
            app.staticTexts["chart.fieldReadout"].label, field)
        app.buttons["toolbar.undo"].tap()  // undo pan
        XCTAssertEqual(readout.label, initial)
        app.buttons["toolbar.redo"].tap()  // redo pan
        XCTAssertEqual(readout.label, afterPan)
    }

    // 6: night mode declared state and screenshot baseline
    @MainActor
    func testNightMode() throws {
        let app = launch()
        waitForChart(app)
        app.descendants(matching: .any)["toolbar.nightMode"].firstMatch.tap()
        let nightSwitch = app.switches["sidebar.display.nightMode"]
        XCTAssertTrue(scrollSidebar(app, to: nightSwitch))
        XCTAssertEqual(nightSwitch.value as? String, "1")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "night-mode"
        shot.lifetime = .keepAlways
        add(shot)
        app.descendants(matching: .any)["toolbar.nightMode"].firstMatch.tap()
        XCTAssertEqual(
            app.switches["sidebar.display.nightMode"].value as? String, "0")
    }

    // 7: add, remove, undo, and restore a label
    @MainActor
    func testLabelLifecycle() throws {
        let app = launch()
        waitForChart(app)
        search(app, "M 31")
        let addLabel = app.buttons["inspector.addLabel"]
        XCTAssertTrue(addLabel.waitForExistence(timeout: 10))
        addLabel.tap()
        let removeLabel = app.buttons["inspector.removeLabel"]
        XCTAssertTrue(removeLabel.waitForExistence(timeout: 5))
        XCTAssertTrue(labelCount(app, is: "1 labels"))

        removeLabel.tap()
        XCTAssertTrue(app.buttons["inspector.addLabel"].waitForExistence(timeout: 5))
        XCTAssertTrue(labelCount(app, is: "0 labels"))

        app.buttons["toolbar.undo"].tap()  // undo remove
        XCTAssertTrue(labelCount(app, is: "1 labels"))

        Thread.sleep(forTimeInterval: 1.5)
        app.terminate()
        let relaunched = launch(reset: false)
        waitForChart(relaunched)
        XCTAssertTrue(
            labelCount(relaunched, is: "1 labels"),
            "label did not survive relaunch")
    }

    // 8: region zoom and cancel paths
    @MainActor
    func testRegionZoomAndCancel() throws {
        let app = launch()
        waitForChart(app)
        let fieldBefore = app.staticTexts["chart.fieldReadout"].label

        // cancel path: arm then disarm without dragging
        app.descendants(matching: .any)["toolbar.zoomRegion"].firstMatch.tap()
        app.descendants(matching: .any)["toolbar.zoomRegion"].firstMatch.tap()
        XCTAssertEqual(
            app.staticTexts["chart.fieldReadout"].label, fieldBefore)

        // zoom path
        app.descendants(matching: .any)["toolbar.zoomRegion"].firstMatch.tap()
        let chart = app.otherElements["chart.canvas"].firstMatch
        let start = chart.coordinate(
            withNormalizedOffset: CGVector(dx: 0.35, dy: 0.35))
        let end = chart.coordinate(
            withNormalizedOffset: CGVector(dx: 0.65, dy: 0.65))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertNotEqual(
            app.staticTexts["chart.fieldReadout"].label, fieldBefore,
            "region zoom did not change the field")
    }

    // 9: import usercat.example → locate Test Object → remove the catalog
    @MainActor
    func testUserCatalogImportSearchRemove() throws {
        let app = launch(extraArguments: ["-uitest-import-example"])
        waitForChart(app)
        XCTAssertTrue(
            app.staticTexts["1 objects · imported"].waitForExistence(
                timeout: 20),
            "imported catalog row missing")

        search(app, "Test Object")
        let name = app.staticTexts["inspector.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        XCTAssertEqual(name.label, "Test Object")

        app.buttons["sidebar.removeUserCatalog"].tap()
        XCTAssertFalse(
            app.staticTexts["1 objects · imported"].waitForExistence(
                timeout: 3),
            "imported catalog was not removed")
    }
}
