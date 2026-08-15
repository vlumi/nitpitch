import NitpitchCore
import NitpitchData
import SwiftUI
import WatchKit

/// An instance's facts, editable where editing makes wrist sense: the lock,
/// the reference (the crown's job again), the temperament, and its presets —
/// every change is a store write, so it syncs like the phone's. No string
/// editing here: a different tuning is a preset away, and a different shape
/// is a different instrument (the phone's rule, kept).
struct WatchInstanceDetailView: View {
    @ObservedObject var store: InstrumentStore
    @ObservedObject var presets: PresetStore
    @ObservedObject var settings: Settings
    let instanceID: String

    @Environment(\.dismiss) private var dismiss

    private var instance: InstrumentInstance? {
        store.instance(id: instanceID)
    }

    var body: some View {
        if let instance {
            detail(for: instance)
        } else {
            // Synced away underneath us: another device deleted it.
            Text(verbatim: "This instrument was removed")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func detail(for instance: InstrumentInstance) -> some View {
        List {
            lockSection(for: instance)
            tuningSection(for: instance)
            // Standard alone earns the section: it's the way back after
            // any preset, catalog by nature, so it can't be deleted away.
            if instance.template != nil || !fittingPresets(for: instance).isEmpty {
                presetSection(for: instance)
            }
        }
        .navigationTitle(instance.name)
    }

    private func lockSection(for instance: InstrumentInstance) -> some View {
        Section {
            Toggle(
                isOn: Binding(
                    get: { instance.isLocked },
                    set: { store.setLocked(id: instance.id, $0) }
                )
            ) {
                Label("Locked", systemImage: instance.isLocked ? "lock.fill" : "lock.open")
            }
        } footer: {
            Text(verbatim: "A locked instrument refuses edits, here and everywhere.")
        }
    }

    private func tuningSection(for instance: InstrumentInstance) -> some View {
        Section {
            referenceRow(for: instance)
            Picker(
                selection: Binding(
                    get: { instance.appliedTemperament },
                    set: { store.setTemperament(id: instance.id, $0) }
                ),
                label: Text(verbatim: "Temperament")
            ) {
                Text(verbatim: "Equal").tag(Temperament.equal)
                Text(verbatim: "Pure fifths").tag(Temperament.pure)
            }
            .disabled(instance.isLocked)
        } header: {
            Text(verbatim: "Tuning")
        }
    }

    private func presetSection(for instance: InstrumentInstance) -> some View {
        Section {
            // The catalog first: Standard is what the instrument's name
            // means, and the way BACK once any preset has been loaded —
            // the phone's Manage sheet offers it, so the wrist does too.
            if let template = instance.template {
                ForEach(template.knownTunings, id: \.strings) { tuning in
                    tuningRow(tuning, for: instance)
                }
            }
            ForEach(fittingPresets(for: instance), id: \.id) { preset in
                Button {
                    presets.load(preset, onto: instance, in: store)
                    WKInterfaceDevice.current().play(.success)
                    dismiss()
                } label: {
                    HStack {
                        Text(verbatim: preset.name)
                        Spacer()
                        loadIndicator(matches: preset.strings == instance.strings)
                        if settings.isPinned(instrumentID: instance.id, presetID: preset.id) {
                            Image(systemName: "pin.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .disabled(instance.isLocked)
            }
        } header: {
            Text(verbatim: "Presets")
        } footer: {
            Text(verbatim: "Tap to load onto this instrument.")
        }
    }

    private func tuningRow(_ tuning: Tuning, for instance: InstrumentInstance) -> some View {
        Button {
            // Pitches only, an explicit pick — the phone's semantics. The
            // no-change tap just leaves: `setTuning` would re-stamp the
            // record and ripple through sync for nothing.
            if tuning.strings != instance.strings {
                store.setTuning(id: instance.id, strings: tuning.strings)
                WKInterfaceDevice.current().play(.success)
            }
            dismiss()
        } label: {
            HStack {
                Text(verbatim: tuning.name ?? "Custom")
                Spacer()
                loadIndicator(matches: tuning.strings == instance.strings)
            }
        }
        .disabled(instance.isLocked)
    }

    /// The row's "already on" mark — the phone's equals sign, kept: a
    /// tappable row should say when tapping it would change nothing.
    @ViewBuilder
    private func loadIndicator(matches: Bool) -> some View {
        if matches {
            Image(systemName: "equal")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func referenceRow(for instance: InstrumentInstance) -> some View {
        HStack {
            Button("−") {
                store.setReference(id: instance.id, instance.reference.lowered())
            }
            .disabled(!instance.reference.canLower || instance.isLocked)
            Spacer()
            Text(verbatim: "A=\(Int(instance.reference.hz))")
                .font(.system(.body, design: .rounded))
                .monospacedDigit()
            Spacer()
            Button("+") {
                store.setReference(id: instance.id, instance.reference.raised())
            }
            .disabled(!instance.reference.canRaise || instance.isLocked)
        }
        .buttonStyle(.bordered)
    }

    /// Pinned first — the launch chips' order of importance, kept on the
    /// wrist — then the rest of what fits.
    private func fittingPresets(for instance: InstrumentInstance) -> [Preset] {
        let fitting = presets.presets.filter { $0.fits(instance) }
        let pinned = fitting.filter {
            settings.isPinned(instrumentID: instance.id, presetID: $0.id)
        }
        let rest = fitting.filter {
            !settings.isPinned(instrumentID: instance.id, presetID: $0.id)
        }
        return pinned + rest
    }
}
