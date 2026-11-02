import copy
import hashlib
import importlib.util
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest

import test_quality_gate
from keyboard_xcresult_fixture import cases

SCRIPTS = pathlib.Path(__file__).parents[1]
EDITOR = "CalendarKeyboardOwnershipTests/nativeEditorSubmitEscapeAndHiddenReopen()"


class KeyboardRuntimeWarningContracts(unittest.TestCase):
    def setUp(self):
        fixture = json.loads((pathlib.Path(__file__).parent
                              / "fixtures/keyboard-runtime-warning.json").read_text())
        self.expected = json.loads((SCRIPTS / "keyboard-ownership-methods.json").read_text())
        self.summary, self.tests = fixture["summary"], fixture["tests"]
        spec = importlib.util.spec_from_file_location(
            "keyboard_checker", SCRIPTS / "check-keyboard-xcresult.py")
        self.checker = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.checker)

    def editor(self, tests):
        return next(node for node in cases(tests) if node["nodeIdentifier"] == EDITOR)

    def run_checker(self, *, tests=None, exits=None):
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            paths = {name: root / (name + ".json") for name in ("manifest", "summary", "tests")}
            for name, document in (("manifest", self.expected), ("summary", self.summary),
                                   ("tests", self.tests if tests is None else tests)):
                paths[name].write_text(json.dumps(document))
            receipt_path = root / "receipt.json"
            command = [sys.executable, str(SCRIPTS / "check-keyboard-xcresult.py")]
            for name, path in paths.items():
                command.extend(["--" + name, str(path)])
            command.extend(["--receipt", str(receipt_path)])
            for name, status in (exits or {}).items():
                command.extend(["--" + name + "-exit", str(status)])
            result = subprocess.run(command, text=True, capture_output=True, timeout=10)
            return result, json.loads(receipt_path.read_text()), {
                name: hashlib.sha256(path.read_bytes()).hexdigest() for name, path in paths.items()
            }

    def test_saved_fourteen_method_sixteen_case_tree_retains_qos_warning_and_input_digests(self):
        result, receipt, digests = self.run_checker()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(receipt["status"], "Passed")
        self.assertEqual(receipt["methods"], self.expected["methods"])
        self.assertEqual(len(receipt["methods"]), 14)
        self.assertEqual(receipt["executed_cases"], 16)
        warning = self.editor(self.tests)["children"][0]
        self.assertEqual(warning["sourceLocation"]["lineNumber"], 958)
        self.assertIn("quality-of-service", warning["name"])
        self.assertEqual(receipt["runtime_warnings"], [{"method": EDITOR, **warning}])
        self.assertEqual(receipt["command_exits"],
                         {"xcodebuild": 0, "summary": 0, "tests": 0, "log": 0})
        for name, digest in digests.items():
            self.assertEqual(receipt["sha256"][name], digest)
        self.assertEqual(receipt["sha256"]["checker"],
                         hashlib.sha256((SCRIPTS / "check-keyboard-xcresult.py").read_bytes()).hexdigest())
        # Existing callers still receive the method dictionary.
        self.assertEqual(self.checker.validate(self.expected, self.summary, self.tests),
                         self.expected["methods"])

    def test_warning_optional_location_and_empty_typed_children_do_not_add_executions(self):
        for with_location in (False, True):
            for with_children in (False, True):
                with self.subTest(location=with_location, children=with_children):
                    tests = copy.deepcopy(self.tests)
                    warning = self.editor(tests)["children"][0]
                    if not with_location:
                        warning.pop("sourceLocation")
                    if with_children:
                        warning["children"] = []
                    result, receipt, _ = self.run_checker(tests=tests)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertEqual(receipt["executed_cases"], 16)
                    self.assertEqual(receipt["runtime_warnings"], [{"method": EDITOR, **warning}])

    def test_malformed_warning_or_unknown_child_cannot_be_admitted(self):
        updates = [
            {"nodeType": "Unknown"}, {"nodeType": "Failure"}, {"name": ""},
            {"name": "  "}, {"name": None}, {"name": 1},
            *({"children": value} for value in (False, 0, "", {}, None, [{}])),
            *({key: value} for key in ("result", "nodeIdentifier", "nodeIdentifierURL")
              for value in (None, "", "Passed")),
            {"unrecognizedField": "value"}, {"sourceLocation": None},
            {"sourceLocation": {}}, {"sourceLocation": {"filePath": "/fixture.swift"}},
            *({"sourceLocation": {"filePath": path, "lineNumber": 958}}
              for path in ("", " ", None, 1)),
            *({"sourceLocation": {"filePath": "/fixture.swift", "lineNumber": line}}
              for line in (0, -1, True, "958", 958.0, None)),
            {"sourceLocation": {"filePath": "/fixture.swift", "lineNumber": 958, "unknown": True}},
        ]
        for update in updates:
            with self.subTest(update=update):
                tests = copy.deepcopy(self.tests)
                self.editor(tests)["children"][0].update(update)
                with self.assertRaises(ValueError):
                    self.checker.validate(self.expected, self.summary, tests)
        for child in (None, "Runtime Warning", [], {}):
            with self.subTest(child=child):
                tests = copy.deepcopy(self.tests)
                self.editor(tests)["children"] = [child]
                with self.assertRaises(ValueError):
                    self.checker.validate(self.expected, self.summary, tests)

    def test_warning_sibling_never_replaces_missing_failed_or_skipped_parameter_execution(self):
        for scenario in ("valid", "missing-one", "missing-all", "failed", "skipped",
                         "unknown-result", "duplicate-url", "duplicate-name"):
            with self.subTest(scenario=scenario):
                tests = copy.deepcopy(self.tests)
                node = next(node for node in cases(tests)
                            if self.expected["methods"][node["nodeIdentifier"]] == 2)
                arguments = node["children"]
                if scenario == "missing-one":
                    arguments.pop()
                elif scenario == "missing-all":
                    arguments.clear()
                elif scenario in ("failed", "skipped", "unknown-result"):
                    arguments[0]["result"] = {"failed": "Failed", "skipped": "Skipped",
                                              "unknown-result": "Unknown"}[scenario]
                elif scenario == "duplicate-url":
                    arguments[1]["nodeIdentifierURL"] = arguments[0]["nodeIdentifierURL"]
                elif scenario == "duplicate-name":
                    arguments[1]["name"] = arguments[0]["name"]
                node["children"].append(copy.deepcopy(self.editor(tests)["children"][0]))
                if scenario == "valid":
                    self.assertEqual(self.checker.validate(self.expected, self.summary, tests),
                                     self.expected["methods"])
                else:
                    with self.assertRaises(ValueError):
                        self.checker.validate(self.expected, self.summary, tests)

    def test_warning_below_passed_argument_is_retained_with_parameter_identity(self):
        tests = copy.deepcopy(self.tests)
        warning = copy.deepcopy(self.editor(tests)["children"][0])
        node = next(node for node in cases(tests)
                    if self.expected["methods"][node["nodeIdentifier"]] == 2)
        argument = node["children"][0]
        argument["children"] = [warning]
        result, receipt, _ = self.run_checker(tests=tests)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(receipt["methods"], self.expected["methods"])
        self.assertEqual(receipt["executed_cases"], 16)
        self.assertCountEqual(receipt["runtime_warnings"], [
            {"method": EDITOR, **self.editor(tests)["children"][0]},
            {"method": node["nodeIdentifier"],
             "parameter": {"name": argument["name"], "nodeIdentifierURL": argument["nodeIdentifierURL"]},
             **warning},
        ])

    def test_warning_at_suite_level_remains_invalid(self):
        tests = copy.deepcopy(self.tests)
        cases(tests).append(copy.deepcopy(self.editor(tests)["children"][0]))
        with self.assertRaises(ValueError):
            self.checker.validate(self.expected, self.summary, tests)

    def test_argument_warning_cannot_admit_invalid_leaves_or_nonpassing_duplicate_missing_cases(self):
        for scenario in ("malformed-warning", "unknown-child", "nested-warning", "failed", "skipped",
                         "missing", "duplicate-url", "duplicate-name"):
            with self.subTest(scenario=scenario):
                tests = copy.deepcopy(self.tests)
                node = next(node for node in cases(tests)
                            if self.expected["methods"][node["nodeIdentifier"]] == 2)
                argument = node["children"][0]
                warning = copy.deepcopy(self.editor(tests)["children"][0])
                argument["children"] = [warning]
                if scenario == "malformed-warning":
                    warning["name"] = ""
                elif scenario == "unknown-child":
                    warning["nodeType"] = "Unknown"
                elif scenario == "nested-warning":
                    warning["children"] = [copy.deepcopy(warning)]
                elif scenario in ("failed", "skipped"):
                    argument["result"] = scenario.title()
                elif scenario == "missing":
                    node["children"].pop()
                elif scenario == "duplicate-url":
                    node["children"][1]["nodeIdentifierURL"] = argument["nodeIdentifierURL"]
                elif scenario == "duplicate-name":
                    node["children"][1]["name"] = argument["name"]
                with self.assertRaises(ValueError):
                    self.checker.validate(self.expected, self.summary, tests)

    def test_warning_does_not_override_any_command_failure(self):
        for name in ("xcodebuild", "summary", "tests", "log"):
            with self.subTest(command=name):
                exits = {"xcodebuild": 0, "summary": 0, "tests": 0, "log": 0, name: 65}
                result, receipt, digests = self.run_checker(exits=exits)
                self.assertEqual(result.returncode, 1)
                self.assertEqual(receipt["status"], "Failed")
                self.assertEqual(receipt["command_exits"], exits)
                for key, digest in digests.items():
                    self.assertEqual(receipt["sha256"][key], digest)

    def test_mocked_gate_accepts_saved_warning_tree_and_retains_diagnostic_receipt(self):
        fixture = test_quality_gate.LocalQualityContracts()
        self.addCleanup(fixture.doCleanups)
        result, root, _, _, runner_temp, results, observed, workspace = fixture.run_workspace_fixture(
            keyboard="both", keyboard_manifest=self.expected,
            keyboard_summary=self.summary, keyboard_tests=self.tests,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        receipt = json.loads((results / "keyboard-ownership-acceptance.json").read_text())
        self.assertEqual(receipt["methods"], self.expected["methods"])
        self.assertEqual(receipt["executed_cases"], 16)
        self.assertEqual(receipt["runtime_warnings"],
                         [{"method": EDITOR, **self.editor(self.tests)["children"][0]}])
        fixture.assert_workspace_cleanup(root, runner_temp, workspace, observed)
        self.assertTrue(any(entry["command"] == "swift" for entry in observed))


if __name__ == "__main__":
    unittest.main()
