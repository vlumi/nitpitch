import Foundation

/// How instruments are grouped in the picker.
///
/// The grouping exists so the list's order is *visible*: within a family the
/// instruments run high to low, which is only legible as a rule if the families
/// are drawn apart. An order whose reasoning the reader can't see is
/// indistinguishable from no order at all.
public enum InstrumentFamily: String, CaseIterable, Hashable, Sendable {
    case bowed
    case fretted
    case other

    /// Untranslated section heading; the UI localizes via the string catalog.
    public var name: String {
        switch self {
        case .bowed: return "Bowed"
        case .fretted: return "Fretted"
        case .other: return "Other"
        }
    }
}

/// A tunable instrument: its open strings and the frequency band worth
/// searching. Adding an instrument is adding a case here — the detector and the
/// UI read the band and the strings, and know nothing else about it.
public struct Instrument: Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    /// Untranslated display name. The UI localizes via the string catalog.
    public let name: String
    /// Open strings, low to high, as MIDI note numbers.
    public let strings: [Int]
    public let family: InstrumentFamily

    public init(id: String, name: String, strings: [Int], family: InstrumentFamily = .other) {
        self.id = id
        self.name = name
        self.strings = strings
        self.family = family
    }

    public var notes: [Note] { strings.map(Note.init(midi:)) }

    /// The frequency band the detector should search for this instrument, with
    /// headroom below the lowest and above the highest open string.
    ///
    /// The headroom is deliberately wide (a major third down, an octave up): a
    /// badly slack string can start far below pitch and still needs to be found
    /// and shown as flat, and stopped notes go well above the open top string.
    public func band(reference: ReferencePitch = .standard) -> ClosedRange<Double> {
        guard let lowest = strings.min(), let highest = strings.max() else {
            return Detection.fullBand
        }
        let low = Note(midi: lowest - 4).frequency(reference: reference)
        let high = Note(midi: highest + 12).frequency(reference: reference)
        return low...high
    }

    /// One band per string, in the same order as `strings`, each owning the
    /// pitches nearest to its own.
    ///
    /// Boundaries sit at the **midpoint between neighbouring strings**, with
    /// headroom beyond the outermost two. Deliberately not a fixed ±N
    /// semitones: a fixed width leaves dead zones wherever strings sit further
    /// apart than 2N. On a guitar — 4 semitones between the closest pair —
    /// ±2 semitones leaves a full semitone unreachable between most strings,
    /// so a string slack enough to fall in the gap lights nothing at all,
    /// which is exactly when you most need to find it. Midpoints tile by
    /// construction: contiguous, no gaps, no overlap, for any tuning.
    ///
    /// Midpoints are taken in **MIDI space, not hertz** — pitch is
    /// logarithmic, so the arithmetic mean of two frequencies sits sharp of
    /// the note halfway between them.
    ///
    /// `maxSemitones` caps how far a band reaches from its string. It can only
    /// narrow, never widen, so the no-overlap guarantee holds at any value —
    /// but below the widest midpoint gap it *does* open gaps, and pitches in
    /// them light no dial at all. That's a deliberate diagnostic knob (see
    /// `DetectionTuning`), not a mode to ship in: at the default it binds on
    /// nothing and the midpoints stand.
    ///
    /// Empty for an instrument with no strings (chromatic), which has no
    /// targets to divide.
    public func stringBands(
        reference: ReferencePitch = .standard,
        maxSemitones: Double = DetectionTuning.default.maxSemitonesFromString
    ) -> [ClosedRange<Double>] {
        guard !strings.isEmpty else { return [] }
        let sorted = strings.sorted()

        return strings.map { midi in
            // `strings` is documented low-to-high but not enforced, so find
            // this string's neighbours in a sorted copy rather than by index.
            let position = sorted.firstIndex(of: midi) ?? 0
            let lowerMidi =
                position == 0
                ? Double(midi) - Self.outerHeadroomSemitones
                : (Double(sorted[position - 1]) + Double(midi)) / 2
            let upperMidi =
                position == sorted.count - 1
                ? Double(midi) + Self.outerHeadroomSemitones
                : (Double(midi) + Double(sorted[position + 1])) / 2
            // The midpoint is the boundary that matters — it's what makes the
            // bands tile with no gaps. `maxSemitones` only ever narrows, so a
            // band never grows into its neighbour's; at the default it binds on
            // nothing and every instrument keeps its midpoints.
            let low = Self.frequency(
                atMidi: max(lowerMidi, Double(midi) - maxSemitones), reference: reference)
            let high = Self.frequency(
                atMidi: min(upperMidi, Double(midi) + maxSemitones), reference: reference)
            return low...high
        }
    }

    /// This instrument's tuning extended (or trimmed) to `count` strings.
    ///
    /// Extension continues the template's own interval pattern on the LOW
    /// side — the dominant convention (5-string bass adds B0, 7-string
    /// guitar adds B1) — and flips to the high side when the next low string
    /// would fall below what the detector can hear. The flip is not a
    /// compromise: for a bass it derives the *real* 6-string tuning, B0 up
    /// top-side to C3, rather than an inaudible F♯0. Rarer shapes (a
    /// high-C 5-string) are one preset or a few target edits away — the
    /// point is that no count is blocked, not that every stringing is
    /// guessed. Trimming keeps the highest strings: the treble side is the
    /// melodic one.
    public func strings(count: Int) -> [Int] {
        guard !strings.isEmpty, count > 0, count != strings.count else { return strings }
        if count < strings.count { return Array(strings.suffix(count)) }
        let lowInterval = strings.count > 1 ? strings[1] - strings[0] : 5
        let highInterval =
            strings.count > 1 ? strings[strings.count - 1] - strings[strings.count - 2] : 5
        var result = strings
        for _ in 0..<(count - strings.count) {
            let below = result[0] - lowInterval
            if below >= Detection.targetMIDIRange.lowerBound {
                result.insert(below, at: 0)
            } else if let top = result.last,
                top + highInterval <= Detection.targetMIDIRange.upperBound
            {
                result.append(top + highInterval)
            } else {
                break  // nowhere left to grow
            }
        }
        return result
    }

    /// How far past the outermost strings their bands reach.
    ///
    /// A major third, matching `band(reference:)`'s headroom below the lowest
    /// string: a newly fitted string can start far below pitch and still needs
    /// to be found.
    public static let outerHeadroomSemitones = 4.0

    /// A fractional MIDI number's frequency — the boundaries fall between
    /// notes, so `Note.frequency` (which takes an integer) can't serve.
    private static func frequency(atMidi midi: Double, reference: ReferencePitch) -> Double {
        reference.hz * pow(2, (midi - 69) / 12)
    }

    // Standard tunings. MIDI: C4 = 60, A4 = 69.
    public static let violin = Instrument(
        id: "violin", name: "Violin", strings: [55, 62, 69, 76], family: .bowed)  // G3 D4 A4 E5
    public static let viola = Instrument(
        id: "viola", name: "Viola", strings: [48, 55, 62, 69], family: .bowed)  // C3 G3 D4 A4
    public static let cello = Instrument(
        id: "cello", name: "Cello", strings: [36, 43, 50, 57], family: .bowed)  // C2 G2 D3 A3
    public static let doubleBass = Instrument(
        id: "double-bass", name: "Double Bass", strings: [28, 33, 38, 43],
        family: .bowed)  // E1 A1 D2 G2
    public static let guitar = Instrument(
        id: "guitar", name: "Guitar", strings: [40, 45, 50, 55, 59, 64],
        family: .fretted)  // E2 A2 D3 G3 B3 E4
    public static let guitar7 = Instrument(
        id: "guitar-7", name: "7-string Guitar", strings: [35, 40, 45, 50, 55, 59, 64],
        family: .fretted)  // B1 + standard
    public static let guitar8 = Instrument(
        id: "guitar-8", name: "8-string Guitar",
        strings: [30, 35, 40, 45, 50, 55, 59, 64],
        family: .fretted)  // F#1 B1 + standard
    public static let bassGuitar = Instrument(
        id: "bass-guitar", name: "Bass Guitar", strings: [28, 33, 38, 43],
        family: .fretted)  // E1 A1 D2 G2
    public static let bassGuitar5 = Instrument(
        id: "bass-guitar-5", name: "5-string Bass", strings: [23, 28, 33, 38, 43],
        family: .fretted)  // B0 + standard — the note the detection floor was set for

    /// Chromatic: no fixed strings, the full detectable band.
    public static let chromatic = Instrument(
        id: "chromatic", name: "Chromatic", strings: [], family: .other)

    /// Selection order in the UI: grouped by family, and within each family
    /// ordered high to low. Violin leads because it's the app's reason for
    /// existing and its default — and because it's the highest bowed string.
    public static let all: [Instrument] = [
        .violin, .viola, .cello, .doubleBass,
        .guitar, .guitar7, .guitar8, .bassGuitar, .bassGuitar5,
        .chromatic,
    ]

    /// `all`, split into the picker's sections. Families keep the order they're
    /// declared in above rather than being sorted, so the list is stable.
    public static var grouped: [(family: InstrumentFamily, instruments: [Instrument])] {
        grouped(from: all)
    }

    /// The instruments a chooser should offer, grouped.
    ///
    /// Excludes chromatic: it's the screen you arrive from, so offering it
    /// would be offering to navigate to where you already are.
    public static var choosable: [(family: InstrumentFamily, instruments: [Instrument])] {
        grouped(from: all.filter { $0 != .chromatic })
    }

    private static func grouped(
        from instruments: [Instrument]
    ) -> [(family: InstrumentFamily, instruments: [Instrument])] {
        InstrumentFamily.allCases.compactMap { family in
            let members = instruments.filter { $0.family == family }
            return members.isEmpty ? nil : (family, members)
        }
    }

    /// The string counts this kind of instrument commonly exists with — the
    /// creation sheet's one-tap chips. Violins, violas and cellos are
    /// essentially always four, so they offer no choice at all; double
    /// basses come in four and five; the guitars have real extended
    /// families. Anything else stays reachable by editing the string list
    /// itself — common is a shortcut, not a wall.
    public var commonStringCounts: [Int] {
        switch id {
        case "double-bass": return [4, 5]
        case "guitar": return [6, 7, 8]
        case "bass-guitar": return [4, 5, 6]
        default: return [strings.count]
        }
    }

    /// The templates the + menu offers: one per instrument KIND. The
    /// N-string variants stay off this list — the string count is the next
    /// step's question, so "7-string Guitar" beside "Guitar" would ask it
    /// twice — while they remain `choosable`, where each is a ready-made
    /// instrument to open.
    public static var addable: [(family: InstrumentFamily, instruments: [Instrument])] {
        let variants: Set<String> = [guitar7.id, guitar8.id, bassGuitar5.id]
        return choosable.compactMap { group in
            let kept = group.instruments.filter { !variants.contains($0.id) }
            return kept.isEmpty ? nil : (group.family, kept)
        }
    }

    public static func named(_ id: String) -> Instrument? { all.first { $0.id == id } }
}
