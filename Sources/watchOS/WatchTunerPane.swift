import NitpitchCore
import SwiftUI
import WatchKit

/// The focused string's pane, shared by the catalog and instance screens:
/// the string's name with a checkmark once it settles, the cents against ITS
/// target, the light strip — and the crown stepping between strings
/// (explicit always wins); everything else is `StringFocus` deciding
/// hands-free, announced by the wrist's haptics rather than demanding eyes.
struct WatchTunerPane<Footer: View>: View {
    @ObservedObject var tuner: WatchInstrumentTunerViewModel
    @ViewBuilder let footer: () -> Footer

    /// The crown's position, kept in step with inferred focus moves so a
    /// twist always starts from where the screen already is.
    @State private var crown: Double = 0

    /// The reading when there is one; the arc and strip go quiet (never
    /// away) without it, so the layout is ONE fixed geometry — a rest
    /// between plucks dims the screen, it doesn't reshuffle it.
    private var liveCents: Double? {
        if case .reading(let cents) = tuner.state { return cents }
        return nil
    }

    var body: some View {
        VStack(spacing: 6) {
            header
            // The cents live INSIDE the arc's hollow — the bow frames the
            // number instead of floating above it.
            ZStack {
                // A sounding double stop hands the arc the INTERVAL's error
                // — zero when both strings sit on their targets — while the
                // strip below splits to keep each member's own.
                WatchArc(cents: tuner.pair?.intervalErrorCents ?? liveCents)
                centerLine
                    .padding(.top, 18)
            }
            if let pair = tuner.pair {
                WatchLightStrip(rows: [pair.lowerCents, pair.upperCents])
            } else {
                WatchLightStrip(cents: liveCents)
            }
            footer()
        }
        .contentShape(Rectangle())
        // Swipe between strings, beside the crown: the names run
        // left-to-right on screen, so a horizontal swipe is the gesture
        // that needs no thought — the crown's rotation direction does.
        // Swipe left = the next string up, the phone's paging direction.
        .gesture(stringSwipe)
        .focusable()
        .digitalCrownRotation(
            $crown, from: 0, through: Double(tuner.stringNames.count - 1), by: 1,
            sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true
        )
        .onChange(of: crown) { _, value in
            tuner.select(Int(value.rounded()))
        }
        .onChange(of: tuner.focusIndex) { _, index in
            // An inferred move re-homes the crown, so the next twist steps
            // from what the screen shows, not from a stale position.
            if Int(crown.rounded()) != index { crown = Double(index) }
        }
        .onAppear {
            // The crown starts where focus starts (bowed instruments open
            // on the A — see `Instrument.firstTuningIndex`), not at zero.
            crown = Double(tuner.focusIndex)
        }
        .task { await tuner.begin() }
        .onDisappear { tuner.end() }
    }

    /// Swipe left = the next string up, the phone's paging direction; a
    /// vertical drag stays the list's.
    private var stringSwipe: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                let dx = value.translation.width
                guard abs(dx) > abs(value.translation.height) else { return }
                let target = tuner.focusIndex + (dx < 0 ? 1 : -1)
                guard tuner.stringNames.indices.contains(target) else { return }
                WKInterfaceDevice.current().play(.click)
                tuner.select(target)
            }
    }

    /// The one line that changes between states — everything around it
    /// holds its ground.
    @ViewBuilder private var centerLine: some View {
        // A double stop owns the slot outright: the beat rate the taps are
        // tapping, green once the interval sits at its tempered width.
        if let pair = tuner.pair {
            Text(verbatim: String(format: "%.1f/s", pair.beatHz))
                .font(.system(size: 22, weight: .medium, design: .rounded))
                .foregroundStyle(
                    TuningDisplay.isInTune(cents: pair.intervalErrorCents) ? .green : .orange)
        } else {
            stateLine
        }
    }

    @ViewBuilder private var stateLine: some View {
        switch tuner.state {
        case .reading(let cents):
            // While the focused string's OCTAVE sounds and both intonation
            // samples are captured, the slot shows the verdict instead of
            // the cents: play open, play the 12th, read the delta — both
            // hands never leave the tools.
            if tuner.isOctaveSounding, let delta = tuner.intonationDelta {
                deltaLine(delta)
            } else {
                Text(verbatim: String(format: "%+.0f¢", cents))
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .foregroundStyle(TuningDisplay.isInTune(cents: cents) ? .green : .orange)
            }
        case .listening:
            // A measured delta OWNS the quiet: a plucked octave decays in a
            // second, and the verdict must outlive the note (field-found on
            // a bass — the delta only flashed). It clears with the captures:
            // refocus, knobs, or the crown.
            if let delta = tuner.intonationDelta {
                deltaLine(delta)
            } else {
                Text(verbatim: "Play a note")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .denied:
            Text(verbatim: "Microphone access is off")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .unavailable:
            Text(verbatim: "No microphone")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .idle:
            Text(verbatim: " ")
        }
    }

    private func deltaLine(_ delta: Double) -> some View {
        Text(verbatim: String(format: "Δ %+.1f", delta))
            .font(.system(size: 22, weight: .medium, design: .rounded))
            .foregroundStyle(TuningDisplay.isInTune(cents: delta) ? .green : .orange)
    }

    /// The string names, as many as GENUINELY fit at full size — the
    /// layout answers "fits" (the Mac rack's lesson: never estimate
    /// widths), so a violin shows all four, a plain 5-string bass all
    /// five, and anything wider — eight strings, or five names heavy with
    /// sharps ("A♯0 D♯1 G♯1…") — falls back to prev/focus/next with
    /// ellipses marking where the row continues (crown or swipe reaches
    /// it). No scale factor: shrunken names were the complaint that
    /// created this header.
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            nameRow(window: 0..<tuner.stringNames.count)
            nameRow(window: threeAroundFocus)
        }
    }

    private var threeAroundFocus: Range<Int> {
        let count = tuner.stringNames.count
        let size = min(3, count)
        let start = max(0, min(tuner.focusIndex - 1, count - size))
        return start..<(start + size)
    }

    /// One candidate row: the windowed names, the focused one large with
    /// its settled check, ellipses wherever the window cuts the row short.
    private func nameRow(window: Range<Int>) -> some View {
        HStack(spacing: 10) {
            if window.lowerBound > 0 { ellipsis }
            ForEach(window, id: \.self) { index in
                if index == tuner.focusIndex {
                    // Settled reads as COLOUR, not a checkmark: a mark adds
                    // width, and width mid-session flipped a five-name row
                    // into the three-name window at the moment of success
                    // (field-found on a half-down five-string). Green is
                    // the vocabulary the needle and cents already speak.
                    Text(verbatim: tuner.stringNames[index])
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(tuner.isSettled ? .green : .primary)
                } else {
                    // A double stop lights its OTHER member too — the
                    // header says "I'm hearing D+A" without a label.
                    Text(verbatim: tuner.stringNames[index])
                        .font(.system(size: 16, design: .rounded))
                        .foregroundStyle(isPairMember(index) ? .primary : .secondary)
                }
            }
            if window.upperBound < tuner.stringNames.count { ellipsis }
        }
        .lineLimit(1)
        .fixedSize()
    }

    private func isPairMember(_ index: Int) -> Bool {
        guard let pair = tuner.pair else { return false }
        return index == pair.lowerIndex || index == pair.upperIndex
    }

    private var ellipsis: some View {
        Text(verbatim: "…")
            .font(.system(size: 16, design: .rounded))
            .foregroundStyle(.tertiary)
    }

}
