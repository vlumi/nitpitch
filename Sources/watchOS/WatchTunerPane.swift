import NitpitchCore
import SwiftUI

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

    var body: some View {
        VStack(spacing: 6) {
            header
            switch tuner.state {
            case .reading(let cents):
                Text(verbatim: String(format: "%+.0f¢", cents))
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .foregroundStyle(TuningDisplay.isInTune(cents: cents) ? .green : .orange)
                lightStrip(cents: cents)
            case .listening:
                Text(verbatim: "Play a note")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                lightStrip(cents: .infinity).opacity(0.4)
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
            footer()
        }
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
        .task { await tuner.begin() }
        .onDisappear { tuner.end() }
    }

    /// The string's name, flanked by its neighbours — where the crown leads,
    /// dimly visible, and a check when this one is done.
    private var header: some View {
        HStack(spacing: 10) {
            ForEach(tuner.stringNames.indices, id: \.self) { index in
                if index == tuner.focusIndex {
                    HStack(spacing: 3) {
                        Text(verbatim: tuner.stringNames[index])
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                        if tuner.isSettled {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.green)
                        }
                    }
                } else {
                    Text(verbatim: tuner.stringNames[index])
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    private func lightStrip(cents: Double) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<TuningDisplay.lightCount, id: \.self) { index in
                Circle()
                    .fill(
                        index == TuningDisplay.centerLightIndex ? Color.green : Color.orange
                    )
                    .opacity(
                        0.15 + 0.85 * TuningDisplay.lightIntensity(index: index, cents: cents)
                    )
                    .frame(width: 7, height: 7)
            }
        }
    }
}
