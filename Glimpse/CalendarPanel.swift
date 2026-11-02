import AppKit
import GlimpseCore
import SwiftUI

@MainActor
final class CalendarPanel: NSPanel {
    static let panelWidth: CGFloat = 316
    static let panelHeight: CGFloat = 420
    static let caretHeight: CGFloat = 12
    static let gapBelowMenuBar: CGFloat = 6

    var caretXOffset: CGFloat = 0
    var isPinned = false
    var isTextInputActive = false
    private var previousApp: NSRunningApplication?
    private let calendarStore: StoreOf<CalendarFeature>
    private var hostingView: NSHostingView<CalendarPopoverView>?
    private var sizeObservation: NSKeyValueObservation?  // invalidated on dealloc via ARC
    private var pendingResize: DispatchWorkItem?
    private var hasShownOnce = false

    init(contentRect: NSRect, caretOffset: CGFloat) {
        let store = Store(initialState: CalendarFeature.State()) {
            CalendarFeature()
        }
        self.calendarStore = store
        self.caretXOffset = caretOffset
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

        let popoverView = CalendarPopoverView(store: store, panel: self)
        let hosting = NSHostingView(rootView: popoverView)
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
    private func resizeToFitContent() {
        guard let hosting = hostingView else { return }
        let fittingSize = hosting.intrinsicContentSize
        guard fittingSize.height > 0, fittingSize.width > 0 else { return }

        let newHeight = min(fittingSize.height, screen?.visibleFrame.height ?? 800)
        let currentFrame = frame

        // Anchor to top: keep the top edge fixed, adjust origin.y downward
        let newY = currentFrame.maxY - newHeight
        let newFrame = NSRect(
            x: currentFrame.origin.x,
            y: newY,
            width: Self.panelWidth,
            height: newHeight
        )

        // Idempotency guard: bail if the frame is already effectively correct.
        // setFrame triggers a hosting-view layout pass, which re-emits the
        // intrinsicContentSize KVO that scheduled this call. Without this guard
        // the observe -> setFrame -> observe cycle never reaches a fixed point
        // and pegs the main thread at the debounce rate (~20 Hz). Comparing with
        // a sub-pixel tolerance lets the loop settle instead of spinning.
        let tolerance: CGFloat = 0.5
        if abs(newFrame.height - currentFrame.height) < tolerance
            && abs(newFrame.width - currentFrame.width) < tolerance
            && abs(newFrame.origin.y - currentFrame.origin.y) < tolerance {
            hasShownOnce = true
            return
        }

        // Skip animation on first show to avoid visible resize jump
        let shouldAnimate = hasShownOnce
        hasShownOnce = true
        setFrame(newFrame, display: true, animate: shouldAnimate)
    }

    /// Reset UI state when panel is re-shown.
    ///
    /// The panel is reused via orderOut/orderFront, so SwiftUI onAppear/onDisappear
    /// do not fire (see gotchas.md). This is the reliable hook to reset the reused
    /// TCA store: collapse preferences, return to the current month with today
    /// selected, and reload any preferences changed while hidden.
    func prepareForReopen() {
        calendarStore.send(.prepareForReopen)
        NotificationCenter.default.post(name: .calendarPanelDidShow, object: self)
    }

    override func orderOut(_ sender: Any?) {
        NotificationCenter.default.post(name: .calendarPanelWillHide, object: self)
        pendingResize?.cancel()
        isTextInputActive = false
        deactivateTextInput()
        super.orderOut(sender)
    }

    /// Activate the app so TextField can receive focus
    func activateForTextInput() {
        previousApp = NSWorkspace.shared.frontmostApplication
        NSApp.activate(ignoringOtherApps: true)
        makeKey()
    }

    /// Restore focus to the previous app
    func deactivateTextInput() {
        previousApp?.activate(options: .activateIgnoringOtherApps)
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
