import AppKit
import ApplicationServices
import Combine
import ComposableArchitecture
import EventKit
import GlimpseCore
import SwiftUI
import Testing
@testable import Glimpse

/// Ordinary app tests include activation; run these notifications in an owned host.
@Suite(.serialized, .enabled(if:
    ProcessInfo.processInfo.environment["GLIMPSE_CALENDAR_KEYBOARD_ACCEPTANCE"] == "1"
))
@MainActor
struct CalendarAgendaRefreshTests {
    @Test
    func visibleStoreChangeRefetchesSelectedDayAndPreservesState() async throws {
        try await withAgendaRefreshFixture { fixture in
            try await fixture.mount()
            let initial = try await fixture.request(at: 0)
            try await fixture.complete(initial, with: [])
            fixture.store.send(.dateTapped(fixture.selectedDay))
            let selected = try await fixture.request(at: 1)
            try await fixture.expectContext(on: fixture.selectedDay, selectedWeek: fixture.selectedWeek)
            try await fixture.captureContext("selected-loading")
            try await fixture.captureContext("selected-loading-cap", maximumHeight: 312)
            let before = fixture.event("Before edit", on: fixture.selectedDay, hour: 11)
            try await fixture.complete(selected, with: [before])
            try await fixture.expectContext(on: fixture.selectedDay, selectedWeek: fixture.selectedWeek)
            try await fixture.captureContext("selected-result")
            try #require(fixture.panel.isVisible)
            try #require(fixture.store.selectedDate == fixture.selectedDay)
            try #require(fixture.hasEventLabel(before), "\(fixture.treeDescription)")
            let month = fixture.store.displayedMonth
            let actions = fixture.actions.value
            let activations = fixture.activations.value
            print("GLIMPSE_AGENDA_BASELINE queries=\(fixture.fetches.count.value) actions=\(actions) activations=\(activations) visible=\(fixture.panel.isVisible)")

            // No click, activation, date selection, Retry or reopen after this signal.
            fixture.postStoreChange()
            try await fixture.settle(until: { fixture.fetches.count.value == 3 },
                                     reason: "EventKit change must start a new selected-day query")
            let refresh = try await fixture.request(at: 2)
            try await fixture.expectContext(on: fixture.selectedDay, selectedWeek: fixture.selectedWeek)
            let edited = fixture.event("After edit", on: fixture.selectedDay, hour: 14)
            try await fixture.complete(refresh, with: [edited])
            #expect(refresh.date == Calendar.current.startOfDay(for: fixture.selectedDay))
            #expect(fixture.store.events == [edited])
            #expect(fixture.hasEventLabel(edited))
            #expect(!fixture.hasEventLabel(before))
            #expect(fixture.store.selectedDate == fixture.selectedDay)
            #expect(fixture.store.displayedMonth == month)
            #expect(fixture.store.isPinned && fixture.panel.isPinned)
            #expect(fixture.actions.value == actions + ["refresh"])
            #expect(fixture.activations.value == activations)
            #expect(fixture.refreshDispatchWasMain.value == [true])
            #expect(fixture.permissionRequests.value == 0)
            try await fixture.expectContext(on: fixture.selectedDay, selectedWeek: fixture.selectedWeek)
        }
    }

    @Test
    func visibleChangeUpdatesEditedAddedDeletedSnapshot() async throws {
        try await withAgendaRefreshFixture(isolated: true) { fixture in
            try await fixture.mountWithEmptyAgenda()
            fixture.store.send(.dateTapped(fixture.selectedDay))
            let selected = try await fixture.request(at: 1)
            let original = fixture.event("Original event", on: fixture.selectedDay)
            try await fixture.complete(selected, with: [original])
            let month = fixture.store.displayedMonth
            let activations = fixture.activations.value

            let added = (8...14).map {
                fixture.event("Added event \($0)", on: fixture.selectedDay, hour: $0)
            }
            let addition = try await fixture.invalidateAndRequest()
            try await fixture.complete(addition, with: added)
            #expect(added.prefix(5).allSatisfy { fixture.hasEventLabel($0) })
            #expect(!fixture.hasEventLabel(added[5]))
            #expect(fixture.hasText("+2 more"))
            #expect(!fixture.hasEventLabel(original))

            let edited = fixture.event("Edited event", on: fixture.selectedDay, hour: 15)
            let edit = try await fixture.invalidateAndRequest()
            try await fixture.complete(edit, with: [edited])
            #expect(fixture.hasEventLabel(edited))
            #expect(!fixture.hasText("+2 more"))
            #expect(!fixture.hasEventLabel(added[0]))

            let deletion = try await fixture.invalidateAndRequest()
            try await fixture.complete(deletion, with: [])
            #expect(fixture.hasText("No events"))
            try await fixture.expectContext(on: fixture.selectedDay, selectedWeek: fixture.selectedWeek)
            try await fixture.captureContext("selected-empty")
            #expect(!fixture.hasEventLabel(edited))
            #expect(fixture.store.selectedDate == fixture.selectedDay)
            #expect(fixture.store.displayedMonth == month)
            #expect(fixture.store.isPinned && fixture.panel.isPinned)
            #expect(fixture.activations.value == activations)
            #expect(fixture.permissionRequests.value == 0)
        }
    }

    @Test
    func deselectedChangeQueriesToday() async throws {
        try await withAgendaRefreshFixture(isolated: true) { fixture in
            try await fixture.mountWithEmptyAgenda()
            fixture.store.send(.dateTapped(fixture.selectedDay))
            try await fixture.complete(try await fixture.request(at: 1), with: [])
            fixture.store.send(.dateTapped(fixture.selectedDay))
            try await fixture.complete(try await fixture.request(at: 2), with: [])
            try #require(fixture.store.selectedDate == nil)
            let actions = fixture.actions.value
            let refresh = try await fixture.invalidateAndRequest()
            try await fixture.complete(refresh, with: [])
            #expect(refresh.date == Calendar.current.startOfDay(for: fixture.today))
            #expect(fixture.store.selectedDate == nil)
            #expect(fixture.actions.value == actions + ["refresh"])
            try await fixture.expectContext(on: fixture.today)
            // Month browsing must not relabel the queried day.
            fixture.store.send(.goToNextMonth)
            try await fixture.expectContext(on: fixture.today)
        }

        let publicToday = Date()
        try await withAgendaRefreshFixture(isolated: true, today: publicToday) { fixture in
            try await fixture.mount()
            try await fixture.expectContext(on: publicToday, isToday: true)
            try await fixture.complete(try await fixture.request(at: 0), with: [])
            try await fixture.expectContext(on: publicToday, isToday: true)
            try await fixture.captureContext("no-selection-today")
            try await fixture.captureContext("no-selection-today-cap", maximumHeight: 312)
            fixture.store.send(.goToToday)
            try await fixture.complete(try await fixture.request(at: 1), with: [])
            try await fixture.expectContext(
                on: publicToday, isToday: true,
                selectedWeek: Calendar.current.component(.weekOfYear, from: publicToday)
            )
            #expect(fixture.permissionRequests.value == 0)
        }
        try await withAgendaRefreshFixture(
            isolated: true, today: publicToday, requestingAccess: true
        ) { fixture in
            try await fixture.mount(expectsQuery: false)
            try await fixture.expectContext(on: publicToday, isToday: true)
            #expect(fixture.hasText("Requesting calendar access…"))
            #expect(!fixture.hasText("No events"))
            #expect(fixture.fetches.count.value == 0 && fixture.permissionRequests.value == 0)
        }
        try #require(Calendar.current.isDate(publicToday, inSameDayAs: Date()),
                     "Public Today observations crossed midnight; repeat in one day")
    }

    @Test
    func changePreservesSettingsAndAIDraftEditor() async throws {
        try await withAgendaRefreshFixture(isolated: true, showAI: true) { fixture in
            try await fixture.mountWithEmptyAgenda()
            fixture.aiModel.setEditorOpen(true)
            fixture.aiModel.setDraft("next Friday")
            try await fixture.settle()
            let settings = try await fixture.openSettings()
            let responder = try #require(settings.firstResponder)
            let calendarResponder = fixture.panel.firstResponder
            let actions = fixture.actions.value
            let activations = fixture.activations.value

            let refresh = try await fixture.invalidateAndRequest()
            try await fixture.complete(refresh, with: [])
            #expect(settings.isVisible && settings.isKeyWindow && NSApp.keyWindow === settings)
            #expect(fixture.settingsController.window === settings)
            #expect(fixture.settingsController.selection.section == .aiDateSearch)
            #expect(fixture.panel.isVisible && fixture.panel.isPinned && fixture.store.isPinned)
            #expect(fixture.aiModel.isEditorOpen)
            #expect(fixture.aiModel.draft == "next Friday")
            #expect(!fixture.aiModel.isProcessing && fixture.aiModel.currentRequestID == nil)
            #expect(settings.firstResponder === responder)
            #expect(fixture.panel.firstResponder === calendarResponder)
            #expect(fixture.actions.value == actions + ["refresh"])
            #expect(fixture.activations.value == activations)
        }
    }

    @Test
    func offMainQueuedChangeUsesCurrentSelectionOnMain() async throws {
        try await withAgendaRefreshFixture(isolated: true) { fixture in
            try await fixture.mountWithEmptyAgenda()
            let deliveries = fixture.deliveries.value
            let actions = fixture.actions.value
            try fixture.postFromBackgroundAndAcknowledge()
            // Main delivery is intentionally unpumped until selection changes.
            #expect(fixture.actions.value == actions)
            fixture.store.send(.dateTapped(fixture.selectedDay))
            try await fixture.drainDelivery(after: deliveries)
            let current = try await fixture.currentPendingRequest()
            try await fixture.complete(current, with: [])
            let requests = await fixture.fetches.snapshot()
            #expect(requests.dropFirst().allSatisfy {
                $0.date == Calendar.current.startOfDay(for: fixture.selectedDay)
            })
            #expect(fixture.actions.value == actions + ["selection", "refresh"])
            #expect(fixture.refreshDispatchWasMain.value == [true])
            #expect(fixture.backgroundProducerWasMain.value == [false])
        }
    }

    @Test
    func queuedChangeAfterHideDoesNotFetch() async throws {
        try await withAgendaRefreshFixture(isolated: true) { fixture in
            try await fixture.mount()
            let pending = try await fixture.request(at: 0)
            let deliveries = fixture.deliveries.value
            try fixture.postFromBackgroundAndAcknowledge()
            fixture.hide()
            let actionsAfterHide = fixture.actions.value
            try await fixture.drainDelivery(after: deliveries)
            try await fixture.expectCancellation(of: pending)
            #expect(fixture.fetches.count.value == 1)
            #expect(fixture.actions.value == actionsAfterHide)
            #expect(!fixture.actions.value.contains("refresh"))
            #expect(fixture.backgroundProducerWasMain.value == [false])
            await pending.complete(.success([fixture.event("Late hidden event", on: fixture.today)]))
            try await fixture.returned(pending)
            #expect(fixture.store.events.isEmpty && !fixture.store.isLoadingEvents)
        }
    }

    @Test(arguments: [false, true])
    func hiddenAndRemovedRootsIgnoreChanges(removeRoot: Bool) async throws {
        try await withAgendaRefreshFixture(isolated: true) { fixture in
            try await fixture.mountWithEmptyAgenda()
            if removeRoot { fixture.removeRoot() }
            else { fixture.hide() }
            try await fixture.settle()
            #expect(fixture.panel.isVisible == removeRoot)
            let actions = fixture.actions.value
            let queries = fixture.fetches.count.value
            let deliveries = fixture.deliveries.value
            fixture.postStoreChange()
            try await fixture.drainDelivery(after: deliveries)
            #expect(fixture.actions.value == actions)
            #expect(fixture.fetches.count.value == queries)
        }
    }

    @Test
    func showHideShowKeepsOneSubscription() async throws {
        try await withAgendaRefreshFixture(isolated: true) { fixture in
            try await fixture.mountWithEmptyAgenda()
            for _ in 0..<3 {
                fixture.hide()
                try await fixture.settle()
                let queries = fixture.fetches.count.value
                fixture.panel.prepareForReopen()
                fixture.panel.orderFront(nil)
                try await fixture.settle(until: {
                    fixture.panel.isVisible && fixture.fetches.count.value == queries + 1
                }, reason: "reused panel enters its prepared query")
                try await fixture.complete(try await fixture.request(at: queries), with: [])
            }
            let actions = fixture.actions.value
            let queries = fixture.fetches.count.value
            let refresh = try await fixture.invalidateAndRequest()
            try await fixture.complete(refresh, with: [])
            #expect(fixture.actions.value == actions + ["refresh"])
            #expect(fixture.fetches.count.value == queries + 1)
        }
    }

    @Test(arguments: [false, true])
    func burstAndLateQueriesKeepLatestResult(lateFailure: Bool) async throws {
        try await withAgendaRefreshFixture(isolated: true) { fixture in
            try await fixture.mountWithEmptyAgenda()
            let old = try await fixture.invalidateAndRequest()
            let actions = fixture.actions.value.filter { $0 == "refresh" }.count
            for _ in 0..<3 { fixture.postStoreChange() }
            try await fixture.settle(until: {
                fixture.actions.value.filter { $0 == "refresh" }.count == actions + 3
            }, reason: "all burst notifications dispatch")
            try await fixture.expectCancellation(of: old)
            let latest = try await fixture.currentPendingRequest()
            let currentEvent = fixture.event("Latest burst result", on: fixture.today)
            try await fixture.complete(latest, with: [currentEvent])
            for request in await fixture.fetches.snapshot()
                where request !== latest && request.returnCount.value == 0 {
                #expect(request.cancellationCount.value > 0)
                await request.complete(lateFailure ? .failure(.query) : .success([
                    fixture.event("Stale burst result", on: fixture.today)
                ]))
                try await fixture.returned(request)
            }
            #expect(fixture.store.events == [currentEvent])
            #expect(fixture.hasEventLabel(currentEvent))
            #expect(!fixture.store.isLoadingEvents && fixture.store.eventsError == nil)
            #expect(fixture.refreshDispatchWasMain.value.allSatisfy { $0 })
            try await fixture.expectContext(on: fixture.today)
        }
    }

    @Test(arguments: [false, true], [false, true])
    func dateChangeAndHideRejectLateInvalidationResult(hide: Bool, lateFailure: Bool) async throws {
        try await withAgendaRefreshFixture(isolated: true) { fixture in
            try await fixture.mountWithEmptyAgenda()
            let old = try await fixture.invalidateAndRequest()
            if hide { fixture.hide() }
            else {
                fixture.store.send(.dateTapped(fixture.selectedDay))
                let current = try await fixture.currentPendingRequest(excluding: old)
                try await fixture.complete(current, with: [
                    fixture.event("Current selected result", on: fixture.selectedDay)
                ])
            }
            try await fixture.expectCancellation(of: old)
            let events = fixture.store.events
            let selection = fixture.store.selectedDate
            let error = fixture.store.eventsError
            let loading = fixture.store.isLoadingEvents
            let stale = fixture.event("Stale invalidation result", on: fixture.today)
            await old.complete(lateFailure ? .failure(.query) : .success([
                stale
            ]))
            try await fixture.returned(old)
            #expect(fixture.store.events == events)
            #expect(fixture.store.selectedDate == selection)
            #expect(fixture.store.eventsError == error)
            #expect(fixture.store.isLoadingEvents == loading)
            #expect(!fixture.hasEventLabel(stale))
            if !hide {
                try await fixture.expectContext(on: fixture.selectedDay, selectedWeek: fixture.selectedWeek)
            }
        }
    }

    @Test(arguments: [
        EKAuthorizationStatus.notDetermined, .denied, .restricted, .writeOnly
    ])
    func permissionLossOnChangeClearsRowsWithoutAccess(status: EKAuthorizationStatus) async throws {
        try await withAgendaRefreshFixture(isolated: true) { fixture in
            let publicToday = Date()
            try await fixture.mount()
            let before = fixture.event("Previously permitted event", on: fixture.today)
            try await fixture.complete(try await fixture.request(at: 0), with: [before])
            try #require(fixture.hasEventLabel(before))
            fixture.authorization.setValue(status)
            var deliveries = fixture.deliveries.value
            fixture.postStoreChange()
            try await fixture.drainDelivery(after: deliveries)
            #expect(fixture.store.events.isEmpty && !fixture.store.isLoadingEvents)
            #expect(!fixture.hasEventLabel(before))
            #expect(fixture.fetches.count.value == 1 && fixture.permissionRequests.value == 0)
            try await fixture.expectContext(on: publicToday, isToday: true)
            #expect(!fixture.hasText("No events"))
            switch status {
            case .notDetermined:
                #expect(fixture.elements().contains {
                    $0.role == .button && $0.label == "Grant calendar access to show events"
                })
            case .restricted:
                #expect(fixture.hasText("Calendar access is restricted on this Mac."))
            case .writeOnly:
                #expect(fixture.hasText("Allow full calendar access to read events."))
            default:
                #expect(fixture.hasText("Calendar access is off."))
            }

            // Separately exercise loss while a cancellation-ignoring query is running.
            fixture.authorization.setValue(.fullAccess)
            let restored = try await fixture.invalidateAndRequest()
            try await fixture.complete(restored, with: [before])
            let old = try await fixture.invalidateAndRequest()
            fixture.authorization.setValue(status)
            deliveries = fixture.deliveries.value
            fixture.postStoreChange()
            try await fixture.drainDelivery(after: deliveries)
            try await fixture.expectCancellation(of: old)
            #expect(fixture.store.calendarAuthorizationStatus == status)
            #expect(fixture.store.events.isEmpty && !fixture.store.isLoadingEvents)
            #expect(fixture.store.eventsRequestID == nil)
            #expect(fixture.fetches.count.value == 3)
            #expect(fixture.permissionRequests.value == 0)
            await old.complete(.success([before]))
            try await fixture.returned(old)
            #expect(fixture.store.events.isEmpty && fixture.store.eventsError == nil)
            #expect(!fixture.hasEventLabel(before))
            #expect(fixture.fetches.count.value == 3 && fixture.permissionRequests.value == 0)
            try await fixture.expectContext(on: publicToday, isToday: true)
            fixture.store.send(.dateTapped(fixture.selectedDay))
            try await fixture.expectContext(on: fixture.selectedDay, selectedWeek: fixture.selectedWeek)
            #expect(!fixture.hasText("No events"))
            #expect(fixture.fetches.count.value == 3 && fixture.permissionRequests.value == 0)
            try #require(Calendar.current.isDate(publicToday, inSameDayAs: Date()),
                         "Permission fallback observations crossed midnight")
        }
    }

    @Test(arguments: [false, true])
    func changeFailureRecoversThroughRetryOrLaterSignal(useRetry: Bool) async throws {
        try await withAgendaRefreshFixture(isolated: true) { fixture in
            try await fixture.mountWithEmptyAgenda()
            fixture.store.send(.dateTapped(fixture.selectedDay))
            try await fixture.complete(try await fixture.request(at: 1), with: [])
            let failed = try await fixture.invalidateAndRequest()
            try await fixture.expectContext(on: fixture.selectedDay, selectedWeek: fixture.selectedWeek)
            await failed.complete(.failure(.query))
            try await fixture.returned(failed)
            try await fixture.settle(until: {
                fixture.store.eventsError != nil && !fixture.store.isLoadingEvents
            }, reason: "query failure renders existing recovery control")
            try await fixture.expectContext(on: fixture.selectedDay, selectedWeek: fixture.selectedWeek)
            let rawError = try #require(fixture.store.eventsError)
            #expect(fixture.hasText("Couldn’t load events."))
            #expect(!fixture.hasText("No events"))
            #expect(fixture.elements().allSatisfy {
                !($0.label?.contains(rawError) ?? false)
                    && !(($0.value as? String)?.contains(rawError) ?? false)
            }, "Query failure keeps its payload in state without exposing it in the agenda")
            if !useRetry { try await fixture.captureContext("selected-error") }
            let retry = try #require(fixture.elements().first {
                $0.role == .button && $0.label == "Retry loading calendar events"
            }, "\(fixture.treeDescription)")
            let queries = fixture.fetches.count.value
            if useRetry { try #require(retry.press()) }
            else { fixture.postStoreChange() }
            try await fixture.settle(until: { fixture.fetches.count.value == queries + 1 },
                                     reason: "real recovery route enters query")
            try await fixture.expectContext(on: fixture.selectedDay, selectedWeek: fixture.selectedWeek)
            let recovered = fixture.event("Recovered event", on: fixture.selectedDay)
            try await fixture.complete(try await fixture.request(at: queries), with: [recovered])
            #expect(fixture.hasEventLabel(recovered))
            #expect(fixture.store.eventsError == nil && !fixture.store.isLoadingEvents)
            #expect(fixture.actions.value.last == (useRetry ? "retry" : "refresh"))
            #expect(fixture.permissionRequests.value == 0)
            try await fixture.expectContext(on: fixture.selectedDay, selectedWeek: fixture.selectedWeek)
        }
    }

    @Test(arguments: [false, true])
    func nilAndUnrelatedObjectChangesInvalidate(unrelatedObject: Bool) async throws {
        try await withAgendaRefreshFixture(isolated: true) { fixture in
            try await fixture.mountWithEmptyAgenda()
            let queries = fixture.fetches.count.value
            fixture.postStoreChange(object: unrelatedObject ? NSObject() : nil)
            try await fixture.settle(until: { fixture.fetches.count.value == queries + 1 },
                                     reason: "public invalidation does not filter object identity")
            try await fixture.complete(try await fixture.request(at: queries), with: [])
            #expect(fixture.actions.value == ["appear", "refresh"])
        }
    }
}

private enum AgendaFixtureFailure: Error, Sendable {
    case query
    case timeout(String)
}

/// The fake client may ignore cancellation until released, like an in-flight
/// synchronous EventKit query. Its receipts describe client work, not TCA task joins.
private final class AgendaFetchRequest: Sendable {
    let id = UUID()
    let date: Date
    let entered = AIDateIntegrationSignal<Void>("agenda client entered")
    let returned = AIDateIntegrationSignal<Void>("agenda client returned")
    let cancellationCount = LockIsolated(0)
    let returnCount = LockIsolated(0)
    private let gate = AgendaFetchGate()

    init(date: Date) { self.date = date }

    func run() async throws -> [CalendarEvent] {
        defer {
            returnCount.withValue { $0 += 1 }
            returned.resolve(.success(()))
        }
        return try await withTaskCancellationHandler {
            entered.resolve(.success(()))
            return try await gate.wait().get()
        } onCancel: {
            self.cancellationCount.withValue { $0 += 1 }
        }
    }

    func complete(_ result: Result<[CalendarEvent], AgendaFixtureFailure>) async {
        await gate.open(result)
    }
}

private actor AgendaFetchGate {
    private var result: Result<[CalendarEvent], AgendaFixtureFailure>?
    private var waiter: CheckedContinuation<Result<[CalendarEvent], AgendaFixtureFailure>, Never>?

    func wait() async -> Result<[CalendarEvent], AgendaFixtureFailure> {
        if let result { return result }
        return await withCheckedContinuation { waiter = $0 }
    }

    func open(_ result: Result<[CalendarEvent], AgendaFixtureFailure>) {
        guard self.result == nil else { return }
        self.result = result
        waiter?.resume(returning: result)
        waiter = nil
    }
}

private actor AgendaFetchProbe {
    nonisolated let count = LockIsolated(0)
    private var entered: [AgendaFetchRequest] = []
    private var discovery: [Int: AIDateIntegrationSignal<AgendaFetchRequest>] = [:]
    private var draining = false

    func fetch(_ date: Date) async throws -> [CalendarEvent] {
        let request = AgendaFetchRequest(date: date)
        let index = entered.count
        entered.append(request)
        let enteredCount = entered.count
        count.setValue(enteredCount)
        discovery[index]?.resolve(.success(request))
        if draining { await request.complete(.failure(.query)) }
        return try await request.run()
    }

    func request(at index: Int) async throws -> AgendaFetchRequest {
        if index < entered.count { return entered[index] }
        let signal = discovery[index] ?? AIDateIntegrationSignal<AgendaFetchRequest>(
            "agenda request \(index) discovered"
        )
        discovery[index] = signal
        return try await signal.wait()
    }

    func beginDrain() async {
        draining = true
        for request in entered { await request.complete(.failure(.query)) }
    }

    func snapshot() -> [AgendaFetchRequest] { entered }

    func drainReceipts() async throws {
        var failure: (any Error)?
        for request in entered {
            do { try await request.returned.wait() }
            catch { if failure == nil { failure = error } }
            #expect(request.returnCount.value == 1)
            await request.entered.drainWatchdogs()
            await request.returned.drainWatchdogs()
        }
        for signal in discovery.values { await signal.drainWatchdogs() }
        if let failure { throw failure }
    }
}

@MainActor
private final class AgendaRefreshFixture {
    let store: StoreOf<CalendarFeature>
    let panel: CalendarPanel
    let hosting: NSHostingView<AnyView>
    let center: NotificationCenter
    let authorization = LockIsolated(EKAuthorizationStatus.fullAccess)
    let permissionRequests = LockIsolated(0)
    let fetches = AgendaFetchProbe()
    let actions = LockIsolated<[String]>([])
    let refreshDispatchWasMain = LockIsolated<[Bool]>([])
    let activations = LockIsolated(0)
    let deliveries = LockIsolated(0)
    let backgroundProducerWasMain = LockIsolated<[Bool]>([])
    let aiModel: AIDateQueryModel
    let today: Date
    let selectedDay: Date
    let selectedWeek: Int
    let settingsController: SettingsWindowController
    private let hotkeyFixture = HotkeyFixture()
    private var activationObserver: NSObjectProtocol?
    private var deliveryObserver: AnyCancellable?
    private var backgroundPosts: [AIDateIntegrationSignal<Void>] = []

    init(
        center: NotificationCenter = .default, showAI: Bool = false,
        today publicToday: Date? = nil, requestingAccess: Bool = false
    ) throws {
        try #require(ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil,
                     "Real agenda fixture is restricted to the owned test host")
        self.center = center
        today = try publicToday ?? #require(Calendar.current.date(from: DateComponents(
            year: 2030, month: 11, day: 15, hour: 12
        )))
        selectedDay = try #require(Calendar.current.date(from: DateComponents(
            year: 2030, month: 11, day: 20
        )))
        selectedWeek = Calendar.current.component(.weekOfYear, from: selectedDay)
        let fixedToday = today
        let authorization = authorization
        let permissionRequests = permissionRequests
        let fetches = fetches
        let actions = actions
        let dispatch = refreshDispatchWasMain
        let requestSequence = LockIsolated(0)
        var state = CalendarFeature.State(displayedMonth: today)
        state.isPinned = true
        if requestingAccess {
            // Presentation-only initial state; no real or injected permission request.
            authorization.setValue(.notDetermined)
            state.isRequestingCalendarAccess = true
        }
        store = Store(initialState: state) {
            Reduce<CalendarFeature.State, CalendarFeature.Action> { _, action in
                let name: String?
                switch action {
                case .onAppear: name = "appear"
                case .onDisappear: name = "disappear"
                case .dateTapped: name = "selection"
                case .goToToday: name = "today"
                case .retryEvents: name = "retry"
                case .prepareForReopen: name = "reopen"
                case .refreshCalendarAuthorization:
                    name = "refresh"
                    dispatch.withValue { $0.append(Thread.isMainThread) }
                default: name = nil
                }
                if let name { actions.withValue { $0.append(name) } }
                return .none
            }
            CalendarFeature()
        } withDependencies: {
            $0.date = .constant(fixedToday)
            $0.uuid = .init {
                requestSequence.withValue {
                    $0 += 1
                    // Each bounded scenario uses a positive sequence below 10^12;
                    // twelve padded decimal digits are valid hex in this fixed UUID.
                    return UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", $0))!
                }
            }
            $0.calendarClient = .liveValue
            $0.calendarClient.menuBarDateString = { _, _ in
                Issue.record("Agenda fixture must not construct a status item")
                return ""
            }
            $0.preferencesClient = .testValue
            $0.preferencesClient.loadStartOfWeekday = { 1 }
            $0.preferencesClient.loadWorkdays = { [2, 3, 4, 5, 6] }
            $0.preferencesClient.loadShowAISearch = { showAI }
            $0.eventKitClient = EventKitClient(
                requestAccess: {
                    permissionRequests.withValue { $0 += 1 }
                    Issue.record("Agenda fixture must not request calendar access")
                    return false
                },
                fetchEvents: { try await fetches.fetch($0) },
                authorizationStatus: { authorization.value }
            )
        }
        let preferences = Store(initialState: PreferencesFeature.State()) {
            PreferencesFeature()
        } withDependencies: {
            $0.preferencesClient = .testValue
            $0.preferencesClient.loadStartOfWeekday = { 1 }
            $0.preferencesClient.loadWorkdays = { [2, 3, 4, 5, 6] }
            $0.preferencesClient.loadDisplayOptions = { .default }
            $0.preferencesClient.loadShowAISearch = { showAI }
            $0.preferencesClient.loadAIProvider = { .auto }
            $0.launchAtLoginClient = .testValue
            $0.launchAtLoginClient.status = { .notRegistered }
        }
        let store = store
        aiModel = AIDateQueryModel(
            client: AIDateQueryClient(
                resolveProvider: { _ in
                    Issue.record("Agenda invalidation must not submit AI")
                    return .proxy
                },
                parseDate: { _, _ in
                    Issue.record("Agenda fixture must not query live AI")
                    return nil
                }
            ), enabled: showAI, preference: .auto,
            onDate: { store.send(.aiDateResult($0)) }
        )
        panel = CalendarPanel(
            contentRect: NSRect(x: -1000, y: -1000, width: 316, height: 550),
            caretOffset: 150, calendarStore: store, content: { _ in AnyView(EmptyView()) }
        )
        panel.isReleasedWhenClosed = false
        panel.isPinned = true
        let hotkeyModel = HotkeyPreferencesModel(
            hotkey: hotkeyFixture.hotkey, defaults: hotkeyFixture.defaults
        ) { Issue.record("Agenda fixture must not operate a global hotkey") }
        let panel = panel
        settingsController = SettingsWindowController(
            store: preferences, hotkeyPreferences: hotkeyModel, notificationCenter: center,
            onAISettingsChange: { [weak panel] enabled, preference in
                panel?.aiSettingsDidChange?(enabled, preference)
            }
        )
        let root: CalendarPopoverView
        if center === NotificationCenter.default {
            // The original RED→GREEN keeps the unchanged production default route.
            root = CalendarPopoverView(
                store: store, panel: panel, layout: panel.layoutState,
                editorPresentation: { _ in }, aiQueryModel: aiModel,
                loadAISettings: { (showAI, .auto) }
            )
        } else {
            root = CalendarPopoverView(
                store: store, panel: panel, layout: panel.layoutState,
                editorPresentation: { _ in }, aiQueryModel: aiModel,
                loadAISettings: { (showAI, .auto) },
                eventChangeNotificationCenter: center
            )
        }
        hosting = NSHostingView(rootView: AnyView(
            root
            .environment(\.accessibilityEnabled, true)
        ))
        panel.contentView = hosting
        let bounds = NSScreen.screens.reduce(NSRect.zero) { $0.union($1.frame) }
        panel.setFrameOrigin(NSPoint(x: bounds.minX - 1000, y: bounds.minY - 1000))
        panel.layoutState.updatePlacement(maximumHeight: 550, caretXOffset: 150)
        let activations = activations
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: nil
        ) { _ in activations.withValue { $0 += 1 } }
        let deliveries = deliveries
        deliveryObserver = center.publisher(for: .EKEventStoreChanged)
            .map { @Sendable _ in () }
            .receive(on: RunLoop.main)
            .sink { _ in deliveries.withValue { $0 += 1 } }
    }

    func mount(expectsQuery: Bool = true) async throws {
        panel.orderFront(nil)
        try await settle(until: {
            self.panel.isVisible && (!expectsQuery || self.fetches.count.value > 0)
        },
                         reason: "real root mounts and enters its initial synthetic query")
        try materializeAccessibilityTree()
    }

    func mountWithEmptyAgenda() async throws {
        try await mount()
        try await complete(try await request(at: 0), with: [])
    }

    func openSettings() async throws -> NSWindow {
        panel.prepareForSettingsPresentation()
        settingsController.show(visibleFrame: NSRect(
            x: panel.frame.minX - 800, y: panel.frame.minY,
            width: 760, height: 650
        ))
        settingsController.select(.aiDateSearch)
        let owner = try #require(settingsController.window)
        try await settle(until: {
            owner.isVisible && owner.isKeyWindow && NSApp.keyWindow === owner && self.panel.isVisible
        }, reason: "owned Settings becomes key while the pinned calendar stays visible")
        return owner
    }

    func request(at index: Int) async throws -> AgendaFetchRequest {
        let request = try await fetches.request(at: index)
        try await request.entered.wait()
        return request
    }

    func complete(_ request: AgendaFetchRequest, with events: [CalendarEvent]) async throws {
        await request.complete(.success(events))
        try await request.returned.wait()
        #expect(request.returnCount.value == 1)
        try await settle(until: { !self.store.isLoadingEvents && self.store.events == events },
                         reason: "current synthetic result renders")
        try materializeAccessibilityTree()
        try await settle()
    }

    func postStoreChange(object: Any? = nil) {
        center.post(name: .EKEventStoreChanged, object: object)
    }

    func invalidateAndRequest() async throws -> AgendaFetchRequest {
        let queries = fetches.count.value
        postStoreChange()
        try await settle(until: { self.fetches.count.value == queries + 1 },
                         reason: "visible invalidation enters a new query")
        return try await request(at: queries)
    }

    func currentPendingRequest(excluding excluded: AgendaFetchRequest? = nil) async throws -> AgendaFetchRequest {
        for _ in 0..<8 { await layoutPass() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while true {
            let requests = await fetches.snapshot()
            let current = requests.filter {
                $0 !== excluded && $0.returnCount.value == 0 && $0.cancellationCount.value == 0
            }
            if current.count == 1, let request = current.first {
                try await request.entered.wait()
                return request
            }
            guard ContinuousClock.now < deadline else {
                throw AgendaFixtureFailure.timeout("Expected exactly one current entered query")
            }
            await layoutPass()
        }
    }

    func expectCancellation(of request: AgendaFetchRequest) async throws {
        try await settle(until: { request.cancellationCount.value > 0 },
                         reason: "actual injected client receives cancellation")
    }

    func returned(_ request: AgendaFetchRequest) async throws {
        try await request.returned.wait()
        #expect(request.returnCount.value == 1)
        try await settle()
    }

    /// Bounded acknowledgment blocks main delivery until the caller changes state.
    /// The producer posts only a payload-free signal and never calls the main queue.
    func postFromBackgroundAndAcknowledge() throws {
        let center = center
        let producer = backgroundProducerWasMain
        let acknowledgment = DispatchSemaphore(value: 0)
        let completedPost = AIDateIntegrationSignal<Void>("background EventKit post completed")
        backgroundPosts.append(completedPost)
        DispatchQueue(label: "GlimpseTests.agenda-producer").async {
            producer.withValue { $0.append(Thread.isMainThread) }
            center.post(name: .EKEventStoreChanged, object: nil)
            completedPost.resolve(.success(()))
            acknowledgment.signal()
        }
        try #require(acknowledgment.wait(timeout: .now() + 2) == .success,
                     "Background notification post did not acknowledge completion")
    }

    func drainDelivery(after baseline: Int) async throws {
        try await settle(until: { self.deliveries.value > baseline },
                         reason: "owned main-run-loop subscriber receives posted invalidation")
        // A receipt plus bounded rendering opportunities lets root delivery finish.
        // It does not claim a hidden or detached root's handler was invoked.
        try await settle()
    }

    func event(_ title: String, on date: Date, hour: Int = 10) -> CalendarEvent {
        let start = Calendar.current.startOfDay(for: date).addingTimeInterval(Double(hour) * 3600)
        return CalendarEvent(id: title, title: title, startDate: start,
                             endDate: start.addingTimeInterval(3600), isAllDay: false)
    }

    func hasEventLabel(_ event: CalendarEvent) -> Bool {
        let text = "\(event.title), \(event.timeString)"
        return hasText(text)
    }

    func hasText(_ text: String) -> Bool {
        elements().contains { $0.label == text || ($0.value as? String) == text }
    }

    /// Independently chosen fixture dates catch missing, duplicate or stale context.
    /// Formatting uses Foundation, never a production view helper or displayed month.
    func expectContext(
        on date: Date, isToday: Bool = false, selectedWeek: Int? = nil
    ) async throws {
        try await settle()
        try materializeAccessibilityTree()
        let headings = elements().filter {
            $0.label?.hasPrefix("Calendar events for ") == true
        }
        #expect(headings.count == 1, "Expected one agenda context; \(treeDescription)")
        guard let heading = headings.first else { return }
        var expected = "Calendar events for \(date.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))"
        if isToday { expected += ", today" }
        if let selectedWeek { expected += ", selected date, Week \(selectedWeek)" }
        #expect(heading.label == expected)
        #expect(heading.role?.rawValue == "AXHeading")
        #expect(heading.frame.width > 0 && heading.frame.width <= hosting.bounds.width)
    }

    /// Opt-in images of the actual owned root; no app-wide appearance mutation.
    func captureContext(_ name: String, maximumHeight: CGFloat? = nil) async throws {
        guard let path = ProcessInfo.processInfo.environment["GLIMPSE_AGENDA_ARTIFACT_DIR"] else {
            return
        }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let originalAppearance = panel.appearance
        let originalMaximumHeight = panel.layoutState.maximumHeight
        if let maximumHeight {
            panel.layoutState.updatePlacement(maximumHeight: maximumHeight, caretXOffset: 150)
        }
        defer {
            panel.appearance = originalAppearance
            panel.layoutState.updatePlacement(
                maximumHeight: originalMaximumHeight, caretXOffset: 150
            )
        }
        for (theme, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            panel.appearance = try #require(NSAppearance(named: appearance))
            try await settle()
            #expect(hosting.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == appearance)
            let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            let data = try #require(bitmap.representation(using: .png, properties: [:]))
            let output = directory.appendingPathComponent("\(name)-\(theme).png")
            try #require(!FileManager.default.fileExists(atPath: output.path),
                         "Each context image has one owned observation")
            try data.write(to: output)
            print("GLIMPSE_AGENDA_CONTEXT bitmap=\(output.path)")
        }
    }

    var treeDescription: String {
        elements().map {
            "\($0.role?.rawValue ?? "?") label=\($0.label ?? "") value=\(String(describing: $0.value))"
        }.joined(separator: "\n")
    }

    private func materializeAccessibilityTree() throws {
        let application = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        var windows: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &windows)
        try #require(result == .success, "Own-process agenda AX read returned \(result.rawValue)")
    }

    func elements() -> [AccessibilityTestNode] {
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

    func settle(until predicate: @MainActor () -> Bool = { true },
                reason: String = "agenda layout") async throws {
        for _ in 0..<8 { await layoutPass() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !predicate() {
            guard ContinuousClock.now < deadline else {
                throw AgendaFixtureFailure.timeout(
                    "\(reason); queries=\(fetches.count.value), actions=\(actions.value), activations=\(activations.value), visible=\(panel.isVisible)"
                )
            }
            await layoutPass()
        }
    }

    private func layoutPass() async {
        _ = hosting.fittingSize
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        pumpRunLoop()
        await Task.yield()
    }

    private func pumpRunLoop() {
        CFRunLoopRunInMode(.defaultMode, 0.01, true)
    }

    func hide() { panel.orderOut(nil) }
    func removeRoot() { hosting.rootView = AnyView(EmptyView()) }

    func drain() async throws {
        // This task does not inherit cancellation of the scenario that owns it.
        let cleanup = Task { @MainActor in
            defer { self.close() }
            self.hide()
            self.removeRoot()
            await self.fetches.beginDrain()
            for _ in 0..<8 { await self.layoutPass() }
            var failure: (any Error)?
            do { try await self.fetches.drainReceipts() }
            catch { failure = error }
            for post in self.backgroundPosts {
                do { try await post.wait() }
                catch { if failure == nil { failure = error } }
                await post.drainWatchdogs()
            }
            if let failure { throw failure }
        }
        try await cleanup.value
    }

    private func close() {
        deliveryObserver?.cancel()
        deliveryObserver = nil
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        settingsController.cancelRecording()
        settingsController.window?.contentView = nil
        settingsController.window?.close()
        panel.makeFirstResponder(nil)
        panel.contentView = nil
        panel.close()
        hotkeyFixture.cleanupDefaults()
    }
}

@MainActor
private func withAgendaRefreshFixture(
    isolated: Bool = false, showAI: Bool = false,
    today: Date? = nil, requestingAccess: Bool = false,
    _ body: @MainActor (AgendaRefreshFixture) async throws -> Void
) async throws {
    let fixture = try AgendaRefreshFixture(
        center: isolated ? NotificationCenter() : .default, showAI: showAI,
        today: today, requestingAccess: requestingAccess
    )
    do { try await body(fixture) }
    catch {
        do { try await fixture.drain() }
        catch { Issue.record("Agenda fixture cleanup failed: \(error)") }
        throw error
    }
    try await fixture.drain()
}
