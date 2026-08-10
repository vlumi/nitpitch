import XCTest

@testable import NitpitchCore

/// The share link: what survives the trip, and what a decoder refuses.
///
/// Refusal matters more than it looks. A link that decodes *wrongly* applies
/// a tuning nobody sent — silently, to a real instrument — so every
/// malformed case below must come back nil rather than best-effort.
final class PresetLinkTests: XCTestCase {
    private let dropD = PresetLink(
        name: "Drop D", templateID: "guitar", strings: [38, 45, 50, 55, 59, 64],
        referenceHz: 442, temperament: nil)

    // MARK: - Round trip

    /// The whole payload survives, field for field.
    func testRoundTripCarriesEveryField() throws {
        let url = try XCTUnwrap(PresetLinkCodec.url(for: dropD))
        let back = try XCTUnwrap(PresetLinkCodec.link(from: url))

        XCTAssertEqual(back, dropD)
    }

    /// A preset carries only the fields it was saved with, so a link must
    /// preserve *absence* — a tuning-only preset that arrives carrying a
    /// reference would move a setting its sender never shared.
    func testAbsentFieldsStayAbsent() throws {
        let tuningOnly = PresetLink(
            name: "Open G", templateID: "guitar", strings: [38, 43, 50, 55, 59, 62])

        let back = try XCTUnwrap(
            PresetLinkCodec.link(from: XCTUnwrap(PresetLinkCodec.url(for: tuningOnly))))

        XCTAssertNil(back.referenceHz)
        XCTAssertNil(back.temperament)
        XCTAssertEqual(back, tuningOnly)
    }

    /// Temperament rides when it was carried — "quartet, pure" is as much
    /// the situation as A=442.
    func testTemperamentRides() throws {
        let quartet = PresetLink(
            name: "Quartet", templateID: "violin", strings: [55, 62, 69, 76],
            referenceHz: 442, temperament: .pure)

        let back = try XCTUnwrap(
            PresetLinkCodec.link(from: XCTUnwrap(PresetLinkCodec.url(for: quartet))))

        XCTAssertEqual(back.temperament, .pure)
    }

    /// The payload rides in the FRAGMENT, which is never sent to a server —
    /// that's what lets a link be hosted on a static site without the host
    /// learning what anyone shared.
    func testPayloadRidesInTheFragment() throws {
        let url = try XCTUnwrap(PresetLinkCodec.url(for: dropD))

        XCTAssertNil(url.query, "nothing in the query")
        let fragment = try XCTUnwrap(url.fragment(percentEncoded: false))
        XCTAssertTrue(fragment.contains("38,45,50,55,59,64"))
    }

    /// Names are the user's own words, verbatim — including the ones that
    /// need escaping in a URL, and the separator itself.
    func testAwkwardNamesSurvive() throws {
        for name in ["Bach No. 1", "Tomorrow's gig", "A|B", "ミサキ", "50% down", "Gig #2"] {
            let link = PresetLink(name: name, templateID: "violin", strings: [55, 62, 69, 76])
            let url = try XCTUnwrap(PresetLinkCodec.url(for: link), name)
            XCTAssertEqual(PresetLinkCodec.link(from: url)?.name, name, name)
        }
    }

    /// Whole hertz stay whole: "442", not "442.0" — a shorter payload is a
    /// less dense QR code, and the reference steps in whole hertz anyway.
    func testWholeHertzStayWhole() {
        let fragment = PresetLinkCodec.fragment(for: dropD)

        XCTAssertTrue(fragment.contains("|442|"), fragment)
    }

    // MARK: - Refusal

    /// A version this build doesn't know is refused, not guessed at.
    func testUnknownVersionIsRefused() {
        XCTAssertNil(
            PresetLinkCodec.link(fromFragment: "v2|guitar|38,45,50,55,59,64|442||Drop D"))
    }

    /// Structurally broken payloads decode to nothing.
    func testMalformedPayloadsAreRefused() {
        let bad = [
            "",
            "v1",
            "v1|guitar|38,45|442|",  // one field short
            "v1||38,45,50,55,59,64|||Drop D",  // no template
            "v1|guitar||||Drop D",  // no strings
            "v1|guitar|38,forty-five|||Drop D",  // a pitch that isn't one
            "v1|guitar|38,45,50,55,59,64|||   ",  // no name
        ]
        for fragment in bad {
            XCTAssertNil(PresetLinkCodec.link(fromFragment: fragment), fragment)
        }
    }

    /// Values outside what the app can represent are refused rather than
    /// clamped: a clamped import is a tuning the sender didn't send, and it
    /// would look deliberate.
    func testOutOfRangeValuesAreRefused() {
        XCTAssertNil(
            PresetLinkCodec.link(fromFragment: "v1|guitar|38,45,999|||Drop D"),
            "a pitch past the detectable range")
        XCTAssertNil(
            PresetLinkCodec.link(fromFragment: "v1|guitar|38,45,50,55,59,64|1000||Drop D"),
            "a reference past the offered range")
        XCTAssertNil(
            PresetLinkCodec.link(fromFragment: "v1|guitar|38,45,50,55,59,64||werckmeister|X"),
            "a temperament this build doesn't have")
    }

    /// Only this app's links open: another app's URL isn't ours to read.
    func testForeignURLsAreRefused() throws {
        for spelling in [
            "https://example.com/#v1|guitar|38,45,50,55,59,64|442||Drop D",
            "nitpitch://instrument#v1|guitar|38,45,50,55,59,64|442||Drop D",
            "nitpitch://preset",
        ] {
            let url = try XCTUnwrap(URL(string: spelling), spelling)
            XCTAssertNil(PresetLinkCodec.link(from: url), spelling)
        }
    }

    /// The scheme is matched case-insensitively — URLs get lowercased and
    /// uppercased in transit by mail clients and QR readers alike.
    func testSchemeMatchingIsCaseInsensitive() throws {
        let url = try XCTUnwrap(
            URL(string: "NITPITCH://PRESET#v1|guitar|38,45,50,55,59,64|442||Drop D"))

        XCTAssertEqual(PresetLinkCodec.link(from: url)?.name, "Drop D")
    }

    /// A QR code's density is its payload length, so the format staying
    /// compact is a feature, not an accident. A six-string preset with
    /// everything set should stay well inside the range that scans easily
    /// from a phone screen.
    func testTheEncodingStaysCompact() throws {
        let url = try XCTUnwrap(PresetLinkCodec.url(for: dropD))

        XCTAssertLessThan(url.absoluteString.count, 80, url.absoluteString)
    }
}
