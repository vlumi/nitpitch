import Foundation

/// A shared setup, as it travels: the payload and nothing else.
///
/// **Deliberately not a preset.** No id, no device, no timestamp — a link is
/// a *value*, which is what a preset already is ("a stamp, not a place").
/// Carrying the sender's id would make the link the identity rather than the
/// name, so a friend's re-share could silently overwrite edits the receiver
/// made to their own copy, and two people deriving from one original would
/// fight over a single entry. It would also leak a stable id into a URL —
/// and ids are what iCloud sync merges on, so an imported one could collide
/// with a preset the receiver already owns on another device.
///
/// The consequence is the point: what arrives is a proposal, and the
/// receiver decides what it becomes (see `PresetImport`).
public struct PresetLink: Equatable, Sendable {
    /// What the sender called it — a suggestion, which the receiver may
    /// keep, replace under, or rename.
    public let name: String
    /// Which template this fits ("guitar"). An import that fits nothing the
    /// receiver owns is refused rather than guessed at.
    public let templateID: String
    /// Open strings, low to high — the payload a preset always carries.
    public let strings: [Int]
    /// Carried only when the sender's preset carried it, so the link
    /// preserves the payload rule rather than inventing fields.
    public let referenceHz: Double?
    public let temperament: Temperament?

    public init(
        name: String, templateID: String, strings: [Int],
        referenceHz: Double? = nil, temperament: Temperament? = nil
    ) {
        self.name = name
        self.templateID = templateID
        self.strings = strings
        self.referenceHz = referenceHz
        self.temperament = temperament
    }
}

/// Turns a `PresetLink` into a URL and back.
///
/// The payload rides in the URL's **fragment**, not its query: fragments are
/// never sent to a server, so a link pasted into a browser reveals nothing
/// to whoever hosts the domain — which is what lets nitpitch.app serve the
/// long tail of tunings as ordinary static links with no backend.
///
/// The encoding is compact by hand rather than JSON+Base64: a QR code's
/// density is set by its payload length, and the fields are few and small.
/// `v1` leads so a later format can be told apart rather than guessed at.
public enum PresetLinkCodec {
    /// The custom scheme the app registers — accepted forever (old QR codes
    /// don't expire), and emitted by nitpitch.app's landing page as its
    /// open-in-app bridge.
    public static let scheme = "nitpitch"
    public static let host = "preset"

    /// The universal-link home: `https://nitpitch.app/t#…`. This is what the
    /// app EMITS — an https link is tappable in every messenger (custom
    /// schemes often don't even linkify), opens the app directly when it's
    /// installed, and falls back to a page that shows the payload when it
    /// isn't. Backed by the apple-app-site-association file on nitpitch.app;
    /// the payload stays in the fragment, which browsers never send, so the
    /// site remains a static host that learns nothing.
    public static let universalHost = "nitpitch.app"
    public static let universalPath = "/t"

    /// The current payload version. A decoder that meets a version it
    /// doesn't know refuses rather than misreading — a wrong tuning applied
    /// silently is worse than a link that doesn't open.
    static let version = "v1"

    /// `https://nitpitch.app/t#v1|guitar|38,45,50,55,59,64|442|pure|Drop D`
    ///
    /// Name goes LAST and unescaped-of-separators: it's the only field that
    /// can contain anything, so putting it at the end means a name with a
    /// `|` in it can't shift the fields that follow.
    public static func url(for link: PresetLink) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = universalHost
        components.path = universalPath
        components.fragment = fragment(for: link)
        return components.url
    }

    static func fragment(for link: PresetLink) -> String {
        let fields = [
            version,
            link.templateID,
            link.strings.map(String.init).joined(separator: ","),
            link.referenceHz.map { formatted($0) } ?? "",
            link.temperament?.rawValue ?? "",
            link.name,
        ]
        return fields.joined(separator: "|")
    }

    /// Whole hertz stay whole ("442", not "442.0") — the reference is
    /// stepped in whole hertz, and the shorter string is a denser QR.
    private static func formatted(_ hz: Double) -> String {
        hz == hz.rounded() ? String(Int(hz)) : String(hz)
    }

    /// The reverse. Returns nil for anything it can't read with certainty:
    /// an unknown version, a missing field, a pitch that isn't a number, an
    /// empty tuning. Refusing is the safe failure — the receiver sees "this
    /// link isn't readable" instead of a preset that isn't what was sent.
    public static func link(from url: URL) -> PresetLink? {
        guard isPresetURL(url), let fragment = url.fragment(percentEncoded: false) else {
            return nil
        }
        return link(fromFragment: fragment)
    }

    /// Both spellings are the app's: the universal link it emits, and the
    /// custom scheme every link ever shared already uses. Anything else —
    /// another host, another path — is not ours to read.
    private static func isPresetURL(_ url: URL) -> Bool {
        switch url.scheme?.lowercased() {
        case "https":
            return url.host?.lowercased() == universalHost
                && (url.path == universalPath || url.path == universalPath + "/")
        case scheme:
            return url.host?.lowercased() == host
        default:
            return false
        }
    }

    static func link(fromFragment fragment: String) -> PresetLink? {
        // Split at most into the field count: the name is last and keeps
        // any separators it contains.
        let parts = fragment.split(separator: "|", maxSplits: 5, omittingEmptySubsequences: false)
        guard parts.count == 6, parts[0] == version else { return nil }

        let templateID = String(parts[1])
        guard !templateID.isEmpty else { return nil }

        let pitches = parts[2].split(separator: ",").map(String.init)
        guard !pitches.isEmpty else { return nil }
        var strings: [Int] = []
        for pitch in pitches {
            guard let midi = Int(pitch), Detection.targetMIDIRange.contains(midi) else {
                return nil
            }
            strings.append(midi)
        }

        // Absent is legitimate for both — a preset carries only the fields
        // it was saved with — but present-and-unreadable is not.
        var referenceHz: Double?
        if !parts[3].isEmpty {
            guard let hz = Double(parts[3]), ReferencePitch.range.contains(hz) else { return nil }
            referenceHz = hz
        }
        var temperament: Temperament?
        if !parts[4].isEmpty {
            guard let read = Temperament(rawValue: String(parts[4])) else { return nil }
            temperament = read
        }

        let name = String(parts[5]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        return PresetLink(
            name: name, templateID: templateID, strings: strings,
            referenceHz: referenceHz, temperament: temperament)
    }
}
