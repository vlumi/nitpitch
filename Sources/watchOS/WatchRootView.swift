import NitpitchCore
import NitpitchData
import SwiftUI

/// The wrist's front door: YOUR instruments (synced — the watch is the
/// second device that makes sync earn its keep), chromatic, and the
/// settings with the sync switch. No catalog section: the store seeds an
/// instance per template on first launch (stable ids, so a later first
/// sync merges clean), so the catalog IS "my instruments" until the user
/// prunes it — and creating new instruments stays a phone/Mac job, no
/// editors on a 40 mm screen. Starred instruments lead, in the order the
/// phone's launch screen keeps them.
struct WatchRootView: View {
    @ObservedObject var store: InstrumentStore
    @ObservedObject var presets: PresetStore
    @ObservedObject var settings: Settings
    @ObservedObject var sync: SyncEngine

    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if !store.instances.isEmpty {
                    Section("My instruments") {
                        ForEach(orderedInstances, id: \.id) { instance in
                            NavigationLink(value: instance.id) {
                                HStack {
                                    Text(verbatim: instance.name)
                                    Spacer()
                                    if instance.isLocked {
                                        Image(systemName: "lock.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                    if settings.favorites.contains(instance.id) {
                                        Image(systemName: "star.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.yellow)
                                    }
                                }
                            }
                        }
                    }
                }
                NavigationLink(value: "chromatic") {
                    Label("Chromatic", systemImage: "waveform")
                }
                NavigationLink(value: "settings") {
                    Label("Settings", systemImage: "gear")
                }
            }
            .navigationTitle("Nitpitch")
            .navigationDestination(for: String.self) { route in
                destination(for: route)
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

    /// Starred first, in the phone rack's own order, then the rest.
    private var orderedInstances: [InstrumentInstance] {
        let starred = settings.favorites.compactMap { id in
            store.instances.first { $0.id == id }
        }
        let rest = store.instances.filter { !settings.favorites.contains($0.id) }
        return starred + rest
    }

    @ViewBuilder
    private func destination(for route: String) -> some View {
        if route == "chromatic" {
            WatchTunerView(settings: settings, sync: sync)
                .navigationTitle("Chromatic")
        } else if route == "settings" {
            WatchSettingsView(settings: settings, sync: sync)
        } else if let instance = store.instance(id: route) {
            WatchInstanceTunerView(
                instance: instance, store: store, presets: presets, settings: settings
            )
            .navigationTitle(instance.name)
            // Identity per INSTANCE SHAPE: a synced edit that changes the
            // string count needs fresh tuners (the phone's `.id` lesson).
            .id("\(instance.id):\(instance.strings.count)")
        }
    }
}
