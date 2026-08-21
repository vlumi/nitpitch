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
            HStack(spacing: 6) {
                NavigationLink {
                    WatchInstanceDetailView(
                        store: store, presets: presets, settings: settings,
                        instanceID: instanceID)
                } label: {
                    // What you'd ask of the button before pressing it: WHICH
                    // tuning is on (your preset's name, Standard, or Custom —
                    // `tuningDisplayName`, the phone's naming), with the
                    // knobs' facts beneath in smaller type.
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
                // The phone's Intonation chip, in the wrist's vocabulary —
                // Δ is what the check's verdict already wears. Fretted
                // only: the check serves saddle work.
                if instance.instrument.family == .fretted {
                    Button {
                        tuner.setChecking(!tuner.isChecking)
                    } label: {
                        Text(verbatim: "Δ")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(tuner.isChecking ? .blue : .secondary)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(Text(verbatim: "Check intonation"))
                    .accessibilityValue(Text(verbatim: tuner.isChecking ? "On" : "Off"))
                }
            }
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
        // Temperament is a bowed fact (frets are equal cast in metal) —
        // announcing "Equal" on a guitar was noise.
        guard instance.instrument.family == .bowed else { return "A=\(hz)" }
        return "A=\(hz) · \(instance.appliedTemperament == .pure ? "Pure" : "Equal")"
    }
}
