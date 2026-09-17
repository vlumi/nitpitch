import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// Why the dials are dark when it isn't the room: microphone access
/// refused, or no input device at all. The chromatic screen answers this
/// in its own readout; the grid and the string view had no answer — every
/// dial sat on "listening" with no message and no way out, which to a
/// user who denied the prompt and went straight to their violin is an app
/// that does nothing. A capsule over the content, never in its layout
/// (the grid's chrome arithmetic is exact), with the one useful action:
/// Retry when a device may have appeared, Settings when access is off.
struct CaptureStatusNotice: View {
    @ObservedObject var audio: AudioSessionController

    var body: some View {
        switch audio.status {
        case .permissionDenied:
            notice(Text("Microphone access is off", bundle: .module)) {
                settingsButton
            }
        case .unavailable:
            notice(Text("No audio input device", bundle: .module)) {
                Button {
                    Task { await audio.activate() }
                } label: {
                    Text("Retry", bundle: .module)
                }
                .accessibilityIdentifier("capture.retry")
            }
        case .idle, .running:
            EmptyView()
        }
    }

    private func notice<Action: View>(_ message: Text, @ViewBuilder action: () -> Action)
        -> some View
    {
        HStack(spacing: 12) {
            Image(systemName: "mic.slash")
                .foregroundStyle(.secondary)
            message
                .font(.callout)
            action()
                .font(.callout.weight(.medium))
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .padding(.top, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("capture.notice")
    }

    private var settingsButton: some View { Self.settingsLink }

    /// The route to the switch the user flipped. iOS opens the app's own
    /// Settings page; the Mac opens the Microphone privacy pane — where a
    /// changed permission does not relaunch the app, so Retry follows.
    /// Static, so the chromatic screen's own denied readout shares it.
    @ViewBuilder static var settingsLink: some View {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            Link(destination: url) { Text("Open Settings", bundle: .module) }
        }
        #elseif os(macOS)
        if let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        {
            Link(destination: url) { Text("Open Settings", bundle: .module) }
        }
        #endif
    }
}
