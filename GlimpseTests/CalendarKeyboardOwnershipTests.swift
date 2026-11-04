import AppKit
import ApplicationServices
import ComposableArchitecture
import GlimpseCore
import SwiftUI
import Testing

@testable import Glimpse

/// Owned key windows are opt-in so ordinary concurrent AX hosts cannot steal keys.
@Suite(.serialized, .enabled(if:
    ProcessInfo.processInfo.environment["GLIMPSE_CALENDAR_KEYBOARD_ACCEPTANCE"] == "1"
))
@MainActor
struct CalendarKeyboardOwnershipTests {
    @Test
    func settingsNativeTraversalAndActivation() async throws {
        let calendar = try CalendarKeyboardRootFixture()
        let settings = SettingsWindowTestFixture()
        defer { settings.close(); calendar.close() }
        try await calendar.openThroughShowOwner()
        calendar.panel.isPinned = true
        calendar.store.send(.togglePin)
        let placement = calendar.showOwner.prepareForSettingsPresentation()
        // Observe the ordinary production root before the fixture's AX replacement.
        settings.controller.show(visibleFrame: placement.visibleFrame, avoiding: placement.avoiding, calendar: placement.calendar)
        let ordinaryOwner = try #require(settings.controller.window)
        let ordinaryRoot = try #require(ordinaryOwner.contentView as? NSHostingView<SettingsRootView>)
        for afterLayout in [false, true] {
            if afterLayout { await settings.settle() }
            let constraints = ordinaryRoot.constraints.filter {
                $0.identifier?.hasPrefix("Glimpse.Settings.minimum") == true
            }.prefix(2).map {
                ($0.identifier ?? "", $0.firstAttribute.rawValue, $0.relation.rawValue,
                 $0.constant, $0.isActive, $0.firstItem as? NSView === ordinaryRoot)
            }
            print("GLIMPSE_SETTINGS_ORDINARY_INITIAL_LAYOUT stage=\(afterLayout ? "after" : "before")-first-fixture-settle-after-public-show contentMinSize=\(ordinaryOwner.contentMinSize) constraints=\(constraints) rootIsWindowContent=\(ordinaryOwner.contentView === ordinaryRoot) rootClass=\(String(reflecting: type(of: ordinaryRoot))) rootBounds=\(ordinaryRoot.bounds) windowFrame=\(ordinaryOwner.frame) keyWindowOwned=\(NSApp.keyWindow === ordinaryOwner)")
        }
        let ordinaryContentSize = ordinaryOwner.contentRect(forFrameRect: ordinaryOwner.frame).size
        ordinaryOwner.setContentSize(NSSize(width: 400, height: 250))
        await settings.settle()
        #expect(ordinaryOwner.contentRect(forFrameRect: ordinaryOwner.frame).size == NSSize(width: 520, height: 360))
        #expect(settings.controller.window === ordinaryOwner && ordinaryOwner.contentView === ordinaryRoot)
        print("GLIMPSE_SETTINGS_ORDINARY_RESIZE_FLOOR requested=(400,250) actual=\(ordinaryOwner.contentRect(forFrameRect: ordinaryOwner.frame).size) contentMinSize=\(ordinaryOwner.contentMinSize) rootBounds=\(ordinaryRoot.bounds)")
        ordinaryOwner.setContentSize(ordinaryContentSize)
        await settings.settle()
        #expect(ordinaryOwner.contentRect(forFrameRect: ordinaryOwner.frame).size == ordinaryContentSize)
        #expect(settings.controller.window === ordinaryOwner && ordinaryOwner.contentView === ordinaryRoot)
        var ordinaryProviderObserved = false
        let ordinaryInitialViewport = try #require(accessibilityScrollView(in: ordinaryRoot))
        let ordinaryInitialDocument = try #require(ordinaryInitialViewport.documentView)
        let ordinaryInitialVisibleRect = ordinaryInitialDocument.convert(
            ordinaryInitialViewport.contentView.bounds, from: ordinaryInitialViewport.contentView
        )
        var ordinaryAdmittedTargets = 0
        var ordinaryLowerRowObserved = false
        for step in 0..<40 {
            let ordinaryClipXBeforeTab = ordinaryInitialViewport.contentView.bounds.origin.x
            try calendar.send(.tab, toWindow: ordinaryOwner)
            await settings.settle()
            let nativeFocused = ordinaryRoot.accessibilityFocusedUIElement
            let ownedNativeTarget = nativeFocused.flatMap { object -> AccessibilityTestNode? in
                let node = AccessibilityTestNode(object: object as AnyObject)
                guard node.object.accessibilityWindow?() as? NSWindow === ordinaryOwner else { return nil }
                return node
            }
            let ordinaryNodes = settings.nodes()
            let provider = ordinaryNodes.first { $0.role == .popUpButton && $0.label == "AI provider" }
            let rowLabel = ordinaryNodes.first {
                $0.role == .staticText && ($0.label == "Provider" || ($0.value as? String) == "Provider")
            }
            let viewport = accessibilityScrollView(in: ordinaryRoot)
            let proxyFrame = (ordinaryOwner.firstResponder as? NSView).flatMap { view -> NSRect? in
                guard view.window === ordinaryOwner else { return nil }
                return ordinaryOwner.convertToScreen(view.convert(view.bounds, to: nil))
            }
            let providerFocused = provider?.object.isAccessibilityFocused?() == true ||
                (ownedNativeTarget?.role == .popUpButton && ownedNativeTarget?.label == "AI provider")
            ordinaryProviderObserved = ordinaryProviderObserved || providerFocused
            var admittedControl: NSRect?
            var admittedRow: NSRect?
            var controlVisible = false
            var rowVisible = false
            let responderView = ordinaryOwner.firstResponder as? NSView
            let document = viewport?.documentView
            let responderDescendsFromDocument = responderView.flatMap { view in
                document.map { view.isDescendant(of: $0) }
            } ?? false
            let responderDescendsFromRoot = responderView?.isDescendant(of: ordinaryRoot) ?? false
            let rawDocumentControl = responderView.flatMap { view -> NSRect? in
                guard view.window === ordinaryOwner, ordinaryOwner.firstResponder === view,
                      settings.controller.window === ordinaryOwner, ordinaryOwner.contentView === ordinaryRoot,
                      ordinaryRoot.window === ordinaryOwner, let document, document.window === ordinaryOwner else {
                    return nil
                }
                return document.convert(view.bounds, from: view)
            }
            if let responderView, let viewport, let document,
               let control = rawDocumentControl,
               settings.controller.window === ordinaryOwner, ordinaryOwner.contentView === ordinaryRoot,
               ordinaryRoot.window === ordinaryOwner, ordinaryOwner.firstResponder === responderView,
               responderView.window === ordinaryOwner, document.window === ordinaryOwner,
               document.isDescendant(of: ordinaryRoot), responderDescendsFromRoot {
                let row = NSRect(x: document.bounds.minX, y: control.midY - max(control.height, 28) / 2,
                                 width: document.bounds.width, height: max(control.height, 28))
                    .insetBy(dx: 0, dy: -8).intersection(document.bounds)
                let controlInClip = viewport.contentView.convert(control, from: document)
                let rowInClip = viewport.contentView.convert(row, from: document)
                let rects = [responderView.bounds, document.bounds, control, row,
                             controlInClip, rowInClip, viewport.contentView.bounds]
                let finitePositive = rects.allSatisfy {
                    [$0.minX, $0.minY, $0.maxX, $0.maxY].allSatisfy(\.isFinite) &&
                        $0.width > 0 && $0.height > 0
                }
                if finitePositive && document.bounds.contains(control) && document.bounds.contains(row) {
                    admittedControl = control
                    admittedRow = row
                    controlVisible = viewport.contentView.bounds.contains(controlInClip)
                    rowVisible = viewport.contentView.bounds.contains(rowInClip)
                    ordinaryAdmittedTargets += 1
                    let lowerRow = document.isFlipped
                        ? control.maxY > ordinaryInitialVisibleRect.maxY
                        : control.minY < ordinaryInitialVisibleRect.minY
                    ordinaryLowerRowObserved = ordinaryLowerRowObserved || lowerRow
                }
            }
            print("GLIMPSE_SETTINGS_ORDINARY_ROOT step=\(step) providerAXPresent=\(provider != nil) providerFocused=\(providerFocused) providerAXFrame=\(String(describing: provider?.frame)) rowLabelAXPresent=\(rowLabel != nil) rowLabelAXFrame=\(String(describing: rowLabel?.frame)) responderClass=\(ordinaryOwner.firstResponder.map { NSStringFromClass(type(of: $0)) } ?? "nil") responderViewOwned=\(responderView?.window === ordinaryOwner) responderBounds=\(String(describing: responderView?.bounds)) responderDescendsFromDocument=\(responderDescendsFromDocument) responderDescendsFromRoot=\(responderDescendsFromRoot) rawDocumentControl=\(String(describing: rawDocumentControl)) proxyFrame=\(String(describing: proxyFrame)) admittedControl=\(String(describing: admittedControl)) admittedRow28Plus8=\(String(describing: admittedRow)) controlVisible=\(controlVisible) rowVisible=\(rowVisible) nativeTargetOwned=\(ownedNativeTarget != nil) nativeTargetClass=\(ownedNativeTarget.map { String(reflecting: type(of: $0.object)) } ?? "nil") nativeTargetLabel=\(String((ownedNativeTarget?.label ?? "<nil>").prefix(200))) nativeTargetFrame=\(String(describing: ownedNativeTarget?.frame)) contentMinSize=\(ordinaryOwner.contentMinSize) rootBounds=\(ordinaryRoot.bounds) documentBounds=\(String(describing: document?.bounds)) clipBounds=\(String(describing: viewport?.contentView.bounds)) clipXBeforeTab=\(ordinaryClipXBeforeTab) clipXAfterTab=\(String(describing: viewport?.contentView.bounds.origin.x))")
            #expect(settings.controller.window === ordinaryOwner && ordinaryOwner.contentView === ordinaryRoot)
            #expect(admittedControl != nil, "Every completed ordinary Tab target must satisfy owned native document/control admission")
            #expect(viewport?.contentView.bounds.origin.x == ordinaryClipXBeforeTab)
            if admittedControl != nil {
                #expect(controlVisible && rowVisible)
            }
            if providerFocused { break }
        }
        #expect(ordinaryAdmittedTargets > 0 && ordinaryLowerRowObserved)
        print("GLIMPSE_SETTINGS_ORDINARY_ROOT_SUMMARY providerObserved=\(ordinaryProviderObserved) admittedTargets=\(ordinaryAdmittedTargets) lowerRowObserved=\(ordinaryLowerRowObserved) replacementProof=false")
        try await settings.open(visibleFrame: placement.visibleFrame, avoiding: placement.avoiding, calendar: placement.calendar)
        let owner = try #require(settings.controller.window)
        let traversalViewport = owner.contentView.flatMap { accessibilityScrollView(in: $0) }
        try #require(owner.makeFirstResponder(nil))
        calendar.clearActionReceipts()
        func focusedLabels() -> [String] {
            settings.nodes().filter { $0.object.isAccessibilityFocused?() == true }
                .compactMap(\.label)
        }
        try calendar.send(.tab, toWindow: owner)
        await settings.settle()
        print("GLIMPSE_SETTINGS_FOCUS first-tab=\(focusedLabels()) full-access=\(NSApp.isFullKeyboardAccessEnabled)")
        #expect(focusedLabels().contains("Launch at login"))
        let loginBefore = settings.login.requests.value.count
        let initialLogin = settings.nodes().first { $0.role == .checkBox && $0.label == "Launch at login" }
        try #require(owner.isKeyWindow && NSApp.keyWindow === owner)
        #expect(initialLogin?.enabled == true && !settings.store.isUpdatingLaunchAtLogin)
        print("GLIMPSE_SETTINGS_LOGIN_FOCUS stage=before-update updating=\(settings.store.isUpdatingLaunchAtLogin) loginEnabled=\(initialLogin?.enabled == true) keyWindowOwned=\(NSApp.keyWindow === owner) responderOwned=\(owner.firstResponder === owner || (owner.firstResponder as? NSView)?.window === owner) focusedLabels=\(Array(focusedLabels().prefix(8)))")
        let targetsBeforeUpdate = settings.nodes().filter { $0.object.isAccessibilityFocused?() == true }.prefix(8)
            .map { ($0.label ?? "", $0.frame) }
        print("GLIMPSE_SETTINGS_NATIVE_FOCUS stage=before-update responderClass=\(owner.firstResponder.map { NSStringFromClass(type(of: $0)) } ?? "nil") responderIsView=\(owner.firstResponder is NSView) responderViewOwned=\((owner.firstResponder as? NSView)?.window === owner) targets=\(targetsBeforeUpdate) clipOrigin=\(String(describing: traversalViewport?.contentView.bounds.origin)) clipSize=\(String(describing: traversalViewport?.contentView.bounds.size))")
        try calendar.send(.space, toWindow: owner)
        await settings.settle()
        #expect(settings.login.requests.value.count == loginBefore + 1)
        let updatingLogin = settings.nodes().first { $0.role == .checkBox && $0.label == "Launch at login" }
        #expect(updatingLogin?.enabled == false && settings.store.isUpdatingLaunchAtLogin)
        #expect(owner.isKeyWindow && NSApp.keyWindow === owner && owner.firstResponder === owner)
        print("GLIMPSE_SETTINGS_LOGIN_FOCUS stage=updating updating=\(settings.store.isUpdatingLaunchAtLogin) loginEnabled=\(updatingLogin?.enabled == true) keyWindowOwned=\(NSApp.keyWindow === owner) responderOwned=\(owner.firstResponder === owner || (owner.firstResponder as? NSView)?.window === owner) focusedLabels=\(Array(focusedLabels().prefix(8)))")
        let targetsWhileUpdating = settings.nodes().filter { $0.object.isAccessibilityFocused?() == true }.prefix(8)
            .map { ($0.label ?? "", $0.frame) }
        print("GLIMPSE_SETTINGS_NATIVE_FOCUS stage=updating responderClass=\(owner.firstResponder.map { NSStringFromClass(type(of: $0)) } ?? "nil") responderIsView=\(owner.firstResponder is NSView) responderViewOwned=\((owner.firstResponder as? NSView)?.window === owner) targets=\(targetsWhileUpdating) clipOrigin=\(String(describing: traversalViewport?.contentView.bounds.origin)) clipSize=\(String(describing: traversalViewport?.contentView.bounds.size))")
        settings.login.finish()
        await settings.settle()
        let completedLogin = settings.nodes().first { $0.role == .checkBox && $0.label == "Launch at login" }
        #expect(completedLogin?.enabled == true && !settings.store.isUpdatingLaunchAtLogin)
        #expect(owner.isKeyWindow && NSApp.keyWindow === owner && owner.firstResponder === owner)
        print("GLIMPSE_SETTINGS_LOGIN_FOCUS stage=completed updating=\(settings.store.isUpdatingLaunchAtLogin) loginEnabled=\(completedLogin?.enabled == true) keyWindowOwned=\(NSApp.keyWindow === owner) responderOwned=\(owner.firstResponder === owner || (owner.firstResponder as? NSView)?.window === owner) focusedLabels=\(Array(focusedLabels().prefix(8)))")
        let targetsAfterUpdate = settings.nodes().filter { $0.object.isAccessibilityFocused?() == true }.prefix(8)
            .map { ($0.label ?? "", $0.frame) }
        print("GLIMPSE_SETTINGS_NATIVE_FOCUS stage=completed responderClass=\(owner.firstResponder.map { NSStringFromClass(type(of: $0)) } ?? "nil") responderIsView=\(owner.firstResponder is NSView) responderViewOwned=\((owner.firstResponder as? NSView)?.window === owner) targets=\(targetsAfterUpdate) clipOrigin=\(String(describing: traversalViewport?.contentView.bounds.origin)) clipSize=\(String(describing: traversalViewport?.contentView.bounds.size))")
        try calendar.send(.tab, toWindow: owner)
        await settings.settle()
        print("GLIMPSE_SETTINGS_FOCUS recovered-login-tab=\(focusedLabels())")
        #expect(focusedLabels().contains("Launch at login"))
        #expect(owner.isKeyWindow && NSApp.keyWindow === owner)
        try settings.expectVisible(try #require(settings.nodes().first {
            $0.role == .checkBox && $0.label == "Launch at login"
        }), rowLabel: "Launch at login")
        try calendar.send(.tab, toWindow: owner)
        await settings.settle()
        print("GLIMPSE_SETTINGS_FOCUS next-tab-recorder=\(focusedLabels())")
        #expect(focusedLabels().contains("Set and enable shortcut"))
        try calendar.send(.backTab, toWindow: owner)
        await settings.settle()
        #expect(focusedLabels().contains("Launch at login"))
        try settings.expectVisible(try #require(settings.nodes().first {
            $0.role == .checkBox && $0.label == "Launch at login"
        }), rowLabel: "Launch at login")
        var traversed: [String] = []
        for step in 0..<40 {
            try calendar.send(.tab, toWindow: owner)
            await settings.settle()
            traversed.append(contentsOf: focusedLabels())
            for target in settings.nodes().filter({ $0.object.isAccessibilityFocused?() == true }).prefix(8) {
                let rowLabel: String?
                switch target.label {
                case "Set and enable shortcut": rowLabel = "Global shortcut"
                case "Show icon in menu bar": rowLabel = nil
                case "Week starts on": rowLabel = "Week starts on"
                case "Enable AI date search": rowLabel = "Enable AI date search"
                case "AI provider": rowLabel = "Provider"
                default: continue
                }
                try settings.expectVisible(target, rowLabel: rowLabel)
            }
            if step < 8 || focusedLabels().contains("AI provider") {
                let observedProvider = settings.nodes().first { $0.label == "AI provider" && $0.role == .popUpButton }
                var providerContained = false
                if let observedProvider, let content = owner.contentView,
                   let viewport = accessibilityScrollView(in: content) {
                    providerContained = viewport.contentView.bounds.contains(
                        viewport.contentView.convert(owner.convertFromScreen(observedProvider.frame), from: nil)
                    )
                }
                print("GLIMPSE_SETTINGS_TAB_OBSERVATION step=\(step) loginFocused=\(focusedLabels().contains("Launch at login")) recorderFocused=\(focusedLabels().contains("Set and enable shortcut")) providerFocused=\(focusedLabels().contains("AI provider")) providerPresent=\(observedProvider != nil) providerFullyContained=\(providerContained)")
                let focusedTargets = settings.nodes().filter { $0.object.isAccessibilityFocused?() == true }.prefix(8)
                    .map { ($0.label ?? "", $0.frame) }
                print("GLIMPSE_SETTINGS_NATIVE_FOCUS stage=tab-\(step) responderClass=\(owner.firstResponder.map { NSStringFromClass(type(of: $0)) } ?? "nil") responderIsView=\(owner.firstResponder is NSView) responderViewOwned=\((owner.firstResponder as? NSView)?.window === owner) targets=\(focusedTargets) clipOrigin=\(String(describing: traversalViewport?.contentView.bounds.origin)) clipSize=\(String(describing: traversalViewport?.contentView.bounds.size))")
                let rowLabel = settings.nodes().first {
                    $0.role == .staticText && ($0.label == "Provider" || ($0.value as? String) == "Provider")
                }
                let proxyFrame = (owner.firstResponder as? NSView).flatMap { view -> NSRect? in
                    guard view.window === owner else { return nil }
                    return owner.convertToScreen(view.convert(view.bounds, to: nil))
                }
                print("GLIMPSE_SETTINGS_REPLACEMENT_GEOMETRY step=\(step) proxyFrame=\(String(describing: proxyFrame)) providerAXFrame=\(String(describing: observedProvider?.frame)) rowLabelAXPresent=\(rowLabel != nil) rowLabelAXFrame=\(String(describing: rowLabel?.frame)) documentBounds=\(String(describing: traversalViewport?.documentView?.bounds)) clipBounds=\(String(describing: traversalViewport?.contentView.bounds)) contentMinSize=\(owner.contentMinSize)")
            }
            if focusedLabels().contains("AI provider") { break }
        }
        let ordered = ["Set and enable shortcut", "Show icon in menu bar",
                       "Week starts on", "Enable AI date search", "AI provider"]
        let positions = try ordered.map { name in try #require(traversed.firstIndex(of: name)) }
        #expect(positions == positions.sorted())
        let provider = try #require(settings.nodes().first { $0.label == "AI provider" && $0.role == .popUpButton })
        try settings.expectVisible(provider, rowLabel: "Provider")
        let reverseOrdered = ["AI provider", "Enable AI date search", "Week starts on",
                              "Show icon in menu bar", "Set and enable shortcut", "Launch at login"]
        var reverseTraversed = focusedLabels()
        try #require(reverseTraversed.contains("AI provider"))
        for _ in 0..<40 {
            try calendar.send(.backTab, toWindow: owner)
            await settings.settle()
            reverseTraversed.append(contentsOf: focusedLabels())
            for target in settings.nodes().filter({ $0.object.isAccessibilityFocused?() == true }).prefix(8) {
                let rowLabel: String?
                switch target.label {
                case "AI provider": rowLabel = "Provider"
                case "Enable AI date search": rowLabel = "Enable AI date search"
                case "Week starts on": rowLabel = "Week starts on"
                case "Show icon in menu bar": rowLabel = nil
                case "Set and enable shortcut": rowLabel = "Global shortcut"
                case "Launch at login": rowLabel = "Launch at login"
                default: continue
                }
                try settings.expectVisible(target, rowLabel: rowLabel)
            }
            if focusedLabels().contains("Launch at login") { break }
        }
        let reversePositions = try reverseOrdered.map { name in
            try #require(reverseTraversed.firstIndex(of: name))
        }
        #expect(reversePositions == reversePositions.sorted())
        #expect(focusedLabels().contains("Launch at login"))
        #expect(owner.isVisible && NSApp.keyWindow === owner)
        #expect(calendar.actions.isEmpty)
        #expect(settings.hotkey.backend.operations.isEmpty)
    }

    @Test
    func settingsPopupEscapePreservesSelectionAndWindow() async throws {
        let settings = SettingsWindowTestFixture()
        defer { settings.close() }
        let visible = try #require(NSScreen.screens.first).visibleFrame
        try await settings.open(visibleFrame: visible)
        try await settings.reveal(.calendar)
        try settings.loadAccessibilityWindowTree()
        let owner = try #require(settings.controller.window)
        let popup = try #require(settings.nodes().first {
            $0.role == .popUpButton && $0.label == "Week starts on"
        })
        try #require((popup.object.accessibilityWindow?() as? NSWindow) === owner)
        let before = settings.saved.value
        let dismissal = SettingsPopupEscape(owner: owner, expectedTitles: Calendar.current.weekdaySymbols)
        defer { dismissal.close() }
        try #require(popup.press())
        await settings.settle()
        #expect(dismissal.postedOwnedEscape)
        #expect(dismissal.trackingEnded && !dismissal.timedOut)
        #expect(settings.saved.value == before)
        #expect(owner.isVisible && NSApp.keyWindow === owner)
        #expect(settings.nodes().contains { $0.role == .popUpButton && $0.label == "Week starts on" })
    }

    @Test(arguments: ["escape", "recorderThenEscape", "closeButton", "commandW"])
    func settingsNativeCloseLeavesCalendarUntouched(boundary: String) async throws {
        let calendar = try CalendarKeyboardRootFixture(maximumHeight: 300)
        let settings = SettingsWindowTestFixture()
        defer { settings.close(); calendar.close() }
        try await calendar.openThroughShowOwner()
        calendar.panel.isPinned = true
        calendar.store.send(.togglePin)
        calendar.store.send(.goToNextMonth)
        await calendar.settleRendering()
        let frame = calendar.panel.frame
        let month = calendar.store.displayedMonth
        let session = calendar.presentationSnapshot?.keyboardSession
        let reopened = calendar.reopenActions.value
        let placement = calendar.showOwner.prepareForSettingsPresentation()
        try await settings.open(visibleFrame: placement.visibleFrame, avoiding: placement.avoiding, calendar: placement.calendar)
        let owner = try #require(settings.controller.window)
        calendar.clearActionReceipts()
        switch boundary {
        case "recorderThenEscape":
            try await settings.startRecording()
            try calendar.send(.escape, toWindow: owner)
            await settings.settle()
            #expect(!settings.model.isRecording)
            #expect(owner.isVisible && NSApp.keyWindow === owner)
            try calendar.send(.escape, toWindow: owner)
        case "escape": try calendar.send(.escape, toWindow: owner)
        case "closeButton":
            let button = try #require(owner.standardWindowButton(.closeButton))
            button.performClick(nil)
        case "commandW":
            func closeCommands(_ menu: NSMenu) -> [NSMenuItem] {
                menu.items.flatMap { item in
                    (item.keyEquivalent == "w" &&
                        item.keyEquivalentModifierMask.intersection([.command, .shift, .option, .control]) == .command
                        ? [item] : []) +
                        (item.submenu.map(closeCommands) ?? [])
                }
            }
            let commands = NSApp.mainMenu.map(closeCommands) ?? []
            print("GLIMPSE_SETTINGS_CLOSE_MENU \(commands.map { "\($0.title):enabled=\($0.isEnabled)" })")
            #expect(commands.count == 1)
            try calendar.send(.closeShortcut, toWindow: owner)
        default: Issue.record("Unknown native Settings close boundary")
        }
        await settings.settle()
        #expect(!owner.isVisible)
        #expect(!settings.model.isRecording)
        #expect(calendar.panel.isVisible && calendar.panel.frame == frame)
        #expect(calendar.store.displayedMonth == month)
        #expect(calendar.presentationSnapshot?.keyboardSession == session)
        #expect(calendar.reopenActions.value == reopened)
        #expect(calendar.actions.isEmpty)
        #expect(calendar.previousAppRestorations == 0)
        #expect(settings.hotkey.backend.operations.isEmpty)
    }

    @Test(arguments: [false, true], [false, true])
    func settingsCategoriesAndRecoveryRemainReachable(constrained: Bool, dark: Bool) async throws {
        let settings = SettingsWindowTestFixture()
        defer { settings.close() }
        let available = try #require(NSScreen.screens.first).visibleFrame
        let visible = constrained
            ? NSRect(x: available.midX - 250, y: available.midY - 160, width: 500, height: 320)
            : available
        try await settings.open(visibleFrame: visible)
        let owner = try #require(settings.controller.window)
        owner.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let frame = owner.frame
        let constrainedRoot = try #require(owner.contentView)
        let minimumConstraints = constrainedRoot.constraints.filter {
            $0.identifier?.hasPrefix("Glimpse.Settings.minimum") == true
        }.prefix(2).map {
            ($0.identifier ?? "", $0.firstAttribute.rawValue, $0.relation.rawValue,
             $0.constant, $0.isActive, $0.firstItem as? NSView === constrainedRoot)
        }
        print("GLIMPSE_SETTINGS_CONSTRAINED_BOUNDS constrained=\(constrained) dark=\(dark) requestedBounds=\(visible) windowFrame=\(frame) contentMinSize=\(owner.contentMinSize) constraints=\(minimumConstraints) rootOwned=\(constrainedRoot.window === owner)")
        let saved = settings.saved.value
        let suffix = "\(constrained ? "constrained" : "nominal")-\(dark ? "dark" : "light")"
        for section in SettingsSection.allCases {
            try await settings.reveal(section)
            try settings.loadAccessibilityWindowTree()
            #expect(owner.frame == frame)
            #expect(settings.saved.value == saved)
            try settings.saveBitmap(name: "settings-\(section.rawValue)-\(suffix)")
        }
        let searchToggle = try #require(settings.nodes().first {
            $0.label == "Enable AI date search" && $0.role == .checkBox
        })
        try #require((searchToggle.value as? NSNumber)?.boolValue == true)
        let enabledSwitch = try settings.aiSwitchBitmap()
        try #require(searchToggle.press())
        try await settings.settleAISwitch(expected: false, changedFrom: enabledSwitch)
        try settings.loadAccessibilityWindowTree()
        #expect(!settings.store.showAISearch)
        #expect(settings.nodes().allSatisfy { $0.label != "AI provider" })
        #expect(owner.frame == frame)
        try settings.saveBitmap(name: "settings-aiDateSearch-off-\(suffix)")
        let restoredToggle = try #require(settings.nodes().first {
            $0.label == "Enable AI date search" && $0.role == .checkBox
        })
        try #require((restoredToggle.value as? NSNumber)?.boolValue == false)
        let disabledSwitch = try settings.aiSwitchBitmap()
        try #require(restoredToggle.press())
        try await settings.settleAISwitch(expected: true, changedFrom: disabledSwitch)
        try settings.loadAccessibilityWindowTree()
        #expect(settings.store.showAISearch)
        #expect(settings.nodes().contains { $0.label == "AI provider" })
        #expect(owner.frame == frame)
        #expect(settings.saved.value == saved)
        try await settings.reveal(.general)
        settings.saved.withValue { $0.launchAtLoginStatus = .notFound }
        settings.store.send(.setLaunchAtLogin(true))
        await settings.settle()
        try #require(settings.login.requests.value == [true])
        settings.login.finish(error: NSError(
            domain: "GlimpseTests.SettingsLogin", code: 1,
            userInfo: [NSLocalizedDescriptionKey:
                "macOS could not register Glimpse’s login item. Check that Glimpse is installed in Applications, allow it in Login Items, then reopen Settings to check the current status."]
        ))
        settings.hotkey.backend.registrationResults = [.init(status: -50, hasReference: false)]
        settings.model.setEnabled(true)
        await settings.settle()
        try settings.loadAccessibilityWindowTree()
        #expect(settings.model.errorMessage != nil)
        #expect(settings.store.launchAtLoginError != nil)
        let recovery = try #require(settings.nodes().first {
            $0.role == .button && $0.label == "Open Login Items in System Settings"
        })
        #expect(recovery.enabled)
        let hosting = try #require(owner.contentView)
        let scroll = try #require(accessibilityScrollView(in: hosting))
        let error = try #require(settings.nodes().first {
            ($0.value as? String) == settings.model.errorMessage || $0.label == settings.model.errorMessage
        })
        let errorRect = scroll.documentView?.convert(
            owner.convertFromScreen(error.frame), from: nil
        )
        let document = try #require(scroll.documentView)
        document.scrollToVisible(try #require(errorRect))
        await settings.settle()
        let errorInViewport = scroll.contentView.convert(owner.convertFromScreen(error.frame), from: nil)
        #expect(scroll.contentView.bounds.intersects(errorInViewport))
        #expect(owner.frame == frame)
        #expect(settings.saved.value.startOfWeekday == saved.startOfWeekday)
        #expect(settings.saved.value.displayOptions == saved.displayOptions)
        try settings.saveBitmap(name: "settings-recovery-\(suffix)")
        // The real recovery control stays reachable; do not open System Settings.
        #expect(settings.nodes().contains { $0.label == "Open Login Items in System Settings" })
    }

    @Test
    func nativeSettingsMenuHasOneRetainedDestination() async throws {
        let initial = SettingsWindowTestFixture()
        defer { initial.close() }
        try await initial.open()
        let menu = try #require(NSApp.mainMenu)
        func commaCommands(in menu: NSMenu) -> [NSMenuItem] {
            menu.items.flatMap { item in
                let own = item.keyEquivalent == "," &&
                    item.keyEquivalentModifierMask.intersection([.command, .shift, .option, .control]) == .command
                    ? [item] : []
                return own + (item.submenu.map { commaCommands(in: $0) } ?? [])
            }
        }
        let commands = commaCommands(in: menu)
        #expect(commands.count == 1)
        guard let command = commands.first, let parent = command.menu else { return }
        let before = Set(NSApp.windows.map(ObjectIdentifier.init))
        defer {
            for window in NSApp.windows where !before.contains(ObjectIdentifier(window)) {
                window.close()
            }
        }
        withDependencies {
            $0.preferencesClient = initial.preferencesClient
            $0.launchAtLoginClient = initial.launchAtLoginClient
        } operation: {
            parent.performActionForItem(at: parent.index(of: command))
        }
        await initial.settle()
        let opened = NSApp.windows.filter {
            $0.isVisible && !before.contains(ObjectIdentifier($0))
        }
        #expect(opened.count == 1)
        let owner = opened.first
        #expect(owner?.title == "Glimpse Settings")
        #expect(owner is SettingsWindow)
        guard let owner else { return }
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: owner.windowNumber, context: nil,
            characters: ",", charactersIgnoringModifiers: ",", isARepeat: false, keyCode: 43
        ))
        try #require(event.window === owner)
        #expect(menu.performKeyEquivalent(with: event))
        await initial.settle()
        #expect(NSApp.keyWindow === owner)
        #expect(NSApp.windows.filter {
            $0.isVisible && !before.contains(ObjectIdentifier($0))
        }.count == 1)
    }

    @Test
    func settingsGearFrontsWindowWithoutInlineExpansion() async throws {
        let calendar = try CalendarKeyboardRootFixture(maximumHeight: 300)
        let settings = SettingsWindowTestFixture()
        let delegate = AppDelegate(
            calendarStatusItem: calendar.showOwner, showCommand: CalendarShowCommand(),
            settingsController: settings.controller
        )
        defer { settings.close(); calendar.close(); withExtendedLifetime(delegate) {} }
        try await calendar.openThroughShowOwner()
        calendar.panel.isPinned = true
        calendar.store.send(.togglePin)
        calendar.store.send(.goToNextMonth)
        await calendar.settleRendering()
        try calendar.loadOwnedAccessibilityTree()
        let scroll = try #require(accessibilityScrollView(in: calendar.hosting))
        let frame = calendar.panel.frame
        let origin = scroll.contentView.bounds.origin
        let month = calendar.store.displayedMonth
        let gear = try #require(calendar.accessibilityNodes().first {
            $0.role == .button && $0.label == "Open Glimpse Settings"
        })
        try #require((gear.object.accessibilityWindow?() as? NSWindow) === calendar.panel)
        try #require(gear.press())
        await calendar.settleRendering()
        #expect(settings.controller.window?.isVisible == true)
        #expect(NSApp.keyWindow === settings.controller.window)
        #expect(!calendar.store.showingPreferences)
        #expect(calendar.panel.isVisible && calendar.panel.frame == frame)
        #expect(scroll.contentView.bounds.origin == origin)
        #expect(calendar.store.displayedMonth == month)
        #expect(calendar.accessibilityNodes().allSatisfy { $0.label != "Week starts on" })
    }

    @Test(arguments: [false, true])
    func settingsSectionsKeepWindowAndCalendarStable(constrained: Bool) async throws {
        let calendar = try CalendarKeyboardRootFixture(maximumHeight: 300)
        let settings = SettingsWindowTestFixture()
        defer { settings.close(); calendar.close() }
        try await calendar.openThroughShowOwner()
        calendar.panel.isPinned = true
        calendar.store.send(.togglePin)
        await calendar.settleRendering()
        let calendarFrame = calendar.panel.frame
        let scroll = try #require(accessibilityScrollView(in: calendar.hosting))
        let origin = scroll.contentView.bounds.origin
        let screen = try #require(NSScreen.screens.first)
        let available = screen.visibleFrame
        let visible = constrained
            ? NSRect(x: available.midX - 250, y: available.midY - 160, width: 500, height: 320)
            : available
        let placement = calendar.showOwner.prepareForSettingsPresentation()
        try await settings.open(visibleFrame: visible, avoiding: placement.avoiding, calendar: placement.calendar)
        let owner = try #require(settings.controller.window)
        let frame = owner.frame
        let saved = settings.saved.value
        #expect(visible.insetBy(dx: 10, dy: 10).contains(frame))
        if !constrained {
            #expect(owner.contentRect(forFrameRect: frame).size == NSSize(width: 600, height: 600))
        }
        for section in SettingsSection.allCases {
            try await settings.reveal(section)
            try settings.loadAccessibilityWindowTree()
            #expect(settings.nodes().contains {
                $0.role != .button &&
                    ($0.label == section.heading || ($0.value as? String) == section.heading)
            })
            #expect(owner.frame == frame)
            #expect(calendar.panel.frame == calendarFrame)
            #expect(scroll.contentView.bounds.origin == origin)
            #expect(settings.saved.value == saved)
        }
    }

    @Test(arguments: [false, true], [false, true])
    func settingsHandoffPreservesPinnedContext(pinned: Bool, editorOpen: Bool) async throws {
        let calendar = try CalendarKeyboardRootFixture(showAI: true, maximumHeight: 300)
        let settings = SettingsWindowTestFixture()
        defer { settings.close(); calendar.close() }
        try await calendar.openThroughShowOwner()
        calendar.panel.isPinned = pinned
        if pinned { calendar.store.send(.togglePin) }
        calendar.store.send(.goToNextMonth)
        let selected = try #require(calendar.store.days.dropFirst(20).first?.date)
        calendar.store.send(.dateTapped(selected))
        if editorOpen {
            calendar.panel.activateForTextInput()
            calendar.aiModel.setEditorOpen(true)
            calendar.aiModel.setDraft("Retain pinned settings handoff draft")
        }
        await calendar.settleRendering()
        try calendar.loadOwnedAccessibilityTree()
        if editorOpen {
            let field = try calendar.nativeEditorField()
            try #require(field.currentEditor() === calendar.panel.firstResponder)
        }
        let scroll = try #require(accessibilityScrollView(in: calendar.hosting))
        let snapshot = (
            frame: calendar.panel.frame, scroll: scroll.contentView.bounds.origin,
            month: calendar.store.displayedMonth, date: calendar.store.selectedDate,
            session: try #require(calendar.presentationSnapshot).keyboardSession,
            reopens: calendar.reopenActions.value, completions: calendar.completions
        )
        let placement = calendar.showOwner.prepareForSettingsPresentation()
        try await settings.open(visibleFrame: placement.visibleFrame, avoiding: placement.avoiding, calendar: placement.calendar)
        try #require(NSApp.keyWindow === settings.controller.window)
        #expect(calendar.panel.isVisible == pinned)
        #expect(calendar.store.isPinned == pinned && calendar.panel.isPinned == pinned)
        if pinned {
            #expect(calendar.store.displayedMonth == snapshot.month)
            #expect(calendar.store.selectedDate == snapshot.date)
            for section in SettingsSection.allCases {
                try await settings.reveal(section)
                #expect(calendar.panel.frame == snapshot.frame)
                #expect(scroll.contentView.bounds.origin == snapshot.scroll)
                #expect(calendar.presentationSnapshot?.keyboardSession == snapshot.session)
            }
            #expect(calendar.aiModel.isEditorOpen == editorOpen)
            if editorOpen { #expect(calendar.aiModel.draft == "Retain pinned settings handoff draft") }
        } else {
            #expect(!calendar.aiModel.isEditorOpen)
        }
        // An internal handoff must abandon the old restoration lease.
        calendar.panel.deactivateTextInput()
        #expect(calendar.previousAppRestorations == 0)
        let monthAfterHandoff = calendar.store.displayedMonth
        let dateAfterHandoff = calendar.store.selectedDate
        settings.controller.window?.close()
        await calendar.settleRendering()
        #expect(calendar.panel.isVisible == pinned)
        #expect(calendar.reopenActions.value == snapshot.reopens)
        #expect(calendar.completions == snapshot.completions)
        #expect(calendar.store.displayedMonth == monthAfterHandoff)
        #expect(calendar.store.selectedDate == dateAfterHandoff)
    }

    @Test(arguments: ["editor-pinned", "editor-unpinned", "cross-screen"])
    func settingsHandoffRejectsDeferredCalendarPresentation(source: String) async throws {
        let crossScreen = source == "cross-screen"
        let calendar = try CalendarKeyboardRootFixture(
            showAI: true, holdEditorPresentation: true, holdCrossScreenShows: crossScreen
        )
        let settings = SettingsWindowTestFixture()
        defer { settings.close(); calendar.close() }
        try await calendar.openThroughShowOwner()
        calendar.panel.isPinned = source == "editor-pinned"
        if crossScreen {
            calendar.showOwner.statusItemClicked()
            try #require(calendar.heldCrossScreenShows.count == 1)
            try #require(!calendar.panel.isVisible)
        } else {
            calendar.aiModel.setEditorOpen(true)
            await calendar.settleRendering()
            try #require(calendar.heldEditorPresentations.count == 1)
            try #require(calendar.nativeEditorFields.count == 1)
            try #require(calendar.presentationSnapshot?.editorFocused == false)
        }
        let placement = calendar.showOwner.prepareForSettingsPresentation()
        try await settings.open(visibleFrame: placement.visibleFrame, avoiding: placement.avoiding, calendar: placement.calendar)
        try #require(NSApp.keyWindow === settings.controller.window)
        if crossScreen { calendar.completeHeldCrossScreenShow() }
        else { calendar.completeHeldEditorPresentation() }
        await calendar.settleRendering()
        #expect(NSApp.keyWindow === settings.controller.window)
        #expect(calendar.panel.isVisible == (source == "editor-pinned"))
        #expect(calendar.presentationSnapshot?.editorFocused == false)
    }

    @Test
    func normalCalendarTextDismissalStillRestoresPreviousApplication() async throws {
        let calendar = try CalendarKeyboardRootFixture(showAI: true)
        defer { calendar.close() }
        try await calendar.openThroughShowOwner()
        calendar.panel.activateForTextInput()
        calendar.panel.deactivateTextInput()
        #expect(calendar.previousAppRestorations == 1)
        calendar.panel.deactivateTextInput()
        #expect(calendar.previousAppRestorations == 1)
    }

    @Test(arguments: ["close", "orderOut", "keyLoss", "appDeactivation", "minimize"])
    func settingsRecordingFollowsItsOwnWindow(boundary: String) async throws {
        let fixture = SettingsWindowTestFixture()
        defer { fixture.close() }
        try await fixture.open()
        try await fixture.startRecording()
        fixture.notifications.post(name: .calendarPanelWillHide, object: nil)
        await fixture.settle()
        #expect(fixture.model.isRecording)

        // Exercise the owner boundary even when the unrelated-hide assertion fails.
        if !fixture.model.isRecording { try await fixture.startRecording() }
        let cancellations = fixture.recordingChanges.value.filter { !$0 }.count
        let owner = try #require(fixture.controller.window)
        let peer = NSWindow(
            contentRect: NSRect(x: owner.frame.minX, y: owner.frame.minY, width: 100, height: 100),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        peer.isReleasedWhenClosed = false
        defer { peer.close() }
        switch boundary {
        case "close": owner.close()
        case "orderOut": owner.orderOut(nil)
        case "keyLoss":
            peer.makeKeyAndOrderFront(nil)
            await fixture.settle()
            try #require(NSApp.keyWindow === peer)
        case "appDeactivation":
            fixture.notifications.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        case "minimize": owner.miniaturize(nil)
        default: Issue.record("Unknown settings ownership boundary")
        }
        await fixture.settle()
        #expect(!fixture.model.isRecording)
        #expect(fixture.recordingChanges.value.filter { !$0 }.count == cancellations + 1)
        fixture.controller.cancelRecording()
        #expect(fixture.recordingChanges.value.filter { !$0 }.count == cancellations + 1)
        #expect(fixture.hotkey.backend.operations.isEmpty)
        #expect(fixture.hotkey.defaults.object(forKey: "hotkeyKeyCode") == nil)
        #expect(fixture.hotkey.defaults.object(forKey: "hotkeyEnabled") == nil)
    }

    @Test
    func settingsReopenRefreshesWithoutReplacingState() async throws {
        let fixture = SettingsWindowTestFixture()
        defer { fixture.close() }
        try await fixture.open()
        let owner = try #require(fixture.controller.window)
        let originalStore = fixture.controller.store
        let originalModel = fixture.controller.hotkeyPreferences
        try await fixture.reveal(.menuBar)
        let contentView = try #require(owner.contentView)
        let scroll = try #require(accessibilityScrollView(in: contentView))
        let documentOrigin = scroll.contentView.bounds.origin
        let root = owner.contentView
        owner.close()
        try await fixture.open()
        #expect(fixture.controller.window === owner && owner.contentView === root)
        #expect(scroll.contentView.bounds.origin == documentOrigin)
        owner.close()
        fixture.saved.withValue {
            $0.startOfWeekday = 7
            $0.showAISearch = false
            $0.launchAtLoginStatus = .requiresApproval
        }
        try await fixture.open()
        #expect(fixture.controller.window === owner)
        #expect(fixture.controller.store === originalStore)
        #expect(fixture.controller.hotkeyPreferences === originalModel)
        #expect(owner.contentView === root)
        #expect(scroll.contentView.bounds.minY >= 0)
        #expect(fixture.store.startOfWeekday == 7)
        #expect(!fixture.store.showAISearch)
        #expect(fixture.store.launchAtLoginStatus == .requiresApproval)
        try await fixture.reveal(.general)
        try fixture.loadAccessibilityWindowTree()
        #expect(fixture.nodes().contains {
            $0.role == .staticText
                && $0.value as? String == "Approval required. Allow Glimpse in Login Items to launch at login."
        })

        fixture.store.send(.setLaunchAtLogin(true))
        await fixture.settle()
        try #require(fixture.store.isUpdatingLaunchAtLogin)
        try #require(fixture.login.requests.value == [true])
        owner.close()
        try await fixture.open()
        try await fixture.open()
        #expect(fixture.controller.window === owner)
        #expect(fixture.store.isUpdatingLaunchAtLogin)
        #expect(fixture.login.requests.value == [true])
        fixture.saved.withValue { $0.launchAtLoginStatus = .enabled }
        fixture.login.finish()
        await fixture.settle()
        #expect(!fixture.store.isUpdatingLaunchAtLogin)
        #expect(fixture.store.launchAtLoginStatus == .enabled)
        #expect(fixture.store.launchAtLoginError == nil)
        #expect(fixture.login.requests.value == [true])
    }

    @Test
    func shortcutRecordingStartsFromItsOrdinaryWindow() async throws {
        let fixture = ShortcutRecorderWindowFixture()
        defer { fixture.close() }
        try await fixture.open()
        let recorder = try fixture.recorder()
        let recorderWindow = recorder.object.accessibilityWindow?() as? NSWindow
        try #require(recorderWindow === fixture.window)
        try #require(recorder.press())
        await fixture.settle()

        #expect(fixture.preferences.hotkeyModel.isRecording)
        #expect(fixture.preferences.hotkey.backend.operations.isEmpty)
        #expect(fixture.preferences.hotkey.defaults.object(forKey: "hotkeyKeyCode") == nil)
        #expect(fixture.preferences.hotkey.defaults.object(forKey: "hotkeyEnabled") == nil)
    }

    @Test
    func backgroundShortcutControlCannotRecordFromAnotherPanel() async throws {
        let fixture = ShortcutRecorderWindowFixture()
        defer { fixture.close() }
        try await fixture.open()
        let otherPanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 120),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        otherPanel.isReleasedWhenClosed = false
        defer { otherPanel.close() }
        otherPanel.setFrameOrigin(fixture.window.frame.origin)
        otherPanel.makeKeyAndOrderFront(nil)
        await fixture.settle()
        try #require(NSApp.keyWindow === otherPanel && otherPanel.isKeyWindow)
        try #require(fixture.window.isVisible && !fixture.window.isKeyWindow)

        let recorder = try fixture.recorder()
        let recorderWindow = recorder.object.accessibilityWindow?() as? NSWindow
        try #require(recorderWindow === fixture.window)
        try #require(recorder.press())
        await fixture.settle()
        try #require(NSApp.keyWindow === otherPanel)

        #expect(!fixture.preferences.hotkeyModel.isRecording)
        #expect(fixture.preferences.hotkey.backend.operations.isEmpty)
        #expect(fixture.preferences.hotkey.defaults.object(forKey: "hotkeyKeyCode") == nil)
        #expect(fixture.preferences.hotkey.defaults.object(forKey: "hotkeyEnabled") == nil)
    }

    @Test
    func normalOpenRetainsBrowseMonthYearAndToday() async throws {
        let fixture = try CalendarKeyboardRootFixture()
        defer { fixture.close() }
        try await fixture.open()
        fixture.trace("normal-open")
        try fixture.send(.right)
        #expect(fixture.monthNumber == 12)
        try fixture.send(.up)
        #expect(fixture.yearNumber == 2029)
        try fixture.send(.returnKey)
        #expect(fixture.monthNumber == 11)
        #expect(fixture.yearNumber == 2030)
        #expect(fixture.store.selectedDate == fixture.today)
        #expect(fixture.actions.value == ["nextMonth", "previousYear", "today"])
        #expect(fixture.actionCurrentEvents.value.allSatisfy { $0 })
    }

    @Test
    func queuedTabAndImmediateArrowSpaceActivateNewLogicalDate() async throws {
        let fixture = try CalendarKeyboardRootFixture()
        defer { fixture.close() }
        try await fixture.open()
        for _ in 0..<4 { try fixture.send(.tab) }
        fixture.trace("after-four-tabs-no-settle")
        let beforeMovement = fixture.callbackRows.count
        try fixture.send(.right)
        fixture.expectInvocation(after: beforeMovement, owner: .grid, key: .right, route: "move(1)")
        #expect(fixture.actions.value.isEmpty)
        #expect(fixture.store.selectedDate == fixture.today)
        let beforeActivation = fixture.callbackRows.count
        try fixture.send(.space)
        fixture.expectInvocation(after: beforeActivation, owner: .grid, key: .space, route: "activate")
        fixture.trace("immediate-arrow-space")
        #expect(fixture.store.selectedDate == fixture.date(day: 16))
        #expect(fixture.monthNumber == 11)
        #expect(fixture.actions.value == ["date:16"])
        #expect(fixture.actionCurrentEvents.value == [true])
    }

    @Test
    func firstHeaderReturnUsesFocusedActionRatherThanToday() async throws {
        let fixture = try CalendarKeyboardRootFixture()
        defer { fixture.close() }
        try await fixture.open()
        try fixture.send(.tab)
        let beforeActivation = fixture.callbackRows.count
        try fixture.send(.returnKey)
        fixture.expectInvocation(after: beforeActivation, owner: .previousMonth, key: .returnKey, route: "activate")
        #expect(fixture.monthNumber == 10)
        #expect(fixture.actions.value == ["previousMonth"])
        #expect(fixture.actionCurrentEvents.value == [true])
    }

    @Test
    func heldHeaderSpaceActivatesOnceAndConsumesRepeat() async throws {
        let fixture = try CalendarKeyboardRootFixture()
        defer { fixture.close() }
        try await fixture.open()
        try fixture.send(.tab)
        let beforeReturn = fixture.callbackRows.count
        try fixture.send(.returnKey)
        fixture.expectInvocation(after: beforeReturn, owner: .previousMonth, key: .returnKey, route: "activate")
        #expect(fixture.monthNumber == 10)
        #expect(fixture.actions.value == ["previousMonth"])
        #expect(fixture.actionCurrentEvents.value == [true])
        let beforeSpace = fixture.callbackRows.count
        try fixture.send(.space) // Complete down/up pair: exactly one local action.
        fixture.expectInvocation(after: beforeSpace, owner: .previousMonth, key: .space, route: "activate")
        #expect(fixture.monthNumber == 9)
        #expect(fixture.actions.value == ["previousMonth", "previousMonth"])
        #expect(fixture.actionCurrentEvents.value == [true, true])
        await fixture.settleRendering()
        #expect(fixture.monthNumber == 9)
        #expect(fixture.actions.value == ["previousMonth", "previousMonth"])
        #expect(fixture.actionCurrentEvents.value == [true, true])
        let beforeRepeat = fixture.callbackRows.count
        try fixture.send(.space, repeatPress: true)
        fixture.expectInvocation(after: beforeRepeat, owner: .previousMonth, key: .space,
                                 route: "consume", phase: "repeatPress")
        #expect(fixture.monthNumber == 9)
        #expect(fixture.actions.value == ["previousMonth", "previousMonth"])
        #expect(fixture.actionCurrentEvents.value == [true, true])
        await fixture.settleRendering()
        #expect(fixture.monthNumber == 9)
        #expect(fixture.actions.value == ["previousMonth", "previousMonth"])
        #expect(fixture.actionCurrentEvents.value == [true, true])
        let beforeFinalReturn = fixture.callbackRows.count
        try fixture.send(.returnKey)
        fixture.expectInvocation(after: beforeFinalReturn, owner: .previousMonth, key: .returnKey, route: "activate")
        #expect(fixture.monthNumber == 8)
        #expect(fixture.actions.value == ["previousMonth", "previousMonth", "previousMonth"])
        #expect(fixture.actionCurrentEvents.value == [true, true, true])
        fixture.trace("held-header-local-space-once-repeat-completed")
    }

    @Test
    func todayBecomingDisabledHasNoExtraTodayAction() async throws {
        // Production disabled state uses public live today; other fixtures retain2030.
        let fixture = try CalendarKeyboardRootFixture(initialToday: Date())
        defer { fixture.close() }
        try await fixture.open()
        try fixture.send(.tab)
        try fixture.send(.returnKey) // Move away so Today is enabled.
        await fixture.settleRendering()
        try fixture.send(.tab)
        let beforeToday = fixture.callbackRows.count
        try fixture.send(.returnKey)
        fixture.expectInvocation(after: beforeToday, owner: .today, key: .returnKey, route: "activate")
        #expect(fixture.actions.value == ["previousMonth", "today"])
        #expect(fixture.actionCurrentEvents.value == [true, true])
        await fixture.settleRendering()
        #expect(fixture.store.isShowingCurrentMonth)
        #expect(fixture.store.selectedDate.map { Calendar.current.isDateInToday($0) } == true)
        for repeatPress in [false, true] {
            let before = fixture.callbackRows.count
            let disabledBeforeEvent = fixture.store.isShowingCurrentMonth
                && fixture.store.selectedDate.map { Calendar.current.isDateInToday($0) } == true
            try fixture.send(.space, repeatPress: repeatPress)
            let rows = Array(fixture.callbackRows.dropFirst(before))
            let todayRows = rows.filter { $0["owner"] as? String == CalendarKeyboardOwner.today.rawValue }
            if disabledBeforeEvent {
                #expect(todayRows.allSatisfy { $0["route"] as? String == "consume" })
            }
            #expect(rows.allSatisfy {
                $0["eventWindowOwned"] as? Bool == true && $0["currentEventMatchesExpected"] as? Bool == true
            })
            #expect(fixture.actions.value.filter { $0 == "today" }.count == 1)
            // Withdrawal is valid; no absent callback is relabeled disabled-handler proof.
            print("GLIMPSE_KEYBOARD_DISABLED_TODAY_OBSERVATION repeat=\(repeatPress) disabledBeforeEvent=\(disabledBeforeEvent) localCallbacks=\(rows.count) todayOwnerCallbacks=\(todayRows.count) disabledOwnerHandlerExercised=\(disabledBeforeEvent && !todayRows.isEmpty) owners=\(rows.compactMap { $0["owner"] as? String })")
            fixture.trace("today-disabled-after-space-\(repeatPress)")
        }

        // Keep the original key-routing sequence above intact; observe the same
        // root afterward so visual checks do not introduce extra fixture opens.
        let otherDate = try #require(fixture.store.days.first {
            $0.isCurrentMonth && !fixture.store.calendar.isDateInToday($0.date)
        }?.date)
        for (appearanceName, theme) in [
            (NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")
        ] {
            fixture.panel.appearance = try #require(NSAppearance(named: appearanceName))

            @MainActor
            func observeToday(_ state: String, enabled: Bool) async throws {
                await fixture.settleRendering()
                try #require(fixture.store.calendar.isDateInToday(fixture.today),
                             "Public today crossed midnight during this fixture")
                try fixture.loadOwnedAccessibilityTree()
                let nodes = fixture.accessibilityNodes().filter {
                    $0.role == .button && $0.label == "Go to today"
                }
                #expect(nodes.count == 1)
                let node = try #require(nodes.first)
                #expect(node.enabled == enabled)
                #expect(node.help == "Go to today")
                expectCalendarControlTarget(node.frame, action: .today)
                #expect(fixture.hosting.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
                        == appearanceName)
                let bounds = fixture.panel.convertToScreen(
                    fixture.hosting.convert(fixture.hosting.bounds, to: nil)
                )
                try fixture.saveFocusedDateBitmap(
                    bounds, name: "today-root-\(theme)-\(state)"
                )
                fixture.clearActionReceipts()
                if enabled {
                    #expect(node.press())
                } else {
                    _ = node.press()
                }
                await fixture.settleRendering()
                #expect(fixture.actions.value == (enabled ? ["today"] : []))
                #expect(fixture.store.isShowingCurrentMonth)
                #expect(fixture.store.selectedDate == fixture.today)
                let after = fixture.accessibilityNodes().filter {
                    $0.role == .button && $0.label == "Go to today"
                }
                #expect(after.count == 1 && after.first?.enabled == false)
                print("GLIMPSE_TODAY_STATE theme=\(theme) state=\(state) enabled=\(enabled) target=\(node.frame)")
            }

            fixture.store.send(.goToToday)
            try await observeToday("today-selected", enabled: false)
            fixture.store.send(.dateTapped(otherDate))
            try await observeToday("other-selected", enabled: true)
            fixture.store.send(.dateTapped(otherDate))
            fixture.store.send(.dateTapped(otherDate))
            #expect(fixture.store.selectedDate == nil)
            try await observeToday("no-selection", enabled: true)
            fixture.store.send(.goToPreviousMonth)
            try await observeToday("away-month", enabled: true)
        }

        if fixture.gridVisualAcceptanceEnabled {
            // Observe this same root after the original key-routing assertions.
            // Calendar configuration is fixture-owned; no real preferences are saved.
            let otherDate = try #require(fixture.store.days.first {
                $0.isCurrentMonth && !fixture.store.calendar.isDateInToday($0.date)
            }?.date)
            for (appearanceName, theme) in CalendarKeyboardRootFixture.gridVisualAppearances {
                fixture.panel.appearance = try #require(NSAppearance(named: appearanceName))

                @MainActor
                func observeGrid(_ state: String, enabled: Bool) async throws {
                    await fixture.settleRendering()
                    try #require(fixture.store.calendar.isDateInToday(fixture.today),
                                 "Public today crossed midnight during this fixture")
                    #expect(fixture.hosting.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
                            == appearanceName)
                    print("GLIMPSE_GRID_APPEARANCE theme=\(theme) state=\(state) requested=\(appearanceName.rawValue) hosting=\(fixture.hosting.effectiveAppearance.name.rawValue)")
                    try fixture.loadOwnedAccessibilityTree()
                    let nodes = fixture.accessibilityNodes()
                    let dateLabels = fixture.store.days.map {
                        $0.date.formatted(
                            Date.FormatStyle.dateTime.weekday(.wide).month(.wide).day().year()
                        )
                    }
                    let dates = nodes.filter {
                        node in node.role == .button
                            && dateLabels.contains { node.label?.hasPrefix($0) == true }
                    }
                    #expect(dates.count == 42)
                    #expect(Set(dates.compactMap(\.label)).count == 42)
                    for (index, date) in dates.enumerated() {
                        #expect(date.enabled && abs(date.frame.height - 30) < 0.5)
                        #expect(date.frame.width > 28)
                        for other in dates.dropFirst(index + 1) {
                            #expect(!date.frame.intersects(other.frame))
                        }
                    }
                    let todayNodes = nodes.filter {
                        $0.role == .button && $0.label == "Go to today"
                    }
                    #expect(todayNodes.count == 1)
                    let todayNode = try #require(todayNodes.first)
                    #expect(todayNode.enabled == enabled)
                    let bounds = fixture.panel.convertToScreen(
                        fixture.hosting.convert(fixture.hosting.bounds, to: nil)
                    )
                    try fixture.saveFocusedDateBitmap(
                        bounds, name: "grid-root-\(theme)-\(state)"
                    )
                    fixture.clearActionReceipts()
                    if enabled { #expect(todayNode.press()) } else { _ = todayNode.press() }
                    await fixture.settleRendering()
                    #expect(fixture.actions.value == (enabled ? ["today"] : []))
                    #expect(fixture.store.isShowingCurrentMonth)
                    #expect(fixture.store.selectedDate == fixture.today)
                    print("GLIMPSE_GRID_STATE theme=\(theme) state=\(state) enabled=\(enabled) weekStart=\(fixture.store.startOfWeekday) workdays=\(fixture.store.workdays.sorted())")
                }

                fixture.store.send(.goToToday)
                try await observeGrid("today-selected", enabled: false)
                fixture.store.send(.dateTapped(otherDate))
                try await observeGrid("other-selected", enabled: true)
                fixture.store.send(.dateTapped(otherDate))
                fixture.store.send(.dateTapped(otherDate))
                #expect(fixture.store.selectedDate == nil)
                try await observeGrid("no-selection", enabled: true)
                fixture.store.send(.goToPreviousMonth)
                try await observeGrid("away-month", enabled: true)

                fixture.calendarSettings.setValue((startOfWeekday: 2, workdays: Set([1, 7])))
                fixture.store.send(.reloadPreferences)
                fixture.store.send(.dateTapped(otherDate))
                #expect(fixture.store.startOfWeekday == 2)
                #expect(fixture.store.workdays == Set([1, 7]))
                try await observeGrid("monday-weekend-workdays", enabled: true)
                fixture.calendarSettings.setValue((startOfWeekday: 1, workdays: Set([2, 3, 4, 5, 6])))
                fixture.store.send(.reloadPreferences)
            }
        }
    }

    @Test
    func reverseTabReturnsToHeaderWithoutCustomTraversal() async throws {
        let fixture = try CalendarKeyboardRootFixture()
        defer { fixture.close() }
        try await fixture.open()
        for _ in 0..<4 { try fixture.send(.tab) }
        try fixture.send(.backTab)
        fixture.trace("immediate-reverse-tab")
        let beforeActivation = fixture.callbackRows.count
        try fixture.send(.returnKey)
        fixture.expectInvocation(after: beforeActivation, owner: .nextMonth, key: .returnKey, route: "activate")
        #expect(fixture.actions.value == ["nextMonth"])
        #expect(fixture.actionCurrentEvents.value == [true])
    }

    @Test
    func gridExitAndReopenWithdrawOwnerBeforeBrowse() async throws {
        let fixture = try CalendarKeyboardRootFixture()
        defer { fixture.close() }
        try await fixture.open()
        for _ in 0..<4 { try fixture.send(.tab) }
        let beforeMovement = fixture.callbackRows.count
        try fixture.send(.right)
        fixture.expectInvocation(after: beforeMovement, owner: .grid, key: .right, route: "move(1)")
        #expect(fixture.actions.value.isEmpty)
        // Traverse the real expanded footer before the native chain wraps to the header.
        try await fixture.focusOwner(.previousMonth)
        try #require(fixture.lastPublishedOwner == .previousMonth)
        let beforeExitActivation = fixture.callbackRows.count
        try fixture.send(.returnKey)
        fixture.expectInvocation(after: beforeExitActivation, owner: .previousMonth, key: .returnKey, route: "activate")
        #expect(fixture.actions.value == ["previousMonth"])
        fixture.panel.orderOut(nil)
        try await fixture.open()
        fixture.trace("reopen-before-browse")
        #expect(fixture.lastPublishedOwner == nil)
        // Keep the exact identity condition while avoiding a private proxy dump.
        let responderIsWindow = fixture.panel.firstResponder === fixture.panel
        #expect(responderIsWindow)
        try fixture.send(.right)
        #expect(fixture.actions.value == ["nextMonth"])
        #expect(fixture.actionCurrentEvents.value == [true])
        #expect(fixture.monthNumber == 12)
        try fixture.send(.returnKey)
        #expect(fixture.actions.value == ["nextMonth", "today"])
        #expect(fixture.actionCurrentEvents.value == [true, true])
        #expect(fixture.monthNumber == 11)
        #expect(fixture.store.selectedDate == fixture.today)
        #expect(fixture.callbackRows.isEmpty)
    }

    @Test
    func settledTraversalCharacterizesGridBeforeImmediateArrowSpace() async throws {
        let fixture = try CalendarKeyboardRootFixture()
        defer { fixture.close() }
        try await fixture.open()
        for _ in 0..<4 {
            try fixture.send(.tab)
            // Characterization only: separate from immediate Tab freshness.
            await fixture.opportunityForFocusRendering()
        }
        fixture.trace("settled-four-tabs")
        #expect(fixture.lastPublishedOwner == .grid)
        try fixture.send(.right)
        #expect(fixture.actions.value.isEmpty)
        #expect(fixture.store.selectedDate == fixture.today)
        // No Tab, yield or rendering opportunity between movement and activation.
        try fixture.send(.space)
        #expect(fixture.actions.value == ["date:16"])
        #expect(fixture.store.selectedDate == fixture.date(day: 16))
        #expect(fixture.actionCurrentEvents.value == [true])
        #expect(fixture.callbackRows.contains {
            $0["owner"] as? String == "grid" && $0["route"] as? String == "move(1)"
                && $0["currentEventMatchesExpected"] as? Bool == true
        })
    }

    @Test(arguments: [CalendarOwnedKey.returnKey, .keypadEnter])
    func gridReturnKeypadRepeatAndModifierOwnership(key: CalendarOwnedKey) async throws {
        let fixture = try CalendarKeyboardRootFixture()
        defer { fixture.close() }
        try await fixture.open()
        for _ in 0..<4 { try fixture.send(.tab) }
        try fixture.send(.right)
        let beforeRepeat = fixture.callbackRows.count
        try fixture.send(key, repeatPress: true)
        fixture.expectInvocation(after: beforeRepeat, owner: .grid, key: key.routerKey,
                                 route: "consume", phase: "repeatPress")
        try fixture.send(key, modifiers: .command)
        #expect(fixture.actions.value.isEmpty)
        #expect(fixture.store.selectedDate == fixture.today)
        let beforeActivation = fixture.callbackRows.count
        try fixture.send(key)
        fixture.expectInvocation(after: beforeActivation, owner: .grid, key: key.routerKey, route: "activate")
        #expect(fixture.actions.value == ["date:16"])
        #expect(fixture.store.selectedDate == fixture.date(day: 16))
        try fixture.send(key, repeatPress: true)
        #expect(fixture.actions.value == ["date:16"])
        try fixture.send(.right, modifiers: .command)
        try fixture.send(.space)
        #expect(fixture.store.selectedDate == nil) // Selecting the same16 again deselects.
        #expect(fixture.actions.value == ["date:16", "date:16"])
        #expect(fixture.actionCurrentEvents.value == [true, true])
        fixture.trace("grid-return-repeat-modifier-\(key.rawValue)")
    }

    @Test
    func recorderPreferencesAndOwnedPeerKeepCalendarKeys() async throws {
        let fixture = try CalendarKeyboardRootFixture()
        defer { fixture.close(); fixture.setRecording(false) }
        try await fixture.open()
        for _ in 0..<4 { try fixture.send(.tab) }
        fixture.setRecording(true)
        try fixture.send(.right)
        try fixture.send(.space)
        try fixture.send(.returnKey)
        #expect(fixture.actions.value.isEmpty)
        #expect(fixture.store.selectedDate == fixture.today)
        fixture.setRecording(false)
        try fixture.send(.space)
        #expect(fixture.actions.value == ["date:15"])
        #expect(fixture.store.selectedDate == nil) // Same-day activation retains existing deselection.

        fixture.clearActionReceipts()
        let settings = SettingsWindowTestFixture()
        defer { settings.close() }
        fixture.panel.isPinned = true
        fixture.panel.prepareForSettingsPresentation()
        try await settings.open(calendar: fixture.panel)
        let settingsWindow = try #require(settings.controller.window)
        try fixture.send(.right, toWindow: settingsWindow)
        try fixture.send(.returnKey, toWindow: settingsWindow)
        #expect(fixture.actions.value.isEmpty)
        #expect(settingsWindow.isVisible && fixture.panel.isVisible)

        let peer = CalendarKeyboardOwnedPeer()
        defer { peer.close() }
        try peer.makeKey()
        let calendarIsNonkey = !fixture.panel.isKeyWindow && NSApp.keyWindow !== fixture.panel
        #expect(calendarIsNonkey)
        fixture.clearActionReceipts()
        try fixture.send(.right, to: peer)
        #expect(peer.receivedKeys == 1)
        #expect(peer.currentEventMatched)
        #expect(fixture.actions.value.isEmpty)
        #expect(fixture.callbackRows.isEmpty)
        fixture.trace("guard-owned-peer-dispatched")
    }

    @Test
    func repeatedVisibleShowRetainsGridFocusAndAnchor() async throws {
        let fixture = try CalendarKeyboardRootFixture()
        defer { fixture.close() }
        try await fixture.openThroughShowOwner()
        for _ in 0..<4 { try fixture.send(.tab) }
        try fixture.send(.right)
        let before = fixture.store.state
        let responder = fixture.panel.firstResponder
        let shows = fixture.completions
        for _ in 0..<2 { try fixture.showOwner.showCalendar() }
        let responderRetained = fixture.panel.firstResponder === responder
        #expect(responderRetained)
        #expect(fixture.store.state == before)
        #expect(fixture.panel.contentView === fixture.hosting)
        #expect(fixture.completions == shows)
        let beforeActivation = fixture.callbackRows.count
        try fixture.send(.space)
        fixture.expectInvocation(after: beforeActivation, owner: .grid, key: .space, route: "activate")
        #expect(fixture.actions.value == ["date:16"])
        #expect(fixture.store.selectedDate == fixture.date(day: 16))
        #expect(fixture.actionCurrentEvents.value == [true])
    }

    @Test
    func nativeEditorSubmitEscapeAndHiddenReopen() async throws {
        try await withAIDateKeyboardRootFixture { fixture in
            logCalendarKeyboardTarget(fixture.panel, stage: "editor-fixture-before-activation")
            NSApp.activate(ignoringOtherApps: true)
            try await fixture.openThroughShowOwner()
            for _ in 0..<4 { try fixture.send(.tab) }
            // The focused prompt locally handles Space; no AX action or panel-wide activation.
            try fixture.send(.space)
            fixture.trace("native-search-prompt-space")
            await fixture.settleRendering()
            try fixture.loadOwnedAccessibilityTree()
            let field = try fixture.nativeEditorField()
            let editor = try #require(field.currentEditor() as? NSTextView)
            let editorIsResponder = fixture.panel.firstResponder === editor
            #expect(editorIsResponder)
            // Public mutation sets up only this synthetic draft; native Return is queued.
            editor.insertText("synthetic next Friday", replacementRange: NSRange(location: NSNotFound, length: 0))
            await fixture.settleRendering()
            editor.setSelectedRange(NSRange(location: 3, length: 5))
            let responder = fixture.panel.firstResponder
            for _ in 0..<2 { try fixture.showOwner.showCalendar() }
            let responderRetained = fixture.panel.firstResponder === responder
            #expect(responderRetained)
            #expect(editor.string == "synthetic next Friday")
            #expect(editor.selectedRange() == NSRange(location: 3, length: 5))
            try fixture.send(.left)
            #expect(fixture.actions.value.isEmpty)
            #expect(editor.selectedRange() != NSRange(location: 3, length: 5))
            try fixture.send(.returnKey)
            #expect(fixture.submissions == ["synthetic next Friday"])
            #expect(fixture.submissionCurrentEvents == [true])
            #expect(fixture.actions.value.isEmpty)
            try await fixture.awaitAcceptedSubmissions()
            try fixture.send(.escape)
            await fixture.settleRendering()
            #expect(fixture.panel.isVisible)
            #expect(fixture.nativeEditorFields.isEmpty)
            #expect(fixture.submissions.count == 1)
            try fixture.send(.searchShortcut)
            await fixture.settleRendering()
            #expect(fixture.nativeEditorFields.count == 1)
            fixture.panel.orderOut(nil)
            try await fixture.openThroughShowOwner()
            #expect(fixture.nativeEditorFields.isEmpty)
            let responderIsWindow = fixture.panel.firstResponder === fixture.panel
            #expect(responderIsWindow)
            #expect(fixture.lastPublishedOwner == nil)
            try fixture.send(.right)
            try fixture.send(.returnKey)
            #expect(fixture.actions.value == ["nextMonth", "today"])
            #expect(fixture.submissions.count == 1)
            #expect(fixture.actionCurrentEvents.value == [true, true])
        }
    }

    @Test(arguments: [CGFloat(312), 812])
    func focusedLogicalDateStaysVisibleInCappedViewport(maximumHeight: CGFloat) async throws {
        let fixture = try CalendarKeyboardRootFixture(maximumHeight: maximumHeight)
        defer { fixture.close() }
        try await fixture.openThroughShowOwner()
        try fixture.loadOwnedAccessibilityTree()
        let scroll = try #require(accessibilityScrollView(in: fixture.hosting))
        let document = try #require(scroll.documentView)
        for _ in 0..<4 { try fixture.send(.tab) }
        for _ in 0..<4 { try fixture.send(.down) }
        await fixture.settleRendering()
        fixture.trace("viewport-anchor-settled-\(Int(maximumHeight))")
        let nodes = fixture.accessibilityNodes()
        let dates = nodes.filter { $0.role == .button && $0.label?.contains("2030") == true }
        let expectedLastDate = try #require(fixture.store.days.last?.date)
        let expectedLabel = expectedLastDate.formatted(
            Date.FormatStyle.dateTime.weekday(.wide).month(.wide).day().year()
        )
        let expectedGridLabel = "Calendar grid for \(fixture.store.monthYearString), focused date: \(expectedLabel)"
        let gridMatches = nodes.filter { $0.label?.hasPrefix("Calendar grid for \(fixture.store.monthYearString)") == true }
        let expectedDate = dates.first { $0.label?.hasPrefix(expectedLabel) == true }
        let expectedDateFrame = expectedDate?.frame
        let clip = fixture.panel.convertToScreen(scroll.contentView.convert(scroll.contentView.bounds, to: nil))
        try fixture.saveFocusedDateBitmap(clip, name: "viewport-\(Int(maximumHeight))-before-assertions")
        if fixture.gridVisualAcceptanceEnabled {
            let originalAppearance = fixture.panel.appearance
            for (appearanceName, theme) in CalendarKeyboardRootFixture.gridVisualAppearances {
                fixture.panel.appearance = try #require(NSAppearance(named: appearanceName))
                await fixture.settleRendering()
                #expect(fixture.gridRenderingFocused && fixture.lastPublishedOwner == .grid)
                #expect(fixture.hosting.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
                        == appearanceName)
                print("GLIMPSE_GRID_APPEARANCE theme=\(theme) viewport=\(Int(maximumHeight)) hosting=\(fixture.hosting.effectiveAppearance.name.rawValue)")
                try fixture.saveFocusedDateBitmap(
                    clip, name: "grid-focus-\(theme)-viewport-\(Int(maximumHeight))"
                )
            }
            fixture.panel.appearance = originalAppearance
            await fixture.settleRendering()
        }
        if let expectedDateFrame {
            try fixture.saveFocusedDateBitmap(
                expectedDateFrame, name: "expected-anchor-\(Int(maximumHeight))-before-assertions"
            )
        }
        let gridRenderingFocused = fixture.gridRenderingFocused
        #expect(gridRenderingFocused)
        #expect(fixture.lastPublishedOwner == .grid)
        #expect(dates.count == 42)
        let grid = try #require(nodes.first { $0.label?.hasPrefix("Calendar grid for ") == true })
        let exactlyOneGridLabel = gridMatches.count == 1
        #expect(exactlyOneGridLabel)
        let actualLabelMatchesExpected = grid.label == expectedGridLabel
        #expect(actualLabelMatchesExpected)
        try fixture.expectOwnedPublicAXGridLabel(expectedGridLabel)
        let focusedDate = try #require(dates.first { $0.label?.hasPrefix(expectedLabel) == true })
        #expect(clip.contains(focusedDate.frame))
        #expect(fixture.store.selectedDate == fixture.today)
        #expect(fixture.actions.value.isEmpty)
        #expect(accessibilityScrollView(in: fixture.hosting) === scroll)
        #expect(scroll.documentView === document)
        let focusedDateFrame = focusedDate.frame
        try fixture.saveFocusedDateBitmap(focusedDateFrame, name: "viewport-\(Int(maximumHeight))")
        // Header's native reverse/Return changes month; forward Tab returns to grid.
        try fixture.send(.backTab)
        try fixture.send(.returnKey)
        try fixture.send(.tab)
        await fixture.settleRendering()
        #expect(fixture.monthNumber == 12)
        let finalGridRenderingFocused = fixture.gridRenderingFocused
        #expect(finalGridRenderingFocused)
        #expect(accessibilityScrollView(in: fixture.hosting) === scroll)
        #expect(scroll.documentView === document)
    }

    @Test(arguments: ["AX", "pointer", "keyboard"], [false, true])
    func composedFooterEntryRetainsExactPairAndContext(entry: String, pinned: Bool) async throws {
        let calendar = try CalendarKeyboardRootFixture(showAI: true, maximumHeight: 300)
        let settings = SettingsWindowTestFixture()
        let delegate = AppDelegate(
            calendarStatusItem: calendar.showOwner, showCommand: CalendarShowCommand(),
            settingsController: settings.controller
        )
        defer { settings.close(); calendar.close(); withExtendedLifetime(delegate) {} }
        try await calendar.openThroughShowOwner()
        calendar.panel.isPinned = pinned
        if pinned { calendar.store.send(.togglePin) }
        calendar.store.send(.goToNextMonth)
        calendar.aiModel.setDraft("Retain composed Settings entry")
        await calendar.settleRendering()
        try calendar.loadOwnedAccessibilityTree()
        let scroll = try #require(accessibilityScrollView(in: calendar.hosting))
        let document = try #require(scroll.documentView)
        if entry == "keyboard" {
            try await calendar.focusOwner(.footerSettings)
            try #require(calendar.lastPublishedOwner == .footerSettings)
        } else {
            let target = try calendar.ownedControl("Open Glimpse Settings")
            document.scrollToVisible(document.convert(calendar.panel.convertFromScreen(target.frame), from: nil))
            await calendar.settleRendering()
        }
        try calendar.loadOwnedAccessibilityTree()
        let button = try calendar.ownedControl("Open Glimpse Settings")
        let viewport = calendar.panel.convertToScreen(
            scroll.contentView.convert(scroll.contentView.bounds, to: nil)
        )
        try #require(viewport.contains(button.frame))
        let point = NSPoint(x: button.frame.midX, y: button.frame.midY)
        if entry == "pointer" {
            let nativePoint = calendar.hosting.convert(calendar.panel.convertPoint(fromScreen: point), from: nil)
            let nativeHit = try #require(calendar.hosting.hitTest(nativePoint))
            try #require(nativeHit.window === calendar.panel)
            let hit = AccessibilityTestNode(object: try #require(
                calendar.hosting.accessibilityHitTest(point)
            ) as AnyObject)
            try #require(hit.role == .button && hit.label == button.label && hit.frame == button.frame)
            try #require(hit.object.accessibilityWindow?() as? NSWindow === calendar.panel)
        }
        // Preparation may scroll; Settings activation must preserve this prepared baseline.
        let before = (
            frame: calendar.panel.frame, caret: calendar.panel.caretXOffset,
            month: calendar.store.displayedMonth, selected: calendar.store.selectedDate,
            scroll: scroll.contentView.bounds.origin, draft: calendar.aiModel.draft,
            reopens: calendar.reopenActions.value, completions: calendar.completions
        )
        calendar.clearActionReceipts()
        switch entry {
        case "AX": try #require(button.press())
        case "pointer":
            try calendar.clickOwned(at: point)
        case "keyboard":
            try calendar.send(.returnKey)
        default: Issue.record("Unknown composed entry")
        }
        await settings.settle()
        let owner = try #require(settings.controller.window)
        #expect(owner.isVisible && owner.isKeyWindow && NSApp.keyWindow === owner)
        #expect(calendar.panel.settingsCalendarPriority === settings.controller.calendarPriority)
        #expect(calendar.panel.isVisible == pinned)
        #expect(calendar.store.isPinned == pinned && calendar.panel.isPinned == pinned)
        #expect(calendar.panel.frame == before.frame && calendar.panel.caretXOffset == before.caret)
        #expect(accessibilityScrollView(in: calendar.hosting) === scroll && scroll.documentView === document)
        if pinned {
            #expect(calendar.store.displayedMonth == before.month && calendar.store.selectedDate == before.selected)
            #expect(scroll.contentView.bounds.origin == before.scroll)
            #expect(calendar.aiModel.draft == before.draft)
        } else {
            #expect(!calendar.panel.isVisible && !calendar.aiModel.isEditorOpen)
            #expect(calendar.aiModel.draft.isEmpty && calendar.nativeEditorFields.isEmpty)
            #expect(calendar.store.displayedMonth == calendar.today)
        }
        #expect(calendar.reopenActions.value == before.reopens && calendar.completions == before.completions)
        #expect(calendar.actions.value.isEmpty && calendar.previousAppRestorations == 0)
        let root = owner.contentView
        let store = settings.controller.store
        delegate.showSettings()
        await settings.settle()
        #expect(settings.controller.window === owner && owner.contentView === root)
        #expect(settings.controller.store === store)
        #expect(calendar.reopenActions.value == before.reopens)
        let contextAfterHandoff = (month: calendar.store.displayedMonth, selected: calendar.store.selectedDate)
        owner.close()
        await calendar.settleRendering()
        #expect(calendar.panel.isVisible == pinned)
        #expect(calendar.panel.frame == before.frame && calendar.panel.caretXOffset == before.caret)
        #expect(calendar.store.isPinned == pinned && calendar.panel.isPinned == pinned)
        #expect(calendar.store.displayedMonth == contextAfterHandoff.month &&
                calendar.store.selectedDate == contextAfterHandoff.selected)
        #expect(calendar.reopenActions.value == before.reopens && calendar.completions == before.completions)
        #expect(calendar.previousAppRestorations == 0)
        if !pinned {
            try await calendar.openThroughShowOwner()
            #expect(calendar.store.displayedMonth == calendar.today && calendar.store.selectedDate == calendar.today)
            #expect(!calendar.aiModel.isEditorOpen && calendar.aiModel.draft.isEmpty)
            #expect(calendar.store.isPinned == pinned && calendar.panel.isPinned == pinned)
            #expect(calendar.reopenActions.value == before.reopens + 1 && calendar.completions == before.completions + 1)
            #expect(calendar.previousAppRestorations == 0)
        }
    }

    @Test
    func scrollingWhileRecordingKeepsMountedOwnerAndFootprint() async throws {
        let fixture = SettingsWindowTestFixture()
        defer { fixture.close() }
        try await fixture.open()
        let owner = try #require(fixture.controller.window)
        owner.setContentSize(NSSize(width: 520, height: 360))
        await fixture.settle()
        let before = try #require(fixture.nodes().first {
            $0.role == .button && $0.label == "Set and enable shortcut"
        }).frame.size
        try await fixture.startRecording()
        let cancellations = fixture.recordingChanges.value.filter { !$0 }.count
        let recorder = try #require(fixture.nodes().first {
            $0.role == .button && $0.label == "Cancel shortcut recording"
        })
        #expect(recorder.frame.size == before)
        let responder = owner.firstResponder
        try await fixture.reveal(.aiDateSearch)
        #expect(fixture.model.isRecording)
        #expect(owner.firstResponder === responder)
        #expect(fixture.recordingChanges.value.filter { !$0 }.count == cancellations)
        try await fixture.reveal(.general)
        #expect(fixture.model.isRecording)
        #expect(try #require(fixture.nodes().first { $0.label == "Cancel shortcut recording" }).frame.size == before)
        fixture.controller.cancelRecording()
        #expect(!fixture.model.isRecording)
        #expect(fixture.hotkey.backend.operations.isEmpty)
    }

    @Test(arguments: ["orderOut", "close", "minimize", "unpin", "calendarHide", "deactivationNotification"])
    func exactPairPriorityReleasesWithoutContextReset(boundary: String) async throws {
        let calendar = try CalendarKeyboardRootFixture(maximumHeight: 300)
        let settings = SettingsWindowTestFixture()
        defer { settings.close(); calendar.close() }
        try await calendar.openThroughShowOwner()
        let originalLevel = calendar.panel.level
        let placement = calendar.showOwner.prepareForSettingsPresentation()
        try await settings.open(visibleFrame: placement.visibleFrame, avoiding: placement.avoiding, calendar: placement.calendar)
        let owner = try #require(settings.controller.window)
        let frame = calendar.panel.frame
        let month = calendar.store.displayedMonth
        let reopens = calendar.reopenActions.value
        try #require(calendar.panel.settingsPriorityLevelToken != nil)
        switch boundary {
        case "orderOut": owner.orderOut(nil)
        case "close": owner.close()
        case "minimize":
            owner.miniaturize(nil)
            await settings.settle()
            #expect(calendar.panel.level == originalLevel)
            owner.deminiaturize(nil)
            owner.makeKeyAndOrderFront(nil)
            await settings.settle()
            #expect(calendar.panel.settingsPriorityLevelToken != nil)
            owner.orderOut(nil)
        case "unpin": calendar.panel.isPinned = false
        case "calendarHide": calendar.panel.orderOut(nil)
        case "deactivationNotification":
            NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        default: Issue.record("Unknown pair boundary")
        }
        await settings.settle()
        #expect(calendar.panel.settingsPriorityLevelToken == nil)
        #expect(calendar.panel.level == originalLevel)
        #expect(calendar.panel.frame == frame && calendar.store.displayedMonth == month)
        #expect(calendar.reopenActions.value == reopens)
        if boundary == "calendarHide" {
            calendar.panel.isPinned = false
            calendar.panel.isPinned = true
            #expect(!calendar.panel.isVisible)
        }
    }

    @Test
    func attachedSheetBlocksCurrentFrontKeyTextAndHiddenReopenBeforeEffects() async throws {
        let calendar = try CalendarKeyboardRootFixture(showAI: true)
        let settings = SettingsWindowTestFixture()
        defer { settings.close(); calendar.close() }
        try await calendar.openThroughShowOwner()
        let placement = calendar.showOwner.prepareForSettingsPresentation()
        try await settings.open(visibleFrame: placement.visibleFrame, avoiding: placement.avoiding, calendar: placement.calendar)
        let owner = try #require(settings.controller.window)
        let sheet = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        sheet.isReleasedWhenClosed = false
        defer { owner.endSheet(sheet); sheet.close() }
        owner.beginSheet(sheet, completionHandler: nil)
        await settings.settle()
        try #require(owner.attachedSheet === sheet && NSApp.keyWindow === sheet)
        let frame = calendar.panel.frame
        let responder = calendar.panel.firstResponder
        let month = calendar.store.displayedMonth
        let reopens = calendar.reopenActions.value
        let completions = calendar.completions
        let requests = calendar.editorPresentationRequests
        let sheetResponder = sheet.firstResponder
        calendar.panel.orderFront(nil)
        calendar.panel.makeKeyAndOrderFront(nil)
        calendar.panel.activateForTextInput()
        try calendar.showOwner.showCalendar()
        await calendar.settleRendering()
        #expect(NSApp.keyWindow === sheet && sheet.firstResponder === sheetResponder)
        #expect(calendar.panel.firstResponder === responder && !calendar.panel.isTextInputActive)
        #expect(calendar.panel.frame == frame && calendar.store.displayedMonth == month)
        #expect(calendar.editorPresentationRequests == requests)
        #expect(calendar.previousAppRestorations == 0)
        calendar.panel.orderOut(nil)
        try calendar.showOwner.showCalendar()
        await calendar.settleRendering()
        #expect(!calendar.panel.isVisible)
        #expect(calendar.reopenActions.value == reopens && calendar.completions == completions)
        #expect(NSApp.keyWindow === sheet)
        owner.endSheet(sheet)
        await settings.settle()
        try calendar.showOwner.showCalendar()
        #expect(calendar.panel.isVisible)
        #expect(calendar.reopenActions.value == reopens + 1)
    }

    @Test(arguments: ["full", "partial", "nonoverlap"])
    func deliveredCalendarClickTransfersPriorityAndReturningSettingsKeepsContext(overlap: String) async throws {
        let calendar = try CalendarKeyboardRootFixture(maximumHeight: 300)
        let settings = SettingsWindowTestFixture()
        defer { settings.close(); calendar.close() }
        try await calendar.openThroughShowOwner()
        let original = calendar.panel.level
        let placement = calendar.showOwner.prepareForSettingsPresentation()
        try await settings.open(visibleFrame: placement.visibleFrame, avoiding: placement.avoiding, calendar: placement.calendar)
        let owner = try #require(settings.controller.window)
        let frame = calendar.panel.frame
        switch overlap {
        case "full": owner.setFrameOrigin(frame.origin)
        case "partial": owner.setFrameOrigin(NSPoint(x: frame.midX, y: frame.midY))
        case "nonoverlap": owner.setFrameOrigin(NSPoint(x: frame.maxX + 12, y: frame.minY))
        default: Issue.record("Unknown overlap")
        }
        await settings.settle()
        try #require(calendar.panel.settingsPriorityLevelToken != nil)
        try calendar.loadOwnedAccessibilityTree()
        let date = try #require(calendar.accessibilityNodes().first {
            $0.role == .button && $0.label?.contains("2030") == true && $0.enabled
        })
        let reopens = calendar.reopenActions.value
        let month = calendar.store.displayedMonth
        calendar.clearActionReceipts()
        // This is deliberately delivered to the exact calendar by the owned
        // test application's native queue; physical frontmost hit acceptance
        // for an overlapped point remains a separate capture obligation.
        try calendar.clickOwned(at: NSPoint(x: date.frame.midX, y: date.frame.midY))
        await calendar.settleRendering()
        #expect(calendar.actions.value.count == 1 && calendar.actions.value.first?.hasPrefix("date:") == true)
        #expect(calendar.actionCurrentEvents.value == [true])
        #expect(calendar.panel.level == original && calendar.panel.settingsPriorityLevelToken == nil)
        #expect(calendar.panel.isKeyWindow || calendar.panel.isMainWindow)
        let selected = calendar.store.selectedDate
        owner.makeKeyAndOrderFront(nil)
        await settings.settle()
        #expect(NSApp.keyWindow === owner && calendar.panel.settingsPriorityLevelToken != nil)
        #expect(calendar.panel.frame == frame && calendar.store.displayedMonth == month)
        #expect(calendar.store.selectedDate == selected && calendar.reopenActions.value == reopens)
    }

    @Test
    func keyResignationDuringOwnedPopupCancelsRecordingAndRetainsPriority() async throws {
        let calendar = try CalendarKeyboardRootFixture()
        let settings = SettingsWindowTestFixture()
        defer { settings.close(); calendar.close() }
        try await calendar.openThroughShowOwner()
        let placement = calendar.showOwner.prepareForSettingsPresentation()
        try await settings.open(visibleFrame: placement.visibleFrame, avoiding: placement.avoiding, calendar: placement.calendar)
        try await settings.startRecording()
        try await settings.reveal(.calendar)
        let token = try #require(calendar.panel.settingsPriorityLevelToken)
        let picker = try #require(settings.nodes().first { $0.role == .popUpButton && $0.label == "Week starts on" })
        var observedInsideTracking = false
        let selection = NativePickerSelection(
            expectedTitles: Calendar.current.weekdaySymbols,
            selectedTitle: Calendar.current.weekdaySymbols[settings.store.startOfWeekday - 1],
            onAction: {
                observedInsideTracking = true
                // Exercise the exact delegate boundary during the real menu's
                // tracking lease; runtime capture must establish whether the
                // platform itself delivered a key-resignation notification.
                settings.controller.windowDidResignKey(Notification(
                    name: NSWindow.didResignKeyNotification,
                    object: settings.controller.window
                ))
                #expect(!settings.model.isRecording)
                #expect(calendar.panel.settingsPriorityLevelToken == token)
                #expect(settings.controller.window?.level == .normal)
            }
        )
        defer { selection.close() }
        try #require(picker.press())
        try await selection.waitUntilTrackingEnds()
        #expect(observedInsideTracking && selection.actionAttempted && selection.trackingEnded && !selection.timedOut)
        #expect(calendar.panel.settingsPriorityLevelToken == token)
        #expect(calendar.panel.isVisible)
    }

    @Test(arguments: [NSSize(width: 600, height: 600), NSSize(width: 520, height: 360)])
    func onePageControllerKeepsNativeGeometryAndSingleDocument(size: NSSize) async throws {
        let settings = SettingsWindowTestFixture()
        defer { settings.close() }
        try await settings.open()
        let owner = try #require(settings.controller.window)
        let initialRoot = try #require(owner.contentView)
        let initialMinimumConstraints = initialRoot.constraints.filter {
            $0.identifier?.hasPrefix("Glimpse.Settings.minimum") == true
        }
        #expect(initialMinimumConstraints.count == 2)
        #expect(initialMinimumConstraints.allSatisfy {
            $0.isActive && $0.priority == .required && ($0.firstItem as? NSView) === initialRoot &&
                $0.secondItem == nil && $0.relation == .greaterThanOrEqual
        })
        #expect(initialMinimumConstraints.filter { $0.firstAttribute == .width && $0.constant == 520 }.count == 1)
        #expect(initialMinimumConstraints.filter { $0.firstAttribute == .height && $0.constant == 360 }.count == 1)
        owner.setContentSize(NSSize(width: 400, height: 250))
        await settings.settle()
        let resizedContent = owner.contentRect(forFrameRect: owner.frame).size
        let minimumConstraints = initialRoot.constraints.filter {
            $0.identifier?.hasPrefix("Glimpse.Settings.minimum") == true
        }.prefix(2).map {
            ($0.identifier ?? "", $0.firstAttribute.rawValue, $0.relation.rawValue,
             $0.constant, $0.isActive, $0.firstItem as? NSView === initialRoot)
        }
        print("GLIMPSE_SETTINGS_RESIZE_FLOOR stage=after-native-setContentSize requested=(400,250) actual=\(resizedContent) contentMinSize=\(owner.contentMinSize) constraints=\(minimumConstraints) rootIsWindowContent=\(owner.contentView === initialRoot) rootBounds=\(initialRoot.bounds)")
        #expect(resizedContent == NSSize(width: 520, height: 360))
        let resizedMinimumConstraints = initialRoot.constraints.filter {
            $0.identifier?.hasPrefix("Glimpse.Settings.minimum") == true
        }
        #expect(resizedMinimumConstraints.count == 2)
        #expect(resizedMinimumConstraints.allSatisfy {
            $0.isActive && $0.priority == .required && ($0.firstItem as? NSView) === initialRoot &&
                $0.secondItem == nil && $0.relation == .greaterThanOrEqual
        })
        #expect(resizedMinimumConstraints.filter { $0.firstAttribute == .width && $0.constant == 520 }.count == 1)
        #expect(resizedMinimumConstraints.filter { $0.firstAttribute == .height && $0.constant == 360 }.count == 1)
        owner.setContentSize(size)
        await settings.settle()
        #expect(owner.contentRect(forFrameRect: owner.frame).size == size)
        let root = try #require(owner.contentView)
        let scroll = try #require(accessibilityScrollView(in: root))
        let document = try #require(scroll.documentView)
        let headings = settings.nodes().filter { $0.role?.rawValue == "AXHeading" }
        #expect(headings.map { $0.label ?? ($0.value as? String) ?? "" } ==
                ["Opening Glimpse", "Menu bar", "Calendar", "AI date search"])
        #expect(!scroll.hasHorizontalScroller)
        for section in SettingsSection.allCases {
            try await settings.reveal(section)
            #expect(owner.contentView === root && scroll.documentView === document)
            #expect(owner.contentRect(forFrameRect: owner.frame).size == size)
        }
        owner.orderOut(nil)
        try await settings.open()
        #expect(settings.controller.window === owner && owner.contentView === root)
        #expect(accessibilityScrollView(in: root) === scroll && scroll.documentView === document)
        let reopenedMinimumConstraints = root.constraints.filter {
            $0.identifier?.hasPrefix("Glimpse.Settings.minimum") == true
        }
        #expect(reopenedMinimumConstraints.count == 2)
        #expect(reopenedMinimumConstraints.allSatisfy {
            $0.isActive && $0.priority == .required && ($0.firstItem as? NSView) === root &&
                $0.secondItem == nil && $0.relation == .greaterThanOrEqual
        })
        #expect(reopenedMinimumConstraints.filter { $0.firstAttribute == .width && $0.constant == 520 }.count == 1)
        #expect(reopenedMinimumConstraints.filter { $0.firstAttribute == .height && $0.constant == 360 }.count == 1)
        #expect(owner.contentRect(forFrameRect: owner.frame).size == size)
        print("GLIMPSE_SETTINGS_RESIZE_FLOOR stage=after-public-reopening contentMinSize=\(owner.contentMinSize) contentSize=\(owner.contentRect(forFrameRect: owner.frame).size) rootIsWindowContent=\(owner.contentView === root) documentUnchanged=\(scroll.documentView === document)")
        owner.setContentSize(NSSize(width: 400, height: 250))
        await settings.settle()
        #expect(owner.contentRect(forFrameRect: owner.frame).size == NSSize(width: 520, height: 360))
        #expect(settings.controller.window === owner && owner.contentView === root)
        #expect(accessibilityScrollView(in: root) === scroll && scroll.documentView === document)
        print("GLIMPSE_SETTINGS_RESIZE_FLOOR stage=after-reopened-native-setContentSize requested=(400,250) actual=\(owner.contentRect(forFrameRect: owner.frame).size) contentMinSize=\(owner.contentMinSize) rootIsWindowContent=\(owner.contentView === root) documentUnchanged=\(scroll.documentView === document)")
        owner.setContentSize(size)
        await settings.settle()
        #expect(owner.contentRect(forFrameRect: owner.frame).size == size)
        #expect(settings.controller.window === owner && owner.contentView === root)
        #expect(accessibilityScrollView(in: root) === scroll && scroll.documentView === document)
    }

    @Test(arguments: ["hideReopen", "settingsHandoff"])
    func footerLifecycleDiscardsHeldEditorAndConfirmationIntent(boundary: String) async throws {
        let calendar = try CalendarKeyboardRootFixture(showAI: true, holdEditorPresentation: true)
        let settings = SettingsWindowTestFixture()
        defer { settings.close(); calendar.close() }
        try await calendar.openThroughShowOwner()
        try calendar.loadOwnedAccessibilityTree()
        calendar.aiModel.setEditorOpen(true)
        calendar.aiModel.setDraft("Held lifecycle draft")
        await calendar.settleRendering()
        try #require(calendar.heldEditorPresentations.count == 1)
        try #require(try calendar.ownedControl("Quit Glimpse").press())
        await calendar.settleRendering()
        try #require(calendar.lastPublishedOwner == .quitCancel)
        if boundary == "hideReopen" {
            calendar.panel.orderOut(nil)
            try await calendar.openThroughShowOwner()
        } else {
            let placement = calendar.showOwner.prepareForSettingsPresentation()
            try await settings.open(
                visibleFrame: placement.visibleFrame, avoiding: placement.avoiding,
                calendar: placement.calendar
            )
        }
        calendar.completeHeldEditorPresentation()
        await calendar.settleRendering()
        #expect(calendar.presentationSnapshot?.editorFocused == false)
        #expect(calendar.lastPublishedOwner != .quitCancel && calendar.lastPublishedOwner != .quitConfirm)
        #expect(calendar.submissions.isEmpty && calendar.terminationReceipts == 0)
        if boundary == "hideReopen" {
            #expect(try calendar.ownedControl("Quit Glimpse").enabled)
            #expect(calendar.nativeEditorFields.isEmpty)
        } else {
            #expect(NSApp.keyWindow === settings.controller.window)
            #expect(calendar.aiModel.isEditorOpen && calendar.aiModel.draft == "Held lifecycle draft")
        }
    }

    @Test(arguments: ["foreignLevel", "foreignToken", "replacement", "disposalBeforeReplacement", "staleActivation"])
    func cleanupCannotOverwriteNewOwnership(boundary: String) async throws {
        let calendar = try CalendarKeyboardRootFixture()
        let settings = SettingsWindowTestFixture()
        defer { settings.close(); calendar.close() }
        try await calendar.openThroughShowOwner()
        let original = calendar.panel.level
        let placement = calendar.showOwner.prepareForSettingsPresentation()
        try await settings.open(visibleFrame: placement.visibleFrame, avoiding: placement.avoiding, calendar: placement.calendar)
        let owner = try #require(settings.controller.window)
        let frame = calendar.panel.frame
        let reopens = calendar.reopenActions.value
        let token = try #require(calendar.panel.settingsPriorityLevelToken)
        switch boundary {
        case "foreignLevel":
            calendar.panel.level = .floating
            settings.controller.calendarPriority.reconcile()
            #expect(calendar.panel.level == .floating)
            owner.orderOut(nil)
            #expect(calendar.panel.level == .floating)
        case "foreignToken":
            let foreign = UUID()
            calendar.panel.settingsPriorityLevelToken = foreign
            settings.controller.calendarPriority.reconcile()
            #expect(calendar.panel.settingsPriorityLevelToken == foreign)
        case "staleActivation":
            NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
            settings.controller.calendarPriority.settingsWasPresented()
            await settings.settle()
            #expect(calendar.panel.settingsPriorityLevelToken == token)
        case "replacement", "disposalBeforeReplacement":
            settings.controller.calendarPriority.invalidate()
            var old: SettingsCalendarPriority? = SettingsCalendarPriority()
            old?.bind(settings: owner, calendar: calendar.panel)
            old?.settingsWasPresented()
            if boundary == "disposalBeforeReplacement" { old = nil }
            let replacement = SettingsCalendarPriority()
            replacement.bind(settings: owner, calendar: calendar.panel)
            replacement.settingsWasPresented()
            let replacementToken = try #require(calendar.panel.settingsPriorityLevelToken)
            #expect(replacementToken != token)
            old?.invalidate()
            await settings.settle()
            #expect(calendar.panel.settingsCalendarPriority === replacement)
            #expect(calendar.panel.settingsPriorityLevelToken == replacementToken)
            replacement.invalidate()
            #expect(calendar.panel.level == original)
        default: Issue.record("Unknown cleanup boundary")
        }
        #expect(calendar.panel.frame == frame && calendar.reopenActions.value == reopens)
    }

    @Test
    func disposalAloneRestoresPriorityWithoutReplacementOrManualInvalidation() async throws {
        let calendar = try CalendarKeyboardRootFixture(showAI: true, maximumHeight: 300)
        let settings = SettingsWindowTestFixture()
        defer { settings.close(); calendar.close() }
        try await calendar.openThroughShowOwner()
        calendar.store.send(.goToNextMonth)
        let selected = try #require(calendar.store.days.dropFirst(20).first?.date)
        calendar.store.send(.dateTapped(selected))
        calendar.aiModel.setDraft("Retain disposal-alone context")
        await calendar.settleRendering()
        let original = calendar.panel.level
        let placement = calendar.showOwner.prepareForSettingsPresentation()
        try await settings.open(visibleFrame: placement.visibleFrame, avoiding: placement.avoiding, calendar: placement.calendar)
        let owner = try #require(settings.controller.window)
        settings.controller.calendarPriority.invalidate()
        try #require(calendar.panel.level == original)
        var coordinator: SettingsCalendarPriority? = SettingsCalendarPriority()
        weak var releasedCoordinator = coordinator
        coordinator?.bind(settings: owner, calendar: calendar.panel)
        coordinator?.settingsWasPresented()
        let token = try #require(calendar.panel.settingsPriorityLevelToken)
        weak var releasedCleanup = calendar.panel.settingsPriorityCleanup
        try #require(releasedCleanup?.levelOverride?.token == token)
        try #require(releasedCleanup?.levelOverride?.original == original)
        let applied = try #require(releasedCleanup?.levelOverride?.applied)
        try #require(calendar.panel.level == applied && applied != original)
        try #require(calendar.panel.settingsCalendarPriority === coordinator)
        let scroll = try #require(accessibilityScrollView(in: calendar.hosting))
        let before = (
            frame: calendar.panel.frame, caret: calendar.panel.caretXOffset,
            month: calendar.store.displayedMonth, selected: calendar.store.selectedDate,
            scroll: scroll.contentView.bounds.origin, draft: calendar.aiModel.draft,
            editor: calendar.aiModel.isEditorOpen, pin: calendar.panel.isPinned,
            storePin: calendar.store.isPinned, presentation: calendar.presentationSnapshot,
            responder: calendar.panel.firstResponder, reopens: calendar.reopenActions.value,
            completions: calendar.completions
        )
        // Only release the coordinator. No replacement or explicit invalidation
        // may repair its queued deinit cleanup before this convergence oracle.
        let actionsBeforeDisposal = calendar.actions.value
        let actionEventsBeforeDisposal = calendar.actionCurrentEvents.value
        coordinator = nil
        #expect(releasedCoordinator == nil && calendar.panel.settingsCalendarPriority == nil)
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while ContinuousClock.now < deadline {
            if calendar.panel.level == original,
               calendar.panel.settingsPriorityLevelToken == nil,
               calendar.panel.settingsPriorityCleanup == nil,
               releasedCleanup == nil { break }
            await calendar.opportunityForFocusRendering()
        }
        #expect(calendar.panel.level == original)
        #expect(calendar.panel.settingsPriorityLevelToken == nil)
        #expect(calendar.panel.settingsPriorityCleanup == nil && releasedCleanup == nil)
        #expect(calendar.panel.settingsCalendarPriority == nil && releasedCoordinator == nil)
        #expect(calendar.panel.frame == before.frame && calendar.panel.caretXOffset == before.caret)
        #expect(calendar.store.displayedMonth == before.month && calendar.store.selectedDate == before.selected)
        #expect(scroll.contentView.bounds.origin == before.scroll)
        #expect(calendar.aiModel.draft == before.draft && calendar.aiModel.isEditorOpen == before.editor)
        #expect(calendar.panel.isPinned == before.pin && calendar.store.isPinned == before.storePin)
        #expect(calendar.presentationSnapshot == before.presentation && calendar.panel.firstResponder === before.responder)
        #expect(calendar.reopenActions.value == before.reopens && calendar.completions == before.completions)
        #expect(calendar.actions.value == actionsBeforeDisposal)
        #expect(calendar.actionCurrentEvents.value == actionEventsBeforeDisposal)
        #expect(calendar.submissions.isEmpty && calendar.terminationReceipts == 0)
    }

    @Test(arguments: [
        CalendarKeyboardOwner.footerQuit, .footerAbout, .footerPin, .footerCalendar, .footerSettings
    ], [CalendarOwnedKey.returnKey, .keypadEnter, .space])
    func injectedFooterActionsHonorNativeDownRepeatUpAndAXAfterKeyboard(
        owner: CalendarKeyboardOwner, key: CalendarOwnedKey
    ) async throws {
        let sender = try CalendarKeyboardRootFixture()
        let footer = CalendarFooterOwnedHost()
        defer { footer.close(); sender.close() }
        logCalendarKeyboardTarget(footer.window, stage: "footer-case-\(owner.rawValue)-\(key.rawValue)")
        try await footer.open()
        for _ in 0..<12 {
            if footer.owner == owner { break }
            try sender.send(.tab, toWindow: footer.window)
            await footer.settle()
        }
        try #require(footer.owner == owner)
        let before = footer.invocations.count
        let phasesBefore = sender.ownedPhaseReceipts.count
        try sender.sendPhase(key, phase: .down, toWindow: footer.window)
        #expect(footer.receipts == [owner: 1])
        #expect(footer.invocations.count == before + 1)
        let invocation = try #require(footer.invocations.last)
        #expect(invocation.owner == owner && invocation.key == key.routerKey)
        #expect(invocation.phase == .down && invocation.route == .activate)
        #expect(invocation.context.allowsRouting && footer.currentEvents.allSatisfy { $0 })
        for _ in 0..<3 { try sender.sendPhase(key, phase: .repeatPress, toWindow: footer.window) }
        #expect(footer.receipts == [owner: 1], "Native fallback must not duplicate handled down/repeat")
        #expect(footer.invocations.suffix(3).allSatisfy { $0.phase == .repeatPress && $0.route == .consume })
        try sender.sendPhase(key, phase: .up, toWindow: footer.window)
        #expect(footer.receipts == [owner: 1] && footer.invocations.count == before + 4)
        sender.expectOwnedPhases(after: phasesBefore, key: key, window: footer.window,
                               phases: [.down, .repeatPress, .repeatPress, .repeatPress, .up])
        let name = footer.name(for: owner)
        let button = try #require(footer.nodes().first { $0.role == .button && $0.label == name })
        #expect(button.press(), "AX remains usable after an owned keyboard event")
        await footer.settle()
        #expect(footer.receipts == [owner: 2])
        try sender.send(.backTab, toWindow: footer.window)
        await footer.settle()
        if owner != .footerQuit { #expect(footer.owner != owner) }
    }

    @Test(arguments: [CalendarOwnedKey.returnKey, .keypadEnter, .space])
    func quitConfirmationOwnsHeldActivationAndRecordsOnlyDeliberateTermination(key: CalendarOwnedKey) async throws {
        let fixture = try CalendarKeyboardRootFixture(maximumHeight: 300)
        defer { fixture.close() }
        try await fixture.openThroughShowOwner()
        try fixture.loadOwnedAccessibilityTree()
        try await fixture.focusOwner(.footerQuit)
        let normal = try fixture.ownedControl("Quit Glimpse").frame
        let phasesBefore = fixture.ownedPhaseReceipts.count
        let callbacksBefore = fixture.callbackRows.count
        try fixture.sendPhase(key, phase: .down)
        await fixture.settleRendering()
        try #require(fixture.lastPublishedOwner == .quitCancel)
        fixture.expectInvocation(after: callbacksBefore, owner: .footerQuit, key: key.routerKey, route: "activate")
        #expect(fixture.terminationReceipts == 0 && fixture.actions.value.isEmpty)
        let cancel = try fixture.ownedControl("Cancel quitting Glimpse")
        let confirm = try fixture.ownedControl("Confirm quitting Glimpse")
        #expect(abs(cancel.frame.height - 28) < 0.5 && abs(confirm.frame.height - 28) < 0.5)
        #expect(abs(cancel.frame.midY - normal.midY) < 0.5)
        if ProcessInfo.processInfo.environment["GLIMPSE_KEYBOARD_ARTIFACT_DIR"] != nil {
            try fixture.saveFocusedDateBitmap(
                fixture.panel.convertToScreen(fixture.hosting.convert(fixture.hosting.bounds, to: nil)),
                name: "footer-quit-confirmation-\(key.rawValue)"
            )
        }
        for _ in 0..<3 {
            let count = fixture.callbackRows.count
            try fixture.sendPhase(key, phase: .repeatPress)
            fixture.expectInvocation(after: count, owner: .footerQuit, key: key.routerKey, route: "consume", phase: "repeatPress")
            #expect(fixture.lastPublishedOwner == .quitCancel && fixture.terminationReceipts == 0)
            #expect(fixture.actions.value.isEmpty && fixture.submissions.isEmpty)
        }
        let callbacksBeforeRelease = fixture.callbackRows.count
        try fixture.sendPhase(key, phase: .up)
        await fixture.settleRendering()
        #expect(fixture.lastPublishedOwner == .quitCancel && fixture.terminationReceipts == 0)
        #expect(fixture.actions.value.isEmpty && fixture.submissions.isEmpty)
        #expect(fixture.callbackRows.count == callbacksBeforeRelease, "The local handler observes down/repeat; release has a sender receipt")
        fixture.expectOwnedPhases(after: phasesBefore, key: key, window: fixture.panel,
                                 phases: [.down, .repeatPress, .repeatPress, .repeatPress, .up])
        let releasedCancel = try fixture.ownedControl("Cancel quitting Glimpse")
        print("GLIMPSE_QUIT_RELEASED_CANCEL axFocused=\(releasedCancel.object.isAccessibilityFocused?() == true) keyWindowOwned=\(NSApp.keyWindow === fixture.panel) visible=\(fixture.panel.isVisible) responderClass=\(fixture.panel.firstResponder.map { NSStringFromClass(type(of: $0)) } ?? "nil") responderIsWindow=\(fixture.panel.firstResponder === fixture.panel) responderViewOwned=\((fixture.panel.firstResponder as? NSView)?.window === fixture.panel)")
        let freshCancelPhasesBefore = fixture.ownedPhaseReceipts.count
        let freshCancelCallbacksBefore = fixture.callbackRows.count
        try fixture.send(key)
        fixture.expectInvocation(after: freshCancelCallbacksBefore, owner: .quitCancel, key: key.routerKey, route: "activate")
        await fixture.settleRendering()
        try #require(fixture.lastPublishedOwner == .footerQuit)
        #expect(fixture.terminationReceipts == 0 && fixture.actions.value.isEmpty && fixture.submissions.isEmpty)
        fixture.expectOwnedPhases(after: freshCancelPhasesBefore, key: key, window: fixture.panel, phases: [.down, .up])
        try fixture.send(key)
        await fixture.settleRendering()
        try #require(fixture.lastPublishedOwner == .quitCancel)
        try fixture.send(.escape, modifiers: .command)
        #expect(try fixture.ownedControl("Cancel quitting Glimpse").enabled)
        try fixture.send(.escape)
        await fixture.settleRendering()
        try #require(fixture.lastPublishedOwner == .footerQuit)
        try fixture.send(.escape, repeatPress: true)
        #expect(fixture.panel.isVisible && fixture.terminationReceipts == 0)
        try fixture.send(key)
        await fixture.settleRendering()
        try #require(fixture.lastPublishedOwner == .quitCancel)
        try fixture.send(.tab)
        await fixture.settleRendering()
        try #require(fixture.lastPublishedOwner == .quitConfirm)
        let deliberatePhasesBefore = fixture.ownedPhaseReceipts.count
        let confirmCallbacksBefore = fixture.callbackRows.count
        try fixture.sendPhase(key, phase: .down)
        fixture.expectInvocation(after: confirmCallbacksBefore, owner: .quitConfirm, key: key.routerKey, route: "activate")
        #expect(fixture.terminationReceipts == 1)
        for _ in 0..<3 { try fixture.sendPhase(key, phase: .repeatPress) }
        try fixture.sendPhase(key, phase: .up)
        fixture.expectOwnedPhases(after: deliberatePhasesBefore, key: key, window: fixture.panel,
                                 phases: [.down, .repeatPress, .repeatPress, .repeatPress, .up])
        #expect(fixture.terminationReceipts == 1)
        #expect(fixture.actions.value.isEmpty && fixture.submissions.isEmpty)
    }

    @Test(arguments: [false, true])
    func olderAIRequestCannotReclaimCancelOrReturnedQuit(cancelFirst: Bool) async throws {
        let fixture = try CalendarKeyboardRootFixture(showAI: true, holdEditorPresentation: true)
        defer { fixture.close() }
        try await fixture.openThroughShowOwner()
        fixture.aiModel.setEditorOpen(true)
        fixture.aiModel.setDraft("Retain held footer draft")
        await fixture.settleRendering()
        try #require(fixture.heldEditorPresentations.count == 1)
        try #require(try fixture.ownedControl("Quit Glimpse").press())
        await fixture.settleRendering()
        try #require(fixture.lastPublishedOwner == .quitCancel)
        if cancelFirst {
            let quitBeforeCancel = fixture.accessibilityNodes().filter { $0.role == .button && $0.label == "Quit Glimpse" }
            print("GLIMPSE_HELD_AI_OWNER stage=before-cancel keyWindowOwned=\(NSApp.keyWindow === fixture.panel) visible=\(fixture.panel.isVisible) responderOwned=\(fixture.panel.firstResponder === fixture.panel || (fixture.panel.firstResponder as? NSView)?.window === fixture.panel) returnedQuitAXPresent=\(quitBeforeCancel.count == 1) ownerIsCancel=\(fixture.lastPublishedOwner == .quitCancel)")
            try #require(try fixture.ownedControl("Cancel quitting Glimpse").press())
            await fixture.settleRendering()
            let returnedQuit = fixture.accessibilityNodes().filter { $0.role == .button && $0.label == "Quit Glimpse" }
            print("GLIMPSE_HELD_AI_OWNER stage=after-cancel keyWindowOwned=\(NSApp.keyWindow === fixture.panel) visible=\(fixture.panel.isVisible) responderOwned=\(fixture.panel.firstResponder === fixture.panel || (fixture.panel.firstResponder as? NSView)?.window === fixture.panel) returnedQuitAXPresent=\(returnedQuit.count == 1) returnedQuitEnabled=\(returnedQuit.first?.enabled == true) returnedQuitFocused=\(returnedQuit.first?.object.isAccessibilityFocused?() == true) ownerNil=\(fixture.lastPublishedOwner == nil) ownerIsReturnedQuit=\(fixture.lastPublishedOwner == .footerQuit) heldCount=\(fixture.heldEditorPresentations.count)")
            try #require(fixture.lastPublishedOwner == .footerQuit)
        }
        let responder = fixture.panel.firstResponder
        let ownerBeforeRelease = fixture.lastPublishedOwner
        print("GLIMPSE_HELD_AI_OWNER stage=before-release cancelFirst=\(cancelFirst) ownerNil=\(ownerBeforeRelease == nil) ownerMatchesExpected=\(ownerBeforeRelease == (cancelFirst ? .footerQuit : .quitCancel)) heldCount=\(fixture.heldEditorPresentations.count)")
        fixture.completeHeldEditorPresentation()
        await fixture.settleRendering()
        print("GLIMPSE_HELD_AI_OWNER stage=after-release cancelFirst=\(cancelFirst) ownerNil=\(fixture.lastPublishedOwner == nil) ownerUnchanged=\(fixture.lastPublishedOwner == ownerBeforeRelease) responderUnchanged=\(fixture.panel.firstResponder === responder) editorFocused=\(fixture.presentationSnapshot?.editorFocused == true)")
        #expect(fixture.lastPublishedOwner == (cancelFirst ? .footerQuit : .quitCancel))
        #expect(fixture.panel.firstResponder === responder)
        #expect(fixture.presentationSnapshot?.editorFocused == false)
        #expect(fixture.aiModel.isEditorOpen && fixture.aiModel.draft == "Retain held footer draft")
        #expect(fixture.submissions.isEmpty && fixture.terminationReceipts == 0)
        fixture.aiModel.setEditorOpen(false)
        await fixture.settleRendering()
        fixture.aiModel.setEditorOpen(true)
        await fixture.settleRendering()
        try #require(fixture.heldEditorPresentations.count == 1)
        fixture.completeHeldEditorPresentation()
        await fixture.settleRendering()
        #expect(fixture.presentationSnapshot?.editorFocused == true)
        #expect(fixture.submissions.isEmpty && fixture.terminationReceipts == 0)
    }

    @Test
    func completionGuardsDoNotResetUnpreparedHiddenOrNonkeyPanels() async throws {
        let fixture = try CalendarKeyboardRootFixture()
        defer { fixture.close() }
        #expect(!fixture.panel.completeReopenPresentation())
        #expect(fixture.completions == 0)
        fixture.panel.prepareForReopen()
        #expect(!fixture.panel.completeReopenPresentation())
        #expect(fixture.completions == 0)
        fixture.panel.makeKeyAndOrderFront(nil)
        let peer = CalendarKeyboardOwnedPeer()
        defer { peer.close() }
        try peer.makeKey()
        #expect(!fixture.panel.completeReopenPresentation())
        #expect(fixture.completions == 0)
        fixture.panel.makeKeyAndOrderFront(nil)
        #expect(fixture.panel.completeReopenPresentation())
        #expect(fixture.completions == 1)
        await fixture.settleRendering()
        try fixture.send(.tab)
        let responder = fixture.panel.firstResponder
        #expect(!fixture.panel.completeReopenPresentation())
        let responderRetained = fixture.panel.firstResponder === responder
        #expect(responderRetained)
        #expect(fixture.completions == 1)
        try fixture.send(.returnKey)
        #expect(fixture.actions.value == ["previousMonth"])
        #expect(fixture.actionCurrentEvents.value == [true])
    }

    @Test(arguments: [false, true])
    func focusedUpdateActionKeepsNativeKeyboardActivation(dark: Bool) async throws {
        let fixture = UpdaterFixture()
        let sender = try CalendarKeyboardRootFixture()
        let host = AboutUpdateHost(
            updater: fixture.updater,
            fullAbout: true,
            appearance: NSAppearance(named: dark ? .darkAqua : .aqua)
        )
        defer { host.close(); sender.close(); fixture.delay.drain() }
        await host.settle()
        try host.saveRender(named: "update-nonkey-\(dark ? "dark" : "light")")
        host.window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        try #require(host.window.makeFirstResponder(nil))
        await host.settle(ownsKey: true)
        try sender.loadOwnedAccessibilityTree()
        for _ in 0..<6 {
            if host.control("Check for updates")?.object.isAccessibilityFocused?() == true { break }
            try sender.send(.tab, toWindow: host.window)
            await host.settle(ownsKey: true)
        }
        let check = try #require(host.control("Check for updates"))
        try #require(check.object.isAccessibilityFocused?() == true)
        #expect(check.accessibilityRole() == .button && check.isAccessibilityEnabled())
        #expect(fixture.backend.checkCount == 0 && fixture.driver.status == .idle)
        try host.saveRender(named: "update-focused-\(dark ? "dark" : "light")")
        try sender.send(.space, toWindow: host.window)
        await host.settle(ownsKey: true)
        #expect(fixture.backend.checkCount == 1 && fixture.driver.status == .checking)
    }
}

/// Observe the selected owned target without changing presentation or admission.
@MainActor
private func logCalendarKeyboardTarget(
    _ window: NSWindow, stage: String, file: StaticString = #fileID, line: UInt = #line
) {
    let appKey = NSApp.keyWindow
    let appKeyIdentity = appKey.map { "\(ObjectIdentifier($0))/\($0.windowNumber)" } ?? "nil"
    print("GLIMPSE_KEYBOARD_TARGET stage=\(stage) caller=\(file):\(line) target=\(ObjectIdentifier(window))/\(window.windowNumber) targetClass=\(String(reflecting: type(of: window))) visible=\(window.isVisible) key=\(window.isKeyWindow) canBecomeKey=\(window.canBecomeKey) canBecomeMain=\(window.canBecomeMain) appActivationPolicy=\(NSApp.activationPolicy().rawValue) appKeyWindow=\(appKeyIdentity) appKeyMatchesTarget=\(appKey === window) appActive=\(NSApp.isActive)")
}

/// Real production footer with injected external actions and current native context.
/// It is a key-window fixture only inside the opt-in serialized acceptance suite.
@MainActor
private final class CalendarFooterOwnedHost {
    let window = NSWindow(
        contentRect: NSRect(x: -1600, y: -1600, width: 280, height: 60),
        styleMask: [.titled], backing: .buffered, defer: false
    )
    let relay = CalendarKeyboardOwnerRelay()
    var owner: CalendarKeyboardOwner?
    var receipts: [CalendarKeyboardOwner: Int] = [:]
    var invocations: [CalendarKeyboardInvocation] = []
    var currentEvents: [Bool] = []
    private(set) var hosting: NSHostingView<AnyView>?

    init() {
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: AnyView(
            CalendarFooterOwnedRow(fixture: self).environment(\.accessibilityEnabled, true)
        ))
        hosting = host
        window.contentView = host
    }

    func context() -> CalendarKeyboardContext {
        .init(
            visible: window.isVisible, key: window.isKeyWindow && NSApp.keyWindow === window,
            eventForPanel: NSApp.currentEvent?.window === window,
            editingText: window.firstResponder is NSTextView
        )
    }

    func record(_ owner: CalendarKeyboardOwner) { receipts[owner, default: 0] += 1 }
    func observe(_ invocation: CalendarKeyboardInvocation) {
        invocations.append(invocation)
        currentEvents.append(NSApp.currentEvent?.window === window && NSApp.currentEvent?.type == .keyDown)
    }
    func name(for owner: CalendarKeyboardOwner) -> String {
        switch owner {
        case .footerQuit: "Quit Glimpse"
        case .footerAbout: "About Glimpse"
        case .footerPin: "Pin calendar window"
        case .footerCalendar: "Open Calendar app"
        default: "Open Glimpse Settings"
        }
    }

    func open(file: StaticString = #fileID, line: UInt = #line) async throws {
        logCalendarKeyboardTarget(window, stage: "footer-open-before", file: file, line: line)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        try #require(window.makeFirstResponder(nil))
        logCalendarKeyboardTarget(window, stage: "footer-open-presented", file: file, line: line)
        await settle()
        logCalendarKeyboardTarget(window, stage: "footer-open-settled", file: file, line: line)
        try #require(NSApp.keyWindow === window)
    }

    func nodes() -> [AccessibilityTestNode] {
        var queue: [Any] = hosting.map { [$0] } ?? []
        var result: [AccessibilityTestNode] = []
        var visited: Set<ObjectIdentifier> = []
        var index = 0
        while index < queue.count {
            let object = queue[index] as AnyObject
            index += 1
            guard object.responds?(to: #selector(NSAccessibilityProtocol.accessibilityRole)) == true,
                  visited.insert(ObjectIdentifier(object)).inserted else { continue }
            let node = AccessibilityTestNode(object: object)
            result.append(node)
            queue.append(contentsOf: node.children + node.contents + node.visibleChildren)
        }
        return result
    }

    func settle() async {
        for _ in 0..<8 {
            hosting?.layoutSubtreeIfNeeded()
            hosting?.displayIfNeeded()
            pumpRunLoop()
            await Task.yield()
        }
    }

    private func pumpRunLoop() {
        CFRunLoopRunInMode(.defaultMode, 0.01, true)
    }

    func close() {
        window.contentView = nil
        hosting = nil
        window.close()
    }
}

@MainActor
private struct CalendarFooterOwnedRow: View {
    let fixture: CalendarFooterOwnedHost
    @FocusState private var focus: CalendarKeyboardOwner?

    var body: some View {
        CalendarFooterControls(
            isPinned: false,
            quit: { fixture.record(.footerQuit) }, about: { fixture.record(.footerAbout) },
            togglePin: { fixture.record(.footerPin) }, openCalendar: { fixture.record(.footerCalendar) },
            openSettings: { fixture.record(.footerSettings) },
            keyboardContext: fixture.context, keyboardObservation: fixture.observe,
            controlFocus: $focus
        )
        .background(CalendarKeyboardOwnerObserver(
            relay: fixture.relay, panel: nil, session: 0,
            onOwnerChange: { fixture.owner = $0 }
        ))
    }
}

/// Real controls in an owned ordinary window, with isolated storage and Carbon.
@MainActor
private final class SettingsWindowTestFixture {
    let saved = LockIsolated(PreferencesFeature.State())
    let login = SettingsLoginTestGate()
    let hotkey = HotkeyFixture()
    let notifications = NotificationCenter()
    let recordingChanges = LockIsolated<[Bool]>([])
    let preferencesClient: PreferencesClient
    let launchAtLoginClient: LaunchAtLoginClient
    let store: StoreOf<PreferencesFeature>
    let model: HotkeyPreferencesModel
    let controller: SettingsWindowController
    private var recordingObserver: NSObjectProtocol?
    private var accessibilityPrepared = false

    init() {
        let saved = saved
        let login = login
        preferencesClient = .init(
            loadStartOfWeekday: { saved.value.startOfWeekday },
            saveStartOfWeekday: { value in saved.withValue { $0.startOfWeekday = value } },
            loadWorkdays: { saved.value.workdays },
            saveWorkdays: { value in saved.withValue { $0.workdays = value } },
            loadDisplayOptions: { saved.value.displayOptions },
            saveDisplayOptions: { value in saved.withValue { $0.displayOptions = value } },
            loadShowAISearch: { saved.value.showAISearch },
            saveShowAISearch: { value in saved.withValue { $0.showAISearch = value } },
            loadAIProvider: { saved.value.aiProvider },
            saveAIProvider: { value in saved.withValue { $0.aiProvider = value } }
        )
        launchAtLoginClient = .init(
            status: { saved.value.launchAtLoginStatus },
            setEnabled: { value in try await login.wait(enabled: value) }
        )
        let preferencesClient = preferencesClient
        let launchAtLoginClient = launchAtLoginClient
        store = Store(initialState: PreferencesFeature.State()) { PreferencesFeature() } withDependencies: {
            $0.preferencesClient = preferencesClient
            $0.launchAtLoginClient = launchAtLoginClient
        }
        model = HotkeyPreferencesModel(hotkey: hotkey.hotkey, defaults: hotkey.defaults, handler: {})
        controller = SettingsWindowController(
            store: store, hotkeyPreferences: model, notificationCenter: notifications
        )
        let changes = recordingChanges
        recordingObserver = NotificationCenter.default.addObserver(
            forName: .hotkeyRecordingDidChange, object: nil, queue: nil
        ) { notification in
            if let value = notification.object as? Bool {
                changes.withValue { $0.append(value) }
            }
        }
    }

    func open(visibleFrame: NSRect? = nil, avoiding: NSRect? = nil, calendar: CalendarPanel? = nil) async throws {
        let bounds = NSScreen.screens.reduce(NSRect.zero) { $0.union($1.frame) }
        let presentationBounds = visibleFrame ?? NSRect(
            x: bounds.minX - 800, y: bounds.minY - 700, width: 760, height: 760
        )
        controller.show(visibleFrame: presentationBounds, avoiding: avoiding, calendar: calendar)
        if !accessibilityPrepared {
            let owner = try #require(controller.window)
            let hosting = try #require(owner.contentView as? NSHostingView<SettingsRootView>)
            for afterLayout in [false, true] {
                if afterLayout { hosting.layoutSubtreeIfNeeded(); hosting.displayIfNeeded() }
                let minimumConstraints = hosting.constraints.filter {
                    $0.identifier?.hasPrefix("Glimpse.Settings.minimum") == true
                }.prefix(2).map { constraint -> [String: Any] in
                    [
                        "identifier": String((constraint.identifier ?? "").prefix(200)),
                        "attribute": constraint.firstAttribute.rawValue,
                        "relation": constraint.relation.rawValue, "constant": constraint.constant,
                        "active": constraint.isActive, "firstItemIsObservedRoot": constraint.firstItem as? NSView === hosting,
                        "observedRootIsWindowContent": owner.contentView === hosting
                    ]
                }
                let provider = nodes().first { $0.role == .popUpButton && $0.label == "AI provider" }
                let rowLabel = nodes().first {
                    $0.role == .staticText && ($0.label == "Provider" || ($0.value as? String) == "Provider")
                }
                let viewport = accessibilityScrollView(in: hosting)
                let proxyFrame = (owner.firstResponder as? NSView).flatMap { view -> NSRect? in
                    guard view.window === owner else { return nil }
                    return owner.convertToScreen(view.convert(view.bounds, to: nil))
                }
                let constraints = try JSONSerialization.data(withJSONObject: minimumConstraints, options: [.sortedKeys])
                print("GLIMPSE_SETTINGS_HOST stage=ordinary-after-public-show-\(afterLayout ? "after" : "before")-fixture-layout contentMinSize=\(owner.contentMinSize) constraints=\(String(decoding: constraints, as: UTF8.self)) rootClass=\(String(reflecting: type(of: hosting))) rootBounds=\(hosting.bounds) rootWindowOwned=\(hosting.window === owner) windowFrame=\(owner.frame) keyWindowOwned=\(NSApp.keyWindow === owner) responderClass=\(owner.firstResponder.map { NSStringFromClass(type(of: $0)) } ?? "nil") responderViewOwned=\((owner.firstResponder as? NSView)?.window === owner) proxyFrame=\(String(describing: proxyFrame)) providerAXPresent=\(provider != nil) providerAXFrame=\(String(describing: provider?.frame)) rowLabelAXPresent=\(rowLabel != nil) rowLabelAXFrame=\(String(describing: rowLabel?.frame)) documentBounds=\(String(describing: viewport?.documentView?.bounds)) clipBounds=\(String(describing: viewport?.contentView.bounds))")
            }
            // Attach the AX-enabled root before key presentation, matching production.
            owner.orderOut(nil)
            let replacement = NSHostingView(rootView: AnyView(
                hosting.rootView.environment(\.accessibilityEnabled, true)
            ))
            replacement.sizingOptions = []
            owner.contentView = replacement
            for afterLayout in [false, true] {
                if afterLayout { replacement.layoutSubtreeIfNeeded(); replacement.displayIfNeeded() }
                let minimumConstraints = replacement.constraints.filter {
                    $0.identifier?.hasPrefix("Glimpse.Settings.minimum") == true
                }.prefix(2).map { constraint -> [String: Any] in
                    [
                        "identifier": String((constraint.identifier ?? "").prefix(200)),
                        "attribute": constraint.firstAttribute.rawValue,
                        "relation": constraint.relation.rawValue, "constant": constraint.constant,
                        "active": constraint.isActive, "firstItemIsObservedRoot": constraint.firstItem as? NSView === replacement,
                        "observedRootIsWindowContent": owner.contentView === replacement
                    ]
                }
                let viewport = accessibilityScrollView(in: replacement)
                let constraints = try JSONSerialization.data(withJSONObject: minimumConstraints, options: [.sortedKeys])
                print("GLIMPSE_SETTINGS_HOST stage=replacement-\(afterLayout ? "after" : "before")-fixture-layout-before-second-show contentMinSize=\(owner.contentMinSize) constraints=\(String(decoding: constraints, as: UTF8.self)) rootClass=\(String(reflecting: type(of: replacement))) rootBounds=\(replacement.bounds) rootWindowOwned=\(replacement.window === owner) windowFrame=\(owner.frame) keyWindowOwned=\(NSApp.keyWindow === owner) responderClass=\(owner.firstResponder.map { NSStringFromClass(type(of: $0)) } ?? "nil") documentBounds=\(String(describing: viewport?.documentView?.bounds)) clipBounds=\(String(describing: viewport?.contentView.bounds))")
            }
            accessibilityPrepared = true
            controller.show(visibleFrame: presentationBounds, avoiding: avoiding, calendar: calendar)
        }
        await settle()
        let owner = try #require(controller.window)
        try #require(owner.isVisible && owner.isKeyWindow && NSApp.keyWindow === owner)
        try #require(!(owner is NSPanel))
        try loadAccessibilityWindowTree()
        await settle()
        let root = try #require(owner.contentView)
        let minimumConstraints = root.constraints.filter {
            $0.identifier?.hasPrefix("Glimpse.Settings.minimum") == true
        }.prefix(2).map { constraint -> [String: Any] in
            [
                "identifier": String((constraint.identifier ?? "").prefix(200)),
                "attribute": constraint.firstAttribute.rawValue,
                "relation": constraint.relation.rawValue, "constant": constraint.constant,
                "active": constraint.isActive, "firstItemIsObservedRoot": constraint.firstItem as? NSView === root,
                "observedRootIsWindowContent": owner.contentView === root
            ]
        }
        let viewport = accessibilityScrollView(in: root)
        let provider = nodes().first { $0.role == .popUpButton && $0.label == "AI provider" }
        let rowLabel = nodes().first {
            $0.role == .staticText && ($0.label == "Provider" || ($0.value as? String) == "Provider")
        }
        let constraints = try JSONSerialization.data(withJSONObject: minimumConstraints, options: [.sortedKeys])
        print("GLIMPSE_SETTINGS_HOST stage=current-root-after-public-show-and-fixture-settle contentMinSize=\(owner.contentMinSize) constraints=\(String(decoding: constraints, as: UTF8.self)) rootClass=\(String(reflecting: type(of: root))) rootBounds=\(root.bounds) rootWindowOwned=\(root.window === owner) windowFrame=\(owner.frame) requestedBounds=\(presentationBounds) keyWindowOwned=\(NSApp.keyWindow === owner) responderClass=\(owner.firstResponder.map { NSStringFromClass(type(of: $0)) } ?? "nil") providerAXPresent=\(provider != nil) providerAXFrame=\(String(describing: provider?.frame)) rowLabelAXPresent=\(rowLabel != nil) rowLabelAXFrame=\(String(describing: rowLabel?.frame)) documentBounds=\(String(describing: viewport?.documentView?.bounds)) clipBounds=\(String(describing: viewport?.contentView.bounds))")
    }

    func loadAccessibilityWindowTree() throws {
        // Match ordinary viewport hosts: a client read materializes SwiftUI's
        // virtual controls throughout the non-lazy document.
        let application = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        var windows: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            application, kAXWindowsAttribute as CFString, &windows
        )
        try #require(result == .success)
    }

    func startRecording() async throws {
        try #require(!model.isRecording)
        try await reveal(.general)
        let matches = nodes().filter { $0.role == .button && $0.label == "Set and enable shortcut" }
        try #require(matches.count == 1)
        let recorder = try #require(matches.first)
        let owner = recorder.object.accessibilityWindow?() as? NSWindow
        try #require(owner === controller.window)
        try #require(recorder.press())
        await settle()
        try #require(model.isRecording)
    }

    func reveal(_ section: SettingsSection) async throws {
        let tree = nodes()
        let node = try #require(tree.first {
            $0.role?.rawValue == "AXHeading" &&
                ($0.label == section.heading || ($0.value as? String) == section.heading)
        })
        let targets: [(label: String, role: NSAccessibility.Role, rowLabel: String?)]
        switch section {
        case .general:
            let label = model.isRecording ? "Cancel shortcut recording" :
                (model.isEnabled ? "Change global shortcut" : "Set and enable shortcut")
            targets = [(label, .button, "Global shortcut")]
        case .menuBar:
            // This checkbox's visible Icon label is inside its native control frame.
            targets = [("Show icon in menu bar", .checkBox, nil)]
        case .calendar:
            targets = [("Week starts on", .popUpButton, "Week starts on")]
        case .aiDateSearch:
            targets = [("Enable AI date search", .checkBox, "Enable AI date search")] +
                (store.showAISearch ? [("AI provider", .popUpButton, "Provider")] : [])
        }
        let revealFrame = try targets.reduce(node.frame) { frame, target in
            let control = try #require(tree.first {
                $0.label == target.label && $0.role == target.role
            })
            var rowFrame = control.frame
            if let label = target.rowLabel {
                let rowLabel = try #require(tree.first {
                    $0.role == .staticText && ($0.label == label || ($0.value as? String) == label)
                })
                rowFrame = rowFrame.union(rowLabel.frame)
            }
            return frame.union(rowFrame)
        }
        let owner = try #require(controller.window)
        let contentView = try #require(owner.contentView)
        let scroll = try #require(accessibilityScrollView(in: contentView))
        let document = try #require(scroll.documentView)
        document.scrollToVisible(document.convert(
            owner.convertFromScreen(revealFrame.insetBy(dx: -8, dy: -8)), from: nil
        ))
        await settle()
        let current = try #require(nodes().first {
            $0.role?.rawValue == "AXHeading" &&
                ($0.label == section.heading || ($0.value as? String) == section.heading)
        })
        try expectVisible(current)
        for target in targets {
            let control = try #require(nodes().first {
                $0.label == target.label && $0.role == target.role
            })
            try expectVisible(control, rowLabel: target.rowLabel)
        }
    }

    func expectVisible(_ node: AccessibilityTestNode, rowLabel: String? = nil) throws {
        let owner = try #require(controller.window)
        let contentView = try #require(owner.contentView)
        let scroll = try #require(accessibilityScrollView(in: contentView))
        var targetFrame = node.frame
        if let rowLabel {
            let label = try #require(nodes().first {
                $0.role == .staticText && ($0.label == rowLabel || ($0.value as? String) == rowLabel)
            })
            targetFrame = targetFrame.union(label.frame)
        }
        #expect(scroll.contentView.bounds.contains(
            scroll.contentView.convert(
                owner.convertFromScreen(targetFrame.insetBy(dx: -8, dy: -8)), from: nil
            )
        ))
    }

    func nodes() -> [AccessibilityTestNode] {
        guard let hosting = controller.window?.contentView else { return [] }
        var queue: [Any] = [hosting]
        var visited: Set<ObjectIdentifier> = []
        var nodes: [AccessibilityTestNode] = []
        var index = 0
        while index < queue.count {
            let object = queue[index] as AnyObject
            index += 1
            guard object.responds?(to: #selector(NSAccessibilityProtocol.accessibilityRole)) == true,
                  visited.insert(ObjectIdentifier(object)).inserted else { continue }
            let node = AccessibilityTestNode(object: object)
            nodes.append(node)
            queue.append(contentsOf: node.children)
            queue.append(contentsOf: node.contents)
            queue.append(contentsOf: node.visibleChildren)
        }
        return nodes
    }

    func settle() async {
        for _ in 0..<12 {
            _ = controller.window?.contentView?.fittingSize
            controller.window?.contentView?.layoutSubtreeIfNeeded()
            controller.window?.contentView?.displayIfNeeded()
            pumpRunLoop()
            await Task.yield()
        }
    }

    func saveBitmap(name: String) throws {
        let hosting = try #require(controller.window?.contentView)
        let rect = hosting.bounds
        let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: rect))
        hosting.cacheDisplay(in: rect, to: bitmap)
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        let base = ProcessInfo.processInfo.environment["GLIMPSE_KEYBOARD_ARTIFACT_DIR"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("keyboard-rendering", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try data.write(to: base.appendingPathComponent(name + ".png"), options: .withoutOverwriting)
    }

    func aiSwitchBitmap() throws -> Data {
        let owner = try #require(controller.window)
        let hosting = try #require(owner.contentView)
        let node = try #require(nodes().first {
            $0.label == "Enable AI date search" && $0.role == .checkBox
        })
        try #require(node.object.accessibilityWindow?() as? NSWindow === owner)
        let rect = hosting.convert(owner.convertFromScreen(node.frame), from: nil)
            .intersection(hosting.bounds)
        try #require(!rect.isEmpty && [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite))
        let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: rect))
        hosting.cacheDisplay(in: rect, to: bitmap)
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }

    func settleAISwitch(expected: Bool, changedFrom original: Data) async throws {
        let started = ContinuousClock.now
        let deadline = started.advanced(by: .seconds(2))
        var last = original
        var stableSince = started
        var changed = false
        while ContinuousClock.now < deadline {
            await settle()
            let rendered = try aiSwitchBitmap()
            let now = ContinuousClock.now
            if rendered != last {
                stableSince = now
                last = rendered
            }
            changed = changed || rendered != original
            // Observe actual native frames through several refresh opportunities,
            // rather than sleeping or assuming an accent color/animation duration.
            if changed && now - stableSince >= .milliseconds(50) {
                let node = try #require(nodes().first {
                    $0.label == "Enable AI date search" && $0.role == .checkBox
                })
                try #require((node.value as? NSNumber)?.boolValue == expected)
                print("GLIMPSE_SETTINGS_SWITCH_RENDER expected=\(expected) changed=true stable=\(now - stableSince) elapsed=\(now - started)")
                return
            }
        }
        throw NSError(
            domain: "GlimpseTests.SettingsSwitchRendering", code: 1,
            userInfo: [NSLocalizedDescriptionKey:
                "The owned AI switch did not change and settle at \(expected) before its bounded deadline."]
        )
    }

    private func pumpRunLoop() {
        CFRunLoopRunInMode(.defaultMode, 0.01, true)
    }

    func close() {
        controller.cancelRecording()
        controller.window?.contentView = nil
        controller.window?.close()
        login.finish()
        if let recordingObserver { NotificationCenter.default.removeObserver(recordingObserver) }
        hotkey.cleanupDefaults()
    }
}

private final class SettingsLoginTestGate: Sendable {
    let requests = LockIsolated<[Bool]>([])
    private let continuations = LockIsolated<[CheckedContinuation<Void, Error>]>([])

    func wait(enabled: Bool) async throws {
        try await withCheckedThrowingContinuation { continuation in
            continuations.withValue { $0.append(continuation) }
            requests.withValue { $0.append(enabled) }
        }
    }

    func finish(error: Error? = nil) {
        let pending = continuations.withValue { values in
            let pending = values
            values.removeAll()
            return pending
        }
        for continuation in pending {
            if let error { continuation.resume(throwing: error) }
            else { continuation.resume() }
        }
    }
}

/// Posts Escape only after the exact owned popup begins native menu tracking.
@MainActor
private final class SettingsPopupEscape: NSObject {
    private weak var owner: NSWindow?
    private let expectedTitles: [String]
    private var menu: NSMenu?
    private var timer: Timer?
    private let deadline = ContinuousClock.now.advanced(by: .seconds(1))
    private(set) var postedOwnedEscape = false
    private(set) var trackingEnded = false
    private(set) var timedOut = false

    init(owner: NSWindow, expectedTitles: [String]) {
        self.owner = owner
        self.expectedTitles = expectedTitles
        super.init()
        NotificationCenter.default.addObserver(
            self, selector: #selector(began(_:)), name: NSMenu.didBeginTrackingNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(ended(_:)), name: NSMenu.didEndTrackingNotification, object: nil
        )
        let timer = Timer(timeInterval: 0.01, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .eventTracking)
    }

    @objc private func began(_ notification: Notification) {
        guard menu == nil, let root = notification.object as? NSMenu,
              root.items.filter({ !$0.isSeparatorItem }).map(\.title) == expectedTitles else { return }
        menu = root
    }

    @objc private func ended(_ notification: Notification) {
        guard let root = notification.object as? NSMenu, root === menu else { return }
        trackingEnded = true
        close()
    }

    private func tick() {
        if ContinuousClock.now >= deadline {
            timedOut = true
            menu?.cancelTrackingWithoutAnimation()
            close()
            return
        }
        guard menu != nil, !postedOwnedEscape, let owner,
              owner.isVisible, owner.isKeyWindow, NSApp.keyWindow === owner,
              let event = NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: owner.windowNumber,
                context: nil, characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}",
                isARepeat: false, keyCode: 53
              ), event.window === owner else { return }
        postedOwnedEscape = true
        NSApp.postEvent(event, atStart: true)
    }

    func close() {
        timer?.invalidate()
        timer = nil
        NotificationCenter.default.removeObserver(self)
        if let menu, !trackingEnded { menu.cancelTrackingWithoutAnimation() }
    }
}

/// Real controls in an owned ordinary window, with isolated storage and Carbon.
@MainActor
private final class ShortcutRecorderWindowFixture {
    let preferences = PreferencesAccessibilityFixture(state: .init())
    let window: NSWindow
    let hosting: NSHostingView<AnyView>

    init() {
        let owner = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 268, height: 700),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window = owner
        window.isReleasedWhenClosed = false
        hosting = NSHostingView(rootView: AnyView(
            PreferencesView(
                store: preferences.store, hotkeyPreferences: preferences.hotkeyModel,
                notificationCenter: preferences.notifications,
                recordingWindow: { [weak owner] in owner }
            ).environment(\.accessibilityEnabled, true)
        ))
        window.contentView = hosting
        let screens = NSScreen.screens.reduce(NSRect.zero) { $0.union($1.frame) }
        window.setFrameOrigin(NSPoint(
            x: screens.minX - window.frame.width - 100,
            y: screens.minY - window.frame.height - 100
        ))
    }

    func open() async throws {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        await settle()
        try #require(NSApp.keyWindow === window && window.isKeyWindow && !(window is NSPanel))
    }

    func recorder() throws -> AccessibilityTestNode {
        var queue: [Any] = [hosting]
        var visited: Set<ObjectIdentifier> = []
        var matches: [AccessibilityTestNode] = []
        var index = 0
        while index < queue.count {
            let object = queue[index] as AnyObject
            index += 1
            guard object.responds?(to: #selector(NSAccessibilityProtocol.accessibilityRole)) == true,
                  visited.insert(ObjectIdentifier(object)).inserted else { continue }
            let node = AccessibilityTestNode(object: object)
            if node.label == "Set and enable shortcut", node.role == .button {
                matches.append(node)
            }
            queue.append(contentsOf: node.children)
            queue.append(contentsOf: node.contents)
            queue.append(contentsOf: node.visibleChildren)
        }
        try #require(matches.count == 1)
        return try #require(matches.first)
    }

    func settle() async {
        for _ in 0..<8 {
            _ = hosting.fittingSize
            hosting.layoutSubtreeIfNeeded()
            hosting.displayIfNeeded()
            pumpRunLoop()
            await Task.yield()
        }
    }

    private func pumpRunLoop() {
        CFRunLoopRunInMode(.defaultMode, 0.01, true)
    }

    func close() {
        preferences.hotkeyModel.cancelRecording()
        window.contentView = nil
        window.close()
        preferences.close()
    }
}

@MainActor
final class CalendarKeyboardRootFixture {
    static let gridVisualAppearances: [(NSAppearance.Name, String)] = [
        (.aqua, "light"),
        (.darkAqua, "dark")
    ]
    var gridVisualAcceptanceEnabled: Bool {
        ProcessInfo.processInfo.environment["GLIMPSE_GRID_VISUAL_ACCEPTANCE"] == "1"
    }
    let today: Date
    let store: StoreOf<CalendarFeature>
    let panel: CalendarPanel
    let hosting: NSHostingView<AnyView>
    let preferences: StoreOf<PreferencesFeature>
    let hotkeyModel: HotkeyPreferencesModel
    let aiModel: AIDateQueryModel
    let aiSettings: LockIsolated<AIDateIntegrationSettings>
    private let aiTaskReceipts: AIDateIntegrationTaskReceipts
    var aiTasks: [AIDateIntegrationTrackedTask] { aiTaskReceipts.tasks }
    let aiSettingSaves = LockIsolated<[AIDateIntegrationSettings]>([])
    let actions = LockIsolated<[String]>([])
    let calendarSettings = LockIsolated(
        (startOfWeekday: 1, workdays: Set([2, 3, 4, 5, 6]))
    )
    let actionCurrentEvents = LockIsolated<[Bool]>([])
    let reopenActions = LockIsolated(0)
    private let dispatch = CalendarKeyboardDispatchReceipt()
    private let focus = CalendarKeyboardFocusReceipt()
    private let callbacks = CalendarKeyboardCallbackReceipt()
    private let effects = CalendarKeyboardEffectReceipt()
    private let hotkeyFixture = HotkeyFixture()
    private let lifecycle = CalendarKeyboardLifecycleReceipt()
    private var completionObserver: NSObjectProtocol?
    private let maximumHeight: CGFloat
    private let holdCrossScreenShows: Bool
    private var sequence = 0
    var lastPublishedOwner: CalendarKeyboardOwner? { focus.owner }
    var callbackRows: [[String: Any]] { callbacks.rows }
    var ownedPhaseReceipts: [CalendarKeyboardSentPhase] { dispatch.phases }
    var submissions: [String] { effects.submissions }
    var submissionCurrentEvents: [Bool] { effects.currentEvents }
    var editorPresentationRequests: Int { effects.presentationRequests }
    var presentationSnapshot: CalendarPresentationSnapshot? { effects.presentationSnapshot }
    var previousAppRestorations: Int { effects.previousAppRestorations }
    var terminationReceipts: Int { effects.terminations }
    var heldEditorPresentations: [@MainActor () -> Void] { effects.heldEditorPresentations }
    var heldCrossScreenShows: [@MainActor () -> Void] { effects.heldCrossScreenShows }
    var completions: Int { lifecycle.completions }
    var gridRenderingFocused: Bool { focus.gridRenderingFocused }
    var matchesCurrentDispatchedEvent: Bool {
        dispatch.expected != nil && NSApp.currentEvent === dispatch.expected
    }

    lazy var showOwner: CalendarStatusItem = {
        let origin = panel.frame.origin
        let anchor = CalendarStatusItem.PanelAnchor(
            statusItemFrame: NSRect(x: origin.x + 138, y: origin.y + maximumHeight + 16, width: 40, height: 24),
            visibleFrame: NSRect(x: origin.x - 100, y: origin.y, width: 1000, height: maximumHeight + 64)
        )
        let panel = panel
        let effects = effects
        let holdCrossScreen = holdCrossScreenShows
        return CalendarStatusItem(
            anchorProvider: { anchor }, panelFactory: { _, _ in panel },
            toggleVisibility: { $0.isVisible }, sameScreen: { _ in !holdCrossScreen },
            crossScreenScheduler: { effects.heldCrossScreenShows.append($0) }
        )
    }()

    var monthNumber: Int { store.calendar.component(.month, from: store.displayedMonth) }
    var yearNumber: Int { store.calendar.component(.year, from: store.displayedMonth) }

    init(
        showAI: Bool = false, maximumHeight: CGFloat = 550, initialToday: Date? = nil,
        aiClient: AIDateQueryClient = AIDateIntegrationClient.immediateNoDate,
        allowAISettings: Bool = false, holdEditorPresentation: Bool = false,
        holdCrossScreenShows: Bool = false
    ) throws {
        self.maximumHeight = maximumHeight
        self.holdCrossScreenShows = holdCrossScreenShows
        if let initialToday {
            today = initialToday
        } else {
            today = try #require(Calendar.current.date(from: DateComponents(
                year: 2030, month: 11, day: 15, hour: 12
            )))
        }
        aiSettings = LockIsolated(AIDateIntegrationSettings(enabled: showAI, preference: .auto))
        let aiSettings = aiSettings
        let aiSettingSaves = aiSettingSaves
        let fixedToday = today
        let actions = actions
        let calendarSettings = calendarSettings
        let events = actionCurrentEvents
        let dispatch = dispatch
        let reopenActions = reopenActions
        store = Store(initialState: CalendarFeature.State(displayedMonth: today)) {
            Reduce<CalendarFeature.State, CalendarFeature.Action> { state, action in
                let name: String?
                switch action {
                case .prepareForReopen:
                    reopenActions.withValue { $0 += 1 }
                    name = nil
                case .goToPreviousMonth: name = "previousMonth"
                case .goToNextMonth: name = "nextMonth"
                case .goToPreviousYear: name = "previousYear"
                case .goToNextYear: name = "nextYear"
                case .goToToday: name = "today"
                case .aiDateResult(.some(_)): name = "aiDate"
                case let .dateTapped(date):
                    name = "date:\(state.calendar.component(.day, from: date))"
                default: name = nil
                }
                if let name {
                    actions.withValue { $0.append(name) }
                    MainActor.assumeIsolated {
                        let matches = NSApp.currentEvent === dispatch.expected
                        events.withValue { $0.append(matches) }
                    }
                }
                return .none
            }
            CalendarFeature()
        } withDependencies: {
            $0.date = .constant(fixedToday)
            $0.calendarClient = .liveValue
            $0.calendarClient.menuBarDateString = { _, _ in
                Issue.record("Keyboard fixture must not use a status item")
                return ""
            }
            $0.preferencesClient = .testValue
            $0.preferencesClient.loadStartOfWeekday = { calendarSettings.value.startOfWeekday }
            $0.preferencesClient.loadWorkdays = { calendarSettings.value.workdays }
            $0.preferencesClient.loadShowAISearch = { aiSettings.value.enabled }
            $0.eventKitClient = EventKitClient(
                requestAccess: {
                    Issue.record("Keyboard fixture must not request calendar access")
                    return false
                },
                fetchEvents: { _ in
                    Issue.record("Keyboard fixture must not read calendars")
                    return []
                },
                authorizationStatus: { .notDetermined }
            )
        }
        preferences = Store(initialState: PreferencesFeature.State()) {
            Reduce<PreferencesFeature.State, PreferencesFeature.Action> { _, action in
                switch action {
                case .onAppear, .refreshLaunchAtLogin:
                    break // Existing view lifecycle reads only injected clients.
                case .setShowAISearch, .setAIProvider, .delegate(.preferencesChanged):
                    if !allowAISettings { Issue.record("Keyboard fixture must not change AI preferences") }
                default:
                    Issue.record("Keyboard fixture must not change preferences")
                }
                return .none
            }
            PreferencesFeature()
        } withDependencies: {
            $0.preferencesClient = .testValue
            $0.preferencesClient.loadStartOfWeekday = { calendarSettings.value.startOfWeekday }
            $0.preferencesClient.loadWorkdays = { calendarSettings.value.workdays }
            $0.preferencesClient.loadDisplayOptions = { .default }
            $0.preferencesClient.loadShowAISearch = { aiSettings.value.enabled }
            $0.preferencesClient.loadAIProvider = { aiSettings.value.preference }
            $0.preferencesClient.saveShowAISearch = { enabled in
                aiSettings.withValue { $0.enabled = enabled }
                aiSettingSaves.withValue { $0.append(aiSettings.value) }
            }
            $0.preferencesClient.saveAIProvider = { preference in
                aiSettings.withValue { $0.preference = preference }
                aiSettingSaves.withValue { $0.append(aiSettings.value) }
            }
            $0.launchAtLoginClient = .testValue
            $0.launchAtLoginClient.status = { .notRegistered }
        }
        let store = store
        aiModel = AIDateQueryModel(
            client: aiClient, enabled: showAI, preference: .auto,
            onDate: { store.send(.aiDateResult($0)) }
        )
        let effects = effects
        panel = CalendarPanel(
            contentRect: NSRect(x: -1000, y: -1000, width: 316, height: maximumHeight),
            caretOffset: 150, calendarStore: store, content: { _ in AnyView(EmptyView()) },
            capturePreviousApp: { .current },
            restorePreviousApp: { _ in effects.previousAppRestorations += 1 }
        )
        panel.isReleasedWhenClosed = false
        let callbacks = callbacks
        let panel = panel
        let focus = focus
        let rendering = focus.gridRenderingSnapshot
        hotkeyModel = HotkeyPreferencesModel(
            hotkey: hotkeyFixture.hotkey, defaults: hotkeyFixture.defaults
        ) { Issue.record("Keyboard fixture must not operate a global hotkey") }
        // Replace only fixture presentation to inject the owned calendar root dependencies.
        // This keyboard test does not accept the private KVO resize path.
        let aiModel = aiModel
        let taskReceipts = AIDateIntegrationTaskReceipts()
        aiTaskReceipts = taskReceipts
        hosting = NSHostingView(rootView: AnyView(
            CalendarPopoverView(
                store: store, panel: panel, layout: panel.layoutState,
                keyboardObservation: { invocation in
                    let row: [String: Any] = [
                        "owner": invocation.owner.rawValue,
                        "key": String(describing: invocation.key),
                        "phase": String(describing: invocation.phase),
                        "route": String(describing: invocation.route),
                        "contextAllowsRouting": invocation.context.allowsRouting,
                        "eventWindowOwned": NSApp.currentEvent?.window === panel,
                        "currentEventMatchesExpected": NSApp.currentEvent === dispatch.expected,
                        "firstResponderIsWindow": panel.firstResponder === panel,
                        "focusRenderingSnapshot": invocation.focusRenderingSnapshot.map { $0 ? "true" : "false" } ?? "not-used"
                    ]
                    callbacks.rows.append(row)
                    let data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
                    if let data { print("GLIMPSE_KEYBOARD_CALLBACK \(String(decoding: data, as: UTF8.self))") }
                },
                editorPresentation: { requestFocus in
                    effects.presentationRequests += 1
                    print("GLIMPSE_KEYBOARD_EDITOR_PRESENTATION count=\(effects.presentationRequests)")
                    if holdEditorPresentation { effects.heldEditorPresentations.append(requestFocus) }
                    else { requestFocus() }
                },
                aiQueryModel: aiModel,
                loadAISettings: {
                    let settings = aiSettings.value
                    return (settings.enabled, settings.preference)
                },
                querySubmissionObservation: { query, task in
                    taskReceipts.tasks.append(AIDateIntegrationTrackedTask(task))
                    let matched = NSApp.currentEvent === dispatch.expected
                    effects.submissions.append(query)
                    effects.currentEvents.append(matched)
                    print("GLIMPSE_KEYBOARD_SUBMIT count=\(effects.submissions.count) currentEvent=\(matched) editor=\(panel.firstResponder is NSTextView)")
                },
                presentationObservation: {
                    effects.presentationSnapshot = $0
                },
                quitApplication: { effects.terminations += 1 }
            )
            .environment(\.accessibilityEnabled, true)
            .background(CalendarKeyboardTestOwnerObserver(receipt: focus))
            .onPreferenceChange(CalendarGridFocusPreference.self) {
                rendering.setValue($0)
            }
        ))
        panel.contentView = hosting
        let bounds = NSScreen.screens.reduce(NSRect.zero) { $0.union($1.frame) }
        panel.setFrameOrigin(NSPoint(x: bounds.minX - 1000, y: bounds.minY - 1000))
        panel.isPinned = true
        panel.layoutState.updatePlacement(maximumHeight: maximumHeight, caretXOffset: 150)
        let lifecycle = lifecycle
        completionObserver = NotificationCenter.default.addObserver(
            forName: .calendarPanelDidCompleteReopen, object: panel, queue: nil
        ) { _ in MainActor.assumeIsolated { lifecycle.completions += 1 } }
    }

    func awaitAcceptedSubmissions() async throws {
        let cleanup = Task { @MainActor in
            var failedReceipts: [Int] = []
            for (index, receipt) in self.aiTasks.enumerated() {
                do { try await receipt.finish() }
                catch { failedReceipts.append(index) }
            }
            // Every actual receipt is visited before reporting unresolved work.
            if !failedReceipts.isEmpty {
                throw AIDateIntegrationFixtureFailure.receiptFailures(failedReceipts)
            }
        }
        try await cleanup.value
    }

    func trackEligibilityProbe(_ task: Task<Void, Never>) {
        aiTaskReceipts.tasks.append(AIDateIntegrationTrackedTask(task))
    }

    func date(day: Int) -> Date? {
        Calendar.current.date(from: DateComponents(year: 2030, month: 11, day: day))
    }

    func open() async throws {
        panel.prepareForReopen()
        panel.makeKeyAndOrderFront(nil)
        let completed = panel.completeReopenPresentation()
        let responderIsWindow = panel.firstResponder === panel
        print("GLIMPSE_KEYBOARD_REOPEN \(completed) responderIsWindow=\(responderIsWindow)")
        #expect(completed)
        #expect(responderIsWindow)
        await settleRendering()
        try #require(panel.isVisible && panel.isKeyWindow && NSApp.keyWindow === panel)
        clearActionReceipts()
    }

    func openThroughShowOwner() async throws {
        let before = completions
        logCalendarKeyboardTarget(panel, stage: "show-owner-before-presentation")
        try showOwner.showCalendar()
        logCalendarKeyboardTarget(panel, stage: "show-owner-after-presentation")
        #expect(completions == before + 1)
        let responderIsWindow = panel.firstResponder === panel
        #expect(responderIsWindow)
        await settleRendering()
        logCalendarKeyboardTarget(panel, stage: "show-owner-after-settle")
        try #require(panel.isVisible && panel.isKeyWindow && NSApp.keyWindow === panel)
        clearActionReceipts()
    }

    func clearActionReceipts() {
        actions.setValue([])
        actionCurrentEvents.setValue([])
        callbacks.rows = []
    }

    func expectInvocation(
        after count: Int, owner: CalendarKeyboardOwner, key: CalendarKeyboardKey,
        route: String, phase: String = "down"
    ) {
        let rows = Array(callbacks.rows.dropFirst(count))
        #expect(rows.count == 1)
        #expect(rows.allSatisfy {
            $0["owner"] as? String == owner.rawValue
                && $0["key"] as? String == String(describing: key)
                && $0["phase"] as? String == phase
                && $0["route"] as? String == route
                && $0["contextAllowsRouting"] as? Bool == true
                && $0["eventWindowOwned"] as? Bool == true
                && $0["currentEventMatchesExpected"] as? Bool == true
                && $0["firstResponderIsWindow"] as? Bool == false
        })
    }

    func opportunityForFocusRendering() async {
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        pumpRunLoop()
        await Task.yield()
    }

    func settleRendering() async {
        for _ in 0..<8 { await opportunityForFocusRendering() }
    }

    func setRecording(_ active: Bool) {
        NotificationCenter.default.post(name: .hotkeyRecordingDidChange, object: active)
    }

    func completeHeldEditorPresentation() {
        let completion = effects.heldEditorPresentations.removeFirst()
        completion()
    }

    func completeHeldCrossScreenShow() {
        let completion = effects.heldCrossScreenShows.removeFirst()
        completion()
    }

    func ownedControl(
        _ name: String, file: StaticString = #fileID, line: UInt = #line
    ) throws -> AccessibilityTestNode {
        let matches = accessibilityNodes().filter { $0.role == .button && $0.label == name }
        logCalendarKeyboardTarget(panel, stage: "owned-control-\(name)-matches-\(matches.count)", file: file, line: line)
        try #require(matches.count == 1)
        let node = try #require(matches.first)
        try #require(node.object.accessibilityWindow?() as? NSWindow === panel)
        return node
    }

    func focusOwner(_ owner: CalendarKeyboardOwner) async throws {
        for _ in 0..<24 {
            if lastPublishedOwner == owner { return }
            try send(.tab)
            await settleRendering()
        }
        Issue.record("Native traversal did not publish \(owner)")
        throw CalendarKeyboardFixtureError.unexpectedEvent
    }

    func clickOwned(at point: NSPoint) throws {
        try #require(ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil)
        try #require(panel.isVisible)
        let location = panel.convertPoint(fromScreen: point)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try #require(NSEvent.mouseEvent(
                with: type, location: location, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: panel.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0
            ))
            try #require(event.window === panel)
            NSApp.postEvent(event, atStart: true)
            let mask: NSEvent.EventTypeMask = type == .leftMouseDown ? .leftMouseDown : .leftMouseUp
            let retrieved = try #require(NSApp.nextEvent(
                matching: mask, until: Date(), inMode: .default, dequeue: true
            ))
            guard retrieved.window === panel, retrieved.type == type,
                  retrieved.windowNumber == event.windowNumber,
                  abs(retrieved.timestamp - event.timestamp) < 0.001,
                  retrieved.locationInWindow == event.locationInWindow else {
                NSApp.postEvent(retrieved, atStart: true)
                throw CalendarKeyboardFixtureError.unexpectedEvent
            }
            dispatch.expected = retrieved
            NSApp.sendEvent(retrieved)
            dispatch.expected = nil
        }
    }

    var nativeEditorFields: [NSTextField] {
        var queue = [hosting as NSView]
        var fields: [NSTextField] = []
        while let view = queue.popLast() {
            if let field = view as? NSTextField, field.isEditable { fields.append(field) }
            queue.append(contentsOf: view.subviews)
        }
        return fields
    }

    func nativeEditorField() throws -> NSTextField {
        #expect(nativeEditorFields.count == 1)
        return try #require(nativeEditorFields.first)
    }

    /// Read only the self-process window positively matched to this owned panel.
    /// No system-wide AX object, trust request, action, permission or fallback.
    func expectOwnedPublicAXGridLabel(_ expectedGridLabel: String) throws {
        let inTestHost = ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil
        try #require(inTestHost)
        let ownPID = ProcessInfo.processInfo.processIdentifier
        func attribute(_ element: AXUIElement, _ name: String) -> (AXError, CFTypeRef?) {
            var value: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(element, name as CFString, &value)
            return (error, value)
        }
        func isOwnProcess(_ element: AXUIElement) -> Bool {
            var pid: pid_t = 0
            return AXUIElementGetPid(element, &pid) == .success && pid == ownPID
        }
        func element(_ value: CFTypeRef?) -> AXUIElement? {
            guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
            return (value as! AXUIElement)
        }
        func frame(_ element: AXUIElement) -> CGRect? {
            let (positionError, positionValue) = attribute(element, kAXPositionAttribute)
            let (sizeError, sizeValue) = attribute(element, kAXSizeAttribute)
            guard positionError == .success, sizeError == .success,
                  let positionValue, let sizeValue,
                  CFGetTypeID(positionValue) == AXValueGetTypeID(),
                  CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
            let positionAX = positionValue as! AXValue
            let sizeAX = sizeValue as! AXValue
            var position = CGPoint.zero
            var size = CGSize.zero
            guard AXValueGetType(positionAX) == .cgPoint,
                  AXValueGetType(sizeAX) == .cgSize,
                  AXValueGetValue(positionAX, .cgPoint, &position),
                  AXValueGetValue(sizeAX, .cgSize, &size),
                  position.x.isFinite, position.y.isFinite,
                  size.width.isFinite, size.height.isFinite else { return nil }
            return CGRect(origin: position, size: size)
        }
        let application = AXUIElementCreateApplication(ownPID)
        let appPIDMatches = isOwnProcess(application)
        try #require(appPIDMatches)
        let (windowsError, windowsValue) = attribute(application, kAXWindowsAttribute)
        let windowsQuerySucceeded = windowsError == .success
        try #require(windowsQuerySucceeded)
        let windows = windowsValue as? [AXUIElement]
        let windowListIsBounded = windows != nil && (windows?.count ?? 0) <= 16
        try #require(windowListIsBounded)
        let primaryScreen = NSScreen.screens.first
        let screenExists = primaryScreen != nil
        try #require(screenExists)
        // AX uses global top-left coordinates; AppKit's main screen has bottom-left origin.
        let expectedFrame = CGRect(
            x: panel.frame.minX, y: primaryScreen!.frame.maxY - panel.frame.maxY,
            width: panel.frame.width, height: panel.frame.height
        )
        let expectedFrameIsFinite = expectedFrame.origin.x.isFinite && expectedFrame.origin.y.isFinite &&
            expectedFrame.width.isFinite && expectedFrame.height.isFinite
        try #require(expectedFrameIsFinite)
        var matchingWindows: [AXUIElement] = []
        for window in windows! {
            let windowPIDMatches = isOwnProcess(window)
            try #require(windowPIDMatches)
            if frame(window) == expectedFrame { matchingWindows.append(window) }
        }
        let exactlyOneOwnedFrame = matchingWindows.count == 1
        try #require(exactlyOneOwnedFrame)
        let ownedWindow = matchingWindows[0]
        var queue = [ownedWindow]
        var index = 0
        var matches = 0
        while index < queue.count {
            let node = queue[index]
            index += 1
            let nodePIDMatches = isOwnProcess(node)
            try #require(nodePIDMatches)
            if !CFEqual(node, ownedWindow) {
                let window = element(attribute(node, kAXWindowAttribute).1)
                let nodeWindowMatches = window.map { CFEqual($0, ownedWindow) } ?? false
                try #require(nodeWindowMatches)
                let parent = element(attribute(node, kAXParentAttribute).1)
                let parentIsOwned = parent.map { parent in
                    guard isOwnProcess(parent) else { return false }
                    if CFEqual(parent, ownedWindow) { return true }
                    return element(attribute(parent, kAXWindowAttribute).1)
                        .map { CFEqual($0, ownedWindow) } ?? false
                } ?? false
                try #require(parentIsOwned)
            }
            let (descriptionError, descriptionValue) = attribute(node, kAXDescriptionAttribute)
            let (titleError, titleValue) = attribute(node, kAXTitleAttribute)
            let description = descriptionValue as? String
            let title = titleValue as? String
            if description == expectedGridLabel || title == expectedGridLabel {
                let role = attribute(node, kAXRoleAttribute).1 as? String
                let finiteFrame = frame(node) != nil
                let successfulLabelReadMatches =
                    (descriptionError == .success && description == expectedGridLabel) ||
                    (titleError == .success && title == expectedGridLabel)
                try #require(successfulLabelReadMatches)
                let roleIsGroup = role == kAXGroupRole
                try #require(roleIsGroup)
                try #require(finiteFrame)
                matches += 1
            }
            for name in [kAXChildrenAttribute, kAXContentsAttribute] {
                var count: CFIndex = 0
                let countError = AXUIElementGetAttributeValueCount(node, name as CFString, &count)
                if countError == .attributeUnsupported || countError == .noValue { continue }
                let childCountIsBounded = countError == .success && count >= 0 && count <= 256
                try #require(childCountIsBounded)
                if count == 0 { continue }
                var values: CFArray?
                let childrenError = AXUIElementCopyAttributeValues(node, name as CFString, 0, count, &values)
                let childrenQuerySucceeded = childrenError == .success
                try #require(childrenQuerySucceeded)
                let children = values as? [AXUIElement]
                let childrenAreElements = children != nil
                try #require(childrenAreElements)
                for child in children! where !queue.contains(where: { CFEqual($0, child) }) {
                    let queueRemainsBounded = queue.count < 256
                    try #require(queueRemainsBounded)
                    queue.append(child)
                }
            }
        }
        let exactlyOneExpectedLabel = matches == 1
        try #require(exactlyOneExpectedLabel)
    }

    func loadOwnedAccessibilityTree() throws {
        let application = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        var windows: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &windows)
        try #require(result == .success)
    }

    func accessibilityNodes() -> [AccessibilityTestNode] {
        var queue: [Any] = [hosting]
        var visited: Set<ObjectIdentifier> = []
        var nodes: [AccessibilityTestNode] = []
        var index = 0
        while index < queue.count {
            let object = queue[index] as AnyObject
            index += 1
            guard object.responds?(to: #selector(NSAccessibilityProtocol.accessibilityRole)) == true,
                  visited.insert(ObjectIdentifier(object)).inserted else { continue }
            let node = AccessibilityTestNode(object: object)
            nodes.append(node)
            queue.append(contentsOf: node.children + node.contents + node.visibleChildren)
        }
        return nodes
    }

    func saveFocusedDateBitmap(_ screenRect: NSRect, name: String) throws {
        let rect = hosting.convert(panel.convertFromScreen(screenRect), from: nil)
        let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: rect))
        hosting.cacheDisplay(in: rect, to: bitmap)
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        let base = ProcessInfo.processInfo.environment["GLIMPSE_KEYBOARD_ARTIFACT_DIR"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("keyboard-rendering", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let output = base.appendingPathComponent(name + ".png")
        try data.write(to: output)
        print("GLIMPSE_KEYBOARD_RENDERING bitmap=\(output.path) focused=\(gridRenderingFocused)")
    }

    /// Retrieve the exact owned event from this isolated test application's queue.
    /// No global CG event, direct NSWindow dispatch or unrelated-event inspection.
    func send(
        _ key: CalendarOwnedKey, repeatPress: Bool = false,
        modifiers: NSEvent.ModifierFlags? = nil, to ownedPeer: CalendarKeyboardOwnedPeer? = nil,
        toWindow: NSWindow? = nil, file: StaticString = #fileID, line: UInt = #line
    ) throws {
        let window = toWindow ?? ownedPeer?.panel ?? panel
        try #require(ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil)
        logCalendarKeyboardTarget(window, stage: "send-\(key.rawValue)-repeat-\(repeatPress)", file: file, line: line)
        try #require(window.isVisible && window.isKeyWindow && NSApp.keyWindow === window)
        // Preserve the original complete-cycle admission: a handled down may
        // hand off key status or hide this window before its owned release.
        try dispatchOwnedPhase(key, phase: repeatPress ? .repeatPress : .down, modifiers: modifiers, window: window)
        try dispatchOwnedPhase(key, phase: .up, modifiers: modifiers, window: window)
    }

    /// One positively owned phase; callers retain the key across presentation
    /// changes by sending down, repeat downs, then a single final up.
    func sendPhase(
        _ key: CalendarOwnedKey, phase: CalendarKeyboardPhase,
        modifiers: NSEvent.ModifierFlags? = nil, toWindow: NSWindow? = nil,
        file: StaticString = #fileID, line: UInt = #line
    ) throws {
        let window = toWindow ?? panel
        try #require(ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil)
        logCalendarKeyboardTarget(window, stage: "send-phase-\(key.rawValue)-\(String(describing: phase))", file: file, line: line)
        try #require(window.isVisible && window.isKeyWindow && NSApp.keyWindow === window)
        try dispatchOwnedPhase(key, phase: phase, modifiers: modifiers, window: window)
    }

    func expectOwnedPhases(
        after count: Int, key: CalendarOwnedKey, window: NSWindow,
        phases: [CalendarKeyboardPhase]
    ) {
        let receipts = Array(dispatch.phases.dropFirst(count))
        #expect(receipts.count == phases.count)
        #expect(zip(receipts, phases).allSatisfy { receipt, phase in
            receipt.key == key && receipt.phase == phase
                && receipt.windowNumber == window.windowNumber
                && receipt.queueIdentityValidated && receipt.senderAdmissionCurrentEventMatchesExpected
        })
    }

    private func dispatchOwnedPhase(
        _ key: CalendarOwnedKey, phase: CalendarKeyboardPhase,
        modifiers: NSEvent.ModifierFlags?, window: NSWindow
    ) throws {
        let type: NSEvent.EventType = phase == .up ? .keyUp : .keyDown
        let event = try #require(NSEvent.keyEvent(
            with: type, location: .zero, modifierFlags: modifiers ?? key.modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil,
            characters: key.characters, charactersIgnoringModifiers: key.ignoringModifiers,
            isARepeat: phase == .repeatPress, keyCode: key.code
        ))
        try #require(event.window === window)
        NSApp.postEvent(event, atStart: true)
        let mask: NSEvent.EventTypeMask = type == .keyDown ? .keyDown : .keyUp
        let retrieved = try #require(NSApp.nextEvent(
            matching: mask, until: Date(), inMode: .default, dequeue: true
        ))
        guard retrieved.window === window,
              retrieved.type == event.type,
              retrieved.windowNumber == event.windowNumber,
              abs(retrieved.timestamp - event.timestamp) < 0.001,
              retrieved.keyCode == event.keyCode,
              retrieved.characters == event.characters,
              retrieved.charactersIgnoringModifiers == event.charactersIgnoringModifiers,
              retrieved.modifierFlags.intersection(Self.semanticModifiers) ==
                event.modifierFlags.intersection(Self.semanticModifiers),
              retrieved.isARepeat == event.isARepeat else {
            var guardEvidence: [String: Bool] = [
                "objectIdentityMatches": retrieved === event,
                "retrievedWindowOwned": retrieved.window === window,
                "postedWindowOwned": event.window === window,
                "retrievedTypeMatches": retrieved.type == type
            ]
            // Only inspect payload after positive owned-window/type identity.
            // Report equality booleans, never unrelated input or raw key data.
            if retrieved.window === window, retrieved.type == type {
                guardEvidence["windowNumberMatches"] = retrieved.windowNumber == event.windowNumber
                guardEvidence["timestampMatches"] = retrieved.timestamp == event.timestamp
                guardEvidence["timestampWithinOneMillisecond"] = abs(retrieved.timestamp - event.timestamp) < 0.001
                guardEvidence["keyCodeMatches"] = retrieved.keyCode == event.keyCode
                guardEvidence["charactersMatch"] = retrieved.characters == event.characters
                guardEvidence["ignoringModifiersMatch"] = retrieved.charactersIgnoringModifiers == event.charactersIgnoringModifiers
                guardEvidence["modifierFlagsMatch"] = retrieved.modifierFlags == event.modifierFlags
                guardEvidence["semanticModifierFlagsMatch"] =
                    retrieved.modifierFlags.intersection(Self.semanticModifiers) ==
                    event.modifierFlags.intersection(Self.semanticModifiers)
                guardEvidence["repeatMatches"] = retrieved.isARepeat == event.isARepeat
            }
            let data = try JSONSerialization.data(withJSONObject: guardEvidence, options: [.sortedKeys])
            print("GLIMPSE_KEYBOARD_QUEUE_GUARD \(String(decoding: data, as: UTF8.self))")
            NSApp.postEvent(retrieved, atStart: true)
            Issue.record("Unexpected event requeued; no unrelated event dispatched or read")
            throw CalendarKeyboardFixtureError.unexpectedEvent
        }
        dispatch.expected = retrieved
        defer { dispatch.expected = nil }
        trace("queue-retrieved-\(key.rawValue)-\(type.rawValue)")
        let actionsBeforeDispatch = actionCurrentEvents.value.count
        let callbacksBeforeDispatch = callbacks.rows.count
        let currentBeforeDispatchMatches = NSApp.currentEvent === retrieved
        let senderAdmissionCurrentEventMatchesExpected = NSApp.currentEvent === retrieved && dispatch.expected === retrieved
        try #require(senderAdmissionCurrentEventMatchesExpected, "The sender admission must have exact owned current-event identity")
        NSApp.sendEvent(retrieved)
        let currentAfterDispatchIsNil = NSApp.currentEvent == nil
        let currentAfterDispatchMatches = NSApp.currentEvent === retrieved
        let actionIdentitySlice = Array(actionCurrentEvents.value.dropFirst(actionsBeforeDispatch))
        let callbackIdentitySlice = callbacks.rows.dropFirst(callbacksBeforeDispatch).map {
            $0["currentEventMatchesExpected"] as? Bool == true
        }
        if dispatch.phases.count < 128 {
            let observation: [String: Any] = [
                "currentBeforeMatchesRetrieved": currentBeforeDispatchMatches,
                "currentAfterIsNil": currentAfterDispatchIsNil,
                "currentAfterMatchesRetrieved": currentAfterDispatchMatches,
                "expectedStillMatchesRetrieved": dispatch.expected === retrieved,
                "actionIdentityCount": actionIdentitySlice.count,
                "actionIdentityBooleans": Array(actionIdentitySlice.prefix(8)),
                "callbackIdentityCount": callbackIdentitySlice.count,
                "callbackIdentityBooleans": Array(callbackIdentitySlice.prefix(8))
            ]
            let data = try JSONSerialization.data(withJSONObject: observation, options: [.sortedKeys])
            // Empty slices supply no handler proof; release retains only sender evidence.
            print("GLIMPSE_KEYBOARD_DISPATCH_EQUALITY \(String(decoding: data, as: UTF8.self))")
        }
        trace("application-dispatched-\(key.rawValue)-\(type.rawValue)")
        dispatch.phases.append(CalendarKeyboardSentPhase(
            key: key, phase: phase, windowNumber: window.windowNumber,
            queueIdentityValidated: true,
            senderAdmissionCurrentEventMatchesExpected: senderAdmissionCurrentEventMatchesExpected
        ))
    }

    func trace(_ stage: String) {
        sequence += 1
        let row: [String: Any] = [
            "sequence": sequence, "stage": stage,
            "windowVisible": panel.isVisible, "windowKey": panel.isKeyWindow,
            "firstResponderIsWindow": panel.firstResponder === panel,
            "firstResponderIsHosting": panel.firstResponder === hosting,
            "currentEventMatchesExpected": dispatch.expected != nil && NSApp.currentEvent === dispatch.expected,
            "lastPublishedOwner": focus.owner?.rawValue ?? "nil",
            "ownerObservations": focus.observations,
            "gridRenderingFocused": focus.gridRenderingFocused,
            "completionNotifications": lifecycle.completions,
            "editorPresentationRequests": effects.presentationRequests,
            "actions": actions.value
        ]
        if let data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            print("GLIMPSE_KEYBOARD_ROOT \(text)")
        }
    }

    func close() {
        dispatch.expected = nil
        effects.heldEditorPresentations.removeAll()
        effects.heldCrossScreenShows.removeAll()
        if let completionObserver { NotificationCenter.default.removeObserver(completionObserver) }
        completionObserver = nil
        panel.orderOut(nil)
        hosting.rootView = AnyView(EmptyView())
        panel.makeFirstResponder(nil)
        panel.initialFirstResponder = nil
        panel.contentView = nil
        panel.close()
        hotkeyFixture.cleanupDefaults()
        #expect(hotkeyFixture.backend.operations.isEmpty)
        #expect(!panel.isVisible && !panel.isKeyWindow)
        #expect(panel.firstResponder == nil || panel.firstResponder === panel)
        trace("closed")
    }

    private func pumpRunLoop() {
        CFRunLoopRunInMode(.defaultMode, 0.01, true)
    }

    // Arrow/numeric-pad/function/device flags describe key classification.
    // Preserve every modifier which can alter application routing or text case.
    private static let semanticModifiers: NSEvent.ModifierFlags = [
        .command, .control, .option, .shift, .capsLock
    ]
}

/// Sender evidence includes release; production local callbacks observe only
/// down/repeat. These receipts do not claim physical input or native up handling.
struct CalendarKeyboardSentPhase {
    let key: CalendarOwnedKey
    let phase: CalendarKeyboardPhase
    let windowNumber: Int
    let queueIdentityValidated: Bool
    let senderAdmissionCurrentEventMatchesExpected: Bool
}

@MainActor
private final class CalendarKeyboardDispatchReceipt {
    var expected: NSEvent?
    var phases: [CalendarKeyboardSentPhase] = []
}

@MainActor
private final class CalendarKeyboardFocusReceipt {
    var owner: CalendarKeyboardOwner?
    var observations: [String] = []
    let gridRenderingSnapshot = LockIsolated(false)
    var gridRenderingFocused: Bool { gridRenderingSnapshot.value }
}

@MainActor
private final class CalendarKeyboardCallbackReceipt {
    var rows: [[String: Any]] = []
}

@MainActor
private final class CalendarKeyboardEffectReceipt {
    var presentationRequests = 0
    var submissions: [String] = []
    var currentEvents: [Bool] = []
    var presentationSnapshot: CalendarPresentationSnapshot?
    var previousAppRestorations = 0
    var terminations = 0
    var heldEditorPresentations: [@MainActor () -> Void] = []
    var heldCrossScreenShows: [@MainActor () -> Void] = []
}

@MainActor
private final class CalendarKeyboardLifecycleReceipt {
    var completions = 0
}

/// One owned native responder proves peer delivery while the calendar is nonkey.
/// It records only its own keyDown; it implements no traversal or production route.
@MainActor
private final class CalendarKeyboardPeerView: NSView {
    var receivedKeys = 0
    var currentEventMatched = false
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        receivedKeys += 1
        currentEventMatched = event.window === window && NSApp.currentEvent === event
    }
}

@MainActor
final class CalendarKeyboardOwnedPeer {
    let panel = NSPanel(
        contentRect: NSRect(x: -1800, y: -1800, width: 120, height: 80),
        styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false
    )
    private let view = CalendarKeyboardPeerView(frame: NSRect(x: 0, y: 0, width: 120, height: 80))
    var receivedKeys: Int { view.receivedKeys }
    var currentEventMatched: Bool { view.currentEventMatched }

    init() {
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.contentView = view
        let screens = NSScreen.screens.reduce(NSRect.zero) { $0.union($1.frame) }
        panel.setFrameOrigin(NSPoint(x: screens.minX - 1800, y: screens.minY - 1800))
    }

    func makeKey() throws {
        panel.makeKeyAndOrderFront(nil)
        try #require(panel.isKeyWindow && NSApp.keyWindow === panel)
        #expect(panel.makeFirstResponder(view))
        let responderOwned = panel.firstResponder === view
        #expect(responderOwned)
    }

    func close() {
        panel.orderOut(nil)
        panel.makeFirstResponder(nil)
        panel.initialFirstResponder = nil
        panel.contentView = nil
        panel.close()
        #expect(!panel.isVisible && !panel.isKeyWindow)
    }
}

@MainActor
private struct CalendarKeyboardTestOwnerObserver: View {
    @FocusedValue(\.calendarKeyboardOwner) private var owner
    let receipt: CalendarKeyboardFocusReceipt

    var body: some View {
        Color.clear.frame(width: 0, height: 0).accessibilityHidden(true)
            .onChange(of: owner, initial: true) { _, owner in
                receipt.owner = owner
                receipt.observations.append(owner?.rawValue ?? "nil")
            }
    }
}

private enum CalendarKeyboardFixtureError: Error {
    case unexpectedEvent
}

enum CalendarOwnedKey: String, Sendable {
    case tab, backTab, left, right, up, down, returnKey, keypadEnter, space, searchShortcut, closeShortcut, escape

    var code: UInt16 {
        switch self {
        case .tab, .backTab: 48
        case .left: 123
        case .right: 124
        case .up: 126
        case .down: 125
        case .returnKey: 36
        case .keypadEnter: 76
        case .space: 49
        case .searchShortcut: 5
        case .closeShortcut: 13
        case .escape: 53
        }
    }
    var characters: String {
        switch self {
        case .tab: "\t"
        case .backTab: "\u{19}"
        case .left: "\u{F702}"
        case .right: "\u{F703}"
        case .up: "\u{F700}"
        case .down: "\u{F701}"
        case .returnKey: "\r"
        case .keypadEnter: "\u{3}"
        case .space: " "
        case .searchShortcut: "g"
        case .closeShortcut: "w"
        case .escape: "\u{1B}"
        }
    }
    // Apple's charactersIgnoringModifiers preserves Shift. Backtab therefore
    // retains U+0019 here rather than reverting to an unshifted Tab character.
    var ignoringModifiers: String { characters }
    var modifiers: NSEvent.ModifierFlags {
        switch self {
        case .backTab: .shift
        case .keypadEnter: .numericPad
        case .searchShortcut, .closeShortcut: .command
        default: []
        }
    }
    var routerKey: CalendarKeyboardKey { CalendarKeyboardKey(nativeCode: code) }
}
