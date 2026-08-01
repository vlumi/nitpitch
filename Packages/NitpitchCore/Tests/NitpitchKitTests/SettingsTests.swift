import NitpitchCore
import XCTest

@testable import NitpitchKit

final class SettingsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "fi.misaki.nitpitch.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testDefaultsToViolinAt440() {
        let settings = Settings(defaults: defaults)
        XCTAssertEqual(settings.instrument, .violin)
        XCTAssertEqual(settings.reference.hz, 440)
    }

    func testPersistsAcrossInstances() {
        let first = Settings(defaults: defaults)
        first.instrument = .cello
        first.reference = ReferencePitch(hz: 442)

        let second = Settings(defaults: defaults)
        XCTAssertEqual(second.instrument, .cello)
        XCTAssertEqual(second.reference.hz, 442)
    }

    func testMissingReferenceDoesNotClampToLowBound() {
        // `double(forKey:)` returns 0 for an absent key; taken literally that
        // would clamp to 390 Hz and silently mistune a fresh install.
        XCTAssertNil(defaults.object(forKey: "referenceHz"))
        XCTAssertEqual(Settings(defaults: defaults).reference.hz, 440)
    }

    func testUnknownInstrumentIDFallsBackToViolin() {
        defaults.set("theremin", forKey: "instrumentID")
        XCTAssertEqual(Settings(defaults: defaults).instrument, .violin)
    }
}
