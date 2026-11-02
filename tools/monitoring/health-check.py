#!/usr/bin/env python3
"""Read-only, one-shot installed Glimpse observation; scheduling is external."""

import argparse
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from copy import deepcopy

EXECUTABLE = "/Applications/Glimpse.app/Contents/MacOS/Glimpse"
BUNDLE_ID = "com.rohit.Glimpse"
SCHEMA_VERSION = 1
LIMITATIONS = (
    "Crash evidence covers only retained Glimpse-named reports in the listed roots; "
    "no matching report does not establish crash-free operation. A missing process "
    "may reflect intentional quit. Login-item status and menu-item visibility are "
    "not queried. ps CPU is an OS estimate with no fixed sampling window; "
    "cpu_interval uses cumulative CPU deltas only for the same PID across checks."
)


def duration_seconds(value):
    """Accept macOS elapsed/CPU forms: [[days-]hours:]minutes:seconds[.fraction]."""
    days = 0
    if "-" in value:
        day_text, value = value.split("-", 1)
        days = int(day_text)
    parts = value.split(":")
    if not 1 <= len(parts) <= 3:
        raise ValueError("invalid process duration")
    seconds = 0.0
    for part in parts:
        seconds = seconds * 60 + float(part)
    seconds += days * 86400
    if not math.isfinite(seconds) or seconds < 0:
        raise ValueError("invalid process duration")
    return seconds


def parse_processes(text):
    """Filter exact executable path before retaining any process information."""
    result = []
    for line in text.splitlines():
        fields = line.strip().split(maxsplit=5)
        if len(fields) != 6:
            if EXECUTABLE in line:
                raise ValueError("malformed installed Glimpse process row")
            continue
        if fields[5] != EXECUTABLE:
            continue
        pid, elapsed, cpu_time, cpu_percent, rss, _ = fields
        item = {
            "pid": int(pid),
            "elapsed_seconds": int(duration_seconds(elapsed)),
            "cpu_seconds": duration_seconds(cpu_time),
            "cpu_percent": float(cpu_percent),
            "rss_bytes": int(rss) * 1024,
        }
        if (item["pid"] <= 0 or item["rss_bytes"] < 0
                or not math.isfinite(item["cpu_percent"]) or item["cpu_percent"] < 0):
            raise ValueError("invalid installed Glimpse process metrics")
        result.append(item)
    return sorted(result, key=lambda item: item["pid"])


def query_processes():
    try:
        response = subprocess.run(
            ["/bin/ps", "-ww", "-axo", "pid=,etime=,time=,%cpu=,rss=,comm="],
            capture_output=True, text=True, timeout=5, check=True,
        )
        processes = parse_processes(response.stdout)
        availability = "missing" if not processes else "running" if len(processes) == 1 else "duplicate"
        return {"availability": availability, "processes": processes, "errors": []}
    except (OSError, subprocess.SubprocessError, ValueError) as error:
        return {
            "availability": "unknown", "processes": [],
            "errors": [f"Installed process observation failed: {type(error).__name__}"],
        }


def parse_crash_report(text, path):
    """Accept only a matching production identity AND exact installed executable."""
    if path.suffix.lower() == ".ips":
        decoder = json.JSONDecoder()
        objects, rest = [], text.lstrip()
        while rest:
            item, end = decoder.raw_decode(rest)
            if not isinstance(item, dict):
                raise ValueError("crash report JSON object expected")
            objects.append(item)
            rest = rest[end:].lstrip()
        if not objects:
            raise ValueError("empty crash report")
        header, body = objects[0], objects[-1]
        name = body.get("procName", header.get("app_name"))
        bundle = body.get("bundleInfo", {}).get("CFBundleIdentifier", header.get("bundleID"))
        executable = body.get("procPath")
        exception = body.get("exception") or {}
        is_crash = str(header.get("bug_type")) == "309" or bool(exception)
        incident = body.get("incident") or body.get("incidentIdentifier") or header.get("incident_id")
        captured = body.get("captureTime") or header.get("timestamp")
        exception_type = exception.get("type")
        signal = exception.get("signal")
    else:
        def field(label):
            match = re.search(rf"^{re.escape(label)}:\s*(.*)$", text, re.MULTILINE)
            return match.group(1).strip() if match else None
        name = re.sub(r"\s+\[\d+\]$", "", field("Process") or "")
        bundle, executable = field("Identifier"), field("Path")
        incident, captured = field("Incident Identifier"), field("Date/Time")
        exception_type, signal = field("Exception Type"), None
        is_crash = bool(exception_type)

    if (executable != EXECUTABLE or not is_crash
            or (name is not None and name != "Glimpse")
            or (bundle is not None and bundle != BUNDLE_ID)
            or not (name == "Glimpse" or bundle == BUNDLE_ID)):
        return None
    identity = f"incident:{incident}" if incident else "sha256:" + hashlib.sha256(text.encode()).hexdigest()
    return {
        "id": identity, "file": str(path), "captured_at": captured,
        "exception_type": exception_type, "signal": signal,
    }


def scan_crash_reports(roots, max_files=250, max_bytes=8 * 1024 * 1024, timeout=8):
    """Bound file count, individual file size, and elapsed scan time."""
    errors, reports, root_info = [], {}, []
    candidate_count = scanned_count = excluded_count = 0
    deadline = time.monotonic() + timeout
    for root in roots:
        root = Path(root).expanduser()
        if not root.is_dir():
            root_info.append({"path": str(root), "available": False})
            errors.append(f"Report root unavailable: {root}")
            continue
        root_info.append({"path": str(root), "available": True})
        def walk_error(error):
            errors.append(f"Report directory unreadable: {error.filename}")
        exhausted = False
        for directory, _, names in os.walk(root, onerror=walk_error, followlinks=False):
            if time.monotonic() > deadline:
                errors.append("Crash scan elapsed-time limit reached")
                exhausted = True
                break
            for name in sorted(names):
                path = Path(directory) / name
                if not name.lower().startswith("glimpse") or path.suffix.lower() not in (".ips", ".crash"):
                    continue
                candidate_count += 1
                if scanned_count >= max_files or time.monotonic() > deadline:
                    errors.append("Crash scan file/time limit reached")
                    exhausted = True
                    break
                try:
                    if path.is_symlink():
                        raise ValueError("symlink report excluded")
                    if path.stat().st_size > max_bytes:
                        raise ValueError("report exceeds size limit")
                    with path.open("rb") as stream:
                        data = stream.read(max_bytes + 1)
                    if len(data) > max_bytes:
                        raise ValueError("report grew beyond size limit")
                    scanned_count += 1
                    parsed = parse_crash_report(data.decode("utf-8"), path)
                    if parsed:
                        reports.setdefault(parsed["id"], parsed)
                    else:
                        excluded_count += 1
                except (OSError, ValueError, TypeError, AttributeError) as error:
                    errors.append(f"Report not assessed: {path} ({type(error).__name__})")
                if len(errors) >= max_files:
                    errors.append("Crash scan error limit reached")
                    exhausted = True
                    break
            if exhausted:
                break
        if exhausted:
            break
    return {
        "complete": not errors, "roots": root_info, "candidate_count": candidate_count,
        "scanned_count": scanned_count, "excluded_count": excluded_count,
        "reports": sorted(reports.values(), key=lambda item: item["id"]), "errors": errors,
        "max_files": max_files, "max_report_bytes": max_bytes,
        "elapsed_limit_seconds": timeout,
    }


def evaluate(current, previous):
    """Produce deduplicated change events and the next persisted observation."""
    old = previous.get("snapshot") if previous else None
    events = []
    def event(kind, severity, message, **details):
        events.append({"kind": kind, "severity": severity, "message": message, **details})
    availability = current["availability"]
    changed = old is None or availability != old["availability"]
    if changed:
        if availability == "missing":
            event("process_missing", "warning", "Installed Glimpse process is absent; intentional quit is possible.")
        elif availability == "duplicate":
            event("duplicate_processes", "warning", "Multiple processes use the installed Glimpse executable.")
        elif availability == "running" and old:
            event("availability_recovered", "info", "Installed Glimpse process is running again.")

    same_instance = False
    if old and availability == old["availability"] == "running":
        new_process, old_process = current["processes"][0], old["processes"][0]
        same_instance = (
            new_process["pid"] == old_process["pid"]
            and new_process["elapsed_seconds"] >= old_process["elapsed_seconds"]
            and new_process["cpu_seconds"] >= old_process["cpu_seconds"]
        )
        if not same_instance:
            event("process_restarted", "info", "Installed Glimpse PID or lifetime counters changed between observations.")
    if old and current["installed"] != old["installed"]:
        event("installed_version_changed", "info", "Installed app version/build observation changed.")

    def issues(item):
        if not item:
            return set()
        result = set(item["errors"]) | set(item["crash_scan"]["errors"])
        if not item["crash_scan"]["complete"]:
            result.add("Crash scan incomplete")
        if item["availability"] == "unknown":
            result.add("Installed process status unknown")
        return result
    current_issues, old_issues = issues(current), issues(old)
    if current_issues and current_issues != old_issues:
        event("observation_incomplete", "warning", "Process, metadata, state, or crash evidence could not be fully observed.")
    elif not current_issues and old_issues:
        event("observation_recovered", "info", "The current observation completed after an incomplete check.")

    seen = set(previous.get("seen_crash_ids", [])) if previous else set()
    for report in current["crash_scan"]["reports"]:
        if old is not None and report["id"] not in seen:
            event("new_crash_report", "warning", "A newly observed report matches installed Glimpse.", report=report)
        seen.add(report["id"])

    interval = None
    if same_instance:
        new_process, old_process = current["processes"][0], old["processes"][0]
        seconds = current["observed_epoch"] - old["observed_epoch"]
        cpu_delta = new_process["cpu_seconds"] - old_process["cpu_seconds"]
        if seconds > 0:
            interval = {
                "pid": new_process["pid"], "seconds": seconds,
                "cpu_seconds": cpu_delta, "average_percent": 100 * cpu_delta / seconds,
            }
    result = {
        "schema_version": SCHEMA_VERSION, "executable": EXECUTABLE,
        **current, "cpu_interval": interval, "events": events, "notify": bool(events),
        "limitations": LIMITATIONS,
        "crash_baseline_initialized": old is None,
    }
    state = {
        "schema_version": SCHEMA_VERSION, "snapshot": deepcopy(current),
        "seen_crash_ids": sorted(seen),
    }
    return result, state


def read_state(path):
    if not path.exists():
        return None, None
    try:
        if path.stat().st_size > 2 * 1024 * 1024:
            raise ValueError("state file exceeds size limit")
        data = json.loads(path.read_text())
        if (data.get("schema_version") != SCHEMA_VERSION or not isinstance(data.get("snapshot"), dict)
                or not isinstance(data.get("seen_crash_ids"), list)):
            raise ValueError("unsupported state structure")
        old = data["snapshot"]
        for key in ("availability", "installed", "processes", "errors", "crash_scan", "observed_epoch"):
            if key not in old:
                raise ValueError("incomplete state")
        if old["availability"] in ("running", "duplicate") and not old["processes"]:
            raise ValueError("state is missing process metrics")
        if old["availability"] not in ("running", "duplicate", "missing", "unknown"):
            raise ValueError("invalid availability")
        if (not isinstance(old["observed_epoch"], (int, float))
                or not math.isfinite(old["observed_epoch"])):
            raise ValueError("invalid timestamp")
        if not isinstance(old["errors"], list) or not all(isinstance(value, str) for value in old["errors"]):
            raise ValueError("invalid errors")
        scan = old["crash_scan"]
        if (not isinstance(scan, dict) or not isinstance(scan.get("complete"), bool)
                or not isinstance(scan.get("errors"), list)
                or not all(isinstance(value, str) for value in scan["errors"])):
            raise ValueError("invalid crash scan state")
        if not isinstance(old["processes"], list):
            raise ValueError("invalid processes")
        for process in old["processes"]:
            for key in ("pid", "elapsed_seconds", "cpu_seconds", "cpu_percent", "rss_bytes"):
                value = process.get(key) if isinstance(process, dict) else None
                if not isinstance(value, (int, float)) or not math.isfinite(value) or value < 0:
                    raise ValueError("invalid process metric")
        if not all(isinstance(value, str) for value in data["seen_crash_ids"]):
            raise ValueError("invalid report identities")
        return data, None
    except (OSError, ValueError, TypeError, AttributeError) as error:
        return None, f"Previous monitor state unavailable: {type(error).__name__}"


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as stream:
            temporary = Path(stream.name)
            json.dump(data, stream, indent=2, sort_keys=True, allow_nan=False)
            stream.write("\n")
        os.replace(temporary, path)
    finally:
        if temporary and temporary.exists():
            temporary.unlink()


def main():
    default_dir = Path.home() / "Library/Application Support/Glimpse Monitoring"
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--state-file", type=Path, default=default_dir / "health-state.json")
    parser.add_argument("--output-file", type=Path, default=default_dir / "health-latest.json")
    args = parser.parse_args()
    repository = Path(__file__).resolve().parents[2]
    args.state_file = args.state_file.expanduser().resolve()
    args.output_file = args.output_file.expanduser().resolve()
    if (args.state_file == args.output_file
            or args.state_file.is_relative_to(repository)
            or args.output_file.is_relative_to(repository)):
        parser.error("State and output need distinct paths outside this repository")
    args.state_file.parent.mkdir(parents=True, exist_ok=True)
    with (args.state_file.parent / (args.state_file.name + ".lock")).open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print(json.dumps({"notify": False, "skipped": "another health check owns the state lock"}))
            return 0
        now = time.time()
        current = {
            "observed_at": datetime.fromtimestamp(now, timezone.utc).isoformat(),
            "observed_epoch": now, **query_processes(),
        }
        info = Path("/Applications/Glimpse.app/Contents/Info.plist")
        try:
            data = plistlib.loads(info.read_bytes())
            if data.get("CFBundleIdentifier") != BUNDLE_ID:
                raise ValueError("installed bundle identifier mismatch")
            current["installed"] = {
                "version": data.get("CFBundleShortVersionString"), "build": data.get("CFBundleVersion"),
            }
        except (OSError, ValueError, plistlib.InvalidFileException) as error:
            current["installed"] = None
            current["errors"].append(f"Installed metadata unavailable: {type(error).__name__}")
        current["crash_scan"] = scan_crash_reports([
            Path.home() / "Library/Logs/DiagnosticReports", Path("/Library/Logs/DiagnosticReports"),
        ])
        previous, state_error = read_state(args.state_file)
        if state_error:
            current["errors"].append(state_error)
        result, state = evaluate(current, previous)
        write_json(args.output_file, result)
        write_json(args.state_file, state)
        print(json.dumps(result, sort_keys=True, allow_nan=False))
        return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except OSError as error:
        print(json.dumps({
            "notify": True, "events": [{
                "kind": "monitor_failed", "severity": "warning",
                "message": f"Monitor could not persist its evidence: {type(error).__name__}",
            }],
        }))
        sys.exit(2)
