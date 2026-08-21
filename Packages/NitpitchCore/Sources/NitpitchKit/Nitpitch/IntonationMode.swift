import Foundation
import SwiftUI

/// Which job the instrument screens are doing: TUNING (the default) or the
/// INTONATION check. One mode for the grid and the string view alike — the
/// two screens are one workflow, and they must never disagree about what a
/// 12th-fret note means (field-found: the grid's buried toggle and the
/// string view's always-on panel each answered differently, and the octave
/// kept being read as ambiguity instead of intent).
///
/// Deliberately a visible choice, not an ambient inference: checking
/// intonation is a different activity from tuning — the player starts one
/// or the other. Screen state, not a setting: a measuring session belongs
/// to the visit that ran it, so arriving at a different instrument lands
/// back in tuning.
@MainActor
final class IntonationMode: ObservableObject {
    @Published var isChecking = false

    private var instrumentID: String?

    /// Called by each screen as it appears: a different instrument is a
    /// fresh visit, and a fresh visit starts in tuning.
    func adopt(instrumentID id: String) {
        guard instrumentID != id else { return }
        instrumentID = id
        if isChecking { isChecking = false }
    }
}

/// The mode's visible handle, worn in the footer row of both instrument
/// screens beside the reference and temperament — the same kind of fact,
/// where you look while playing. Tinted while the check is running.
struct IntonationChip: View {
    @ObservedObject var mode: IntonationMode
    let identifier: String

    var body: some View {
        Button {
            mode.isChecking.toggle()
        } label: {
            Text("Intonation", bundle: .module)
                .font(.callout.weight(.medium))
                .foregroundStyle(
                    mode.isChecking ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary)
                )
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .overlay(
                    Capsule().strokeBorder(
                        mode.isChecking
                            ? AnyShapeStyle(.tint)
                            : AnyShapeStyle(Color.secondary.opacity(0.4)),
                        lineWidth: 1)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(Text("Check intonation", bundle: .module))
        .accessibilityValue(
            mode.isChecking ? Text("On", bundle: .module) : Text("Off", bundle: .module))
    }
}

/// The instrument screens' shared bottom bar. Fixed chrome that still
/// GROWS a little with a big window: the string view's canvas-scaled row
/// dwarfed the grid's fixed one, and a fixed row reads tiny beside a big
/// dial (field-found, both directions) — so both screens wear this, and
/// it scales together, capped where chrome starts competing with content.
struct TunerFooter<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @State private var scale: CGFloat = 1

    var body: some View {
        content()
            .scaleEffect(scale)
            .frame(maxWidth: .infinity)
            .frame(height: 44 * scale)
            .background(.thinMaterial)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
                scale = min(1.5, max(1, width / 560))
            }
    }
}
