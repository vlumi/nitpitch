#!/usr/bin/env swift
//
// App icon: a tuning fork under a dial track, with the in-tune mark above it.
// Pure CoreGraphics, no dependencies — run it to regenerate every catalog size.
//   swift Scripts/assets/make-icon.swift <appiconset-dir>
//
// The design in one line: the fork says "tuner", the track and centre tick say
// "this one measures pitch". Deliberately NOT the app's error arc — that only
// exists when you're out of tune, so an icon showing it would advertise the
// failure state.
//
// Why the proportions are what they are:
//   - Tines are slim relative to the stem, and the crown is a real U. Equal
//     widths and square corners read as a goalpost, not a tuning fork.
//   - The track ends short of the frame. Run it to the edges and it reads as
//     an eyebrow rather than a dial.
//   - The tick's green is bright (luminance 0.855 against the fork's 0.939).
//     iOS tinted icons map luminance onto one hue, so a darker accent sinks
//     below the fork and disappears; brightness is what keeps it visible when
//     the colour is thrown away.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count > 1 else {
    FileHandle.standardError.write(
        "usage: make-icon.swift <appiconset-dir>\n".data(using: .utf8)!)
    exit(2)
}
let outDir = args[1]

let space = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

struct Palette {
    let bg, fg, accent: CGColor

    /// Charcoal ground, matching the launch background.
    static let dark = Palette(
        bg: rgb(0.055, 0.06, 0.07),
        fg: rgb(0.94, 0.94, 0.93),
        accent: rgb(0.55, 0.97, 0.62))

    /// Warm off-white, for the light-appearance variant.
    static let light = Palette(
        bg: rgb(0.96, 0.95, 0.93),
        fg: rgb(0.13, 0.14, 0.16),
        accent: rgb(0.10, 0.52, 0.24))
}

// MARK: - Geometry
//
// All values are fractions of the icon's edge, so every size is the same
// drawing rather than a scaled bitmap.

enum Geometry {
    static let tineWidth: CGFloat = 0.098
    static let tineGap: CGFloat = 0.155
    static let tineTop: CGFloat = 0.26
    static let crownY: CGFloat = 0.585
    static let stemBottom: CGFloat = 0.86
    /// The stem is deliberately wider than a tine — that difference is most of
    /// what makes the shape read as a tuning fork.
    static let stemScale: CGFloat = 1.5

    static let trackTop: CGFloat = 0.10
    static let trackHalfSpanDegrees: CGFloat = 46
    /// How far the track's ends stop short of the frame edge.
    static let trackEndInset: CGFloat = 0.13
    static let trackWidth: CGFloat = 0.034
    static let trackOpacity: CGFloat = 0.32

    static let tickTop: CGFloat = 0.028
    static let tickLength: CGFloat = 0.068
    static let tickWidth: CGFloat = 0.04
}

func drawFork(_ ctx: CGContext, _ s: CGFloat, _ p: Palette) {
    let cx = s / 2
    let w = s * Geometry.tineWidth
    let gap = s * Geometry.tineGap
    let bendRadius = gap / 2 + w / 2

    // One stroked path: down a tine, round the crown, back up the other. A
    // round cap domes the tine tips the way a real fork's are.
    let u = CGMutablePath()
    u.move(to: CGPoint(x: cx - gap / 2 - w / 2, y: s * Geometry.tineTop))
    u.addLine(to: CGPoint(x: cx - gap / 2 - w / 2, y: s * Geometry.crownY - bendRadius))
    u.addArc(
        center: CGPoint(x: cx, y: s * Geometry.crownY - bendRadius), radius: bendRadius,
        startAngle: .pi, endAngle: 0, clockwise: true)
    u.addLine(to: CGPoint(x: cx + gap / 2 + w / 2, y: s * Geometry.tineTop))

    ctx.setStrokeColor(p.fg)
    ctx.setLineWidth(w)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.addPath(u)
    ctx.strokePath()

    let stemW = w * Geometry.stemScale
    let stemTop = s * Geometry.crownY - w * 0.2
    ctx.setFillColor(p.fg)
    ctx.addPath(
        CGPath(
            roundedRect: CGRect(
                x: cx - stemW / 2, y: stemTop,
                width: stemW, height: s * Geometry.stemBottom - stemTop),
            cornerWidth: stemW * 0.3, cornerHeight: stemW * 0.3, transform: nil))
    ctx.fillPath()
}

/// The dial track. Radius is solved from the apex position and where the ends
/// should land, so `trackEndInset` means what it says at every size.
func drawTrack(_ ctx: CGContext, _ s: CGFloat, _ p: Palette) {
    let halfSpan = Geometry.trackHalfSpanDegrees * .pi / 180
    let radius = s * (0.5 - Geometry.trackEndInset) / sin(halfSpan)
    let centre = CGPoint(x: s / 2, y: s * Geometry.trackTop + radius)

    ctx.setStrokeColor(p.fg.copy(alpha: Geometry.trackOpacity)!)
    ctx.setLineWidth(s * Geometry.trackWidth)
    ctx.setLineCap(.round)
    ctx.addArc(
        center: centre, radius: radius,
        startAngle: -.pi / 2 - halfSpan, endAngle: -.pi / 2 + halfSpan, clockwise: false)
    ctx.strokePath()
}

/// The in-tune mark at top dead centre.
func drawTick(_ ctx: CGContext, _ s: CGFloat, _ p: Palette) {
    ctx.setStrokeColor(p.accent)
    ctx.setLineWidth(s * Geometry.tickWidth)
    ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: s / 2, y: s * Geometry.tickTop))
    ctx.addLine(to: CGPoint(x: s / 2, y: s * (Geometry.tickTop + Geometry.tickLength)))
    ctx.strokePath()
}

func renderIcon(size: Int, palette: Palette) -> CGImage {
    // `noneSkipLast` drops the alpha channel entirely rather than emitting an
    // all-opaque one. App icons must not carry alpha at all — App Store
    // validation rejects a 1024 that has the channel, even when every pixel in
    // it is opaque. iOS masks the corners itself.
    let ctx = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)

    let s = CGFloat(size)
    ctx.setFillColor(palette.bg)
    ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))

    // Flip to a top-left origin so the fractions above read as "down from top".
    ctx.translateBy(x: 0, y: s)
    ctx.scaleBy(x: 1, y: -1)

    drawTrack(ctx, s, palette)
    drawTick(ctx, s, palette)
    drawFork(ctx, s, palette)

    return ctx.makeImage()!
}

func write(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path) as CFURL
    guard
        let dest = CGImageDestinationCreateWithURL(
            url, UTType.png.identifier as CFString, 1, nil)
    else {
        FileHandle.standardError.write("cannot write \(path)\n".data(using: .utf8)!)
        exit(1)
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else {
        FileHandle.standardError.write("failed writing \(path)\n".data(using: .utf8)!)
        exit(1)
    }
}

// MARK: - Emit

/// (filename, pixel size) for every entry in the appiconset.
let outputs: [(String, Int)] = [
    ("icon-1024.png", 1024),
    ("icon-16.png", 16), ("icon-16@2x.png", 32),
    ("icon-32.png", 32), ("icon-32@2x.png", 64),
    ("icon-128.png", 128), ("icon-128@2x.png", 256),
    ("icon-256.png", 256), ("icon-256@2x.png", 512),
    ("icon-512.png", 512), ("icon-512@2x.png", 1024),
]

for (name, size) in outputs {
    write(renderIcon(size: size, palette: .dark), to: "\(outDir)/\(name)")
}
// Dark-appearance variant for the iOS 1024 slot.
write(renderIcon(size: 1024, palette: .light), to: "\(outDir)/icon-1024-light.png")

print("wrote \(outputs.count + 1) images to \(outDir)")
