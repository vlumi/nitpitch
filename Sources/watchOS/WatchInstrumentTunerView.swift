import NitpitchCore
import SwiftUI

/// The focused string's screen: its name, the cents against ITS target, the
/// light strip — and a checkmark once it settles. The crown steps between
/// strings (explicit always wins); everything else is `StringFocus` deciding
/// hands-free, announced by the wrist's haptics rather than demanding eyes.
struct WatchInstrumentTunerView: View {
    @StateObject private var tuner: WatchInstrumentTunerViewModel
    /// The crown's position, kept in step with inferred focus moves so a
    /// twist always starts from where the screen already is.
    @State private var crown: Double = 0
    @AppStorage(WatchTuning.referenceKey) private var referenceHz: Double = 440
    @AppStorage(WatchTuning.temperamentKey) private var temperamentMode: String =
        WatchTuning.TemperamentMode.auto.rawValue

    private let instrument: Instrument

    init(instrument: Instrument) {
        self.instrument = instrument
        _tuner = StateObject(
            wrappedValue: WatchInstrumentTunerViewModel(instrument: instrument))
    }

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
            // The knobs, visible where they act (a tuner that silently
            // applies 442 or pure fifths would look broken next to a phone
            // on different settings) — and the door to changing them.
            NavigationLink {
                WatchSettingsView(showsTemperament: true)
            } label: {
                Text(verbatim: footerLabel)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
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
        .onChange(of: referenceHz) { _, _ in retune() }
        .onChange(of: temperamentMode) { _, _ in retune() }
    }

    private var footerLabel: String {
        let mode =
            WatchTuning.TemperamentMode(rawValue: temperamentMode) ?? .auto
        let temperament = mode.temperament(for: instrument.family)
        return "A=\(Int(referenceHz)) · \(temperament == .pure ? "Pure" : "Equal")"
    }

    private func retune() {
        tuner.configure(
            reference: WatchTuning.storedReference(),
            temperament: WatchTuning.storedTemperament(for: instrument.family))
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
