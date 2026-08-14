import NitpitchCore
import NitpitchData
import SwiftUI

/// The wrist's settings — synced facts, both of them. The sync switch has
/// the phone's honesty: off by default, disabled with a reason when iCloud
/// is signed out. The reference is the chromatic tuner's A (your instruments
/// carry their own, edited on their detail screens); temperament needs no
/// knob here at all — every tunable thing on the wrist is an instance, and
/// instances have theirs.
struct WatchSettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var sync: SyncEngine

    var body: some View {
        List {
            Section {
                Toggle(
                    isOn: Binding(
                        get: { sync.isEnabled },
                        set: { sync.setEnabled($0) }
                    )
                ) {
                    Label("iCloud Sync", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(!sync.isCloudAvailable)
            } footer: {
                Text(
                    verbatim: sync.isCloudAvailable
                        ? "Keeps your instruments, presets and favorites the same on every device."
                        : "Sign in to iCloud on the paired iPhone to sync.")
            }
            Section {
                HStack {
                    Button("−") { settings.reference = settings.reference.lowered() }
                        .disabled(!settings.reference.canLower)
                    Spacer()
                    Text(verbatim: "A=\(Int(settings.reference.hz))")
                        .font(.system(.title3, design: .rounded))
                        .monospacedDigit()
                    Spacer()
                    Button("+") { settings.reference = settings.reference.raised() }
                        .disabled(!settings.reference.canRaise)
                }
                .buttonStyle(.bordered)
            } header: {
                Text(verbatim: "Reference")
            } footer: {
                Text(verbatim: "The chromatic tuner's A; your instruments carry their own.")
            }
        }
        .navigationTitle("Settings")
    }
}
