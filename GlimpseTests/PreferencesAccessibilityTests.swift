import AppKit
import ComposableArchitecture
import GlimpseCore
import SwiftUI
import Testing
@testable import Glimpse

@Suite(.serialized)
@MainActor
struct PreferencesAccessibilityTests {
    @Test
    func nativeTitlesPreserveRolesAndSelectedValues() async throws {
        var state = PreferencesFeature.State()
        state.startOfWeekday = 2
        state.aiProvider = .proxy
        state.displayOptions.showFilledBackground = true
        let fixture = PreferencesAccessibilityFixture(state: state)
        let host = fixture.host()
        defer { host.close(); fixture.close() }
        try await host.settle()
        for (name, expected) in [("Filled background", 1), ("AI date search", 1)] {
            let node = try host.control(named: name)
            #expect(node.role == .checkBox)
            #expect((node.value as? NSNumber)?.intValue == expected)
        }
        let weekday = try host.control(named: "Week starts on")
        #expect(weekday.role == .popUpButton)
        #expect(weekday.value as? String == Calendar.current.weekdaySymbols[1])
        let provider = try host.control(named: "AI provider")
        #expect(provider.role == .popUpButton)
        #expect(provider.value as? String == "Cloud AI")
    }

    @Test(arguments: ["Icon", "Day", "Mon", "Date", "Year"], [false, true])
    func displayPillPressChangesOnlyItsOwnValue(pill: String, initial: Bool) async throws {
        let (name, keyPath) = pillContract(pill)
        var state = PreferencesFeature.State()
        state.displayOptions = .init(
            showIcon: false, showDayOfWeek: true, showMonth: false,
            showDate: true, showYear: false, showFilledBackground: true
        )
        state.displayOptions[keyPath: keyPath] = initial
        let fixture = PreferencesAccessibilityFixture(state: state)
        let host = fixture.host()
        defer { host.close(); fixture.close() }
        try await host.settle()
        let before = fixture.store.displayOptions
        let node = try #require(
            host.controls(named: name).first ?? host.controls(named: pill).first
        )
        #expect(node.role == .button)
        #expect(node.label == name)
        #expect(node.value as? String == (initial ? "On" : "Off"))
        #expect(node.press())
        try await host.settle(until: { fixture.receipts.value.menuNotifications == 1 })
        var changed = before
        changed[keyPath: keyPath] = !initial
        #expect(fixture.store.displayOptions == changed)
        #expect(fixture.receipts.value.displaySaves == [changed])
        let after = try #require(
            host.controls(named: name).first ?? host.controls(named: pill).first
        )
        #expect(after.label == name)
        #expect(after.value as? String == (initial ? "Off" : "On"))
        #expect(after.press())
        try await host.settle(until: { fixture.receipts.value.menuNotifications == 2 })
        #expect(fixture.store.displayOptions == before)
        #expect(fixture.receipts.value.displaySaves == [changed, before])
        #expect(fixture.receipts.value.calendarNotifications == 0)
        #expect(fixture.receipts.value.forbidden == 0)
    }

    @Test
    func providerVisibilityAndSelectionSurviveSearchToggle() async throws {
        var state = PreferencesFeature.State()
        state.aiProvider = .proxy
        let fixture = PreferencesAccessibilityFixture(state: state)
        let host = fixture.host()
        defer { host.close(); fixture.close() }
        try await host.settle()
        #expect(try host.control(named: "AI provider").value as? String == "Cloud AI")
        #expect(try host.control(named: "AI date search").press())
        try await host.settle(until: { !fixture.store.showAISearch })
        #expect(host.controls(named: "AI provider").isEmpty)
        #expect(fixture.store.aiProvider == .proxy)
        #expect(try host.control(named: "AI date search").press())
        try await host.settle(until: { fixture.store.showAISearch })
        #expect(try host.control(named: "AI provider").value as? String == "Cloud AI")
        #expect(fixture.receipts.value.aiSaves == [false, true])
        #expect(fixture.receipts.value.providerSaves.isEmpty)
        #expect(fixture.receipts.value.displaySaves.isEmpty)
        #expect(fixture.receipts.value.menuNotifications == 0)
        #expect(fixture.receipts.value.calendarNotifications == 0)
    }

    @Test(arguments: ["Week starts on", "AI provider"])
    func nativePickerSelectionSavesOnce(pickerName: String) async throws {
        var state = PreferencesFeature.State()
        state.startOfWeekday = 1
        state.aiProvider = .auto
        let fixture = PreferencesAccessibilityFixture(state: state)
        let host = fixture.host()
        defer { host.close(); fixture.close() }
        try await host.settle()
        let popup = try host.control(named: pickerName)
        #expect(popup.role == .popUpButton)
        let popupWindow = popup.object.accessibilityWindow?() as? NSWindow
        try #require(popupWindow === host.window, "Picker must belong to the owned window")
        let isWeekday = pickerName == "Week starts on"
        let selectedTitle = isWeekday ? Calendar.current.weekdaySymbols[1] : "Cloud AI"
        let selection = NativePickerSelection(
            expectedTitles: isWeekday
                ? Calendar.current.weekdaySymbols : ["Auto", "Cloud AI", "On-device AI"],
            selectedTitle: selectedTitle
        )
        defer { selection.close() }
        #expect(popup.press())
        try await host.settle(until: { selection.finished })
        #expect(selection.actionAttempted, "\(selection.observation)")
        #expect(selection.trackingEnded, "\(selection.observation)")
        #expect(!selection.timedOut, "\(selection.observation)")
        try await host.settle(until: {
            let receipt = fixture.receipts.value
            return isWeekday
                ? receipt.weekdaySaves == [2] && receipt.calendarNotifications == 1
                : receipt.providerSaves == [.proxy]
        })
        #expect(try host.control(named: pickerName).value as? String == selectedTitle)
        #expect(fixture.store.startOfWeekday == (isWeekday ? 2 : 1))
        #expect(fixture.store.aiProvider == (isWeekday ? .auto : .proxy))
        let receipt = fixture.receipts.value
        #expect(receipt.weekdaySaves == (isWeekday ? [2] : []))
        #expect(receipt.providerSaves == (isWeekday ? [] : [.proxy]))
        #expect(receipt.calendarNotifications == (isWeekday ? 1 : 0))
        #expect(receipt.menuNotifications == 0)
        #expect(receipt.displaySaves.isEmpty)
        #expect(receipt.aiSaves.isEmpty)
        #expect(receipt.forbidden == 0)
        #expect(fixture.hotkey.backend.operations.isEmpty)
    }

    @Test
    func hostingPreferencesNeverTouchesProtectedDependencies() async throws {
        let fixture = PreferencesAccessibilityFixture(state: .init())
        let host = fixture.host()
        defer { host.close(); fixture.close() }
        try await host.settle()
        #expect(fixture.hotkey.backend.operations.isEmpty)
        #expect(fixture.receipts.value.forbidden == 0)
        #expect(fixture.receipts.value.displaySaves.isEmpty)
        #expect(fixture.receipts.value.aiSaves.isEmpty)
        #expect(fixture.receipts.value.providerSaves.isEmpty)
        #expect(fixture.receipts.value.weekdaySaves.isEmpty)
        #expect(!host.window.isKeyWindow)
        #expect(!host.window.isMainWindow)
        #expect(!host.elements().isEmpty)
    }

    private func pillContract(
        _ pill: String
    ) -> (String, WritableKeyPath<MenuBarDisplayOptions, Bool>) {
        switch pill {
        case "Icon": ("Show icon in menu bar", \.showIcon)
        case "Day": ("Show day of week in menu bar", \.showDayOfWeek)
        case "Mon": ("Show month in menu bar", \.showMonth)
        case "Date": ("Show date in menu bar", \.showDate)
        default: ("Show year in menu bar", \.showYear)
        }
    }
}

/// Observes only the menu armed immediately before this owned popup's native press.
@MainActor
final class NativePickerSelection: NSObject {
    private let expectedTitles: [String]
    private let selectedTitle: String
    private let onAction: (@MainActor () -> Void)?
    private let trackingCompleted = AIDateIntegrationSignal<Void>("owned native picker tracking ended")
    private let deadline = ContinuousClock.now.advanced(by: .seconds(1))
    private var menu: NSMenu?
    private var timer: Timer?
    private var observedTitles: [[String]] = []
    private(set) var actionAttempted = false
    private(set) var trackingEnded = false
    private(set) var timedOut = false

    var finished: Bool { trackingEnded || (timedOut && menu == nil) }
    var observation: String {
        "titles=\(observedTitles); action=\(actionAttempted); ended=\(trackingEnded); timeout=\(timedOut)"
    }

    init(
        expectedTitles: [String], selectedTitle: String,
        onAction: (@MainActor () -> Void)? = nil
    ) {
        self.expectedTitles = expectedTitles
        self.selectedTitle = selectedTitle
        self.onAction = onAction
        super.init()
        NotificationCenter.default.addObserver(
            self, selector: #selector(didBeginTracking(_:)),
            name: NSMenu.didBeginTrackingNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(didEndTracking(_:)),
            name: NSMenu.didEndTrackingNotification, object: nil
        )
        let timer = Timer(timeInterval: 0.01, repeats: true) { [weak self] _ in
            // This timer is installed only in the main run loop, including menu tracking.
            MainActor.assumeIsolated { self?.tick() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .eventTracking)
    }

    // AppKit delivers these selector notifications synchronously on its main thread.
    @objc private func didBeginTracking(_ notification: Notification) {
        guard let root = notification.object as? NSMenu,
              root !== NSApp.mainMenu, root.supermenu == nil, menu == nil else { return }
        let titles = root.items.map(\.title)
        observedTitles.append(titles)
        guard titles == expectedTitles else { return }
        menu = root
        removeBeginObserver()
    }

    @objc private func didEndTracking(_ notification: Notification) {
        guard let root = notification.object as? NSMenu, root === menu else { return }
        trackingEnded = true
        trackingCompleted.resolve(.success(()))
        close()
    }

    private func tick() {
        if ContinuousClock.now >= deadline {
            timedOut = true
            if let menu {
                menu.cancelTrackingWithoutAnimation()
            } else {
                trackingCompleted.resolve(.failure(
                    AIDateIntegrationFixtureFailure.watchdog("owned native picker never began tracking")
                ))
                close()
            }
            return
        }
        guard let menu, !actionAttempted else { return }
        let matches = menu.items.enumerated().filter {
            $0.element.title == selectedTitle && $0.element.isEnabled && $0.element.menu === menu
        }
        guard matches.count == 1, let match = matches.first else {
            menu.cancelTrackingWithoutAnimation()
            return
        }
        actionAttempted = true
        menu.performActionForItem(at: match.offset)
        // The real native setter has returned; inspect ownership before yielding
        // or dismissing the menu. SwiftUI can defer presentation after AXPress.
        onAction?()
        menu.cancelTrackingWithoutAnimation()
    }

    func waitUntilTrackingEnds() async throws {
        do {
            try await trackingCompleted.wait()
        } catch {
            await trackingCompleted.drainWatchdogs()
            throw error
        }
        await trackingCompleted.drainWatchdogs()
    }

    private func removeBeginObserver() {
        NotificationCenter.default.removeObserver(
            self, name: NSMenu.didBeginTrackingNotification, object: nil
        )
    }

    func close() {
        if let menu, !trackingEnded { menu.cancelTrackingWithoutAnimation() }
        timer?.invalidate()
        timer = nil
        removeBeginObserver()
        NotificationCenter.default.removeObserver(
            self, name: NSMenu.didEndTrackingNotification, object: nil
        )
    }
}

struct PreferencesActionReceipts: Sendable {
    var displaySaves: [MenuBarDisplayOptions] = []
    var aiSaves: [Bool] = []
    var providerSaves: [AIProvider] = []
    var weekdaySaves: [Int] = []
    var menuNotifications = 0
    var calendarNotifications = 0
    var forbidden = 0
}

/// All storage/native effects are injected; the production controls and reducer stay real.
@MainActor
final class PreferencesAccessibilityFixture {
    let store: StoreOf<PreferencesFeature>
    let hotkey = HotkeyFixture()
    let hotkeyModel: HotkeyPreferencesModel
    let notifications = NotificationCenter()
    let receipts = LockIsolated(PreferencesActionReceipts())
    private var observers: [NSObjectProtocol] = []

    init(state: PreferencesFeature.State) {
        let receipts = receipts
        store = Store(initialState: state) { PreferencesFeature() } withDependencies: {
            $0.preferencesClient = .init(
                loadStartOfWeekday: { state.startOfWeekday },
                saveStartOfWeekday: { value in receipts.withValue { $0.weekdaySaves.append(value) } },
                loadWorkdays: { state.workdays },
                saveWorkdays: { _ in receipts.withValue { $0.forbidden += 1 } },
                loadDisplayOptions: { state.displayOptions },
                saveDisplayOptions: { value in receipts.withValue { $0.displaySaves.append(value) } },
                loadShowAISearch: { state.showAISearch },
                saveShowAISearch: { value in receipts.withValue { $0.aiSaves.append(value) } },
                loadAIProvider: { state.aiProvider },
                saveAIProvider: { value in receipts.withValue { $0.providerSaves.append(value) } }
            )
            $0.launchAtLoginClient = .init(
                status: { .notRegistered },
                setEnabled: { _ in receipts.withValue { $0.forbidden += 1 } }
            )
        }
        hotkeyModel = HotkeyPreferencesModel(
            hotkey: hotkey.hotkey, defaults: hotkey.defaults,
            handler: { receipts.withValue { $0.forbidden += 1 } }
        )
        observers = [
            notifications.addObserver(forName: .menuBarDisplayDidChange, object: nil, queue: nil) { _ in
                receipts.withValue { $0.menuNotifications += 1 }
            },
            notifications.addObserver(forName: .calendarPreferencesDidChange, object: nil, queue: nil) { _ in
                receipts.withValue { $0.calendarNotifications += 1 }
            },
        ]
    }

    func host() -> AccessibilityTestHost {
        AccessibilityTestHost(width: 268, height: 700) {
            PreferencesView(
                store: store, hotkeyPreferences: hotkeyModel,
                notificationCenter: notifications
            )
        }
    }

    func close() {
        for observer in observers { notifications.removeObserver(observer) }
        hotkey.cleanupDefaults()
    }
}
