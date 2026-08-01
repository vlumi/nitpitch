import NitpitchCore
import SwiftUI

/// The tuner screen: the dial, the light strip, and the note readout.
///
/// The dial's shapes live in `DialView.swift`; this file is the screen and its
/// controls.
///
/// Accessibility identifiers are stable and kept in sync with `Tests/UITests`
/// (`tuner.note`, `tuner.cents`, `tuner.status`, `tuner.instrument`,
/// `tuner.naming`, `tuner.reference`).
public struct NitpitchView: View {
    @ObservedObject private var settings: Settings
    @StateObject private var model: NitpitchViewModel

    public init(settings: Settings) {
        self.settings = settings
        _model = StateObject(
            wrappedValue: NitpitchViewModel(
                reference: settings.reference, band: settings.instrument.band()))
    }

    public var body: some View {
        VStack(spacing: 20) {
            header
            ArcView(cents: displayCents, inTune: isInTune)
                .frame(height: 120)
            LightStrip(cents: displayCents, isReading: isReading)
            readout
            Spacer(minLength: 0)
            controls
        }
        .padding(24)
        // Capped so the column stays a column on an iPad or a wide Mac window
        // rather than stretching to the full width; all four orientations are
        // supported, so this has to hold in landscape too.
        .frame(maxWidth: 520)
        // Top-aligned: with the column centred, any height change below the
        // dial would still shift it, even with the readout pinned.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
            ReferencePitchStepper(reference: $settings.reference)
            Spacer()
            LevelMeter(level: model.level)
                .frame(width: 60, height: 4)
        }
    }

    /// The readout reserves a fixed height whatever it's showing.
    ///
    /// The note-plus-cents stack is much taller than a one-line status, and
    /// letting the block resize pushed the dial up and down every time a note
    /// started or stopped — the whole screen twitching on each bow stroke.
    private var readout: some View {
        readoutContent
            .frame(height: Self.readoutHeight)
    }

    /// Tall enough for the note name and the cent label together. Derived from
    /// the font sizes rather than hardcoded, so it holds if they change.
    private static let readoutHeight: CGFloat = noteFontSize * 1.2 + 6 + 24

    private static let noteFontSize: CGFloat = 76

    @ViewBuilder
    private var readoutContent: some View {
        switch model.state {
        case .reading(let reading, let cents, _):
            VStack(spacing: 6) {
                Text(reading.note.name(in: settings.naming))
                    .font(.system(size: Self.noteFontSize, weight: .light, design: .rounded))
                    .accessibilityIdentifier("tuner.note")
                    .accessibilityLabel(reading.note.accessibleName(in: settings.naming))
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
        HStack(spacing: 16) {
            Picker(selection: $settings.instrument) {
                ForEach(Instrument.all) { instrument in
                    Text(LocalizedStringKey(instrument.name), bundle: .module).tag(instrument)
                }
            } label: {
                Text("Instrument", bundle: .module)
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("tuner.instrument")

            Picker(selection: $settings.naming) {
                // Each convention is labelled in its own terms ("A H C",
                // "イロハ"), so the list doesn't need translating.
                ForEach(NoteNaming.allCases, id: \.self) { naming in
                    Text(verbatim: naming.label).tag(naming)
                }
            } label: {
                Text("Notation", bundle: .module)
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("tuner.naming")
        }
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

    private var isInTune: Bool {
        if case .reading(_, let cents, _) = model.state {
            return TuningDisplay.isInTune(cents: cents)
        }
        return false
    }

    /// Whether there's a live reading to display, as opposed to silence or a
    /// rejected frame — the strip dims rather than sitting on a stale value.
    private var isReading: Bool {
        if case .reading = model.state { return true }
        return false
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

    var body: some View {
        HStack(spacing: 6) {
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
        index == TuningDisplay.centerLightIndex ? 14 : 10
    }

    private func color(for index: Int) -> Color {
        guard isReading else { return .secondary.opacity(0.15) }
        let intensity = TuningDisplay.lightIntensity(index: index, cents: cents)
        guard intensity > 0 else { return .secondary.opacity(0.15) }
        let lit: Color = index == TuningDisplay.centerLightIndex ? .green : .orange
        return lit.opacity(intensity)
    }
}

/// The reference-pitch control: the `A=440` readout with a step either side.
///
/// It replaces the plain label in the header rather than adding a third menu
/// to the controls row, which is already full. Whole hertz per step, matching
/// how orchestras actually specify a pitch (442, 443, baroque 415).
struct ReferencePitchStepper: View {
    @Binding var reference: ReferencePitch

    var body: some View {
        HStack(spacing: 6) {
            button("minus", enabled: reference.canLower) { reference = reference.lowered() }
            Text(verbatim: "A=\(Int(reference.hz))")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
                // Fixed width so the row doesn't shift when the value goes
                // from three digits to two, or the glyph widths change.
                .frame(minWidth: 46)
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
                .font(.footnote)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .foregroundStyle(enabled ? Color.secondary : Color.secondary.opacity(0.3))
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
