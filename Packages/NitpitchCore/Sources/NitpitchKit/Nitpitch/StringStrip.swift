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
    /// The intonation layer: the octave's tiny dots squeezed above the
    /// string's own, the verdict in a slot of its own — there's width to
    /// spare in a strip.
    var isIntonating = false
    /// The string's speaker, INSIDE the card — out on the string line it
    /// was invisible (the field couldn't spot it).
    var tone: ToneGenerator?
    var toneTag = ToneTag.single
    var toneIdentifier = ""
    var onToneToggle: (() -> Void)?
    /// When set, the card publishes its bounds under this string index —
    /// how the interval chip finds the pair it must straddle.
    var boundsIndex: Int?

    var body: some View {
        HStack(spacing: 12 * scale) {
            stringLine
            card
            stringLine
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: tuner.target.accessibleName(in: naming)))
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
            // The octave rides as a subscript here too — a guitar has two
            // E strings, and the strips are where they sit side by side.
            // A size bigger in a slot a touch narrower: the old 60pt slot
            // left dead air between short names and the flat-cents column.
            CompactNoteName(
                note: tuner.target, naming: naming, fontSize: 27 * scale,
                color: cents == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary)
            )
            .frame(width: 54 * scale, alignment: .leading)
            centsSlot(flatSide: true)
            VStack(spacing: 5 * scale) {
                if isIntonating {
                    LightStrip(
                        cents: tuner.octaveCents ?? 0,
                        isReading: tuner.octaveCents != nil,
                        scale: 0.55 * scale)
                }
                LightStrip(cents: cents ?? 0, isReading: cents != nil, scale: 1.4 * scale)
                // The signal, squeezed under the dots: worth a glance, not a
                // column of its own.
                LevelMeter(level: cents == nil ? 0 : tuner.level)
                    .frame(width: 80 * scale, height: 2)
            }
            centsSlot(flatSide: false)
            if isIntonating {
                deltaSlot
            }
            if let tone, let onToneToggle {
                ToneSpeaker(
                    tone: tone, tag: toneTag, identifier: toneIdentifier,
                    font: .caption, action: onToneToggle)
            }
        }
        // Trimmed from 16/12: the interval chip lives in the side margin
        // now, and the cards ceding a few points is what gives it its
        // room — the vertical trim buys back the bigger name, so the
        // card's height holds.
        .padding(.horizontal, 10 * scale)
        .padding(.vertical, 10 * scale)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .anchorPreference(key: StripCardBoundsKey.self, value: .bounds) { anchor in
            boundsIndex.map { [$0: anchor] } ?? [:]
        }
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

    /// The intonation verdict, in a reserved slot like the cents': the
    /// number arriving must not shift the row.
    private var deltaSlot: some View {
        Text(verbatim: TuningReadout.deltaLabel(tuner.delta))
            .font(.system(size: 14 * scale, weight: .medium).monospacedDigit())
            .foregroundStyle(deltaStyle)
            .frame(width: 64 * scale, alignment: .leading)
    }

    private var deltaStyle: AnyShapeStyle { TuningReadout.deltaStyle(tuner.delta) }

    private var cents: Double? {
        if case .reading(let cents, _) = tuner.state { return cents }
        return nil
    }

    private var isInTune: Bool {
        guard let cents else { return false }
        return TuningDisplay.isInTune(cents: cents)
    }

    private var accessibleValue: String {
        TuningReadout.accessibleValue(
            cents: cents, octaveDelta: isIntonating ? tuner.delta : nil)
    }
}
