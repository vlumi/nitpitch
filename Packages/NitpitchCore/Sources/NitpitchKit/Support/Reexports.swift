// NitpitchKit is the app-facing surface on iOS/macOS: importing it must keep
// meaning "the stores too", exactly as before NitpitchData was split out for
// the watch — the split is an implementation fact of the package, not
// something every view and app shell should have to spell.
@_exported import NitpitchData

/// SwiftUI also exports a `Settings` (the macOS settings Scene). While the
/// app's Settings lived in this module it won bare-name lookup as the local
/// type; this alias keeps that true now that it lives in NitpitchData, so a
/// hundred call sites don't grow qualifiers.
public typealias Settings = NitpitchData.Settings
