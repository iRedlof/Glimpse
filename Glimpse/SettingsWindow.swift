import AppKit
import ComposableArchitecture
import GlimpseCore
import Observation
import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case general, menuBar, calendar, aiDateSearch

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .menuBar: "Menu bar"
        case .calendar: "Calendar"
        case .aiDateSearch: "AI date search"
        }
    }

    var heading: String { self == .general ? "Opening Glimpse" : title }
}

@MainActor
@Observable
final class SettingsSelection {
    var section = SettingsSection.general
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    let store: StoreOf<PreferencesFeature>
    let hotkeyPreferences: HotkeyPreferencesModel
    let selection = SettingsSelection()
    private(set) var window: NSWindow?
    private let notificationCenter: NotificationCenter
    private let onAISettingsChange: (@MainActor (Bool, AIProvider) -> Void)?
    // Assigned once during initialization; NotificationCenter removal is thread-safe.
    nonisolated(unsafe) private var applicationObservers: [NSObjectProtocol] = []

    init(
        store: StoreOf<PreferencesFeature>? = nil,
        hotkeyPreferences: HotkeyPreferencesModel? = nil,
        notificationCenter: NotificationCenter = .default,
        onAISettingsChange: (@MainActor (Bool, AIProvider) -> Void)? = nil
    ) {
        self.store = store ?? Store(initialState: PreferencesFeature.State.live()) {
            PreferencesFeature()
        }
        self.hotkeyPreferences = hotkeyPreferences ?? HotkeyPreferencesModel()
        self.notificationCenter = notificationCenter
        self.onAISettingsChange = onAISettingsChange
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

    func show(visibleFrame: NSRect? = nil, avoiding: NSRect? = nil) {
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
                store: store, hotkeyPreferences: hotkeyPreferences, selection: selection,
                notificationCenter: notificationCenter, onAISettingsChange: onAISettingsChange,
                selectSection: { [weak self] in self?.select($0) },
                recordingWindow: { [weak self] in self?.window }
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
        if let owner = window,
           let bounds = visibleFrame ?? owner.screen?.visibleFrame ?? NSScreen.main?.visibleFrame {
            fit(owner, within: bounds, avoiding: avoiding)
        }
        // orderOut/orderFront reuse does not re-run SwiftUI onAppear.
        store.send(.onAppear)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func fit(_ owner: NSWindow, within bounds: NSRect, avoiding: NSRect? = nil) {
        let chrome = owner.frame.height - owner.contentRect(forFrameRect: owner.frame).height
        let usable = bounds.insetBy(dx: AppDesign.Settings.screenInset, dy: AppDesign.Settings.screenInset)
        owner.contentMinSize = NSSize(
            width: min(AppDesign.Settings.minimumContentSize.width, max(1, usable.width)),
            height: min(AppDesign.Settings.minimumContentSize.height, max(1, usable.height - chrome))
        )
        let frame = SettingsWindowGeometry.placement(
            frame: owner.frame, visibleFrame: bounds, avoiding: avoiding
        )
        if owner.frame != frame { owner.setFrame(frame, display: true) }
    }

    func windowDidChangeScreen(_ notification: Notification) {
        guard let owner = notification.object as? NSWindow, owner === window,
              let bounds = owner.screen?.visibleFrame else { return }
        fit(owner, within: bounds)
    }

    func select(_ section: SettingsSection) {
        if selection.section == .general && section != .general {
            cancelRecording()
        }
        selection.section = section
    }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === window else { return }
        cancelRecording()
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

    override func orderOut(_ sender: Any?) {
        settingsController?.cancelRecording()
        super.orderOut(sender)
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
