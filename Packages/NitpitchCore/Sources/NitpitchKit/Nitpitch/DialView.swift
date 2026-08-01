import NitpitchCore
import SwiftUI

/// One complete tuning display: the arc, then the readout and light strip
/// stacked below it — everything specific to a single reading.
///
/// Self-contained by design. Double-stop fifths (ROADMAP § 2) needs two of
/// these on one iPhone screen, so the whole unit targets `height`. Anything
/// applying to *both* dials — reference pitch, instrument — belongs outside.
struct TunerDial<Readout: View>: View {
    let cents: Double
    let inTune: Bool
    let isReading: Bool
    @ViewBuilder var readout: () -> Readout

    /// Height of the arc alone. The readout and light strip stack *below* it.
    ///
    /// The readout was briefly nested in the arc's hollow, which only ever fit
    /// on a wide Mac window: the hollow is ~40–50pt tall at phone width
    /// against the ~96pt the note, cents and strip need, and a taller box
    /// pushes the centre down and shrinks it further. Stacking below is both
    /// simpler and lets the arc keep its full width.
    static var arcHeight: CGFloat { 110 }

    /// The whole unit: arc (less the slack pulled back), readout, light strip.
    ///
    /// Two of these no longer fit an iPhone SE, and that's deliberate. Sizing
    /// the arc down until a pair fitted made it a small hump on a screen that
    /// was visibly half empty — the wrong trade for the layout that ships.
    /// Double-stop fifths (ROADMAP § 2) will need its own answer: a shorter
    /// arc in that mode, or a side-by-side pair on wider screens.
    static var height: CGFloat { arcHeight - apexSlack + 6 + 62 + 6 + 14 }

    var body: some View {
        VStack(spacing: 6) {
            ArcView(cents: cents, inTune: inTune)
                .frame(height: Self.arcHeight)
                // The box reserves height for the arc's *ends*, which hang
                // ~37pt below its centre. Stacking naively leaves that dead
                // space under the apex — right where the note sits — so the
                // readout is pulled back up into it.
                .padding(.bottom, -Self.apexSlack)
            readout()
            LightStrip(cents: cents, isReading: isReading)
        }
    }

    /// Dead height between the band's inner edge at the apex and the bottom of
    /// the arc's box, which the ends' sag forces it to reserve.
    ///
    /// Computed, not stored: the type is generic over its readout, and Swift
    /// has no static stored properties on generic types.
    private static var apexSlack: CGFloat { 30 }
}

/// The dial: a fixed needle standing at vertical, and the gap between it and
/// the current reading filled in.
///
/// The filled region *is* the error — nothing when in tune, growing out to one
/// side as the note drifts. That makes zero mean zero, rather than asking the
/// eye to judge a pointer's position against a mark.
struct ArcView: View {
    let cents: Double
    let inTune: Bool

    var body: some View {
        let arc = TuningDisplay.arc(forCents: cents)
        ZStack {
            DialTrack()
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
            DialTicks()
                .stroke(Color.secondary.opacity(0.45), lineWidth: 1)
            // Flat, not `tint.gradient`: a colour gradient spans the shape's
            // *bounding box*, which at a small sweep is nearly square — so the
            // band rendered as a coloured block with the arc cut out of it.
            ErrorFill(sweepDegrees: arc.sweepDegrees)
                .fill(tint)
                .animation(.easeOut(duration: 0.12), value: cents)
            // Both needles last, so they stay visible against the fill.
            ReadingNeedle(sweepDegrees: arc.sweepDegrees)
                .fill(tint)
                .animation(.easeOut(duration: 0.12), value: cents)
            CentreNeedle()
                .fill(inTune ? Color.green : Color.primary.opacity(0.85))
        }
        .accessibilityHidden(true)
    }

    /// Green when in tune, warming through amber to red as the error grows —
    /// with brightness falling as the hue shifts.
    ///
    /// Hue alone would be invisible to a red-green colour-blind viewer, for
    /// whom green and red desaturate to nearly the same grey. Moving
    /// brightness together with hue keeps the two ends distinguishable in
    /// greyscale, and makes in tune the brightest thing on the dial.
    private var tint: Color {
        let magnitude = min(abs(cents) / TuningDisplay.fullScaleCents, 1)
        // 0.33 (green) → 0.0 (red). The brightness ramp is steep enough to
        // overcome yellow's high intrinsic luminance in the middle of the
        // range: without it, greyscale luminance *rises* before it falls and
        // slightly-flat looks brighter than in tune.
        let hue = 0.33 * pow(1 - magnitude, 1.6)
        let brightness = 1.0 - 0.55 * pow(magnitude, 0.7)
        return Color(hue: hue, saturation: 0.9, brightness: brightness)
    }
}

/// The fixed needle at top dead centre: the target, always in the same place.
private struct CentreNeedle: Shape {
    func path(in rect: CGRect) -> Path {
        let centre = Dial.centre(in: rect)
        let radius = Dial.radius(in: rect)
        let half = Dial.maxHalfThickness(in: rect)
        let width = Dial.needleHalfWidth
        return Path(
            CGRect(
                x: centre.x - width, y: centre.y - radius - half,
                width: width * 2, height: half * 2))
    }
}

/// A needle at the fill's leading edge, marking where the reading actually is.
///
/// Without it the arc's end is a colour boundary the eye has to estimate
/// against the track; with it there's a definite pointer to read off the
/// scale. It overhangs the band slightly on both sides so it stays findable
/// against the fill behind it.
private struct ReadingNeedle: Shape {
    var sweepDegrees: Double

    var animatableData: Double {
        get { sweepDegrees }
        set { sweepDegrees = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let centre = Dial.centre(in: rect)
        let radius = Dial.radius(in: rect)
        let half = Dial.maxHalfThickness(in: rect)
        let overhang = half * 0.35
        let width = Dial.needleHalfWidth

        // Hidden while in tune, where it would sit on top of the centre needle
        // and just thicken it.
        let onTrack = Dial.onTrack(sweepDegrees)
        guard abs(onTrack) > 0.4 else { return Path() }

        let angle = Angle.degrees(-90 + onTrack)
        let cosine = cos(angle.radians)
        let sine = sin(angle.radians)
        let inner = radius - half - overhang
        let outer = radius + half + overhang

        // A rectangle laid along the radius at `angle`: two points on the
        // radial line, expanded sideways by the needle's half-width.
        let acrossX = -sine * width
        let acrossY = cosine * width
        let innerPoint = CGPoint(x: centre.x + cosine * inner, y: centre.y + sine * inner)
        let outerPoint = CGPoint(x: centre.x + cosine * outer, y: centre.y + sine * outer)

        var path = Path()
        path.move(to: CGPoint(x: innerPoint.x - acrossX, y: innerPoint.y - acrossY))
        path.addLine(to: CGPoint(x: outerPoint.x - acrossX, y: outerPoint.y - acrossY))
        path.addLine(to: CGPoint(x: outerPoint.x + acrossX, y: outerPoint.y + acrossY))
        path.addLine(to: CGPoint(x: innerPoint.x + acrossX, y: innerPoint.y + acrossY))
        path.closeSubpath()
        return path
    }
}

/// Scale marks along the track, at the same cent thresholds as the lights.
private struct DialTicks: Shape {
    func path(in rect: CGRect) -> Path {
        let centre = Dial.centre(in: rect)
        let radius = Dial.radius(in: rect)
        let half = Dial.maxHalfThickness(in: rect)

        var path = Path()
        for tick in TuningDisplay.ticks {
            let angle = Angle.degrees(-90 + Dial.onTrack(tick.degrees))
            let cosine = cos(angle.radians)
            let sine = sin(angle.radians)
            // Marks sit outside the band so the fill never covers them.
            let start = radius + half
            let length = half * (tick.isMajor ? 0.85 : 0.5)
            path.move(to: CGPoint(x: centre.x + cosine * start, y: centre.y + sine * start))
            path.addLine(
                to: CGPoint(
                    x: centre.x + cosine * (start + length),
                    y: centre.y + sine * (start + length)))
        }
        return path
    }
}

/// Geometry shared by the arc band and its backdrop, so the band always sits
/// exactly on the track.
private enum Dial {
    /// The dial's centre sits well below the box, so the drawn arc is a broad
    /// shallow cap of a large circle rather than a small hump.
    ///
    /// The depth is what makes the arc wide. Pulling the centre up to 0.12h
    /// once shrank the radius to 64pt on an iPhone SE — the arc spanned barely
    /// a third of the screen — because the ends then hit the bottom edge long
    /// before the sides. Keep it deep and let the *width* bound the radius.
    static func centre(in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.midX, y: rect.maxY + rect.height * 1.3)
    }

    /// Leaves headroom above the band for the tick marks and the reading
    /// needle's overhang, both of which sit outside it.
    ///
    /// Bounded by the width as well as the height. Height alone let the arc
    /// run past the frame's sides on a narrow screen (it clipped on an iPhone
    /// SE), and the `sin(visibleSweep)` term keeps the ends inside the box
    /// rather than merely keeping the apex in view.
    static func radius(in rect: CGRect) -> CGFloat {
        let margin = maxHalfThickness(in: rect) * 1.9
        let cy = centre(in: rect).y

        // Apex must clear the top edge.
        let byApex = cy - rect.minY - margin
        // The arc's ends must clear the sides…
        let bySides = (rect.width / 2 - margin) / sin(visibleSweep.radians)
        // …and the bottom, since the ends hang below the apex by
        // r·(1 − cos θ). Without this the arc dropped out of the frame on a
        // narrow screen even while the apex was comfortably inside.
        let byBottom = (cy - rect.maxY + margin) / (1 - cos(visibleSweep.radians))

        return max(0, min(byApex, bySides, byBottom))
    }

    /// How far from vertical the drawn track extends.
    ///
    /// Less than the ±90° the *reading* can reach: at a full quarter turn the
    /// arc's ends fall to the horizontal and the shape stops reading as the
    /// top cap of a dial. The band still sweeps its full range — this only
    /// bounds how much of the track is drawn behind it.
    ///
    /// 42° keeps the whole arc — apex to ends — inside a 110pt box while the
    /// radius stays bound by the *width*, which is what makes it span ~80% of
    /// the screen. Wider sweeps sag further (the ends drop by r·(1 − cos θ))
    /// and fall out of the box before the sides constrain anything.
    static let visibleSweep = Angle.degrees(42)

    /// Half-thickness of the filled band and the needle it stands against.
    static func maxHalfThickness(in rect: CGRect) -> CGFloat {
        rect.height * 0.15
    }

    /// The needle is deliberately narrow: it marks the target, and shouldn't
    /// compete with the fill for attention.
    static let needleHalfWidth: CGFloat = 1.5

    /// Maps a reading's sweep onto the drawn track.
    ///
    /// `TuningDisplay` works in ±`fullScaleDegrees` (a quarter turn) because
    /// that's the natural way to express "a semitone either way". The track is
    /// drawn shallower, so the reading is compressed to fit it — otherwise a
    /// large error would send the band past the end of its own scale.
    static func onTrack(_ sweepDegrees: Double) -> Double {
        sweepDegrees / TuningDisplay.fullScaleDegrees * visibleSweep.degrees
    }
}

/// The faint track the band sweeps along.
private struct DialTrack: Shape {
    func path(in rect: CGRect) -> Path {
        let centre = Dial.centre(in: rect)
        let radius = Dial.radius(in: rect)
        let sweep = Dial.visibleSweep
        var path = Path()
        path.addArc(
            center: centre, radius: radius,
            startAngle: .degrees(-90) - sweep, endAngle: .degrees(-90) + sweep,
            clockwise: false)
        return path
    }
}

/// The gap between the needle and the reading, filled in.
///
/// A constant-thickness arc from top dead centre out to the reading's angle,
/// cut square at the leading end. Its *length* is the error, so it vanishes
/// when the note is in tune and grows to one side as it drifts — the sign of
/// the sweep is which side.
///
/// The end is flat rather than rounded because a round cap overshoots the
/// reading by half the band's thickness, leaving the eye unsure which point on
/// the dial the arc is actually claiming. A square edge lands on the value.
struct ErrorFill: Shape {
    /// Signed degrees from vertical; negative sweeps flat (left).
    var sweepDegrees: Double

    var animatableData: Double {
        get { sweepDegrees }
        set { sweepDegrees = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let centre = Dial.centre(in: rect)
        let radius = Dial.radius(in: rect)
        let half = Dial.maxHalfThickness(in: rect)

        let onTrack = Dial.onTrack(sweepDegrees)
        let magnitude = abs(onTrack)
        // Anything shorter reads as a speck clinging to the needle rather than
        // as nothing; in tune should show nothing at all.
        guard magnitude > 0.4 else { return Path() }
        let direction: Double = onTrack < 0 ? -1 : 1

        let start = Angle.degrees(-90)
        let end = Angle.degrees(-90 + direction * magnitude)

        // Out along the far edge, straight across the end, back along the near
        // edge — the two straight closes are the square ends.
        var path = Path()
        path.addArc(
            center: centre, radius: radius + half,
            startAngle: start, endAngle: end, clockwise: direction < 0)
        path.addArc(
            center: centre, radius: radius - half,
            startAngle: end, endAngle: start, clockwise: direction > 0)
        path.closeSubpath()
        return path
    }
}
