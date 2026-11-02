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
    static let hotkeyRecordingDidChange = Notification.Name("hotkeyRecordingDidChange")
}

@MainActor
final class CalendarStatusItem {
    private var statusItem: NSStatusItem?
    private var panel: CalendarPanel?
    private var midnightTimer: Timer?
    private var displayChangeObserver: Any?
    private var wakeObserver: Any?
    private var timeChangeObserver: Any?
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

    deinit {
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
        guard let panel else {
            showPanel()
            return
        }

        let isVisible = panel.occlusionState.contains(.visible) && panel.isVisible

        if isVisible {
            if !isOnSameScreen(panel) {
                panel.orderOut(nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.showPanel()
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

    private func showPanel() {
        guard let button = statusItem?.button,
              let buttonWindow = button.window
        else { return }

        let statusItemRect = buttonWindow.convertToScreen(
            button.convert(button.bounds, to: nil)
        )

        guard let screen = currentStatusItemScreen() ?? NSScreen.main else { return }

        let panelWidth = CalendarPanel.panelWidth
        let panelHeight = CalendarPanel.panelHeight
        let caretHeight = CalendarPanel.caretHeight
        let gapBelowMenuBar = CalendarPanel.gapBelowMenuBar
        let edgeMargin: CGFloat = 10

        var panelX = round(statusItemRect.midX - panelWidth / 2)
        let panelY = statusItemRect.minY - panelHeight - caretHeight - gapBelowMenuBar

        if panelX + panelWidth + edgeMargin > screen.frame.maxX {
            panelX = screen.frame.maxX - panelWidth - edgeMargin
        }
        if panelX < screen.frame.minX + edgeMargin {
            panelX = screen.frame.minX + edgeMargin
        }

        let caretOffset = max(16, min(statusItemRect.midX - panelX, panelWidth - 16))

        let contentRect = NSRect(
            x: panelX,
            y: panelY,
            width: panelWidth,
            height: panelHeight + caretHeight
        )

        if panel == nil {
            panel = CalendarPanel(contentRect: contentRect, caretOffset: caretOffset)
        } else {
            panel?.caretXOffset = caretOffset
        }

        panel?.setFrame(contentRect, display: true)
        panel?.makeKeyAndOrderFront(nil)
        panel?.prepareForReopen()
    }
}
