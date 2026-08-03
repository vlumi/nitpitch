import NitpitchCore
import SwiftUI

// Controls shared by every tuning screen. They live apart from any one
// screen because the per-string grid reuses all three.

/// The light strip: logarithmically spaced dots, centre lit when in tune.
///
/// Spacing doubles outward (±2, 4, 8, 16, 32¢) because the ear responds to
/// proportional error — this puts the resolution where tuning actually
/// happens instead of spreading it evenly across a semitone.
struct LightStrip: View {
    let cents: Double
    let isReading: Bool
    /// Shrinks the whole strip for a grid cell, so both sizes stay one type
    /// rather than drifting apart as two.
    var scale: CGFloat = 1

    var body: some View {
        HStack(spacing: 6 * scale) {
            ForEach(0..<TuningDisplay.lightCount, id: \.self) { index in
                Circle()
                    .fill(color(for: index))
                    .frame(width: diameter(for: index), height: diameter(for: index))
            }
        }
        .animation(.easeOut(duration: 0.1), value: cents)
        .accessibilityHidden(true)
    }

    /// The centre light is drawn larger — it's the target, so it should be the
    /// easiest thing on the strip to find without looking directly at it.
    private func diameter(for index: Int) -> CGFloat {
        (index == TuningDisplay.centerLightIndex ? 14 : 10) * scale
    }

    private func color(for index: Int) -> Color {
        guard isReading else { return .secondary.opacity(0.15) }
        let intensity = TuningDisplay.lightIntensity(index: index, cents: cents)
        guard intensity > 0 else { return .secondary.opacity(0.15) }
        let lit: Color = index == TuningDisplay.centerLightIndex ? .green : .orange
        return lit.opacity(intensity)
    }
}

/// The reference-pitch control: the `A=440` readout with a step either side.
///
/// It replaces the plain label in the header rather than adding a third menu
/// to the controls row, which is already full. Whole hertz per step, matching
/// how orchestras actually specify a pitch (442, 443, baroque 415).
struct ReferencePitchStepper: View {
    @Binding var reference: ReferencePitch
    /// The reference is "this note at this frequency", so its label follows the
    /// notation setting — `A=442` beside a readout spelling notes `La` or `イ`
    /// would name the same pitch two different ways on one screen.
    let naming: NoteNaming

    var body: some View {
        HStack(spacing: 10) {
            button("minus", enabled: reference.canLower) { reference = reference.lowered() }
            Text(verbatim: "\(naming.concertAName)=\(Int(reference.hz))")
                .font(.body.monospacedDigit())
                .foregroundStyle(.primary)
                // Fixed width so the row doesn't shift when the value goes
                // from three digits to two, or the glyph widths change.
                .frame(minWidth: 78)
                .accessibilityIdentifier("tuner.reference")
                .accessibilityLabel(Text("Reference pitch", bundle: .module))
                .accessibilityValue(Text(verbatim: "\(Int(reference.hz)) Hz"))
            button("plus", enabled: reference.canRaise) { reference = reference.raised() }
        }
        // The buttons are the adjustment; VoiceOver gets one adjustable
        // element instead of three separate stops.
        .accessibilityElement(children: .combine)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: reference = reference.raised()
            case .decrement: reference = reference.lowered()
            @unknown default: break
            }
        }
    }

    private func button(
        _ systemName: String, enabled: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.medium))
                // 44pt is the minimum comfortable touch target, and the Mac
                // needs the same visual weight even though a pointer is
                // precise — this is a primary control, not a corner label.
                .frame(width: 44, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.35))
    }
}

/// Input level — shows the app is hearing something even when no pitch is
/// confident enough to display.
///
/// Grows outward from the centre rather than filling left to right: a
/// left-anchored bar reads as progress toward something, while a symmetric one
/// reads as signal, the way a hardware input meter does. It also shares the
/// dial's centre-out geometry, so the two agree.
struct LevelMeter: View {
    let level: Double

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Capsule().fill(Color.secondary.opacity(0.2))
                Capsule()
                    .fill(Color.secondary)
                    .frame(width: geo.size.width * level)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .animation(.easeOut(duration: 0.1), value: level)
        .accessibilityHidden(true)
    }
}

/// A note's name with subscripted octave and the chosen convention's spelling
/// beside it — the readout's centrepiece, shared by the chromatic tuner and
/// the string view. See `Note.readoutLabel(in:)` for why the scientific name
/// and the localized one are kept apart rather than combined.
struct NoteNameLabel: View {
    /// Which spelling leads. Detections read scientific-first ("A4 (イ)") —
    /// the settled chromatic convention — but a *target* is something the
    /// player asked for by its own name, so the string view leads with the
    /// local spelling: "H₀ (B0)", not "B0 (H)". The grid cells show the local
    /// name alone; this keeps the detail view consistent with them.
    enum Order {
        case scientificFirst
        case localizedFirst
    }

    let note: Note
    let naming: NoteNaming
    let fontSize: CGFloat
    var order: Order = .scientificFirst

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            // The octave is subscripted so the letter stays the thing you read
            // at a glance — the number qualifies it rather than competing.
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(verbatim: primaryName)
                    .font(.system(size: fontSize, weight: .light, design: .rounded))
                Text(verbatim: "\(note.octave)")
                    .font(.system(size: fontSize * 0.44, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
                    .baselineOffset(-fontSize * 0.06)
            }
            if let alternate {
                Text(verbatim: "(\(alternate))")
                    .font(.system(size: fontSize * 0.40, weight: .light))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var primaryName: String {
        let readout = note.readoutLabel(in: naming)
        if order == .localizedFirst, readout.alternate != nil {
            return note.name(in: naming)
        }
        return readout.name
    }

    private var alternate: String? {
        let readout = note.readoutLabel(in: naming)
        guard let localized = readout.alternate else { return nil }
        return order == .localizedFirst ? "\(readout.name)\(readout.octave)" : localized
    }
}
