import SwiftUI

#if canImport(AppKit)
import AppKit
#endif

/// Whether the app follows the system appearance or forces one.
///
/// Ported from donpa, including the three traps its comments record — each was
/// found the hard way, and none of them fail loudly.
public enum AppearancePreference: String, CaseIterable, Identifiable, Codable, Sendable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    /// Untranslated label; the UI localizes via the string catalog.
    public var name: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// What to force on the hierarchy, or nil to follow the system.
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// The concrete scheme currently in effect.
    ///
    /// **Trap 1:** on macOS the ambient `@Environment(\.colorScheme)` is
    /// unreliable while a sibling `.preferredColorScheme` is active — it can
    /// report the forced value rather than the system's. Resolving `.system`
    /// therefore reads AppKit directly. On iOS the ambient value is
    /// authoritative once the forced scheme clears.
    public func resolvedScheme(systemFallback: ColorScheme) -> ColorScheme {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system:
            #if canImport(AppKit)
            let match = NSApp?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
            return match == .darkAqua ? .dark : .light
            #else
            return systemFallback
            #endif
        }
    }
}

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
