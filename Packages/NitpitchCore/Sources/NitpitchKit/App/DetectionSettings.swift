import Combine
import Foundation
import NitpitchCore

/// The live detector tuning, shared by every dial on screen.
///
/// Separate from `Settings` because it isn't one: `Settings` holds preferences
/// a user chose and expects to find again, this holds a diagnostic that resets
/// to the shipped defaults on every launch. Persisting it would mean a session
/// of experimenting could quietly leave the app detuned forever, with no
/// indication why — the worst possible bug to inherit from a debug screen.
///
/// It exists at all because the right thresholds can't be derived. They depend
/// on the instrument, the room, and the microphone, and the only way to find
/// them is to sit down with an instrument and turn the knobs.
@MainActor
public final class DetectionSettings: ObservableObject {
    @Published public var tuning: DetectionTuning = .default

    /// True once anything has been moved — the tuner screen shows a marker so
    /// a surprising reading is never mistaken for the shipped behaviour.
    public var isModified: Bool { tuning != .default }

    public init() {}

    public func reset() {
        tuning = .default
    }
}
