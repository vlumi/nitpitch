import Foundation

/// The string-list editing rules, in one place: the live instrument editor
/// and the creation sheet's draft both edit "a list of strings", and what
/// "add a string" proposes must not depend on which of them asked.
public enum StringListEditing {
    /// Whether a string can be added at this end: only while the outermost
    /// pitch has room to extend past, in the detectable range. (What the
    /// proposed pitch IS — and that it never lands on an existing string —
    /// is `extended`'s business.)
    public static func canExtend(_ strings: [Int], lowEnd: Bool) -> Bool {
        guard let outer = lowEnd ? strings.first : strings.last else { return false }
        return lowEnd
            ? outer > Detection.targetMIDIRange.lowerBound
            : outer < Detection.targetMIDIRange.upperBound
    }

    /// Two strings on ONE pitch is the shape nothing downstream can serve:
    /// the spectral engine discards every partial the two share — all of
    /// them — and both dials go dark for good; the band split gives the
    /// pair one zero-width band. No shipped instrument has a unison course
    /// (a mandolin is modelled by its four courses), so the editor refuses
    /// the shape rather than making the engines guess.
    public static func isDistinct(_ strings: [Int]) -> Bool {
        Set(strings).count == strings.count
    }

    /// The interval "one more string" continues at an end: the outermost
    /// gap. A single string has no interval to continue; a fifth is the
    /// least surprising guess for anything strung — and it must be the SAME
    /// guess wherever growing happens, or what "add a string" proposes
    /// depends on who asked (`Instrument.strings(count:)` grows with this
    /// too).
    public static func continuationInterval(of strings: [Int], lowEnd: Bool) -> Int {
        let count = strings.count
        guard count >= 2 else { return 7 }
        let interval = lowEnd ? strings[1] - strings[0] : strings[count - 1] - strings[count - 2]
        // A zero interval (a duplicated outer pair) would propose the same
        // pitch a third time; a negative one (an unsorted list) would grow
        // the wrong way. Neither is an interval to continue — guess the
        // fifth, as for a single string.
        return interval > 0 ? interval : 7
    }

    /// The list grown by one string at the chosen end. The proposed pitch
    /// continues the outermost interval — a violin grows a viola's C3 below
    /// or a B5 above, a guitar grows a 7-string's B1 — clamped to the
    /// detectable range.
    public static func extended(_ strings: [Int], lowEnd: Bool) -> [Int] {
        guard canExtend(strings, lowEnd: lowEnd),
            let outer = lowEnd ? strings.first : strings.last
        else { return strings }
        let interval = continuationInterval(of: strings, lowEnd: lowEnd)
        let proposed = lowEnd ? outer - interval : outer + interval
        let clamped = proposed.clamped(to: Detection.targetMIDIRange)
        // The clamp can land on the outermost string itself (the range
        // edge is one step away): a duplicate is refused, not proposed.
        guard !strings.contains(clamped) else { return strings }
        return lowEnd ? [clamped] + strings : strings + [clamped]
    }

    /// The list with one string removed — never the last: a zero-string
    /// instrument is a screen with nothing on it.
    public static func removed(_ strings: [Int], at index: Int) -> [Int] {
        guard strings.count > 1, strings.indices.contains(index) else { return strings }
        var result = strings
        result.remove(at: index)
        return result
    }

    /// Whether one target may be nudged by `delta`: inside the detectable
    /// range, and never onto another string's pitch (see `isDistinct`).
    /// The editor's ± buttons disable on exactly this, so the refusal is
    /// visible before the tap.
    public static func canStep(_ strings: [Int], at index: Int, by delta: Int) -> Bool {
        guard strings.indices.contains(index) else { return false }
        let proposed = strings[index] + delta
        guard Detection.targetMIDIRange.contains(proposed) else { return false }
        return !strings.enumerated().contains { $0.offset != index && $0.element == proposed }
    }

    /// One target nudged by `delta` semitones, clamped to the detectable
    /// range — the same rule as every target stepper.
    public static func stepped(_ strings: [Int], at index: Int, by delta: Int) -> [Int] {
        guard canStep(strings, at: index, by: delta) else { return strings }
        var result = strings
        result[index] += delta
        return result
    }
}
