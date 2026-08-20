import NitpitchCore
import SwiftUI

/// One string's dial, sized for the grid.
///
/// The same instrument as the full dial — arc, scale ticks, name, cents and
/// light strip — drawn smaller. Everything scales off the box, so the grid
/// doesn't become a second, poorer display with its own rules.
///
/// The cents line is **not** decoration. The arc saturates at ±50¢, so a string
/// a semitone flat and one a whole tone flat both pin at the end — the number
/// is the only thing that tells them apart, and the only way to watch progress
/// while a badly slack string is still far out.
struct CompactDial: View {
    /// The intonation layer's slice of a cell: the octave's live cents and
    /// the captured verdict. Present at all (non-nil) means the layer is
    /// on and the tiny row is drawn, populated or not.
    struct OctaveReadout {
        let cents: Double?
        let delta: Double?
    }

    let note: Note
    let naming: NoteNaming
    /// Cents from *this string's* target, or nil when it isn't sounding.
    /// Unbounded: −340 is a legitimate reading for a very slack string.
    let cents: Double?
    /// Signal strength behind the reading, 0...1. Zero when nothing reads.
    var level: Double = 0
    /// The aggregate verdict: this string has HELD in tune (`SettleMeter`).
    /// The name wears it as green — steady where the needle honestly
    /// wobbles with the bow, and the readable answer to "was that it?"
    /// when two strings sound at once.
    var isSettled = false
    /// One factor drives every dimension, so a big Mac window gets a big
    /// dial rather than a postage stamp centred in a prairie — you stand
    /// further from a big window. Capped by the caller.
    var scale: CGFloat = 1
    var octave: OctaveReadout?

    var body: some View {
        VStack(spacing: 4 * scale) {
            // The chromatic screen's meter, scaled to the cell: centre-out,
            // because a symmetric bar reads as signal the way a hardware input
            // meter does, and it shares the dial's centre-out geometry.
            LevelMeter(level: cents == nil ? 0 : level)
                .frame(height: 3)
                .padding(.horizontal, 22 * scale)
            CompactArc(cents: cents, inTune: isInTune)
                .frame(height: Self.arcHeight * scale)
                // The hollow under the arc's apex is real estate — the name
                // rises into it, the same move the full dial makes with its
                // readout (`TunerDial.apexSlack`). 28 measured against the
                // compact geometry: the band's inner edge sits ~25 into the
                // 58pt box, and the name at 30 clears the arc's line at its
                // own width.
                .padding(.bottom, -28 * scale)
            // Name and cents stacked, each centred on its own line: side by
            // side, the pair wobbled left and right as the number's width
            // changed with every reading. The name is the cell's headline;
            // growing it faster than the cell is what keeps it legible on
            // an SE, where six height-bound rows shrink everything.
            CompactNoteName(
                note: note, naming: naming, fontSize: 26 * scale,
                color: nameColor)
            Text(verbatim: centsLabel)
                .font(.system(size: 12 * scale).monospacedDigit())
                .foregroundStyle(
                    isInTune ? AnyShapeStyle(Color.green) : AnyShapeStyle(.secondary))
            // The octave's own row, squeezed above the string's dots: the
            // tiniest strip for its live reading, the verdict beside it.
            if let octave {
                HStack(spacing: 5 * scale) {
                    LightStrip(
                        cents: octave.cents ?? 0, isReading: octave.cents != nil,
                        scale: 0.3 * scale)
                    Text(verbatim: deltaLabel(octave.delta))
                        .font(.system(size: 9 * scale, weight: .semibold).monospacedDigit())
                        .foregroundStyle(deltaStyle(octave.delta))
                }
            }
            LightStrip(cents: cents ?? 0, isReading: cents != nil, scale: 0.55 * scale)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12 * scale)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: note.accessibleName(in: naming)))
        .accessibilityValue(Text(verbatim: accessibleValue))
    }

    static var arcHeight: CGFloat { 58 }

    private var isInTune: Bool {
        guard let cents else { return false }
        return TuningDisplay.isInTune(cents: cents)
    }

    /// Settled beats sounding: the verdict holds through silence, so a
    /// tuned string's name stays green after the bow lifts.
    private var nameColor: AnyShapeStyle {
        if isSettled { return AnyShapeStyle(Color.green) }
        return cents == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary)
    }

    private var centsLabel: String { TuningReadout.centsLabel(cents) }

    private var accessibleValue: String {
        let value = TuningReadout.accessibleValue(cents: cents, octaveDelta: octave?.delta)
        guard isSettled else { return value }
        return String(localized: "Tuned", bundle: .module) + ", " + value
    }

    private func deltaLabel(_ delta: Double?) -> String { TuningReadout.deltaLabel(delta) }

    private func deltaStyle(_ delta: Double?) -> AnyShapeStyle {
        TuningReadout.deltaStyle(delta)
    }
}

/// The arc alone, dimmed to a bare track when this string isn't sounding.
private struct CompactArc: View {
    let cents: Double?
    let inTune: Bool

    var body: some View {
        ZStack {
            DialTrack()
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            DialTicks()
                .stroke(Color.secondary.opacity(0.4), lineWidth: 1)
            if let cents {
                ErrorFill(sweepDegrees: TuningDisplay.arc(forCents: cents).sweepDegrees)
                    .fill(tint(for: cents))
                    .animation(.easeOut(duration: 0.12), value: cents)
            }
            CentreNeedle()
                .fill(needleColour)
        }
        .accessibilityHidden(true)
    }

    private func tint(for cents: Double) -> Color {
        Dial.tint(forCents: cents)
    }

    private var needleColour: Color {
        guard cents != nil else { return .secondary.opacity(0.4) }
        return inTune ? .green : .primary.opacity(0.85)
    }
}
