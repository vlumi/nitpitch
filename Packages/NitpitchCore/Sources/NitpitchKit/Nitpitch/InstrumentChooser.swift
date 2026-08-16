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

/// A creation in progress: the kind, and optionally the instrument it is
/// a near-copy of (Duplicate's shortcut into the same sheet).
struct Creation: Identifiable {
    let template: Instrument
    var source: InstrumentInstance?
    /// An explicit string list — an orphaned preset's shape, which beats
    /// both the source's and the template's.
    var strings: [Int]?
    var id: String { source?.id ?? template.id }
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
    @ObservedObject var presets: PresetStore
    /// A shape an orphaned preset needs. Set by the browser; the creation
    /// sheet opens on it once, then it clears.
    var pendingShape: Binding<InstrumentShape?> = .constant(nil)
    let onChoose: (String) -> Void

    /// The instance being renamed, driving the alert.
    @State private var renamingID: String?
    @State private var renameText = ""
    /// The instance whose strings are being edited, driving the sheet.
    @State var editing: EditingStrings?
    /// The creation in progress — a kind, optionally prefilled from a
    /// source instrument (Duplicate) — driving the sheet.
    @State var creating: Creation?

    var body: some View {
        List {
            // Favorites first: the starred instruments, in YOUR order — the
            // same order the launch rack shows, which is exactly why only
            // this section is draggable. Below, everything else, grouped by
            // family like a catalog — but every row is a real, ordinary,
            // fully editable instrument: the factory list is seeded as
            // instances on first launch, and starring any row promotes it.
            if !starred.isEmpty {
                Section {
                    ForEach(starred) { entry in
                        if let template = entry.template {
                            row(for: entry, template: template)
                        }
                    }
                    .onMove { source, destination in
                        settings.favorites.move(fromOffsets: source, toOffset: destination)
                    }
                } header: {
                    Text("Favorites", bundle: .module)
                } footer: {
                    if starred.count > LaunchRack.rowCap {
                        Text("The first four are on the launch screen.", bundle: .module)
                    }
                }
            }
            ForEach(familyGroups, id: \.family) { group in
                Section {
                    ForEach(group.instruments) { entry in
                        if let template = entry.template {
                            row(for: entry, template: template)
                        }
                    }
                } header: {
                    Text(LocalizedStringKey(group.family.name), bundle: .module)
                }
            }
            if starred.isEmpty && familyGroups.isEmpty {
                // Deleting everything is legitimate; a blank screen isn't.
                Section {
                    addMenu(label: emptyStateLabel)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle(Text("Instrument", bundle: .module))
        .toolbar {
            ToolbarItem(placement: .primaryAction) { addMenu }
        }
        .frame(minWidth: 320, minHeight: 380)
        .sheet(item: $editing) { target in
            InstrumentEditor(
                store: store, presets: presets, settings: settings, instanceID: target.id,
                onChangeStringCount: { instance in
                    // A different count is a different instrument: the
                    // creation sheet, prefilled from this one.
                    guard let template = instance.template else { return }
                    creating = Creation(template: template, source: instance)
                })
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
        .sheet(item: $creating) { creation in
            InstrumentCreator(
                store: store, settings: settings, template: creation.template,
                source: creation.source, strings: creation.strings)
        }
        // An orphaned preset asked for an instrument that fits it: open the
        // creation sheet already shaped, and consume the request so it
        // can't fire twice.
        .onAppear { consumePendingShape() }
        .onChangeCompat(of: pendingShape.wrappedValue) { _ in consumePendingShape() }
    }

    private func consumePendingShape() {
        guard let shape = pendingShape.wrappedValue,
            let template = Instrument.named(shape.templateID)
        else { return }
        creating = Creation(template: template, source: nil, strings: shape.strings)
        pendingShape.wrappedValue = nil
    }

    /// The starred instruments, in the favorites list's own order — the
    /// list is both membership and the launch-screen order, one source of
    /// truth, nothing to migrate.
    private var starred: [InstrumentInstance] {
        settings.favorites.compactMap { store.instance(id: $0) }
    }

    /// Everything unstarred, family-grouped like a catalog and ordered by
    /// kind then name — deliberately NOT draggable: the stable shelf, so
    /// the only custom order anywhere is the one the launch screen shows.
    private var familyGroups: [(family: InstrumentFamily, instruments: [InstrumentInstance])] {
        Instrument.choosable.compactMap { group in
            let members = group.instruments.flatMap { template in
                store.instances(of: template)
                    .filter { !settings.favorites.contains($0.id) }
            }
            return members.isEmpty ? nil : (group.family, members)
        }
    }

    private var emptyStateLabel: some View {
        Label {
            Text("Add an instrument", bundle: .module)
        } icon: {
            Image(systemName: "plus.circle.fill")
        }
        .font(.body.weight(.medium))
        .foregroundStyle(.tint)
        .padding(.vertical, 10)
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
                    Text(
                        LocalizedStringKey(presets.tuningDisplayName(for: entry)),
                        bundle: .module
                    )
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
        Button(role: .destructive) {
            removeInstrument(entry)
        } label: {
            Label {
                Text("Delete", bundle: .module)
            } icon: {
                Image(systemName: "trash")
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
        renameText = entry.name
        renamingID = entry.id
    }

    /// Duplicate is a shortcut into the creation sheet, prefilled from the
    /// source — name suggested, strings copied and editable, reference
    /// carried — because "a copy" is usually "near what I want", and
    /// Cancel still creates nothing.
    private func duplicate(_ entry: InstrumentInstance, template: Instrument) {
        creating = Creation(template: template, source: entry)
    }

    private func beginEditStrings(_ entry: InstrumentInstance, template: Instrument) {
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
        Button(role: .destructive) {
            removeInstrument(entry)
        } label: {
            Label {
                Text("Delete", bundle: .module)
            } icon: {
                Image(systemName: "trash")
            }
        }
    }

    /// Deleting takes the instrument's satellites along — its star and its
    /// pins. Any instrument may go, the seeded ones included; the + menu
    /// is always the way back.
    private func removeInstrument(_ entry: InstrumentInstance) {
        store.delete(entry.id, settings: settings)
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

// The sync switch used to live at the foot of this list; it moved to
// Settings (both platforms — the Mac's ⌘, window included), where an
// account-scoped mode is looked for. Most users never need it, and the
// two-device user who does will find Settings.
