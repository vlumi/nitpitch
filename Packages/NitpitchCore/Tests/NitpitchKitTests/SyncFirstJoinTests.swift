import Combine
import NitpitchCore
import XCTest

@testable import NitpitchData
@testable import NitpitchKit

/// First-join duplication: two devices used apart for weeks edit the SAME
/// seeded record, then meet — and nothing anyone did vanishes. The later
/// edit keeps the id; the other survives as a copy ("Guitar 2" when the
/// names collide). Merging them back is the user's cleanup, not the app's
/// prevention.
@MainActor
final class SyncFirstJoinTests: XCTestCase {
    /// The headline: both devices renamed the same violin before ever
    /// syncing. After the join, both names exist everywhere — the later
    /// on the original id, the earlier as a copy under a fresh one.
    func testBothEditedSameIdKeepsBothVersions() {
        let cloud = FakeSyncStore()
        let phone = SyncTestDevice(sharing: cloud, enabled: false)
        let mac = SyncTestDevice(sharing: cloud, enabled: false)
        defer { phone.destroy(); mac.destroy() }
        let violin = Instrument.violin.id

        phone.instruments.rename(id: violin, to: "Phone fiddle")
        mac.instruments.rename(id: violin, to: "Mac fiddle")  // later
        phone.engine.setEnabled(true)
        phone.engine.sync()
        mac.engine.setEnabled(true)
        mac.engine.sync()
        phone.engine.sync()
        mac.engine.sync()

        for device in [phone, mac] {
            let names = Set(device.instruments.instances.map(\.name))
            XCTAssertTrue(names.contains("Mac fiddle"), "the later edit survives")
            XCTAssertTrue(names.contains("Phone fiddle"), "and so does the earlier one")
            XCTAssertEqual(
                device.instruments.instance(id: violin)?.name, "Mac fiddle",
                "the later edit keeps the id")
        }
    }

    /// Same name, different setups — the common conflict: both still called
    /// it "Guitar", so the copy steps aside as "Guitar 2".
    func testSameNameConflictBecomesGuitarTwo() {
        let cloud = FakeSyncStore()
        let phone = SyncTestDevice(sharing: cloud, enabled: false)
        let mac = SyncTestDevice(sharing: cloud, enabled: false)
        defer { phone.destroy(); mac.destroy() }
        let guitar = Instrument.guitar.id

        phone.instruments.setReference(id: guitar, ReferencePitch(hz: 442))
        mac.instruments.setReference(id: guitar, ReferencePitch(hz: 443))  // later
        phone.engine.setEnabled(true)
        phone.engine.sync()
        mac.engine.setEnabled(true)
        mac.engine.sync()
        phone.engine.sync()

        for device in [phone, mac] {
            XCTAssertEqual(
                device.instruments.instance(id: guitar)?.referenceHz, 443,
                "the later reference keeps the id")
            let copy = device.instruments.instances.first { $0.name == "Guitar 2" }
            XCTAssertEqual(copy?.referenceHz, 442, "the earlier one survives as Guitar 2")
        }
    }

    /// Untouched seeds are not conflicts: identical content, seed stamps —
    /// the lists must not grow.
    func testUneditedSeedsDoNotDuplicate() {
        let cloud = FakeSyncStore()
        let phone = SyncTestDevice(sharing: cloud)
        let mac = SyncTestDevice(sharing: cloud)
        defer { phone.destroy(); mac.destroy() }
        let before = phone.instruments.instances.count

        phone.engine.sync()
        mac.engine.sync()
        phone.engine.sync()

        XCTAssertEqual(phone.instruments.instances.count, before)
        XCTAssertEqual(mac.instruments.instances.count, before)
    }

    /// Edited on ONE side only: ordinary LWW, no copy — the seed on the
    /// quiet device is not an opinion.
    func testOneSidedEditDoesNotDuplicate() {
        let cloud = FakeSyncStore()
        let phone = SyncTestDevice(sharing: cloud, enabled: false)
        let mac = SyncTestDevice(sharing: cloud, enabled: false)
        defer { phone.destroy(); mac.destroy() }
        let before = phone.instruments.instances.count

        phone.instruments.rename(id: Instrument.violin.id, to: "Konzertmeister")
        phone.engine.setEnabled(true)
        phone.engine.sync()
        mac.engine.setEnabled(true)
        mac.engine.sync()

        XCTAssertEqual(mac.instruments.instances.count, before, "no copy appeared")
        XCTAssertEqual(
            mac.instruments.instance(id: Instrument.violin.id)?.name, "Konzertmeister")
    }

    /// After the first join, conflicts are ordinary LWW again: steady-state
    /// stamps can't tell a true concurrent edit from a routine sync, so the
    /// clean rule applies exactly once.
    func testSteadyStateConflictsStayLWW() {
        let cloud = FakeSyncStore()
        let phone = SyncTestDevice(sharing: cloud)
        let mac = SyncTestDevice(sharing: cloud)
        defer { phone.destroy(); mac.destroy() }
        phone.engine.sync()
        mac.engine.sync()
        let joined = phone.instruments.instances.count

        phone.instruments.rename(id: Instrument.violin.id, to: "First")
        mac.instruments.rename(id: Instrument.violin.id, to: "Second")  // later
        phone.engine.sync()
        mac.engine.sync()
        phone.engine.sync()

        XCTAssertEqual(phone.instruments.instances.count, joined, "no duplicate")
        XCTAssertEqual(phone.instruments.instance(id: Instrument.violin.id)?.name, "Second")
    }

    /// Presets carry the same rule, with their per-template name uniqueness
    /// honoured: two devices renamed the same seeded preset before syncing,
    /// and both names survive on distinct presets.
    func testPresetConflictKeepsBothWithDistinctNames() {
        let cloud = FakeSyncStore()
        let phone = SyncTestDevice(sharing: cloud, enabled: false)
        let mac = SyncTestDevice(sharing: cloud, enabled: false)
        defer { phone.destroy(); mac.destroy() }
        let seed = "seed:guitar:drop-d"

        XCTAssertTrue(phone.presets.rename(id: seed, to: "Slide"))
        XCTAssertTrue(mac.presets.rename(id: seed, to: "Gig"))  // later
        phone.engine.setEnabled(true)
        phone.engine.sync()
        mac.engine.setEnabled(true)
        mac.engine.sync()
        phone.engine.sync()

        for device in [phone, mac] {
            let names = Set(
                device.presets.presets.filter { $0.templateID == "guitar" }.map(\.name))
            XCTAssertTrue(names.contains("Gig"), "the later rename keeps the id")
            XCTAssertTrue(names.contains("Slide"), "the earlier survives as its own preset")
            XCTAssertEqual(
                device.presets.presets.first { $0.id == seed }?.name, "Gig")
        }
    }
}
