import Foundation
import NitpitchCore

/// The grid's frame router while the intonation layer is on: readings that
/// are really some string's OCTAVE get claimed by that string, wherever the
/// bank happened to put them. Pure, so the bass field case is a test.
///
/// Why it exists: parity alone starved the low strings. The spectral
/// estimator barely functions below ~90 Hz — a bass E1's whole search
/// window is narrower than one FFT bin, and the fourths tuning eats even
/// slots (E1's 4th harmonic IS A1's 3rd, skipped as shared) — so on a bass
/// only the G string's octave ever classified. Meanwhile MPM was finding
/// the fretted notes every frame and attributing them as wrong-string
/// noise: E1's 12th fret lands in the D string's BAND (+200¢ on its dial),
/// because a string's own octave is always outside its own band and inside
/// a neighbour's. The information arrives; it just lands on the wrong dial.
///
/// The claim rule: a reading within `octaveWindowCents` of some string's 2f
/// becomes that string's octave — normalized into the same parity-shaped
/// result the spectral path produces (frequency halved, flag set), so the
/// view models have exactly one octave path. The window is tighter than the
/// single-string screen's ±150: fourths put the nearest competing
/// interpretation (a badly flat neighbour) 200¢ from a 2f, and ±75 keeps
/// the two regimes apart with margin. A string whose own dial is reading
/// keeps its reading — a claim never overwrites live evidence.
enum GridIntonationRouting {
    static let octaveWindowCents = 75.0

    /// One frame in, one frame out: per-string results with octave findings
    /// claimed by their owners and silenced where they landed. `above` is
    /// the bank's sentinel reading — the note above every band, which is
    /// where the TOP strings' octaves live by construction (a band tops out
    /// a few semitones past its string, and an octave is twelve).
    static func route(
        results: [DetectionResult], targets: [Double], above: DetectionResult? = nil
    ) -> [DetectionResult] {
        var routed = results
        for (index, result) in results.enumerated() {
            // Spectral parity frames are already shaped; only unflagged
            // readings (MPM's, in practice) need claiming.
            guard let hz = result.frequency, !result.evenPartialsOnly else { continue }
            guard let owner = octaveOwner(of: hz, targets: targets) else { continue }
            // The dial the reading landed on goes quiet — its clarity and
            // rms stay for diagnostics.
            routed[index] = DetectionResult(
                frequency: nil, clarity: result.clarity, rms: result.rms)
            claim(hz, from: result, for: owner, in: &routed)
        }
        if let above, let hz = above.frequency,
            let owner = octaveOwner(of: hz, targets: targets)
        {
            claim(hz, from: above, for: owner, in: &routed)
        }
        return routed
    }

    /// The owner takes the reading in parity shape — unless its own dial
    /// has live evidence this frame, which a claim never overwrites.
    private static func claim(
        _ hz: Double, from result: DetectionResult, for owner: Int,
        in routed: inout [DetectionResult]
    ) {
        guard routed[owner].frequency == nil else { return }
        routed[owner] = DetectionResult(
            frequency: hz / 2, clarity: result.clarity, rms: result.rms,
            level: result.displayLevel, evenPartialsOnly: true)
    }

    /// The string whose octave this reading is — the nearest 2f within the
    /// window — or nil when it's nobody's.
    ///
    /// A reading that is plausibly an OPEN string is never claimed: in an
    /// octave tuning like Drop D, the low string's 2f IS the open D3 — one
    /// frequency, two meanings — and claiming it would dark the D3 dial
    /// whenever it plays and record fake octave samples besides. That
    /// octave slot honestly stays empty instead (the roadmap's promise).
    /// Standard tunings never trip this: every 2f sits ≥200¢ from every
    /// fundamental.
    private static func octaveOwner(of hz: Double, targets: [Double]) -> Int? {
        let nearAFundamental = targets.contains { target in
            target > 0 && abs(1200 * log2(hz / target)) <= octaveWindowCents
        }
        guard !nearAFundamental else { return nil }
        var best: (index: Int, cents: Double)?
        for (index, target) in targets.enumerated() where target > 0 {
            let cents = abs(1200 * log2(hz / (2 * target)))
            guard cents <= octaveWindowCents else { continue }
            if best == nil || cents < best!.cents {
                best = (index, cents)
            }
        }
        return best?.index
    }
}
