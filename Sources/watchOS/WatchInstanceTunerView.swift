import NitpitchCore
import NitpitchData
import SwiftUI

/// One of YOUR instruments on the wrist: the shared tuner pane over the
/// instance's own strings, reference and temperament — all synced facts,
/// which is what makes the watch a real second device. The footer opens the
/// instance's detail screen: lock, knobs, and its presets.
struct WatchInstanceTunerView: View {
    @ObservedObject var store: InstrumentStore
    @ObservedObject var presets: PresetStore
    @ObservedObject var settings: Settings
    @StateObject private var tuner: WatchInstrumentTunerViewModel

    private let instanceID: String
    private let initial: InstrumentInstance

    init(
        instance: InstrumentInstance, store: InstrumentStore, presets: PresetStore,
        settings: Settings
    ) {
        self.store = store
        self.presets = presets
        self.settings = settings
        self.instanceID = instance.id
        self.initial = instance
        _tuner = StateObject(
            wrappedValue: WatchInstrumentTunerViewModel(
                instrument: instance.instrument,
                reference: instance.reference,
                temperament: instance.appliedTemperament,
                naming: settings.naming,
                // Bowed instruments open on the A — the note the orchestra
                // gives, tuned first, fifths outward from there.
                initialIndex: instance.instrument.firstTuningIndex))
    }

    private var instance: InstrumentInstance {
        store.instance(id: instanceID) ?? initial
    }

    var body: some View {
        WatchTunerPane(tuner: tuner) {
            NavigationLink {
                WatchInstanceDetailView(
                    store: store, presets: presets, settings: settings,
                    instanceID: instanceID)
            } label: {
                // What you'd ask of the button before pressing it: WHICH
                // tuning is on (your preset's name, Standard, or Custom —
                // `tuningDisplayName`, the phone's naming), with the knobs'
                // facts beneath in smaller type.
                VStack(spacing: 1) {
                    HStack(spacing: 4) {
                        if instance.isLocked {
                            Image(systemName: "lock.fill").font(.caption2)
                        }
                        Text(verbatim: presets.tuningDisplayName(for: instance))
                            .font(.footnote.weight(.semibold))
                    }
                    Text(verbatim: footerLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.bordered)
        }
        // A synced edit arriving mid-view — the phone moved this
        // instance's A, retuned a string, flipped its temperament —
        // retargets the live screen.
        .onChange(of: instance) { _, current in
            retune(to: current)
        }
        // The notation is a synced preference now: a phone-side change
        // renames the live header.
        .onChange(of: settings.naming) { _, _ in
            retune(to: instance)
        }
    }

    private func retune(to current: InstrumentInstance) {
        tuner.configure(
            instrument: current.instrument,
            reference: current.reference,
            temperament: current.appliedTemperament,
            naming: settings.naming)
    }

    private var footerLabel: String {
        let hz = Int(instance.reference.hz)
        return "A=\(hz) · \(instance.appliedTemperament == .pure ? "Pure" : "Equal")"
    }
}
