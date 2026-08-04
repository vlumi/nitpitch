import NitpitchCore
import SwiftUI

// The + flow — staged creation behind the "New instrument" prompt — out of
// the chooser's main file for the file gauge; same type, same behavior.

/// A creation staged behind the "New instrument" prompt: what would be
/// added, if confirmed. Nothing exists until Create — cancelling a staged
/// add leaves the store exactly as it was.
struct PendingAdd: Identifiable {
    let id = UUID()
    let template: Instrument
    let count: Int?
    /// Custom…: open the string editor on the new instrument right away.
    let openEditor: Bool
}

extension InstrumentChooser {
    private func beginAdd(_ template: Instrument, count: Int?, openEditor: Bool) {
        newName = store.nextAddedName(for: template)
        pendingAdd = PendingAdd(template: template, count: count, openEditor: openEditor)
    }

    func confirmAdd() {
        guard let pending = pendingAdd else { return }
        let added = store.add(of: pending.template, stringCount: pending.count)
        store.rename(id: added.id, to: newName)
        if pending.openEditor {
            editing = EditingStrings(id: added.id)
        }
        pendingAdd = nil
    }

    /// The + in the toolbar: pick a type — and, for anything strung, how
    /// many strings — then get a fresh numbered instrument and the rename
    /// dialog ready to name it what it really is. Uncommon counts extend the
    /// template's own interval pattern (see `Instrument.strings(count:)`),
    /// so a 6-string bass is a creation choice, not a blocked shape.
    var addMenu: some View {
        Menu {
            // One entry per instrument KIND, in the list's own family
            // grouping so the order reads as organized rather than
            // arbitrary. The N-string variants stay off this level — the
            // count is the submenu's question, so nothing gets asked twice.
            ForEach(Instrument.addable, id: \.family) { group in
                Section {
                    ForEach(group.instruments) { template in
                        Menu {
                            ForEach(countOptions(for: template), id: \.self) { count in
                                Button {
                                    beginAdd(template, count: count, openEditor: false)
                                } label: {
                                    if count == template.strings.count {
                                        Text("\(count) strings (standard)", bundle: .module)
                                    } else {
                                        Text("\(count) strings", bundle: .module)
                                    }
                                }
                            }
                            // The odd shapes: created and opened straight
                            // into the string editor — add at either end,
                            // retune in place, no count question.
                            Divider()
                            Button {
                                beginAdd(template, count: nil, openEditor: true)
                            } label: {
                                Text("Custom…", bundle: .module)
                            }
                        } label: {
                            Text(LocalizedStringKey(template.name), bundle: .module)
                        }
                    }
                } header: {
                    Text(LocalizedStringKey(group.family.name), bundle: .module)
                }
            }
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityIdentifier("chooser.add")
        .accessibilityLabel(Text("Add instrument", bundle: .module))
    }

    /// The counts worth offering: around the template's own, and only where
    /// the extension rule can actually produce that many strings.
    private func countOptions(for template: Instrument) -> [Int] {
        let base = template.strings.count
        return (max(2, base - 1)...(base + 4)).filter {
            template.strings(count: $0).count == $0
        }
    }
}
