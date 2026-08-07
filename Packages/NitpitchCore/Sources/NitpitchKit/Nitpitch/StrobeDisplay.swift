import NitpitchCore
import SwiftUI

/// The strobe's screen state, its own observable island: readings feed it
/// ~21×/second and only the band re-renders.
@MainActor
final class StrobeMonitor: ObservableObject {
    /// A crawl in progress: where the pattern stood at `since`, and how
    /// fast it moves — the band interpolates between readings from these,
    /// so the motion is smooth at render rate, not at reading rate.
    struct Crawl: Equatable {
        /// Revolutions, 0..<1, at `since`.
        let phase: Double
        /// Revolutions per second — the tuning error, as the eye reads it.
        let velocity: Double
        /// The current cents error, for the in-tune tint.
        let cents: Double
        let since: Date
    }

    @Published private(set) var crawl: Crawl?

    /// Beyond this the band is dormant: a far-off string is the needle's
    /// business, and a fast strobe is alias shimmer, not information.
    static let gateCents = 10.0

    private var integrator = StrobeIntegrator()

    /// One confident reading of the OPEN string, already smoothed and
    /// measured against the tempered target.
    func ingest(cents: Double, targetHz: Double, dt: Double) {
        guard abs(cents) <= Self.gateCents else {
            clear()
            return
        }
        integrator.advance(cents: cents, targetHz: targetHz, dt: dt)
        let velocity = StrobeIntegrator.hzError(cents: cents, targetHz: targetHz)
        let next = Crawl(
            phase: integrator.phase,
            velocity: velocity,
            cents: cents,
            since: Date())
        if crawl.map({ abs($0.velocity - velocity) > 0.005 || abs($0.cents - cents) > 0.05 })
            ?? true
        {
            crawl = next
        }
    }

    func clear() {
        guard crawl != nil else {
            integrator.reset()
            return
        }
        integrator.reset()
        crawl = nil
    }
}

/// The strobe band: a film-strip of segments crawling at the tuning
/// error's own rate — one segment pitch per hertz-second. Rightward =
/// sharp, leftward = flat, stationary = there; the eye reads sub-cent
/// error as slow drift, which no position display can show. Wakes only
/// near the target (`StrobeMonitor.gateCents`); a11y-hidden — the cents
/// number is the accessible channel, and this is pure motion.
struct StrobeBand: View {
    @ObservedObject var strobe: StrobeMonitor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let height: CGFloat = 12
    private static let segmentPitch: CGFloat = 36

    var body: some View {
        ZStack {
            if let crawl = strobe.crawl, !reduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    let elapsed = context.date.timeIntervalSince(crawl.since)
                    let phase = crawl.phase + crawl.velocity * elapsed
                    band(phase: phase, inTune: TuningDisplay.isInTune(cents: crawl.cents))
                }
            }
        }
        .frame(height: Self.height)
        .accessibilityHidden(true)
    }

    private func band(phase: Double, inTune: Bool) -> some View {
        Canvas { context, size in
            let pitch = Self.segmentPitch
            // One revolution scrolls one segment pitch; the fill covers a
            // pitch beyond each edge so the crawl never runs out of stripes.
            let offset =
                (phase.truncatingRemainder(dividingBy: 1) * pitch)
                .truncatingRemainder(dividingBy: pitch)
            let color = inTune ? Color.green.opacity(0.5) : Color.secondary.opacity(0.35)
            var x = -pitch + offset
            while x < size.width + pitch {
                let segment = CGRect(
                    x: x, y: 0, width: pitch / 2, height: size.height)
                context.fill(
                    Path(roundedRect: segment, cornerRadius: size.height / 2),
                    with: .color(color))
                x += pitch
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Self.height / 2))
    }
}
