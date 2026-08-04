import NitpitchCore
import SwiftUI

extension InstrumentInstance {
    /// The name for display: catalog-localized while it's still the
    /// template's own name, verbatim once the user has renamed it — "Strat"
    /// is not a phrase to translate.
    var nameText: Text {
        if let template, name == template.name {
            return Text(LocalizedStringKey(name), bundle: .module)
        }
        return Text(verbatim: name)
    }
}

/// The instance whose strings are open in the editor sheet.
struct EditingStrings: Identifiable {
    let id: String
}

/// The instrument list, grouped by family, pushed onto the stack.
///
/// Rows are your *instruments* — the default one per template (shown even
/// before it's materialized, indistinguishably) plus any you've added. A
/// beginner sees exactly the template list; someone with three guitars sees
/// three rows under Fretted.
///
/// Management forks by platform idiom and shares everything else: the same
/// actions (rename / duplicate / delete) ride iOS swipe actions and the
/// context menu, and on the Mac a visible ellipsis menu — hover-and-hunt
/// right-clicks demonstrably weren't found. Adding is not row work at all:
/// the toolbar's + picks the type.
struct InstrumentChooser: View {
    @ObservedObject var settings: Settings
    @ObservedObject var store: InstrumentStore
    let onChoose: (String) -> Void

    /// The instance being renamed, driving the alert.
    @State private var renamingID: String?
    @State private var renameText = ""
    /// The instance whose strings are being edited, driving the sheet.
    @State var editing: EditingStrings?
    /// The kind being created, driving the creation sheet.
    @State var creating: Instrument?

    var body: some View {
        List {
            // Your instruments first — the things you actually tune — with
            // the untouched catalog below, visibly a catalog. Presence in
            // the store IS the "mine" heuristic: opening, renaming, or
            // starring a template materializes it.
            if !store.myInstruments.isEmpty {
                Section {
                    ForEach(store.myInstruments) { entry in
                        if let template = entry.template {
                            row(for: entry, template: template)
                        }
                    }
                    .onMove { source, destination in
                        store.moveMyInstruments(from: source, to: destination)
                    }
                } header: {
                    Text("My instruments", bundle: .module)
                }
            }
            ForEach(catalogGroups, id: \.family) { group in
                Section {
                    ForEach(group.instruments) { template in
                        catalogRow(for: template)
                    }
                } header: {
                    Text(LocalizedStringKey(group.family.name), bundle: .module)
                }
            }
        }
        .navigationTitle(Text("Instrument", bundle: .module))
        .toolbar {
            ToolbarItem(placement: .primaryAction) { addMenu }
        }
        .frame(minWidth: 320, minHeight: 380)
        .sheet(item: $editing) { target in
            InstrumentEditor(store: store, settings: settings, instanceID: target.id)
        }
        .alert(
            Text("Rename", bundle: .module),
            isPresented: Binding(
                get: { renamingID != nil },
                set: { if !$0 { renamingID = nil } })
        ) {
            TextField(text: $renameText) { Text("Name", bundle: .module) }
                // Fresh identity per presentation: a reused alert TextField
                // keeps its first life's text and ignores the prefill — the
                // rename box came up empty instead of holding the name.
                .id(renamingID)
            Button {
                if let id = renamingID { store.rename(id: id, to: renameText) }
                renamingID = nil
            } label: {
                Text("Rename", bundle: .module)
            }
            Button(role: .cancel) {
                renamingID = nil
            } label: {
                Text("Cancel", bundle: .module)
            }
        }
        .sheet(item: $creating) { template in
            InstrumentCreator(store: store, settings: settings, template: template)
        }
    }

    /// The catalog: templates you haven't touched, still grouped by family.
    /// A family whose every template is already yours disappears from here.
    private var catalogGroups: [(family: InstrumentFamily, instruments: [Instrument])] {
        Instrument.choosable.compactMap { group in
            let untouched = group.instruments.filter { store.instance(id: $0.id) == nil }
            return untouched.isEmpty ? nil : (group.family, untouched)
        }
    }

    /// A catalog row: just the way in. No star, no management — there is
    /// nothing to manage until the first open materializes it as yours.
    private func catalogRow(for template: Instrument) -> some View {
        Button {
            onChoose(template.id)
        } label: {
            HStack(spacing: 10) {
                KindTag(template: template)
                Text(LocalizedStringKey(template.name), bundle: .module)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("chooser.\(template.id)")
    }

    private func row(for entry: InstrumentInstance, template: Instrument) -> some View {
        // The star leads the row — favorites read as a column at a glance —
        // and there's no chevron: it promised nothing the whole row doesn't
        // already do.
        HStack(spacing: 12) {
            star(for: entry)

            KindTag(template: template)

            Button {
                onChoose(entry.id)
            } label: {
                HStack(spacing: 6) {
                    entry.nameText
                        .foregroundStyle(.primary)
                    Text(LocalizedStringKey(entry.tuningName ?? "Custom"), bundle: .module)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        // Visual seasoning only: in the accessibility tree it
                        // would pollute the row's name ("Guitar 2, Standard"),
                        // breaking name-addressed automation and VoiceOver
                        // alike.
                        .accessibilityHidden(true)
                    if entry.isLocked {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("chooser.\(entry.id)")
        }
        #if os(macOS)
        // The Mac's visible affordance: hover-revealed or right-click-only
        // controls are exactly what wasn't found in use.
        .safeAreaInset(edge: .trailing, spacing: 8) { moreMenu(entry, template) }
        #endif
        .contextMenu {
            managementActions(for: entry, template: template)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            swipeButtons(for: entry, template: template)
        }
    }

    /// The same actions the context menu carries, tinted for the swipe tray.
    @ViewBuilder
    private func swipeButtons(
        for entry: InstrumentInstance, template: Instrument
    ) -> some View {
        if entry.id != template.id {
            Button(role: .destructive) {
                settings.favorites.removeAll { $0 == entry.id }
                store.remove(id: entry.id)
            } label: {
                Label {
                    Text("Delete", bundle: .module)
                } icon: {
                    Image(systemName: "trash")
                }
            }
        }
        Button {
            beginRename(entry, template: template)
        } label: {
            Label {
                Text("Rename", bundle: .module)
            } icon: {
                Image(systemName: "pencil")
            }
        }
        .tint(.blue)
        Button {
            duplicate(entry, template: template)
        } label: {
            Label {
                Text("Duplicate", bundle: .module)
            } icon: {
                Image(systemName: "plus.square.on.square")
            }
        }
        .tint(.green)
    }

    /// The Mac's per-row menu — the same actions the swipe carries on iOS.
    private func moreMenu(_ entry: InstrumentInstance, _ template: Instrument) -> some View {
        Menu {
            managementActions(for: entry, template: template)
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .accessibilityIdentifier("chooser.more.\(entry.id)")
    }

    private func beginRename(_ entry: InstrumentInstance, template: Instrument) {
        // Renaming a virtual default materializes it first.
        if store.instance(id: entry.id) == nil {
            _ = store.defaultInstance(for: template)
        }
        renameText = entry.name
        renamingID = entry.id
    }

    private func duplicate(_ entry: InstrumentInstance, template: Instrument) {
        // Duplicating a virtual default materializes it first.
        if store.instance(id: entry.id) == nil {
            _ = store.defaultInstance(for: template)
        }
        _ = store.duplicate(id: entry.id)
    }

    private func beginEditStrings(_ entry: InstrumentInstance, template: Instrument) {
        // Editing a virtual default materializes it first.
        if store.instance(id: entry.id) == nil {
            _ = store.defaultInstance(for: template)
        }
        editing = EditingStrings(id: entry.id)
    }

    /// Rename / duplicate / delete — instrument management, on the row it
    /// manages. Adding lives in the toolbar: it's not about any one row.
    @ViewBuilder
    private func managementActions(
        for entry: InstrumentInstance, template: Instrument
    ) -> some View {
        Button {
            beginRename(entry, template: template)
        } label: {
            Label {
                Text("Rename", bundle: .module)
            } icon: {
                Image(systemName: "pencil")
            }
        }
        Button {
            duplicate(entry, template: template)
        } label: {
            Label {
                Text("Duplicate", bundle: .module)
            } icon: {
                Image(systemName: "plus.square.on.square")
            }
        }
        // The instrument editor: strings are the instrument's physical
        // shape, so the door is here with the other instrument management —
        // and closed while the padlock holds the setup frozen.
        Button {
            beginEditStrings(entry, template: template)
        } label: {
            Label {
                Text("Edit strings…", bundle: .module)
            } icon: {
                Image(systemName: "music.note.list")
            }
        }
        .disabled(entry.isLocked)
        if entry.id != template.id {
            Button(role: .destructive) {
                settings.favorites.removeAll { $0 == entry.id }
                store.remove(id: entry.id)
            } label: {
                Label {
                    Text("Delete", bundle: .module)
                } icon: {
                    Image(systemName: "trash")
                }
            }
        }
    }

    /// Pin/unpin. `.borderless` so the star and the row stay separately
    /// tappable — a plain List row would swallow both into one target.
    private func star(for entry: InstrumentInstance) -> some View {
        let isPinned = settings.favorites.contains(entry.id)
        return Button {
            settings.toggleFavorite(entry.id)
        } label: {
            Image(systemName: isPinned ? "star.fill" : "star")
                .foregroundStyle(isPinned ? Color.yellow : Color.secondary.opacity(0.5))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier("chooser.pin.\(entry.id)")
        .accessibilityLabel(
            isPinned
                ? Text("Remove from favorites", bundle: .module)
                : Text("Add to favorites", bundle: .module))
    }
}
