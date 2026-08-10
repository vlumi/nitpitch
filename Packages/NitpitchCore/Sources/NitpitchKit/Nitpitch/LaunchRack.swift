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
        /// Setup shortcuts riding under this instrument's row — resolved
        /// pins; a pin whose preset was deleted simply isn't here.
        var pins: [PinEntry] = []
    }

    struct PinEntry: Identifiable {
        let presetID: String
        let name: String
        /// Catalog tuning names localize; a user's preset name is verbatim.
        var localized: Bool = false
        var id: String { presetID }
    }

    let entries: [Entry]
    /// Which rows show their chips — the accordion, persisted in Settings.
    let expanded: Set<String>
    let onChoose: (String) -> Void
    /// A pin's tap: open the instrument INTO the preset (or, locked, just
    /// open it — the navigation half of a pin is not a change).
    let onChoosePin: (String, String) -> Void
    let onToggleExpand: (String) -> Void
    let onOpenChooser: () -> Void
    /// Opens the whole collection. Nil when there is nothing saved yet —
    /// the row appears only once you own a preset, since a door onto an
    /// empty collection teaches nothing and costs the rack a row.
    let onOpenPresets: (() -> Void)?

    /// Rows shown before deferring to the chooser.
    static let rowCap = 4
    /// Design metrics the chromatic canvas math builds on. The row is a
    /// finger target first: 40 sat under Apple's 44pt floor and the field
    /// called it hard to hit.
    static let rowHeight: CGFloat = 48
    static let rowSpacing: CGFloat = 6

    /// One chips line's design height. Proper targets now: the chips only
    /// appear behind the accordion, so their size no longer costs every
    /// row its clutter budget.
    static let chipRowHeight: CGFloat = 44

    /// The rack's exact design height — instrument rows, the All
    /// instruments row, and a chips line per EXPANDED pinned-into
    /// instrument — so the canvas grows by precisely this much and the
    /// fill stays honest.
    static func height(
        for entries: [Entry], expanded: Set<String>, hasPresets: Bool = false
    ) -> CGFloat {
        let shown = entries.prefix(rowCap)
        // Instrument rows, the All instruments row, and — once anything is
        // saved — the All presets row. Counted exactly: overstating the
        // rack is what once left a third of the window empty below the
        // tuner.
        let rows = CGFloat(shown.count + 1 + (hasPresets ? 1 : 0))
        let chipRows = CGFloat(
            shown.filter { !$0.pins.isEmpty && expanded.contains($0.id) }.count)
        return rows * rowHeight + (rows - 1) * rowSpacing + chipRows * chipRowHeight
    }

    var body: some View {
        VStack(spacing: Self.rowSpacing) {
            ForEach(entries.prefix(Self.rowCap)) { entry in
                row(for: entry)
                if !entry.pins.isEmpty, expanded.contains(entry.id) {
                    pinChips(for: entry)
                }
            }
            allInstrumentsRow
            if let onOpenPresets {
                allPresetsRow(action: onOpenPresets)
            }
        }
    }

    /// The instrument's setup shortcuts, indented under its row — the
    /// placement is what teaches the binding: pins live with their
    /// instrument, never floating free. On a locked instrument they dim
    /// and wear the lock; tapping still navigates, but loads nothing —
    /// only the load half of a pin is a change.
    private func pinChips(for entry: Entry) -> some View {
        HStack(spacing: 6) {
            ForEach(entry.pins) { pin in
                Button {
                    onChoosePin(entry.id, pin.presetID)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "pin.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Group {
                            if pin.localized {
                                Text(LocalizedStringKey(pin.name), bundle: .module)
                            } else {
                                Text(verbatim: pin.name)
                            }
                        }
                        .font(.callout.weight(.medium))
                        if entry.isLocked {
                            Image(systemName: "lock.fill")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: Self.chipRowHeight - 6)
                    .background(Capsule().fill(Color.secondary.opacity(0.1)))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .opacity(entry.isLocked ? 0.45 : 1)
                .accessibilityIdentifier("pin.\(entry.id).\(pin.name)")
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 26)
        .frame(height: Self.chipRowHeight - 6)
    }

    /// Two buttons, one row: the row itself opens the instrument, and a
    /// separated trailing chevron discloses its pin chips — the split the
    /// player asked for, so the row never serves two purposes at one tap.
    /// No pins, no chevron.
    private func row(for entry: Entry) -> some View {
        HStack(spacing: 0) {
            Button {
                onChoose(entry.id)
            } label: {
                HStack(spacing: 10) {
                    KindTag(template: entry.template)
                    entry.name
                        .font(.body.weight(.medium))
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
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("favorite.\(entry.id)")

            if !entry.pins.isEmpty {
                Rectangle()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(width: 1, height: Self.rowHeight - 20)
                expandToggle(for: entry)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.accentColor.opacity(0.12))
        )
    }

    private func expandToggle(for entry: Entry) -> some View {
        Button {
            onToggleExpand(entry.id)
        } label: {
            Image(systemName: "chevron.down")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(expanded.contains(entry.id) ? 0 : -90))
                .frame(width: 44, height: Self.rowHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("rack.expand.\(entry.id)")
        .accessibilityLabel(Text("Presets", bundle: .module))
        .accessibilityValue(
            expanded.contains(entry.id)
                ? Text("On", bundle: .module) : Text("Off", bundle: .module))
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

    /// The collection, all of it. Deliberately the same shape as the row
    /// above — same height, same chevron, same ellipsis — so the two read
    /// as a pair of doors rather than a row and an oddity.
    private func allPresetsRow(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "slider.horizontal.3")
                    .font(.footnote)
                Text("All presets…", bundle: .module)
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
        .accessibilityIdentifier("tuner.presets")
    }
}
