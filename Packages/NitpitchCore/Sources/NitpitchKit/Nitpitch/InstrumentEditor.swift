import NitpitchCore
import SwiftUI

/// The instrument editor: a string list, nothing else. Add a string at
/// either end — the proposed pitch continues the outermost interval, so a
/// violin grows a viola's C3 below or a B5 above — nudge any target in
/// place, or remove strings down to the last one.
///
/// Strings stack the shared way (`Settings.stripsLowOnTop`): lowest at the
/// bottom unless flipped, same as the grid and the strips. The row numbers
/// are the musician's — the 1st string is the highest, so a violin reads
/// 1 E, 2 A, 3 D, 4 G from the top.
///
/// Pitch edits go through `setString` and keep a loaded preset's claim,
/// like the string view's stepper; adding or removing goes through the
/// structural verbs, which clear it — a new shape is a new setup.
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
                    content(for: instance)
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
        .frame(minWidth: 360, minHeight: 340)
    }

    @ViewBuilder
    private func content(for instance: InstrumentInstance) -> some View {
        let lowOnTop = settings.stripsLowOnTop
        Section {
            addRow(lowEnd: lowOnTop, for: instance)
            ForEach(displayedIndices(for: instance), id: \.self) { index in
                stringRow(index: index, instance: instance)
            }
            addRow(lowEnd: !lowOnTop, for: instance)
        } footer: {
            // The same naming rule as everywhere: the tuning's identity
            // follows the pitches, so edits relabel it by themselves.
            Text(LocalizedStringKey(instance.tuningName ?? "Custom"), bundle: .module)
        }
        .disabled(instance.isLocked)
    }

    /// Rows in the shared vertical order — lowest at the bottom by default.
    private func displayedIndices(for instance: InstrumentInstance) -> [Int] {
        let indices = Array(instance.strings.indices)
        return settings.stripsLowOnTop ? indices : indices.reversed()
    }

    private func addRow(lowEnd: Bool, for instance: InstrumentInstance) -> some View {
        Button {
            store.addString(id: instance.id, lowEnd: lowEnd)
        } label: {
            Label {
                lowEnd
                    ? Text("Add low string", bundle: .module)
                    : Text("Add high string", bundle: .module)
            } icon: {
                Image(systemName: "plus.circle")
            }
            .foregroundStyle(.tint)
        }
        .disabled(!store.canAddString(id: instance.id, lowEnd: lowEnd))
        .accessibilityIdentifier(lowEnd ? "editor.add.low" : "editor.add.high")
    }

    private func stringRow(index: Int, instance: InstrumentInstance) -> some View {
        let note = Note(midi: instance.strings[index])
        return HStack(spacing: 12) {
            // The musician's numbering: the 1st string is the highest.
            Text(verbatim: "\(instance.strings.count - index)")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 20)
            NoteNameLabel(
                note: note, naming: settings.naming, fontSize: 24,
                order: .localizedFirst)
            Spacer()
            step(systemName: "minus", id: "editor.down.\(index)", index: index, by: -1)
            step(systemName: "plus", id: "editor.up.\(index)", index: index, by: 1)
            Button {
                store.removeString(id: instance.id, index: index)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(
                        instance.strings.count > 1 ? AnyShapeStyle(.red) : AnyShapeStyle(.tertiary)
                    )
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(instance.strings.count <= 1)
            .accessibilityIdentifier("editor.remove.\(index)")
            .accessibilityLabel(Text("Remove string", bundle: .module))
        }
        .accessibilityIdentifier("editor.row.\(index)")
    }

    private func step(systemName: String, id: String, index: Int, by delta: Int) -> some View {
        Button {
            guard let midi = instance?.strings[index] else { return }
            store.setString(id: instanceID, index: index, midi: midi + delta)
        } label: {
            Image(systemName: systemName)
                .font(.body.weight(.medium))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .disabled(!canStep(index: index, by: delta))
        .accessibilityIdentifier(id)
        .accessibilityLabel(
            delta < 0
                ? Text("Lower target", bundle: .module)
                : Text("Raise target", bundle: .module))
    }

    private func canStep(index: Int, by delta: Int) -> Bool {
        guard let strings = instance?.strings, strings.indices.contains(index) else {
            return false
        }
        return InstrumentStore.editableMIDIRange.contains(strings[index] + delta)
    }
}
