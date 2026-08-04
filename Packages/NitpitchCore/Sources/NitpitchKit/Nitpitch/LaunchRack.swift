import NitpitchCore
import SwiftUI

/// The small kind tag — "which instrument is which" at a glance, without
/// encoding the kind into the user's name for it. Shared by the chooser's
/// rows and the launch rack.
struct KindTag: View {
    let template: Instrument?

    var body: some View {
        if let tag = template?.kindTag, !tag.isEmpty {
            Text(LocalizedStringKey(tag), bundle: .module)
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary.opacity(0.4), lineWidth: 1)
                )
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }
}

/// The launch screen's rack: your pinned instruments as full rows — kind
/// tag, name, current tuning, lock — with the whole list one row further.
///
/// This is what replaced the truncating chips: the fast path to the
/// instruments you always tune looks like the main door it is, and each
/// row says what state it opens into *before* the tap. Capped so the dial
/// stays the screen's headline; the chooser is never more than one row
/// away.
struct LaunchRack: View {
    struct Entry: Identifiable {
        let id: String
        let name: Text
        let template: Instrument?
        let tuningName: String?
        let isLocked: Bool
    }

    let entries: [Entry]
    let onChoose: (String) -> Void
    let onOpenChooser: () -> Void

    /// Rows shown before deferring to the chooser.
    static let rowCap = 4
    /// Design metrics the chromatic canvas math builds on.
    static let rowHeight: CGFloat = 40
    static let rowSpacing: CGFloat = 6

    /// The rack's exact design height for `count` pinned instruments (plus
    /// the All instruments row) — the canvas grows by precisely this much,
    /// so the fill stays honest instead of guessing.
    static func height(forPinned count: Int) -> CGFloat {
        let rows = CGFloat(min(count, rowCap) + 1)
        return rows * rowHeight + (rows - 1) * rowSpacing
    }

    var body: some View {
        VStack(spacing: Self.rowSpacing) {
            ForEach(entries.prefix(Self.rowCap)) { entry in
                row(for: entry)
            }
            allInstrumentsRow
        }
    }

    private func row(for entry: Entry) -> some View {
        Button {
            onChoose(entry.id)
        } label: {
            HStack(spacing: 10) {
                KindTag(template: entry.template)
                entry.name
                    .font(.callout.weight(.medium))
                if let tuningName = entry.tuningName {
                    Text(LocalizedStringKey(tuningName), bundle: .module)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                Spacer(minLength: 4)
                if entry.isLocked {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: Self.rowHeight)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("favorite.\(entry.id)")
    }

    private var allInstrumentsRow: some View {
        Button(action: onOpenChooser) {
            HStack(spacing: 10) {
                Image(systemName: "guitars")
                    .font(.footnote)
                Text("All instruments…", bundle: .module)
                    .font(.callout.weight(.medium))
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .frame(height: Self.rowHeight)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tuner.instrument")
    }
}
