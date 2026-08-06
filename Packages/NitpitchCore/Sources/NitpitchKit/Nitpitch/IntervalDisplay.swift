import NitpitchCore
import SwiftUI

/// The interval readout's state, its own observable island: a beat number
/// arrives per frame, and only the chip should re-render for it.
@MainActor
final class IntervalMonitor: ObservableObject {
    struct Display: Equatable {
        let lowerIndex: Int
        let upperIndex: Int
        let kind: IntervalBeat.Kind
        /// Smoothed and tenth-quantized.
        let beatHz: Double
        /// Signed vs pure: positive wide, negative narrow.
        let wideCents: Double
        /// What the beat should read once both strings sit on their
        /// targets — 0 under pure, ~1 Hz for equal's fifth.
        let targetBeatHz: Double
    }

    @Published private(set) var display: Display?

    private var midis: [Int] = []
    private var targets: [Double] = []
    private var smoothedBeat: Double?
    private var quietFrames = 0
    private static let quietFramesBeforeClear = 4

    func configure(midis: [Int], targets: [Double]) {
        self.midis = midis
        self.targets = targets
        reset()
    }

    /// One frame's per-string frequencies (octave claims already excluded
    /// by the caller — a claimed 2f is not an open string sounding).
    func ingest(frequencies: [Double?]) {
        guard let reading = IntervalBeat.resolve(frequencies: frequencies, midis: midis)
        else {
            quietFrames += 1
            if quietFrames >= Self.quietFramesBeforeClear, display != nil {
                smoothedBeat = nil
                display = nil
            }
            return
        }
        quietFrames = 0
        // Light smoothing: the pitches jitter sub-cent frame to frame, and
        // half a hertz of beat flutter would read as indecision.
        let smoothed = (smoothedBeat ?? reading.beatHz) * 0.7 + reading.beatHz * 0.3
        smoothedBeat = smoothed
        let upper = reading.lowerIndex + 1
        let next = Display(
            lowerIndex: reading.lowerIndex,
            upperIndex: upper,
            kind: reading.kind,
            beatHz: (smoothed * 10).rounded() / 10,
            wideCents: (reading.wideCents * 10).rounded() / 10,
            targetBeatHz: targets.indices.contains(upper)
                ? (IntervalBeat.targetBeatHz(
                    kind: reading.kind,
                    lowerTargetHz: targets[reading.lowerIndex],
                    upperTargetHz: targets[upper]) * 10).rounded() / 10
                : 0)
        if next != display { display = next }
    }

    func reset() {
        smoothedBeat = nil
        quietFrames = 0
        display = nil
    }
}

/// The interval chip: the pair, the beats, the aim — and a dot that pulses
/// at the true rate, so the eye can sync with what the ear hears. Steady
/// (and green) once the beating effectively stops at its target.
struct IntervalChip: View {
    let display: IntervalMonitor.Display
    let notes: [Note]
    let naming: NoteNaming

    var body: some View {
        HStack(spacing: 8) {
            pulsingDot
            if notes.indices.contains(display.lowerIndex),
                notes.indices.contains(display.upperIndex)
            {
                HStack(spacing: 2) {
                    CompactNoteName(
                        note: notes[display.lowerIndex], naming: naming, fontSize: 14)
                    Text(verbatim: "–")
                        .foregroundStyle(.secondary)
                    CompactNoteName(
                        note: notes[display.upperIndex], naming: naming, fontSize: 14)
                }
            }
            kindLabel
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(verbatim: beatText)
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(onTarget ? AnyShapeStyle(Color.green) : AnyShapeStyle(.primary))
            if display.targetBeatHz > 0.05 {
                Text(verbatim: "→ \(format(display.targetBeatHz))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if !onTarget {
                directionLabel
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Capsule().fill(.thinMaterial))
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("tuner.interval")
        .accessibilityLabel(Text("Interval", bundle: .module))
        .accessibilityValue(Text(verbatim: accessibleValue))
    }

    /// Close enough to the temperament's own answer that the ear hears
    /// "done": within a fifth of a hertz of the target rate.
    private var onTarget: Bool {
        abs(display.beatHz - display.targetBeatHz) < 0.2
    }

    /// The pulse, computed rather than animated with a keyframe: the rate
    /// changes every frame while tuning, and TimelineView follows it
    /// continuously. Capped at 8 Hz — past that the ear hears roughness,
    /// not pulses, and the eye gave up earlier still.
    private var pulsingDot: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let rate = min(display.beatHz, 8)
            let phase =
                rate < 0.05
                ? 1.0
                : 0.5 + 0.5 * sin(2 * .pi * rate * context.date.timeIntervalSinceReferenceDate)
            Circle()
                .fill(onTarget ? Color.green : Color.orange)
                .frame(width: 10, height: 10)
                .opacity(0.25 + 0.75 * phase)
        }
    }

    private var kindLabel: Text {
        switch display.kind {
        case .fifth: return Text("fifth", bundle: .module)
        case .fourth: return Text("fourth", bundle: .module)
        }
    }

    private var directionLabel: Text {
        display.wideCents < 0
            ? Text("narrow", bundle: .module) : Text("wide", bundle: .module)
    }

    private var beatText: String {
        display.beatHz < 0.05 ? "0/s" : "\(format(display.beatHz))/s"
    }

    private func format(_ hz: Double) -> String {
        String(format: "%.1f", hz)
    }

    private var accessibleValue: String {
        var parts = ["\(format(display.beatHz)) beats per second"]
        if display.targetBeatHz > 0.05 {
            parts.append("aim \(format(display.targetBeatHz))")
        }
        if !onTarget {
            parts.append(display.wideCents < 0 ? "narrow" : "wide")
        }
        return parts.joined(separator: ", ")
    }
}

/// The grid's fixed interval lane, directly under the level meter: one
/// place in every column count, height always reserved so the dials never
/// reflow when a double stop starts or stops. Adjacent strings aren't
/// reliably adjacent CELLS (a two-column violin puts D and A on a
/// diagonal), so the grid gets a lane and the sounding pair gets a tinted
/// edge instead of a spatial marker.
struct IntervalLane: View {
    @ObservedObject var interval: IntervalMonitor
    let notes: [Note]
    let naming: NoteNaming

    static let height: CGFloat = 34

    var body: some View {
        ZStack {
            if let display = interval.display {
                IntervalChip(display: display, notes: notes, naming: naming)
            }
        }
        .frame(height: Self.height)
    }
}

/// The strips' home for the chip: centered on the boundary the sounding
/// pair shares — adjacent strings are adjacent rows there by construction.
/// Positioned arithmetically (the strips are a plain VStack with known row
/// heights), never by inserting a row: nothing may reflow mid-bow.
struct StripsIntervalOverlay: View {
    @ObservedObject var interval: IntervalMonitor
    let notes: [Note]
    let naming: NoteNaming
    let rowHeight: CGFloat
    let rowSpacing: CGFloat
    let count: Int
    let lowOnTop: Bool

    var body: some View {
        if let display = interval.display {
            let lowerRow = displayRow(display.lowerIndex)
            let upperRow = displayRow(display.upperIndex)
            let boundary = CGFloat(min(lowerRow, upperRow) + 1)
            let centerY = boundary * rowHeight + (boundary - 0.5) * rowSpacing
            IntervalChip(display: display, notes: notes, naming: naming)
                .offset(y: centerY - IntervalLane.height / 2)
        }
    }

    private func displayRow(_ index: Int) -> Int {
        lowOnTop ? index : count - 1 - index
    }
}

/// The tinted edge on a cell whose string is one half of the sounding
/// pair — the lane names the pair; this is where the eye lands next.
struct IntervalHighlight: View {
    @ObservedObject var interval: IntervalMonitor
    let index: Int

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1.5)
            .opacity(isMember ? 1 : 0)
            .allowsHitTesting(false)
    }

    private var isMember: Bool {
        guard let display = interval.display else { return false }
        return index == display.lowerIndex || index == display.upperIndex
    }
}
