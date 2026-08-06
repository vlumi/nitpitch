import NitpitchCore
import SwiftUI

// Controls shared by every tuning screen. They live apart from any one
// screen because the per-string grid reuses all three.

/// The design-canvas presentation the full-screen tuner views share: a
/// layout drawn at a fixed design size and scaled as one unit to the
/// viewport, so proportions hold from a tiny window to a fullscreen one.
///
/// The platform split is one decision made once: Mac windows frame their
/// content (unfilled space splits around it) and earn a higher scale ceiling
/// — a big window there means a viewer across the room — while phones read
/// from the top and stay at arm's length.
enum DesignCanvas {
    static var maxScale: CGFloat {
        #if os(macOS)
        return 3.2
        #else
        return 2.2
        #endif
    }

    static var alignment: Alignment {
        #if os(macOS)
        return .center
        #else
        return .top
        #endif
    }

    static var anchor: UnitPoint {
        #if os(macOS)
        return .center
        #else
        return .top
        #endif
    }
}

/// The overall input level as its own observable island.
///
/// The meter ticks on every audibly-different frame; when that ticking
/// lived as a `@Published` on the same object a screen holds, the whole
/// screen — toolbar included — re-rendered per tick, and macOS closes an
/// open `Menu` whenever its anchor rebuilds: the grid's columns picker
/// dropped the moment any sound arrived. Only the small meter view observes
/// this island, so the ticking reaches exactly the pixels it moves.
@MainActor
final class InputLevel: ObservableObject {
    @Published private(set) var value: Double = 0

    func set(_ level: Double) {
        if level != value { value = level }
    }
}

/// The meter wired to its island — the header slot's drop-in.
struct ObservedLevelMeter: View {
    @ObservedObject var level: InputLevel

    var body: some View {
        LevelMeter(level: level.value)
            .frame(width: 72, height: 4)
    }
}

/// The compact target name: the letter with the octave subscripted — just
/// enough to tell a guitar's two E strings apart at a glance. The grid
/// cells and the strips share it; the full-size views use `NoteNameLabel`.
struct CompactNoteName: View {
    let note: Note
    let naming: NoteNaming
    let fontSize: CGFloat
    var color: AnyShapeStyle = AnyShapeStyle(.primary)

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(verbatim: note.name(in: naming))
                .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
            Text(verbatim: "\(note.octave)")
                .font(.system(size: fontSize * 0.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .baselineOffset(-fontSize * 0.06)
        }
    }
}

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

/// A speaker toggle bound to one tone tag — its own observable island, so a
/// tone starting re-renders the speakers and nothing else. Enabled on
/// locked instruments: sounding a target changes no state.
struct ToneSpeaker: View {
    @ObservedObject var tone: ToneGenerator
    let tag: String
    let identifier: String
    var font: Font = .body
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isSounding ? "speaker.wave.2.fill" : "speaker.wave.2")
                .font(font)
                .foregroundStyle(
                    isSounding ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary)
                )
                .frame(minWidth: 24, minHeight: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(Text("Reference tone", bundle: .module))
        .accessibilityValue(
            isSounding ? Text("On", bundle: .module) : Text("Off", bundle: .module))
    }

    private var isSounding: Bool { tone.playingTag == tag }
}

/// The temperament, worn where the reference is: it's the same kind of
/// fact — "A=442, pure" — and it must be readable on the tuning screens
/// themselves, because a ±2¢ target shift redraws nothing a dial would
/// show. Bowed instruments only; a tap flips it. The tuning menu keeps the
/// long-form picker ("Pure fifths"/"Pure fourths") for the labeled choice.
struct TemperamentChip: View {
    let temperament: Temperament
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            label
                .font(.callout.weight(.medium))
                .foregroundStyle(
                    temperament == .pure
                        ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary)
                )
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .overlay(
                    Capsule().strokeBorder(
                        temperament == .pure
                            ? AnyShapeStyle(.tint)
                            : AnyShapeStyle(Color.secondary.opacity(0.4)),
                        lineWidth: 1)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tuner.temperament")
        .accessibilityLabel(Text("Temperament", bundle: .module))
        .accessibilityValue(label)
    }

    private var label: Text {
        switch temperament {
        case .equal: return Text("Equal", bundle: .module)
        case .pure: return Text("Pure", bundle: .module)
        }
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
    /// Every readout leads with the LOCAL spelling — a note is something
    /// the player knows by their own name for it ("H₃", "Si₃"), targets and
    /// detections alike, with the scientific spelling in parens for
    /// cross-referencing ("(B3)"). English has no separate local spelling,
    /// so it reads plain ("A₄"). (Scientific-first detections were the
    /// original convention; wearing both forms in use settled it.)
    let note: Note
    let naming: NoteNaming
    let fontSize: CGFloat
    /// The scientific spelling in parens. The string view's target keeps it
    /// (the one place a cross-reference earns its width); the chromatic
    /// readout dropped it — "(A4)" under "La₄" says the same thing twice.
    var showsScientific = true

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
            if showsScientific, let alternate {
                Text(verbatim: "(\(alternate))")
                    .font(.system(size: fontSize * 0.40, weight: .light))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var primaryName: String {
        let readout = note.readoutLabel(in: naming)
        return readout.alternate != nil ? note.name(in: naming) : readout.name
    }

    private var alternate: String? {
        let readout = note.readoutLabel(in: naming)
        guard readout.alternate != nil else { return nil }
        return "\(readout.name)\(readout.octave)"
    }
}
