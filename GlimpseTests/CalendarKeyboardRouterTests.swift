import Foundation
import Testing

@testable import Glimpse

struct CalendarKeyboardRouterTests {
    @Test(arguments: [
        (CalendarKeyboardKey.left, -1), (.right, 1), (.up, -7), (.down, 7)
    ])
    func gridArrowsMoveLogicalAnchorOnly(key: CalendarKeyboardKey, delta: Int) {
        #expect(CalendarKeyboardRouter.local(
            key, phase: .down, owner: .grid, context: .eligible
        ) == .move(delta))
        #expect(CalendarKeyboardRouter.local(
            key, phase: .repeatPress, owner: .grid, context: .eligible
        ) == .move(delta))
    }

    @Test(arguments: [CalendarKeyboardKey.returnKey, .keypadEnter, .space])
    func gridActivationOccursOnceAndRepeatsAreConsumed(key: CalendarKeyboardKey) {
        #expect(CalendarKeyboardRouter.local(
            key, phase: .down, owner: .grid, context: .eligible
        ) == .activate)
        #expect(CalendarKeyboardRouter.local(
            key, phase: .repeatPress, owner: .grid, context: .eligible
        ) == .consume)
        #expect(CalendarKeyboardRouter.local(
            key, phase: .up, owner: .grid, context: .eligible
        ) == .yield)
    }

    @Test(arguments: [
        CalendarKeyboardOwner.previousMonth, .today, .nextMonth, .searchPrompt, .searchDismiss
    ])
    func fixedControlReturnAndSpaceActivateOnceWithRepeatConsumed(owner: CalendarKeyboardOwner) {
        #expect(CalendarKeyboardRouter.local(
            .returnKey, phase: .down, owner: owner, context: .eligible
        ) == .activate)
        #expect(CalendarKeyboardRouter.local(
            .keypadEnter, phase: .repeatPress, owner: owner, context: .eligible
        ) == .consume)
        #expect(CalendarKeyboardRouter.local(
            .space, phase: .down, owner: owner, context: .eligible
        ) == .activate)
        #expect(CalendarKeyboardRouter.local(
            .space, phase: .repeatPress, owner: owner, context: .eligible
        ) == .consume)
        #expect(CalendarKeyboardRouter.local(
            .space, phase: .up, owner: owner, context: .eligible
        ) == .yield)
        for key in [CalendarKeyboardKey.tab, .left, .right, .up, .down, .other] {
            #expect(CalendarKeyboardRouter.local(
                key, phase: .down, owner: owner, context: .eligible
            ) == .yield)
        }
    }

    @Test
    func disabledFixedControlsCannotActivate() {
        let activationKeys: [CalendarKeyboardKey] = [.returnKey, .keypadEnter, .space]
        for owner in [CalendarKeyboardOwner.previousMonth, .today, .nextMonth, .searchPrompt, .searchDismiss] {
            for key in activationKeys {
                for phase in [CalendarKeyboardPhase.down, .repeatPress] {
                    #expect(CalendarKeyboardRouter.local(
                        key, phase: phase, owner: owner, context: .eligible, isEnabled: false
                    ) == .consume)
                }
                #expect(CalendarKeyboardRouter.local(
                    key, phase: .up, owner: owner, context: .eligible, isEnabled: false
                ) == .yield)
            }
            for key in [CalendarKeyboardKey.tab, .left, .right, .up, .down, .other] {
                for phase in [CalendarKeyboardPhase.down, .repeatPress] {
                    #expect(CalendarKeyboardRouter.local(
                        key, phase: phase, owner: owner, context: .eligible, isEnabled: false
                    ) == .yield)
                }
            }
        }
        for context in [
            CalendarKeyboardContext(visible: false), CalendarKeyboardContext(key: false),
            CalendarKeyboardContext(eventForPanel: false), CalendarKeyboardContext(recording: true),
            CalendarKeyboardContext(preferences: true), CalendarKeyboardContext(modified: true),
            CalendarKeyboardContext(editingText: true)
        ] {
            for key in activationKeys {
                for phase in [CalendarKeyboardPhase.down, .repeatPress] {
                    #expect(CalendarKeyboardRouter.local(
                        key, phase: phase, owner: .today, context: context, isEnabled: false
                    ) == .yield)
                }
            }
        }
        for owner in [CalendarKeyboardOwner.editor, .grid] {
            for key in [CalendarKeyboardKey.returnKey, .keypadEnter, .space, .tab, .left, .right, .up, .down, .other] {
                for phase in [CalendarKeyboardPhase.down, .repeatPress, .up] {
                    #expect(CalendarKeyboardRouter.local(
                        key, phase: phase, owner: owner, context: .eligible, isEnabled: false
                    ) == .yield)
                }
            }
        }
    }

    @Test
    func editorReturnIsExclusivelyNativeSubmit() {
        for phase in [CalendarKeyboardPhase.down, .repeatPress, .up] {
            #expect(CalendarKeyboardRouter.local(
                .space, phase: phase, owner: .editor, context: .eligible
            ) == .yield)
        }
        for ownership in [CalendarKeyboardBrowseOwnership.windowDefault, .ambiguous, .designated(.editor)] {
            #expect(CalendarKeyboardRouter.browse(
                .space, phase: .down, ownership: ownership, context: .eligible
            ) == .yield)
        }
        #expect(CalendarKeyboardRouter.local(
            .returnKey, phase: .down, owner: .editor, context: .eligible
        ) == .yield)
        #expect(CalendarKeyboardRouter.browse(
            .returnKey, phase: .down, ownership: .designated(.editor), context: .eligible
        ) == .yield)
    }

    @Test(arguments: [
        CalendarKeyboardContext(visible: false),
        CalendarKeyboardContext(key: false),
        CalendarKeyboardContext(eventForPanel: false),
        CalendarKeyboardContext(recording: true),
        CalendarKeyboardContext(preferences: true),
        CalendarKeyboardContext(modified: true),
        CalendarKeyboardContext(editingText: true)
    ])
    func ineligibleInputsCannotMoveActivateOrBrowse(context: CalendarKeyboardContext) {
        for phase in [CalendarKeyboardPhase.down, .repeatPress] {
            #expect(CalendarKeyboardRouter.local(
                .space, phase: phase, owner: .nextMonth, context: context
            ) == .yield)
        }
        #expect(CalendarKeyboardRouter.local(
            .right, phase: .down, owner: .grid, context: context
        ) == .yield)
        #expect(CalendarKeyboardRouter.local(
            .returnKey, phase: .down, owner: .nextMonth, context: context
        ) == .yield)
        #expect(CalendarKeyboardRouter.browse(
            .returnKey, phase: .down, ownership: .windowDefault, context: context
        ) == .yield)
    }

    @Test
    func tabAlwaysPassesThroughEveryOwner() {
        for owner in CalendarKeyboardOwner.allCases {
            #expect(CalendarKeyboardRouter.local(
                .tab, phase: .down, owner: owner, context: .eligible
            ) == .yield)
        }
        #expect(CalendarKeyboardRouter.browse(
            .tab, phase: .down, ownership: .windowDefault, context: .eligible
        ) == .yield)
    }

    @Test
    func requestedGridCannotOverridePublishedHeaderAndOpenDraftCannotOverrideGrid() {
        // FocusState requests/AI row visibility are intentionally not routing inputs.
        #expect(CalendarKeyboardRouter.browse(
            .returnKey, phase: .down, ownership: .designated(.nextMonth), context: .eligible
        ) == .yield)
        #expect(CalendarKeyboardRouter.local(
            .returnKey, phase: .down, owner: .nextMonth, context: .eligible
        ) == .activate)
        #expect(CalendarKeyboardRouter.local(
            .returnKey, phase: .down, owner: .grid, context: .eligible
        ) == .activate)
    }

    @Test(arguments: [
        (CalendarKeyboardKey.left, CalendarBrowseIntent.previousMonth),
        (.right, .nextMonth), (.up, .previousYear), (.down, .nextYear),
        (.returnKey, .today), (.keypadEnter, .today)
    ])
    func positiveOwnerlessBrowseRetainsExistingIntents(
        key: CalendarKeyboardKey, intent: CalendarBrowseIntent
    ) {
        #expect(CalendarKeyboardRouter.browse(
            key, phase: .down, ownership: .windowDefault, context: .eligible
        ) == .browse(intent))
        #expect(CalendarKeyboardRouter.browse(
            key, phase: .down, ownership: .ambiguous, context: .eligible
        ) == .yield)
    }

    @Test
    func cachedNilWithUnknownResponderCannotAuthorizeBrowse() {
        #expect(CalendarKeyboardRouter.ownership(
            published: nil, observed: true, responderIsWindowDefault: false,
            snapshotMatchesResponder: true
        ) == .ambiguous)
        #expect(CalendarKeyboardRouter.ownership(
            published: nil, observed: true, responderIsWindowDefault: true,
            snapshotMatchesResponder: false
        ) == .ambiguous)
        #expect(CalendarKeyboardRouter.ownership(
            published: nil, observed: false, responderIsWindowDefault: true,
            snapshotMatchesResponder: true
        ) == .ambiguous)
        #expect(CalendarKeyboardRouter.ownership(
            published: nil, observed: true, responderIsWindowDefault: true,
            snapshotMatchesResponder: true
        ) == .windowDefault)
    }

    @Test
    func nativeCodesPreserveKeypadAndTabNormalization() {
        #expect(CalendarKeyboardKey(nativeCode: 76) == .keypadEnter)
        #expect(CalendarKeyboardKey(nativeCode: 48) == .tab)
        #expect(CalendarKeyboardKey(nativeCode: 124) == .right)
        #expect(CalendarKeyboardKey(nativeCode: 0) == .other)
    }

    @Test
    func anchorMovesAndClampsWithoutSelectionState() throws {
        let days = try dates()
        let calendar = Calendar.current
        #expect(CalendarKeyboardRouter.move(days[19], by: -1, days: days, calendar: calendar) == days[18])
        #expect(CalendarKeyboardRouter.move(days[19], by: 1, days: days, calendar: calendar) == days[20])
        #expect(CalendarKeyboardRouter.move(days[19], by: -7, days: days, calendar: calendar) == days[12])
        #expect(CalendarKeyboardRouter.move(days[19], by: 7, days: days, calendar: calendar) == days[26])
        #expect(CalendarKeyboardRouter.move(days[0], by: -1, days: days, calendar: calendar) == days[0])
        #expect(CalendarKeyboardRouter.move(days[41], by: 7, days: days, calendar: calendar) == days[41])
        #expect(CalendarKeyboardRouter.move(nil, by: 1, days: days, calendar: calendar) == nil)
    }

    @Test
    func anchorReconcilesCurrentSelectedTodayThenCurrentMonth() throws {
        let days = try dates()
        let calendar = Calendar.current
        let outside = try #require(calendar.date(from: DateComponents(year: 2029, month: 1, day: 1)))
        func reconcile(_ current: Date?, _ selected: Date?, _ today: Date) -> Date? {
            CalendarKeyboardRouter.reconcile(
                current, days: days, selected: selected, today: today,
                displayedMonth: days[19], calendar: calendar
            )
        }
        #expect(reconcile(days[19], days[24], days[20]) == days[19])
        #expect(reconcile(outside, days[24], days[20]) == days[24])
        #expect(reconcile(outside, nil, days[20]) == days[20])
        #expect(reconcile(outside, nil, outside) == days[5]) // November1.
        #expect(CalendarKeyboardRouter.reconcile(
            nil, days: [], selected: nil, today: outside,
            displayedMonth: outside, calendar: calendar
        ) == nil)
    }

    private func dates() throws -> [Date] {
        let start = try #require(Calendar.current.date(from: DateComponents(year: 2030, month: 10, day: 27)))
        return try (0..<42).map {
            try #require(Calendar.current.date(byAdding: .day, value: $0, to: start))
        }
    }
}
