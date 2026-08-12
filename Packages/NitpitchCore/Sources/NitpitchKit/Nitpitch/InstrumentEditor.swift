import NitpitchCore
import SwiftUI

/// The instrument editor: this instrument's targets, and nothing else.
/// Nudge any string's pitch in place — the rows are `StringListEditor`,
/// shared with the creation sheet.
///
/// **The string COUNT is fixed once an instrument exists.** A six-string
/// guitar doesn't become a seven-string guitar; that's a different
/// instrument. Allowing it here was a real bug in both directions: the live
/// screen kept a dial per old string (the tuners are built per string and
/// were silently truncated), and every preset saved at the old shape was
/// stranded, since a preset only loads onto an instrument with the same
/// number of strings. "Change string count…" leads to the creation sheet
/// instead, prefilled from this instrument — the honest move, and the one
/// that leaves the original intact.
///
/// Pitch nudges keep a loaded preset's claim, like the string view's
/// stepper.
///
/// Like the creation sheet, the presentation forks: an iPhone List, and a
/// Mac form that hugs exactly its rows (`fixedSize`) — growing as strings
/// are added, scrolling only when a truly long instrument outgrows a
/// screen's worth.
struct InstrumentEditor: View {
    @ObservedObject var store: InstrumentStore
    @ObservedObject var presets: PresetStore
    @ObservedObject var settings: Settings
    let instanceID: String
    /// Opens the creation sheet for a new instrument of this kind — the
    /// way to a differently-strung one. Nil where the caller has no sheet
    /// to present it in.
    var onChangeStringCount: ((InstrumentInstance) -> Void)?
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
                        StringListEditor.blockHeight(
                            strings: instance.strings.count, canResize: false), 440)
                )
                .disabled(instance.isLocked)
                HStack {
                    changeCountButton(for: instance)
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
                    if onChangeStringCount != nil, !instance.isLocked {
                        Section {
                            changeCountButton(for: instance)
                        } footer: {
                            Text(
                                "A different number of strings is a different instrument.",
                                bundle: .module)
                        }
                    }
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
            lowOnTop: settings.stripsLowOnTop,
            canResize: false
        ) { edited in
            store.setEditedStrings(id: instanceID, edited)
        }
    }

    /// The way to a differently-strung instrument of the same kind: the
    /// creation sheet, prefilled from this one. Discoverability is the
    /// whole point — without it, "make a 7-string" means finding the +
    /// menu and knowing it offers string counts.
    @ViewBuilder
    private func changeCountButton(for instance: InstrumentInstance) -> some View {
        if let onChangeStringCount {
            Button {
                dismiss()
                onChangeStringCount(instance)
            } label: {
                Text("Change string count…", bundle: .module)
            }
            .accessibilityIdentifier("editor.changeCount")
        }
    }

    /// The same naming rule as everywhere: the tuning's identity follows
    /// the pitches, so edits relabel it by themselves.
    private func tuningCaption(for instance: InstrumentInstance) -> some View {
        Text(LocalizedStringKey(presets.tuningDisplayName(for: instance)), bundle: .module)
            .foregroundStyle(.secondary)
    }
}
