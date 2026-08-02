import NitpitchCore
import SwiftUI

/// The way from the chromatic tuner into an instrument.
///
/// Large and below the dial rather than a menu in the corner: choosing an
/// instrument decides which screen you're on, so it wants the weight of a
/// destination rather than the weight of a setting. It only *requests* the
/// navigation — the chooser is a pushed screen owned by `RootView`, so back
/// from a grid lands on the list you chose from.
struct InstrumentButton: View {
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 8) {
                Image(systemName: "guitars")
                    .font(.body)
                Text("Tune an instrument", bundle: .module)
                    .font(.body.weight(.medium))
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.secondary.opacity(0.14))
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tuner.instrument")
    }
}

/// Pinned instruments as one-tap chips on the launch screen.
///
/// This is what retires "two taps to reach the violin": a favourite is a
/// repeated setup converted into one tap. Pinning lives in the chooser (the
/// star on each row); the row hides itself when nothing is pinned.
struct FavoritesRow: View {
    let favorites: [Instrument]
    let onChoose: (Instrument) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(favorites) { instrument in
                    Button {
                        onChoose(instrument)
                    } label: {
                        Text(LocalizedStringKey(instrument.name), bundle: .module)
                            .font(.callout.weight(.medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("favorite.\(instrument.id)")
                }
            }
            // Breathing room so the capsules' edges aren't clipped by the
            // scroll view at rest.
            .padding(.horizontal, 2)
        }
    }
}

/// The instrument list, grouped by family, pushed onto the stack.
///
/// A screen rather than a menu: it's a step into the instrument, and it's
/// where instrument management (rename, add another — ROADMAP § 1) will live.
/// Each row carries a star for pinning to the launch screen.
struct InstrumentChooser: View {
    @ObservedObject var settings: Settings
    let onChoose: (Instrument) -> Void

    var body: some View {
        List {
            // Chromatic is absent by construction — see `Instrument.choosable`.
            ForEach(Instrument.choosable, id: \.family) { group in
                Section {
                    ForEach(group.instruments) { instrument in
                        row(for: instrument)
                    }
                } header: {
                    Text(LocalizedStringKey(group.family.name), bundle: .module)
                }
            }
        }
        .navigationTitle(Text("Instrument", bundle: .module))
        .frame(minWidth: 320, minHeight: 380)
    }

    private func row(for instrument: Instrument) -> some View {
        HStack(spacing: 12) {
            Button {
                onChoose(instrument)
            } label: {
                HStack {
                    Text(LocalizedStringKey(instrument.name), bundle: .module)
                        .foregroundStyle(.primary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("chooser.\(instrument.id)")

            star(for: instrument)

            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
    }

    /// Pin/unpin. `.borderless` so the star and the row stay separately
    /// tappable — a plain List row would swallow both into one target.
    private func star(for instrument: Instrument) -> some View {
        let isPinned = settings.favorites.contains(instrument.id)
        return Button {
            settings.toggleFavorite(instrument.id)
        } label: {
            Image(systemName: isPinned ? "star.fill" : "star")
                .foregroundStyle(isPinned ? Color.yellow : Color.secondary.opacity(0.5))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier("chooser.pin.\(instrument.id)")
        .accessibilityLabel(
            isPinned
                ? Text("Remove from favorites", bundle: .module)
                : Text("Add to favorites", bundle: .module))
    }
}
