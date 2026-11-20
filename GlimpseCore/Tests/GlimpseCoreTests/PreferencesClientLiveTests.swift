import Foundation
import Testing

@testable import GlimpseCore

struct PreferencesClientLiveTests {
    @Test(arguments: [-10, 0, 8, Int.max])
    func invalidFirstWeekdayFallsBackToSunday(value: Int) {
        let domain = "GlimpseTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(value, forKey: "startOfWeekday")
        #expect(PreferencesClient.live(defaults: defaults).loadStartOfWeekday() == 1)
    }

    @Test
    func invalidWorkdaysAreDiscarded() {
        let domain = "GlimpseTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set([-1, 0, 2, 7, 8], forKey: "workdays")
        #expect(PreferencesClient.live(defaults: defaults).loadWorkdays() == [2, 7])
    }

    @Test
    func validWeekdayAndEmptyWorkdaysArePreserved() {
        let domain = "GlimpseTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(2, forKey: "startOfWeekday")
        defaults.set([Int](), forKey: "workdays")
        let client = PreferencesClient.live(defaults: defaults)
        #expect(client.loadStartOfWeekday() == 2)
        #expect(client.loadWorkdays().isEmpty)
    }

    @Test
    func nextMeetingIsOffByDefaultAndRoundTrips() throws {
        let domain = "GlimpseTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let client = PreferencesClient.live(defaults: defaults)
        // Existing users have no key: nothing changes for them.
        #expect(client.loadDisplayOptions().showNextMeeting == false)
        var options = client.loadDisplayOptions()
        options.showNextMeeting = true
        client.saveDisplayOptions(options)
        #expect(client.loadDisplayOptions() == options)
        #expect(defaults.bool(forKey: "showNextMeeting"))
    }

    @Test
    func displayOptionsDecodeOlderEncodingsWithDefaults() throws {
        let old = Data(#"{"showIcon":false,"showDayOfWeek":true,"showMonth":true,"showDate":true,"showYear":true,"showFilledBackground":true}"#.utf8)
        let decoded = try JSONDecoder().decode(MenuBarDisplayOptions.self, from: old)
        #expect(decoded == MenuBarDisplayOptions(showIcon: false, showYear: true, showFilledBackground: true))
        #expect(decoded.showNextMeeting == false)
        let empty = try JSONDecoder().decode(MenuBarDisplayOptions.self, from: Data("{}".utf8))
        #expect(empty == .default)
        let current = MenuBarDisplayOptions(showNextMeeting: true)
        let roundTrip = try JSONDecoder().decode(MenuBarDisplayOptions.self, from: JSONEncoder().encode(current))
        #expect(roundTrip == current)
    }
}
