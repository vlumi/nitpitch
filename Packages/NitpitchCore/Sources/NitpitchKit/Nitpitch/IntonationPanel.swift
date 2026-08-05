import NitpitchCore
import SwiftUI

/// The octave's own tuner and the intonation verdict, ambient below the
/// string switcher: a second dial for the 12th fret (or the fingered octave,
/// or the harmonic — they all land here), lit whenever the octave sounds,
/// beside the captured samples and the delta between them.
///
/// No mode. The main dial answers "how far is this from the open target" and
/// goes quiet when the octave plays; this panel answers for the octave; the
/// verdict updates whenever both have been held. The screen simply shows
/// everything it knows.
struct IntonationPanel: View {
    @ObservedObject var monitor: IntonationMonitor
    /// The open string's target; the octave derives from it.
    let target: Note
    let naming: NoteNaming

    /// Measured: the compact dial's own stack at 0.8 scale.
    static let height: CGFloat = 104

    var body: some View {
        HStack(spacing: 16) {
            CompactDial(
                note: Note(midi: target.midi + 12),
                naming: naming,
                cents: octaveCents,
                level: octaveLevel,
                scale: 0.8
            )
            .frame(width: 190)
            .accessibilityIdentifier("intonation.dial")
            values
        }
        .frame(height: Self.height)
    }

    private var octaveCents: Double? {
        guard let live = monitor.live, live.slot == .octave else { return nil }
        return live.cents
    }

    private var octaveLevel: Double {
        guard let live = monitor.live, live.slot == .octave else { return 0 }
        return live.level
    }

    /// The measurement: both captures and the verdict, each on its own
    /// line — the delta is the headline, green within the same tolerance
    /// the dials call in tune.
    private var values: some View {
        VStack(alignment: .leading, spacing: 6) {
            row(
                label: Text("Open", bundle: .module),
                value: monitor.open, id: "intonation.open")
            row(
                label: Text("Octave", bundle: .module),
                value: monitor.octave, id: "intonation.octave")
            HStack(spacing: 6) {
                Text(verbatim: "Δ")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .leading)
                Text(verbatim: monitor.delta.map(Self.cents) ?? "—")
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .foregroundStyle(deltaStyle)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("intonation.delta")
            .accessibilityLabel(Text("Octave versus open", bundle: .module))
            .accessibilityValue(Text(verbatim: monitor.delta.map(Self.cents) ?? "—"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(label: Text, value: Double?, id: String) -> some View {
        HStack(spacing: 6) {
            label
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)
            Text(verbatim: value.map(Self.cents) ?? "—")
                .font(.callout.monospacedDigit())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(id)
        .accessibilityLabel(label)
        .accessibilityValue(Text(verbatim: value.map(Self.cents) ?? "—"))
    }

    private var deltaStyle: AnyShapeStyle {
        guard let delta = monitor.delta else { return AnyShapeStyle(.secondary) }
        return TuningDisplay.isInTune(cents: delta)
            ? AnyShapeStyle(Color.green) : AnyShapeStyle(Color.orange)
    }

    /// One decimal: saddle work happens in single cents, and the captures
    /// are stable enough to deserve the digit.
    private static func cents(_ value: Double) -> String {
        String(format: "%+.1f¢", value)
    }
}
