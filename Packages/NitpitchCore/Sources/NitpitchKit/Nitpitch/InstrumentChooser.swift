import NitpitchCore
import SwiftUI

/// The way from the chromatic tuner into an instrument.
///
/// Large and below the dial rather than a menu in the corner: choosing an
/// instrument decides which screen you're on, so it wants the weight of a
/// destination rather than the weight of a setting.
struct InstrumentButton: View {
    let onChoose: (Instrument) -> Void
    @State private var isChoosing = false

    var body: some View {
        Button {
            isChoosing = true
        } label: {
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
        .sheet(isPresented: $isChoosing) {
            InstrumentChooser { instrument in
                isChoosing = false
                onChoose(instrument)
            }
        }
    }
}

/// The instrument list, grouped by family.
///
/// A screen rather than a menu: it's a step into the instrument, and it's
/// where tunings will be chosen alongside the instrument once they exist —
/// they're one decision made together, which a menu has no room for.
struct InstrumentChooser: View {
    let onChoose: (Instrument) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Chromatic is absent by construction — see
                // `Instrument.choosable`.
                ForEach(Instrument.choosable, id: \.family) { group in
                    Section {
                        ForEach(group.instruments) { instrument in
                            Button {
                                onChoose(instrument)
                            } label: {
                                HStack {
                                    Text(LocalizedStringKey(instrument.name), bundle: .module)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.footnote)
                                        .foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("chooser.\(instrument.id)")
                        }
                    } header: {
                        Text(LocalizedStringKey(group.family.name), bundle: .module)
                    }
                }
            }
            .navigationTitle(Text("Instrument", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Cancel", bundle: .module)
                    }
                }
            }
        }
        .frame(minWidth: 320, minHeight: 380)
    }
}
