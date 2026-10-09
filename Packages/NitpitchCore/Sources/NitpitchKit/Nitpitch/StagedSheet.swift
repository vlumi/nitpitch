import NitpitchData
import SwiftUI

extension View {
    /// Opens the sheet a staged screenshot asked for (`-demo-stage
    /// present=presets`), a beat after launch.
    ///
    /// The delay is the demo route's, for the demo route's reason:
    /// presenting any earlier reliably leaves the macOS window unmade. Out
    /// of the screen's own file because this is the demo's business, not
    /// the chromatic tuner's — and a no-op in every build nobody passed
    /// `-demo-stage` to.
    func presentsStagedSheet(
        presets: Binding<Bool>, settings: Binding<Bool>
    ) -> some View {
        task {
            guard let present = DemoStage.current?.present else { return }
            try? await Task.sleep(nanoseconds: 400_000_000)
            switch present {
            case .presets: presets.wrappedValue = true
            case .settings: settings.wrappedValue = true
            }
        }
    }
}
