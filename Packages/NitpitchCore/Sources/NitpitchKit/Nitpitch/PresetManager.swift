import NitpitchCore
import SwiftUI

/// The saved presets for one template, with the one management action loading
/// can't offer: deletion. Loading and saving live in the tuning menu where
/// the tuning is; this sheet exists so a stale preset can be removed without
/// menu gymnastics.
struct PresetManager: View {
    @ObservedObject var presets: PresetStore
    let templateID: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(templatePresets) { preset in
                    row(for: preset)
                }
            }
            .navigationTitle(Text("Presets", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done", bundle: .module)
                    }
                }
            }
        }
        .frame(minWidth: 360, minHeight: 300)
    }

    private var templatePresets: [Preset] {
        presets.presets.filter { $0.templateID == templateID }
    }

    private func row(for preset: Preset) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: preset.name)
                Text(verbatim: payloadSummary(preset))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                presets.remove(id: preset.id)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("presets.delete.\(preset.id)")
            .accessibilityLabel(Text("Delete", bundle: .module))
        }
    }

    /// What loading would do, spelled out: the pitches, and the reference if
    /// it carries one.
    private func payloadSummary(_ preset: Preset) -> String {
        let notes = preset.strings.map { Note(midi: $0).fullName }.joined(separator: " ")
        if let reference = preset.reference {
            return "\(notes) · A=\(Int(reference.hz))"
        }
        return notes
    }
}
