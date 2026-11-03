"""Synthetic public metadata; no executed native or private calendar inputs."""

from ai_date_search_xcresult_fixture import cases, fixture_directory

SUITE = "CalendarAgendaRefreshTests"
# Hand-checked seven owned context observations, each in light and dark.
AGENDA_PNGS = (
    'selected-loading-light.png',
    'selected-loading-dark.png',
    'selected-loading-cap-light.png',
    'selected-loading-cap-dark.png',
    'selected-result-light.png',
    'selected-result-dark.png',
    'selected-empty-light.png',
    'selected-empty-dark.png',
    'no-selection-today-light.png',
    'no-selection-today-dark.png',
    'no-selection-today-cap-light.png',
    'no-selection-today-cap-dark.png',
    'selected-error-light.png',
    'selected-error-dark.png',
)

EXPECTED = {
    "schema_version": 1,
    "required_pngs": list(AGENDA_PNGS),
    "methods": {
        "CalendarAgendaRefreshTests/visibleStoreChangeRefetchesSelectedDayAndPreservesState()": 1,
        "CalendarAgendaRefreshTests/visibleChangeUpdatesEditedAddedDeletedSnapshot()": 1,
        "CalendarAgendaRefreshTests/deselectedChangeQueriesToday()": 1,
        "CalendarAgendaRefreshTests/changePreservesSettingsAndAIDraftEditor()": 1,
        "CalendarAgendaRefreshTests/offMainQueuedChangeUsesCurrentSelectionOnMain()": 1,
        "CalendarAgendaRefreshTests/queuedChangeAfterHideDoesNotFetch()": 1,
        "CalendarAgendaRefreshTests/hiddenAndRemovedRootsIgnoreChanges(removeRoot:)": 2,
        "CalendarAgendaRefreshTests/showHideShowKeepsOneSubscription()": 1,
        "CalendarAgendaRefreshTests/burstAndLateQueriesKeepLatestResult(lateFailure:)": 2,
        "CalendarAgendaRefreshTests/dateChangeAndHideRejectLateInvalidationResult(hide:lateFailure:)": 4,
        "CalendarAgendaRefreshTests/permissionLossOnChangeClearsRowsWithoutAccess(status:)": 4,
        "CalendarAgendaRefreshTests/changeFailureRecoversThroughRetryOrLaterSignal(useRetry:)": 2,
        "CalendarAgendaRefreshTests/nilAndUnrelatedObjectChangesInvalidate(unrelatedObject:)": 2,
    },
}


def metadata():
    # Hand-checked totals describe this synthetic thirteen-method/twenty-three-case graph.
    summary = {
        "result": "Passed", "totalTestCount": 13, "passedTests": 13, "failedTests": 0,
        "skippedTests": 0, "expectedFailures": 0, "testFailures": [],
        "devicesAndConfigurations": [
            {"passedTests": 23, "failedTests": 0, "skippedTests": 0, "expectedFailures": 0},
        ],
    }
    prefix = "test://com.apple.xcode/Glimpse/GlimpseTests/"
    nodes = []
    for identifier, count in EXPECTED["methods"].items():
        node = {"nodeType": "Test Case", "result": "Passed",
                "nodeIdentifier": identifier, "nodeIdentifierURL": prefix + identifier}
        if count > 1:
            node["children"] = [
                {"nodeType": "Arguments", "result": "Passed",
                 "name": f"synthetic argument {index}",
                 "nodeIdentifierURL": prefix + identifier + f"?args=fixture-{index}"}
                for index in range(1, count + 1)
            ]
        nodes.append(node)
    tests = {"testNodes": [
        {"nodeType": "Test Plan", "result": "Passed", "children": [
            {"nodeType": "Unit test bundle", "result": "Passed", "children": [
                {"nodeType": "Test Suite", "result": "Passed", "children": nodes},
            ]},
        ]},
    ]}
    return summary, tests
