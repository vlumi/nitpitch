import NitpitchCore
import NitpitchData
import SwiftUI

/// One glance, one answer: the note, its cents, and the light strip — the
/// strips' light-dot vocabulary is already watch-sized, so the wrist gets
/// that rather than a shrunken arc. Chromatic only for now: play anything
/// (a harmonic included — its cent error IS the string's) and read it.
struct WatchTunerView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var sync: SyncEngine
    @StateObject private var tuner = WatchTunerViewModel()

    var body: some View {
        VStack(spacing: 6) {
            switch tuner.state {
            case .reading(let note, let cents):
                reading(note: note, cents: cents)
            // Verbatim strings on purpose: the watch target carries no
            // string catalog yet — localization is deferred repo-wide, and
            // a catalog-less `String(localized:)` invites exactly the
            // key-pruning churn the Kit catalog had to be armored against.
            case .listening:
                status("Play a note")
            case .denied:
                status("Microphone access is off")
            case .unavailable:
                status("No microphone")
            case .idle:
                status(" ")
            }
            NavigationLink {
                WatchSettingsView(settings: settings, sync: sync)
            } label: {
                Text(verbatim: "A=\(Int(settings.reference.hz))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.bordered)
        }
        .task {
            tuner.configure(reference: settings.reference)
            await tuner.begin()
        }
        .onDisappear { tuner.end() }
        .onChange(of: settings.reference) { _, reference in
            tuner.configure(reference: reference)
        }
    }

    private func reading(note: Note, cents: Double) -> some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(verbatim: note.name(in: settings.naming))
                    .font(.system(size: 46, weight: .semibold, design: .rounded))
                Text(verbatim: "\(note.octave)")
                    .font(.system(size: 24, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Text(verbatim: String(format: "%+.0f¢", cents))
                .font(.system(size: 16, design: .rounded))
                .foregroundStyle(TuningDisplay.isInTune(cents: cents) ? .green : .orange)
            lightStrip(cents: cents)
        }
    }

    /// The same strip as every other screen: eleven dots on ratio-spaced
    /// thresholds, centre means in tune.
    private func lightStrip(cents: Double) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<TuningDisplay.lightCount, id: \.self) { index in
                Circle()
                    .fill(
                        index == TuningDisplay.centerLightIndex
                            ? Color.green : Color.orange
                    )
                    .opacity(
                        0.15 + 0.85 * TuningDisplay.lightIntensity(index: index, cents: cents)
                    )
                    .frame(width: 7, height: 7)
            }
        }
    }

    private func status(_ text: String) -> some View {
        VStack(spacing: 8) {
            Text(verbatim: text)
                .font(.headline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if case .listening = tuner.state {
                lightStrip(cents: .infinity)
                    .opacity(0.4)
                if !tuner.measurementMode {
                    // The roadmap unknown, answered on the wrist: watchOS
                    // refused `.measurement`, so input processing is on.
                    Text(verbatim: "(measurement mode refused)")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}
