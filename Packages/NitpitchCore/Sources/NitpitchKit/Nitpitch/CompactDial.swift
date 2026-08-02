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
    let name: String
    /// Cents from *this string's* target, or nil when it isn't sounding.
    /// Unbounded: −340 is a legitimate reading for a very slack string.
    let cents: Double?

    var body: some View {
        VStack(spacing: 4) {
            CompactArc(cents: cents, inTune: isInTune)
                .frame(height: Self.arcHeight)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(
                        cents == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                Text(verbatim: centsLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(
                        isInTune ? AnyShapeStyle(Color.green) : AnyShapeStyle(.secondary))
            }
            LightStrip(cents: cents ?? 0, isReading: cents != nil, scale: 0.55)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: name))
        .accessibilityValue(Text(verbatim: accessibleValue))
    }

    static var arcHeight: CGFloat { 58 }

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

    /// The full dial's ramp, unchanged: brightness moves with hue so the two
    /// ends stay distinguishable in greyscale and to a colour-blind viewer.
    private func tint(for cents: Double) -> Color {
        let magnitude = min(abs(cents) / TuningDisplay.fullScaleCents, 1)
        let hue = 0.33 * pow(1 - magnitude, 1.6)
        let brightness = 1.0 - 0.55 * pow(magnitude, 0.7)
        return Color(hue: hue, saturation: 0.9, brightness: brightness)
    }

    private var needleColour: Color {
        guard cents != nil else { return .secondary.opacity(0.4) }
        return inTune ? .green : .primary.opacity(0.85)
    }
}
