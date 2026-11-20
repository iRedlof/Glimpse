import Foundation
import Testing

@testable import GlimpseCore

struct MeetingLinkTests {
    private func provider(_ string: String) -> MeetingLink.Provider? {
        URL(string: string).flatMap(MeetingLink.init(url:))?.provider
    }

    @Test(arguments: [
        ("https://zoom.us/j/1234567890?pwd=abc", MeetingLink.Provider.zoom),
        ("https://acme.zoom.us/j/1234567890", .zoom),
        ("https://us02web.zoom.us/s/987", .zoom),
        ("https://zoom.us/my/jane.doe", .zoom),
        ("https://zoom.us/wc/join/123", .zoom),
        ("https://acme.zoomgov.com/j/1610000000", .zoom),
        ("HTTPS://ZOOM.US/j/42", .zoom),
        ("https://meet.google.com/abc-defg-hij", .meet),
        ("https://meet.google.com/abc-defg-hij/?authuser=1", .meet),
        ("https://teams.microsoft.com/l/meetup-join/19%3ameeting_x%40thread.v2/0?context=%7b%7d", .teams),
        ("https://teams.microsoft.com/meet/1234?p=abc", .teams),
        ("https://teams.live.com/meet/9876", .teams),
        ("https://acme.webex.com/meet/jane", .webex),
        ("https://acme.webex.com/acme/j.php?MTID=m123", .webex),
        ("https://acme.webex.com/wbxmjs/joinservice/sites/acme/meeting/download/abc", .webex),
        ("https://zoom.us:443/j/1", .zoom),
    ])
    func acceptsKnownMeetingLinks(url: String, expected: MeetingLink.Provider) {
        #expect(provider(url) == expected)
    }

    @Test(arguments: [
        "http://zoom.us/j/123",                       // not https
        "zoommtg://zoom.us/join?confno=123",          // custom scheme
        "https://evilzoom.us/j/123",                  // no label boundary
        "https://zoom.us.evil.com/j/123",             // suffix spoof
        "https://zoom.us@evil.com/j/123",             // credentials redirect host
        "https://user:pw@zoom.us/j/123",              // credentials
        "https://zoom.us:8443/j/123",                 // odd port
        "https://zoom.us/",                           // no meeting path
        "https://zoom.us/j/",                         // empty meeting id
        "https://zoom.us/download",                   // not a meeting
        "https://meet.google.com/",                   // no code
        "https://meet.google.com/abc-defg",           // malformed code
        "https://meet.google.com/ABC-DEFG-HIJ",       // codes are lowercase
        "https://meet.google.com/abc-defg-hij/extra", // extra path
        "https://google.com/abc-defg-hij",            // wrong host
        "https://teams.microsoft.com/",               // no meeting path
        "https://teams.microsoft.com.evil.io/l/meetup-join/1",
        "https://webex.com.evil.io/meet/x",
        "https://acme.webex.com/",                    // no meeting path
        "https://example.com/zoom.us/j/1",
        "https://zооm.us/j/1",                        // Cyrillic homograph host
        "javascript:alert(1)",
        "file:///etc/passwd",
    ])
    func rejectsEverythingElse(url: String) {
        #expect(provider(url) == nil)
    }

    @Test
    func eventURLFieldWinsOverLocationAndNotes() {
        let link = MeetingLinkExtractor.link(
            url: URL(string: "https://meet.google.com/abc-defg-hij"),
            location: "https://zoom.us/j/1",
            notes: "https://teams.microsoft.com/meet/2"
        )
        #expect(link?.provider == .meet)
    }

    @Test
    func nonMeetingEventURLFallsBackToLocationThenNotes() {
        let fromLocation = MeetingLinkExtractor.link(
            url: URL(string: "https://example.com/agenda"),
            location: "Room 4 / https://zoom.us/j/1",
            notes: "https://teams.microsoft.com/meet/2"
        )
        #expect(fromLocation?.url.absoluteString == "https://zoom.us/j/1")
        let fromNotes = MeetingLinkExtractor.link(
            url: nil, location: "Room 4",
            notes: "Agenda: https://example.com/doc\nJoin: https://teams.microsoft.com/meet/2"
        )
        #expect(fromNotes?.provider == .teams)
    }

    @Test
    func noLinkAnywhereIsNil() {
        #expect(MeetingLinkExtractor.link(url: nil, location: nil, notes: nil) == nil)
        #expect(MeetingLinkExtractor.link(url: nil, location: "Room 4", notes: "zoom.us/j/1 (no scheme)") == nil)
    }

    @Test(arguments: [
        "Join: <https://zoom.us/j/123>",
        "(https://zoom.us/j/123)",
        "Join at https://zoom.us/j/123.",
        "Join at https://zoom.us/j/123, thanks",
        "\"https://zoom.us/j/123\"",
        "Join:\nhttps://zoom.us/j/123\nPasscode 42",
    ])
    func freeTextTokensStopAtDelimitersAndTrailingPunctuation(text: String) {
        #expect(MeetingLinkExtractor.firstLink(in: text)?.url.absoluteString == "https://zoom.us/j/123")
    }

    @Test
    func skipsLookalikesAndFindsTheFirstRealLink() {
        let text = "https://zoom.us.evil.com/j/1 then https://evil.io/x and https://acme.zoom.us/j/77"
        #expect(MeetingLinkExtractor.firstLink(in: text)?.url.absoluteString == "https://acme.zoom.us/j/77")
    }

    @Test
    func notesBeyondTheScanLimitAreIgnored() {
        let padding = String(repeating: "x", count: MeetingLinkExtractor.maximumScannedCharacters)
        #expect(MeetingLinkExtractor.firstLink(in: padding + " https://zoom.us/j/1") == nil)
        #expect(MeetingLinkExtractor.firstLink(in: "https://zoom.us/j/1 " + padding) != nil)
    }

    @Test
    func providersHaveDisplayNames() {
        #expect(MeetingLink.Provider.allCases.map(\.displayName) == ["Zoom", "Google Meet", "Teams", "Webex"])
    }
}
