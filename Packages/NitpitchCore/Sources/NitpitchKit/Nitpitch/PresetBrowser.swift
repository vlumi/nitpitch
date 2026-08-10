import NitpitchCore
import SwiftUI

/// Every preset you've saved, across every instrument — the collection as a
/// collection, rather than one instrument's window onto it.
///
/// **Saved presets only.** Catalog tunings are deliberately absent: they
/// belong to templates rather than to you, so listing them here would put a
/// dozen rows you can't rename, delete or share in front of the handful you
/// actually made. `PresetManager` still shows them, because it is scoped to
/// one instrument, where "the tunings this guitar can wear" is a short and
/// meaningful list.
///
/// **No pinning here either**, for the same reason it exists there: a pin is
/// the (instrument, preset) pair, and a global list has no instrument to
/// bind to — "Gig" fits every guitar you own, and a pin button would have to
/// guess which one.
struct PresetBrowser: View {
    @ObservedObject var presets: PresetStore
    @ObservedObject var store: InstrumentStore
    @Environment(\.dismiss) private var dismiss

    @State private var order: PresetBrowsing.Order = .recent
    /// Nil = every instrument.
    @State private var templateFilter: String?
    @State private var renaming: Preset?
    @State private var renameText = ""
    @State private var sharing: Preset?

    var body: some View {
        NavigationStack {
            List {
                if arranged.isEmpty {
                    Section {
                        Text("No presets for this instrument.", bundle: .module)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(arranged, id: \.id) { preset in
                        row(for: preset)
                    }
                }
            }
            .navigationTitle(Text("All presets", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .primaryAction) { sortMenu }
                ToolbarItem(placement: .cancellationAction) { filterMenu }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done", bundle: .module)
                    }
                }
            }
            .alert(
                Text("Rename preset", bundle: .module),
                isPresented: Binding(
                    get: { renaming != nil }, set: { if !$0 { renaming = nil } })
            ) {
                TextField("", text: $renameText)
                Button {
                    renaming = nil
                } label: {
                    Text("Cancel", bundle: .module)
                }
                Button {
                    if let target = renaming { presets.rename(id: target.id, to: renameText) }
                    renaming = nil
                } label: {
                    Text("Rename", bundle: .module)
                }
                .disabled(!canRename)
            } message: {
                if !canRename, !renameText.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("That name is already used for this instrument.", bundle: .module)
                }
            }
            .sheet(item: $sharing) { preset in
                PresetShareView(
                    link: PresetLink(
                        name: preset.name, templateID: preset.templateID,
                        strings: preset.strings, referenceHz: preset.referenceHz,
                        temperament: preset.temperament),
                    summary: PresetPayloadSummary.text(
                        strings: preset.strings, referenceHz: preset.referenceHz,
                        temperament: preset.temperament))
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 380)
        #endif
    }

    // MARK: - Rows

    private func row(for preset: Preset) -> some View {
        HStack(spacing: 10) {
            favoriteButton(for: preset)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: preset.name)
                Text(verbatim: subtitle(for: preset))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            shareButton(for: preset)
        }
        .contentShape(Rectangle())
        .swipeActions(edge: .trailing) { actions(for: preset) }
        .contextMenu { actions(for: preset) }
        .accessibilityIdentifier("browser.preset.\(preset.id)")
    }

    /// Rename and delete, offered by both idioms — the iOS swipe and the
    /// press-and-hold menu the Mac uses — so neither platform hides an
    /// action behind a gesture its users don't reach for.
    @ViewBuilder
    private func actions(for preset: Preset) -> some View {
        Button {
            beginRename(preset)
        } label: {
            Text("Rename", bundle: .module)
        }
        Button(role: .destructive) {
            presets.remove(id: preset.id)
        } label: {
            Text("Delete", bundle: .module)
        }
    }

    private func favoriteButton(for preset: Preset) -> some View {
        Button {
            presets.toggleFavorite(preset.id)
        } label: {
            Image(systemName: presets.isFavorite(preset.id) ? "star.fill" : "star")
                .foregroundStyle(
                    presets.isFavorite(preset.id)
                        ? AnyShapeStyle(Color.orange)
                        : AnyShapeStyle(Color.secondary.opacity(0.5))
                )
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier("browser.favorite.\(preset.id)")
        .accessibilityLabel(Text("Favorite", bundle: .module))
    }

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
        .accessibilityIdentifier("browser.share.\(preset.id)")
        .accessibilityLabel(Text("Share", bundle: .module))
    }

    /// The instrument, the payload, and when it last changed — the three
    /// things that tell one preset from another in a list that spans every
    /// instrument. The date is simply absent on presets saved before
    /// stamping existed: a blank is honest, an invented date isn't.
    private func subtitle(for preset: Preset) -> String {
        var parts = [templateName(preset.templateID)]
        parts.append(
            PresetPayloadSummary.text(
                strings: preset.strings, referenceHz: preset.referenceHz,
                temperament: preset.temperament))
        if let changed = preset.modifiedAt {
            parts.append(Self.relative.localizedString(for: changed, relativeTo: Date()))
        }
        return parts.joined(separator: " · ")
    }

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    // MARK: - Controls

    private var sortMenu: some View {
        Menu {
            Picker(selection: $order) {
                Text("Recently changed", bundle: .module).tag(PresetBrowsing.Order.recent)
                Text("Name", bundle: .module).tag(PresetBrowsing.Order.name)
                Text("Instrument", bundle: .module).tag(PresetBrowsing.Order.instrument)
            } label: {
                Text("Sort", bundle: .module)
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .accessibilityIdentifier("browser.sort")
        .accessibilityLabel(Text("Sort", bundle: .module))
    }

    /// Offered only for instruments that actually have presets — a filter
    /// that can only produce an empty list is a dead end.
    private var filterMenu: some View {
        Menu {
            Picker(selection: $templateFilter) {
                Text("All instruments", bundle: .module).tag(String?.none)
                ForEach(filterableTemplates, id: \.self) { templateID in
                    Text(LocalizedStringKey(templateName(templateID)), bundle: .module)
                        .tag(String?.some(templateID))
                }
            } label: {
                Text("Instrument", bundle: .module)
            }
            .pickerStyle(.inline)
        } label: {
            Image(
                systemName: templateFilter == nil
                    ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
        }
        .accessibilityIdentifier("browser.filter")
        .accessibilityLabel(Text("Filter by instrument", bundle: .module))
    }

    // MARK: - Data

    private var items: [PresetBrowsing.Item] {
        presets.presets.map {
            PresetBrowsing.Item(
                id: $0.id, name: $0.name, templateID: $0.templateID, modifiedAt: $0.modifiedAt)
        }
    }

    private var arranged: [Preset] {
        let byID = Dictionary(uniqueKeysWithValues: presets.presets.map { ($0.id, $0) })
        return PresetBrowsing.arrange(
            items, order: order, templateID: templateFilter,
            displayName: { templateName($0) }
        )
        .compactMap { byID[$0.id] }
    }

    private var filterableTemplates: [String] {
        PresetBrowsing.filterableTemplates(items, displayName: { templateName($0) })
    }

    /// The template's catalog name — what the user reads. Falls back to the
    /// id for a template this build doesn't know, which a synced preset
    /// from a newer version could carry.
    private func templateName(_ templateID: String) -> String {
        Instrument.named(templateID)?.name ?? templateID
    }

    private func beginRename(_ preset: Preset) {
        renameText = preset.name
        renaming = preset
    }

    private var canRename: Bool {
        guard let target = renaming else { return false }
        return presets.isNameAvailable(
            renameText, templateID: target.templateID, excluding: target.id)
    }
}
