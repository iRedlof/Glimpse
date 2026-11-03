import copy
import hashlib
import json
import pathlib
import subprocess
import sys
import unittest

from agenda_refresh_xcresult_fixture import EXPECTED, SUITE, cases, fixture_directory, metadata

SCRIPTS = pathlib.Path(__file__).parents[1]


class AgendaRefreshResultContracts(unittest.TestCase):
    def run_checker(self, *, manifest=None, summary=None, tests=None, suite=SUITE,
                    exits=None, duplicate_json=False):
        root = fixture_directory(self, "agenda-checker-")
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
        command = [sys.executable, str(SCRIPTS / "check-keyboard-xcresult.py"), "--suite", suite]
        for name, path in paths.items():
            command.extend(["--" + name, str(path)])
        command.extend(["--receipt", str(root / "receipt.json")])
        for name, code in (exits or {}).items():
            command.extend(["--" + name + "-exit", str(code)])
        result = subprocess.run(command, capture_output=True, text=True, timeout=10)
        for name, text in (("stdout.log", result.stdout), ("stderr.log", result.stderr)):
            (root / name).write_text(text)
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

    def test_exact_agenda_graph_passes_with_accurate_label_and_input_hashes(self):
        result, receipt, paths = self.run_checker()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Agenda refresh: Passed (23 cases)", result.stdout)
        self.assertEqual(receipt["methods"], EXPECTED["methods"])
        self.assertEqual(len(receipt["methods"]), 13)
        self.assertEqual(receipt["executed_cases"], 23)
        self.assertEqual(receipt["command_exits"], {"xcodebuild": 0, "summary": 0, "tests": 0, "log": 0})
        for name, path in paths.items():
            self.assertEqual(receipt["sha256"][name], hashlib.sha256(path.read_bytes()).hexdigest())

    def test_archive_membership_is_exact_and_parameter_counts_are_required(self):
        manifest = SCRIPTS / "agenda-refresh-methods.json"
        self.assertTrue(manifest.is_file(), "the source archive needs its agenda membership manifest")
        self.assertEqual(json.loads(manifest.read_text()), EXPECTED)
        for change in ("missing-method", "duplicate-method", "unexpected-method", "wrong-method-url",
                       "missing-argument", "duplicate-argument-url", "duplicate-argument-name",
                       "foreign-argument-url", "failed-argument", "skipped-argument"):
            with self.subTest(change=change):
                _, tests = metadata()
                nodes = cases(tests)
                args = nodes[9]["children"]
                if change == "missing-method":
                    nodes.pop()
                elif change == "duplicate-method":
                    nodes.append(copy.deepcopy(nodes[0]))
                elif change == "unexpected-method":
                    nodes[0]["nodeIdentifier"] = SUITE + "/unlisted()"
                elif change == "wrong-method-url":
                    nodes[0]["nodeIdentifierURL"] += "?args=unexpected"
                elif change == "missing-argument":
                    args.pop()
                elif change == "duplicate-argument-url":
                    args[1]["nodeIdentifierURL"] = args[0]["nodeIdentifierURL"]
                elif change == "duplicate-argument-name":
                    args[1]["name"] = args[0]["name"]
                elif change == "foreign-argument-url":
                    args[0]["nodeIdentifierURL"] = "test://foreign/fixture?args=1"
                else:
                    args[0]["result"] = "Failed" if change == "failed-argument" else "Skipped"
                self.assert_rejected(tests=tests)

    def test_wrong_suite_summary_skips_failures_and_case_totals_fail_closed(self):
        for suite in ("CalendarKeyboardOwnershipTests", "AIDateSearchIntegrationTests"):
            with self.subTest(suite=suite):
                self.assert_rejected(suite=suite)
        for field, value in (("totalTestCount", 12), ("passedTests", 12), ("failedTests", 1),
                             ("skippedTests", 1), ("expectedFailures", 1), ("testFailures", [{}]),
                             ("result", "Skipped"), ("totalTestCount", True)):
            with self.subTest(field=field):
                summary, _ = metadata()
                summary[field] = value
                self.assert_rejected(summary=summary)
        summary, _ = metadata()
        summary["devicesAndConfigurations"][0]["passedTests"] = 22
        self.assert_rejected(summary=summary)

    def test_passed_argument_warning_retains_exact_method_and_parameter_identity(self):
        _, tests = metadata()
        method = cases(tests)[9]
        argument = method["children"][0]
        warning = {"nodeType": "Runtime Warning", "name": "synthetic lifecycle diagnostic",
                   "sourceLocation": {"filePath": "SyntheticFixture.swift", "lineNumber": 9}}
        argument["children"] = [warning]
        result, receipt, _ = self.run_checker(tests=tests)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(receipt["executed_cases"], 23)
        self.assertEqual(receipt["runtime_warnings"], [
            {"method": method["nodeIdentifier"], **warning,
             "parameter": {"name": argument["name"], "nodeIdentifierURL": argument["nodeIdentifierURL"]}},
        ])

    def test_malformed_or_unknown_warnings_cannot_repair_arguments(self):
        for change in ("empty-name", "unknown-field", "nested-child", "bad-location",
                       "failed-parent", "skipped-parent", "suite-warning"):
            with self.subTest(change=change):
                _, tests = metadata()
                argument = cases(tests)[9]["children"][0]
                warning = {"nodeType": "Runtime Warning", "name": "synthetic diagnostic"}
                argument["children"] = [warning]
                if change == "empty-name":
                    warning["name"] = ""
                elif change == "unknown-field":
                    warning["result"] = "Passed"
                elif change == "nested-child":
                    warning["children"] = [copy.deepcopy(warning)]
                elif change == "bad-location":
                    warning["sourceLocation"] = {"filePath": "fixture", "lineNumber": True}
                elif change in ("failed-parent", "skipped-parent"):
                    argument["result"] = "Failed" if change == "failed-parent" else "Skipped"
                else:
                    tests["testNodes"][0]["children"][0]["children"][0]["children"].append(warning)
                self.assert_rejected(tests=tests)

    def test_duplicate_json_and_each_raw_command_exit_remain_failures(self):
        result, receipt, paths = self.run_checker(duplicate_json=True)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertEqual(receipt["status"], "Failed")
        self.assertIn("Duplicate JSON key", receipt["errors"])
        self.assertEqual(receipt["sha256"]["manifest"],
                         hashlib.sha256(paths["manifest"].read_bytes()).hexdigest())
        for phase, code in (("xcodebuild", 65), ("summary", 8), ("tests", 9), ("log", 7)):
            with self.subTest(phase=phase):
                self.assert_rejected(exits={phase: code})

    def test_unknown_suite_spellings_are_rejected_by_cli(self):
        for suite in ("OtherTests", "CalendarAgendaRefreshTests/.*", "calendaragendarefreshtests"):
            with self.subTest(suite=suite):
                result, receipt, _ = self.run_checker(suite=suite)
                self.assertEqual(result.returncode, 2)
                self.assertIsNone(receipt)
                self.assertIn("invalid choice", result.stderr)


if __name__ == "__main__":
    unittest.main()
