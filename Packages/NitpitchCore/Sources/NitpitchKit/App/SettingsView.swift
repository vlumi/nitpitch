import NitpitchCore
import SwiftUI

/// Preferences you set once and forget: appearance, note notation, and the
/// string order in the strips view.
///
/// Deliberately *not* the instrument or the reference pitch — those change
/// between sessions and belong on the tuner screen where they're visible
/// without opening anything.
public struct SettingsView: View {
    @ObservedObject private var settings: Settings
    @ObservedObject private var sync: SyncEngine
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingAbout = false

    public init(settings: Settings, sync: SyncEngine) {
        self.settings = settings
        self.sync = sync
    }

    public var body: some View {
        #if os(macOS)
        // A preferences window is already a window: no navigation stack, no
        // title bar of its own, no Done button. Plain form style gives the
        // right-aligned labels Mac preferences use, rather than the iOS
        // grouped cards.
        macForm
            .frame(width: 420)
            .fixedSize()
        #else
        sheetForm
        #endif
    }

    #if os(macOS)
    private var macForm: some View {
        Form {
            Picker(selection: $settings.appearance) {
                ForEach(AppearancePreference.allCases) { option in
                    Text(LocalizedStringKey(option.name), bundle: .module).tag(option)
                }
            } label: {
                Text("Appearance", bundle: .module)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("settings.appearance")

            Picker(selection: $settings.naming) {
                ForEach(NoteNaming.allCases, id: \.self) { naming in
                    Text(verbatim: naming.label).tag(naming)
                }
            } label: {
                Text("Notation", bundle: .module)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("settings.naming")

            // Off by default: low at the bottom, as tabs are written.
            Toggle(isOn: $settings.stripsLowOnTop) {
                Text("Low string on top", bundle: .module)
            }
            .accessibilityIdentifier("settings.stripsLowOnTop")

            syncToggle
            syncFooter
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }
    #endif

    /// iCloud syncing — opt-in, and phrased as what it does rather than
    /// what it is. It lives HERE (it used to sit at the foot of the
    /// instrument list): an account-scoped mode is looked for in Settings,
    /// and the footer states the promise the app makes when it's off,
    /// since that promise is the reason the toggle exists at all.
    private var syncToggle: some View {
        Toggle(isOn: Binding(get: { sync.isEnabled }, set: { sync.setEnabled($0) })) {
            Text("Sync with iCloud", bundle: .module)
        }
        // Disabled, not hidden, when there's no iCloud account: KVS would
        // accept every write locally and move none of them, so an enabled
        // switch would claim a sync that isn't happening. The footer says
        // what would make it work.
        .disabled(!sync.isCloudAvailable)
        .accessibilityIdentifier("settings.sync")
    }

    @ViewBuilder private var syncFooter: some View {
        if !sync.isCloudAvailable {
            Text("Sign in to iCloud on this device to sync.", bundle: .module)
        } else if sync.isEnabled {
            Text(
                "Instruments, presets and favorites stay the same on every device.",
                bundle: .module)
        } else {
            Text("Nothing leaves this device.", bundle: .module)
        }
    }

    private var sheetForm: some View {
        NavigationStack {
            Form {
                // Segmented rather than menus: three appearances and four
                // notations all fit inline, so hiding them behind a tap buys
                // nothing and costs the ability to see what's on offer.
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Appearance", bundle: .module)
                        Picker(selection: $settings.appearance) {
                            ForEach(AppearancePreference.allCases) { option in
                                Text(LocalizedStringKey(option.name), bundle: .module).tag(option)
                            }
                        } label: {
                            Text("Appearance", bundle: .module)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .accessibilityIdentifier("settings.appearance")
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notation", bundle: .module)
                        Picker(selection: $settings.naming) {
                            ForEach(NoteNaming.allCases, id: \.self) { naming in
                                Text(verbatim: naming.label).tag(naming)
                            }
                        } label: {
                            Text("Notation", bundle: .module)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .accessibilityIdentifier("settings.naming")
                    }
                } footer: {
                    Text("How note names are spelled.", bundle: .module)
                }

                Section {
                    Toggle(isOn: $settings.stripsLowOnTop) {
                        Text("Low string on top", bundle: .module)
                    }
                    .accessibilityIdentifier("settings.stripsLowOnTop")
                } footer: {
                    Text(
                        "In the dial grid and the strips. Off: lowest at the bottom, as tabs are written.",
                        bundle: .module)
                }

                Section {
                    syncToggle
                } footer: {
                    syncFooter
                }

                Section {
                    Button {
                        isShowingAbout = true
                    } label: {
                        HStack {
                            Text("About Nitpitch", bundle: .module)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .accessibilityIdentifier("settings.about")
                }
            }
            .formStyle(.grouped)
            .navigationTitle(Text("Settings", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done", bundle: .module)
                    }
                }
            }
            .navigationDestination(isPresented: $isShowingAbout) {
                AboutView()
            }
        }
        .frame(minWidth: 380, minHeight: 320)
    }
}

/// The app's own icon, loaded from the bundle at runtime.
///
/// `AppIcon.appiconset` is reserved by the OS and can't be referenced as a
/// named image, so this reaches for the loaded icon instead — the alternative
/// is committing a second copy of the artwork as a plain image set, which
/// would then quietly drift from the real one.
struct AppIconImage: View {
    let size: CGFloat

    var body: some View {
        if let image = platformIcon {
            image
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        } else {
            // Only reachable if the bundle has no icon — a broken build,
            // but not worth crashing an About screen over.
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(.secondary.opacity(0.2))
                .frame(width: size, height: size)
        }
    }

    private var platformIcon: Image? {
        #if canImport(AppKit)
        return NSApp?.applicationIconImage.map(Image.init(nsImage:))
        #elseif canImport(UIKit)
        // The primary icon's largest rendition, dug out of the Info.plist.
        guard
            let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
            let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
            let files = primary["CFBundleIconFiles"] as? [String],
            let name = files.last,
            let image = UIImage(named: name)
        else { return nil }
        return Image(uiImage: image)
        #else
        return nil
        #endif
    }
}

/// What the app is, who made it, and where to check the claims.
///
/// A centred stack rather than a `Form`, following donpa's shape: the icon and
/// name are the subject, not rows in a list.
public struct AboutView: View {
    public init() {}

    public var body: some View {
        // Scrollable on iOS, where a small screen with large Dynamic Type can
        // overflow; a plain stack on macOS, so the window sizes to the content
        // instead of the ScrollView claiming whatever width it's offered.
        #if os(macOS)
        content
            .frame(width: 320)
            .fixedSize()
        #else
        ScrollView { content }
        #endif
    }

    private var content: some View {
        VStack(spacing: 16) {
            AppIconImage(size: 88)
                .shadow(color: .black.opacity(0.25), radius: 8, y: 3)

            VStack(spacing: 4) {
                Text(verbatim: "Nitpitch")
                    .font(.title2.bold())
                // The pun, for anyone who hasn't got it yet.
                Text("Nitpicking about pitch.", bundle: .module)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            versionPill

            if let sha = commitSHA {
                Text(verbatim: sha)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }

            Divider().frame(maxWidth: 220)

            Text(
                "Audio is analyzed on your device and never recorded or sent anywhere.",
                bundle: .module
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 280)

            VStack(spacing: 6) {
                Text(verbatim: "© 2026 Ville Misaki").font(.footnote)
                Link(destination: URL(string: "https://nitpitch.app")!) {
                    Label {
                        Text(verbatim: "nitpitch.app")
                    } icon: {
                        Image(systemName: "globe")
                    }
                    .font(.footnote)
                }
                Link(destination: URL(string: "https://github.com/vlumi/nitpitch")!) {
                    Label {
                        Text(verbatim: "github.com/vlumi/nitpitch")
                    } icon: {
                        Image(systemName: "link")
                    }
                    .font(.footnote)
                }
                Text("MIT licensed.", bundle: .module)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 20)
        .navigationTitle(Text("About", bundle: .module))
    }

    /// Version as a tinted pill rather than plain text — it's the one fact
    /// people come to an About screen to read.
    private var versionPill: some View {
        Text("Version \(versionLine)", bundle: .module)
            .font(.footnote.monospaced().weight(.semibold))
            .foregroundStyle(.tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
            .overlay(Capsule().stroke(Color.accentColor.opacity(0.3), lineWidth: 1))
    }

    /// Version and build from the bundle, so it can't drift from what shipped.
    private var versionLine: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    /// The build's git commit, stamped into the plist by
    /// `Scripts/embed-commit-sha.sh`. Absent only if that script didn't run.
    private var commitSHA: String? {
        Bundle.main.infoDictionary?["GitCommitSHA"] as? String
    }
}
