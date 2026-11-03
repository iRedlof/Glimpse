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
        try await settings.open(visibleFrame: placement.visibleFrame, avoiding: placement.avoiding)
        let owner = try #require(settings.controller.window)
        try #require(owner.makeFirstResponder(nil))
        calendar.clearActionReceipts()
        func focusedLabels() -> [String] {
            settings.nodes().filter { $0.object.isAccessibilityFocused?() == true }
                .compactMap(\.label)
        }
        try calendar.send(.tab, toWindow: owner)
        await settings.settle()
        print("GLIMPSE_SETTINGS_FOCUS first-tab=\(focusedLabels()) full-access=\(NSApp.isFullKeyboardAccessEnabled)")
        #expect(focusedLabels().contains("General"))
        try calendar.send(.tab, toWindow: owner)
        await settings.settle()
        print("GLIMPSE_SETTINGS_FOCUS second-tab=\(focusedLabels())")
        #expect(focusedLabels().contains("Menu bar"))
        try calendar.send(.space, toWindow: owner)
        await settings.settle()
        #expect(settings.controller.selection.section == .menuBar)
        try calendar.send(.backTab, toWindow: owner)
        await settings.settle()
        #expect(focusedLabels().contains("General"))
        try calendar.send(.returnKey, toWindow: owner)
        await settings.settle()
        #expect(settings.controller.selection.section == .general)
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
        settings.controller.select(.calendar)
        await settings.settle()
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
        #expect(settings.controller.selection.section == .calendar)
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
        try await settings.open(visibleFrame: placement.visibleFrame, avoiding: placement.avoiding)
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
    func settingsPanesAndRecoveryRemainReachable(constrained: Bool, dark: Bool) async throws {
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
        let saved = settings.saved.value
        let suffix = "\(constrained ? "constrained" : "nominal")-\(dark ? "dark" : "light")"
        for section in SettingsSection.allCases {
            let entry = try #require(settings.nodes().first {
                $0.role == .button && $0.label == section.title
            })
            try #require(entry.press())
            await settings.settle()
            try settings.loadAccessibilityWindowTree()
            #expect(settings.controller.selection.section == section)
            #expect(owner.frame == frame)
            #expect(settings.saved.value == saved)
            try settings.saveBitmap(name: "settings-\(section.rawValue)-\(suffix)")
        }
        let searchToggle = try #require(settings.nodes().first {
            $0.label == "AI date search" && $0.role == .checkBox
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
            $0.label == "AI date search" && $0.role == .checkBox
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
        settings.controller.select(.general)
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
        calendar.panel.requestSettings = { [weak delegate] in delegate?.showSettings() }
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
            $0.role == .button && ["Open preferences", "Open Settings"].contains($0.label ?? "")
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
        try await settings.open(visibleFrame: visible, avoiding: placement.avoiding)
        let owner = try #require(settings.controller.window)
        let frame = owner.frame
        let saved = settings.saved.value
        #expect(visible.insetBy(dx: 10, dy: 10).contains(frame))
        if !constrained {
            #expect(owner.contentRect(forFrameRect: frame).size == NSSize(width: 600, height: 480))
        }
        for section in SettingsSection.allCases {
            let button = try #require(settings.nodes().first {
                $0.role == .button && $0.label == section.title
            })
            try #require(button.press())
            await settings.settle()
            try settings.loadAccessibilityWindowTree()
            #expect(settings.controller.selection.section == section)
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
        try await settings.open(visibleFrame: placement.visibleFrame, avoiding: placement.avoiding)
        try #require(NSApp.keyWindow === settings.controller.window)
        #expect(calendar.panel.isVisible == pinned)
        #expect(calendar.store.isPinned == pinned && calendar.panel.isPinned == pinned)
        if pinned {
            #expect(calendar.store.displayedMonth == snapshot.month)
            #expect(calendar.store.selectedDate == snapshot.date)
            for section in SettingsSection.allCases {
                settings.controller.select(section)
                await settings.settle()
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
        try await settings.open(visibleFrame: placement.visibleFrame, avoiding: placement.avoiding)
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

    @Test(arguments: ["close", "orderOut", "keyLoss", "appDeactivation", "sectionExit"])
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
        case "sectionExit": fixture.controller.select(.menuBar)
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
        fixture.controller.select(.menuBar)
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
        #expect(fixture.controller.selection.section == .menuBar)
        #expect(fixture.store.startOfWeekday == 7)
        #expect(!fixture.store.showAISearch)
        #expect(fixture.store.launchAtLoginStatus == .requiresApproval)
        fixture.controller.select(.general)
        await fixture.settle()
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
        try fixture.send(.tab)
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
        try await settings.open()
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

    func open(visibleFrame: NSRect? = nil, avoiding: NSRect? = nil) async throws {
        let bounds = NSScreen.screens.reduce(NSRect.zero) { $0.union($1.frame) }
        controller.show(visibleFrame: visibleFrame ?? NSRect(
            x: bounds.minX - 800, y: bounds.minY - 700, width: 600, height: 480
        ), avoiding: avoiding)
        if !accessibilityPrepared {
            let owner = try #require(controller.window)
            let hosting = try #require(owner.contentView as? NSHostingView<SettingsRootView>)
            // Attach the AX-enabled root before key presentation, matching production.
            owner.orderOut(nil)
            let replacement = NSHostingView(rootView: AnyView(
                hosting.rootView.environment(\.accessibilityEnabled, true)
            ))
            replacement.sizingOptions = []
            owner.contentView = replacement
            accessibilityPrepared = true
            controller.show(visibleFrame: visibleFrame, avoiding: avoiding)
        }
        await settle()
        let owner = try #require(controller.window)
        try #require(owner.isVisible && owner.isKeyWindow && NSApp.keyWindow === owner)
        try #require(!(owner is NSPanel))
        try loadAccessibilityWindowTree()
        await settle()
    }

    func loadAccessibilityWindowTree() throws {
        // Match ordinary viewport hosts: a client read materializes SwiftUI's
        // virtual controls, including newly selected panes.
        let application = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        var windows: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            application, kAXWindowsAttribute as CFString, &windows
        )
        try #require(result == .success)
    }

    func startRecording() async throws {
        try #require(!model.isRecording)
        let matches = nodes().filter { $0.role == .button && $0.label == "Set and enable shortcut" }
        try #require(matches.count == 1)
        let recorder = try #require(matches.first)
        let owner = recorder.object.accessibilityWindow?() as? NSWindow
        try #require(owner === controller.window)
        try #require(recorder.press())
        await settle()
        try #require(model.isRecording)
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
            $0.label == "AI date search" && $0.role == .checkBox
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
                    $0.label == "AI date search" && $0.role == .checkBox
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
    var submissions: [String] { effects.submissions }
    var submissionCurrentEvents: [Bool] { effects.currentEvents }
    var editorPresentationRequests: Int { effects.presentationRequests }
    var presentationSnapshot: CalendarPresentationSnapshot? { effects.presentationSnapshot }
    var previousAppRestorations: Int { effects.previousAppRestorations }
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
                }
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
        try showOwner.showCalendar()
        #expect(completions == before + 1)
        let responderIsWindow = panel.firstResponder === panel
        #expect(responderIsWindow)
        await settleRendering()
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
        toWindow: NSWindow? = nil
    ) throws {
        let window = toWindow ?? ownedPeer?.panel ?? panel
        try #require(ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil)
        try #require(window.isVisible && window.isKeyWindow && NSApp.keyWindow === window)
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            let event = try #require(NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: modifiers ?? key.modifiers,
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil,
                characters: key.characters, charactersIgnoringModifiers: key.ignoringModifiers,
                isARepeat: type == .keyDown && repeatPress, keyCode: key.code
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
            trace("queue-retrieved-\(key.rawValue)-\(type.rawValue)")
            NSApp.sendEvent(retrieved)
            trace("application-dispatched-\(key.rawValue)-\(type.rawValue)")
            dispatch.expected = nil
        }
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

@MainActor
private final class CalendarKeyboardDispatchReceipt {
    var expected: NSEvent?
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
