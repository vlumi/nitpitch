import SwiftUI

extension View {
    /// Escape closes a sheet on the Mac — the platform convention, which a
    /// sheet whose only button is Done does not get for free: `.cancelAction`
    /// lives on a Cancel button, and these sheets have none to give it to.
    /// A no-op elsewhere; iOS sheets swipe down.
    func dismissesOnEscape(_ dismiss: DismissAction) -> some View {
        #if os(macOS)
        return onExitCommand { dismiss() }
        #else
        return self
        #endif
    }
}
