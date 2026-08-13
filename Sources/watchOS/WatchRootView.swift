import NitpitchCore
import SwiftUI

/// The wrist's front door: chromatic first (the scaffold's screen, still the
/// zero-setup answer), then the catalog instruments for the hands-free
/// one-string-at-a-time mode. Local catalog only for now — synced favorites
/// replace this list when sync reaches the wrist (see ROADMAP § Watch app).
struct WatchRootView: View {
    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                NavigationLink(value: "chromatic") {
                    Label("Chromatic", systemImage: "waveform")
                }
                ForEach(Instrument.choosable, id: \.family) { group in
                    Section(group.family.name) {
                        ForEach(group.instruments, id: \.id) { instrument in
                            NavigationLink(value: instrument.id) {
                                Text(verbatim: instrument.name)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Nitpitch")
            .navigationDestination(for: String.self) { route in
                if route == "chromatic" {
                    WatchTunerView().navigationTitle("Chromatic")
                } else if let instrument = Instrument.all.first(where: { $0.id == route }) {
                    WatchInstrumentTunerView(instrument: instrument)
                        .navigationTitle(instrument.name)
                }
            }
            // The demo route, same as the phone's: `-demo -demo-open violin`
            // (or `chromatic`) lands straight on the screen being judged —
            // simulator screenshots without scripting taps.
            .task {
                let arguments = ProcessInfo.processInfo.arguments
                guard arguments.contains("-demo"), path.isEmpty,
                    let index = arguments.firstIndex(of: "-demo-open"),
                    arguments.indices.contains(index + 1)
                else { return }
                try? await Task.sleep(nanoseconds: 300_000_000)
                path = [arguments[index + 1]]
            }
        }
    }
}
