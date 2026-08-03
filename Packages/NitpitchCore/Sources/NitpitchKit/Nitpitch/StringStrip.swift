import NitpitchCore
import SwiftUI

/// One string as a strip: the name and cents at the left, the light dots
/// carrying the tuning across the width, the string's signal at the right —
/// and no arc, because at this shape the dots ARE the display.
struct StringStrip: View {
    @ObservedObject var tuner: StringTunerViewModel
    let naming: NoteNaming

    var body: some View {
        HStack(spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: tuner.target.name(in: naming))
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(
                        cents == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                Text(verbatim: centsLabel)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(
                        isInTune ? AnyShapeStyle(Color.green) : AnyShapeStyle(.secondary))
            }
            .frame(width: 130, alignment: .leading)
            Spacer(minLength: 0)
            LightStrip(cents: cents ?? 0, isReading: cents != nil, scale: 1.4)
            Spacer(minLength: 0)
            LevelMeter(level: cents == nil ? 0 : tuner.level)
                .frame(width: 48, height: 3)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: tuner.target.name(in: naming)))
        .accessibilityValue(Text(verbatim: accessibleValue))
    }

    private var cents: Double? {
        if case .reading(let cents, _) = tuner.state { return cents }
        return nil
    }

    private var isInTune: Bool {
        guard let cents else { return false }
        return TuningDisplay.isInTune(cents: cents)
    }

    private var centsLabel: String {
        guard let cents else { return "—" }
        let rounded = Int(cents.rounded())
        return rounded > 0 ? "+\(rounded)¢" : "\(rounded)¢"
    }

    private var accessibleValue: String {
        guard let cents else { return "not heard" }
        if isInTune { return "in tune" }
        let rounded = abs(Int(cents.rounded()))
        return cents < 0 ? "\(rounded) cents flat" : "\(rounded) cents sharp"
    }
}
