#if os(macOS)
import NitpitchCore
import SwiftUI

/// The Mac's launch layout: the phone's composition, with the rack scrolling
/// instead of inflating the canvas.
///
/// A phone has a fixed screen, so the rack and the tuner share one design
/// canvas that scales as a unit — every pinned row costs the dial some size,
/// which is why the rack caps at four rows there.
///
/// A window is served in the other order: **the tuner is paid first**, and
/// the rack scrolls inside whatever is left. Giving the rack what it "needs"
/// and the tuner the remainder is the same mistake as scaling the canvas, one
/// step removed — a long collection still ends up eating the dial. So the
/// tuner takes its share of the window and the rack lives on the rest,
/// however many instruments there are.
///
/// Everything else — dial beside controls when wide, above them when tall,
/// the stepper travelling WITH the rack because they are one column of
/// controls — is the layout the phone already had, and is deliberately
/// unchanged: it was right.
extension ChromaticTunerView {
    var macLayout: some View {
        GeometryReader { geo in
            // Side by side only once it EARNS it. A pure aspect test put a
            // 670×580 window just over the line, and after the rack's fixed
            // column the dial was left ~300pt: squeezed and flat, worse than
            // the stacked layout at the same size. So the question isn't "is
            // this window wide?" but "is there a real dial's worth of width
            // left after the rack?".
            let dialPane = geo.size.width - Self.macRackWidth - 24
            let sideBySide =
                dialPane >= Self.minSideBySideDialWidth
                && geo.size.width > geo.size.height * 1.15
            if sideBySide {
                HStack(alignment: .center, spacing: 24) {
                    scaledDial(in: CGSize(width: dialPane, height: geo.size.height))
                    macControls(
                        rackHeight: Self.rackHeight(
                            allowed: geo.size.height - 80, needed: rackNeeded)
                    )
                    .frame(width: Self.macRackWidth)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Stacked, every rack row is height the dial doesn't get, so
                // the tuner is paid first: it keeps `macTunerShare` of the
                // window and the rack scrolls in the remainder.
                let rackHeight = Self.rackHeight(
                    allowed: geo.size.height * (1 - Self.macTunerShare) - 60,
                    needed: rackNeeded)
                VStack(spacing: 16) {
                    scaledDial(
                        in: CGSize(
                            width: geo.size.width,
                            height: max(1, geo.size.height - rackHeight - 16)))
                    macControls(rackHeight: rackHeight)
                        .frame(maxWidth: Self.macStackedControlsWidth)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
    }

    /// The dial, SCALED into the space it's given.
    ///
    /// `TunerDial` is a fixed-size unit — a 110pt arc with the readout and
    /// light strip stacked below — so widening its frame only spreads the same
    /// short arc into a flat smear, which is exactly the shape that looked
    /// broken. It has to be scaled as a whole, the way the phone's canvas
    /// always did it; then a bigger window means a genuinely bigger tuner
    /// with its proportions intact.
    private func scaledDial(in available: CGSize) -> some View {
        let design = Self.dialDesign
        let scale = min(
            DesignCanvas.maxScale,
            max(0.5, min(available.width / design.width, available.height / design.height)))
        return
            dial
            .frame(width: design.width, height: design.height)
            .scaleEffect(scale, anchor: .center)
            .frame(width: available.width, height: available.height)
    }

    /// The dial's own measured footprint — the arc plus its readout and
    /// strip, the same numbers the phone's canvas uses for this half.
    static let dialDesign = CGSize(width: 400, height: 236)

    /// The controls' column stays a column when stacked: the rack's rows are
    /// text, and a 1000pt-wide row of "Violin · Standard" is a stripe, not a
    /// button. Only the dial earns the extra width.
    static let macStackedControlsWidth: CGFloat = 560

    /// The dial needs at least this much width for side-by-side to beat
    /// stacking. Below it the arc is narrower than the rack beside it, which
    /// reads as a tuner squeezed into a corner rather than a layout.
    static let minSideBySideDialWidth: CGFloat = 420

    /// The rack's column on a wide window: room for a long instrument name
    /// beside its tuning, and no more — the dial gets the rest.
    static let macRackWidth: CGFloat = 320

    /// How much of a STACKED window the tuner keeps before the rack is given
    /// anything. The dial is why the screen exists; the rack is how you leave
    /// it.
    static let macTunerShare: CGFloat = 0.55

    /// The rack's slice: what it needs, never more than it's allowed, and
    /// never so little that it can't show a row or two.
    static func rackHeight(allowed: CGFloat, needed: CGFloat) -> CGFloat {
        max(LaunchRack.rowHeight * 2, min(needed, allowed))
    }

    /// What the rack would take if nothing constrained it.
    private var rackNeeded: CGFloat {
        LaunchRack.height(
            for: pinned, expanded: Set(settings.rackExpanded),
            hasPresets: !presets.presets.isEmpty, rowCap: nil)
    }

    /// The stepper and the rack, as one column — the rack scrolling once it
    /// outgrows its slice.
    private func macControls(rackHeight: CGFloat) -> some View {
        VStack(spacing: 16) {
            referenceStepper
            ScrollView {
                launchRack(rowCap: nil)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: rackHeight)
        }
    }
}
#endif
