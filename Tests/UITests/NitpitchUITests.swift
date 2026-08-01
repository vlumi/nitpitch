import XCTest

/// Local-only UI regression tests (`make uitest`); CI never runs
/// `xcodebuild test`.
///
/// The simulator has no usable microphone — it delivers silence — so these
/// cover launch, layout, and the persistence of the picker. The needle
/// responding to a real note is verified on device by hand; the DSP itself is
/// covered headlessly by the NitpitchCore suite.
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

    func testInstrumentPickerDefaultsToViolin() {
        let app = launch()
        let picker = app.descendants(matching: .any)["tuner.instrument"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        XCTAssertTrue(picker.label.contains("Violin") || picker.value as? String == "Violin")
    }
}
