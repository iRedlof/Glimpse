"""Synthetic public metadata only; this is not an executed native suite."""

import os
import pathlib
import tempfile

SUITE = "AIDateSearchIntegrationTests"
EXPECTED = {
    "schema_version": 1,
    "methods": {
        "AIDateSearchIntegrationTests/actualRowShowsStaticOutcomesAndResubmitsOnce(outcome:)": 3,
        "AIDateSearchIntegrationTests/cancellationEndsProgressWithoutFeedback()": 1,
        "AIDateSearchIntegrationTests/nativeDraftEditRejectsLateCompletionAndAllowsClose()": 1,
        "AIDateSearchIntegrationTests/directSettingsSettersInvalidateBeforeCompletion(action:)": 3,
        "AIDateSearchIntegrationTests/preferenceReloadReconcilesCurrentSettings(disable:)": 2,
        "AIDateSearchIntegrationTests/hiddenPreparationAndVisibleShowPreserveOwnership()": 1,
        "AIDateSearchIntegrationTests/dismissEscapeAndRemovalRejectLateCompletion(boundary:)": 3,
        "AIDateSearchIntegrationTests/failureCopyFitsAndRemainsAccessible(outcome:)": 3,
        "AIDateSearchIntegrationTests/liveCreateNeedsAnExplicitPickAndSavesOnce()": 1,
        "AIDateSearchIntegrationTests/liveCreateReturnInTheFieldNeverRequestsCalendarAccess()": 1,
        "AIDateSearchIntegrationTests/liveCreateSlotKeysWorkWhenFocusLeavesTheField()": 1,
    },
}


def metadata():
    # Literal totals independently describe the accepted graph.
    summary = {
        "result": "Passed", "totalTestCount": 11, "passedTests": 11, "failedTests": 0,
        "skippedTests": 0, "expectedFailures": 0, "testFailures": [],
        "devicesAndConfigurations": [
            {"passedTests": 20, "failedTests": 0, "skippedTests": 0, "expectedFailures": 0},
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


def cases(tests):
    return tests["testNodes"][0]["children"][0]["children"][0]["children"]


def fixture_directory(test, prefix):
    """Retain raw synthetic runs when explicitly requested by an offline caller."""
    retained = os.environ.get("GLIMPSE_OFFLINE_FIXTURE_ROOT")
    if retained:
        return pathlib.Path(tempfile.mkdtemp(prefix=prefix, dir=retained)).resolve()
    temporary = tempfile.TemporaryDirectory(prefix=prefix)
    test.addCleanup(temporary.cleanup)
    return pathlib.Path(temporary.name).resolve()
