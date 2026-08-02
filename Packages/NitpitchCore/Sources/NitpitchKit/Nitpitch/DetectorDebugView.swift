import NitpitchCore
import SwiftUI

/// Detector thresholds, adjustable while an instrument is playing, above a live
/// readout of what every string's detector is actually seeing.
///
/// The two halves are the point, and neither works without the other. Moving a
/// threshold blind tells you nothing; watching the raw numbers without being
/// able to move anything tells you what's wrong but not what to do. Together
/// they answer the only question that matters here: what value makes this
/// instrument, in this room, through this microphone, read correctly.
///
/// Reachable only under `-debug` (see `LaunchStores.isDebug`). Nothing is
/// persisted — see `DetectionSettings` for why that's deliberate.
struct DetectorDebugView: View {
    @ObservedObject var detection: DetectionSettings
    let strings: StringTuners
    let naming: NoteNaming
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                engineSection
                liveSection
                thresholdSection
                bandSection
                resetSection
            }
            .formStyle(.grouped)
            .navigationTitle(Text(verbatim: "Detector"))
            .accessibilityIdentifier("debug.detector")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done", bundle: .module)
                    }
                }
            }
        }
        .frame(minWidth: 420, minHeight: 520)
        // Raw results are only published while this screen is up.
        .onAppear { strings.setReportingRaw(true) }
        .onDisappear { strings.setReportingRaw(false) }
    }

    /// The A/B switch this screen exists for: the same instrument, the same
    /// room, both algorithms.
    private var engineSection: some View {
        Section {
            Picker(selection: $detection.tuning.engine) {
                Text(verbatim: "MPM").tag(DetectionTuning.Engine.mpm)
                Text(verbatim: "Spectral").tag(DetectionTuning.Engine.spectral)
            } label: {
                Text(verbatim: "Engine")
            }
            .pickerStyle(.segmented)
        } header: {
            Text(verbatim: "Engine")
        } footer: {
            Text(
                verbatim: "MPM: one detector per string, subharmonic shadows filtered out; "
                    + "finds a badly slack string but can't do two at once. "
                    + "Spectral: every string measured from one spectrum; handles double "
                    + "stops, but a string more than a semitone off shows nothing.")
        }
    }

    /// One row per string, updating live. This is where a subharmonic shows
    /// itself: play one note and watch which rows light and what they claim.
    private var liveSection: some View {
        Section {
            ForEach(Array(strings.tuners.enumerated()), id: \.offset) { _, tuner in
                DetectorRow(tuner: tuner, naming: naming)
            }
        } header: {
            Text(verbatim: "Live")
        } footer: {
            Text(
                verbatim: """
                    Each string's own detector, before smoothing. Play one note: \
                    a row lighting up that isn't the note you played is the \
                    problem worth chasing.
                    """)
        }
    }

    private var thresholdSection: some View {
        Section {
            Knob(
                title: "Clarity gate",
                value: $detection.tuning.clarityThreshold,
                range: DetectionTuning.Limits.clarity,
                format: { String(format: "%.2f", $0) },
                note: "Below this a frame is rejected. Higher is stricter.")

            Knob(
                title: "Peak pick",
                value: $detection.tuning.peakPickThreshold,
                range: DetectionTuning.Limits.peakPick,
                format: { String(format: "%.2f", $0) },
                note: "Octave guard. Lower favours the fundamental over its harmonics.")

            Knob(
                title: "Silence",
                value: Binding(
                    get: { Double(detection.tuning.silenceRMS) },
                    set: { detection.tuning.silenceRMS = Float($0) }),
                range: DetectionTuning.Limits.silence,
                format: { String(format: "%.4f", $0) },
                note: "Frames quieter than this are skipped entirely.")
        } header: {
            Text(verbatim: "Thresholds")
        }
    }

    private var bandSection: some View {
        Section {
            Knob(
                title: "Band width",
                value: $detection.tuning.maxSemitonesFromString,
                range: DetectionTuning.Limits.semitones,
                format: { String(format: "±%.1f st", $0) },
                note: "How far from its target a string still answers.")
        } header: {
            Text(verbatim: "Bands")
        } footer: {
            Text(
                verbatim: """
                    Bands normally meet at the midpoint between neighbouring \
                    strings, so every pitch belongs to exactly one. Narrowing \
                    below that opens gaps where nothing responds at all.
                    """)
        }
    }

    private var resetSection: some View {
        Section {
            Button(role: .destructive) {
                detection.reset()
            } label: {
                Text(verbatim: "Reset to shipped defaults")
            }
            .disabled(!detection.isModified)
        }
    }
}

/// One string's raw detector state.
private struct DetectorRow: View {
    @ObservedObject var tuner: StringTunerViewModel
    let naming: NoteNaming

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // With the octave, unlike the grid cell: the question this screen
            // exists to answer is whether a reading is the string or something
            // an octave off it, and "G" alone can't say.
            Text(verbatim: tuner.target.fullName(in: naming))
                .font(.body.weight(.semibold).monospacedDigit())
                .frame(width: 48, alignment: .leading)
                .foregroundStyle(isFound ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: headline)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(isFound ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                Text(verbatim: detail)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
    }

    private var isFound: Bool { tuner.lastResult.frequency != nil }

    /// What the detector found, and how far that is from this string.
    private var headline: String {
        guard let hz = tuner.lastResult.frequency else { return "—" }
        let cents = 1200 * log2(hz / tuner.target.frequency())
        return String(format: "%.1f Hz  %+.0f¢", hz, cents)
    }

    /// Why it did or didn't report — the numbers the sliders move.
    private var detail: String {
        let result = tuner.lastResult
        return String(
            format: "clarity %.2f · rms %.4f · band %.0f–%.0f",
            result.clarity, result.rms, tuner.band.lowerBound, tuner.band.upperBound)
    }
}

/// A labelled slider with its current value and a line on what it does.
///
/// Sliders rather than steppers because the useful move here is a sweep —
/// dragging while the instrument sounds and watching where the reading breaks,
/// which is the fastest way to find an edge.
private struct Knob: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: (Double) -> String
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(verbatim: title)
                Spacer()
                Text(verbatim: format(value))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range)
            Text(verbatim: note)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}
