import NitpitchCore
import XCTest

@testable import NitpitchData
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

    /// The rack's drag-reorder is a synced whole value with one stamp; a
    /// move that didn't stamp either never left the device or was pushed
    /// under the old stamp and undone by the next merge.
    func testMovingFavoritesStampsTheOrder() {
        let settings = Settings(defaults: defaults)
        settings.favorites = ["violin", "guitar", "cello"]
        XCTAssertNil(settings.favoritesOrderStamp, "assigning the array is not a user act")

        settings.moveFavorites(fromOffsets: IndexSet(integer: 2), toOffset: 0)

        XCTAssertEqual(settings.favorites, ["cello", "violin", "guitar"])
        XCTAssertNotNil(settings.favoritesOrderStamp, "the move is stamped at the act")
    }

    /// A pin is the (instrument, preset) pair — toggling is idempotent and
    /// the pins survive a relaunch like everything else.
    func testPresetPinsToggleAndPersist() {
        let first = Settings(defaults: defaults)
        first.togglePin(instrumentID: "guitar", presetID: "p1")
        XCTAssertTrue(first.isPinned(instrumentID: "guitar", presetID: "p1"))
        XCTAssertFalse(
            first.isPinned(instrumentID: "guitar-2", presetID: "p1"),
            "the pin binds one instrument, not the template")

        let second = Settings(defaults: defaults)
        XCTAssertTrue(second.isPinned(instrumentID: "guitar", presetID: "p1"))
        second.togglePin(instrumentID: "guitar", presetID: "p1")
        XCTAssertFalse(second.isPinned(instrumentID: "guitar", presetID: "p1"))
    }

    func testMissingReferenceDoesNotClampToLowBound() {
        // `double(forKey:)` returns 0 for an absent key; taken literally that
        // would clamp to 390 Hz and silently mistune a fresh install.
        XCTAssertNil(defaults.object(forKey: "referenceHz"))
        XCTAssertEqual(Settings(defaults: defaults).reference.hz, 440)
    }

}
