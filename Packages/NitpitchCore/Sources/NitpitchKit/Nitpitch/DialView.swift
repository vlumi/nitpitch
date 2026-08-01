import NitpitchCore
import SwiftUI

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
        GeometryReader { geo in
            let arc = TuningDisplay.arc(forCents: cents)
            ZStack {
                DialTrack()
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                DialTicks()
                    .stroke(Color.secondary.opacity(0.45), lineWidth: 1)
                ErrorFill(sweepDegrees: arc.sweepDegrees)
                    .fill(tint.gradient)
                    .animation(.easeOut(duration: 0.12), value: cents)
                // Both needles last, so they stay visible against the fill.
                ReadingNeedle(sweepDegrees: arc.sweepDegrees)
                    .fill(tint)
                    .animation(.easeOut(duration: 0.12), value: cents)
                CentreNeedle()
                    .fill(inTune ? Color.green : Color.primary.opacity(0.85))
            }
            .frame(width: geo.size.width, height: geo.size.height)
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
        guard abs(sweepDegrees) > 0.5 else { return Path() }

        let angle = Angle.degrees(-90 + sweepDegrees)
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
            let angle = Angle.degrees(-90 + tick.degrees)
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
    /// The dial's centre sits below the visible area, so the drawn arc is the
    /// top cap of a large circle rather than a small dial in the middle.
    static func centre(in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.midX, y: rect.maxY + rect.height * 0.55)
    }

    /// Leaves headroom above the band for the tick marks and the reading
    /// needle's overhang, both of which sit outside it.
    static func radius(in rect: CGRect) -> CGFloat {
        centre(in: rect).y - rect.minY - maxHalfThickness(in: rect) * 1.9
    }

    /// Half-thickness of the filled band and the needle it stands against.
    static func maxHalfThickness(in rect: CGRect) -> CGFloat {
        rect.height * 0.13
    }

    /// The needle is deliberately narrow: it marks the target, and shouldn't
    /// compete with the fill for attention.
    static let needleHalfWidth: CGFloat = 1.5
}

/// The faint full-range track the band sweeps along.
private struct DialTrack: Shape {
    func path(in rect: CGRect) -> Path {
        let centre = Dial.centre(in: rect)
        let radius = Dial.radius(in: rect)
        let sweep = Angle.degrees(TuningDisplay.fullScaleDegrees)
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

        let magnitude = abs(sweepDegrees)
        // Anything shorter reads as a speck clinging to the needle rather than
        // as nothing; in tune should show nothing at all.
        guard magnitude > 0.5 else { return Path() }
        let direction: Double = sweepDegrees < 0 ? -1 : 1

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
