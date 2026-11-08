import copy
import hashlib
import importlib.util
import json
import pathlib
import subprocess
import sys
import unittest

from ai_date_search_xcresult_fixture import EXPECTED, SUITE, cases, fixture_directory, metadata
from keyboard_xcresult_fixture import current_suite

SCRIPTS = pathlib.Path(__file__).parents[1]


class AIDateSearchResultContracts(unittest.TestCase):
    def run_checker(self, *, manifest=None, summary=None, tests=None, suite=SUITE,
                    exits=None, duplicate_json=False):
        root = fixture_directory(self, "checker-")
        base_summary, base_tests = metadata()
        documents = {"manifest": EXPECTED if manifest is None else manifest,
                     "summary": base_summary if summary is None else summary,
                     "tests": base_tests if tests is None else tests}
        paths = {name: root / (name + ".json") for name in documents}
        for name, document in documents.items():
            paths[name].write_text(json.dumps(document) + "\n")
        if duplicate_json:
            paths["manifest"].write_text(
                '{"schema_version":1,"schema_version":1,"methods":' +
                json.dumps(EXPECTED["methods"]) + '}\n')
        command = [sys.executable, str(SCRIPTS / "check-keyboard-xcresult.py")]
        for name, path in paths.items():
            command.extend(["--" + name, str(path)])
        command.extend(["--receipt", str(root / "receipt.json")])
        if suite is not None:
            command.extend(["--suite", suite])
        for name, code in (exits or {}).items():
            command.extend(["--" + name + "-exit", str(code)])
        result = subprocess.run(command, capture_output=True, text=True, timeout=10)
        (root / "stdout.log").write_text(result.stdout)
        (root / "stderr.log").write_text(result.stderr)
        (root / "command.json").write_text(json.dumps(
            {"argv": command, "timeout_seconds": 10, "exit": result.returncode}, indent=2) + "\n")
        receipt = json.loads((root / "receipt.json").read_text()) if (root / "receipt.json").exists() else None
        return result, receipt, paths

    def assert_rejected(self, **kwargs):
        result, receipt, paths = self.run_checker(**kwargs)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertEqual(receipt["status"], "Failed")
        self.assertEqual(receipt["methods"], {})
        self.assertEqual(receipt["executed_cases"], 0)
        self.assertTrue(receipt["errors"])
        for name, path in paths.items():
            self.assertEqual(receipt["sha256"][name], hashlib.sha256(path.read_bytes()).hexdigest())
        return receipt

    def test_selected_ai_graph_is_nine_methods_eighteen_cases_with_exact_input_hashes(self):
        result, receipt, paths = self.run_checker()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(receipt["status"], "Passed")
        self.assertEqual(receipt["methods"], EXPECTED["methods"])
        self.assertEqual(len(receipt["methods"]), 9)
        self.assertEqual(receipt["executed_cases"], 18)
        self.assertEqual(receipt["command_exits"],
                         {"xcodebuild": 0, "summary": 0, "tests": 0, "log": 0})
        for name, path in paths.items():
            self.assertEqual(receipt["sha256"][name], hashlib.sha256(path.read_bytes()).hexdigest())
        self.assertEqual(receipt["sha256"]["checker"],
                         hashlib.sha256((SCRIPTS / "check-keyboard-xcresult.py").read_bytes()).hexdigest())

    def test_keyboard_default_and_explicit_choice_keep_existing_fourteen_sixteen_contract(self):
        manifest, summary, tests = current_suite()
        for suite in (None, "CalendarKeyboardOwnershipTests"):
            with self.subTest(suite=suite):
                result, receipt, _ = self.run_checker(
                    manifest=manifest, summary=summary, tests=tests, suite=suite)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(receipt["methods"], manifest["methods"])
                self.assertEqual(receipt["executed_cases"], 16)

    def test_only_two_exact_suites_are_selectable_and_validate_default_stays_compatible(self):
        for suite in ("OtherTests", "AIDateSearchIntegrationTests/.*", "aidatesearchintegrationtests"):
            with self.subTest(suite=suite):
                result, receipt, _ = self.run_checker(suite=suite)
                self.assertEqual(result.returncode, 2)
                self.assertIsNone(receipt)
                self.assertIn("invalid choice", result.stderr)
        spec = importlib.util.spec_from_file_location("selected_checker", SCRIPTS / "check-keyboard-xcresult.py")
        checker = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(checker)
        manifest, summary, tests = current_suite()
        self.assertEqual(checker.validate(manifest, summary, tests), manifest["methods"])
        with self.assertRaisesRegex(ValueError, "suite"):
            checker.validate(manifest, summary, tests, suite="OtherTests")

    def test_cross_suite_or_mixed_manifest_cannot_pass_either_selection(self):
        self.assert_rejected(suite=None)
        keyboard, summary, tests = current_suite()
        self.assert_rejected(manifest=keyboard, summary=summary, tests=tests)
        mixed = copy.deepcopy(EXPECTED)
        mixed["methods"][next(iter(keyboard["methods"]))] = 1
        self.assert_rejected(manifest=mixed)

    def test_no_selection_skips_failures_wrong_device_and_wrong_case_totals_are_rejected(self):
        for field, value in (("totalTestCount", 0), ("passedTests", 0), ("failedTests", 1),
                             ("skippedTests", 1), ("expectedFailures", 1), ("result", "Skipped"),
                             ("totalTestCount", True), ("testFailures", [{}])):
            with self.subTest(field=field, value=value):
                summary, _ = metadata()
                summary[field] = value
                self.assert_rejected(summary=summary)
        for change in ("zero-devices", "two-devices", "missing-case", "failed-case", "skipped-case"):
            with self.subTest(change=change):
                summary, _ = metadata()
                device = summary["devicesAndConfigurations"][0]
                if change == "zero-devices":
                    summary["devicesAndConfigurations"].clear()
                elif change == "two-devices":
                    summary["devicesAndConfigurations"].append(copy.deepcopy(device))
                else:
                    device[{"missing-case": "passedTests", "failed-case": "failedTests",
                            "skipped-case": "skippedTests"}[change]] = 16 if change == "missing-case" else 1
                self.assert_rejected(summary=summary)

    def test_missing_duplicate_failed_and_wrong_url_method_executions_fail(self):
        for change in ("missing", "duplicate", "failed", "skipped", "wrong-url", "unexpected"):
            with self.subTest(change=change):
                _, tests = metadata()
                nodes = cases(tests)
                if change == "missing":
                    nodes.pop()
                elif change == "duplicate":
                    nodes.append(copy.deepcopy(nodes[0]))
                elif change in ("failed", "skipped"):
                    nodes[0]["result"] = change.title()
                elif change == "wrong-url":
                    nodes[0]["nodeIdentifierURL"] += "?args=unexpected"
                else:
                    nodes[0]["nodeIdentifier"] = "AIDateSearchIntegrationTests/unlisted()"
                self.assert_rejected(tests=tests)

    def test_arguments_require_unique_names_urls_exact_count_and_passed_leaf_nodes(self):
        for change in ("missing", "empty", "duplicate-url", "duplicate-name", "failed",
                       "skipped", "foreign-url", "nested", "unknown-child"):
            with self.subTest(change=change):
                _, tests = metadata()
                args = cases(tests)[0]["children"]
                if change == "missing":
                    args.pop()
                elif change == "empty":
                    args.clear()
                elif change == "duplicate-url":
                    args[1]["nodeIdentifierURL"] = args[0]["nodeIdentifierURL"]
                elif change == "duplicate-name":
                    args[1]["name"] = args[0]["name"]
                elif change in ("failed", "skipped"):
                    args[0]["result"] = change.title()
                elif change == "foreign-url":
                    args[0]["nodeIdentifierURL"] = "test://foreign/fixture?args=1"
                elif change == "nested":
                    args[0]["children"] = [{}]
                else:
                    args[0]["nodeType"] = "Unknown"
                self.assert_rejected(tests=tests)

    def test_ai_runtime_warning_is_retained_but_cannot_replace_a_parameter_case(self):
        _, tests = metadata()
        warning = {"nodeType": "Runtime Warning", "name": "Synthetic fixture warning",
                   "sourceLocation": {"filePath": "/synthetic/fixture.swift", "lineNumber": 12}}
        cases(tests)[0]["children"].append(warning)
        result, receipt, _ = self.run_checker(tests=tests)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(receipt["executed_cases"], 18)
        self.assertEqual(receipt["runtime_warnings"],
                         [{"method": next(iter(EXPECTED["methods"])), **warning}])
        cases(tests)[0]["children"].pop(0)
        self.assert_rejected(tests=tests)

    def nested_warning_metadata(self):
        summary, tests = metadata()
        argument = cases(tests)[0]["children"][0]
        argument["name"] = ".noDate"
        argument["nodeIdentifierURL"] = cases(tests)[0]["nodeIdentifierURL"] + "?args=2e6e6f44617465"
        warning = {"nodeType": "Runtime Warning", "name": "Synthetic quality-of-service warning",
                   "sourceLocation": {"filePath": "/synthetic/CalendarKeyboardOwnershipTests.swift",
                                      "lineNumber": 1016}}
        argument["children"] = [warning]
        return summary, tests, argument, warning

    def test_warning_leaf_below_passed_argument_retains_method_and_parameter_identity(self):
        for with_location in (False, True):
            for with_children in (False, True):
                with self.subTest(location=with_location, children=with_children):
                    summary, tests, argument, warning = self.nested_warning_metadata()
                    if not with_location:
                        warning.pop("sourceLocation")
                    if with_children:
                        warning["children"] = []
                    result, receipt, _ = self.run_checker(summary=summary, tests=tests)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertEqual(receipt["methods"], EXPECTED["methods"])
                    self.assertEqual(receipt["executed_cases"], 18)
                    self.assertEqual(receipt["runtime_warnings"], [
                        {"method": next(iter(EXPECTED["methods"])),
                         "parameter": {"name": ".noDate", "nodeIdentifierURL": argument["nodeIdentifierURL"]},
                         **warning},
                    ])

    def test_malformed_or_unknown_argument_warning_children_cannot_be_admitted(self):
        updates = [
            {"nodeType": "Unknown"}, {"name": ""}, {"name": " "}, {"name": None},
            {"children": None}, {"children": {}}, {"children": [{}]},
            {"result": "Passed"}, {"nodeIdentifierURL": "test://foreign/fixture"},
            {"sourceLocation": {"filePath": "/synthetic/fixture.swift", "lineNumber": 0}},
            {"sourceLocation": {"filePath": "/synthetic/fixture.swift", "lineNumber": True}},
            {"sourceLocation": {"filePath": "", "lineNumber": 1016}},
            {"sourceLocation": {"filePath": "/synthetic/fixture.swift", "lineNumber": 1016, "unknown": True}},
        ]
        for update in updates:
            with self.subTest(update=update):
                summary, tests, _, warning = self.nested_warning_metadata()
                warning.update(update)
                self.assert_rejected(summary=summary, tests=tests)
        for child in (None, "Runtime Warning", [], {}):
            with self.subTest(child=child):
                summary, tests, argument, _ = self.nested_warning_metadata()
                argument["children"] = [child]
                self.assert_rejected(summary=summary, tests=tests)

    def test_nested_warning_cannot_repair_failed_skipped_missing_or_duplicated_argument_cases(self):
        for change in ("failed", "skipped", "missing", "duplicate-url", "duplicate-name",
                       "foreign-url", "nested-argument"):
            with self.subTest(change=change):
                summary, tests, argument, _ = self.nested_warning_metadata()
                arguments = cases(tests)[0]["children"]
                if change in ("failed", "skipped"):
                    argument["result"] = change.title()
                elif change == "missing":
                    arguments.pop()
                elif change == "duplicate-url":
                    arguments[1]["nodeIdentifierURL"] = argument["nodeIdentifierURL"]
                elif change == "duplicate-name":
                    arguments[1]["name"] = argument["name"]
                elif change == "foreign-url":
                    argument["nodeIdentifierURL"] = "test://foreign/fixture?args=1"
                else:
                    argument["children"].append(copy.deepcopy(arguments[1]))
                self.assert_rejected(summary=summary, tests=tests)

    def test_nested_warning_never_overrides_any_command_failure(self):
        for name in ("xcodebuild", "summary", "tests", "log"):
            with self.subTest(command=name):
                summary, tests, _, _ = self.nested_warning_metadata()
                receipt = self.assert_rejected(summary=summary, tests=tests, exits={name: 65})
                self.assertEqual(receipt["command_exits"][name], 65)

    def test_each_raw_command_exit_and_duplicate_json_key_fail_with_retained_receipt(self):
        for name in ("xcodebuild", "summary", "tests", "log"):
            with self.subTest(command=name):
                receipt = self.assert_rejected(exits={name: 65})
                self.assertEqual(receipt["command_exits"][name], 65)
        result, receipt, paths = self.run_checker(duplicate_json=True)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(receipt["status"], "Failed")
        self.assertIn("Duplicate JSON key", receipt["errors"])
        # Parsing stops at the malformed first input; only read bytes have digests.
        self.assertEqual(receipt["sha256"]["manifest"],
                         hashlib.sha256(paths["manifest"].read_bytes()).hexdigest())

    def test_archive_manifest_matches_the_accepted_literal_graph(self):
        self.assertEqual(json.loads((SCRIPTS / "ai-date-search-integration-methods.json").read_text()),
                         EXPECTED)


if __name__ == "__main__":
    unittest.main()
