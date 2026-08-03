import NitpitchCore
import SwiftUI

// The wide presentation, and the tuning menu's vocabulary — out of the type
// body: SwiftLint counts the struct's lines, and the view proper is the part
// worth keeping in one eyeful.
extension InstrumentGridView {
    /// One cell's design footprint, the unit the scale multiplies.
    private static var cellDesign: CGSize { CGSize(width: 230, height: 158) }

    /// The grid's shape for this viewport. On iOS the column count is the
    /// user's picker and the cells scale to the width — down to half size,
    /// so three-across on an SE shrinks to fit instead of overflowing. On
    /// the Mac the window is continuously resizable, so both the column
    /// count and the scale are chosen to FILL: try every count, compute the
    /// scale each reaches inside the window (width and height both), and
    /// take the largest — a big squarish window gets 2×2 huge dials rather
    /// than one thin row across the top.
    func dialLayout(for size: CGSize) -> (columns: Int, scale: CGFloat) {
        let count = max(1, strings.tuners.count)
        #if os(macOS)
        var best = (columns: 1, scale: CGFloat(0))
        for candidate in 1...count {
            let rows = CGFloat((count + candidate - 1) / candidate)
            let cellWidth =
                (size.width - 32 - CGFloat(candidate - 1) * 12) / CGFloat(candidate)
            let cellHeight = (size.height - 150 - (rows - 1) * 12) / rows
            let scale = min(
                cellWidth / Self.cellDesign.width, cellHeight / Self.cellDesign.height)
            if scale > best.scale { best = (candidate, scale) }
        }
        return (best.columns, min(3.0, max(0.6, best.scale)))
        #else
        let cellWidth = (size.width - 32 - CGFloat(columns - 1) * 12) / CGFloat(columns)
        return (columns, min(1.8, max(0.5, cellWidth / Self.cellDesign.width)))
        #endif
    }

    /// The strings as strings: one horizontal strip each, stacked like the
    /// instrument's own strings across the display.
    func strips(for size: CGSize) -> some View {
        // Direction is the viewer's call: low string on top ("as you look
        // down, fat closest") or reversed ("as you play it" / tab order).
        // Distinct from left-handedness, which will be the instrument's
        // property and affect every view.
        let ordered =
            settings.stripsReversed ? displayedTuners.reversed() : displayedTuners
        // Sized to FIT: a phone in landscape holds all four strips without
        // scrolling (they compress a little), a huge Mac window grows them.
        let count = CGFloat(max(1, ordered.count))
        let available = size.height - 150 - (count - 1) * 10
        let scale = min(2.0, max(0.45, available / (count * 64)))
        return VStack(spacing: 10) {
            ForEach(Array(ordered.enumerated()), id: \.offset) { position, entry in
                NavigationLink(value: TunerRoute.string(instance.id, entry.index)) {
                    StringStrip(tuner: entry.tuner, naming: settings.naming, scale: scale)
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
