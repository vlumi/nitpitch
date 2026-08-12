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
    /// The preset being shared, driving the share sheet.
    @State private var sharing: Preset?

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
        .sheet(item: $sharing) { preset in
            PresetShareView(
                link: PresetLink(
                    name: preset.name, templateID: preset.templateID,
                    strings: preset.strings, referenceHz: preset.referenceHz,
                    temperament: preset.temperament),
                summary: payloadSummary(preset))
        }
        // Mac sheet sizing only: on an iPhone this minimum EXCEEDS a 375pt
        // screen, and the missing width came out of the list's horizontal
        // margins — rows flush to both edges.
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 300)
        #endif
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

    /// FITTING presets only — template AND string count. This sheet is one
    /// instrument's window onto the collection, and a preset this
    /// instrument can't wear is pure noise here: the menu won't offer it,
    /// the pin disables, and the only live control left is Delete — a trap.
    /// Cross-shape presets live in the All-presets browser, which can pick
    /// a compatible instrument or offer to create one.
    private var templatePresets: [Preset] {
        presets.presets.filter { $0.fits(instance) }
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
            shareButton(for: preset)
            pinButton(for: preset)
            deleteButton(for: preset)
        }
    }

    /// Hand this setup to someone else. Offered on saved presets only:
    /// catalog tunings are already everywhere the app is, so a link to one
    /// would carry nothing the receiver doesn't have.
    private func shareButton(for preset: Preset) -> some View {
        Button {
            sharing = preset
        } label: {
            Image(systemName: "square.and.arrow.up")
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier("presets.share.\(preset.id)")
        .accessibilityLabel(Text("Share", bundle: .module))
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

    /// What loading would do, spelled out: the pitches, the reference if it
    /// carries one, and a pure temperament — the same vocabulary as the
    /// tuning menu's rows. (An explicitly-equal payload stays unspelled,
    /// like there: "· equal" on every fretted preset would be noise.)
    private func payloadSummary(_ preset: Preset) -> String {
        var summary = preset.strings.map { Note(midi: $0).fullName }.joined(separator: " ")
        if let reference = preset.reference {
            summary += " · A=\(Int(reference.hz))"
        }
        if preset.temperament == .pure {
            summary += " · pure"
        }
        return summary
    }
}
