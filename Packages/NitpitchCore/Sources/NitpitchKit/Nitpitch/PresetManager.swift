import NitpitchCore
import SwiftUI

/// One instrument's window onto the saved presets: favorites float in their
/// own block, and each row carries the two independent toggles — ★ favorite
/// (template-wide: floats the preset to the top of every preset list) and
/// 📌 pin (bound to THIS instrument: a launch-screen shortcut into the
/// setup). The sheet is titled by the instrument, which is what makes a lit
/// pin read "pinned to Strat" with no sentence needed. Loading and saving
/// live in the tuning menu; deletion and the toggles live here.
struct PresetManager: View {
    @ObservedObject var presets: PresetStore
    @ObservedObject var settings: Settings
    let instance: InstrumentInstance
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(fittingTunings, id: \.self) { tuning in
                        tuningRow(for: tuning)
                    }
                } header: {
                    Text("Tunings", bundle: .module)
                }
                if !favorites.isEmpty {
                    Section {
                        ForEach(favorites) { preset in
                            row(for: preset)
                        }
                    } header: {
                        Text("Favorites", bundle: .module)
                    }
                }
                Section {
                    ForEach(others) { preset in
                        row(for: preset)
                    }
                } header: {
                    if !favorites.isEmpty && !others.isEmpty {
                        Text("All presets", bundle: .module)
                    }
                }
            }
            .navigationTitle(instance.nameText)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done", bundle: .module)
                    }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 300)
    }

    /// The catalog tunings this instrument can wear — pinnable like any
    /// preset ("a catalog tuning is exactly a built-in preset"), never
    /// deletable: the catalog is few enough not to need pruning, and
    /// Standard stays standard by simply being catalog.
    private var fittingTunings: [Tuning] {
        guard let template = instance.template else { return [] }
        return template.knownTunings.filter { $0.strings.count == instance.strings.count }
    }

    private func tuningRow(for tuning: Tuning) -> some View {
        let name = tuning.name ?? "Custom"
        let pinID = CatalogPinID.make(templateID: instance.templateID, tuningName: name)
        let pinned = settings.isPinned(instrumentID: instance.id, presetID: pinID)
        return HStack(spacing: 10) {
            Text(LocalizedStringKey(name), bundle: .module)
            Spacer()
            Button {
                settings.togglePin(instrumentID: instance.id, presetID: pinID)
            } label: {
                Image(systemName: pinned ? "pin.fill" : "pin")
                    .foregroundStyle(
                        pinned
                            ? AnyShapeStyle(Color.orange)
                            : AnyShapeStyle(Color.secondary.opacity(0.5))
                    )
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("presets.pin.\(name)")
            .accessibilityLabel(Text("Pin to launch screen", bundle: .module))
        }
    }

    private var templatePresets: [Preset] {
        presets.presets.filter { $0.templateID == instance.templateID }
    }

    private var favorites: [Preset] {
        templatePresets.filter { presets.isFavorite($0.id) }
    }

    private var others: [Preset] {
        templatePresets.filter { !presets.isFavorite($0.id) }
    }

    private func row(for preset: Preset) -> some View {
        // Status leads, actions trail — the same row grammar as the
        // instrument list.
        HStack(spacing: 10) {
            favoriteButton(for: preset)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: preset.name)
                Text(verbatim: payloadSummary(preset))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            pinButton(for: preset)
            deleteButton(for: preset)
        }
    }

    private func favoriteButton(for preset: Preset) -> some View {
        Button {
            presets.toggleFavorite(preset.id)
        } label: {
            Image(systemName: presets.isFavorite(preset.id) ? "star.fill" : "star")
                .foregroundStyle(
                    presets.isFavorite(preset.id)
                        ? AnyShapeStyle(Color.yellow)
                        : AnyShapeStyle(Color.secondary.opacity(0.5))
                )
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier("presets.fav.\(preset.name)")
        .accessibilityLabel(Text("Favorite", bundle: .module))
    }

    private func pinButton(for preset: Preset) -> some View {
        let pinned = settings.isPinned(instrumentID: instance.id, presetID: preset.id)
        return Button {
            settings.togglePin(instrumentID: instance.id, presetID: preset.id)
        } label: {
            Image(systemName: pinned ? "pin.fill" : "pin")
                .foregroundStyle(
                    pinned
                        ? AnyShapeStyle(Color.orange)
                        : AnyShapeStyle(Color.secondary.opacity(0.5))
                )
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        // A preset that doesn't fit this instrument can't be its
        // shortcut — the pin is only offered where loading is.
        .disabled(!preset.fits(instance))
        .accessibilityIdentifier("presets.pin.\(preset.name)")
        .accessibilityLabel(Text("Pin to launch screen", bundle: .module))
    }

    private func deleteButton(for preset: Preset) -> some View {
        Button {
            presets.remove(id: preset.id)
        } label: {
            Image(systemName: "trash")
                .foregroundStyle(.red)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier("presets.delete.\(preset.id)")
        .accessibilityLabel(Text("Delete", bundle: .module))
    }

    /// What loading would do, spelled out: the pitches, and the reference if
    /// it carries one.
    private func payloadSummary(_ preset: Preset) -> String {
        let notes = preset.strings.map { Note(midi: $0).fullName }.joined(separator: " ")
        if let reference = preset.reference {
            return "\(notes) · A=\(Int(reference.hz))"
        }
        return notes
    }
}
