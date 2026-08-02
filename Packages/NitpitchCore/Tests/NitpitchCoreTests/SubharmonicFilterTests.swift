import XCTest

@testable import NitpitchCore

/// Every case here is a real detector output observed in practice — the filter
/// exists because these happened, first against synthesized tones and then on
/// a real violin.
final class SubharmonicFilterTests: XCTestCase {
    private func candidates(_ frequencies: [Double?]) -> [SubharmonicFilter.Candidate] {
        frequencies.enumerated().compactMap { index, hz in
            hz.map { SubharmonicFilter.Candidate(id: index, frequency: $0) }
        }
    }

    private func surviving(_ frequencies: [Double?]) -> Set<Int> {
        Set(SubharmonicFilter.real(among: candidates(frequencies)).map(\.id))
    }

    /// The violin bug as reported: playing A4, the G detector locks A's
    /// subharmonic at exactly half frequency. A survives, G goes dark.
    func testPlayingAKeepsGDark() {
        XCTAssertEqual(surviving([220.0, nil, 440.0, nil]), [2])
    }

    /// Playing E5 lit both G (÷3) and D (÷2) on the real instrument.
    func testPlayingEKeepsGAndDDark() {
        XCTAssertEqual(surviving([219.7, 329.6, nil, 659.3]), [3])
    }

    /// A single honest reading passes through untouched.
    func testLoneReadingSurvives() {
        XCTAssertEqual(surviving([196.0, nil, nil, nil]), [0])
    }

    /// A slack string is exactly who the wide bands serve; far from target is
    /// NOT grounds for rejection when nothing above claims its frequency.
    func testSlackStringSurvives() {
        // G3 300¢ flat, alone.
        XCTAssertEqual(surviving([164.8, nil, nil, nil]), [0])
    }

    /// The guitar trap: high E4 makes the E2 detector read a *perfect* E2 (two
    /// octaves down, −0¢) and A2 read −2¢. Distance-from-target can't catch
    /// these — they look in tune — but the 4:1 and 3:1 ratios can.
    func testGuitarHighEShadowsAreDropped() {
        // E2, A2, D3, G3, B3, E4 — playing high E4 alone.
        XCTAssertEqual(
            surviving([82.4, 109.9, nil, nil, nil, 329.6]), [5])
    }

    /// Two genuinely different notes — a real double stop that MPM happened to
    /// resolve — both survive, because neither divides the other.
    func testTwoRealNotesBothSurvive() {
        // G3 and D4: ratio 1.5, not an integer.
        XCTAssertEqual(surviving([196.0, 293.7, nil, nil]), [0, 1])
    }

    /// A chain: 110 ÷ 220 ÷ 440. Only the top survives; the middle is both a
    /// shadow and (numerically) a "fundamental" of the bottom, and neither
    /// role saves it.
    func testChainsCollapseToTheHighest() {
        XCTAssertEqual(surviving([110.0, 220.0, 440.0, nil]), [2])
    }

    /// A shadow slightly off the exact ratio — a mistuned string's subharmonic
    /// — is still caught inside the tolerance.
    func testToleranceCatchesDetunedShadows() {
        let a = 440.0 * pow(2, 12.0 / 1200)  // A4 +12¢
        XCTAssertEqual(surviving([a / 2, nil, a, nil]), [2])
    }

    /// A semitone is 100¢ from an octave-ratio only in the wrong direction —
    /// readings a semitone apart in frequency-ratio terms never reject each
    /// other.
    func testNearMissRatiosDoNotReject() {
        // 207.65 (G#3) vs 440: ratio 2.119, ~101¢ off the octave — must both
        // survive.
        XCTAssertEqual(surviving([207.65, nil, 440.0, nil]), [0, 2])
    }

    func testEmptyAndSingleInputs() {
        XCTAssertTrue(SubharmonicFilter.real(among: []).isEmpty)
        XCTAssertEqual(surviving([nil, nil, nil, nil]), [])
    }
}
