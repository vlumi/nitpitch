import XCTest

@testable import NitpitchCore

/// The merge rules — the whole of syncing's decision-making, tested with no
/// iCloud, no network and no second device. Every case below is a real
/// two-device story written as values.
final class SyncMergeTests: XCTestCase {
    /// A stand-in for whatever the stores sync. The merge never knows what
    /// a record IS, so neither does its test.
    private struct Record: SyncRecord {
        let syncID: String
        let syncModifiedAt: Date?
        var payload: String = ""
    }

    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)
    private func at(_ offset: TimeInterval) -> Date { epoch.addingTimeInterval(offset) }

    // MARK: - Last writer wins

    /// The core promise: edit the same instrument on two devices, the later
    /// save is what both end up with.
    func testNewerStampWins() {
        let local = [Record(syncID: "violin", syncModifiedAt: at(10), payload: "phone")]
        let remote = [Record(syncID: "violin", syncModifiedAt: at(20), payload: "mac")]

        let merged = SyncMerge.mergedRecords(local: local, remote: remote, tombstones: [])

        XCTAssertEqual(merged.map(\.payload), ["mac"])
        // ...and symmetrically, so both devices converge on the same answer
        // rather than each keeping its own.
        let reversed = SyncMerge.mergedRecords(local: remote, remote: local, tombstones: [])
        XCTAssertEqual(reversed.map(\.payload), ["mac"])
    }

    /// Records the other side has never seen simply join, and the local
    /// order holds — a remote arrival must not reshuffle the user's list
    /// under them.
    func testDisjointRecordsUniteInLocalOrder() {
        let local = [
            Record(syncID: "violin", syncModifiedAt: at(10)),
            Record(syncID: "guitar", syncModifiedAt: at(11)),
        ]
        let remote = [Record(syncID: "cello", syncModifiedAt: at(12))]

        let merged = SyncMerge.mergedRecords(local: local, remote: remote, tombstones: [])

        XCTAssertEqual(merged.map(\.syncID), ["violin", "guitar", "cello"])
    }

    /// Everything stored before syncing existed carries no stamp. It must
    /// lose to anything that knows when it happened — otherwise a device
    /// that has never synced would overwrite a device that has.
    func testUnstampedRecordYieldsToStamped() {
        let unstamped = [Record(syncID: "violin", syncModifiedAt: nil, payload: "old")]
        let stamped = [Record(syncID: "violin", syncModifiedAt: at(1), payload: "new")]

        XCTAssertEqual(
            SyncMerge.mergedRecords(local: unstamped, remote: stamped, tombstones: [])
                .map(\.payload), ["new"])
        XCTAssertEqual(
            SyncMerge.mergedRecords(local: stamped, remote: unstamped, tombstones: [])
                .map(\.payload), ["new"])
    }

    /// Identical stamps are the same save arriving twice. Local wins, so a
    /// merge that changed nothing publishes nothing.
    func testEqualStampsKeepLocal() {
        let local = [Record(syncID: "violin", syncModifiedAt: at(5), payload: "phone")]
        let remote = [Record(syncID: "violin", syncModifiedAt: at(5), payload: "mac")]

        let merged = SyncMerge.mergedRecords(local: local, remote: remote, tombstones: [])

        XCTAssertEqual(merged.map(\.payload), ["phone"])
    }

    /// The factory seed's whole point: stable template ids mean two devices
    /// that each seeded themselves merge to one list, not two.
    func testIdenticallySeededDevicesDoNotDouble() {
        let seeded = ["violin", "viola", "guitar"].map {
            Record(syncID: $0, syncModifiedAt: nil)
        }

        let merged = SyncMerge.mergedRecords(local: seeded, remote: seeded, tombstones: [])

        XCTAssertEqual(merged.map(\.syncID), ["violin", "viola", "guitar"])
    }

    // MARK: - Deletion

    /// Delete on the phone, and the Mac's surviving copy must not merge it
    /// back in. This is the case tombstones exist for.
    func testTombstoneRemovesARecordTheOtherSideStillHas() {
        let remote = [Record(syncID: "guitar", syncModifiedAt: at(10))]
        let stones: Set<Tombstone> = [Tombstone(id: "guitar", deletedAt: at(20))]

        let merged = SyncMerge.mergedRecords(local: [], remote: remote, tombstones: stones)

        XCTAssertTrue(merged.isEmpty)
    }

    /// An edit made after the deletion is the later intent and wins: the
    /// user deleted it on one device, then went on using it on another.
    func testEditAfterDeletionSurvivesTheTombstone() {
        let remote = [Record(syncID: "guitar", syncModifiedAt: at(30), payload: "still here")]
        let stones: Set<Tombstone> = [Tombstone(id: "guitar", deletedAt: at(20))]

        let merged = SyncMerge.mergedRecords(local: [], remote: remote, tombstones: stones)

        XCTAssertEqual(merged.map(\.payload), ["still here"])
    }

    /// A tombstone for a record nobody has is inert — it must not disturb
    /// the records that remain.
    func testUnrelatedTombstoneLeavesRecordsAlone() {
        let local = [Record(syncID: "violin", syncModifiedAt: at(10))]
        let stones: Set<Tombstone> = [Tombstone(id: "banjo", deletedAt: at(20))]

        let merged = SyncMerge.mergedRecords(local: local, remote: [], tombstones: stones)

        XCTAssertEqual(merged.map(\.syncID), ["violin"])
    }

    // MARK: - Tombstone housekeeping

    /// A stone whose record came back must be dropped — keeping it would
    /// delete the resurrected record again on the next round trip, and the
    /// merge would never settle.
    func testResurrectedRecordDropsItsTombstone() {
        let survivors = [Record(syncID: "guitar", syncModifiedAt: at(30))]
        let stones: Set<Tombstone> = [Tombstone(id: "guitar", deletedAt: at(20))]

        let kept = SyncMerge.mergedTombstones(
            local: stones, remote: [], survivors: survivors, now: at(40))

        XCTAssertTrue(kept.isEmpty)
    }

    /// Both sides' stones survive while their records stay dead, and the
    /// later of two stones for one id is the one kept.
    func testTombstonesUniteAndKeepTheLatest() {
        let local: Set<Tombstone> = [Tombstone(id: "guitar", deletedAt: at(20))]
        let remote: Set<Tombstone> = [
            Tombstone(id: "guitar", deletedAt: at(25)),
            Tombstone(id: "banjo", deletedAt: at(21)),
        ]

        let kept = SyncMerge.mergedTombstones(
            local: local, remote: remote, survivors: [Record]([]), now: at(30))

        XCTAssertEqual(Set(kept.map(\.id)), ["guitar", "banjo"])
        XCTAssertEqual(kept.first { $0.id == "guitar" }?.deletedAt, at(25))
    }

    /// Stones expire, so the set can't grow forever; a stone younger than
    /// the lifetime stays, because a device could still be offline holding
    /// the record it kills.
    func testExpiredTombstonesArePruned() {
        let old = Tombstone(id: "guitar", deletedAt: at(0))
        let recent = Tombstone(id: "banjo", deletedAt: at(Tombstone.lifetime))

        let kept = SyncMerge.mergedTombstones(
            local: [old, recent], remote: [], survivors: [Record]([]),
            now: at(Tombstone.lifetime + 60))

        XCTAssertEqual(kept.map(\.id), ["banjo"])
    }

    // MARK: - Whole-value settings

    /// Pins, pin order and preset favorites are one value each, not a
    /// collection of records — same rule, one stamp.
    func testWholeValueTakesTheNewerSide() {
        let merged = SyncMerge.mergedValue(
            local: ["violin"], localModifiedAt: at(10),
            remote: ["guitar", "cello"], remoteModifiedAt: at(20))

        XCTAssertEqual(merged, ["guitar", "cello"])
    }

    /// A side that has never been stamped yields; with neither stamped
    /// there is nothing to prefer, so local stands and no publish follows.
    func testWholeValueYieldsWhenUnstamped() {
        XCTAssertEqual(
            SyncMerge.mergedValue(
                local: ["violin"], localModifiedAt: nil,
                remote: ["guitar"], remoteModifiedAt: at(1)),
            ["guitar"])
        XCTAssertEqual(
            SyncMerge.mergedValue(
                local: ["violin"], localModifiedAt: at(1),
                remote: ["guitar"], remoteModifiedAt: nil),
            ["violin"])
        XCTAssertEqual(
            SyncMerge.mergedValue(
                local: ["violin"], localModifiedAt: nil,
                remote: ["guitar"], remoteModifiedAt: nil),
            ["violin"])
    }

    // MARK: - Per-setting flags

    /// The rule that makes settings merges safe: a stamp exists only for a
    /// value the user actually SET, and never-set can never wipe set.
    func testUnsetFlagYieldsToAnySetFlag() {
        let adopted = SyncMerge.mergedFlag(
            localOn: true, localModifiedAt: nil,  // the install seed's star
            remoteOn: false, remoteModifiedAt: at(1))  // the user unstarred it

        XCTAssertEqual(adopted.on, false, "months of choices beat a fresh install")
        XCTAssertEqual(adopted.modifiedAt, at(1), "and the stamp rides along")
    }

    /// A stamped OFF is a real act: it beats an older ON and loses to a
    /// newer one — unstarring on one device sticks, restarring later wins.
    func testStampedOffIsARealAct() {
        let off = SyncMerge.mergedFlag(
            localOn: true, localModifiedAt: at(1),
            remoteOn: false, remoteModifiedAt: at(2))
        XCTAssertEqual(off.on, false)

        let backOn = SyncMerge.mergedFlag(
            localOn: false, localModifiedAt: at(2),
            remoteOn: true, remoteModifiedAt: at(3))
        XCTAssertEqual(backOn.on, true)
    }

    /// Ties break to ON on BOTH sides — local-wins would resolve a tie
    /// differently on each device, the one outcome that never converges.
    func testFlagTiesBreakToOnEverywhere() {
        let hereView = SyncMerge.mergedFlag(
            localOn: true, localModifiedAt: at(5),
            remoteOn: false, remoteModifiedAt: at(5))
        let thereView = SyncMerge.mergedFlag(
            localOn: false, localModifiedAt: at(5),
            remoteOn: true, remoteModifiedAt: at(5))

        XCTAssertEqual(hereView.on, true)
        XCTAssertEqual(thereView.on, true, "both devices compute the same answer")
    }

    /// Two never-set sides have nothing to say: local stands, unstamped,
    /// so nothing gets published as if it were a choice.
    func testTwoUnsetFlagsStayUnset() {
        let merged = SyncMerge.mergedFlag(
            localOn: true, localModifiedAt: nil,
            remoteOn: false, remoteModifiedAt: nil)

        XCTAssertEqual(merged.on, true)
        XCTAssertNil(merged.modifiedAt)
    }

    // MARK: - Convergence

    /// The property that matters more than any single rule: whatever the
    /// two sides hold, merging in both directions gives the same answer.
    /// A merge that isn't symmetric leaves two devices permanently
    /// disagreeing, each convinced it is right.
    func testMergeIsSymmetric() {
        let phone = [
            Record(syncID: "violin", syncModifiedAt: at(30), payload: "phone violin"),
            Record(syncID: "guitar", syncModifiedAt: at(10), payload: "phone guitar"),
            Record(syncID: "banjo", syncModifiedAt: nil, payload: "phone banjo"),
        ]
        let mac = [
            Record(syncID: "violin", syncModifiedAt: at(20), payload: "mac violin"),
            Record(syncID: "cello", syncModifiedAt: at(40), payload: "mac cello"),
            Record(syncID: "banjo", syncModifiedAt: at(5), payload: "mac banjo"),
        ]
        let stones: Set<Tombstone> = [Tombstone(id: "guitar", deletedAt: at(25))]

        let onPhone = SyncMerge.mergedRecords(local: phone, remote: mac, tombstones: stones)
        let onMac = SyncMerge.mergedRecords(local: mac, remote: phone, tombstones: stones)

        XCTAssertEqual(Set(onPhone.map(\.payload)), Set(onMac.map(\.payload)))
        // The content, spelled out: the newer violin, the Mac's only cello,
        // the stamped banjo over the unstamped one, and no deleted guitar.
        XCTAssertEqual(
            Set(onPhone.map(\.payload)), ["phone violin", "mac cello", "mac banjo"])
    }

    /// A stamped scalar (notation) keeps the flag's promises: never-set
    /// yields in both directions, newer wins, and a stamp tie with
    /// differing values breaks to the GREATER value on both sides.
    func testMergedScalarKeepsTheFlagRules() {
        let adopts = SyncMerge.mergedScalar(
            local: "english", localModifiedAt: nil,
            remote: "german", remoteModifiedAt: at(1))
        XCTAssertEqual(adopts.value, "german", "never-set yields")

        let keeps = SyncMerge.mergedScalar(
            local: "german", localModifiedAt: at(1),
            remote: "english", remoteModifiedAt: nil)
        XCTAssertEqual(keeps.value, "german", "an unstamped remote never wins")

        let newer = SyncMerge.mergedScalar(
            local: "english", localModifiedAt: at(1),
            remote: "italian", remoteModifiedAt: at(2))
        XCTAssertEqual(newer.value, "italian")
        XCTAssertEqual(newer.modifiedAt, at(2))

        let hereView = SyncMerge.mergedScalar(
            local: "english", localModifiedAt: at(5),
            remote: "german", remoteModifiedAt: at(5))
        let thereView = SyncMerge.mergedScalar(
            local: "german", localModifiedAt: at(5),
            remote: "english", remoteModifiedAt: at(5))
        XCTAssertEqual(hereView.value, "german")
        XCTAssertEqual(thereView.value, "german", "both devices compute the same answer")
    }

    /// Merging an already-merged state changes nothing — the round trip
    /// between two devices has to settle, not oscillate.
    func testMergeIsIdempotent() {
        let phone = [Record(syncID: "violin", syncModifiedAt: at(30), payload: "phone")]
        let mac = [Record(syncID: "cello", syncModifiedAt: at(40), payload: "mac")]

        let once = SyncMerge.mergedRecords(local: phone, remote: mac, tombstones: [])
        let twice = SyncMerge.mergedRecords(local: once, remote: once, tombstones: [])

        XCTAssertEqual(once, twice)
    }
}
