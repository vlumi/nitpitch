import NitpitchCore
import SwiftUI

/// The instrument editor: a string list, nothing else. Add a string at
/// either end, nudge any target in place, or remove strings down to the
/// last one — the rows themselves are `StringListEditor`, shared with the
/// creation sheet.
///
/// Pitch nudges keep a loaded preset's claim, like the string view's
/// stepper; adding or removing is structural and clears it — the store's
/// `setEditedStrings` reads the difference off the shape.
struct InstrumentEditor: View {
    @ObservedObject var store: InstrumentStore
    @ObservedObject var settings: Settings
    let instanceID: String
    @Environment(\.dismiss) private var dismiss

    private var instance: InstrumentInstance? { store.instance(id: instanceID) }

    var body: some View {
        NavigationStack {
            List {
                if let instance {
                    Section {
                        StringListEditor(
                            strings: instance.strings,
                            naming: settings.naming,
                            lowOnTop: settings.stripsLowOnTop
                        ) { edited in
                            store.setEditedStrings(id: instanceID, edited)
                        }
                    } footer: {
                        // The same naming rule as everywhere: the tuning's
                        // identity follows the pitches, so edits relabel it
                        // by themselves.
                        Text(
                            LocalizedStringKey(instance.tuningName ?? "Custom"),
                            bundle: .module)
                    }
                    .disabled(instance.isLocked)
                }
            }
            .navigationTitle(instance?.nameText ?? Text(verbatim: ""))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done", bundle: .module)
                    }
                    .accessibilityIdentifier("editor.done")
                }
            }
        }
        .frame(
            minWidth: 380,
            // The list's rows: the strings plus the two add rows.
            minHeight: Self.sheetHeight(rows: (instance?.strings.count ?? 4) + 2, chrome: 150))
    }

    /// Tall enough for exactly the list, growing as strings are added,
    /// capped where a screen stops being one — a Mac sheet that scrolled
    /// six guitar strings was pointless economy, and one padded past its
    /// rows pools the leftover as a margin above the buttons. `rows` is
    /// every visible list row; `chrome` is the measured rest (bars and
    /// insets). Piano and harp will need a different shape entirely; for
    /// anything strung this holds.
    static func sheetHeight(rows: Int, chrome: CGFloat) -> CGFloat {
        min(720, chrome + CGFloat(rows) * 44)
    }
}
