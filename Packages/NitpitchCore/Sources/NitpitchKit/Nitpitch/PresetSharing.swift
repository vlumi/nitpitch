import CoreImage
import CoreImage.CIFilterBuiltins
import NitpitchCore
import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Renders a share link as a QR code — the across-the-room transfer, for a
/// bandmate standing in front of you with no interest in messaging apps.
///
/// CoreImage's generator, which ships with the OS (no dependency), at
/// `.medium` correction: the payload is small enough that heavier correction
/// only makes the modules smaller and harder to scan from a phone screen.
enum PresetQR {
    static func image(for url: URL, scale: CGFloat = 10) -> Image? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        // Scale by transform rather than resizing the view: the generator
        // emits one pixel per module, and letting SwiftUI stretch that gives
        // blurred edges that scanners struggle with.
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else {
            return nil
        }
        #if canImport(UIKit)
        return Image(uiImage: UIImage(cgImage: cgImage))
        #elseif canImport(AppKit)
        return Image(nsImage: NSImage(cgImage: cgImage, size: scaled.extent.size))
        #else
        return nil
        #endif
    }
}

/// A preset link that just arrived, and what can be done about it.
enum PresetArrival: Identifiable {
    /// Readable, and the receiver owns something it fits.
    case offer(link: PresetLink, instrumentID: String, resolution: PresetImport.Resolution)
    /// Readable, but for an instrument they don't own — a bass preset with
    /// no bass. Told plainly rather than silently dropped.
    case noInstrument(PresetLink)
    /// Not readable at all: a truncated link, or a version this build
    /// doesn't know. Refusing beats applying a tuning nobody sent.
    case unreadable

    var id: String {
        switch self {
        case .offer(let link, let instrumentID, _):
            return "offer:\(instrumentID):\(link.name):\(link.strings)"
        case .noInstrument(let link):
            return "noInstrument:\(link.templateID):\(link.name)"
        case .unreadable:
            return "unreadable"
        }
    }
}

/// What a payload would do, spelled out — the same vocabulary the preset
/// rows and the tuning menu use, so a shared setup reads the way a saved
/// one does. (An explicitly-equal temperament stays unspelled, as there.)
enum PresetPayloadSummary {
    static func text(strings: [Int], referenceHz: Double?, temperament: Temperament?) -> String {
        var summary = strings.map { Note(midi: $0).fullName }.joined(separator: " ")
        if let referenceHz {
            summary += " · A=\(Int(referenceHz))"
        }
        if temperament == .pure {
            summary += " · pure"
        }
        return summary
    }
}

/// A link that can't become anything: said plainly, with whatever of the
/// payload is worth showing.
struct PresetArrivalProblemView: View {
    let message: Text
    let detail: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Image(systemName: "link.badge.plus")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                message
                    .multilineTextAlignment(.center)
                if let detail {
                    Text(verbatim: detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle(Text("Preset received", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done", bundle: .module)
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 320, minHeight: 260)
        #endif
    }
}

/// The share sheet for one preset: what it carries, its QR code, and the
/// link itself.
///
/// The payload is shown rather than described, because sharing a setup is
/// sharing *values* — someone about to send "Gig" to a bandmate should see
/// that it carries A=442 before they send it, not discover it afterwards.
struct PresetShareView: View {
    let link: PresetLink
    let summary: String
    @Environment(\.dismiss) private var dismiss

    private var url: URL? { PresetLinkCodec.url(for: link) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                VStack(spacing: 4) {
                    Text(verbatim: link.name)
                        .font(.title3.weight(.semibold))
                    Text(verbatim: summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                if let url, let code = PresetQR.image(for: url) {
                    code
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 220, maxHeight: 220)
                        .padding(10)
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .accessibilityLabel(Text("QR code for this preset", bundle: .module))
                }
                Text("Scan this, or send the link.", bundle: .module)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let url {
                    ShareLink(item: url) {
                        Label {
                            Text("Share link", bundle: .module)
                        } icon: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                    .accessibilityIdentifier("preset.share.link")
                }
                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle(Text("Share preset", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done", bundle: .module)
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 460)
        #endif
    }
}

/// The other end: a link has arrived, and nothing is written until the
/// receiver says so.
///
/// The choice offered depends on what they already have, and it's the same
/// choice a local save offers — because an import IS a save from elsewhere.
/// A name they don't use saves outright; a name they do use asks, since
/// "here's the corrected version" and "here's a variant" are intents only
/// the user can tell apart.
struct PresetImportView: View {
    let link: PresetLink
    let instrumentName: String
    let summary: String
    let resolution: PresetImport.Resolution
    /// Load it onto the instrument without keeping it — trying a friend's
    /// tuning is not a commitment to store it.
    let onLoadOnce: () -> Void
    /// Save it: `.create` mints a new preset, `.nameTaken` replaces the
    /// named one. "Keep both" is spelled as a `.create` with the numbered
    /// name, so the store never has to guess which the user meant.
    let onSave: (PresetImport.Resolution) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                VStack(spacing: 4) {
                    Text(verbatim: link.name)
                        .font(.title3.weight(.semibold))
                    Text(verbatim: summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Text(verbatim: instrumentName)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)

                if case .nameTaken(_, let name, _) = resolution {
                    Label {
                        Text("You already have a preset called “\(name)”.", bundle: .module)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                }

                VStack(spacing: 10) {
                    Button {
                        onLoadOnce()
                        dismiss()
                    } label: {
                        Text("Load once", bundle: .module)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("preset.import.loadOnce")

                    switch resolution {
                    case .create:
                        Button {
                            onSave(resolution)
                            dismiss()
                        } label: {
                            Text("Save", bundle: .module)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("preset.import.save")
                    case .nameTaken(_, let name, let keepBothName):
                        Button {
                            onSave(resolution)
                            dismiss()
                        } label: {
                            Text("Replace “\(name)”", bundle: .module)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("preset.import.replace")

                        Button {
                            onSave(.create(name: keepBothName))
                            dismiss()
                        } label: {
                            Text("Keep both", bundle: .module)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("preset.import.keepBoth")
                    }
                }
                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle(Text("Preset received", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Cancel", bundle: .module)
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 380)
        #endif
    }
}
