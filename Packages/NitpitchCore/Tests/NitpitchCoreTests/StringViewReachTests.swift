import XCTest

@testable import NitpitchCore

/// The single-string view's band has to reach the two things that screen does
/// beyond plain tuning, both of which live ABOVE the top open string:
/// the intonation check's octave, and the 3rd-harmonic lens's 3·f. At the old
/// +12 headroom the top string's octave sat exactly ON the edge (flickering
/// in and out) and its 3·f fell outside entirely (never read at all) —
/// field-found on a guitar's E4.
final class StringViewReachTests: XCTestCase {
    private func assertReach(_ instrument: Instrument, _ name: String) {
        let band = instrument.band()
        // Chromatic has no strings and no string view to reach from.
        guard let top = instrument.notes.last?.frequency() else { return }
        // The octave must sit INSIDE, not on the boundary: a reading at the
        // edge drops in and out as the estimate wobbles a cent either way.
        let octave = 2 * top
        XCTAssertTrue(
            band.contains(octave * pow(2, 30.0 / 1200)),
            "\(name): the top string's octave needs room above it, not the edge")
        // And 3·f plus the estimator's search window, or the lens has nowhere
        // to look.
        let lens = 3 * top * pow(2, HarmonicEstimator.searchCents / 1200)
        XCTAssertTrue(
            band.contains(lens),
            "\(name): the 3rd-harmonic lens must fit inside the searched band")
    }

    func testEveryFactoryInstrumentReachesItsOctaveAndThirdHarmonic() {
        for instrument in Instrument.all {
            assertReach(instrument, instrument.name)
        }
    }
}
