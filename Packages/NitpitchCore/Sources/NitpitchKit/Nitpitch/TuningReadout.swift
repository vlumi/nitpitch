import NitpitchCore
import SwiftUI

/// The reading's shared vocabulary, one spelling per fact: every screen
/// that shows a cents number, an intonation delta, or speaks a reading to
/// VoiceOver formats it here — so "+2¢" and "2 cents sharp" can never
/// drift between the dial, the strips and the grid cells.
enum TuningReadout {
    /// "+2¢" / "-4¢" / "—". A leading sign on both directions, so flat or
    /// sharp reads at a glance without parsing the number.
    static func centsLabel(_ cents: Double?) -> String {
        guard let cents else { return "—" }
        let rounded = Int(cents.rounded())
        return rounded > 0 ? "+\(rounded)¢" : "\(rounded)¢"
    }

    /// "Δ +1.3" / "Δ —" — the intonation verdict.
    static func deltaLabel(_ delta: Double?) -> String {
        guard let delta else { return "Δ —" }
        return String(format: "Δ %+.1f", delta)
    }

    static func deltaStyle(_ delta: Double?) -> AnyShapeStyle {
        guard let delta else { return AnyShapeStyle(.secondary) }
        return TuningDisplay.isInTune(cents: delta)
            ? AnyShapeStyle(Color.green) : AnyShapeStyle(Color.orange)
    }

    /// The VoiceOver phrasing — "in tune" / "4 cents flat" / "not heard" —
    /// with the octave delta appended when one is being measured.
    static func accessibleValue(cents: Double?, octaveDelta: Double? = nil) -> String {
        var value: String
        if let cents {
            if TuningDisplay.isInTune(cents: cents) {
                value = "in tune"
            } else {
                let rounded = abs(Int(cents.rounded()))
                value = cents < 0 ? "\(rounded) cents flat" : "\(rounded) cents sharp"
            }
        } else {
            value = "not heard"
        }
        if let delta = octaveDelta {
            value += String(format: ", octave delta %+.1f cents", delta)
        }
        return value
    }
}
