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

    @ObservedObject private var store: InstrumentStore
    @ObservedObject private var presets: PresetStore
    /// Opens the pushed instrument list.
    private let onOpenChooser: () -> Void
    /// Goes straight to one instance's grid — a rack row's path, skipping
    /// the chooser the way a favorite should.
    private let onChooseInstance: (String) -> Void
    /// A pin's path: the instrument opened INTO a preset — or, locked,
    /// merely opened (the navigation half of a pin is not a change).
    private let onChoosePin: (String, String) -> Void

    public init(
        settings: Settings, audio: AudioSessionController, store: InstrumentStore,
        presets: PresetStore,
        onOpenChooser: @escaping () -> Void,
        onChooseInstance: @escaping (String) -> Void,
        onChoosePin: @escaping (String, String) -> Void
    ) {
        self.settings = settings
        self.store = store
        self.presets = presets
        self.onOpenChooser = onOpenChooser
        self.onChooseInstance = onChooseInstance
        self.onChoosePin = onChoosePin
        // Full band, not the saved instrument's: this screen is chromatic by
        // definition, and an instrument is somewhere you navigate to.
        _model = StateObject(
            wrappedValue: NitpitchViewModel(
                audio: audio,
                reference: settings.reference, band: Detection.fullBand))
    }

    public var body: some View {
        GeometryReader { geo in
            // The layout is drawn on a fixed design canvas and scaled as one
            // unit to the viewport — proportions hold by construction from a
            // tiny window to a fullscreen one, instead of each element
            // compressing on its own until something breaks.
            //
            // WHICH canvas wins is decided by fill: compute the scale each
            // layout could reach in this viewport and take the larger. That
            // is the "stacked when the tuner spans edge-to-edge with room
            // below, otherwise side-by-side filling the width" rule, derived
            // rather than thresholded — a squarish window gets one big
            // stacked tuner, a wide one gets the side-by-side as large as
            // the height allows.
            // Heights are the measured content — dial 174 (arc less its
            // readout's rise, plus the readout), stepper 30, 16pt gaps, and
            // the rack at its EXACT height for the current pin count — not
            // padded guesses: overstating them is exactly what left a third
            // of the window empty below the tuner (the dial-grid's cell had
            // the same disease). Margins live outside, in the 24pt padding.
            let rackHeight = LaunchRack.height(for: pinned)
            let stacked = CGSize(width: 400, height: 236 + rackHeight)
            let wide = CGSize(width: 860, height: max(174, 46 + rackHeight))
            let stackedScale = min(
                geo.size.width / stacked.width, geo.size.height / stacked.height)
            let wideScale = min(geo.size.width / wide.width, geo.size.height / wide.height)
            let isWide = wideScale > stackedScale
            let design = isWide ? wide : stacked
            let scale = min(DesignCanvas.maxScale, max(0.5, isWide ? wideScale : stackedScale))
            Group {
                if isWide {
                    sideBySideLayout
                } else {
                    stackedLayout
                }
            }
            // On the Mac the slack frames the content — same rule as the
            // dial grid: unfilled height is split around the tuner, not
            // pooled below it. Phones keep reading from the top.
            .frame(
                width: design.width, height: design.height,
                alignment: DesignCanvas.alignment
            )
            .scaleEffect(scale, anchor: DesignCanvas.anchor)
            .frame(
                width: geo.size.width, height: geo.size.height,
                alignment: DesignCanvas.alignment)
        }
        .padding(24)
        // The header IS the toolbar now, rather than a hand-drawn imitation
        // of one — the gear gets the system's size, position and tint for
        // free, identical to the chooser's +. The meter rides the principal
        // slot: whether the app can hear anything applies to the whole
        // screen, so it belongs in the chrome, on the dial's axis.
        .toolbar {
            ToolbarItem(placement: .principal) {
                LevelMeter(level: model.level)
                    .frame(width: 72, height: 4)
            }
            // macOS reaches settings through the app menu (⌘,), so a gear
            // in the window would be a second door to the same room.
            #if !os(macOS)
            ToolbarItem(placement: .primaryAction) { settingsButton }
            #endif
        }
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
            dial
            controls
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
        HStack(alignment: .center, spacing: 24) {
            dial
                .frame(maxWidth: .infinity)
            controls
                .frame(maxWidth: 260)
        }
        .frame(maxWidth: 900)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    /// Everything specific to one reading. Self-contained so the per-string
    /// grid can repeat it.
    private var dial: some View {
        // Rises deeper than the default (50 vs 40): this readout is a
        // narrow centred column, so it clears the arc's sagging line where
        // the string view's stepper-flanked row wouldn't.
        TunerDial(
            cents: displayCents, inTune: isInTune, isReading: isReading,
            rise: 50, readout: { readout })
    }

    /// Applies to the reading rather than being part of it: the reference
    /// the dial is measured against, and the rack — your instruments as
    /// rows that say what they'll open into, the whole list one row below.
    private var controls: some View {
        VStack(spacing: 16) {
            ReferencePitchStepper(reference: $settings.reference, naming: settings.naming)
            LaunchRack(
                entries: pinned, onChoose: onChooseInstance,
                onChoosePin: onChoosePin, onOpenChooser: onOpenChooser)
        }
    }

    /// Pinned ids resolved to rack rows, in pin order. An id resolves
    /// through the store (an instrument you own, with its live tuning and
    /// lock) or, before its default instance exists, through the template;
    /// ids that resolve to neither are skipped rather than crashing a
    /// launch screen.
    private var pinned: [LaunchRack.Entry] {
        settings.favorites.compactMap { id in
            if let instance = store.instance(id: id) {
                return LaunchRack.Entry(
                    id: id, name: instance.nameText, template: instance.template,
                    tuningName: instance.tuningName, isLocked: instance.isLocked,
                    pins: pinEntries(for: instance))
            }
            if let template = Instrument.named(id) {
                return LaunchRack.Entry(
                    id: id,
                    name: Text(LocalizedStringKey(template.name), bundle: .module),
                    template: template,
                    tuningName: "Standard", isLocked: false)
            }
            return nil
        }
    }

    /// The instrument's pins, resolved: a pin whose preset was deleted (or
    /// no longer fits after a reshape) resolves to nothing and vanishes.
    private func pinEntries(for instance: InstrumentInstance) -> [LaunchRack.PinEntry] {
        settings.presetPins
            .filter { $0.instrumentID == instance.id }
            .compactMap { pin in
                // A catalog pin resolves through the template's tunings…
                if let name = CatalogPinID.tuningName(
                    in: pin.presetID, templateID: instance.templateID)
                {
                    guard
                        let tuning = instance.template?.knownTunings
                            .first(where: { $0.name == name }),
                        tuning.strings.count == instance.strings.count
                    else { return nil }
                    return LaunchRack.PinEntry(
                        presetID: pin.presetID, name: name, localized: true)
                }
                // …a preset pin through the store; dangling ones vanish.
                guard
                    let preset = presets.presets.first(where: { $0.id == pin.presetID }),
                    preset.fits(instance)
                else { return nil }
                return LaunchRack.PinEntry(presetID: preset.id, name: preset.name)
            }
    }

    private func reconfigure() {
        model.configure(reference: settings.reference, band: Detection.fullBand)
    }

    private var settingsButton: some View {
        Button {
            isShowingSettings = true
        } label: {
            Image(systemName: "gearshape")
        }
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

    /// The headline of the whole screen — big, because the parens' exit and
    /// the deeper rise into the arc's hollow both paid for the points.
    private static let noteFontSize: CGFloat = 56

    /// The note being heard, via the shared label — subscripted octave, no
    /// scientific parens: with the local name leading, "(A4)" under "La₄"
    /// said the same thing twice.
    private func noteLabel(_ note: Note) -> some View {
        NoteNameLabel(
            note: note, naming: settings.naming, fontSize: Self.noteFontSize,
            showsScientific: false
        )
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
        case .noInput:
            VStack(spacing: 8) {
                status("No audio input device", id: "tuner.status")
                // The cheapest recovery loop there is: plug one in, tap.
                Button {
                    Task { await model.retryInput() }
                } label: {
                    Text("Retry", bundle: .module)
                        .font(.callout.weight(.medium))
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("tuner.retry")
            }
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
