import importlib.util
import json
import os
import pathlib
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("release_metrics", pathlib.Path(__file__).parents[1] / "release-metrics.py")
metrics = importlib.util.module_from_spec(spec)
spec.loader.exec_module(metrics)


class ReleaseMetricContracts(unittest.TestCase):
    def test_elapsed_time_accounts_for_timezone_offsets(self):
        self.assertEqual(metrics.duration("2026-11-01T12:00:00-08:00", "2026-11-01T20:01:15Z"), 75)

    def test_incomplete_job_has_no_fabricated_duration(self):
        self.assertIsNone(metrics.duration("2026-11-01T20:00:00Z", None))

    def test_failed_release_retains_failure_outcome_and_duration(self):
        class FixtureAPI:
            def __init__(self, repo):
                pass

            def api(self, endpoint):
                if endpoint.endswith("/jobs?per_page=100"):
                    return {"jobs": [{"name": "build", "conclusion": "failure",
                                      "started_at": "2026-11-01T20:00:00Z",
                                      "completed_at": "2026-11-01T20:01:00Z"}]}
                return {"created_at": "2026-11-01T20:00:00Z"}

        with tempfile.TemporaryDirectory() as temporary:
            directory = pathlib.Path(temporary)
            original = pathlib.Path.cwd()
            try:
                os.chdir(directory)
                with patch.dict("os.environ", {
                    "GITHUB_REPOSITORY": "owner/Glimpse", "GITHUB_SHA": "a" * 40,
                    "GITHUB_RUN_ID": "42", "GITHUB_RUN_ATTEMPT": "2",
                    "GITHUB_STEP_SUMMARY": str(directory / "summary.md"),
                    "JOB_RESULTS": json.dumps({"release-verified": {"result": "failure"},
                                               "build": {"result": "failure"}}),
                }), patch.object(metrics.control, "GitHub", FixtureAPI):
                    metrics.main()
            finally:
                os.chdir(original)
            record = json.loads((directory / "release-metrics.json").read_text())
            self.assertFalse(record["release_verified"])
            self.assertEqual(record["job_results"]["build"], "failure")
            self.assertEqual(record["jobs"][0]["duration_seconds"], 60)
            self.assertEqual(record["workflow_run_attempt"], 2)


if __name__ == "__main__":
    unittest.main()
