import NitpitchCore
import SwiftUI

/// The wrist's two knobs, stored locally until sync brings the real
/// settings over: the reference pitch (the crown's second natural job —
/// twist through 390…466 a hertz at a time) and the temperament, defaulting
/// to Auto (pure fifths on bowed instruments, the phone's rule).
///
/// Deliberately NOT here: instrument locks. A lock belongs to one of YOUR
/// instruments, and those reach the wrist with iCloud sync — the catalog
/// instruments this version tunes have nothing to lock yet.
struct WatchSettingsView: View {
    @AppStorage(WatchTuning.referenceKey) private var referenceHz: Double = 440
    @AppStorage(WatchTuning.temperamentKey) private var temperamentMode: String =
        WatchTuning.TemperamentMode.auto.rawValue
    /// Temperament only matters where there are strings to temper —
    /// chromatic hides the row.
    let showsTemperament: Bool

    var body: some View {
        List {
            Section {
                HStack {
                    Button("−") { referenceHz = ReferencePitch(hz: referenceHz).lowered().hz }
                        .disabled(!ReferencePitch(hz: referenceHz).canLower)
                    Spacer()
                    Text(verbatim: "A=\(Int(referenceHz))")
                        .font(.system(.title3, design: .rounded))
                        .monospacedDigit()
                    Spacer()
                    Button("+") { referenceHz = ReferencePitch(hz: referenceHz).raised().hz }
                        .disabled(!ReferencePitch(hz: referenceHz).canRaise)
                }
                .buttonStyle(.bordered)
                .focusable()
                .digitalCrownRotation(
                    $referenceHz,
                    from: ReferencePitch.range.lowerBound,
                    through: ReferencePitch.range.upperBound,
                    by: ReferencePitch.step,
                    sensitivity: .medium, isContinuous: false,
                    isHapticFeedbackEnabled: true)
            } header: {
                Text(verbatim: "Reference")
            } footer: {
                Text(verbatim: "440 by default; 442–443 in many European orchestras.")
            }
            if showsTemperament {
                Section {
                    Picker(
                        selection: $temperamentMode,
                        label: Text(verbatim: "Temperament")
                    ) {
                        ForEach(WatchTuning.TemperamentMode.allCases, id: \.rawValue) { mode in
                            Text(verbatim: mode.label).tag(mode.rawValue)
                        }
                    }
                } footer: {
                    Text(verbatim: "Auto tunes bowed instruments in pure fifths.")
                }
            }
        }
        .navigationTitle("Tuning")
    }
}

/// The stored-knob vocabulary, shared by the screens that read it.
enum WatchTuning {
    static let referenceKey = "watch.referenceHz"
    static let temperamentKey = "watch.temperament"

    enum TemperamentMode: String, CaseIterable {
        case auto
        case equal
        case pure

        var label: String {
            switch self {
            case .auto: return "Auto"
            case .equal: return "Equal"
            case .pure: return "Pure fifths"
            }
        }

        /// The rule the phone applies, made explicit here.
        func temperament(for family: InstrumentFamily) -> Temperament {
            switch self {
            case .auto: return family == .bowed ? .pure : .equal
            case .equal: return .equal
            case .pure: return .pure
            }
        }
    }

    static func storedReference() -> ReferencePitch {
        let stored = UserDefaults.standard.double(forKey: referenceKey)
        guard ReferencePitch.range.contains(stored) else { return .standard }
        return ReferencePitch(hz: stored)
    }

    static func storedTemperament(for family: InstrumentFamily) -> Temperament {
        let raw = UserDefaults.standard.string(forKey: temperamentKey) ?? ""
        let mode = TemperamentMode(rawValue: raw) ?? .auto
        return mode.temperament(for: family)
    }
}
