import SwiftUI
import TunerCore

/// The tuner screen: note name, cent offset, and a needle.
///
/// Accessibility identifiers are stable and kept in sync with `Tests/UITests`
/// (`tuner.note`, `tuner.cents`, `tuner.status`, `tuner.instrument`).
public struct TunerView: View {
    @ObservedObject private var settings: Settings
    @StateObject private var model: TunerViewModel

    public init(settings: Settings) {
        self.settings = settings
        _model = StateObject(
            wrappedValue: TunerViewModel(
                reference: settings.reference, band: settings.instrument.band()))
    }

    public var body: some View {
        VStack(spacing: 28) {
            header
            NeedleView(cents: displayCents, inTune: isInTune)
                .frame(height: 120)
            readout
            Spacer(minLength: 0)
            controls
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await model.start() }
        .onDisappear { model.stop() }
        .onChangeCompat(of: settings.instrument) { _ in reconfigure() }
        .onChangeCompat(of: settings.reference) { _ in reconfigure() }
    }

    private func reconfigure() {
        model.configure(reference: settings.reference, band: settings.instrument.band())
    }

    private var header: some View {
        HStack {
            Text(verbatim: "A=\(Int(settings.reference.hz))")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()
            LevelMeter(level: model.level)
                .frame(width: 60, height: 4)
        }
    }

    @ViewBuilder
    private var readout: some View {
        switch model.state {
        case .reading(let reading, let cents, _):
            VStack(spacing: 6) {
                Text(reading.note.name)
                    .font(.system(size: 76, weight: .light, design: .rounded))
                    .accessibilityIdentifier("tuner.note")
                    .accessibilityLabel(reading.note.fullName)
                Text(centsLabel(cents))
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(isInTune ? Color.green : .secondary)
                    .accessibilityIdentifier("tuner.cents")
            }
        case .listening:
            status("Play a note", id: "tuner.status")
        case .permissionDenied:
            status("Microphone access is off", id: "tuner.status")
        case .idle:
            status("Not listening", id: "tuner.status")
        }
    }

    private func status(_ key: LocalizedStringKey, id: String) -> some View {
        Text(key, bundle: .module)
            .font(.title3)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier(id)
    }

    private var controls: some View {
        Picker(selection: $settings.instrument) {
            ForEach(Instrument.all) { instrument in
                Text(LocalizedStringKey(instrument.name), bundle: .module).tag(instrument)
            }
        } label: {
            Text("Instrument", bundle: .module)
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("tuner.instrument")
    }

    private func centsLabel(_ cents: Double) -> String {
        // A leading sign on both directions, so "flat or sharp" reads at a
        // glance without parsing the number.
        let rounded = Int(cents.rounded())
        return rounded > 0 ? "+\(rounded)¢" : "\(rounded)¢"
    }

    private var displayCents: Double {
        if case .reading(_, let cents, _) = model.state { return cents }
        return 0
    }

    /// ±5 cents is the band a player can't hear as out of tune, and the
    /// tolerance most tuners treat as "in".
    private var isInTune: Bool {
        if case .reading(_, let cents, _) = model.state { return abs(cents) <= 5 }
        return false
    }
}

/// The needle: a line that rotates with the cent offset, plus a center mark.
struct NeedleView: View {
    let cents: Double
    let inTune: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Rectangle()
                    .fill(inTune ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 2, height: geo.size.height * 0.25)
                Rectangle()
                    .fill(inTune ? Color.green : Color.primary)
                    .frame(width: 3, height: geo.size.height * 0.9)
                    // ±50 cents maps to ±45°, so the full dial spans a semitone.
                    .rotationEffect(.degrees(cents / 50 * 45), anchor: .bottom)
                    .animation(.easeOut(duration: 0.12), value: cents)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .accessibilityHidden(true)
    }
}

/// Input level bar — shows the app is hearing something even when no pitch is
/// confident enough to display.
struct LevelMeter: View {
    let level: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.2))
                Capsule().fill(Color.secondary)
                    .frame(width: geo.size.width * level)
            }
        }
        .accessibilityHidden(true)
    }
}
