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
