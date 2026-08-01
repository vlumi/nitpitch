import NitpitchCore
import SwiftUI

/// The tuner screen: note name, cent offset, and a needle.
///
/// Accessibility identifiers are stable and kept in sync with `Tests/UITests`
/// (`tuner.note`, `tuner.cents`, `tuner.status`, `tuner.instrument`).
public struct NitpitchView: View {
    @ObservedObject private var settings: Settings
    @StateObject private var model: NitpitchViewModel

    public init(settings: Settings) {
        self.settings = settings
        _model = StateObject(
            wrappedValue: NitpitchViewModel(
                reference: settings.reference, band: settings.instrument.band()))
    }

    public var body: some View {
        VStack(spacing: 20) {
            header
            ArcView(cents: displayCents, inTune: isInTune)
                .frame(height: 120)
            LightStrip(cents: displayCents, isReading: isReading)
            readout
            Spacer(minLength: 0)
            controls
        }
        .padding(24)
        // Capped so the column stays a column on an iPad or a wide Mac window
        // rather than stretching to the full width; all four orientations are
        // supported, so this has to hold in landscape too.
        .frame(maxWidth: 520)
        // Top-aligned: with the column centred, any height change below the
        // dial would still shift it, even with the readout pinned.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task { await model.start() }
        .onDisappear { model.stop() }
        .onChangeCompat(of: settings.instrument) { _ in reconfigure() }
        .onChangeCompat(of: settings.reference) { _ in reconfigure() }
    }

    private func reconfigure() {
        model.configure(reference: settings.reference, band: settings.instrument.band())
    }

    private var header: some View {
        HStack {
            Text(verbatim: "A=\(Int(settings.reference.hz))")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()
            LevelMeter(level: model.level)
                .frame(width: 60, height: 4)
        }
    }

    /// The readout reserves a fixed height whatever it's showing.
    ///
    /// The note-plus-cents stack is much taller than a one-line status, and
    /// letting the block resize pushed the dial up and down every time a note
    /// started or stopped — the whole screen twitching on each bow stroke.
    private var readout: some View {
        readoutContent
            .frame(height: Self.readoutHeight)
    }

    /// Tall enough for the note name and the cent label together. Derived from
    /// the font sizes rather than hardcoded, so it holds if they change.
    private static let readoutHeight: CGFloat = noteFontSize * 1.2 + 6 + 24

    private static let noteFontSize: CGFloat = 76

    @ViewBuilder
    private var readoutContent: some View {
        switch model.state {
        case .reading(let reading, let cents, _):
            VStack(spacing: 6) {
                Text(reading.note.name(in: settings.naming))
                    .font(.system(size: Self.noteFontSize, weight: .light, design: .rounded))
                    .accessibilityIdentifier("tuner.note")
                    .accessibilityLabel(reading.note.accessibleName(in: settings.naming))
                Text(centsLabel(cents))
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(isInTune ? Color.green : .secondary)
                    .accessibilityIdentifier("tuner.cents")
            }
        case .listening:
            status("Play a note", id: "tuner.status")
        case .permissionDenied:
            status("Microphone access is off", id: "tuner.status")
        case .idle:
            status("Not listening", id: "tuner.status")
        }
    }

    private func status(_ key: LocalizedStringKey, id: String) -> some View {
        Text(key, bundle: .module)
            .font(.title3)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier(id)
    }

    private var controls: some View {
        HStack(spacing: 16) {
            Picker(selection: $settings.instrument) {
                ForEach(Instrument.all) { instrument in
                    Text(LocalizedStringKey(instrument.name), bundle: .module).tag(instrument)
                }
            } label: {
                Text("Instrument", bundle: .module)
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("tuner.instrument")

            Picker(selection: $settings.naming) {
                // Each convention is labelled in its own terms ("A H C",
                // "イロハ"), so the list doesn't need translating.
                ForEach(NoteNaming.allCases, id: \.self) { naming in
                    Text(verbatim: naming.label).tag(naming)
                }
            } label: {
                Text("Notation", bundle: .module)
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("tuner.naming")
        }
    }

    private func centsLabel(_ cents: Double) -> String {
        // A leading sign on both directions, so "flat or sharp" reads at a
        // glance without parsing the number.
        let rounded = Int(cents.rounded())
        return rounded > 0 ? "+\(rounded)¢" : "\(rounded)¢"
    }

    private var displayCents: Double {
        if case .reading(_, let cents, _) = model.state { return cents }
        return 0
    }

    private var isInTune: Bool {
        if case .reading(_, let cents, _) = model.state {
            return TuningDisplay.isInTune(cents: cents)
        }
        return false
    }

    /// Whether there's a live reading to display, as opposed to silence or a
    /// rejected frame — the strip dims rather than sitting on a stale value.
    private var isReading: Bool {
        if case .reading = model.state { return true }
        return false
    }
}

/// The dial: a fixed needle standing at vertical, and the gap between it and
/// the current reading filled in.
///
/// The filled region *is* the error — nothing when in tune, growing out to one
/// side as the note drifts. That makes zero mean zero, rather than asking the
/// eye to judge a pointer's position against a mark.
struct ArcView: View {
    let cents: Double
    let inTune: Bool

    var body: some View {
        GeometryReader { geo in
            let arc = TuningDisplay.arc(forCents: cents)
            ZStack {
                DialTrack()
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                DialTicks()
                    .stroke(Color.secondary.opacity(0.45), lineWidth: 1)
                ErrorFill(sweepDegrees: arc.sweepDegrees)
                    .fill(tint.gradient)
                    .animation(.easeOut(duration: 0.12), value: cents)
                // Both needles last, so they stay visible against the fill.
                ReadingNeedle(sweepDegrees: arc.sweepDegrees)
                    .fill(tint)
                    .animation(.easeOut(duration: 0.12), value: cents)
                CentreNeedle()
                    .fill(inTune ? Color.green : Color.primary.opacity(0.85))
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityHidden(true)
    }

    /// Green when in tune, warming through amber to red as the error grows —
    /// with brightness falling as the hue shifts.
    ///
    /// Hue alone would be invisible to a red-green colour-blind viewer, for
    /// whom green and red desaturate to nearly the same grey. Moving
    /// brightness together with hue keeps the two ends distinguishable in
    /// greyscale, and makes in tune the brightest thing on the dial.
    private var tint: Color {
        let magnitude = min(abs(cents) / TuningDisplay.fullScaleCents, 1)
        // 0.33 (green) → 0.0 (red). The brightness ramp is steep enough to
        // overcome yellow's high intrinsic luminance in the middle of the
        // range: without it, greyscale luminance *rises* before it falls and
        // slightly-flat looks brighter than in tune.
        let hue = 0.33 * pow(1 - magnitude, 1.6)
        let brightness = 1.0 - 0.55 * pow(magnitude, 0.7)
        return Color(hue: hue, saturation: 0.9, brightness: brightness)
    }
}

/// The fixed needle at top dead centre: the target, always in the same place.
private struct CentreNeedle: Shape {
    func path(in rect: CGRect) -> Path {
        let centre = Dial.centre(in: rect)
        let radius = Dial.radius(in: rect)
        let half = Dial.maxHalfThickness(in: rect)
        let width = Dial.needleHalfWidth
        return Path(
            CGRect(
                x: centre.x - width, y: centre.y - radius - half,
                width: width * 2, height: half * 2))
    }
}

/// A needle at the fill's leading edge, marking where the reading actually is.
///
/// Without it the arc's end is a colour boundary the eye has to estimate
/// against the track; with it there's a definite pointer to read off the
/// scale. It overhangs the band slightly on both sides so it stays findable
/// against the fill behind it.
private struct ReadingNeedle: Shape {
    var sweepDegrees: Double

    var animatableData: Double {
        get { sweepDegrees }
        set { sweepDegrees = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let centre = Dial.centre(in: rect)
        let radius = Dial.radius(in: rect)
        let half = Dial.maxHalfThickness(in: rect)
        let overhang = half * 0.35
        let width = Dial.needleHalfWidth

        // Hidden while in tune, where it would sit on top of the centre needle
        // and just thicken it.
        guard abs(sweepDegrees) > 0.5 else { return Path() }

        let angle = Angle.degrees(-90 + sweepDegrees)
        let cosine = cos(angle.radians)
        let sine = sin(angle.radians)
        let inner = radius - half - overhang
        let outer = radius + half + overhang

        // A rectangle laid along the radius at `angle`: two points on the
        // radial line, expanded sideways by the needle's half-width.
        let acrossX = -sine * width
        let acrossY = cosine * width
        let innerPoint = CGPoint(x: centre.x + cosine * inner, y: centre.y + sine * inner)
        let outerPoint = CGPoint(x: centre.x + cosine * outer, y: centre.y + sine * outer)

        var path = Path()
        path.move(to: CGPoint(x: innerPoint.x - acrossX, y: innerPoint.y - acrossY))
        path.addLine(to: CGPoint(x: outerPoint.x - acrossX, y: outerPoint.y - acrossY))
        path.addLine(to: CGPoint(x: outerPoint.x + acrossX, y: outerPoint.y + acrossY))
        path.addLine(to: CGPoint(x: innerPoint.x + acrossX, y: innerPoint.y + acrossY))
        path.closeSubpath()
        return path
    }
}

/// Scale marks along the track, at the same cent thresholds as the lights.
private struct DialTicks: Shape {
    func path(in rect: CGRect) -> Path {
        let centre = Dial.centre(in: rect)
        let radius = Dial.radius(in: rect)
        let half = Dial.maxHalfThickness(in: rect)

        var path = Path()
        for tick in TuningDisplay.ticks {
            let angle = Angle.degrees(-90 + tick.degrees)
            let cosine = cos(angle.radians)
            let sine = sin(angle.radians)
            // Marks sit outside the band so the fill never covers them.
            let start = radius + half
            let length = half * (tick.isMajor ? 0.85 : 0.5)
            path.move(to: CGPoint(x: centre.x + cosine * start, y: centre.y + sine * start))
            path.addLine(
                to: CGPoint(
                    x: centre.x + cosine * (start + length),
                    y: centre.y + sine * (start + length)))
        }
        return path
    }
}

/// Geometry shared by the arc band and its backdrop, so the band always sits
/// exactly on the track.
private enum Dial {
    /// The dial's centre sits below the visible area, so the drawn arc is the
    /// top cap of a large circle rather than a small dial in the middle.
    static func centre(in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.midX, y: rect.maxY + rect.height * 0.55)
    }

    /// Leaves headroom above the band for the tick marks and the reading
    /// needle's overhang, both of which sit outside it.
    static func radius(in rect: CGRect) -> CGFloat {
        centre(in: rect).y - rect.minY - maxHalfThickness(in: rect) * 1.9
    }

    /// Half-thickness of the filled band and the needle it stands against.
    static func maxHalfThickness(in rect: CGRect) -> CGFloat {
        rect.height * 0.13
    }

    /// The needle is deliberately narrow: it marks the target, and shouldn't
    /// compete with the fill for attention.
    static let needleHalfWidth: CGFloat = 1.5
}

/// The faint full-range track the band sweeps along.
private struct DialTrack: Shape {
    func path(in rect: CGRect) -> Path {
        let centre = Dial.centre(in: rect)
        let radius = Dial.radius(in: rect)
        let sweep = Angle.degrees(TuningDisplay.fullScaleDegrees)
        var path = Path()
        path.addArc(
            center: centre, radius: radius,
            startAngle: .degrees(-90) - sweep, endAngle: .degrees(-90) + sweep,
            clockwise: false)
        return path
    }
}

/// The gap between the needle and the reading, filled in.
///
/// A constant-thickness arc from top dead centre out to the reading's angle,
/// cut square at the leading end. Its *length* is the error, so it vanishes
/// when the note is in tune and grows to one side as it drifts — the sign of
/// the sweep is which side.
///
/// The end is flat rather than rounded because a round cap overshoots the
/// reading by half the band's thickness, leaving the eye unsure which point on
/// the dial the arc is actually claiming. A square edge lands on the value.
struct ErrorFill: Shape {
    /// Signed degrees from vertical; negative sweeps flat (left).
    var sweepDegrees: Double

    var animatableData: Double {
        get { sweepDegrees }
        set { sweepDegrees = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let centre = Dial.centre(in: rect)
        let radius = Dial.radius(in: rect)
        let half = Dial.maxHalfThickness(in: rect)

        let magnitude = abs(sweepDegrees)
        // Anything shorter reads as a speck clinging to the needle rather than
        // as nothing; in tune should show nothing at all.
        guard magnitude > 0.5 else { return Path() }
        let direction: Double = sweepDegrees < 0 ? -1 : 1

        let start = Angle.degrees(-90)
        let end = Angle.degrees(-90 + direction * magnitude)

        // Out along the far edge, straight across the end, back along the near
        // edge — the two straight closes are the square ends.
        var path = Path()
        path.addArc(
            center: centre, radius: radius + half,
            startAngle: start, endAngle: end, clockwise: direction < 0)
        path.addArc(
            center: centre, radius: radius - half,
            startAngle: end, endAngle: start, clockwise: direction > 0)
        path.closeSubpath()
        return path
    }
}

/// The light strip: logarithmically spaced dots, centre lit when in tune.
///
/// Spacing doubles outward (±2, 4, 8, 16, 32¢) because the ear responds to
/// proportional error — this puts the resolution where tuning actually
/// happens instead of spreading it evenly across a semitone.
struct LightStrip: View {
    let cents: Double
    let isReading: Bool

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<TuningDisplay.lightCount, id: \.self) { index in
                Circle()
                    .fill(color(for: index))
                    .frame(width: diameter(for: index), height: diameter(for: index))
            }
        }
        .animation(.easeOut(duration: 0.1), value: cents)
        .accessibilityHidden(true)
    }

    /// The centre light is drawn larger — it's the target, so it should be the
    /// easiest thing on the strip to find without looking directly at it.
    private func diameter(for index: Int) -> CGFloat {
        index == TuningDisplay.centerLightIndex ? 14 : 10
    }

    private func color(for index: Int) -> Color {
        guard isReading else { return .secondary.opacity(0.15) }
        let intensity = TuningDisplay.lightIntensity(index: index, cents: cents)
        guard intensity > 0 else { return .secondary.opacity(0.15) }
        let lit: Color = index == TuningDisplay.centerLightIndex ? .green : .orange
        return lit.opacity(intensity)
    }
}

/// Input level bar — shows the app is hearing something even when no pitch is
/// confident enough to display.
struct LevelMeter: View {
    let level: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.2))
                Capsule().fill(Color.secondary)
                    .frame(width: geo.size.width * level)
            }
        }
        .accessibilityHidden(true)
    }
}
