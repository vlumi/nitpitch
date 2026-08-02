import NitpitchCore
import SwiftUI

/// One dial per string, so tuning an instrument is measurement against known
/// targets rather than "what note is this".
///
/// Each dial watches its own narrow band — split at the midpoints between
/// neighbouring strings — so playing the G string lights the G dial and
/// nothing else. All of them read the same microphone through
/// `AudioSessionController`.
struct InstrumentGridView: View {
    let instrument: Instrument
    let audio: AudioSessionController
    @ObservedObject var settings: Settings
    @ObservedObject var detection: DetectionSettings

    @StateObject private var strings: StringTuners
    /// How many dials across. Defaults to the string count and is adjustable
    /// on the screen — how big is a preference, not a constant.
    @State private var columns: Int
    @State private var isShowingDebug = false

    init(
        instrument: Instrument, audio: AudioSessionController, settings: Settings,
        detection: DetectionSettings
    ) {
        self.instrument = instrument
        self.audio = audio
        self.settings = settings
        self.detection = detection
        _strings = StateObject(
            wrappedValue: StringTuners(
                instrument: instrument, audio: audio, reference: settings.reference,
                tuning: detection.tuning))
        _columns = State(initialValue: Self.defaultColumns(for: instrument))
    }

    var body: some View {
        ScrollView {
            // Whether the app can hear anything at all — the same meter, size
            // and axis as the chromatic screen's. The per-string bars can't
            // answer this: they're zero both in a quiet room and when sound is
            // coming in that isn't near any string's target.
            LevelMeter(level: strings.inputLevel)
                .frame(width: 72, height: 4)
                .padding(.top, 6)
            // Lazy so cost tracks the viewport rather than the string count —
            // which keeps "only track what's on screen" reachable later, and
            // lets an arbitrary tuning scale.
            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(Array(strings.tuners.enumerated()), id: \.offset) { _, tuner in
                    StringCell(tuner: tuner, naming: settings.naming)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .safeAreaInset(edge: .bottom) { footer }
        .navigationTitle(Text(LocalizedStringKey(instrument.name), bundle: .module))
        .toolbar { ToolbarItem(placement: .primaryAction) { layoutMenu } }
        .accessibilityIdentifier("grid.strings")
        .task { strings.attachAll() }
        .onDisappear { strings.detachAll() }
        .onChangeCompat(of: settings.reference) { _ in
            reconfigure()
        }
        // Two separate paths on purpose. A band change has to rebuild the
        // detectors — the band is baked into their lag bounds — while a
        // threshold change must not, or dragging a slider would reset the
        // smoothing on every tick and the dial would jump for reasons that have
        // nothing to do with the threshold under test.
        .onChangeCompat(of: detection.tuning.maxSemitonesFromString) { _ in
            reconfigure()
        }
        .onChangeCompat(of: detection.tuning) { tuning in
            strings.retune(tuning)
        }
        .sheet(isPresented: $isShowingDebug) {
            DetectorDebugView(
                detection: detection, strings: strings, naming: settings.naming)
        }
    }

    private func reconfigure() {
        strings.configure(
            instrument: instrument, reference: settings.reference, tuning: detection.tuning)
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: columns)
    }

    /// The reference belongs on this screen: it's what every dial is measured
    /// against, and it's adjusted in the moment. How *big* the dials are isn't
    /// — that's set once and lives in the menu.
    private var footer: some View {
        ReferencePitchStepper(reference: $settings.reference, naming: settings.naming)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(.thinMaterial)
    }

    private var layoutMenu: some View {
        Menu {
            Picker(selection: $columns) {
                ForEach(1...3, id: \.self) { count in
                    Text("\(count) across", bundle: .module).tag(count)
                }
            } label: {
                Text("Columns", bundle: .module)
            }

            if LaunchStores.isDebug {
                Divider()
                Button {
                    isShowingDebug = true
                } label: {
                    Label {
                        Text(verbatim: "Detector…")
                    } icon: {
                        Image(systemName: "waveform.badge.magnifyingglass")
                    }
                }
                .accessibilityIdentifier("grid.debug")
            }
        } label: {
            // A badge while anything is off its shipped value, so a surprising
            // reading is never mistaken for how the app actually behaves.
            Image(
                systemName: detection.isModified
                    ? "square.grid.2x2.fill" : "square.grid.2x2"
            )
            .foregroundStyle(detection.isModified ? AnyShapeStyle(.orange) : AnyShapeStyle(.tint))
        }
        .accessibilityIdentifier("grid.columns")
        .accessibilityLabel(Text("Columns", bundle: .module))
    }

    /// Few strings want fewer, wider cells; many want more across so the grid
    /// doesn't run off the screen.
    private static func defaultColumns(for instrument: Instrument) -> Int {
        instrument.strings.count > 4 ? 3 : 2
    }
}

/// One cell, observing its own string's model.
private struct StringCell: View {
    @ObservedObject var tuner: StringTunerViewModel
    let naming: NoteNaming

    var body: some View {
        CompactDial(name: tuner.target.name(in: naming), cents: cents, level: tuner.level)
    }

    private var cents: Double? {
        if case .reading(let cents, _) = tuner.state { return cents }
        return nil
    }
}
