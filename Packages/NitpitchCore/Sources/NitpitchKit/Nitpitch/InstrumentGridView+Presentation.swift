import NitpitchCore
import SwiftUI

// The wide presentation, and the tuning menu's vocabulary — out of the type
// body: SwiftLint counts the struct's lines, and the view proper is the part
// worth keeping in one eyeful.
extension InstrumentGridView {
    /// The strings as strings: one horizontal strip each, stacked like the
    /// instrument's own strings across the display.
    var strips: some View {
        VStack(spacing: 10) {
            ForEach(Array(displayedTuners.enumerated()), id: \.offset) { position, entry in
                NavigationLink(value: TunerRoute.string(instance.id, entry.index)) {
                    StringStrip(tuner: entry.tuner, naming: settings.naming)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("strips.row.\(position)")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    /// Catalog names are localizable; a user's custom tuning has no name to
    /// translate, and "Custom" is the catalog's word for that.
    func tuningText(_ name: String) -> Text {
        Text(LocalizedStringKey(name), bundle: .module)
    }

    /// The user's name verbatim, with the reference riding along when the
    /// preset carries one — the label says what loading will do.
    func presetLabel(_ preset: Preset) -> Text {
        if let reference = preset.reference {
            return Text(verbatim: "\(preset.name) · A=\(Int(reference.hz))")
        }
        return Text(verbatim: preset.name)
    }

    /// The claimed preset — still existing; a dangling id after a deletion
    /// counts as none. Values may have drifted: that's "(edited)", not gone.
    var loadedPreset: Preset? {
        guard let id = instance.loadedPresetID else { return nil }
        return presets.presets(fitting: instance).first { $0.id == id }
    }

    /// Whether a tuning row may carry the checkmark: no preset claim standing
    /// in the way (intact or drifted — a drifted claim still owns the pill).
    var claimIsFree: Bool { loadedPreset == nil }

    /// Whether loading this preset would change nothing — the equals mark.
    func valuesMatch(_ preset: Preset) -> Bool {
        instance.strings == preset.strings
            && (preset.referenceHz == nil || preset.referenceHz == instance.referenceHz)
    }

    @ViewBuilder
    func menuRow(_ label: Text, checked: Bool, matching: Bool) -> some View {
        if checked {
            Label {
                label
            } icon: {
                Image(systemName: "checkmark")
            }
        } else if matching {
            Label {
                label
            } icon: {
                Image(systemName: "equal")
            }
        } else {
            label
        }
    }

    var fittingTunings: [Tuning] {
        guard let template = instance.template else { return [] }
        return template.knownTunings.filter { $0.strings.count == instance.strings.count }
    }
}

/// One cell, observing its own string's model.
struct StringCell: View {
    @ObservedObject var tuner: StringTunerViewModel
    let naming: NoteNaming
    var scale: CGFloat = 1

    var body: some View {
        CompactDial(
            name: tuner.target.name(in: naming), cents: cents, level: tuner.level,
            scale: scale)
    }

    private var cents: Double? {
        if case .reading(let cents, _) = tuner.state { return cents }
        return nil
    }
}
