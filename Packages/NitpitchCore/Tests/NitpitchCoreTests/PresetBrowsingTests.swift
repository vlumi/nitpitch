import XCTest

@testable import NitpitchCore

/// How the browser orders and narrows a collection.
final class PresetBrowsingTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)
    private func at(_ offset: TimeInterval) -> Date { epoch.addingTimeInterval(offset) }

    private func item(
        _ id: String, _ name: String, _ templateID: String = "guitar", _ age: TimeInterval? = nil
    ) -> PresetBrowsing.Item {
        PresetBrowsing.Item(
            id: id, name: name, templateID: templateID, modifiedAt: age.map(at))
    }

    /// The default order: what you just made, received or edited leads.
    func testRecentPutsTheNewestFirst() {
        let items = [item("a", "Old", "guitar", 10), item("b", "New", "guitar", 30)]

        let arranged = PresetBrowsing.arrange(items, order: .recent)

        XCTAssertEqual(arranged.map(\.id), ["b", "a"])
    }

    /// A preset saved before stamping existed has no date, and inventing
    /// one would be a lie in either direction — treating it as brand new
    /// would push real recent work down the list, treating it as ancient
    /// asserts an age nobody recorded. It sorts last, by name.
    func testUndatedPresetsSortLastByName() {
        let items = [
            item("a", "Zulu", "guitar", nil),
            item("b", "Dated", "guitar", 10),
            item("c", "Alpha", "guitar", nil),
        ]

        let arranged = PresetBrowsing.arrange(items, order: .recent)

        XCTAssertEqual(arranged.map(\.id), ["b", "c", "a"])
    }

    /// Name order is the user's spelling, compared the way a person reads
    /// it: "Gig 2" before "Gig 10", and case-insensitively.
    func testNameOrderIsHumanReadable() {
        let items = [
            item("a", "Gig 10"), item("b", "gig 2"), item("c", "Bach No. 1"),
        ]

        let arranged = PresetBrowsing.arrange(items, order: .name)

        XCTAssertEqual(arranged.map(\.name), ["Bach No. 1", "gig 2", "Gig 10"])
    }

    /// Grouping by instrument sorts by the word the user SEES, not the id
    /// — "Bass" and "bass-guitar" are the same row to them.
    func testInstrumentOrderUsesTheDisplayName() {
        let items = [
            item("a", "One", "violin"),
            item("b", "Two", "bass-guitar"),
            item("c", "Three", "guitar"),
        ]
        let names = ["violin": "Violin", "bass-guitar": "Bass", "guitar": "Guitar"]

        let arranged = PresetBrowsing.arrange(
            items, order: .instrument, displayName: { names[$0] ?? $0 })

        XCTAssertEqual(arranged.map(\.id), ["b", "c", "a"], "Bass, Guitar, Violin")
    }

    /// Every order is total, so the list can't reshuffle between renders:
    /// arranging a collection and its reverse gives the same answer. Two
    /// presets sharing a name is ordinary — "Gig" fits a guitar and a
    /// violin both — and each order still has to decide between them.
    func testOrdersAreStableUnderTies() {
        let items = [
            item("z", "Gig", "guitar", 10),
            item("a", "Gig", "violin", 10),
        ]

        for order in PresetBrowsing.Order.allCases {
            let once = PresetBrowsing.arrange(items, order: order)
            let twice = PresetBrowsing.arrange(items.reversed(), order: order)
            XCTAssertEqual(once.map(\.id), twice.map(\.id), "\(order) is order-independent")
        }

        // Same date and same name leaves only the id: a stable answer.
        XCTAssertEqual(PresetBrowsing.arrange(items, order: .recent).map(\.id), ["a", "z"])
        XCTAssertEqual(PresetBrowsing.arrange(items, order: .name).map(\.id), ["a", "z"])
        // Under instrument order they aren't tied at all — "guitar" sorts
        // before "violin", and that beats the name they share.
        XCTAssertEqual(PresetBrowsing.arrange(items, order: .instrument).map(\.id), ["z", "a"])
    }

    /// The filter narrows to one instrument's presets.
    func testFilteringNarrowsToOneTemplate() {
        let items = [
            item("a", "One", "guitar", 10),
            item("b", "Two", "violin", 20),
            item("c", "Three", "guitar", 30),
        ]

        let arranged = PresetBrowsing.arrange(items, order: .recent, templateID: "guitar")

        XCTAssertEqual(arranged.map(\.id), ["c", "a"])
    }

    /// Only instruments that actually have presets are offered as filters —
    /// a filter that can only produce an empty list is a dead end the UI
    /// shouldn't offer.
    func testOnlyTemplatesWithPresetsAreFilterable() {
        let items = [
            item("a", "One", "guitar"), item("b", "Two", "guitar"), item("c", "3", "cello"),
        ]
        let names = ["guitar": "Guitar", "cello": "Cello"]

        let templates = PresetBrowsing.filterableTemplates(
            items, displayName: { names[$0] ?? $0 })

        XCTAssertEqual(templates, ["cello", "guitar"], "each once, in display order")
    }

    /// An empty collection arranges and filters to nothing, rather than
    /// tripping over itself.
    func testEmptyIsHandled() {
        XCTAssertTrue(PresetBrowsing.arrange([], order: .recent).isEmpty)
        XCTAssertTrue(PresetBrowsing.filterableTemplates([]).isEmpty)
    }
}
