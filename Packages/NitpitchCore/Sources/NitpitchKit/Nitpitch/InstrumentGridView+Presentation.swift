import NitpitchCore
import SwiftUI

// The wide presentation, and the tuning menu's vocabulary — out of the type
// body: SwiftLint counts the struct's lines, and the view proper is the part
// worth keeping in one eyeful.
extension InstrumentGridView {
    /// One cell's design footprint, the unit the scale multiplies. The height
    /// is CompactDial's actual stack at scale 1 — meter 3 + arc (58 less the
    /// 28 the name rises into its hollow) + name ~31 + cents ~14 + dots ~11
    /// + four 4pt gaps + 24pt vertical padding ≈ 129 — not a round guess:
    /// overstating it makes every height-bound layout underfill (observed
    /// as a third of the window left empty below the dials).
    /// The intonation layer adds its tiny row (~11 with its gap), so the
    /// footprint is honest in both states.
    private var cellDesign: CGSize {
        CGSize(width: 230, height: isIntonating ? 140 : 129)
    }

    /// What the viewport spends around the dials: the level-meter row (4pt
    /// meter + 6pt top padding) above the grid, and the grid's own 8pt top
    /// padding. The footer is deliberately NOT in here: `safeAreaInset`
    /// already subtracts it from what the GeometryReader reports, and
    /// reserving it a second time is exactly what kept leaving a band of
    /// empty below the grid — the scale stopped early, and the leftover fell
    /// outside the centering frame, pooling at the bottom.
    /// The interval lane joins the DIAL budget only: the strips carry
    /// their chip on the pair's own boundary instead.
    static var meterChrome: CGFloat { 10 }
    static var gridChrome: CGFloat { meterChrome + 8 + IntervalLane.height }

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
        // A picked count (the iOS picker) skips the choice but keeps the
        // scaling, floored low so three-across on an SE shrinks to fit.
        if columns > 0 {
            let cellWidth = (size.width - 32 - CGFloat(columns - 1) * 12) / CGFloat(columns)
            return (columns, min(1.8, max(0.5, cellWidth / cellDesign.width)))
        }
        // Auto, the default on both platforms: try every count, and each
        // added column must EARN its place by making the dials noticeably
        // larger (35% per column) — a phone or a modest window keeps one
        // serene column, a big squarish window goes 2×2 huge. The chrome
        // reservation is `gridChrome`, measured — see its comment for why
        // the footer must not be counted again here.
        var best = (columns: 1, scale: CGFloat(0), score: CGFloat(0))
        for candidate in 1...count {
            let rows = CGFloat((count + candidate - 1) / candidate)
            let cellWidth =
                (size.width - 32 - CGFloat(candidate - 1) * 12) / CGFloat(candidate)
            let cellHeight = (size.height - Self.gridChrome - (rows - 1) * 12) / rows
            let scale = min(
                cellWidth / cellDesign.width, cellHeight / cellDesign.height)
            let score = scale / pow(1.35, CGFloat(candidate - 1))
            if score > best.score { best = (candidate, scale, score) }
        }
        return (best.columns, min(3.0, max(0.5, best.scale)))
    }

    /// Lazy so cost tracks the viewport rather than the string count — which
    /// keeps "only track what's on screen" reachable later, and lets an
    /// arbitrary tuning scale.
    func dialGrid(columns: Int, cellScale: CGFloat) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns),
            spacing: 12
        ) {
            ForEach(gridOrdered(columns: columns), id: \.index) { entry in
                // A cell is a link into its string's full-screen view — the
                // grid shows all of them, the string view holds one.
                NavigationLink(value: TunerRoute.string(instance.id, entry.index)) {
                    StringCell(
                        tuner: entry.tuner, naming: settings.naming, scale: cellScale,
                        isIntonating: isIntonating)
                }
                .buttonStyle(.plain)
                // Identified by STRING, not by visual position: cell 0 is the
                // lowest string wherever the row order puts it.
                .accessibilityIdentifier("grid.cell.\(entry.index)")
                // The sounding interval pair's tinted edge — the lane names
                // the pair, this is where the eye lands next.
                .overlay {
                    IntervalHighlight(interval: strings.interval, index: entry.index)
                }
                // The string's own speaker, a sibling overlay so its taps
                // never reach the navigation underneath. Bottom corner: the
                // top row belongs to the level meter, and the two competed
                // there. Tapping another speaker mid-tone glides to it.
                .overlay(alignment: .bottomTrailing) {
                    ToneSpeaker(
                        tone: strings.tone, tag: .string(entry.index),
                        identifier: "grid.tone.\(entry.index)", font: .caption
                    ) {
                        Task { await strings.toggleTone(string: entry.index) }
                    }
                    .padding(6)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    /// Cells in display order: pitch ascends left to right within a row, and
    /// rows ascend *upward* — the lowest string sits at the bottom of the
    /// grid, the same shared order as the strips, flipped by the same
    /// Settings switch (`Settings.stripsLowOnTop`). Without this, a
    /// one-column grid — which visually IS the strips — read top-down while
    /// the strips read bottom-up.
    private func gridOrdered(columns: Int) -> [(index: Int, tuner: StringTunerViewModel)] {
        let all = displayedTuners
        return Self.gridRows(
            count: all.count, columns: columns, lowOnTop: settings.stripsLowOnTop
        )
        .flatMap { row in row.map { all[$0] } }
    }

    /// String indices (ascending = low to high) arranged into the grid's
    /// visual rows, top row first — exactly what `LazyVGrid` consumes, which
    /// is the point: the grid fills rows top-down row-major, so the sequence
    /// handed to it must already BE the visual arrangement. (Building
    /// bottom-up rows and reversing the flat list garbled every layout whose
    /// count didn't divide the columns: a violin in three columns read
    /// E G D / A.)
    ///
    /// With low at the bottom, the BOTTOM row takes the remainder, so the
    /// full rows stack above it and pitch stays monotone: up and to the
    /// right is always higher — a violin in three columns is G alone at
    /// bottom-left with D A E above, E in the top-right corner.
    static func gridRows(count: Int, columns: Int, lowOnTop: Bool) -> [[Int]] {
        let cols = max(1, columns)
        let indices = Array(0..<max(0, count))
        if lowOnTop {
            // Low at the top reads like a list: plain row-major chunks.
            return stride(from: 0, to: indices.count, by: cols).map {
                Array(indices[$0..<min($0 + cols, indices.count)])
            }
        }
        var rows: [[Int]] = []
        let remainder = indices.count % cols
        var start = remainder == 0 ? min(cols, indices.count) : remainder
        if start > 0 { rows.append(Array(indices[0..<start])) }
        while start < indices.count {
            rows.append(Array(indices[start..<start + cols]))
            start += cols
        }
        return rows.reversed()
    }

    /// Mac only: phones read scrolling content from the top, but a Mac
    /// window's height is chosen by the user, and unfilled height should
    /// frame the content rather than trail it.
    var verticalCentering: Alignment {
        #if os(macOS)
        return .center
        #else
        return .top
        #endif
    }

    /// The strings as strings: one horizontal strip each, stacked like the
    /// instrument's own strings across the display.
    func strips(for size: CGSize) -> some View {
        // Low string at the bottom by default — pitch intuition and tab
        // order agree, and a violin has no view in which its strings stack
        // vertically (see `Settings.stripsLowOnTop`).
        let ordered =
            settings.stripsLowOnTop ? displayedTuners : displayedTuners.reversed()
        // Sized to FIT: a phone in landscape holds all four strips without
        // scrolling — around nine before the floor forces a scroll — and a
        // huge Mac window grows them. The chrome reservation is the shared
        // measured one; 150 here was the same padded guess that left the
        // dial grid a third empty.
        let count = CGFloat(max(1, ordered.count))
        let available = size.height - Self.gridChrome - (count - 1) * 10
        let scale = min(2.0, max(0.45, available / (count * 64)))
        // Height the cap or the floor leaves unspent is spread evenly — the
        // same share between neighbours and at both edges (the centering
        // supplies the edge shares) — so four strings occupy the screen
        // instead of huddling at the top of it.
        let slack = size.height - Self.gridChrome - count * 64 * scale
        let share = max(0, (slack - (count - 1) * 10) / (count + 1))
        // The drawn gauge grades by pitch — the lowest string the fattest,
        // like the set in your hand — independent of display order.
        let total = max(1, strings.tuners.count - 1)
        return VStack(spacing: 10 + share) {
            ForEach(Array(ordered.enumerated()), id: \.offset) { position, entry in
                NavigationLink(value: TunerRoute.string(instance.id, entry.index)) {
                    StringStrip(
                        tuner: entry.tuner, naming: settings.naming, scale: scale,
                        gauge: 1.5 + CGFloat(total - entry.index) / CGFloat(total) * 3.5,
                        isIntonating: isIntonating,
                        tone: strings.tone,
                        toneTag: .string(entry.index),
                        toneIdentifier: "strips.tone.\(entry.index)",
                        onToneToggle: {
                            Task { await strings.toggleTone(string: entry.index) }
                        },
                        boundsIndex: entry.index)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("strips.row.\(position)")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        // The interval chip straddles the sounding pair: snug against the
        // cards' trailing edge, vertically centered on the union of their
        // PUBLISHED bounds — estimated row heights drifted, geometry
        // doesn't. An overlay rather than an inserted row: nothing may
        // reflow the strips mid-bow.
        .overlayPreferenceValue(StripCardBoundsKey.self) { anchors in
            GeometryReader { proxy in
                StripsIntervalOverlay(
                    interval: strings.interval,
                    notes: instance.instrument.notes,
                    naming: settings.naming,
                    anchors: anchors,
                    proxy: proxy)
            }
        }
        .frame(
            minHeight: max(0, size.height - Self.meterChrome),
            alignment: .center)
    }

    /// Catalog names are localizable; a user's custom tuning has no name to
    /// translate, and "Custom" is the catalog's word for that.
    func tuningText(_ name: String) -> Text {
        Text(LocalizedStringKey(name), bundle: .module)
    }

    /// The user's name verbatim, with the reference and a non-equal
    /// temperament riding along when the preset carries them — the label
    /// says what loading will do.
    func presetLabel(_ preset: Preset) -> Text {
        var suffix = ""
        if let reference = preset.reference {
            suffix += " · A=\(Int(reference.hz))"
        }
        if preset.temperament == .pure {
            suffix += " · pure"
        }
        return Text(verbatim: preset.name + suffix)
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
        preset.matchesValues(of: instance)
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

    /// The menu's tunings, pinned-first: a pin is "I reach for this on
    /// THIS instrument", so it floats here even when the instrument never
    /// made the launch screen.
    var orderedTunings: [Tuning] {
        let all = fittingTunings
        let pinned = all.filter { isPinnedTuning($0) }
        return pinned + all.filter { !isPinnedTuning($0) }
    }

    private func isPinnedTuning(_ tuning: Tuning) -> Bool {
        settings.isPinned(
            instrumentID: instance.id,
            presetID: CatalogPinID.make(
                templateID: instance.templateID, tuningName: tuning.name ?? "Custom"))
    }

    /// The menu's presets: pinned (this instrument) first, then favorites
    /// (template-wide, already floated by the store), then the rest.
    var orderedPresets: [Preset] {
        let all = presets.presets(fitting: instance)
        let pinned = all.filter {
            settings.isPinned(instrumentID: instance.id, presetID: $0.id)
        }
        return pinned + all.filter { pin in !pinned.contains(pin) }
    }

    var fittingTunings: [Tuning] { instance.fittingTunings }
}

/// One cell, observing its own string's model.
struct StringCell: View {
    @ObservedObject var tuner: StringTunerViewModel
    let naming: NoteNaming
    var scale: CGFloat = 1
    var isIntonating = false

    var body: some View {
        CompactDial(
            note: tuner.target, naming: naming, cents: cents, level: tuner.level,
            scale: scale,
            octave: isIntonating
                ? CompactDial.OctaveReadout(cents: tuner.octaveCents, delta: tuner.delta)
                : nil)
    }

    private var cents: Double? {
        if case .reading(let cents, _) = tuner.state { return cents }
        return nil
    }
}
