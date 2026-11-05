import AppKit
import GlimpseCore
import SwiftUI

@MainActor
final class CalendarPanel: NSPanel {
    static let panelWidth = PanelGeometry.panelWidth
    static let panelHeight: CGFloat = 420
    static let caretHeight = PanelGeometry.caretHeight
    static let gapBelowMenuBar = PanelGeometry.gapBelowMenuBar

    let layoutState = PanelLayoutState()

    var caretXOffset: CGFloat {
        get { layoutState.caretXOffset }
        set {
            layoutState.updatePlacement(
                maximumHeight: layoutState.maximumHeight, caretXOffset: newValue
            )
        }
    }
    var isPinned = false {
        didSet {
            guard isPinned != oldValue else { return }
            settingsCalendarPriority?.reconcile()
        }
    }

    var pinState: Bool { calendarStore.isPinned }
    static let hidePreservesContextKey = "Glimpse.CalendarPanel.hidePreservesContext"
    /// One-shot: the next hide keeps month/date (a later explicit reopen resets them).
    private var preservesContextOnNextHide = false

    func setPinned(_ pinned: Bool) {
        if calendarStore.isPinned != pinned { calendarStore.send(.togglePin) }
        isPinned = pinned
        if !pinned && isVisible && !isKeyWindow && !isTextInputActive {
            preservesContextOnNextHide = true
            orderOut(nil)
        }
    }

    weak var settingsCalendarPriority: SettingsCalendarPriority?
    var settingsPriorityCleanup: SettingsCalendarPriority.Cleanup?
    var settingsPriorityLevelToken: UUID?
    var isTextInputActive = false
    var aiSettingsDidChange: (@MainActor (Bool, AIProvider) -> Void)?
    var requestSettings: (@MainActor () -> Void)?
    private var previousApp: NSRunningApplication?
    private let capturePreviousApp: @MainActor () -> NSRunningApplication?
    private let restorePreviousApp: @MainActor (NSRunningApplication) -> Void
    private let calendarStore: StoreOf<CalendarFeature>
    private var hostingView: NSHostingView<AnyView>?
    private var sizeObservation: NSKeyValueObservation?  // invalidated on dealloc via ARC
    private var pendingResize: DispatchWorkItem?
    private var hasShownOnce = false
    private var statusItemFrame: NSRect?
    private var visibleFrame: NSRect?
    private var pendingReopenPresentation = false

    convenience init(contentRect: NSRect, caretOffset: CGFloat) {
        let store = Store(initialState: CalendarFeature.State()) {
            CalendarFeature()
        }
        self.init(contentRect: contentRect, caretOffset: caretOffset, calendarStore: store)
    }

    init(contentRect: NSRect, caretOffset: CGFloat, calendarStore store: StoreOf<CalendarFeature>,
         content: ((PanelLayoutState) -> AnyView)? = nil,
         capturePreviousApp: @escaping @MainActor () -> NSRunningApplication? = {
             NSWorkspace.shared.frontmostApplication
         },
         restorePreviousApp: @escaping @MainActor (NSRunningApplication) -> Void = {
             $0.activate(options: .activateIgnoringOtherApps)
         }) {
        self.calendarStore = store
        self.capturePreviousApp = capturePreviousApp
        self.restorePreviousApp = restorePreviousApp
        layoutState.updatePlacement(
            maximumHeight: layoutState.maximumHeight, caretXOffset: caretOffset
        )
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        level = .init(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)))
        hasShadow = true
        isMovableByWindowBackground = false
        becomesKeyOnlyIfNeeded = false
        collectionBehavior = [.moveToActiveSpace]
        animationBehavior = .utilityWindow

        let root = content?(layoutState)
            ?? AnyView(CalendarPopoverView(store: store, panel: self, layout: layoutState))
        let hosting = NSHostingView(rootView: root)
        hosting.frame = contentRect
        contentView = hosting
        hostingView = hosting

        // KVO on intrinsicContentSize is not formally documented as KVO-compliant,
        // but NSHostingView emits KVO notifications for it in practice (macOS 14+).
        // This is the only reliable way to detect SwiftUI content size changes from
        // the AppKit side. If a future macOS breaks this, the panel will simply stop
        // auto-resizing and remain at its initial size — a graceful degradation.
        sizeObservation = hosting.observe(\.intrinsicContentSize, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                self?.scheduleResizeToFitContent()
            }
        }
    }

    func updatePlacement(statusItemFrame: NSRect, visibleFrame: NSRect) {
        guard let placement = PanelGeometry.placement(
            statusItemFrame: statusItemFrame, visibleFrame: visibleFrame,
            desiredHeight: layoutState.naturalContentHeight + Self.caretHeight
        ) else {
            AppLogger.general.error("Ignoring invalid panel anchor or visible bounds")
            return
        }
        self.statusItemFrame = statusItemFrame
        self.visibleFrame = visibleFrame
        layoutState.updatePlacement(
            maximumHeight: placement.maximumHeight, caretXOffset: placement.caretXOffset
        )
        applyFrame(placement.frame)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// Debounce rapid intrinsicContentSize changes to avoid animation flicker.
    private func scheduleResizeToFitContent() {
        pendingResize?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.resizeToFitContent()
        }
        pendingResize = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
    }

    /// Resize the panel to fit the hosting view's intrinsic content size,
    /// anchored to the top (menu bar edge). Width is always fixed at panelWidth.
    func resizeToFitContent() {
        guard let hosting = hostingView else { return }
        let fittingSize = hosting.intrinsicContentSize
        guard fittingSize.height.isFinite, fittingSize.height > 0,
              fittingSize.width.isFinite, fittingSize.width > 0
        else {
            AppLogger.general.error("Ignoring invalid panel intrinsic size")
            return
        }
        guard let statusItemFrame, let visibleFrame else { return }
        updatePlacement(statusItemFrame: statusItemFrame, visibleFrame: visibleFrame)
        hasShownOnce = true
    }

    private func applyFrame(_ newFrame: NSRect) {
        // All components participate, including x after a status item/screen change.
        // A frame update can emit another intrinsic-size observation; unchanged
        // geometry terminates that feedback loop.
        if PanelGeometry.framesMatch(newFrame, frame) {
            return
        }
        // Initial placement does not spend the first-resize animation exemption.
        let shouldAnimate = hasShownOnce && isVisible
        setFrame(newFrame, display: true, animate: shouldAnimate)
    }

    /// Reset UI state when panel is re-shown.
    ///
    /// The panel is reused via orderOut/orderFront, so SwiftUI onAppear/onDisappear
    /// do not fire (see gotchas.md). This is the reliable hook to reset the reused
    /// TCA store: collapse preferences, return to the current month with today
    /// selected, and reload any preferences changed while hidden.
    func prepareForReopen() {
        guard !isVisible else { return }
        pendingReopenPresentation = true
        // Owned SwiftUI bindings dismiss first, before native key presentation.
        calendarStore.send(.prepareForReopen)
        NotificationCenter.default.post(name: .calendarPanelDidShow, object: self)
    }

    /// Finish only a prepared hidden session, after normal key presentation.
    /// A refused or redirected native focus request remains a reported failure.
    @discardableResult
    func completeReopenPresentation() -> Bool {
        guard pendingReopenPresentation, isVisible, isKeyWindow, NSApp.keyWindow === self else {
            return false
        }
        let accepted = makeFirstResponder(nil)
        guard accepted, firstResponder === self else {
            AppLogger.general.error("Calendar reopen did not establish window-default focus")
            return false
        }
        pendingReopenPresentation = false
        NotificationCenter.default.post(name: .calendarPanelDidCompleteReopen, object: self)
        return true
    }

    override func orderOut(_ sender: Any?) {
        let preservesContext = preservesContextOnNextHide
        preservesContextOnNextHide = false
        settingsCalendarPriority?.calendarWillHide(self)
        NotificationCenter.default.post(
            name: .calendarPanelWillHide, object: self,
            userInfo: [Self.hidePreservesContextKey: preservesContext]
        )
        makeFirstResponder(nil)
        pendingReopenPresentation = false
        pendingResize?.cancel()
        isTextInputActive = false
        deactivateTextInput()
        super.orderOut(sender)
    }

    override func close() {
        settingsCalendarPriority?.calendarWillHide(self)
        super.close()
    }

    override func miniaturize(_ sender: Any?) {
        settingsCalendarPriority?.calendarWillHide(self)
        super.miniaturize(sender)
    }

    override func deminiaturize(_ sender: Any?) {
        guard settingsCalendarPriority?.calendarMayBecomeFront(self) != false else { return }
        super.deminiaturize(sender)
        settingsCalendarPriority?.calendarDidShow(self)
    }

    override func orderFront(_ sender: Any?) {
        guard settingsCalendarPriority?.calendarMayBecomeFront(self) != false else { return }
        super.orderFront(sender)
        settingsCalendarPriority?.calendarDidShow(self)
    }

    override func makeKeyAndOrderFront(_ sender: Any?) {
        guard settingsCalendarPriority?.calendarMayBecomeFront(self) != false else { return }
        super.makeKeyAndOrderFront(sender)
        settingsCalendarPriority?.calendarDidShow(self)
    }

    override func makeKey() {
        guard settingsCalendarPriority?.calendarMayBecomeFront(self) != false else { return }
        super.makeKey()
    }

    override func sendEvent(_ event: NSEvent) {
        let priority = settingsCalendarPriority
        let bindingID = settingsPriorityCleanup?.bindingID
        super.sendEvent(event)
        guard let priority, priority === settingsCalendarPriority,
              bindingID == settingsPriorityCleanup?.bindingID,
              event.window === self, isVisible,
              [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type),
              (isKeyWindow && NSApp.keyWindow === self)
                || (isMainWindow && NSApp.mainWindow === self) else { return }
        // Only delivered input can transfer ownership. Native menu tracking can
        // consume its dismissal click without ever dispatching it to this panel.
        _ = priority.calendarRequestsPriority(self)
    }

    func prepareForSettingsPresentation() {
        // This is an internal transition; restoring another app would steal
        // focus from the Settings window. Ordinary dismissal keeps its lease.
        previousApp = nil
        NotificationCenter.default.post(name: .calendarPanelWillPresentSettings, object: self)
        isTextInputActive = false
        makeFirstResponder(nil)
        if !isPinned { orderOut(nil) }
    }

    /// Activate the app so TextField can receive focus
    func activateForTextInput() {
        guard settingsCalendarPriority?.calendarMayBecomeFront(self) != false else { return }
        previousApp = capturePreviousApp()
        NSApp.activate(ignoringOtherApps: true)
        makeKey()
    }

    /// Restore focus to the previous app
    func deactivateTextInput() {
        if let previousApp { restorePreviousApp(previousApp) }
        previousApp = nil
    }

    override func resignKey() {
        super.resignKey()
        if !isPinned && !isTextInputActive {
            deactivateTextInput()
            orderOut(nil)
        }
    }
}
