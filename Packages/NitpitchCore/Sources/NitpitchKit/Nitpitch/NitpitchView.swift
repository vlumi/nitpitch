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
    @State private var isShowingSettings = false
    /// Only consulted on iOS — `resolvedScheme` reads AppKit directly on the
    /// Mac, where this ambient value is unreliable under a forced scheme.
    @Environment(\.colorScheme) private var systemScheme

    public init(settings: Settings, audio: AudioSessionController) {
        self.settings = settings
        _model = StateObject(
            wrappedValue: NitpitchViewModel(
                audio: audio,
                reference: settings.reference, band: settings.instrument.band()))
    }

    public var body: some View {
        VStack(spacing: 16) {
            header
            // Everything specific to one reading lives inside the dial, so the
            // whole unit can be repeated — a dial per string (ROADMAP § 2)
            // needs two of these on one iPhone screen, and an SE leaves about
            // 195pt each. Reference and instrument stay outside: they apply to
            // both dials, and duplicating them would be actively confusing.
            TunerDial(
                cents: displayCents, inTune: isInTune, isReading: isReading,
                readout: { readout })
            ReferencePitchStepper(reference: $settings.reference, naming: settings.naming)
            Spacer(minLength: 0)
        }
        .padding(24)
        // Capped so the column stays a column on an iPad or a wide Mac window
        // rather than stretching to the full width; all four orientations are
        // supported, so this has to hold in landscape too.
        .frame(maxWidth: 520)
        // Top-aligned: with the column centred, any height change below the
        // dial would still shift it, even with the readout pinned.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Forced onto the whole hierarchy; nil means follow the system.
        .preferredColorScheme(settings.appearance.colorScheme)
        // The sheet needs a *concrete* scheme — see `appearanceSheet` for why
        // passing the optional through would strand it on the last choice.
        .appearanceSheet(
            isPresented: $isShowingSettings,
            scheme: settings.appearance.resolvedScheme(systemFallback: systemScheme)
        ) {
            SettingsView(settings: settings)
        }
        .task { await model.attach() }
        .onDisappear { model.detach() }
        .onChangeCompat(of: settings.instrument) { _ in reconfigure() }
        .onChangeCompat(of: settings.reference) { _ in reconfigure() }
    }

    private func reconfigure() {
        model.configure(reference: settings.reference, band: settings.instrument.band())
    }

    /// The only chrome on the screen: what's being tuned, whether the app can
    /// hear it, and the way into settings. Everything below this bar belongs
    /// to the reading itself, which leaves the bottom free for the per-string
    /// and tone-generator controls still to come.
    private var header: some View {
        ZStack {
            // Centred independently of the items either side, so the meter
            // sits on the dial's axis rather than wherever the row's spacing
            // happens to put it.
            LevelMeter(level: model.level)
                .frame(width: 72, height: 4)
            HStack {
                instrumentPicker
                Spacer()
                // macOS reaches settings through the app menu (⌘,), so a gear
                // in the window would be a second door to the same room.
                #if !os(macOS)
                settingsButton
                #endif
            }
        }
    }

    private var settingsButton: some View {
        Button {
            isShowingSettings = true
        } label: {
            Image(systemName: "gearshape")
                .font(.body)
                .frame(width: 44, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("tuner.settings")
        .accessibilityLabel(Text("Settings", bundle: .module))
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
    private static let readoutHeight: CGFloat = noteFontSize * 1.15 + 4 + 20

    /// Sized to sit inside the arc alongside the light strip, in a unit
    /// compact enough to appear twice on an iPhone SE.
    private static let noteFontSize: CGFloat = 46

    /// The note: scientific designator, with the chosen convention's name
    /// beside it when it differs. See `Note.readoutLabel(in:)` for why the two
    /// are kept apart rather than combined into one spelling.
    private func noteLabel(_ note: Note) -> some View {
        let label = note.readoutLabel(in: settings.naming)
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            // The octave is subscripted so the letter stays the thing you read
            // at a glance — the number qualifies it rather than competing.
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(verbatim: label.name)
                    .font(.system(size: Self.noteFontSize, weight: .light, design: .rounded))
                Text(verbatim: "\(label.octave)")
                    .font(.system(size: Self.noteFontSize * 0.44, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
                    .baselineOffset(-Self.noteFontSize * 0.06)
            }
            if let alternate = label.alternate {
                Text(verbatim: "(\(alternate))")
                    .font(.system(size: Self.noteFontSize * 0.40, weight: .light))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("tuner.note")
        .accessibilityLabel(note.accessibleName(in: settings.naming))
    }

    @ViewBuilder
    private var readoutContent: some View {
        switch model.state {
        case .reading(let reading, let cents, _):
            VStack(spacing: 6) {
                noteLabel(reading.note)
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

    /// Label-less in the header: the selected instrument's own name says what
    /// the control is, and a "Instrument" prefix would just crowd the bar.
    private var instrumentPicker: some View {
        Picker(selection: $settings.instrument) {
            // Sectioned so the ordering explains itself: bowed strings first
            // (violin leads — the app's reason for existing), then fretted,
            // each family running high to low. Ungrouped, that sequence reads
            // as arbitrary.
            ForEach(Instrument.grouped, id: \.family) { group in
                Section {
                    ForEach(group.instruments) { instrument in
                        Text(LocalizedStringKey(instrument.name), bundle: .module)
                            .tag(instrument)
                    }
                } header: {
                    Text(LocalizedStringKey(group.family.name), bundle: .module)
                }
            }
        } label: {
            Text("Instrument", bundle: .module)
        }
        .pickerStyle(.menu)
        .labelsHidden()
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
