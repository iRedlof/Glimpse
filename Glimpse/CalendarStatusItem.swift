import AppKit
import Carbon
import GlimpseCore

extension Notification.Name {
    /// Bridges PreferencesView display option changes to CalendarStatusItem (AppKit).
    /// TCA delegate actions handle state within SwiftUI; these notifications cross
    /// the SwiftUI → AppKit boundary where TCA stores are not shared.
    static let menuBarDisplayDidChange = Notification.Name("menuBarDisplayDidChange")
    static let calendarPreferencesDidChange = Notification.Name("calendarPreferencesDidChange")
    static let calendarPanelWillHide = Notification.Name("calendarPanelWillHide")
    static let calendarPanelDidShow = Notification.Name("calendarPanelDidShow")
    static let calendarPanelDidCompleteReopen = Notification.Name("calendarPanelDidCompleteReopen")
    static let calendarPanelWillPresentSettings = Notification.Name("calendarPanelWillPresentSettings")
    static let hotkeyRecordingDidChange = Notification.Name("hotkeyRecordingDidChange")
}

@MainActor
final class CalendarStatusItem {
    struct PanelAnchor {
        let statusItemFrame: NSRect
        let visibleFrame: NSRect
    }

    private var statusItem: NSStatusItem?
    private var panel: CalendarPanel?
    var requestSettings: (@MainActor () -> Void)?
    private let anchorProvider: (@MainActor () -> PanelAnchor?)?
    private let panelFactory: @MainActor (NSRect, CGFloat) -> CalendarPanel
    private let toggleVisibility: (@MainActor (CalendarPanel) -> Bool)?
    private let sameScreen: (@MainActor (CalendarPanel) -> Bool)?
    private let crossScreenScheduler: (@MainActor (@escaping @MainActor () -> Void) -> Void)?
    private var pendingCrossScreenShow: UUID?
    private var midnightTimer: Timer?
    private var displayChangeObserver: Any?
    private var wakeObserver: Any?
    private var timeChangeObserver: Any?
    // Set once on the main actor; the thread-safe removal happens in deinit.
    nonisolated(unsafe) private var screenParametersObserver: Any?
    // nonisolated(unsafe): only assigned once on the main actor in setup() and only
    // read in deinit; the opaque observer token is never mutated concurrently. This
    // lets the nonisolated deinit remove the observer without needing isolated deinit
    // (a newer runtime feature). removeObserver is itself thread-safe.
    nonisolated(unsafe) private var appearanceObserver: Any?
    // CalendarStatusItem uses .liveValue directly because it sits at the AppKit
    // boundary outside TCA's dependency graph. Extract pure logic (like nextMidnight)
    // into testable static methods instead of injecting clients here.
    private let preferencesClient = PreferencesClient.liveValue
    private let calendarClient = CalendarClient.liveValue

    init(
        anchorProvider: (@MainActor () -> PanelAnchor?)? = nil,
        panelFactory: @escaping @MainActor (NSRect, CGFloat) -> CalendarPanel = {
            CalendarPanel(contentRect: $0, caretOffset: $1)
        },
        toggleVisibility: (@MainActor (CalendarPanel) -> Bool)? = nil,
        sameScreen: (@MainActor (CalendarPanel) -> Bool)? = nil,
        crossScreenScheduler: (@MainActor (@escaping @MainActor () -> Void) -> Void)? = nil
    ) {
        self.anchorProvider = anchorProvider
        self.panelFactory = panelFactory
        self.toggleVisibility = toggleVisibility
        self.sameScreen = sameScreen
        self.crossScreenScheduler = crossScreenScheduler
    }

    deinit {
        if let screenParametersObserver {
            NotificationCenter.default.removeObserver(screenParametersObserver)
        }
        // CalendarStatusItem is a lifetime singleton, but remove the distributed
        // observer explicitly for correctness — block-based observers are retained
        // by the center until removed. removeObserver is thread-safe.
        if let appearanceObserver {
            DistributedNotificationCenter.default.removeObserver(appearanceObserver)
        }
    }

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.imagePosition = .imageOnly
        }

        // Re-render when the system switches between light and dark. We must NOT
        // observe the button's own effectiveAppearance via KVO: setting button.image
        // invalidates the bezel, which re-evaluates appearance, which re-fires the
        // observer — an observe→mutate→observe loop that pegs the CPU. The system's
        // distributed appearance notification does not reenter on our image update.
        appearanceObserver = DistributedNotificationCenter.default.addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: nil
        ) { [weak self] _ in
            // DistributedNotificationCenter delivers off the main thread; hop to
            // the main actor before touching UI. The notification can also arrive
            // before the button's effectiveAppearance flips, so re-render on the
            // next runloop tick to read the updated appearance.
            Task { @MainActor in
                self?.updateMenuBarDisplay()
            }
        }

        updateMenuBarDisplay()
        scheduleMidnightRefresh()
        registerGlobalHotkey()
        observeDisplayChanges()
        observeSystemEvents()
        AppLogger.statusItem.info("Status item configured")
    }

    private func observeDisplayChanges() {
        displayChangeObserver = NotificationCenter.default.addObserver(
            forName: .menuBarDisplayDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateMenuBarDisplay()
            }
        }
    }

    private func observeSystemEvents() {
        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshVisiblePanelPlacement() }
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateMenuBarDisplay()
                self?.scheduleMidnightRefresh()
                AppLogger.statusItem.info("Refreshed after wake")
            }
        }

        timeChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSSystemClockDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateMenuBarDisplay()
                self?.scheduleMidnightRefresh()
                AppLogger.statusItem.info("Refreshed after system clock change")
            }
        }
    }

    private func registerGlobalHotkey() {
        let enabled = UserDefaults.standard.object(forKey: "hotkeyEnabled") != nil
            ? UserDefaults.standard.bool(forKey: "hotkeyEnabled")
            : true

        guard enabled else {
            AppLogger.statusItem.info("Global hotkey disabled by user")
            return
        }

        let combo = HotkeyCombo.load()
        GlobalHotkey.shared.register(combo: combo) { [weak self] in
            self?.statusItemClicked()
        }
    }

    func updateMenuBarDisplay() {
        guard let button = statusItem?.button else { return }

        let options = preferencesClient.loadDisplayOptions()
        let dateString = calendarClient.menuBarDateString(Date(), options)
        let isDark = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        // Composite the entire item (border, fill, icon, separator, text) into the
        // button's own image. No custom subview — that drives a redraw loop on
        // macOS 26 (see MenuBarItemRenderer).
        let image = MenuBarItemRenderer.render(
            options: options, dateString: dateString, isDark: isDark
        )
        button.image = image
        statusItem?.length = image.size.width
        // Status-item layout applies the image width on the next runloop tick.
        DispatchQueue.main.async { [weak self] in
            self?.refreshVisiblePanelPlacement()
        }
    }

    /// Compute the next midnight (00:00:01) after the given date.
    /// Visible for testing.
    nonisolated static func nextMidnight(after date: Date, calendar: Calendar = .current) -> Date? {
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: date),
              let midnight = calendar.date(bySettingHour: 0, minute: 0, second: 1, of: tomorrow)
        else { return nil }
        return midnight
    }

    private func scheduleMidnightRefresh() {
        midnightTimer?.invalidate()

        guard let midnight = Self.nextMidnight(after: Date()) else {
            AppLogger.statusItem.error("Failed to compute next midnight for refresh")
            return
        }

        let timer = Timer(fire: midnight, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.updateMenuBarDisplay()
                self?.scheduleMidnightRefresh()
                AppLogger.statusItem.info("Midnight refresh completed")
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        midnightTimer = timer
    }

    @objc func statusItemClicked() {
        pendingCrossScreenShow = nil
        guard let panel else {
            showPanel()
            return
        }

        let isVisible = toggleVisibility?(panel)
            ?? (panel.occlusionState.contains(.visible) && panel.isVisible)

        if isVisible {
            if !(sameScreen?(panel) ?? isOnSameScreen(panel)) {
                let requestID = UUID()
                pendingCrossScreenShow = requestID
                panel.orderOut(nil)
                let completion: @MainActor () -> Void = { [weak self] in
                    guard let self, self.pendingCrossScreenShow == requestID else { return }
                    self.pendingCrossScreenShow = nil
                    do {
                        try self.showCalendar()
                    } catch {
                        AppLogger.statusItem.error("Cannot show calendar: \(error.localizedDescription, privacy: .public)")
                    }
                }
                if let crossScreenScheduler {
                    crossScreenScheduler(completion)
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { completion() }
                }
                return
            }

            if !panel.isPinned {
                panel.orderOut(nil)
            }
        } else {
            showPanel()
        }
    }

    /// Explicit Show preserves an ordered-in panel even when another window occludes it.
    func showCalendar() throws {
        pendingCrossScreenShow = nil
        if let panel, panel.settingsCalendarPriority?.calendarRequestsPriority(panel) == false { return }
        if let panel, panel.isVisible {
            if let anchor = currentPanelAnchor() {
                panel.updatePlacement(
                    statusItemFrame: anchor.statusItemFrame, visibleFrame: anchor.visibleFrame
                )
            }
            panel.makeKeyAndOrderFront(nil)
            return
        }
        try presentHiddenPanel()
    }

    func prepareForSettingsPresentation() -> (
        visibleFrame: NSRect?, avoiding: NSRect?, calendar: CalendarPanel?
    ) {
        pendingCrossScreenShow = nil
        let placement = (
            currentPanelAnchor()?.visibleFrame,
            panel?.isVisible == true && panel?.isPinned == true ? panel?.frame : nil,
            panel
        )
        panel?.prepareForSettingsPresentation()
        return placement
    }

    func synchronizeAISettings(enabled: Bool, preference: AIProvider) {
        panel?.aiSettingsDidChange?(enabled, preference)
    }

    private func isOnSameScreen(_ panel: CalendarPanel) -> Bool {
        guard let panelScreen = panel.screen,
              let currentScreen = currentStatusItemScreen()
        else { return true }
        return NSEqualRects(panelScreen.frame, currentScreen.frame)
    }

    private func currentStatusItemScreen() -> NSScreen? {
        guard let button = statusItem?.button,
              let buttonWindow = button.window
        else { return NSScreen.main }

        let buttonRect = buttonWindow.convertToScreen(
            button.convert(button.bounds, to: nil)
        )

        let testPoint = NSPoint(x: buttonRect.midX, y: buttonRect.origin.y - 100)
        return NSScreen.screens.first { $0.frame.contains(testPoint) } ?? NSScreen.main
    }

    private func currentPanelAnchor() -> PanelAnchor? {
        if let anchorProvider { return anchorProvider() }
        guard let button = statusItem?.button,
              let buttonWindow = button.window
        else { return nil }

        let statusItemRect = buttonWindow.convertToScreen(
            button.convert(button.bounds, to: nil)
        )
        guard let screen = currentStatusItemScreen() ?? NSScreen.main else { return nil }
        return PanelAnchor(statusItemFrame: statusItemRect, visibleFrame: screen.visibleFrame)
    }

    private func showPanel() {
        do {
            try presentHiddenPanel()
        } catch {
            AppLogger.statusItem.error("Cannot show calendar: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func presentHiddenPanel() throws {
        guard let anchor = currentPanelAnchor() else { throw CalendarShowError.unavailableAnchor }
        guard let placement = PanelGeometry.placement(
            statusItemFrame: anchor.statusItemFrame, visibleFrame: anchor.visibleFrame,
            desiredHeight: panel?.layoutState.totalHeight
                ?? CalendarPanel.panelHeight + CalendarPanel.caretHeight
        ) else {
            throw CalendarShowError.invalidGeometry
        }
        let calendarPanel: CalendarPanel
        if let panel {
            calendarPanel = panel
        } else {
            calendarPanel = panelFactory(placement.frame, placement.caretXOffset)
            panel = calendarPanel
            calendarPanel.requestSettings = { [weak self] in self?.requestSettings?() }
        }
        guard calendarPanel.settingsCalendarPriority?.calendarRequestsPriority(calendarPanel) != false else { return }
        calendarPanel.prepareForReopen()
        calendarPanel.updatePlacement(
            statusItemFrame: anchor.statusItemFrame, visibleFrame: anchor.visibleFrame
        )
        calendarPanel.makeKeyAndOrderFront(nil)
        calendarPanel.completeReopenPresentation()
    }

    /// Refresh an already visible panel without sending the reopen/reset action.
    private func refreshVisiblePanelPlacement() {
        guard let panel, panel.isVisible,
              let button = statusItem?.button, let buttonWindow = button.window,
              let screen = currentStatusItemScreen()
        else { return }
        let statusItemRect = buttonWindow.convertToScreen(
            button.convert(button.bounds, to: nil)
        )
        panel.updatePlacement(statusItemFrame: statusItemRect, visibleFrame: screen.visibleFrame)
    }
}
