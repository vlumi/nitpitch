import NitpitchCore
import SwiftUI

/// The same strip as every other screen: eleven dots on ratio-spaced
/// thresholds, centre means in tune. Nil cents = no reading — the strip
/// DIMS rather than disappears, so a rest between plucks never reshuffles
/// the layout.
///
/// A double stop splits the strip into two half-height rows in the SAME
/// footprint — tinier dots, upper string on top, low at the bottom (the
/// app's vertical order) — so each member keeps its own error visible
/// while the arc carries the interval's.
struct WatchLightStrip: View {
    /// One row per sounding voice, low to high; rendered top-down.
    let rows: [Double?]

    init(cents: Double?) { rows = [cents] }

    init(rows: [Double?]) { self.rows = rows }

    var body: some View {
        VStack(spacing: 1) {
            ForEach(Array(rows.enumerated().reversed()), id: \.offset) { _, cents in
                row(cents: cents, dot: rows.count > 1 ? 3 : 7)
            }
        }
        .frame(height: 7)
        .opacity(rows.allSatisfy { $0 == nil } ? 0.4 : 1)
    }

    private func row(cents: Double?, dot: CGFloat) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<TuningDisplay.lightCount, id: \.self) { index in
                Circle()
                    .fill(
                        index == TuningDisplay.centerLightIndex ? Color.green : Color.orange
                    )
                    .opacity(
                        0.15 + 0.85
                            * TuningDisplay.lightIntensity(
                                index: index, cents: cents ?? .infinity)
                    )
                    .frame(width: dot, height: dot)
            }
        }
    }
}
