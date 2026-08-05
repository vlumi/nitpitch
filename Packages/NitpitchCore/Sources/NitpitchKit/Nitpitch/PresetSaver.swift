import NitpitchCore
import SwiftUI

/// Saving a preset: the name, and what rides along. The pitches always do —
/// they're what a preset IS — while the reference and the temperament are
/// each a checkbox, both on by default: a preset is a situation, and the
/// faithful capture is the default, narrowing it the deliberate act.
///
/// A sheet rather than the old alert, which had one button per payload
/// combination ("Tuning only" / "Tuning and reference") — a pattern that
/// stopped scaling the moment temperament became a third dimension.
struct PresetSaver: View {
    let instance: InstrumentInstance
    let naming: NoteNaming
    /// The grid owns the actual save (and the replace confirmation); this
    /// sheet only collects the choices.
    let onSave: (String, _ includeReference: Bool, _ includeTemperament: Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var includeReference = true
    @State private var includeTemperament = true
    @FocusState private var nameFocused: Bool

    /// Only where there's a choice to carry: fretted instruments are
    /// structurally equal, so the row would be noise.
    private var offersTemperament: Bool {
        instance.template?.family == .bowed
    }

    var body: some View {
        #if os(macOS)
        macBody
        #else
        iosBody
        #endif
    }

    #if os(macOS)
    private var macBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Save preset", bundle: .module)
                .font(.headline)
            TextField(text: $name) { Text("Name", bundle: .module) }
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)
                .accessibilityIdentifier("preset.save.name")
                .onSubmit(save)
            toggles
            HStack {
                Button(role: .cancel) {
                    dismiss()
                } label: {
                    Text("Cancel", bundle: .module)
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button(action: save) {
                    Text("Save", bundle: .module)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmed.isEmpty)
                .accessibilityIdentifier("preset.save.confirm")
            }
        }
        .padding(20)
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { nameFocused = true }
    }
    #else
    private var iosBody: some View {
        NavigationStack {
            Form {
                TextField(text: $name) { Text("Name", bundle: .module) }
                    .focused($nameFocused)
                    .accessibilityIdentifier("preset.save.name")
                    .onSubmit(save)
                Section {
                    toggles
                }
            }
            .navigationTitle(Text("Save preset", bundle: .module))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) {
                        Text("Save", bundle: .module)
                    }
                    .disabled(trimmed.isEmpty)
                    .accessibilityIdentifier("preset.save.confirm")
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) {
                        dismiss()
                    } label: {
                        Text("Cancel", bundle: .module)
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear { nameFocused = true }
    }
    #endif

    /// The payload rows: each label carries the value it would capture, so
    /// the checkbox reads as a fact, not a mystery setting.
    @ViewBuilder
    private var toggles: some View {
        Toggle(isOn: $includeReference) {
            HStack(spacing: 6) {
                Text("Reference", bundle: .module)
                Text(verbatim: "\(naming.concertAName)=\(Int(instance.referenceHz))")
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("preset.save.reference")
        if offersTemperament {
            Toggle(isOn: $includeTemperament) {
                HStack(spacing: 6) {
                    Text("Temperament", bundle: .module)
                    Group {
                        switch instance.appliedTemperament {
                        case .equal: Text("Equal", bundle: .module)
                        case .pure: Text("Pure", bundle: .module)
                        }
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("preset.save.temperament")
        }
    }

    private var trimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        guard !trimmed.isEmpty else { return }
        onSave(trimmed, includeReference, offersTemperament && includeTemperament)
        dismiss()
    }
}
