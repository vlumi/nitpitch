import SwiftUI

/// A row of chips that wraps instead of squeezing.
///
/// `HStack` distributes a shortfall by compressing its children, which turns
/// "Half-step down" into "H al" — a shortcut nobody can read is not a
/// shortcut. This lays each chip out at its natural width and starts a new
/// line when the next one won't fit, which is what a row of tags should do
/// in a column whose width the user controls.
struct ChipFlow: Layout {
    var spacing: CGFloat = 6
    /// Chips are uniform height by design (they're capsules of one text
    /// line), so rows are a constant rather than a per-row measurement.
    var rowHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = layout(subviews: subviews, in: width)
        let height =
            rows.isEmpty
            ? 0 : CGFloat(rows.count) * rowHeight + CGFloat(rows.count - 1) * spacing
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        let rows = layout(subviews: subviews, in: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: size.width, height: rowHeight))
                x += size.width + spacing
            }
            y += rowHeight + spacing
        }
    }

    /// The lines, as index ranges plus the width each came to.
    private func layout(subviews: Subviews, in width: CGFloat) -> [(indices: [Int], width: CGFloat)]
    {
        var rows: [(indices: [Int], width: CGFloat)] = []
        var current: [Int] = []
        var used: CGFloat = 0
        for index in subviews.indices {
            let chip = subviews[index].sizeThatFits(.unspecified).width
            // A chip wider than the whole line still gets its own line —
            // wrapping can't help it, and dropping it would hide a shortcut.
            if !current.isEmpty, used + spacing + chip > width {
                rows.append((current, used))
                current = [index]
                used = chip
            } else {
                used += current.isEmpty ? chip : spacing + chip
                current.append(index)
            }
        }
        if !current.isEmpty { rows.append((current, used)) }
        return rows
    }
}
