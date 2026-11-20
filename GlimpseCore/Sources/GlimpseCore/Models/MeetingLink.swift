import Foundation

/// A video-call link found on a calendar event (Zoom, Google Meet, Teams, Webex).
///
/// Extraction is deliberately strict: only `https` URLs on known meeting hosts with a
/// meeting-shaped path are accepted, so Join can never open an arbitrary link pasted
/// into an invitation. No credentials, no non-default port, ASCII hosts only.
public struct MeetingLink: Equatable, Sendable {
    public enum Provider: String, CaseIterable, Equatable, Sendable {
        case zoom, meet, teams, webex

        public var displayName: String {
            switch self {
            case .zoom: "Zoom"
            case .meet: "Google Meet"
            case .teams: "Teams"
            case .webex: "Webex"
            }
        }
    }

    public let provider: Provider
    public let url: URL

    /// Validates `url`; nil unless it is a strict meeting link.
    public init?(url: URL) {
        guard let provider = MeetingLinkExtractor.provider(for: url) else { return nil }
        self.provider = provider
        self.url = url
    }
}

public enum MeetingLinkExtractor {
    /// Notes beyond this many characters are not scanned (long invitations put the
    /// join link near the top; this bounds work on pathological notes).
    static let maximumScannedCharacters = 20_000
    private static let scheme = "https://"
    /// Characters that end a URL token in free text.
    private static let terminators = CharacterSet.whitespacesAndNewlines
        .union(CharacterSet(charactersIn: "<>\"'`()[]{}|\\^"))
    /// Trailing punctuation that belongs to the sentence, not the URL.
    private static let trailingPunctuation = CharacterSet(charactersIn: ".,;:!?")

    /// The first meeting link on an event: its URL field, then location, then notes.
    public static func link(url: URL?, location: String?, notes: String?) -> MeetingLink? {
        if let url, let link = MeetingLink(url: url) { return link }
        for text in [location, notes].compactMap({ $0 }) {
            if let link = firstLink(in: text) { return link }
        }
        return nil
    }

    /// The first strict meeting link among the `https://` tokens of `text`.
    public static func firstLink(in text: String) -> MeetingLink? {
        let scanned = text.prefix(maximumScannedCharacters)
        var searchStart = scanned.startIndex
        while let match = scanned.range(of: scheme, options: [.caseInsensitive],
                                        range: searchStart..<scanned.endIndex) {
            let token = urlToken(in: scanned, from: match.lowerBound)
            if let url = URL(string: String(token)), let link = MeetingLink(url: url) { return link }
            searchStart = match.upperBound
        }
        return nil
    }

    private static func urlToken(in text: Substring, from start: Substring.Index) -> Substring {
        var end = start
        while end < text.endIndex,
              !text[end].unicodeScalars.contains(where: terminators.contains) {
            end = text.index(after: end)
        }
        var token = text[start..<end]
        while let last = token.unicodeScalars.last, trailingPunctuation.contains(last) {
            token = token.dropLast()
        }
        return token
    }

    /// The provider for a strict meeting URL, else nil.
    static func provider(for url: URL) -> MeetingLink.Provider? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              components.user == nil, components.password == nil,
              components.port == nil || components.port == 443,
              let rawHost = components.host, !rawHost.isEmpty,
              rawHost.unicodeScalars.allSatisfy(\.isASCII)
        else { return nil }
        let host = rawHost.lowercased()
        let path = components.path
        if matches(host, domain: "zoom.us") || matches(host, domain: "zoomgov.com") {
            return isZoomPath(path) ? .zoom : nil
        }
        if host == "meet.google.com" {
            return isMeetPath(path) ? .meet : nil
        }
        if host == "teams.microsoft.com" || host == "teams.live.com" {
            return isTeamsPath(path) ? .teams : nil
        }
        if matches(host, domain: "webex.com") {
            return isWebexPath(path) ? .webex : nil
        }
        return nil
    }

    /// `host` is `domain` or a subdomain of it (label boundary, so `evilzoom.us` fails).
    private static func matches(_ host: String, domain: String) -> Bool {
        host == domain || host.hasSuffix("." + domain)
    }

    private static func isZoomPath(_ path: String) -> Bool {
        // /j/<id> (join), /s/<id> (start), /w/<id> (webinar), /my/<vanity>, /wc/join/<id>.
        ["/j/", "/s/", "/w/", "/my/", "/wc/join/"].contains { prefix in
            path.hasPrefix(prefix) && path.count > prefix.count
        }
    }

    private static func isMeetPath(_ path: String) -> Bool {
        // /abc-defg-hij, optionally with a trailing slash.
        let code = path.hasSuffix("/") ? String(path.dropFirst().dropLast()) : String(path.dropFirst())
        let parts = code.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.map(\.count) == [3, 4, 3] else { return false }
        return parts.allSatisfy { $0.unicodeScalars.allSatisfy { CharacterSet.lowercaseLetters.contains($0) && $0.isASCII } }
    }

    private static func isTeamsPath(_ path: String) -> Bool {
        ["/l/meetup-join/", "/meet/"].contains { prefix in
            path.hasPrefix(prefix) && path.count > prefix.count
        }
    }

    private static func isWebexPath(_ path: String) -> Bool {
        let lowered = path.lowercased()
        if lowered.hasSuffix("/j.php") { return true }
        return ["/meet/", "/join/", "/wbxmjs/joinservice/"].contains { prefix in
            lowered.hasPrefix(prefix) && lowered.count > prefix.count
        }
    }
}
