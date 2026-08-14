import NitpitchData
import SwiftUI

extension View {
    /// Presents a sheet pinned to the app's chosen appearance.
    ///
    /// **Trap 2:** a sheet presents in a fresh environment that does *not*
    /// inherit the presenter's `.preferredColorScheme`, so without this it
    /// follows the system and ignores a Light/Dark override.
    ///
    /// **Trap 3:** the scheme passed to a sheet must always be *concrete*.
    /// `.preferredColorScheme(nil)` on a live sheet goes inert without
    /// releasing the previously-forced value, so switching back to `.system`
    /// would leave the sheet stuck on the last explicit choice. That's why
    /// this takes a resolved `ColorScheme` rather than the optional.
    func appearanceSheet<Content: View>(
        isPresented: Binding<Bool>,
        scheme: ColorScheme,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        sheet(isPresented: isPresented) {
            content().preferredColorScheme(scheme)
        }
    }
}
