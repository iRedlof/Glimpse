import AppKit
import ComposableArchitecture
import GlimpseCore
import Observation
import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case general, menuBar, calendar, aiDateSearch

    var id: Self { self }

    var heading: String {
        switch self {
        case .general: "Opening Glimpse"
        case .menuBar: "Menu bar"
        case .calendar: "Calendar"
        case .aiDateSearch: "AI date search"
        }
    }
}

/// The retained Settings page always operates on its exact calendar partner.
@MainActor @Observable
final class SettingsCalendarActions {
    private(set) weak var calendar: CalendarPanel?

    var isPinned: Bool {
        get { calendar?.pinState ?? false }
        set { calendar?.setPinned(newValue) }
    }

    func bind(calendar: CalendarPanel?) {
        self.calendar = calendar
    }
}

/// Escape cancels only the Quit sheet it was created for. After the sheet ends, held-Escape
/// repeats aimed at the owner are consumed until release or a fresh key, so they cannot close Settings.
@MainActor
final class QuitSheetEscapeMonitor {
    private static let escapeKeyCode: UInt16 = 53
    private var token: Any?
    private weak var endedOwner: NSWindow?

    init(sheet: NSWindow, cancel: NSButton?) {
        token = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self, weak sheet, weak cancel] event in
            guard let self else { return event }
            if let owner = self.endedOwner {
                return self.filterAfterSheet(event, owner: owner)
            }
            guard let sheet, event.type == .keyDown, event.window === sheet,
                  Self.isPlainEscape(event) else { return event }
            if !event.isARepeat { cancel?.performClick(nil) }
            return nil
        }
    }

    /// Called from the sheet completion; keeps swallowing this press's repeats on `owner`.
    func sheetEnded(owner: NSWindow?) {
        guard let owner, token != nil else { return remove() }
        endedOwner = owner
    }

    func remove() {
        guard let token else { return }
        NSEvent.removeMonitor(token)
        self.token = nil
        endedOwner = nil
    }

    private func filterAfterSheet(_ event: NSEvent, owner: NSWindow) -> NSEvent? {
        if event.type == .keyDown, event.isARepeat, event.window === owner, Self.isPlainEscape(event) {
            return nil
        }
        if event.type == .keyDown || event.keyCode == Self.escapeKeyCode { remove() }
        return event
    }

    private static func isPlainEscape(_ event: NSEvent) -> Bool {
        event.keyCode == escapeKeyCode && event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function]).isEmpty
    }
}

/// Temporary ordering for one retained Settings/calendar pair.
@MainActor
final class SettingsCalendarPriority {
    /// Also retained by the panel so a replacement owner can settle pending
    /// disposal before admitting a new original level. All references back to
    /// windows are weak; this token never retains its coordinator.
    @MainActor
    final class Cleanup {
        struct LevelOverride {
            weak var settings: NSWindow?
            weak var calendar: CalendarPanel?
            let token = UUID()
            let original: NSWindow.Level
            let applied: NSWindow.Level
        }

        weak var settings: NSWindow?
        weak var calendar: CalendarPanel?
        var bindingID: UUID?
        var levelOverride: LevelOverride?
        var observers: [NSObjectProtocol] = []

        func restore() {
            guard let claim = levelOverride else { return }
            levelOverride = nil
            guard let calendar = claim.calendar, calendar === self.calendar,
                  claim.settings === settings,
                  calendar.settingsPriorityCleanup === self,
                  calendar.settingsPriorityLevelToken == claim.token else { return }
            calendar.settingsPriorityLevelToken = nil
            if calendar.level == claim.applied && calendar.level != claim.original {
                calendar.level = claim.original
            }
        }

        func invalidate() {
            bindingID = nil
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
            observers.removeAll()
            restore()
            if let calendar, calendar.settingsPriorityCleanup === self {
                calendar.settingsCalendarPriority = nil
                calendar.settingsPriorityCleanup = nil
            }
            settings = nil
            calendar = nil
        }
    }

    private let cleanup = Cleanup()
    private var settingsInteraction = false
    private var settingsUnavailable = false
    private var calendarUnavailable = false
    private var sheetInProgress = false
    private var latestInteractionChange = ContinuousClock.now

    private enum Observation: Sendable {
        case geometry, activation, calendarShown
    }

    deinit {
        // Global-actor types are Sendable. Copy this isolated cleanup token,
        // never self, into a one-shot task; no AppKit access occurs in deinit.
        // This does not require the newer isolated-deinit runtime.
        Task { @MainActor [cleanup] in cleanup.invalidate() }
    }

    func bind(settings: NSWindow, calendar: CalendarPanel?) {
        if cleanup.settings === settings, cleanup.calendar === calendar,
           calendar?.settingsCalendarPriority === self { return }
        invalidate()
        guard let calendar else { return }
        // A previous coordinator may already be gone with cleanup still queued.
        // Restore its claim now so normal is not mistaken for the original level.
        calendar.settingsCalendarPriority?.invalidate()
        calendar.settingsPriorityCleanup?.invalidate()
        cleanup.settings = settings
        cleanup.calendar = calendar
        cleanup.bindingID = UUID()
        calendar.settingsCalendarPriority = self
        calendar.settingsPriorityCleanup = cleanup
        sheetInProgress = settings.attachedSheet != nil
        for name in [
            NSWindow.didMoveNotification, NSWindow.didResizeNotification,
            NSWindow.didChangeScreenNotification, NSWindow.didChangeOcclusionStateNotification,
        ] {
            observe(name, object: calendar)
            observe(name, object: settings)
        }
        observe(NSWindow.didDeminiaturizeNotification, object: calendar, event: .calendarShown)
        observe(NSApplication.didResignActiveNotification, object: NSApp, event: .activation)
        observe(NSApplication.didBecomeActiveNotification, object: NSApp, event: .activation)
    }

    private func observe(_ name: Notification.Name, object: AnyObject, event: Observation = .geometry) {
        let bindingID = cleanup.bindingID
        let observer = NotificationCenter.default.addObserver(
            forName: name, object: object, queue: .main
        ) { [weak self] _ in
            let deliveredAt = ContinuousClock.now
            Task { @MainActor in
                guard let self, self.cleanup.bindingID == bindingID else { return }
                switch event {
                case .activation:
                    // A queued native notification cannot undo a newer delivered
                    // interaction (including opening an owned menu), nor can
                    // tasks delivered out of order restore an older owner.
                    guard deliveredAt >= self.latestInteractionChange else { return }
                    self.latestInteractionChange = deliveredAt
                    self.settingsInteraction = name == NSApplication.didBecomeActiveNotification
                        && NSApp.isActive && self.settingsOwnsInput
                case .calendarShown:
                    if let calendar = self.cleanup.calendar { self.calendarDidShow(calendar) }
                case .geometry:
                    break
                }
                self.reconcile()
            }
        }
        cleanup.observers.append(observer)
    }

    private var settingsOwnsInput: Bool {
        guard let settings = cleanup.settings else { return false }
        if settings.isKeyWindow && NSApp.keyWindow === settings { return true }
        guard let sheet = settings.attachedSheet else { return false }
        return sheet.isKeyWindow && NSApp.keyWindow === sheet
    }

    func settingsWasPresented() {
        discardSupersededLevel()
        latestInteractionChange = ContinuousClock.now
        settingsUnavailable = false
        settingsInteraction = true
        reconcile()
    }

    func settingsDidEnter() {
        guard NSApp.isActive, settingsOwnsInput else { return }
        discardSupersededLevel()
        latestInteractionChange = ContinuousClock.now
        settingsInteraction = true
        reconcile()
    }

    func settingsDidShow() {
        guard let settings = cleanup.settings, settings.isVisible, !settings.isMiniaturized else { return }
        settingsUnavailable = false
        settingsDidEnter()
        reconcile()
    }

    func settingsWillHide() {
        latestInteractionChange = ContinuousClock.now
        settingsUnavailable = true
        settingsInteraction = false
        cleanup.restore()
    }

    func settingsDidDeminiaturize() {
        settingsUnavailable = false
        settingsDidEnter()
    }

    func settingsWillBeginSheet() {
        sheetInProgress = true
        settingsDidEnter()
        reconcile()
    }

    func settingsDidEndSheet() {
        sheetInProgress = false
        settingsDidEnter()
        reconcile()
    }

    func calendarWillHide(_ calendar: CalendarPanel) {
        guard calendar === cleanup.calendar else { return }
        latestInteractionChange = ContinuousClock.now
        calendarUnavailable = true
        discardSupersededLevel()
        cleanup.restore()
    }

    func calendarDidShow(_ calendar: CalendarPanel) {
        guard calendar === cleanup.calendar, calendar.isVisible, !calendar.isMiniaturized else { return }
        calendarUnavailable = false
        reconcile()
    }

    func calendarRequestsPriority(_ calendar: CalendarPanel) -> Bool {
        guard calendar === cleanup.calendar, calendar.settingsCalendarPriority === self else { return true }
        guard calendarMayBecomeFront(calendar) else {
            reconcile()
            return false
        }
        latestInteractionChange = ContinuousClock.now
        settingsInteraction = false
        cleanup.restore()
        return true
    }

    /// Checks native modality without granting Calendar interaction intent.
    func calendarMayBecomeFront(_ calendar: CalendarPanel) -> Bool {
        guard calendar === cleanup.calendar, calendar.settingsCalendarPriority === self,
              let settings = cleanup.settings, settings.isVisible, !settings.isMiniaturized,
              !settingsUnavailable else { return true }
        return !sheetInProgress && settings.attachedSheet == nil
    }

    func reconcile() {
        guard !discardSupersededLevel() else { return }
        guard settingsInteraction, !settingsUnavailable, !calendarUnavailable,
              NSApp.isActive, let settings = cleanup.settings, let calendar = cleanup.calendar,
              settings.isVisible, !settings.isMiniaturized,
              calendar.isVisible, !calendar.isMiniaturized, calendar.isPinned,
              calendar.settingsCalendarPriority === self,
              calendar.settingsPriorityCleanup === cleanup else {
            cleanup.restore()
            return
        }
        if cleanup.levelOverride == nil {
            let claim = Cleanup.LevelOverride(
                settings: settings, calendar: calendar, original: calendar.level,
                applied: .init(rawValue: min(calendar.level.rawValue, NSWindow.Level.normal.rawValue))
            )
            cleanup.levelOverride = claim
            calendar.settingsPriorityLevelToken = claim.token
            if calendar.level != claim.applied { calendar.level = claim.applied }
        }
        // Read only the two known windows' order; never enumerate to find a pair.
        if calendar.level == settings.level, settings.windowNumber > 0,
           calendar.orderedIndex < settings.orderedIndex {
            calendar.order(.below, relativeTo: settings.windowNumber)
        }
    }

    @discardableResult
    private func discardSupersededLevel() -> Bool {
        guard let claim = cleanup.levelOverride, let calendar = cleanup.calendar,
              calendar.settingsPriorityLevelToken != claim.token || calendar.level != claim.applied
        else { return false }
        // Geometry/unpin callbacks discard this claim without re-admitting it.
        // A fresh Settings entry may subsequently capture the new original.
        latestInteractionChange = ContinuousClock.now
        settingsInteraction = false
        cleanup.restore()
        return true
    }

    func invalidate() {
        latestInteractionChange = ContinuousClock.now
        settingsInteraction = false
        settingsUnavailable = false
        calendarUnavailable = false
        sheetInProgress = false
        cleanup.invalidate()
    }
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    let store: StoreOf<PreferencesFeature>
    let hotkeyPreferences: HotkeyPreferencesModel
    let calendarPriority = SettingsCalendarPriority()
    let calendarActions = SettingsCalendarActions()
    private(set) var window: NSWindow?
    private let notificationCenter: NotificationCenter
    private let onAISettingsChange: (@MainActor (Bool, AIProvider) -> Void)?
    private let onAbout: @MainActor () -> Void
    private let onOpenCalendar: @MainActor () -> Void
    private let onQuit: @MainActor () -> Void
    /// Retained here: the sheet completion closure is released once it runs.
    private var quitEscapeMonitor: QuitSheetEscapeMonitor?
    private weak var minimumSizedContentView: NSView?
    private var minimumContentSizeConstraints: [NSLayoutConstraint] = []
    // Assigned once during initialization; NotificationCenter removal is thread-safe.
    nonisolated(unsafe) private var applicationObservers: [NSObjectProtocol] = []

    init(
        store: StoreOf<PreferencesFeature>? = nil,
        hotkeyPreferences: HotkeyPreferencesModel? = nil,
        notificationCenter: NotificationCenter = .default,
        onAISettingsChange: (@MainActor (Bool, AIProvider) -> Void)? = nil,
        onAbout: @escaping @MainActor () -> Void = { AboutWindow.show() },
        onOpenCalendar: @escaping @MainActor () -> Void = {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") else { return }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        },
        onQuit: @escaping @MainActor () -> Void = { NSApp.terminate(nil) }
    ) {
        self.store = store ?? Store(initialState: PreferencesFeature.State.live()) {
            PreferencesFeature()
        }
        self.hotkeyPreferences = hotkeyPreferences ?? HotkeyPreferencesModel()
        self.notificationCenter = notificationCenter
        self.onAISettingsChange = onAISettingsChange
        self.onAbout = onAbout
        self.onOpenCalendar = onOpenCalendar
        self.onQuit = onQuit
        super.init()
        applicationObservers = [
            notificationCenter.addObserver(
                forName: NSApplication.didResignActiveNotification, object: NSApp, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.cancelRecording() }
            },
            notificationCenter.addObserver(
                forName: NSApplication.didBecomeActiveNotification, object: NSApp, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.store.send(.refreshLaunchAtLogin) }
            },
        ]
    }

    deinit {
        for observer in applicationObservers {
            notificationCenter.removeObserver(observer)
        }
    }

    func show(visibleFrame: NSRect? = nil, avoiding: NSRect? = nil, calendar: CalendarPanel? = nil) {
        calendarActions.bind(calendar: calendar)
        if window == nil {
            let owner = SettingsWindow(
                contentRect: NSRect(origin: .zero, size: AppDesign.Settings.contentSize),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false
            )
            owner.title = "Glimpse Settings"
            owner.isReleasedWhenClosed = false
            owner.delegate = self
            owner.settingsController = self
            owner.level = .normal
            let hosting = NSHostingView(rootView: SettingsRootView(
                store: store, hotkeyPreferences: hotkeyPreferences,
                notificationCenter: notificationCenter, onAISettingsChange: onAISettingsChange,
                recordingWindow: { [weak self] in self?.window },
                calendarActions: calendarActions,
                about: { [weak self] in self?.onAbout() },
                openCalendar: { [weak self] in self?.onOpenCalendar() },
                requestQuit: { [weak self] in self?.requestQuit() }
            ))
            hosting.sizingOptions = []
            owner.contentView = hosting
            if let visibleFrame = visibleFrame ?? NSScreen.main?.visibleFrame {
                owner.setFrameOrigin(NSPoint(
                    x: visibleFrame.midX - owner.frame.width / 2,
                    y: visibleFrame.midY - owner.frame.height / 2
                ))
            } else {
                owner.center()
            }
            window = owner
        }
        if let owner = window { calendarPriority.bind(settings: owner, calendar: calendar) }
        if let owner = window,
           let bounds = visibleFrame ?? owner.screen?.visibleFrame ?? NSScreen.main?.visibleFrame {
            fit(owner, within: bounds, avoiding: avoiding)
        }
        // orderOut/orderFront reuse does not re-run SwiftUI onAppear.
        store.send(.onAppear)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        calendarPriority.settingsWasPresented()
    }

    func requestQuit() {
        guard let owner = window, owner.isVisible, owner.attachedSheet == nil else { return }
        cancelRecording()
        let alert = NSAlert()
        alert.messageText = "Quit Glimpse?"
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Quit")
        alert.buttons.last?.keyEquivalent = ""
        // Assigning defaultButtonCell rebinds Cancel's key equivalent to Return,
        // so Escape is routed by a monitor scoped to this sheet's window.
        alert.window.defaultButtonCell = alert.buttons.first?.cell as? NSButtonCell
        quitEscapeMonitor?.remove()
        let escape = QuitSheetEscapeMonitor(sheet: alert.window, cancel: alert.buttons.first)
        quitEscapeMonitor = escape
        alert.beginSheetModal(for: owner) { [weak self, weak owner] response in
            escape.sheetEnded(owner: owner)
            guard let self, let owner, self.window === owner,
                  response == .alertSecondButtonReturn else { return }
            self.onQuit()
        }
    }

    private func fit(_ owner: NSWindow, within bounds: NSRect, avoiding: NSRect? = nil) {
        let chrome = owner.frame.height - owner.contentRect(forFrameRect: owner.frame).height
        let usable = bounds.insetBy(dx: AppDesign.Settings.screenInset, dy: AppDesign.Settings.screenInset)
        let minimumContentSize = NSSize(
            width: min(AppDesign.Settings.minimumContentSize.width, max(1, usable.width)),
            height: min(AppDesign.Settings.minimumContentSize.height, max(1, usable.height - chrome))
        )
        applyMinimumContentSize(minimumContentSize, to: owner)
        let frame = SettingsWindowGeometry.placement(
            frame: owner.frame, visibleFrame: bounds, avoiding: avoiding
        )
        if owner.frame != frame { owner.setFrame(frame, display: true) }
    }

    private func applyMinimumContentSize(_ size: NSSize, to owner: NSWindow) {
        guard size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0, let content = owner.contentView else { return }
        // AppKit derives resizing limits from Auto Layout when it is active.
        // Keep the native content minimum independent of SwiftUI's measured size.
        if minimumSizedContentView !== content {
            NSLayoutConstraint.deactivate(minimumContentSizeConstraints)
            let width = content.widthAnchor.constraint(greaterThanOrEqualToConstant: size.width)
            let height = content.heightAnchor.constraint(greaterThanOrEqualToConstant: size.height)
            width.identifier = "Glimpse.Settings.minimumWidth"
            height.identifier = "Glimpse.Settings.minimumHeight"
            minimumContentSizeConstraints = [width, height]
            minimumSizedContentView = content
            NSLayoutConstraint.activate(minimumContentSizeConstraints)
        } else {
            for (constraint, value) in zip(minimumContentSizeConstraints, [size.width, size.height])
            where constraint.constant != value {
                constraint.constant = value
            }
        }
        if owner.contentMinSize != size { owner.contentMinSize = size }
    }

    func windowDidChangeScreen(_ notification: Notification) {
        guard let owner = notification.object as? NSWindow, owner === window,
              let bounds = owner.screen?.visibleFrame else { return }
        fit(owner, within: bounds)
        calendarPriority.reconcile()
    }

    func windowWillMiniaturize(_ notification: Notification) {
        guard notification.object as? NSWindow === window else { return }
        calendarPriority.settingsWillHide()
        cancelRecording()
    }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === window else { return }
        calendarPriority.settingsWillHide()
        cancelRecording()
        quitEscapeMonitor?.remove()
        quitEscapeMonitor = nil
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        guard notification.object as? NSWindow === window else { return }
        calendarPriority.settingsDidDeminiaturize()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard notification.object as? NSWindow === window else { return }
        calendarPriority.settingsDidEnter()
    }

    func windowWillBeginSheet(_ notification: Notification) {
        guard notification.object as? NSWindow === window else { return }
        calendarPriority.settingsWillBeginSheet()
    }

    func windowDidEndSheet(_ notification: Notification) {
        guard notification.object as? NSWindow === window else { return }
        calendarPriority.settingsDidEndSheet()
    }

    func windowDidResignKey(_ notification: Notification) {
        guard notification.object as? NSWindow === window else { return }
        cancelRecording()
    }

    func cancelRecording() {
        hotkeyPreferences.cancelRecording()
    }
}

@MainActor
final class SettingsWindow: NSWindow {
    weak var settingsController: SettingsWindowController?
    // Discovery stays bounded even if a future native control adds a large subtree.
    private static let focusRevealViewLimit = 256
    private var focusRevealGeneration = 0

    override func orderOut(_ sender: Any?) {
        focusRevealGeneration += 1
        settingsController?.calendarPriority.settingsWillHide()
        settingsController?.cancelRecording()
        super.orderOut(sender)
    }

    override func orderFront(_ sender: Any?) {
        super.orderFront(sender)
        settingsController?.calendarPriority.settingsDidShow()
    }

    override func makeKeyAndOrderFront(_ sender: Any?) {
        super.makeKeyAndOrderFront(sender)
        settingsController?.calendarPriority.settingsDidShow()
    }

    override func resignKey() {
        focusRevealGeneration += 1
        super.resignKey()
    }

    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        let previous = firstResponder
        let accepted = super.makeFirstResponder(responder)
        guard firstResponder !== previous else { return accepted }
        focusRevealGeneration += 1
        guard accepted, let current = firstResponder,
              ownsRevealFocus(current), let content = contentView else { return accepted }
        let generation = focusRevealGeneration
        DispatchQueue.main.async { [weak self, weak current, weak content] in
            guard let self, let current, let content,
                  self.focusRevealGeneration == generation, self.contentView === content,
                  self.ownsRevealFocus(current) else { return }
            content.layoutSubtreeIfNeeded()
            guard self.focusRevealGeneration == generation, self.contentView === content,
                  self.ownsRevealFocus(current) else { return }
            self.revealFocusedRow(in: content, responder: current, generation: generation)
        }
        return accepted
    }

    private func ownsRevealFocus(_ responder: NSResponder) -> Bool {
        isVisible && isKeyWindow && NSApp.isActive && NSApp.keyWindow === self
            && attachedSheet == nil && settingsController?.window === self
            && firstResponder === responder && (responder as? NSView)?.window === self
    }

    private func revealFocusedRow(in content: NSView, responder: NSResponder, generation: Int) {
        // Native focus remains available when SwiftUI's AX tree is inactive.
        // Use the current responder's view, never a cached accessibility target.
        guard let focused = responder as? NSView,
              focused.window === self, focused.isDescendant(of: content),
              isUsableRevealRect(focused.bounds),
              let scrollView = settingsScrollView(in: content),
              // Fixed chrome outside the scroll view (the utility footer) never scrolls settings.
              focused.isDescendant(of: scrollView),
              let document = scrollView.documentView,
              document.window === self, document.isDescendant(of: content),
              isUsableRevealRect(document.bounds) else { return }
        // SwiftUI key-view proxies can be siblings of the scroll document.
        // Same-window conversion keeps their current control bounds in document coordinates.
        let control = document.convert(focused.bounds, from: focused)
        guard isUsableRevealRect(control), document.bounds.contains(control) else { return }

        // Current rows center their labels beside a control in at least 28 points.
        // Full document width includes those labels without guessing an AX group.
        let rowHeight = max(control.height, AppDesign.Settings.minimumRowHeight)
        let row = NSRect(x: document.bounds.minX, y: control.midY - rowHeight / 2,
                         width: document.bounds.width, height: rowHeight)
            .insetBy(dx: 0, dy: -AppDesign.Spacing.sm).intersection(document.bounds)
        let clip = scrollView.contentView
        let target = clip.convert(row, from: document)
        guard isUsableRevealRect(row), document.bounds.contains(row),
              isUsableRevealRect(target), isUsableRevealRect(clip.bounds),
              focusRevealGeneration == generation, ownsRevealFocus(responder),
              contentView === content, content.window === self,
              focused.window === self, focused.isDescendant(of: content),
              focused.isDescendant(of: scrollView) else { return }
        var proposed = clip.bounds
        if target.minY < proposed.minY {
            proposed.origin.y = target.minY
        } else if target.maxY > proposed.maxY {
            proposed.origin.y = target.maxY - proposed.height
        } else {
            return
        }
        let y = clip.constrainBoundsRect(proposed).origin.y
        guard y.isFinite, y != clip.bounds.origin.y else { return }
        clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: y))
        scrollView.reflectScrolledClipView(clip)
    }

    private func settingsScrollView(in content: NSView) -> NSScrollView? {
        var pending = [content]
        var visited = 0
        var scrollView: NSScrollView?
        while let view = pending.popLast() {
            visited += 1
            guard visited + pending.count + view.subviews.count <= Self.focusRevealViewLimit
            else { return nil }
            if let candidate = view as? NSScrollView {
                guard scrollView == nil else { return nil }
                scrollView = candidate
            }
            pending.append(contentsOf: view.subviews)
        }
        return scrollView
    }

    private func isUsableRevealRect(_ rect: NSRect) -> Bool {
        [rect.minX, rect.minY, rect.maxX, rect.maxY].allSatisfy(\.isFinite)
            && rect.width > 0 && rect.height > 0
    }

    override func sendEvent(_ event: NSEvent) {
        super.sendEvent(event)
        guard event.window === self,
              [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type) else { return }
        settingsController?.calendarPriority.settingsDidEnter()
    }

    override func cancelOperation(_ sender: Any?) {
        guard isVisible, isKeyWindow, NSApp.keyWindow === self, attachedSheet == nil else { return }
        if settingsController?.hotkeyPreferences.isRecording == true {
            settingsController?.cancelRecording()
            return
        }
        performClose(sender)
    }
}

enum SettingsWindowGeometry {
    static func placement(
        frame: NSRect, visibleFrame: NSRect, avoiding: NSRect? = nil
    ) -> NSRect {
        guard [visibleFrame.minX, visibleFrame.minY, visibleFrame.width, visibleFrame.height,
               frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite),
              visibleFrame.width > 20, visibleFrame.height > 20,
              frame.width > 0, frame.height > 0 else { return frame }
        let usable = visibleFrame.insetBy(
            dx: AppDesign.Settings.screenInset, dy: AppDesign.Settings.screenInset
        )
        let size = NSSize(width: min(frame.width, usable.width), height: min(frame.height, usable.height))
        func clamped(_ origin: NSPoint) -> NSRect {
            NSRect(
                x: min(max(origin.x, usable.minX), usable.maxX - size.width),
                y: min(max(origin.y, usable.minY), usable.maxY - size.height),
                width: size.width, height: size.height
            )
        }
        let placed = clamped(frame.origin)
        guard let avoiding, placed.intersects(avoiding) else { return placed }
        let gap = AppDesign.Settings.windowGap
        let candidates = [
            NSPoint(x: avoiding.maxX + gap, y: placed.minY),
            NSPoint(x: avoiding.minX - size.width - gap, y: placed.minY),
            NSPoint(x: placed.minX, y: avoiding.minY - size.height - gap),
            NSPoint(x: placed.minX, y: avoiding.maxY + gap),
        ].map(clamped)
        return candidates.first { !$0.intersects(avoiding) } ?? placed
    }
}
