import NitpitchCore
import NitpitchData
import SwiftUI

/// The wrist's front door: your STARRED instruments (synced — the watch is
/// the second device that makes sync earn its keep), the rest behind one
/// row (grouped by family, where the whole seeded catalog stops being
/// clutter), chromatic, and the settings with the sync switch. Starring
/// works from here too — swipe a row, or the toggle on the instrument's
/// detail — because the watch is a full citizen of the favorites now, not
/// a window onto the phone's. Creating new instruments stays a phone/Mac
/// job: no editors on a 40 mm screen. Favorites keep the order the phone's
/// launch screen keeps them.
struct WatchRootView: View {
    @ObservedObject var store: InstrumentStore
    @ObservedObject var presets: PresetStore
    @ObservedObject var settings: Settings
    @ObservedObject var sync: SyncEngine

    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if !favoriteInstances.isEmpty {
                    Section("My instruments") {
                        ForEach(favoriteInstances, id: \.id) { instance in
                            WatchInstanceRow(instance: instance, settings: settings)
                        }
                    }
                }
                if !store.instances.isEmpty {
                    NavigationLink(value: "all") {
                        Label("All instruments", systemImage: "guitars")
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
                guard path.isEmpty, let route = LaunchStores.demoRoute else { return }
                try? await Task.sleep(nanoseconds: 300_000_000)
                path = [route]
            }
        }
    }

    /// The stars, in the phone rack's own order.
    private var favoriteInstances: [InstrumentInstance] {
        settings.favorites.compactMap { id in
            store.instances.first { $0.id == id }
        }
    }

    @ViewBuilder
    private func destination(for route: String) -> some View {
        if route == "all" {
            WatchAllInstrumentsView(store: store, settings: settings)
        } else if route == "chromatic" {
            WatchChromaticTunerView(settings: settings, sync: sync)
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

/// One instrument row, shared by the front door and the all-instruments
/// list: tap opens its tuner, swipe stars or unstars it — the wrist-native
/// verb for a list row, and a stamped act that syncs like the phone's.
/// Starred rows wear the star EVERYWHERE, front door included: there it
/// spells out the membership rule ("these are here because of this"), in
/// the full list it marks which ones made the door.
private struct WatchInstanceRow: View {
    let instance: InstrumentInstance
    @ObservedObject var settings: Settings

    private var starred: Bool { settings.favorites.contains(instance.id) }

    var body: some View {
        NavigationLink(value: instance.id) {
            HStack {
                Text(verbatim: instance.name)
                Spacer()
                if instance.isLocked {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if starred {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                settings.toggleFavorite(instance.id)
            } label: {
                Image(systemName: starred ? "star.slash.fill" : "star.fill")
            }
            .tint(.yellow)
        }
    }
}

/// The whole collection — ALL means all, favorites included, starred rows
/// wearing their star — grouped the chooser's way: by family, bowed first,
/// so the seeded catalog reads as a shelf rather than clutter. Swipe a row
/// to star or unstar; the front door follows.
struct WatchAllInstrumentsView: View {
    @ObservedObject var store: InstrumentStore
    @ObservedObject var settings: Settings

    var body: some View {
        List {
            ForEach(InstrumentFamily.allCases, id: \.self) { family in
                let members = store.instances.filter {
                    ($0.template?.family ?? .other) == family
                }
                if !members.isEmpty {
                    Section(family.name) {
                        ForEach(members, id: \.id) { instance in
                            WatchInstanceRow(instance: instance, settings: settings)
                        }
                    }
                }
            }
        }
        .navigationTitle("All instruments")
    }
}
