import XCTest

/// Local-only UI regression tests (`make uitest`); CI never runs
/// `xcodebuild test`.
///
/// The simulator has no usable microphone — it delivers silence — so these
/// cover launch, navigation, and layout. The needle responding to a real note
/// is verified on device by hand; the DSP itself is covered headlessly by the
/// NitpitchCore suite.
final class NitpitchUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        // Wipe persisted settings so each run starts identical (see LaunchStores).
        app.launchArguments = ["-uitest-clean"]
        app.launch()
        return app
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
            app.descendants(matching: .any)["grid.placeholder"].exists,
            "the app should not open on an instrument")
    }

    func testChoosingAnInstrumentOpensItsStrings() {
        let app = launch()
        let button = app.descendants(matching: .any)["tuner.instrument"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        button.tap()

        let violin = app.descendants(matching: .any)["chooser.violin"]
        XCTAssertTrue(violin.waitForExistence(timeout: 5))
        violin.tap()

        let grid = app.descendants(matching: .any)["grid.placeholder"]
        XCTAssertTrue(grid.waitForExistence(timeout: 5))
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
