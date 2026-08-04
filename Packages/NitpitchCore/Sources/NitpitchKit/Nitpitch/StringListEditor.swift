import NitpitchCore
import SwiftUI

/// The string list as editable rows — the shared middle of the live
/// instrument editor and the creation sheet. Every edit is computed by
/// `StringListEditing` and handed back whole; the caller decides what the
/// change means (a store write with claim rules, or just a draft).
///
/// Rows stack the shared vertical order (`Settings.stripsLowOnTop`):
/// lowest at the bottom unless flipped, which makes the row numbers a
/// musician's — the 1st string, the highest, reads first from the top.
struct StringListEditor: View {
    let strings: [Int]
    let naming: NoteNaming
    let lowOnTop: Bool
    let onChange: ([Int]) -> Void

    var body: some View {
        Group {
            addRow(lowEnd: lowOnTop)
            ForEach(displayedIndices, id: \.self) { index in
                stringRow(index: index)
            }
            addRow(lowEnd: !lowOnTop)
        }
    }

    /// Rows in the shared vertical order — lowest at the bottom by default.
    private var displayedIndices: [Int] {
        let indices = Array(strings.indices)
        return lowOnTop ? indices : indices.reversed()
    }

    private func addRow(lowEnd: Bool) -> some View {
        Button {
            onChange(StringListEditing.extended(strings, lowEnd: lowEnd))
        } label: {
            Label {
                lowEnd
                    ? Text("Add low string", bundle: .module)
                    : Text("Add high string", bundle: .module)
            } icon: {
                Image(systemName: "plus.circle")
            }
            .foregroundStyle(.tint)
            .contentShape(Rectangle())
        }
        // Explicitly borderless: in the Mac form (a plain stack, not a
        // List) the default style would render a push button.
        .buttonStyle(.borderless)
        // Fixed row heights on purpose — the Mac sheet hugs a stack of
        // these, so their size must be ours, not a list style's.
        .frame(height: Self.addRowHeight)
        .disabled(!StringListEditing.canExtend(strings, lowEnd: lowEnd))
        .accessibilityIdentifier(lowEnd ? "editor.add.low" : "editor.add.high")
    }

    /// The deterministic row metrics the Mac sheets size against.
    static let rowHeight: CGFloat = 36
    static let addRowHeight: CGFloat = 32

    /// The exact height of the whole block — rows plus both add rows —
    /// for containers that hug rather than scroll.
    static func blockHeight(strings count: Int) -> CGFloat {
        CGFloat(count) * rowHeight + 2 * addRowHeight
    }

    private func stringRow(index: Int) -> some View {
        let note = Note(midi: strings[index])
        return HStack(spacing: 12) {
            // The musician's numbering: the 1st string is the highest.
            Text(verbatim: "\(strings.count - index)")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 20)
            NoteNameLabel(note: note, naming: naming, fontSize: 24)
            Spacer()
            step(systemName: "minus", id: "editor.down.\(index)", index: index, by: -1)
            step(systemName: "plus", id: "editor.up.\(index)", index: index, by: 1)
            Button {
                onChange(StringListEditing.removed(strings, at: index))
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(
                        strings.count > 1 ? AnyShapeStyle(.red) : AnyShapeStyle(.tertiary)
                    )
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(strings.count <= 1)
            .accessibilityIdentifier("editor.remove.\(index)")
            .accessibilityLabel(Text("Remove string", bundle: .module))
        }
        .frame(height: Self.rowHeight)
        .accessibilityIdentifier("editor.row.\(index)")
    }

    private func step(systemName: String, id: String, index: Int, by delta: Int) -> some View {
        Button {
            onChange(StringListEditing.stepped(strings, at: index, by: delta))
        } label: {
            Image(systemName: systemName)
                .font(.body.weight(.medium))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .disabled(!Detection.targetMIDIRange.contains(strings[index] + delta))
        .accessibilityIdentifier(id)
        .accessibilityLabel(
            delta < 0
                ? Text("Lower target", bundle: .module)
                : Text("Raise target", bundle: .module))
    }
}
