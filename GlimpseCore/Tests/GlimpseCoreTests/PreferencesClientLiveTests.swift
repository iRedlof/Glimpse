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
}
