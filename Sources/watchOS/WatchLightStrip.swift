import NitpitchCore
import SwiftUI

/// The same strip as every other screen: eleven dots on ratio-spaced
/// thresholds, centre means in tune. Nil cents = no reading — the strip
/// DIMS rather than disappears, so a rest between plucks never reshuffles
/// the layout. One definition; the pane and the chromatic screen had a
/// copy each.
struct WatchLightStrip: View {
    let cents: Double?

    var body: some View {
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
                    .frame(width: 7, height: 7)
            }
        }
        .opacity(cents == nil ? 0.4 : 1)
    }
}
