import AppKit
import ApplicationServices
import ComposableArchitecture
import EventKit
import GlimpseCore
import SwiftUI
import Testing
@testable import Glimpse

/// Owns a key panel, so root runs this suite in its isolated native test host.
/// Provider work is always the explicit cancellation-ignoring synthetic client.
@Suite(.serialized, .enabled(if:
    ProcessInfo.processInfo.environment["GLIMPSE_CALENDAR_KEYBOARD_ACCEPTANCE"] == "1"
))
@MainActor
struct AIDateSearchIntegrationTests {
    @Test(arguments: AIDateIntegrationOutcome.allCases)
    func actualRowShowsStaticOutcomesAndResubmitsOnce(outcome: AIDateIntegrationOutcome) async throws {
        try await withAIDateIntegrationFixture { fixture in
            let root = fixture.root
            try await root.openThroughShowOwner()
            let first = try await submitDraft(fixture)
            #expect(root.aiModel.isProcessing)
            #expect(root.aiModel.errorMessage == nil)
            #expect(nodes(root, named: CalendarDateSearchRow.closeName).isEmpty)
            #expect(root.submissions == [Self.draft])
            #expect(root.submissionCurrentEvents == [true])
            await first.release(outcome.result)
            try await fixture.completed(first, at: 0)
            #expect(!root.aiModel.isProcessing)
            #expect(root.aiModel.currentRequestID == nil)
            #expect(root.aiModel.isEditorOpen && root.aiModel.draft == Self.draft)
            #expect(root.aiModel.errorMessage == outcome.errorMessage
                && root.aiModel.clarification == outcome.clarification)
            #expect(try editor(root).string == Self.draft)
            try expectFeedback(root, outcome.feedback)
            #expect(root.actions.value.isEmpty)
            #expect(root.store.selectedDate == root.today)
            #expect(await fixture.requests.count == 1)

            // Only a second owned native Return retries the retained draft.
            try root.send(.returnKey)
            try #require(root.aiTasks.count == 2)
            #expect(root.aiModel.isProcessing && root.aiModel.errorMessage == nil)
            let second = try await fixture.request(at: 1)
            #expect(second.query == Self.draft && second.provider == .proxy)
            let target = try #require(root.date(day: 18))
            await second.release(.success(.navigate(CivilDate(target, calendar: .current))))
            try await fixture.completed(second, at: 1)
            #expect(root.actions.value == ["aiDate"])
            #expect(root.store.selectedDate == target)
            #expect(!root.aiModel.isEditorOpen && !root.aiModel.isProcessing)
            #expect(root.aiModel.draft.isEmpty && root.aiModel.errorMessage == nil)
            #expect(root.nativeEditorFields.isEmpty)
            #expect(root.submissions == [Self.draft, Self.draft])
            #expect(root.submissionCurrentEvents == [true, true])
            #expect(await fixture.requests.count == 2)
        }
    }

    @Test
    func cancellationEndsProgressWithoutFeedback() async throws {
        try await withAIDateIntegrationFixture { fixture in
            let root = fixture.root
            try await root.open()
            let request = try await submitDraft(fixture)
            await request.release(.failure(CancellationError()))
            try await fixture.completed(request, at: 0)
            #expect(!root.aiModel.isProcessing && root.aiModel.currentRequestID == nil)
            #expect(root.aiModel.errorMessage == nil)
            #expect(root.aiModel.isEditorOpen && root.aiModel.draft == Self.draft)
            #expect(try editor(root).string == Self.draft)
            #expect(root.actions.value.isEmpty)
            #expect(root.accessibilityNodes().allSatisfy { node in
                !AIDateIntegrationOutcome.allCases.contains { outcome in
                    node.label == outcome.feedback || node.value as? String == outcome.feedback
                }
            })
        }
    }

    @Test
    func nativeDraftEditRejectsLateCompletionAndAllowsClose() async throws {
        try await withAIDateIntegrationFixture { fixture in
            let root = fixture.root
            try await root.open()
            let request = try await submitDraft(fixture)
            let nativeEditor = try editor(root)
            #expect(nativeEditor.string == Self.draft)
            nativeEditor.setSelectedRange(NSRange(
                location: (nativeEditor.string as NSString).length, length: 0
            ))
            nativeEditor.insertText(" edited", replacementRange: NSRange(location: NSNotFound, length: 0))
            await root.settleRendering()
            #expect(root.aiModel.draft == Self.draft + " edited")
            #expect(!root.aiModel.isProcessing && root.aiModel.currentRequestID == nil)
            #expect(request.cancelCount.value > 0 && request.returnCount.value == 0)
            try root.loadOwnedAccessibilityTree()
            let dismiss = try control(root, named: CalendarDateSearchRow.closeName, role: .button)
            #expect(dismiss.press())
            #expect(!root.aiModel.isEditorOpen && root.aiModel.draft.isEmpty)
            let target = try #require(root.date(day: 18))
            await request.release(.success(.navigate(CivilDate(target, calendar: .current))))
            try await fixture.completed(request, at: 0)
            #expect(root.actions.value.isEmpty && root.store.selectedDate == root.today)
            #expect(root.aiModel.errorMessage == nil && root.nativeEditorFields.isEmpty)
            #expect(root.panel.isVisible && root.submissions.count == 1)
        }
    }

    @Test(arguments: AIDateIntegrationSettingsAction.allCases)
    func directSettingsSettersInvalidateBeforeCompletion(action: AIDateIntegrationSettingsAction) async throws {
        try await withAIDateIntegrationFixture(allowAISettings: true) { fixture in
            let root = fixture.root
            try await root.openThroughShowOwner()
            let request = try await submitDraft(fixture)
            let requestID = try #require(root.aiModel.currentRequestID)
            let settings = SettingsAIIntegrationHost(root: root)
            defer { settings.close() }
            try await settings.open()
            try await settings.revealControl(named: "AI provider", role: .popUpButton)
            try settings.loadAccessibilityWindowTree()
            #expect(root.aiModel.currentRequestID == requestID && root.aiModel.isProcessing)
            #expect(root.submissions.count == 1 && request.cancelCount.value == 0)
            switch action {
            case .disable:
                let toggle = try settings.control(named: "Enable AI date search", role: .checkBox)
                #expect(toggle.press())
                #expect(!root.preferences.showAISearch && !root.aiSettings.value.enabled)
                // No yield/redraw/delayed notification between setter and assertions.
                #expect(!root.store.showAISearch)
                #expect(!root.aiModel.isEditorOpen && root.aiModel.draft.isEmpty)
            case .provider:
                let unchanged = try await selectProvider(
                    root, settings: settings, title: "Auto", request: request
                )
                #expect(unchanged.preference == .auto && unchanged.savedPreference == .auto)
                #expect(unchanged.currentRequestID == requestID && unchanged.isProcessing)
                #expect(unchanged.cancelCount == 0 && unchanged.returnCount == 0)
                let state = try await selectProvider(
                    root, settings: settings, title: "Cloud AI", request: request
                )
                #expect(state.preference == .proxy)
                #expect(state.savedPreference == .proxy)
                #expect(state.isEditorOpen && state.draft == Self.draft)
                expectRequestRelinquished(state)
            case .providerRoundTrip:
                // Auto and Cloud resolve to the same synthetic provider. Each
                // real selection must advance the revision, even after a round trip.
                let cloud = try await selectProvider(
                    root, settings: settings, title: "Cloud AI", request: request
                )
                #expect(cloud.preference == .proxy)
                #expect(cloud.savedPreference == .proxy)
                expectRequestRelinquished(cloud)
                let auto = try await selectProvider(
                    root, settings: settings, title: "Auto", request: request
                )
                #expect(auto.preference == .auto)
                #expect(auto.savedPreference == .auto)
                #expect(auto.savedPreferences == [.proxy, .auto])
                #expect(auto.isEditorOpen && auto.draft == Self.draft)
                expectRequestRelinquished(auto)
            }
            #expect(!root.aiModel.isProcessing && root.aiModel.currentRequestID == nil)
            #expect(root.aiModel.errorMessage == nil)
            // The actual worker ignores cancel until this explicit release.
            #expect(request.returnCount.value == 0)
            #expect(request.cancelCount.value > 0)
            settings.close()
            #expect(root.panel.isVisible && root.submissions.count == 1)
            let target = try #require(root.date(day: 18))
            await request.release(.success(.navigate(CivilDate(target, calendar: .current))))
            try await fixture.completed(request, at: 0)
            #expect(root.actions.value.isEmpty)
            #expect(root.store.selectedDate == root.today)
            #expect(root.aiModel.errorMessage == nil)
            #expect(await fixture.requests.count == 1)
            if action == .disable {
                #expect(root.nativeEditorFields.isEmpty)
            } else {
                #expect(root.aiModel.isEditorOpen && root.aiModel.draft == Self.draft)
            }
        }
    }

    @Test(arguments: [false, true])
    func preferenceReloadReconcilesCurrentSettings(disable: Bool) async throws {
        try await withAIDateIntegrationFixture { fixture in
            let root = fixture.root
            try await root.open()
            let request = try await submitDraft(fixture)
            root.aiSettings.withValue {
                if disable { $0.enabled = false } else { $0.preference = .proxy }
            }
            // Exercise the actual root subscription with current injected saved data.
            NotificationCenter.default.post(name: .calendarPreferencesDidChange, object: nil)
            #expect(root.store.showAISearch == !disable)
            #expect(!root.aiModel.isProcessing && root.aiModel.currentRequestID == nil)
            if disable {
                #expect(!root.aiModel.isEditorOpen && root.aiModel.draft.isEmpty)
            } else {
                #expect(root.aiModel.isEditorOpen && root.aiModel.draft == Self.draft)
            }
            #expect(request.cancelCount.value > 0 && request.returnCount.value == 0)
            await request.release(.failure(AIDateFailure.transport))
            try await fixture.completed(request, at: 0)
            #expect(root.aiModel.errorMessage == nil && root.actions.value.isEmpty)
            #expect(await fixture.requests.count == 1)
        }
    }

    @Test
    func hiddenPreparationAndVisibleShowPreserveOwnership() async throws {
        try await withAIDateIntegrationFixture { fixture in
            let root = fixture.root
            try await root.openThroughShowOwner()
            let request = try await submitDraft(fixture)
            let requestID = try #require(root.aiModel.currentRequestID)
            let nativeEditor = try editor(root)
            nativeEditor.setSelectedRange(NSRange(location: 3, length: 5))
            let responder = root.panel.firstResponder
            let completions = root.completions
            root.store.send(.togglePin) // Recompute the same actual root identity.
            for _ in 0..<2 { try root.showOwner.showCalendar() }
            #expect(root.completions == completions)
            #expect(root.panel.firstResponder === responder)
            #expect(nativeEditor.string == Self.draft)
            #expect(nativeEditor.selectedRange() == NSRange(location: 3, length: 5))
            #expect(root.aiModel.currentRequestID == requestID && root.aiModel.isProcessing)
            #expect(root.aiModel.draft == Self.draft && root.submissions.count == 1)

            root.panel.orderOut(nil)
            #expect(root.aiModel.currentRequestID == nil && !root.aiModel.isProcessing)
            #expect(!root.aiModel.isEditorOpen && root.aiModel.draft.isEmpty)
            root.panel.prepareForReopen() // The owned didShow notification is hidden.
            #expect(!root.panel.isVisible)
            await root.settleRendering()
            try root.loadOwnedAccessibilityTree()
            // A public press exercises the actual collapsed row while hidden.
            // The subsequent direct submit is an eligibility probe of the model
            // that received the root notification, not a native Return claim.
            let prompt = try control(root, named: CalendarDateSearchRow.accessibilityName, role: .button)
            #expect(prompt.press())
            root.aiModel.setDraft("synthetic hidden probe")
            let hiddenTask = root.aiModel.submit()
            if let hiddenTask { root.trackEligibilityProbe(hiddenTask) }
            #expect(hiddenTask == nil)
            #expect(root.submissions.count == 1)
            let target = try #require(root.date(day: 18))
            await request.release(.success(.navigate(CivilDate(target, calendar: .current))))
            try await fixture.completed(request, at: 0)
            #expect(root.actions.value.isEmpty)
            #expect(await fixture.requests.count == 1)
        }
    }

    @Test(arguments: AIDateIntegrationLifecycle.allCases)
    func dismissEscapeAndRemovalRejectLateCompletion(boundary: AIDateIntegrationLifecycle) async throws {
        try await withAIDateIntegrationFixture { fixture in
            let root = fixture.root
            try await root.open()
            let request = try await submitDraft(fixture)
            switch boundary {
            case .escape:
                try root.send(.escape)
            case .hide:
                root.panel.orderOut(nil)
            case .removeRoot:
                root.hosting.rootView = AnyView(EmptyView())
                await root.settleRendering() // Actual SwiftUI removal; no willHide.
                #expect(root.panel.isVisible)
            }
            #expect(root.aiModel.currentRequestID == nil && !root.aiModel.isProcessing)
            #expect(!root.aiModel.isEditorOpen && root.aiModel.draft.isEmpty)
            #expect(root.aiModel.errorMessage == nil)
            #expect(request.returnCount.value == 0)
            #expect(request.cancelCount.value > 0)
            let target = try #require(root.date(day: 18))
            await request.release(.success(.navigate(CivilDate(target, calendar: .current))))
            try await fixture.completed(request, at: 0)
            #expect(root.actions.value.isEmpty)
            #expect(root.store.selectedDate == root.today)
            #expect(!root.aiModel.isEditorOpen && root.aiModel.draft.isEmpty)
            #expect(root.aiModel.errorMessage == nil)
            if boundary == .escape { #expect(root.panel.isVisible) }
            if boundary == .hide {
                try await root.openThroughShowOwner()
                #expect(root.nativeEditorFields.isEmpty)
            }
        }
    }

    @Test(arguments: AIDateIntegrationOutcome.allCases)
    func failureCopyFitsAndRemainsAccessible(outcome: AIDateIntegrationOutcome) async throws {
        try await withAIDateIntegrationFixture(maximumHeight: 312) { fixture in
            let root = fixture.root
            try await root.openThroughShowOwner()
            let request = try await submitDraft(fixture)
            await request.release(outcome.result)
            try await fixture.completed(request, at: 0)
            try expectFeedback(root, outcome.feedback)
            let scroll = try #require(accessibilityScrollView(in: root.hosting))
            let document = try #require(scroll.documentView)
            let feedback = try #require(feedbackNodes(root, outcome.feedback).first)
            let inDocument = document.convert(root.panel.convertFromScreen(feedback.frame), from: nil)
            _ = document.scrollToVisible(inDocument.insetBy(dx: -8, dy: -8))
            scroll.reflectScrolledClipView(scroll.contentView)
            await root.settleRendering()
            let visibleFeedback = try #require(feedbackNodes(root, outcome.feedback).first)
            let clip = root.panel.convertToScreen(scroll.contentView.convert(scroll.contentView.bounds, to: nil))
            let body = NSRect(
                x: root.panel.frame.minX + (PanelGeometry.panelWidth - PanelGeometry.contentWidth) / 2,
                y: clip.minY, width: PanelGeometry.contentWidth, height: clip.height
            )
            #expect(abs(root.panel.frame.width - PanelGeometry.panelWidth) < PanelGeometry.tolerance)
            #expect(root.panel.layoutState.isOverflowing)
            #expect(visibleFeedback.frame.width > 0 && visibleFeedback.frame.height > 0)
            #expect(clip.contains(visibleFeedback.frame))
            #expect(visibleFeedback.frame.minX >= body.minX - PanelGeometry.tolerance)
            #expect(visibleFeedback.frame.maxX <= body.maxX + PanelGeometry.tolerance)
            #expect(document.frame.width <= PanelGeometry.contentWidth + PanelGeometry.tolerance)
            #expect(abs(scroll.contentView.bounds.minX) < PanelGeometry.tolerance)
            #expect(scroll.horizontalScroller == nil || scroll.horizontalScroller?.isHidden == true)
            let dismiss = try control(root, named: CalendarDateSearchRow.closeName, role: .button)
            let textField = try control(root, named: CalendarDateSearchRow.accessibilityName, role: .textField)
            #expect(dismiss.help == "Clears the query and closes Ask Glimpse.")
            expectDateSearchTarget(dismiss.frame)
            #expect(!dismiss.frame.intersects(textField.frame))
            #expect(textField.value as? String == Self.draft)
            #expect(dismiss.press())
            #expect(!root.aiModel.isEditorOpen && root.aiModel.draft.isEmpty)
            #expect(root.aiModel.errorMessage == nil && root.aiModel.currentRequestID == nil)
            await root.settleRendering()
            #expect(root.nativeEditorFields.isEmpty && root.panel.isVisible)
            #expect(root.actions.value.isEmpty && root.submissions.count == 1)
        }
    }

    private static let draft = "synthetic next Friday"

    // Preselecting a time, or letting Return resubmit while choosing, breaks the honest button.
    @Test
    func liveCreateNeedsAnExplicitPickAndSavesOnce() async throws {
        let saves = LockIsolated<[NewEvent]>([])
        let removals = LockIsolated(0)
        let work = WritableCalendar(id: "work", title: "Work")
        let day = CivilDate(year: 2030, month: 11, day: 18)!
        let draft = EventDraft(title: "Coffee with Priya", day: day, window: .partOfDay(.afternoon), durationMinutes: 30)
        let eventKit = EventKitClient(
            requestAccess: {
                Issue.record("Full-access fixture must not prompt")
                return true
            },
            fetchEvents: { _ in [] },
            authorizationStatus: { .fullAccess },
            fetchEventsInInterval: { _ in [] },
            defaultWritableCalendar: { work },
            saveEvent: { new in
                saves.withValue { $0.append(new) }
                return SavedEvent(eventID: "saved-1", title: new.title, start: new.start, end: new.end,
                                  calendarTitle: work.title)
            },
            removeEvent: { _ in removals.withValue { $0 += 1 } }
        )
        let root = try CalendarKeyboardRootFixture(
            showAI: true,
            aiClient: AIDateQueryClient(resolveProvider: { _ in .proxy }, interpret: { _, _ in .create(draft) }),
            eventKitClient: eventKit
        )
        defer { root.close() }
        try await root.openThroughShowOwner()
        try root.send(.searchShortcut)
        await root.settleRendering()
        let field = try root.nativeEditorField()
        let nativeEditor = try #require(field.currentEditor() as? NSTextView)
        nativeEditor.insertText("coffee with Priya Monday afternoon", replacementRange: NSRange(location: NSNotFound, length: 0))
        await root.settleRendering()
        try root.send(.returnKey)
        try #require(root.aiTasks.count == 1)
        try await root.aiTasks[0].finish()
        for _ in 0..<50 where root.store.schedule.phase != .choosing { await root.settleRendering() }
        #expect(root.store.schedule.phase == .choosing)
        #expect(root.store.schedule.slots.count == 3)
        #expect(root.store.schedule.selectedSlotIndex == nil)
        #expect(root.aiModel.isEditorOpen)

        // Return before any pick neither books nor resubmits.
        try root.send(.returnKey)
        try root.send(.returnKey)
        await root.settleRendering()
        #expect(saves.value.isEmpty)
        #expect(root.aiTasks.count == 1)

        try root.send(.down)
        try root.send(.down)
        await root.settleRendering()
        #expect(root.store.schedule.selectedSlotIndex == 1)
        #expect(root.actions.value.isEmpty, "Arrows must not browse months while picking a time")

        try root.send(.returnKey)
        for _ in 0..<50 where root.store.schedule.undo == nil { await root.settleRendering() }
        let picked = root.store.calendar.date(bySettingHour: 13, minute: 30, second: 0, of: day.date(in: root.store.calendar)!)!
        #expect(saves.value == [NewEvent(title: "Coffee with Priya", start: picked,
                                         end: picked.addingTimeInterval(30 * 60), calendarID: "work")])
        #expect(root.store.schedule.undo?.status == .available)
        #expect(!root.aiModel.isEditorOpen)
        #expect(removals.value == 0)
        try await root.awaitAcceptedSubmissions()
    }

    private func createFixture(
        status: LockIsolated<EKAuthorizationStatus>, requests: LockIsolated<Int>,
        saves: LockIsolated<[NewEvent]> = LockIsolated([])
    ) throws -> CalendarKeyboardRootFixture {
        let work = WritableCalendar(id: "work", title: "Work")
        let day = CivilDate(year: 2030, month: 11, day: 18)!
        let draft = EventDraft(title: "Coffee with Priya", day: day, window: .partOfDay(.afternoon), durationMinutes: 30)
        let eventKit = EventKitClient(
            requestAccess: {
                requests.withValue { $0 += 1 }
                status.setValue(.fullAccess)
                return true
            },
            fetchEvents: { _ in [] },
            authorizationStatus: { status.value },
            fetchEventsInInterval: { _ in [] },
            defaultWritableCalendar: { work },
            saveEvent: { new in
                saves.withValue { $0.append(new) }
                return SavedEvent(eventID: "saved-1", title: new.title, start: new.start, end: new.end,
                                  calendarTitle: work.title)
            },
            removeEvent: { _ in }
        )
        return try CalendarKeyboardRootFixture(
            showAI: true,
            aiClient: AIDateQueryClient(resolveProvider: { _ in .proxy }, interpret: { _, _ in .create(draft) }),
            eventKitClient: eventKit
        )
    }

    private func submitCreate(_ root: CalendarKeyboardRootFixture, until phase: ScheduleFeature.Phase) async throws {
        try await root.openThroughShowOwner()
        try root.send(.searchShortcut)
        await root.settleRendering()
        let nativeEditor = try #require(root.nativeEditorField().currentEditor() as? NSTextView)
        nativeEditor.insertText("coffee with Priya Monday afternoon", replacementRange: NSRange(location: NSNotFound, length: 0))
        await root.settleRendering()
        try root.send(.returnKey)
        try #require(root.aiTasks.count == 1)
        try await root.aiTasks[0].finish()
        for _ in 0..<50 where root.store.schedule.phase != phase { await root.settleRendering() }
        try #require(root.store.schedule.phase == phase)
    }

    // A double Return (or a habitual resubmit) after a create must not raise
    // the system calendar prompt; only the Allow button does, by click or by
    // Return once it has keyboard focus.
    @Test
    func liveCreateReturnInTheFieldNeverRequestsCalendarAccess() async throws {
        let status = LockIsolated<EKAuthorizationStatus>(.notDetermined)
        let requests = LockIsolated(0)
        let root = try createFixture(status: status, requests: requests)
        defer { root.close() }
        try await submitCreate(root, until: .needsAccess)

        try root.send(.returnKey)
        try root.send(.returnKey)
        await root.settleRendering()
        #expect(requests.value == 0)
        #expect(root.store.schedule.phase == .needsAccess)
        #expect(root.aiTasks.count == 1, "Return in .needsAccess must not resubmit either")

        try await root.focusOwner(.scheduleAllowAccess)
        try root.send(.returnKey)
        for _ in 0..<50 where root.store.schedule.phase != .choosing { await root.settleRendering() }
        #expect(requests.value == 1)
        #expect(root.store.schedule.phase == .choosing)
        try await root.awaitAcceptedSubmissions()
    }

    // With focus out of the field, ↓ used to browse to next year and Return to today.
    @Test
    func liveCreateSlotKeysWorkWhenFocusLeavesTheField() async throws {
        let status = LockIsolated<EKAuthorizationStatus>(.fullAccess)
        let requests = LockIsolated(0)
        let saves = LockIsolated<[NewEvent]>([])
        let root = try createFixture(status: status, requests: requests, saves: saves)
        defer { root.close() }
        try await submitCreate(root, until: .choosing)
        let month = root.store.displayedMonth

        try #require(root.panel.makeFirstResponder(nil))
        await root.settleRendering()
        try root.send(.returnKey)
        await root.settleRendering()
        #expect(saves.value.isEmpty, "Return with nothing picked must not save")
        try root.send(.down)
        await root.settleRendering()
        #expect(root.store.schedule.selectedSlotIndex == 0)
        #expect(root.actions.value.isEmpty, "Arrows must not browse months while picking a time")
        #expect(root.store.displayedMonth == month)

        try root.send(.returnKey)
        for _ in 0..<50 where root.store.schedule.undo == nil { await root.settleRendering() }
        #expect(saves.value.count == 1)
        #expect(root.actions.value.isEmpty, "Return must save the pick, not jump to today")
        #expect(root.store.schedule.undo?.status == .available)
        #expect(!root.aiModel.isEditorOpen)
        try await root.awaitAcceptedSubmissions()
    }

    private func submitDraft(_ fixture: AIDateIntegrationFixture) async throws -> AIDateIntegrationRequest {
        let root = fixture.root
        try root.send(.searchShortcut)
        await root.settleRendering()
        let nativeEditor = try editor(root)
        nativeEditor.insertText(Self.draft, replacementRange: NSRange(location: NSNotFound, length: 0))
        await root.settleRendering()
        #expect(root.aiModel.draft == Self.draft)
        try root.send(.returnKey)
        try #require(root.aiTasks.count == 1, "Native onSubmit must return an actual model Task")
        let request = try await fixture.request(at: 0)
        #expect(request.query == Self.draft && request.provider == .proxy)
        await root.settleRendering()
        try root.loadOwnedAccessibilityTree()
        return request
    }

    private func editor(_ root: CalendarKeyboardRootFixture) throws -> NSTextView {
        let field = try root.nativeEditorField()
        let editor = try #require(field.currentEditor() as? NSTextView)
        #expect(root.panel.firstResponder === editor)
        return editor
    }

    private func nodes(_ root: CalendarKeyboardRootFixture, named name: String) -> [AccessibilityTestNode] {
        root.accessibilityNodes().filter { $0.label == name }
    }

    private func control(
        _ root: CalendarKeyboardRootFixture, named name: String, role: NSAccessibility.Role
    ) throws -> AccessibilityTestNode {
        let matches = nodes(root, named: name).filter { $0.role == role }
        try #require(matches.count == 1, "Expected one owned \(name) \(role)")
        let node = try #require(matches.first)
        let owner = node.object.accessibilityWindow?() as? NSWindow
        try #require(owner === root.panel)
        return node
    }

    private func feedbackNodes(_ root: CalendarKeyboardRootFixture, _ message: String) -> [AccessibilityTestNode] {
        root.accessibilityNodes().filter { $0.role == .staticText && ($0.label == message || $0.value as? String == message) }
    }

    private func expectFeedback(_ root: CalendarKeyboardRootFixture, _ message: String) throws {
        #expect(feedbackNodes(root, message).count == 1)
        let dismiss = try control(root, named: CalendarDateSearchRow.closeName, role: .button)
        #expect(dismiss.enabled)
        #expect(root.accessibilityNodes().filter { $0.role == .textField }.count == 1)
    }

    private struct ProviderSetterState {
        let preference: AIProvider
        let savedPreference: AIProvider
        let savedPreferences: [AIProvider]
        let isEditorOpen: Bool
        let draft: String
        let isProcessing: Bool
        let currentRequestID: UUID?
        let errorMessage: String?
        let returnCount: Int
        let cancelCount: Int
    }

    private func expectRequestRelinquished(_ state: ProviderSetterState) {
        #expect(!state.isProcessing && state.currentRequestID == nil)
        #expect(state.errorMessage == nil)
        #expect(state.returnCount == 0 && state.cancelCount > 0)
    }

    private func selectProvider(
        _ root: CalendarKeyboardRootFixture, settings: SettingsAIIntegrationHost, title: String,
        request: AIDateIntegrationRequest
    ) async throws -> ProviderSetterState {
        let popup = try settings.control(named: "AI provider", role: .popUpButton)
        var state: ProviderSetterState?
        let selection = NativePickerSelection(
            expectedTitles: ["Auto", "Cloud AI", "On-device AI"], selectedTitle: title,
            onAction: {
                // Capture at the native setter boundary, before menu dismissal
                // or an await. Emit issues later in the originating test context.
                state = ProviderSetterState(
                    preference: root.preferences.aiProvider,
                    savedPreference: root.aiSettings.value.preference,
                    savedPreferences: root.aiSettingSaves.value.map(\.preference),
                    isEditorOpen: root.aiModel.isEditorOpen,
                    draft: root.aiModel.draft,
                    isProcessing: root.aiModel.isProcessing,
                    currentRequestID: root.aiModel.currentRequestID,
                    errorMessage: root.aiModel.errorMessage,
                    returnCount: request.returnCount.value,
                    cancelCount: request.cancelCount.value
                )
            }
        )
        defer { selection.close() }
        #expect(popup.press())
        // Await genuine didEndTracking after the synchronous state capture,
        // allowing deferred native presentation without losing test identity.
        try await selection.waitUntilTrackingEnds()
        try #require(selection.actionAttempted && selection.trackingEnded && !selection.timedOut,
                     "\(selection.observation)")
        return try #require(state)
    }
}

/// Uses the actual Settings controller with the root's existing injected store/model.
/// It changes only owned hosting accessibility, never production preferences or TCC.
@MainActor
private final class SettingsAIIntegrationHost {
    let controller: SettingsWindowController
    private let root: CalendarKeyboardRootFixture

    init(root: CalendarKeyboardRootFixture) {
        self.root = root
        let statusItem = root.showOwner
        controller = SettingsWindowController(
            store: root.preferences, hotkeyPreferences: root.hotkeyModel,
            onAISettingsChange: { [weak statusItem] enabled, preference in
                statusItem?.synchronizeAISettings(enabled: enabled, preference: preference)
            }
        )
    }

    func open() async throws {
        let placement = root.showOwner.prepareForSettingsPresentation()
        controller.show(
            visibleFrame: placement.visibleFrame, avoiding: placement.avoiding,
            calendar: placement.calendar
        )
        let window = try #require(controller.window)
        let hosting = try #require(window.contentView as? NSHostingView<SettingsRootView>)
        window.contentView = NSHostingView(rootView: AnyView(
            hosting.rootView.environment(\.accessibilityEnabled, true)
        ))
        await settle()
        try loadAccessibilityWindowTree()
        try #require(window.isVisible && window.isKeyWindow && NSApp.keyWindow === window)
        try #require(root.panel.isVisible && !root.panel.isKeyWindow)
    }

    func revealControl(named name: String, role: NSAccessibility.Role) async throws {
        let node = try control(named: name, role: role)
        let window = try #require(controller.window)
        let hosting = try #require(window.contentView)
        let scroll = try #require(accessibilityScrollView(in: hosting))
        let document = try #require(scroll.documentView)
        let rect = document.convert(window.convertFromScreen(node.frame), from: nil)
        document.scrollToVisible(rect)
        await settle()
        let current = try control(named: name, role: role)
        #expect(scroll.contentView.bounds.intersects(
            scroll.contentView.convert(window.convertFromScreen(current.frame), from: nil)
        ))
    }

    func loadAccessibilityWindowTree() throws {
        let application = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        var windows: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            application, kAXWindowsAttribute as CFString, &windows
        )
        try #require(result == .success)
    }

    func control(named name: String, role: NSAccessibility.Role) throws -> AccessibilityTestNode {
        var queue: [Any] = [try #require(controller.window?.contentView)]
        var visited: Set<ObjectIdentifier> = []
        var matches: [AccessibilityTestNode] = []
        var index = 0
        while index < queue.count {
            let object = queue[index] as AnyObject
            index += 1
            guard object.responds?(to: #selector(NSAccessibilityProtocol.accessibilityRole)) == true,
                  visited.insert(ObjectIdentifier(object)).inserted else { continue }
            let node = AccessibilityTestNode(object: object)
            if node.label == name && node.role == role { matches.append(node) }
            queue.append(contentsOf: node.children)
            queue.append(contentsOf: node.contents)
            queue.append(contentsOf: node.visibleChildren)
        }
        try #require(matches.count == 1)
        let node = try #require(matches.first)
        try #require(node.object.accessibilityWindow?() as? NSWindow === controller.window)
        return node
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

    private func pumpRunLoop() {
        CFRunLoopRunInMode(.defaultMode, 0.01, true)
    }

    func close() {
        controller.cancelRecording()
        controller.window?.contentView = nil
        controller.window?.close()
    }
}

enum AIDateIntegrationOutcome: CaseIterable, Sendable {
    case noDate, operational, unavailable

    var result: Result<AIIntent?, any Error> {
        switch self {
        case .noDate: .success(nil)
        case .operational: .failure(AIDateFailure.transport)
        case .unavailable: .failure(AIDateFailure.unavailable)
        }
    }

    var message: String {
        switch self {
        case .noDate: AIDateQueryModel.unparsedMessage
        case .operational: AIDateQueryModel.failureMessage
        case .unavailable: "On-device AI is unavailable. Choose Cloud AI in Preferences."
        }
    }

    /// An unparsed reply asks a clarifying line instead of showing an error.
    var errorMessage: String? { self == .noDate ? nil : message }
    var clarification: String? { self == .noDate ? message : nil }
    var feedback: String { self == .noDate ? "Glimpse asks: \(message)" : message }
}

enum AIDateIntegrationSettingsAction: CaseIterable, Sendable {
    case disable, provider, providerRoundTrip
}

enum AIDateIntegrationLifecycle: CaseIterable, Sendable {
    case escape, hide, removeRoot
}
