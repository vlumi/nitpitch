import NitpitchCore
import SwiftUI

/// The string pane in intonation mode: the same dial, measuring whichever of
/// the two notes is sounding — the headline names it, the badge says which
/// slot it is. Mirrors `StringDialPane`'s geometry exactly, so flipping the
/// mode moves nothing.
struct IntonationDialPane: View {
    @ObservedObject var monitor: IntonationMonitor
    /// The open string's target; the octave headline derives from it.
    let target: Note
    let naming: NoteNaming

    var body: some View {
        TunerDial(cents: displayCents, inTune: isInTune, isReading: monitor.live != nil) {
            readout
        }
    }

    private var readout: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Color.clear.frame(width: 40, height: 40)
                NoteNameLabel(note: displayNote, naming: naming, fontSize: 46)
                    .frame(width: 190)
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("intonation.note")
                    .accessibilityLabel(displayNote.accessibleName(in: naming))
                Color.clear.frame(width: 40, height: 40)
            }
            HStack(spacing: 8) {
                Text(verbatim: centsLabel)
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(
                        isInTune
                            ? AnyShapeStyle(Color.green)
                            : AnyShapeStyle(.secondary))
                slotBadge
            }
        }
        .frame(height: 46 * 1.15 + 4 + 20)
    }

    /// The note being measured: the octave's own name while the octave
    /// sounds, so the headline never claims E₂ while showing E₃'s cents.
    private var displayNote: Note {
        monitor.live?.slot == .octave ? Note(midi: target.midi + 12) : target
    }

    private var slotBadge: some View {
        Group {
            switch monitor.live?.slot {
            case .open: Text("Open", bundle: .module)
            case .octave: Text("Octave", bundle: .module)
            case nil: Text(verbatim: " ")
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.secondary.opacity(0.15)))
        .opacity(monitor.live == nil ? 0 : 1)
    }

    private var centsLabel: String {
        guard let live = monitor.live else { return "—" }
        let rounded = Int(live.cents.rounded())
        return rounded > 0 ? "+\(rounded)¢" : "\(rounded)¢"
    }

    private var displayCents: Double {
        monitor.live?.cents ?? 0
    }

    private var isInTune: Bool {
        guard let live = monitor.live else { return false }
        return TuningDisplay.isInTune(cents: live.cents)
    }
}

/// The captured measurement, where the reference stepper stands in tuning
/// mode: the two samples, styled apart — the open reference filled, the
/// octave outlined — and the verdict between them.
struct IntonationReadout: View {
    @ObservedObject var monitor: IntonationMonitor

    var body: some View {
        HStack(spacing: 12) {
            chip(
                label: Text("Open", bundle: .module),
                value: monitor.open,
                isLive: monitor.live?.slot == .open,
                filled: true,
                id: "intonation.open")
            chip(
                label: Text("Octave", bundle: .module),
                value: monitor.octave,
                isLive: monitor.live?.slot == .octave,
                filled: false,
                id: "intonation.octave")
            delta
        }
        .frame(height: 30)
    }

    /// The headline number: how far the octave sits from where the open
    /// string promises it. Green once the pair agrees within the same
    /// tolerance the dial calls in tune; orange while it doesn't.
    private var delta: some View {
        HStack(spacing: 4) {
            Text(verbatim: "Δ")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(verbatim: monitor.delta.map(Self.cents) ?? "—")
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(deltaStyle)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("intonation.delta")
        .accessibilityLabel(Text("Octave versus open", bundle: .module))
        .accessibilityValue(Text(verbatim: monitor.delta.map(Self.cents) ?? "—"))
    }

    private var deltaStyle: AnyShapeStyle {
        guard let delta = monitor.delta else { return AnyShapeStyle(.secondary) }
        return TuningDisplay.isInTune(cents: delta)
            ? AnyShapeStyle(Color.green) : AnyShapeStyle(Color.orange)
    }

    private func chip(
        label: Text, value: Double?, isLive: Bool, filled: Bool, id: String
    ) -> some View {
        HStack(spacing: 5) {
            label
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(verbatim: value.map(Self.cents) ?? "—")
                .font(.callout.monospacedDigit())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(filled ? Color.secondary.opacity(0.12) : Color.clear)
        )
        .overlay(
            Capsule().strokeBorder(
                isLive ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.secondary.opacity(0.35)),
                lineWidth: isLive ? 1.5 : 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(id)
        .accessibilityLabel(label)
        .accessibilityValue(Text(verbatim: value.map(Self.cents) ?? "—"))
    }

    /// One decimal: saddle work happens in single cents, and the captures
    /// are stable enough to deserve the digit.
    private static func cents(_ value: Double) -> String {
        String(format: "%+.1f¢", value)
    }
}
