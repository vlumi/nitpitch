import Foundation

/// A tunable instrument: its open strings and the frequency band worth
/// searching. Adding an instrument is adding a case here — the detector and the
/// UI read the band and the strings, and know nothing else about it.
public struct Instrument: Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    /// Untranslated display name. The UI localizes via the string catalog.
    public let name: String
    /// Open strings, low to high, as MIDI note numbers.
    public let strings: [Int]

    public init(id: String, name: String, strings: [Int]) {
        self.id = id
        self.name = name
        self.strings = strings
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

    // Standard tunings. MIDI: C4 = 60, A4 = 69.
    public static let violin = Instrument(
        id: "violin", name: "Violin", strings: [55, 62, 69, 76])  // G3 D4 A4 E5
    public static let viola = Instrument(
        id: "viola", name: "Viola", strings: [48, 55, 62, 69])  // C3 G3 D4 A4
    public static let cello = Instrument(
        id: "cello", name: "Cello", strings: [36, 43, 50, 57])  // C2 G2 D3 A3
    public static let doubleBass = Instrument(
        id: "double-bass", name: "Double Bass", strings: [28, 33, 38, 43])  // E1 A1 D2 G2
    public static let guitar = Instrument(
        id: "guitar", name: "Guitar", strings: [40, 45, 50, 55, 59, 64])  // E2 A2 D3 G3 B3 E4
    public static let bassGuitar = Instrument(
        id: "bass-guitar", name: "Bass Guitar", strings: [28, 33, 38, 43])  // E1 A1 D2 G2

    /// Chromatic: no fixed strings, the full detectable band.
    public static let chromatic = Instrument(id: "chromatic", name: "Chromatic", strings: [])

    /// Selection order in the UI — violin first (the app's reason for existing).
    public static let all: [Instrument] = [
        .violin, .viola, .cello, .doubleBass, .guitar, .bassGuitar, .chromatic,
    ]

    public static func named(_ id: String) -> Instrument? { all.first { $0.id == id } }
}
