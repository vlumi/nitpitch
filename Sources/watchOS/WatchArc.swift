import NitpitchCore
import SwiftUI

/// The wrist's arc: distance from centre as ANGLE, through the same
/// logarithmic mapping as the phone's dial (`TuningDisplay.arc` — ±2¢ is
/// 18°, every doubling adds the same step), which is exactly what the dot
/// strip can't say. Drawn FLAT and WIDE — a shallow bow off a large circle,
/// every mapped angle compressed by one visual factor so proportions stay
/// honest — leaving a hollow the string names nest into. A sweep growing
/// rightward is sharp, leftward is flat; ticks mark the in-tune boundary.
struct WatchArc: View {
    /// Nil = no reading: the arc dims rather than disappears, keeping the
    /// pane's one fixed geometry.
    let cents: Double?

    /// Visual degrees per mapped degree: <1 flattens the bow without
    /// touching the mapping's proportions.
    private static let flattening = 0.55

    var body: some View {
        Canvas { [cents = cents ?? .infinity] context, size in
            // A large circle whose centre sits far below the frame: the
            // visible part is the shallow top bow.
            let maxVisual = TuningDisplay.fullScaleDegrees * Self.flattening
            let halfChord = size.width / 2 - 4
            let radius = halfChord / sin(Angle.degrees(maxVisual).radians)
            let center = CGPoint(x: size.width / 2, y: 5 + radius)

            func angle(_ mappedDegrees: Double) -> Double {
                Angle.degrees(-90 + mappedDegrees * Self.flattening).radians
            }

            // The scale: the full ±fullScale bow, quiet.
            var scale = Path()
            scale.addArc(
                center: center, radius: radius,
                startAngle: .degrees(-90 - maxVisual),
                endAngle: .degrees(-90 + maxVisual),
                clockwise: false)
            context.stroke(
                scale, with: .color(.gray.opacity(0.25)),
                style: StrokeStyle(lineWidth: 3, lineCap: .butt))

            // Ticks: centre (the target) and the in-tune boundary either side.
            let boundary = TuningDisplay.arc(forCents: TuningDisplay.inTuneCents).sweepDegrees
            for degrees in [-boundary, 0, boundary] {
                let radians = angle(degrees)
                var tick = Path()
                tick.move(
                    to: CGPoint(
                        x: center.x + (radius - 4) * cos(radians),
                        y: center.y + (radius - 4) * sin(radians)))
                tick.addLine(
                    to: CGPoint(
                        x: center.x + (radius + 4) * cos(radians),
                        y: center.y + (radius + 4) * sin(radians)))
                context.stroke(
                    tick, with: .color(.gray.opacity(degrees == 0 ? 0.7 : 0.45)),
                    style: StrokeStyle(lineWidth: degrees == 0 ? 2 : 1.5, lineCap: .round))
            }

            // The reading: a sweep from the top, log-scaled, colour-coded.
            let sweep = TuningDisplay.arc(forCents: cents).sweepDegrees
            guard abs(sweep) > 0.4 else {
                // In tune to the eye: a proud upright needle instead of a
                // sliver too thin to see.
                var needle = Path()
                needle.move(to: CGPoint(x: center.x, y: center.y - radius + 6))
                needle.addLine(to: CGPoint(x: center.x, y: center.y - radius - 6))
                context.stroke(
                    needle, with: .color(.green),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round))
                return
            }
            var reading = Path()
            reading.addArc(
                center: center, radius: radius,
                startAngle: .degrees(-90),
                endAngle: .degrees(-90 + sweep * Self.flattening),
                clockwise: sweep < 0)
            // Flat ends: the sweep's edge IS the reading, and a round cap
            // smears it half a linewidth past the truth.
            context.stroke(
                reading,
                with: .color(TuningDisplay.isInTune(cents: cents) ? .green : .orange),
                style: StrokeStyle(lineWidth: 5, lineCap: .butt))
        }
        .frame(height: 44)
        .padding(.horizontal, 2)
        .opacity(cents == nil ? 0.4 : 1)
    }
}
