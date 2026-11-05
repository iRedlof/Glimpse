import AppKit
import ComposableArchitecture
import GlimpseCore
import SwiftUI
import Testing
@testable import Glimpse

@Suite(.serialized)
@MainActor
struct PreferencesAccessibilityTests {
    @Test(arguments: [SettingsSection.menuBar, .calendar, .aiDateSearch])
    func nativeTitlesPreserveRolesAndSelectedValues(section: SettingsSection) async throws {
        var state = PreferencesFeature.State()
        state.startOfWeekday = 2
        state.aiProvider = .proxy
        state.displayOptions.showFilledBackground = true
        let fixture = PreferencesAccessibilityFixture(state: state)
        let host = fixture.host(section: section)
        defer { host.close(); fixture.close() }
        try await host.settle()
        switch section {
        case .menuBar, .aiDateSearch:
            let name = section == .menuBar ? "Filled background" : "Enable AI date search"
            let node = try host.control(named: name)
            #expect(node.role == .checkBox)
            #expect((node.value as? NSNumber)?.intValue == 1)
            if section == .aiDateSearch {
                let provider = try host.control(named: "AI provider")
                #expect(provider.role == .popUpButton)
                #expect(provider.value as? String == "Cloud AI")
            }
        case .calendar:
            let weekday = try host.control(named: "Week starts on")
            #expect(weekday.role == .popUpButton)
            #expect(weekday.value as? String == Calendar.current.weekdaySymbols[1])
        case .general:
                Issue.record("This role matrix covers the three categories with selected preference values")
        }
    }

    @Test(arguments: ["Icon", "Day of week", "Month", "Date", "Year"], [false, true])
    func displayCheckboxPressChangesOnlyItsOwnValue(pill: String, initial: Bool) async throws {
        let (name, keyPath) = pillContract(pill)
        var state = PreferencesFeature.State()
        state.displayOptions = .init(
            showIcon: false, showDayOfWeek: true, showMonth: false,
            showDate: true, showYear: false, showFilledBackground: true
        )
        state.displayOptions[keyPath: keyPath] = initial
        let fixture = PreferencesAccessibilityFixture(state: state)
        let host = fixture.host(section: .menuBar)
        defer { host.close(); fixture.close() }
        try await host.settle()
        let before = fixture.store.displayOptions
        let node = try #require(
            host.controls(named: name).first ?? host.controls(named: pill).first
        )
        #expect(node.role == .checkBox)
        #expect(node.label == name)
        #expect((node.value as? NSNumber)?.boolValue == initial)
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
        #expect((after.value as? NSNumber)?.boolValue == !initial)
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
        let host = fixture.host(section: .aiDateSearch)
        defer { host.close(); fixture.close() }
        try await host.settle()
        #expect(try host.control(named: "AI provider").value as? String == "Cloud AI")
        #expect(try host.control(named: "Enable AI date search").press())
        try await host.settle(until: { !fixture.store.showAISearch })
        #expect(host.controls(named: "AI provider").isEmpty)
        #expect(fixture.store.aiProvider == .proxy)
        #expect(try host.control(named: "Enable AI date search").press())
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
        let host = fixture.host(section: pickerName == "Week starts on" ? .calendar : .aiDateSearch)
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
        defer { fixture.close() }
        for section in SettingsSection.allCases {
            let host = fixture.host(section: section)
            defer { host.close() }
            try await host.settle()
            #expect(fixture.hotkey.backend.operations.isEmpty)
            #expect(fixture.receipts.value.forbidden == 0)
            #expect(fixture.receipts.value.displaySaves.isEmpty)
            #expect(fixture.receipts.value.aiSaves.isEmpty)
            #expect(fixture.receipts.value.providerSaves.isEmpty)
            #expect(fixture.receipts.value.weekdaySaves.isEmpty)
            #expect(fixture.receipts.value.menuNotifications == 0)
            #expect(fixture.receipts.value.calendarNotifications == 0)
            #expect(!host.window.isKeyWindow)
            #expect(!host.window.isMainWindow)
            #expect(!host.elements().isEmpty)
        }
    }

    @Test(arguments: [CGFloat(600), AppDesign.Settings.minimumContentSize.width], [false, true])
    func categorizedDocumentHasOrderedReachableNativeControls(width: CGFloat, showAI: Bool) async throws {
        var state = PreferencesFeature.State()
        state.showAISearch = showAI
        let fixture = PreferencesAccessibilityFixture(state: state)
        let isMinimum = width == AppDesign.Settings.minimumContentSize.width
        let host = fixture.documentHost(
            width: width, height: isMinimum ? AppDesign.Settings.minimumContentSize.height : 600
        )
        defer { host.close(); fixture.close() }
        try await host.settle()
        try host.loadAccessibilityWindowTree()
        try await host.settle()
        // Classic pane: no visible titles; each category is a labeled AXGroup.
        let headings = host.elements().filter(isSettingsSectionGroup)
        #expect(headings.map { $0.label ?? ($0.value as? String) ?? "" } ==
                ["Opening Glimpse", "Menu bar", "Calendar", "AI date search"])
        let scroll = try #require(accessibilityScrollView(in: host.hosting))
        let document = try #require(scroll.documentView)
        if isMinimum {
            #expect(document.frame.height > scroll.contentView.bounds.height)
        }
        #expect(!scroll.hasHorizontalScroller)
        // Native checkboxes keep AppKit's regular intrinsic height; every other
        // control keeps the 20pt target floor.
        let nativeCheckboxHeight = NSButton(checkboxWithTitle: "", target: nil, action: nil).fittingSize.height
        let nativeCheckboxes: Set<String> = [
            "Launch at login", "Global shortcut", "Show icon in menu bar", "Show day of week in menu bar",
            "Show month in menu bar", "Show date in menu bar", "Show year in menu bar",
            "Filled background", "Enable AI date search"
        ]
        let names = ["Launch at login", "Set and enable shortcut", "Global shortcut",
                     "Show icon in menu bar", "Show day of week in menu bar",
                     "Show month in menu bar", "Show date in menu bar", "Show year in menu bar",
                     "Filled background", "Week starts on"] +
            Calendar.current.weekdaySymbols.map { "\($0) workday" } +
            ["Enable AI date search"] + (showAI ? ["AI provider"] : [])
        for name in names {
            let node = try host.control(named: name)
            document.scrollToVisible(host.rect(node.frame, in: document))
            scroll.reflectScrolledClipView(scroll.contentView)
            try await host.settle()
            let current = try host.control(named: name)
            let clip = host.window.convertToScreen(
                scroll.contentView.convert(scroll.contentView.bounds, to: nil)
            )
            // Baseline-aligned rows land on fractional points; allow one device pixel of scroll rounding.
            let pixel = 1 / (host.window.backingScaleFactor > 0 ? host.window.backingScaleFactor : 1)
            #expect(clip.insetBy(dx: -pixel, dy: -pixel).contains(current.frame), "\(name) must be fully reachable")
            let minimumHeight: CGFloat = nativeCheckboxes.contains(name) ? nativeCheckboxHeight : 20
            #expect(current.frame.width > 0 && current.frame.height >= minimumHeight,
                    "\(name) target height \(current.frame.height) is below \(minimumHeight)")
            if nativeCheckboxes.contains(name) { #expect(current.role == .checkBox) }
            #expect(accessibilityScrollView(in: host.hosting) === scroll)
            #expect(scroll.documentView === document)
        }
        #expect(fixture.receipts.value.forbidden == 0)
        #expect(fixture.hotkey.backend.operations.isEmpty)
    }

    @Test(arguments: [
        LaunchAtLoginClient.Status.enabled, .notRegistered, .requiresApproval, .notFound, .unavailable
    ], [false, true])
    func startupStatusAndUpdatingKeepTruthfulRecovery(status: LaunchAtLoginClient.Status, updating: Bool) async throws {
        var state = PreferencesFeature.State()
        state.launchAtLoginStatus = status
        state.isUpdatingLaunchAtLogin = updating
        let fixture = PreferencesAccessibilityFixture(state: state)
        let host = fixture.host()
        defer { host.close(); fixture.close() }
        try await host.settle()
        let toggle = try host.control(named: "Launch at login")
        let recovery = [LaunchAtLoginClient.Status.requiresApproval, .notFound, .unavailable].contains(status)
        #expect(toggle.role == .checkBox)
        #expect(toggle.enabled == (!updating && !recovery))
        let recoveryNodes = host.controls(named: "Open Login Items in System Settings")
        #expect(recoveryNodes.count == (recovery ? 1 : 0))
        if recovery { #expect(recoveryNodes.first?.enabled == !updating) }
        let copy: String
        switch status {
        case .enabled: copy = "Enabled for your next login."
        case .notRegistered: copy = "Off. Glimpse won’t open automatically when you log in."
        case .requiresApproval: copy = "Approval required. Allow Glimpse in Login Items to launch at login."
        case .notFound: copy = "macOS couldn’t find Glimpse’s login item. Check that Glimpse is installed in Applications."
        case .unavailable: copy = "macOS couldn’t determine Glimpse’s login item status."
        }
        #expect((toggle.value as? NSNumber)?.boolValue == (status == .enabled))
        #expect(toggle.object.accessibilityValueDescription?() == copy)
        if updating || recovery {
            #expect(host.elements().contains {
                let text = $0.label ?? ($0.value as? String) ?? ""
                return text.contains(updating ? "Updating login item…" : copy)
            })
        }
        #expect(fixture.receipts.value.forbidden == 0)
    }

    @Test(arguments: [false, true])
    func emptyAndAllWorkdaysPersistOneCheckboxAtATime(all: Bool) async throws {
        var state = PreferencesFeature.State()
        state.workdays = all ? Set(1...7) : []
        let fixture = PreferencesAccessibilityFixture(state: state, allowWorkdayWrites: true)
        let host = fixture.host(section: .calendar)
        defer { host.close(); fixture.close() }
        try await host.settle()
        let before = state.workdays
        for weekday in 1...7 {
            let name = "\(Calendar.current.weekdaySymbols[weekday - 1]) workday"
            let node = try host.control(named: name)
            #expect(node.role == .checkBox)
            #expect(node.help == Calendar.current.weekdaySymbols[weekday - 1])
            #expect((node.value as? NSNumber)?.boolValue == all)
            #expect(node.press())
            try await host.settle(until: { fixture.receipts.value.calendarNotifications == weekday })
            var expected = before
            for changed in 1...weekday {
                if all { expected.remove(changed) } else { expected.insert(changed) }
            }
            #expect(fixture.store.workdays == expected)
            #expect(fixture.receipts.value.workdaySaves.last == expected)
            #expect(fixture.receipts.value.workdaySaves.count == weekday)
        }
        #expect(fixture.store.workdays == (all ? [] : Set(1...7)))
        #expect(fixture.receipts.value.menuNotifications == 0)
        #expect(fixture.receipts.value.forbidden == 0)
    }

    @Test(arguments: [false, true])
    func actualPreviewRetainsAllFieldsOffIconFallback(filled: Bool) async throws {
        var state = PreferencesFeature.State()
        state.displayOptions = .init(
            showIcon: false, showDayOfWeek: false, showMonth: false,
            showDate: false, showYear: false, showFilledBackground: filled
        )
        let fixture = PreferencesAccessibilityFixture(state: state)
        let host = fixture.host(section: .menuBar)
        defer { host.close(); fixture.close() }
        try await host.settle()
        let previews = host.elements().filter { $0.label == "Menu bar preview" }
        try #require(previews.count == 1)
        let preview = try #require(previews.first)
        let rawValue = preview.value
        let diagnostic: [String: Any] = [
            "method": "actualPreviewRetainsAllFieldsOffIconFallback", "filled": filled, "index": 0,
            "role": String((preview.role?.rawValue ?? "<nil>").prefix(200)),
            "class": String(String(reflecting: type(of: preview.object)).prefix(200)),
            "rawAXValue": String((rawValue.map { String(reflecting: $0) } ?? "<nil>").prefix(200)),
            "rawAXValueType": String((rawValue.map { String(reflecting: type(of: $0)) } ?? "<nil>").prefix(200)),
            "label": String((preview.label ?? "<nil>").prefix(200)),
            "help": String((preview.help ?? "<nil>").prefix(200)),
            "AXValueDescription": String((preview.object.accessibilityValueDescription?() ?? "<nil>").prefix(200))
        ]
        if let data = try? JSONSerialization.data(withJSONObject: diagnostic, options: [.sortedKeys]) {
            print("GLIMPSE_AX_DIAGNOSTIC \(String(decoding: data, as: UTF8.self))")
        }
        #expect(preview.role == .image)
        #expect(preview.label == "Menu bar preview")
        #expect((preview.value as? String) == "Calendar icon, \(filled ? "filled" : "bordered") background")
        func images(in view: NSView) -> [NSImageView] {
            (view as? NSImageView).map { [$0] } ?? view.subviews.flatMap { images(in: $0) }
        }
        let image = try #require(images(in: host.hosting).first?.image)
        #expect(image.size.width > 0 && image.size.height > 0)
        #expect(fixture.receipts.value.displaySaves.isEmpty)
    }

    private func pillContract(
        _ pill: String
    ) -> (String, WritableKeyPath<MenuBarDisplayOptions, Bool>) {
        switch pill {
        case "Icon": ("Show icon in menu bar", \.showIcon)
        case "Day of week": ("Show day of week in menu bar", \.showDayOfWeek)
        case "Month": ("Show month in menu bar", \.showMonth)
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
    var workdaySaves: [Set<Int>] = []
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

    init(state: PreferencesFeature.State, allowWorkdayWrites: Bool = false) {
        let receipts = receipts
        store = Store(initialState: state) { PreferencesFeature() } withDependencies: {
            $0.preferencesClient = .init(
                loadStartOfWeekday: { state.startOfWeekday },
                saveStartOfWeekday: { value in receipts.withValue { $0.weekdaySaves.append(value) } },
                loadWorkdays: { state.workdays },
                saveWorkdays: { value in
                    receipts.withValue {
                        $0.workdaySaves.append(value)
                        if !allowWorkdayWrites { $0.forbidden += 1 }
                    }
                },
                loadDisplayOptions: { state.displayOptions },
                saveDisplayOptions: { value in receipts.withValue { $0.displaySaves.append(value) } },
                loadShowAISearch: { state.showAISearch },
                saveShowAISearch: { value in receipts.withValue { $0.aiSaves.append(value) } },
                loadAIProvider: { state.aiProvider },
                saveAIProvider: { value in receipts.withValue { $0.providerSaves.append(value) } }
            )
            $0.launchAtLoginClient = .init(
                status: { state.launchAtLoginStatus },
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

    func host(section: SettingsSection = .general) -> AccessibilityTestHost {
        AccessibilityTestHost(width: 600, height: 600) {
            PreferencesView(
                store: store, hotkeyPreferences: hotkeyModel,
                notificationCenter: notifications, section: section
            )
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    func documentHost(width: CGFloat, height: CGFloat) -> AccessibilityTestHost {
        AccessibilityTestHost(width: width, height: height) {
            ScrollView(.vertical) {
                PreferencesView(
                    store: store, hotkeyPreferences: hotkeyModel,
                    notificationCenter: notifications
                )
                .padding(AppDesign.Settings.contentInset)
            }
        }
    }

    func close() {
        for observer in observers { notifications.removeObserver(observer) }
        hotkey.cleanupDefaults()
    }
}
