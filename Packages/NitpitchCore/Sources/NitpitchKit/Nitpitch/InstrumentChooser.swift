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

/// The way from the chromatic tuner into an instrument.
///
/// Large and below the dial rather than a menu in the corner: choosing an
/// instrument decides which screen you're on, so it wants the weight of a
/// destination rather than the weight of a setting. It only *requests* the
/// navigation — the chooser is a pushed screen owned by `RootView`, so back
/// from a grid lands on the list you chose from.
struct InstrumentButton: View {
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 8) {
                Image(systemName: "guitars")
                    .font(.body)
                Text("Tune an instrument", bundle: .module)
                    .font(.body.weight(.medium))
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.secondary.opacity(0.14))
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tuner.instrument")
    }
}

/// Pinned instruments as one-tap chips on the launch screen.
///
/// This is what retires "two taps to reach the violin": a favourite is a
/// repeated setup converted into one tap — and since an instance remembers
/// its state, the chip lands exactly where you left off. Pinning lives in
/// the chooser (the star on each row); the row hides itself when nothing is
/// pinned.
struct FavoritesRow: View {
    struct Chip: Identifiable {
        let id: String
        let label: Text
    }

    let chips: [Chip]
    let onChoose: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips) { chip in
                    Button {
                        onChoose(chip.id)
                    } label: {
                        chip.label
                            .font(.callout.weight(.medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("favorite.\(chip.id)")
                }
            }
            // Breathing room so the capsules' edges aren't clipped by the
            // scroll view at rest.
            .padding(.horizontal, 2)
        }
    }
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

    var body: some View {
        List {
            ForEach(Instrument.choosable, id: \.family) { group in
                Section {
                    ForEach(group.instruments) { template in
                        ForEach(entries(for: template)) { entry in
                            row(for: entry, template: template)
                        }
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
        .alert(
            Text("Rename", bundle: .module),
            isPresented: Binding(
                get: { renamingID != nil },
                set: { if !$0 { renamingID = nil } })
        ) {
            TextField(text: $renameText) { Text("Name", bundle: .module) }
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
    }

    /// One row per instance of the template — with the default instance
    /// present even before it exists in the store, so the list never changes
    /// shape just because something was opened once.
    private func entries(for template: Instrument) -> [InstrumentInstance] {
        let existing = store.instances(of: template)
        if existing.contains(where: { $0.id == template.id }) { return existing }
        let virtualDefault = InstrumentInstance(
            id: template.id, templateID: template.id, name: template.name,
            strings: template.strings, referenceHz: settings.reference.hz,
            isLocked: false, loadedPresetID: nil)
        return [virtualDefault] + existing
    }

    private func row(for entry: InstrumentInstance, template: Instrument) -> some View {
        HStack(spacing: 12) {
            Button {
                onChoose(entry.id)
            } label: {
                HStack(spacing: 6) {
                    entry.nameText
                        .foregroundStyle(.primary)
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

            star(for: entry)

            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundStyle(.tertiary)
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

    /// The + in the toolbar: pick a type, get a fresh numbered instrument and
    /// the rename dialog ready to name it what it really is.
    private var addMenu: some View {
        Menu {
            ForEach(Instrument.choosable, id: \.family) { group in
                ForEach(group.instruments) { template in
                    Button {
                        let added = store.add(of: template)
                        renameText = added.name
                        renamingID = added.id
                    } label: {
                        Text(LocalizedStringKey(template.name), bundle: .module)
                    }
                }
            }
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityIdentifier("chooser.add")
        .accessibilityLabel(Text("Add instrument", bundle: .module))
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
