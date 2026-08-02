import XCTest

/// Local-only UI regression tests (`make uitest`); CI never runs
/// `xcodebuild test`.
///
/// The simulator has no usable microphone — it delivers silence — so these
/// cover launch, navigation, and layout. The needle responding to a real note
/// is verified on device by hand; the DSP itself is covered headlessly by the
/// NitpitchCore suite.
final class NitpitchUITests: XCTestCase {
    private func launch(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        // Wipe persisted settings so each run starts identical (see LaunchStores).
        app.launchArguments = ["-uitest-clean"] + extraArguments
        app.launch()
        return app
    }

    /// The toolbar menu. Its identifier lands on descendants too, so match the
    /// button rather than "any" — the broad query finds several elements and
    /// XCTest refuses to guess which one to tap.
    private func openLayoutMenu(_ app: XCUIApplication) {
        let menu = app.buttons["grid.columns"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
    }

    /// Root → chooser → violin's grid, which several tests need to reach.
    private func openViolinGrid(_ app: XCUIApplication) {
        let button = app.descendants(matching: .any)["tuner.instrument"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        button.tap()

        let violin = app.descendants(matching: .any)["chooser.violin"]
        XCTAssertTrue(violin.waitForExistence(timeout: 5))
        violin.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["grid.strings"].waitForExistence(timeout: 5))
    }

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testLaunchesToAStatusOrReading() {
        let app = launch()
        // With no audio the app should sit in a status state rather than showing
        // a stale or garbage note.
        let status = app.staticTexts["tuner.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
    }

    /// The launch screen is chromatic whatever instrument was chosen last, so
    /// what's on it is the way *into* an instrument rather than a picker
    /// showing one. (This replaces a test that asserted the opposite.)
    func testLaunchesOnTheChromaticTuner() {
        let app = launch()
        let button = app.descendants(matching: .any)["tuner.instrument"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        XCTAssertFalse(
            app.descendants(matching: .any)["grid.strings"].exists,
            "the app should not open on an instrument")
    }

    func testChoosingAnInstrumentOpensItsStrings() {
        let app = launch()
        openViolinGrid(app)
    }

    /// The chooser is pushed, not presented: back from a grid lands on the
    /// list you chose from, then on the tuner — the stack you walked.
    func testBackFromGridReturnsToTheChooser() {
        let app = launch()
        openViolinGrid(app)

        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["chooser.violin"].waitForExistence(timeout: 5),
            "back from the grid should land on the chooser")

        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["tuner.instrument"].waitForExistence(timeout: 5),
            "back from the chooser should land on the tuner")
    }

    // MARK: - The string view

    /// A grid cell opens its string full screen; the arrows walk the strings;
    /// back returns to the grid.
    func testCellOpensStringViewAndArrowsWalkStrings() {
        let app = launch()
        openViolinGrid(app)

        let cell = app.descendants(matching: .any)["grid.cell.0"].firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
        cell.tap()

        let target = app.descendants(matching: .any)["string.target"]
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        XCTAssertTrue(target.label.hasPrefix("G"), "first violin string is G3")

        let next = app.descendants(matching: .any)["string.next"]
        next.tap()
        XCTAssertTrue(target.label.hasPrefix("D"), "next string up is D4")

        // The first string has no previous; walking back down re-enables it.
        let previous = app.descendants(matching: .any)["string.prev"]
        previous.tap()
        XCTAssertTrue(target.label.hasPrefix("G"))
        XCTAssertFalse(previous.isEnabled, "no string below G3")

        // For the eye as much as the assertions — the layout is judged from
        // the report.
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "string-view"
        shot.lifetime = .keepAlways
        add(shot)

        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["grid.strings"].waitForExistence(timeout: 5),
            "back from a string should land on the grid")
    }

    // MARK: - Favourites

    /// The point of the row: one tap from launch to the violin's strings,
    /// no list in between. Violin starts pinned.
    func testFavoriteChipGoesStraightToTheGrid() {
        let app = launch()
        let chip = app.descendants(matching: .any)["favorite.violin"]
        XCTAssertTrue(chip.waitForExistence(timeout: 10))
        chip.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["grid.strings"].waitForExistence(timeout: 5))
        // And back is ONE step to the tuner — the chip skipped the chooser,
        // so the stack must have too.
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["tuner.instrument"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["chooser.violin"].exists)
    }

    /// Pinning in the chooser puts a chip on the launch screen; unpinning
    /// removes it.
    func testPinningFromTheChooser() {
        let app = launch()
        let button = app.descendants(matching: .any)["tuner.instrument"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        button.tap()

        let pin = app.descendants(matching: .any)["chooser.pin.guitar"]
        XCTAssertTrue(pin.waitForExistence(timeout: 5))
        pin.tap()
        app.navigationBars.buttons.firstMatch.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["favorite.guitar"].waitForExistence(timeout: 5),
            "pinning should add a chip")

        button.tap()
        pin.tap()
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertFalse(
            app.descendants(matching: .any)["favorite.guitar"].exists,
            "unpinning should remove the chip")
    }

    // MARK: - Detector diagnostics

    /// The diagnostics screen is gated on `-debug`, and the gate is the only
    /// thing keeping it out of a shipped build — so it's worth a test that it
    /// really is shut by default.
    func testDetectorScreenIsHiddenWithoutTheDebugFlag() {
        let app = launch()
        openViolinGrid(app)

        openLayoutMenu(app)
        XCTAssertFalse(
            app.descendants(matching: .any)["grid.debug"].waitForExistence(timeout: 2),
            "the detector screen must not be reachable in a normal launch")
    }

    func testDetectorScreenOpensUnderTheDebugFlag() {
        let app = launch(extraArguments: ["-debug"])
        openViolinGrid(app)

        openLayoutMenu(app)
        let entry = app.descendants(matching: .any)["grid.debug"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["debug.detector"].waitForExistence(timeout: 5))
        // Every string gets a row, so a subharmonic on a neighbour is visible.
        for name in ["G3", "D4", "A4", "E5"] {
            XCTAssertTrue(
                app.staticTexts[name].waitForExistence(timeout: 2),
                "no diagnostics row for \(name)")
        }

        // Attached for the screenshot in the test report — this screen is judged
        // by eye as much as by assertion.
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "detector-diagnostics"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Chromatic is the screen you arrive from, so offering it in the chooser
    /// would be offering to navigate to where you already are.
    func testTheChooserDoesNotOfferChromatic() {
        let app = launch()
        let button = app.descendants(matching: .any)["tuner.instrument"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        button.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["chooser.violin"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["chooser.chromatic"].exists)
    }
}
