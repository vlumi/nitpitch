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
    /// For loading: a tapped row applies itself to THIS instrument — the
    /// sheet is scoped to one, so unlike the browser there is nothing to
    /// ask.
    @ObservedObject var store: InstrumentStore
    let instance: InstrumentInstance
    @Environment(\.dismiss) private var dismiss
    /// The preset being shared, driving the share sheet.
    @State private var sharing: Preset?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(instance.fittingTunings, id: \.self) { tuning in
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
                link: PresetLink(preset),
                summary: PresetPayloadSummary.text(for: preset))
        }
        // Mac sheet sizing only: on an iPhone this minimum EXCEEDS a 375pt
        // screen, and the missing width came out of the list's horizontal
        // margins — rows flush to both edges.
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 300)
        #endif
    }

    private func tuningRow(for tuning: Tuning) -> some View {
        let name = tuning.name ?? "Custom"
        let pinID = CatalogPinID.make(templateID: instance.templateID, tuningName: name)
        let pinned = settings.isPinned(instrumentID: instance.id, presetID: pinID)
        return HStack(spacing: 10) {
            Text(LocalizedStringKey(name), bundle: .module)
            Spacer()
            loadIndicator(matches: instance.strings == tuning.strings)
            RowIconButton(
                systemName: pinned ? "pin.fill" : "pin",
                tint: .orange, isOn: pinned,
                identifier: "presets.pin.\(name)",
                label: Text("Pin to launch screen", bundle: .module)
            ) { settings.togglePin(instrumentID: instance.id, presetID: pinID) }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // Same semantics as picking it in the tuning menu: pitches only,
            // an explicit pick.
            store.setTuning(id: instance.id, strings: tuning.strings)
            dismiss()
        }
    }

    /// The row's "already on" mark — a tappable row should say when tapping
    /// it would change nothing, the way the menu's equals sign does.
    @ViewBuilder
    private func loadIndicator(matches: Bool) -> some View {
        if matches {
            Image(systemName: "equal")
                .font(.caption)
                .foregroundStyle(.tertiary)
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
                Text(verbatim: PresetPayloadSummary.text(for: preset))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            loadIndicator(matches: preset.matchesValues(of: instance))
            shareButton(for: preset)
            pinButton(for: preset)
            deleteButton(for: preset)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // The sheet answers for ONE instrument, so a tap needs no
            // instrument picker — load and get out of the way, like the
            // browser.
            presets.load(preset, onto: instance, in: store)
            dismiss()
        }
        // A CONTAINER, explicitly: a bare identifier on a plain stack
        // broadcasts onto every element inside it, renaming the pin and
        // share buttons out from under their own identifiers.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("presets.row.\(preset.name)")
    }

    /// Hand this setup to someone else. Offered on saved presets only:
    /// catalog tunings are already everywhere the app is, so a link to one
    /// would carry nothing the receiver doesn't have.
    private func shareButton(for preset: Preset) -> some View {
        RowIconButton(
            systemName: "square.and.arrow.up",
            identifier: "presets.share.\(preset.id)",
            label: Text("Share", bundle: .module)
        ) { sharing = preset }
    }

    private func favoriteButton(for preset: Preset) -> some View {
        RowIconButton(
            systemName: presets.isFavorite(preset.id) ? "star.fill" : "star",
            tint: .yellow, isOn: presets.isFavorite(preset.id),
            identifier: "presets.fav.\(preset.name)",
            label: Text("Favorite", bundle: .module)
        ) { presets.toggleFavorite(preset.id) }
    }

    private func pinButton(for preset: Preset) -> some View {
        let pinned = settings.isPinned(instrumentID: instance.id, presetID: preset.id)
        return RowIconButton(
            systemName: pinned ? "pin.fill" : "pin",
            tint: .orange, isOn: pinned,
            identifier: "presets.pin.\(preset.name)",
            label: Text("Pin to launch screen", bundle: .module)
        ) { settings.togglePin(instrumentID: instance.id, presetID: preset.id) }
        // A preset that doesn't fit this instrument can't be its
        // shortcut — the pin is only offered where loading is.
        .disabled(!preset.fits(instance))
    }

    private func deleteButton(for preset: Preset) -> some View {
        RowIconButton(
            systemName: "trash", tint: .red,
            identifier: "presets.delete.\(preset.id)",
            label: Text("Delete", bundle: .module)
        ) { presets.remove(id: preset.id) }
    }

}
