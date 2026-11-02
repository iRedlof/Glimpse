"""Fixture tests; do not launch, stop, or configure any macOS application."""

import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).with_name("health-check.py")
EXECUTABLE = "/Applications/Glimpse.app/Contents/MacOS/Glimpse"
BUNDLE_ID = "com.rohit.Glimpse"


def module():
    if not SCRIPT.exists():
        raise AssertionError("The read-only health checker is not implemented")
    spec = importlib.util.spec_from_file_location("glimpse_health_check", SCRIPT)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


def report(path=EXECUTABLE, name="Glimpse", bundle=BUNDLE_ID, incident="incident-1"):
    header = {"app_name": name, "bundleID": bundle, "bug_type": "309"}
    body = {
        "procName": name, "procPath": path,
        "bundleInfo": {"CFBundleIdentifier": bundle},
        "incident": incident, "captureTime": "2026-11-01 10:00:00 -0700",
        "exception": {"type": "EXC_BAD_ACCESS", "signal": "SIGSEGV"},
    }
    return json.dumps(header) + "\n" + json.dumps(body)


def snapshot(availability="running", pid=2805, cpu_seconds=30.0, at=1000.0):
    processes = [] if availability in ("missing", "unknown") else [{
        "pid": pid, "elapsed_seconds": 100, "cpu_seconds": cpu_seconds,
        "cpu_percent": 0.1, "rss_bytes": 1024 * 1024,
    }]
    if availability == "duplicate":
        processes.append({**processes[0], "pid": pid + 1})
    return {
        "observed_at": "2026-11-01T18:00:00Z", "observed_epoch": at,
        "availability": availability, "processes": processes,
        "installed": {"version": "1.4.3", "build": "10"},
        "crash_scan": {"complete": True, "errors": [], "reports": []},
        "errors": [],
    }


class ProcessFixtures(unittest.TestCase):
    def test_exact_executable_excludes_development_and_name_only_processes(self):
        parsed = module().parse_processes(
            f"2805 33-08:25:19 0:30.58 0.0 17776 {EXECUTABLE}\n"
            "9000 01:00 0:01.00 2.0 30000 /tmp/QA/Glimpse.app/Contents/MacOS/Glimpse\n"
            "9001 01:00 0:01.00 2.0 30000 Glimpse\n"
        )
        self.assertEqual([p["pid"] for p in parsed], [2805])
        self.assertEqual(parsed[0]["elapsed_seconds"], 33 * 86400 + 8 * 3600 + 25 * 60 + 19)
        self.assertEqual(parsed[0]["cpu_seconds"], 30.58)
        self.assertEqual(parsed[0]["rss_bytes"], 17776 * 1024)

    def test_duplicate_exact_executables_are_preserved(self):
        text = "".join(f"{pid} 01:00 0:01.00 0.0 1000 {EXECUTABLE}\n" for pid in (1, 2))
        self.assertEqual(len(module().parse_processes(text)), 2)

    def test_malformed_matching_process_is_observation_error(self):
        with self.assertRaises(ValueError):
            module().parse_processes(f"2805 INVALID 0:30.58 0.0 17776 {EXECUTABLE}\n")

    def test_process_query_timeout_is_unknown_and_never_missing(self):
        with patch("subprocess.run", side_effect=subprocess.TimeoutExpired("ps", 5)):
            result = module().query_processes()
        self.assertEqual(result["availability"], "unknown")
        self.assertTrue(result["errors"])


class CrashFixtures(unittest.TestCase):
    def test_production_ips_retains_only_safe_summary(self):
        parsed = module().parse_crash_report(report(), Path("Glimpse.ips"))
        self.assertEqual(parsed["id"], "incident:incident-1")
        self.assertEqual(parsed["exception_type"], "EXC_BAD_ACCESS")
        self.assertNotIn("raw", parsed)

    def test_test_host_same_name_and_bundle_is_excluded_by_path(self):
        text = report(path="/tmp/glimpse-qa/app-build/Build/Products/Debug/Glimpse.app/Contents/MacOS/Glimpse")
        self.assertIsNone(module().parse_crash_report(text, Path("Glimpse.ips")))

    def test_unrelated_name_or_bundle_is_excluded(self):
        for text in (report(name="Other"), report(bundle="com.other.Glimpse")):
            with self.subTest(text=text):
                self.assertIsNone(module().parse_crash_report(text, Path("Glimpse.ips")))

    def test_missing_executable_path_does_not_establish_production_crash(self):
        self.assertIsNone(module().parse_crash_report(report(path=""), Path("Glimpse.ips")))

    def test_legacy_crash_format_checks_name_bundle_and_path(self):
        text = (
            f"Process: Glimpse [2805]\nPath: {EXECUTABLE}\nIdentifier: {BUNDLE_ID}\n"
            "Date/Time: 2026-11-01 10:00:00 -0700\n"
            "Incident Identifier: incident-2\nException Type: EXC_BAD_ACCESS (SIGSEGV)\n"
        )
        self.assertEqual(module().parse_crash_report(text, Path("Glimpse.crash"))["id"], "incident:incident-2")
        self.assertIsNone(module().parse_crash_report(text.replace(EXECUTABLE, "/tmp/Glimpse"), Path("Glimpse.crash")))

    def test_noncrash_diagnostic_is_not_a_crash(self):
        header = {"app_name": "Glimpse", "bug_type": "298", "bundleID": BUNDLE_ID}
        body = {"procName": "Glimpse", "procPath": EXECUTABLE}
        self.assertIsNone(module().parse_crash_report(json.dumps(header) + "\n" + json.dumps(body), Path("Glimpse.ips")))

    def test_retired_reports_are_scanned_and_duplicates_deduplicated(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "Retired").mkdir()
            (root / "Glimpse-new.ips").write_text(report())
            (root / "Retired/Glimpse-old.ips").write_text(report())
            (root / "Glimpse-test.ips").write_text(report(path="/tmp/Glimpse"))
            (root / "Other.ips").write_text("{unrelated malformed content")
            result = module().scan_crash_reports([root])
        self.assertTrue(result["complete"])
        self.assertEqual(len(result["reports"]), 1)
        self.assertEqual(result["candidate_count"], 3)

    def test_malformed_or_oversized_report_marks_scan_incomplete(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "Glimpse-broken.ips").write_text("{broken")
            result = module().scan_crash_reports([root])
            self.assertFalse(result["complete"])
            (root / "Glimpse-broken.ips").write_text(report())
            result = module().scan_crash_reports([root], max_bytes=10)
            self.assertFalse(result["complete"])
            self.assertTrue(result["errors"])

    def test_scan_limit_marks_evidence_incomplete(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for number in range(3):
                (root / f"Glimpse-{number}.ips").write_text(report(incident=str(number)))
            result = module().scan_crash_reports([root], max_files=1)
        self.assertFalse(result["complete"])
        self.assertEqual(result["scanned_count"], 1)

    def test_missing_report_root_is_explicit_incomplete_evidence(self):
        with tempfile.TemporaryDirectory() as directory:
            result = module().scan_crash_reports([Path(directory) / "missing"])
        self.assertFalse(result["complete"])
        self.assertTrue(result["errors"])


class StateFixtures(unittest.TestCase):
    def test_first_healthy_run_baselines_old_reports_without_notification(self):
        current = snapshot()
        current["crash_scan"]["reports"] = [{"id": "old-crash", "file": "Glimpse-old.ips"}]
        result, state = module().evaluate(current, None)
        self.assertFalse(result["notify"])
        self.assertEqual(state["seen_crash_ids"], ["old-crash"])
        self.assertIsNone(result["cpu_interval"])

    def test_missing_is_notified_once_then_recovery_is_notified(self):
        result, state = module().evaluate(snapshot("missing"), None)
        self.assertEqual([e["kind"] for e in result["events"]], ["process_missing"])
        repeated, state = module().evaluate(snapshot("missing", at=1060), state)
        self.assertFalse(repeated["notify"])
        recovered, _ = module().evaluate(snapshot(at=1120), state)
        self.assertEqual([e["kind"] for e in recovered["events"]], ["availability_recovered"])

    def test_duplicate_processes_are_notified_once(self):
        result, state = module().evaluate(snapshot("duplicate"), None)
        self.assertEqual(result["events"][0]["kind"], "duplicate_processes")
        result, _ = module().evaluate(snapshot("duplicate", at=1060), state)
        self.assertFalse(result["notify"])

    def test_new_report_notifies_once_even_if_report_moves_to_retired(self):
        _, state = module().evaluate(snapshot(), None)
        current = snapshot(at=1060)
        current["crash_scan"]["reports"] = [{"id": "new-crash", "file": "Glimpse.ips"}]
        result, state = module().evaluate(current, state)
        self.assertEqual([e["kind"] for e in result["events"]], ["new_crash_report"])
        current["crash_scan"]["reports"][0]["file"] = "Retired/Glimpse.ips"
        result, _ = module().evaluate(current, state)
        self.assertFalse(result["notify"])

    def test_restart_and_version_change_are_meaningful(self):
        _, state = module().evaluate(snapshot(), None)
        current = snapshot(pid=2900, at=1060)
        current["installed"]["version"] = "1.4.4"
        result, _ = module().evaluate(current, state)
        self.assertEqual({e["kind"] for e in result["events"]}, {"process_restarted", "installed_version_changed"})

    def test_cpu_interval_uses_cumulative_cpu_delta_and_observation_window(self):
        _, state = module().evaluate(snapshot(cpu_seconds=30, at=1000), None)
        result, _ = module().evaluate(snapshot(cpu_seconds=31.2, at=1060), state)
        self.assertEqual(result["cpu_interval"]["seconds"], 60)
        self.assertAlmostEqual(result["cpu_interval"]["average_percent"], 2)
        self.assertEqual(result["cpu_interval"]["pid"], 2805)

    def test_cpu_interval_is_unavailable_after_restart_or_clock_reversal(self):
        _, state = module().evaluate(snapshot(), None)
        for current in (snapshot(pid=9999, at=1060), snapshot(at=999)):
            self.assertIsNone(module().evaluate(current, state)[0]["cpu_interval"])

    def test_pid_reuse_with_lower_uptime_is_a_restart_without_cpu_interval(self):
        _, state = module().evaluate(snapshot(), None)
        current = snapshot(at=1060)
        current["processes"][0]["elapsed_seconds"] = 5
        result, _ = module().evaluate(current, state)
        self.assertEqual(result["events"][0]["kind"], "process_restarted")
        self.assertIsNone(result["cpu_interval"])

    def test_incomplete_scan_notifies_once_and_never_claims_crash_free(self):
        current = snapshot()
        current["crash_scan"]["complete"] = False
        current["crash_scan"]["errors"] = ["permission denied"]
        result, state = module().evaluate(current, None)
        self.assertEqual(result["events"][0]["kind"], "observation_incomplete")
        self.assertIn("retained", result["limitations"])
        self.assertNotIn("crash_free", result)
        repeated, _ = module().evaluate(current, state)
        self.assertFalse(repeated["notify"])

    def test_invalid_state_file_is_reported_not_silently_reset(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "state.json"
            path.write_text("{bad")
            state, error = module().read_state(path)
        self.assertIsNone(state)
        self.assertIsNotNone(error)

    def test_well_formed_json_with_invalid_nested_state_is_rejected(self):
        for change in (
            {"crash_scan": {}},
            {"processes": [{"pid": 1}]},
            {"observed_epoch": "not a timestamp"},
            {"availability": "nonsense"},
        ):
            with self.subTest(change=change), tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / "state.json"
                broken = {**snapshot(), **change}
                path.write_text(json.dumps({"schema_version": 1, "snapshot": broken, "seen_crash_ids": []}))
                state, error = module().read_state(path)
                self.assertIsNone(state)
                self.assertIsNotNone(error)

    def test_new_observation_failure_notifies_even_if_another_is_unresolved(self):
        current = snapshot()
        current["errors"] = ["ps timeout"]
        _, state = module().evaluate(current, None)
        current["errors"] = ["ps timeout", "metadata unreadable"]
        result, _ = module().evaluate(current, state)
        self.assertEqual(result["events"][0]["kind"], "observation_incomplete")

    def test_atomic_json_output_round_trips(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "nested/output.json"
            module().write_json(path, {"notify": True})
            self.assertEqual(json.loads(path.read_text()), {"notify": True})


if __name__ == "__main__":
    unittest.main()
