import Foundation

/// The string-list editing rules, in one place: the live instrument editor
/// and the creation sheet's draft both edit "a list of strings", and what
/// "add a string" proposes must not depend on which of them asked.
public enum StringListEditing {
    /// Whether a string can be added at this end: only while the outermost
    /// pitch has room to extend past — a duplicated outermost target would
    /// give two dials one zero-width band.
    public static func canExtend(_ strings: [Int], lowEnd: Bool) -> Bool {
        guard let outer = lowEnd ? strings.first : strings.last else { return false }
        return lowEnd
            ? outer > Detection.targetMIDIRange.lowerBound
            : outer < Detection.targetMIDIRange.upperBound
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
        return lowEnd ? strings[1] - strings[0] : strings[count - 1] - strings[count - 2]
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
        let clamped = min(
            max(proposed, Detection.targetMIDIRange.lowerBound),
            Detection.targetMIDIRange.upperBound)
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

    /// One target nudged by `delta` semitones, clamped to the detectable
    /// range — the same rule as every target stepper.
    public static func stepped(_ strings: [Int], at index: Int, by delta: Int) -> [Int] {
        guard strings.indices.contains(index),
            Detection.targetMIDIRange.contains(strings[index] + delta)
        else { return strings }
        var result = strings
        result[index] += delta
        return result
    }
}
