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

    func testDefaultsTo440WithViolinPinned() {
        let settings = Settings(defaults: defaults)
        XCTAssertEqual(settings.reference.hz, 440)
        XCTAssertEqual(settings.favorites, [Instrument.violin.id])
    }

    func testPersistsAcrossInstances() {
        let first = Settings(defaults: defaults)
        first.reference = ReferencePitch(hz: 442)
        first.toggleFavorite("guitar")

        let second = Settings(defaults: defaults)
        XCTAssertEqual(second.reference.hz, 442)
        XCTAssertEqual(second.favorites, ["violin", "guitar"])
    }

    func testMissingReferenceDoesNotClampToLowBound() {
        // `double(forKey:)` returns 0 for an absent key; taken literally that
        // would clamp to 390 Hz and silently mistune a fresh install.
        XCTAssertNil(defaults.object(forKey: "referenceHz"))
        XCTAssertEqual(Settings(defaults: defaults).reference.hz, 440)
    }

}
