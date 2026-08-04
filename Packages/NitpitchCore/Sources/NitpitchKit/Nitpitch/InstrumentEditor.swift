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
///
/// Like the creation sheet, the presentation forks: an iPhone List, and a
/// Mac form that hugs exactly its rows (`fixedSize`) — growing as strings
/// are added, scrolling only when a truly long instrument outgrows a
/// screen's worth.
struct InstrumentEditor: View {
    @ObservedObject var store: InstrumentStore
    @ObservedObject var settings: Settings
    let instanceID: String
    @Environment(\.dismiss) private var dismiss

    private var instance: InstrumentInstance? { store.instance(id: instanceID) }

    var body: some View {
        #if os(macOS)
        macBody
        #else
        sheetBody
        #endif
    }

    #if os(macOS)
    private var macBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let instance {
                instance.nameText
                    .font(.headline)
                tuningCaption(for: instance)
                    .font(.callout)
                ScrollView {
                    VStack(spacing: 0) {
                        stringList(for: instance)
                    }
                }
                .frame(
                    height: min(
                        StringListEditor.blockHeight(strings: instance.strings.count), 440)
                )
                .disabled(instance.isLocked)
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Text("Done", bundle: .module)
                    }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("editor.done")
                }
            }
        }
        .padding(20)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }
    #else
    private var sheetBody: some View {
        NavigationStack {
            List {
                if let instance {
                    Section {
                        stringList(for: instance)
                    } footer: {
                        tuningCaption(for: instance)
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
    }
    #endif

    private func stringList(for instance: InstrumentInstance) -> some View {
        StringListEditor(
            strings: instance.strings,
            naming: settings.naming,
            lowOnTop: settings.stripsLowOnTop
        ) { edited in
            store.setEditedStrings(id: instanceID, edited)
        }
    }

    /// The same naming rule as everywhere: the tuning's identity follows
    /// the pitches, so edits relabel it by themselves.
    private func tuningCaption(for instance: InstrumentInstance) -> some View {
        Text(LocalizedStringKey(instance.tuningName ?? "Custom"), bundle: .module)
            .foregroundStyle(.secondary)
    }
}
