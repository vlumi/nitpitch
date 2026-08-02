import NitpitchCore
import SwiftUI

/// The launch screen: a chromatic tuner, and the way into an instrument.
///
/// Always chromatic, whatever instrument was last chosen. That makes the first
/// screen immediately useful — anyone checking a single note is tuning within
/// a second of opening the app — and it gives chromatic a home of its own
/// rather than an odd entry in the instrument list. It *is* the
/// no-instrument case: no known targets, resolving freely to whatever it
/// hears.
///
/// The dial's shapes live in `DialView.swift`, the shared controls in
/// `TunerControls.swift`.
///
/// Accessibility identifiers are stable and kept in sync with `Tests/UITests`:
/// `tuner.note`, `tuner.cents`, `tuner.status`, `tuner.instrument`,
/// `tuner.reference`, `tuner.settings`.
public struct ChromaticTunerView: View {
    @ObservedObject private var settings: Settings
    @StateObject private var model: NitpitchViewModel
    @State private var isShowingSettings = false
    /// Only consulted on iOS — `resolvedScheme` reads AppKit directly on the
    /// Mac, where this ambient value is unreliable under a forced scheme.
    @Environment(\.colorScheme) private var systemScheme

    /// Opens the pushed instrument list.
    private let onOpenChooser: () -> Void
    /// Goes straight to one instrument's grid — the favourite chips' path,
    /// skipping the chooser the way a favourite should.
    private let onChooseInstrument: (Instrument) -> Void

    public init(
        settings: Settings, audio: AudioSessionController,
        onOpenChooser: @escaping () -> Void,
        onChooseInstrument: @escaping (Instrument) -> Void
    ) {
        self.settings = settings
        self.onOpenChooser = onOpenChooser
        self.onChooseInstrument = onChooseInstrument
        // Full band, not the saved instrument's: this screen is chromatic by
        // definition, and an instrument is somewhere you navigate to.
        _model = StateObject(
            wrappedValue: NitpitchViewModel(
                audio: audio,
                reference: settings.reference, band: Detection.fullBand))
    }

    public var body: some View {
        GeometryReader { geo in
            // One rule for both platforms rather than size classes, which
            // macOS doesn't have and which lie under iPad Split View: a wide,
            // short viewport puts the controls beside the dial instead of
            // under it.
            let isWide = geo.size.width > geo.size.height * 1.3
            Group {
                if isWide {
                    sideBySideLayout
                } else {
                    stackedLayout
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .padding(24)
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
        // Only the reference matters here — the instrument doesn't change this
        // screen's band, which is always full.
        .onChangeCompat(of: settings.reference) { _ in reconfigure() }
    }

    /// Portrait: everything in one column.
    private var stackedLayout: some View {
        VStack(spacing: 16) {
            header
            dial
            controls
            Spacer(minLength: 0)
        }
        // Capped so the column stays a column on an iPad or a wide Mac window
        // rather than stretching to the full width.
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    /// Landscape: controls beside the dial, since vertical room is what's
    /// scarce. The dial keeps the larger share — its radius is bounded by
    /// width, so an even split would shrink the arc (see `DialView`).
    private var sideBySideLayout: some View {
        VStack(spacing: 12) {
            header
            HStack(alignment: .center, spacing: 24) {
                dial
                    .frame(maxWidth: .infinity)
                controls
                    .frame(maxWidth: 260)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 900)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    /// Everything specific to one reading. Self-contained so the per-string
    /// grid can repeat it.
    private var dial: some View {
        TunerDial(
            cents: displayCents, inTune: isInTune, isReading: isReading,
            readout: { readout })
    }

    /// Applies to the reading rather than being part of it: the reference the
    /// dial is measured against, and the ways into an instrument — pinned
    /// chips for one tap, the full list for everything else.
    private var controls: some View {
        VStack(spacing: 16) {
            ReferencePitchStepper(reference: $settings.reference, naming: settings.naming)
            VStack(spacing: 10) {
                if !pinnedInstruments.isEmpty {
                    FavoritesRow(favorites: pinnedInstruments, onChoose: onChooseInstrument)
                }
                InstrumentButton(onOpen: onOpenChooser)
            }
        }
    }

    /// Pinned ids resolved to instruments, in pin order; ids that no longer
    /// resolve are skipped rather than crashing a launch screen.
    private var pinnedInstruments: [Instrument] {
        settings.favorites.compactMap(Instrument.named)
    }

    private func reconfigure() {
        model.configure(reference: settings.reference, band: Detection.fullBand)
    }

    /// Whether the app can hear anything, and the way into settings. The
    /// instrument moved out of here and below the dial: choosing one is a
    /// navigation, not a control, so it wants weight rather than a corner.
    private var header: some View {
        ZStack {
            // Centred independently of the items either side, so the meter
            // sits on the dial's axis rather than wherever the row's spacing
            // happens to put it.
            LevelMeter(level: model.level)
                .frame(width: 72, height: 4)
            HStack {
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
