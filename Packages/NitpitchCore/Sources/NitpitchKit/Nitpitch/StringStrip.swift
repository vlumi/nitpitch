import NitpitchCore
import SwiftUI

/// One string as a string: a compact card — name, dots, cents — threaded on
/// a line that runs to both screen edges, drawn at the string's own gauge,
/// so the fat strings read fat at a glance. No arc: at this shape the dots
/// ARE the display.
///
/// The card's slots are all fixed, which is what keeps every row's card the
/// same width (they hug identical content) and the columns aligned without
/// any coordination between rows. The cents sit where the pitch leans —
/// left of the dots when flat, right when sharp — in a reserved slot each,
/// so the number's arrival never shifts the row: the side answers "which
/// way" before the number answers "how far", with no sign or unit to parse.
struct StringStrip: View {
    @ObservedObject var tuner: StringTunerViewModel
    let naming: NoteNaming
    /// One factor drives every dimension — computed by the caller so all
    /// strips FIT the viewport (a phone in landscape) or fill it (a big
    /// window), never scroll.
    var scale: CGFloat = 1
    /// The string's drawn thickness in design points — the caller grades it
    /// by pitch, lowest fattest, like the strings in your hand.
    var gauge: CGFloat = 3

    var body: some View {
        HStack(spacing: 12 * scale) {
            stringLine
            card
            stringLine
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: tuner.target.name(in: naming)))
        .accessibilityValue(Text(verbatim: accessibleValue))
    }

    /// The string itself, at its own gauge, filling whatever the card
    /// doesn't take — both sides flexible, so the cards sit centred.
    private var stringLine: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.35))
            .frame(height: gauge * scale)
            .frame(maxWidth: .infinity)
    }

    private var card: some View {
        HStack(spacing: 10 * scale) {
            Text(verbatim: tuner.target.name(in: naming))
                .font(.system(size: 24 * scale, weight: .semibold, design: .rounded))
                .foregroundStyle(
                    cents == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary)
                )
                .frame(width: 60 * scale, alignment: .leading)
            centsSlot(flatSide: true)
            VStack(spacing: 5 * scale) {
                LightStrip(cents: cents ?? 0, isReading: cents != nil, scale: 1.4 * scale)
                // The signal, squeezed under the dots: worth a glance, not a
                // column of its own.
                LevelMeter(level: cents == nil ? 0 : tuner.level)
                    .frame(width: 80 * scale, height: 2)
            }
            centsSlot(flatSide: false)
        }
        .padding(.horizontal, 16 * scale)
        .padding(.vertical, 12 * scale)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    /// The magnitude alone, on the side the pitch leans — flat's slot sits
    /// before the dots, sharp's after. Both slots are always reserved, so
    /// nothing wobbles when a reading starts, stops, or changes sign.
    private func centsSlot(flatSide: Bool) -> some View {
        Text(verbatim: slotText(flatSide: flatSide))
            .font(.system(size: 20 * scale, weight: .medium).monospacedDigit())
            .foregroundStyle(
                isInTune ? AnyShapeStyle(Color.green) : AnyShapeStyle(.secondary)
            )
            .frame(width: 46 * scale, alignment: flatSide ? .trailing : .leading)
    }

    private func slotText(flatSide: Bool) -> String {
        guard let cents else { return "" }
        let rounded = Int(cents.rounded())
        // Zero — in tune — reads on the sharp side, next to where it would
        // first drift visible.
        let belongsHere = flatSide ? rounded < 0 : rounded >= 0
        return belongsHere ? "\(abs(rounded))" : ""
    }

    private var cents: Double? {
        if case .reading(let cents, _) = tuner.state { return cents }
        return nil
    }

    private var isInTune: Bool {
        guard let cents else { return false }
        return TuningDisplay.isInTune(cents: cents)
    }

    private var accessibleValue: String {
        guard let cents else { return "not heard" }
        if isInTune { return "in tune" }
        let rounded = abs(Int(cents.rounded()))
        return cents < 0 ? "\(rounded) cents flat" : "\(rounded) cents sharp"
    }
}
