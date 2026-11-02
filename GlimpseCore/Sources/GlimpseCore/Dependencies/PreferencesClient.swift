import ComposableArchitecture
import Foundation

@DependencyClient
public struct PreferencesClient: Sendable {
    public var loadStartOfWeekday: @Sendable () -> Int = { 1 }
    public var saveStartOfWeekday: @Sendable (Int) -> Void
    public var loadWorkdays: @Sendable () -> Set<Int> = { [2, 3, 4, 5, 6] }
    public var saveWorkdays: @Sendable (Set<Int>) -> Void
    public var loadDisplayOptions: @Sendable () -> MenuBarDisplayOptions = { .default }
    public var saveDisplayOptions: @Sendable (MenuBarDisplayOptions) -> Void
    public var loadShowAISearch: @Sendable () -> Bool = { true }
    public var saveShowAISearch: @Sendable (Bool) -> Void
    public var loadAIProvider: @Sendable () -> AIProvider = { .auto }
    public var saveAIProvider: @Sendable (AIProvider) -> Void
}

extension PreferencesClient: DependencyKey {
    public static var liveValue: Self {
        live(defaults: .standard)
    }

    /// Accept a defaults domain so separate app instances do not share settings.
    public static func live(defaults userDefaults: UserDefaults) -> Self {
        // Safety: UserDefaults is documented thread-safe for read/write operations.
        nonisolated(unsafe) let defaults = userDefaults

        return Self(
            loadStartOfWeekday: {
                let value = defaults.object(forKey: "startOfWeekday") != nil
                    ? defaults.integer(forKey: "startOfWeekday")
                    : 1
                guard (1...7).contains(value) else {
                    AppLogger.preferences.error("Invalid saved start weekday; using Sunday")
                    return 1
                }
                return value
            },
            saveStartOfWeekday: { value in
                defaults.set(value, forKey: "startOfWeekday")
            },
            loadWorkdays: {
                if let saved = defaults.array(forKey: "workdays") as? [Int] {
                    return Set(saved.filter { (1...7).contains($0) })
                }
                return [2, 3, 4, 5, 6]
            },
            saveWorkdays: { value in
                defaults.set(Array(value), forKey: "workdays")
            },
            loadDisplayOptions: {
                func loadBool(_ key: String, defaultValue: Bool) -> Bool {
                    defaults.object(forKey: key) != nil
                        ? defaults.bool(forKey: key)
                        : defaultValue
                }
                return MenuBarDisplayOptions(
                    showIcon: loadBool("showIcon", defaultValue: true),
                    showDayOfWeek: loadBool("showDayOfWeek", defaultValue: true),
                    showMonth: loadBool("showMonth", defaultValue: true),
                    showDate: loadBool("showDate", defaultValue: true),
                    showYear: loadBool("showYear", defaultValue: false),
                    showFilledBackground: loadBool("showFilledBackground", defaultValue: false)
                )
            },
            saveDisplayOptions: { options in
                defaults.set(options.showIcon, forKey: "showIcon")
                defaults.set(options.showDayOfWeek, forKey: "showDayOfWeek")
                defaults.set(options.showMonth, forKey: "showMonth")
                defaults.set(options.showDate, forKey: "showDate")
                defaults.set(options.showYear, forKey: "showYear")
                defaults.set(options.showFilledBackground, forKey: "showFilledBackground")
            },
            loadShowAISearch: {
                defaults.object(forKey: "showAISearch") != nil
                    ? defaults.bool(forKey: "showAISearch")
                    : true
            },
            saveShowAISearch: { value in
                defaults.set(value, forKey: "showAISearch")
            },
            loadAIProvider: {
                if let raw = defaults.string(forKey: "aiProvider"),
                   let provider = AIProvider(rawValue: raw) {
                    return provider
                }
                return .auto
            },
            saveAIProvider: { provider in
                defaults.set(provider.rawValue, forKey: "aiProvider")
            }
        )
    }

    public static let testValue = Self()
}

extension DependencyValues {
    public var preferencesClient: PreferencesClient {
        get { self[PreferencesClient.self] }
        set { self[PreferencesClient.self] = newValue }
    }
}
