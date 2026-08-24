import SwiftUI

// The string switcher — out of the type body for the same reason the grid's
// presentation is: SwiftLint counts the file's lines, and the view proper is
// the part worth keeping in one eyeful.
extension StringView {
    /// ◀ dots ▶ — where you are among the strings, and the way sideways.
    /// The dots are also a scrubber: tap one to jump straight to that
    /// string, or drag across the row to flick through them.
    var stringSwitcher: some View {
        HStack(spacing: 24) {
            arrow(systemName: "chevron.left", id: "string.prev", by: -1)
            dots
            arrow(systemName: "chevron.right", id: "string.next", by: 1)
        }
    }

    /// Dot geometry the scrub mapping depends on: 7pt dots on a 14pt pitch,
    /// inside an 8pt horizontal inset of finger-sized hit surface.
    static var dotPitch: CGFloat { 14 }
    static var dotInset: CGFloat { 8 }

    private var dots: some View {
        HStack(spacing: Self.dotPitch - 7) {
            ForEach(instrument.notes.indices, id: \.self) { position in
                Circle()
                    .fill(
                        position == index
                            ? Color.primary.opacity(0.7) : Color.secondary.opacity(0.25)
                    )
                    .frame(width: 7, height: 7)
            }
        }
        // Hidden as decoration — the arrows and swipe carry the accessible
        // paths — but interactive as a scrubber, with a finger-sized
        // surface padded out around the 7pt dots.
        .accessibilityHidden(true)
        .padding(.vertical, 12)
        .padding(.horizontal, Self.dotInset)
        .contentShape(Rectangle())
        // minimumDistance 0: touching down on a dot jumps immediately, and
        // the same gesture keeps following the finger as it scrubs. As a
        // child gesture it wins over the page-swipe on the pane above.
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    scrub(toX: value.location.x)
                }
        )
    }

    /// Map a position on the dots row to a string, and go there. The first
    /// dot's centre sits at inset + 3.5; each further one a pitch along.
    private func scrub(toX x: CGFloat) {
        let position = Int(((x - Self.dotInset - 3.5) / Self.dotPitch).rounded())
        let clamped = min(max(position, 0), instrument.notes.count - 1)
        guard clamped != index else { return }
        animatedStep(clamped - index)
    }

    /// A tap target, deliberately not a `Button`: a Button holds the touch
    /// until release and never fails on movement, so a swipe that began on
    /// one starved the page-pan — no tracking, sometimes no animation at
    /// all. A tap gesture fails as soon as the finger moves, and the touch
    /// joins the swipe with its full translation, without stepping.
    private func arrow(systemName: String, id: String, by delta: Int) -> some View {
        let enabled = canStep(delta)
        return Image(systemName: systemName)
            .font(.title3.weight(.semibold))
            .frame(width: 56, height: 40)
            .contentShape(Rectangle())
            .foregroundStyle(.secondary)
            .opacity(enabled ? 1 : 0.35)
            .onTapGesture { animatedStep(delta) }
            .disabled(!enabled)
            .accessibilityIdentifier(id)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(
                delta < 0
                    ? Text("Previous string", bundle: .module)
                    : Text("Next string", bundle: .module))
    }
}
