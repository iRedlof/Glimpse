"""Public Xcode test-results shape; synthetic data contains no native/private inputs."""

METHOD_IDS = [
    "CalendarKeyboardOwnershipTests/normalOpenRetainsBrowseMonthYearAndToday()",
    "CalendarKeyboardOwnershipTests/queuedTabAndImmediateArrowSpaceActivateNewLogicalDate()",
    "CalendarKeyboardOwnershipTests/firstHeaderReturnUsesFocusedActionRatherThanToday()",
    "CalendarKeyboardOwnershipTests/reverseTabReturnsToHeaderWithoutCustomTraversal()",
    "CalendarKeyboardOwnershipTests/gridExitAndReopenWithdrawOwnerBeforeBrowse()",
    "CalendarKeyboardOwnershipTests/settledTraversalCharacterizesGridBeforeImmediateArrowSpace()",
]


def manifest():
    return {"schema_version": 1, "methods": {identifier: 1 for identifier in METHOD_IDS}}


def summary():
    return {
        "devicesAndConfigurations": [{
            "device": {"architecture": "arm64", "deviceId": "fixture",
                       "deviceName": "Owned fixture", "modelName": "Mac",
                       "osBuildNumber": "fixture", "osVersion": "27.0.1", "platform": "macOS"},
            "expectedFailures": 0, "failedTests": 0, "passedTests": 6, "skippedTests": 0,
            "testPlanConfiguration": {"configurationId": "1", "configurationName": "Test Scheme Action"},
        }],
        "environmentDescription": "Synthetic Glimpse", "expectedFailures": 0, "failedTests": 0,
        "finishTime": 2, "passedTests": 6, "result": "Passed", "runtimeWarnings": [],
        "skippedTests": 0, "startTime": 1, "statistics": [], "testFailures": [],
        "title": "Test - Glimpse", "topInsights": [], "totalTestCount": 6,
    }


def tree():
    prefix = "test://com.apple.xcode/Glimpse/GlimpseTests/"
    cases = [
        {"duration": "0.01s", "durationInSeconds": 0.01, "name": identifier.split("/", 1)[1],
         "nodeIdentifier": identifier, "nodeIdentifierURL": prefix + identifier,
         "nodeType": "Test Case", "result": "Passed"}
        for identifier in METHOD_IDS
    ]
    return {
        "devices": [summary()["devicesAndConfigurations"][0]["device"]],
        "testNodes": [{
            "name": "Glimpse", "nodeType": "Test Plan", "result": "Passed", "children": [{
                "name": "GlimpseTests", "nodeType": "Unit test bundle", "result": "Passed",
                "nodeIdentifierURL": prefix.rstrip("/"), "children": [{
                    "name": "CalendarKeyboardOwnershipTests", "nodeType": "Test Suite",
                    "nodeIdentifierURL": prefix + "CalendarKeyboardOwnershipTests",
                    "result": "Passed", "children": cases,
                }],
            }],
        }],
        "testPlanConfigurations": [{"configurationId": "1", "configurationName": "Test Scheme Action"}],
    }


def cases(tests):
    return tests["testNodes"][0]["children"][0]["children"][0]["children"]


def parameterized():
    expected, result, tests = manifest(), summary(), tree()
    identifier = "CalendarKeyboardOwnershipTests/activation(key:)"
    expected["methods"].pop(METHOD_IDS[-1])
    expected["methods"][identifier] = 2
    case = cases(tests)[-1]
    case.update(name="activation(key:)", nodeIdentifier=identifier,
                nodeIdentifierURL="test://com.apple.xcode/Glimpse/GlimpseTests/" + identifier)
    case["children"] = [
        {"name": name, "nodeType": "Arguments", "result": "Passed",
         "duration": "0.01s", "durationInSeconds": 0.01,
         "nodeIdentifierURL": case["nodeIdentifierURL"] + "?args=" + suffix}
        for name, suffix in ((".returnKey", "first"), (".keypadReturn", "second"))
    ]
    result["devicesAndConfigurations"][0]["passedTests"] = 7
    return expected, result, tests


def current_suite():
    """The engineer's prepared fourteen methods; argument suffixes here are synthetic."""
    expected, result, tests = manifest(), summary(), tree()
    additions = [
        ("gridReturnKeypadRepeatAndModifierOwnership(key:)", 2),
        ("recorderPreferencesAndOwnedPeerKeepCalendarKeys()", 1),
        ("repeatedVisibleShowRetainsGridFocusAndAnchor()", 1),
        ("nativeEditorSubmitEscapeAndHiddenReopen()", 1),
        ("focusedLogicalDateStaysVisibleInCappedViewport(maximumHeight:)", 2),
        ("completionGuardsDoNotResetUnpreparedHiddenOrNonkeyPanels()", 1),
        ("heldHeaderSpaceActivatesOnceAndConsumesRepeat()", 1),
        ("todayBecomingDisabledHasNoExtraTodayAction()", 1),
    ]
    for method, count in additions:
        identifier = "CalendarKeyboardOwnershipTests/" + method
        expected["methods"][identifier] = count
        case = {"name": method, "nodeIdentifier": identifier, "nodeType": "Test Case",
                "nodeIdentifierURL": "test://com.apple.xcode/Glimpse/GlimpseTests/" + identifier,
                "result": "Passed", "duration": "0.01s", "durationInSeconds": 0.01}
        if count == 2:
            case["children"] = [
                {"name": name, "nodeType": "Arguments", "result": "Passed",
                 "duration": "0.01s", "durationInSeconds": 0.01,
                 "nodeIdentifierURL": case["nodeIdentifierURL"] + "?args=" + suffix}
                for name, suffix in (("first fixture argument", "first"), ("second fixture argument", "second"))
            ]
        cases(tests).append(case)
    result.update(totalTestCount=14, passedTests=14)
    result["devicesAndConfigurations"][0]["passedTests"] = 16
    return expected, result, tests


def settings_suite():
    """Current Settings coverage, independent of the retained fourteen-method archive."""
    expected, result, tests = current_suite()
    additions = [
        ("shortcutRecordingStartsFromItsOrdinaryWindow()", 1),
        ("backgroundShortcutControlCannotRecordFromAnotherPanel()", 1),
        ("settingsRecordingFollowsItsOwnWindow(boundary:)", 5),
        ("settingsReopenRefreshesWithoutReplacingState()", 1),
        ("settingsHandoffPreservesPinnedContext(pinned:editorOpen:)", 4),
        ("settingsHandoffRejectsDeferredCalendarPresentation(source:)", 3),
        ("normalCalendarTextDismissalStillRestoresPreviousApplication()", 1),
        ("settingsGearFrontsWindowWithoutInlineExpansion()", 1),
        ("nativeSettingsMenuHasOneRetainedDestination()", 1),
        ("settingsSectionsKeepWindowAndCalendarStable(constrained:)", 2),
        ("settingsNativeCloseLeavesCalendarUntouched(boundary:)", 4),
        ("settingsCategoriesAndRecoveryRemainReachable(constrained:dark:)", 4),
        ("settingsNativeTraversalAndActivation()", 1),
        ("settingsPopupEscapePreservesSelectionAndWindow()", 1),
        ("composedFooterEntryRetainsExactPairAndContext(entry:pinned:)", 6),
        ("scrollingWhileRecordingKeepsMountedOwnerAndFootprint()", 1),
        ("exactPairPriorityReleasesWithoutContextReset(boundary:)", 6),
        ("attachedSheetBlocksCurrentFrontKeyTextAndHiddenReopenBeforeEffects()", 1),
        ("deliveredCalendarClickTransfersPriorityAndReturningSettingsKeepsContext(overlap:)", 3),
        ("keyResignationDuringOwnedPopupCancelsRecordingAndRetainsPriority()", 1),
        ("onePageControllerKeepsNativeGeometryAndSingleDocument(size:)", 2),
        ("footerLifecycleDiscardsHeldEditorAndConfirmationIntent(boundary:)", 2),
        ("cleanupCannotOverwriteNewOwnership(boundary:)", 5),
        ("disposalAloneRestoresPriorityWithoutReplacementOrManualInvalidation()", 1),
        ("injectedFooterActionsHonorNativeDownRepeatUpAndAXAfterKeyboard(owner:key:)", 15),
        ("quitConfirmationOwnsHeldActivationAndRecordsOnlyDeliberateTermination(key:)", 3),
        ("olderAIRequestCannotReclaimCancelOrReturnedQuit(cancelFirst:)", 2),
        ("focusedUpdateActionKeepsNativeKeyboardActivation(dark:)", 2),
    ]
    for method, count in additions:
        identifier = "CalendarKeyboardOwnershipTests/" + method
        expected["methods"][identifier] = count
        case = {
            "name": method, "nodeIdentifier": identifier, "nodeType": "Test Case",
            "nodeIdentifierURL": "test://com.apple.xcode/Glimpse/GlimpseTests/" + identifier,
            "result": "Passed", "duration": "0.01s", "durationInSeconds": 0.01,
        }
        if count > 1:
            case["children"] = [
                {
                    "name": f"fixture argument {index}", "nodeType": "Arguments",
                    "result": "Passed", "duration": "0.01s", "durationInSeconds": 0.01,
                    "nodeIdentifierURL": case["nodeIdentifierURL"] + f"?args={index}",
                }
                for index in range(1, count + 1)
            ]
        cases(tests).append(case)
    result.update(totalTestCount=42, passedTests=42)
    result["devicesAndConfigurations"][0]["passedTests"] = 96
    return expected, result, tests
