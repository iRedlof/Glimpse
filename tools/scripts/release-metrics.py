#!/usr/bin/env python3
"""Preserve observable timing and failure/rollback outcomes for every release."""
import datetime
import importlib.util
import json
import os
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("release_control", ROOT / "tools/scripts/release-control.py")
control = importlib.util.module_from_spec(spec)
spec.loader.exec_module(control)
def duration(start, end):
    if not start or not end:
        return None
    return (datetime.datetime.fromisoformat(end.replace("Z", "+00:00")) -
            datetime.datetime.fromisoformat(start.replace("Z", "+00:00"))).total_seconds()


def main():
    repo = os.environ["GITHUB_REPOSITORY"]
    run_id = int(os.environ["GITHUB_RUN_ID"])
    github = control.GitHub(repo)
    run = github.api(f"repos/{repo}/actions/runs/{run_id}")
    jobs = github.api(f"repos/{repo}/actions/runs/{run_id}/jobs?per_page=100")["jobs"]
    results = json.loads(os.environ["JOB_RESULTS"])
    metrics = {
        "schema": 1, "repository": repo, "source_sha": os.environ["GITHUB_SHA"],
        "workflow_run_id": run_id, "workflow_run_attempt": int(os.environ["GITHUB_RUN_ATTEMPT"]),
        "created_at": run["created_at"],
        "elapsed_seconds": duration(run["created_at"], datetime.datetime.now(datetime.timezone.utc).isoformat()),
        "release_verified": results["release-verified"]["result"] == "success",
        "job_results": {name: result["result"] for name, result in results.items()},
        "jobs": [
            {"name": j["name"], "conclusion": j["conclusion"],
             "duration_seconds": duration(j.get("started_at"), j.get("completed_at"))}
            for j in jobs if j["name"] != "metrics"
        ],
    }
    pathlib.Path("release-metrics.json").write_text(json.dumps(metrics, indent=2) + "\n")
    with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as summary:
        summary.write(f"Source `{metrics['source_sha']}` · verified: **{metrics['release_verified']}**\n\n")
        summary.write("| Job | Result | Seconds |\n| --- | --- | --- |\n")
        for job in metrics["jobs"]:
            summary.write(f"| {job['name']} | {job['conclusion']} | {job['duration_seconds']} |\n")


if __name__ == "__main__":
    main()
