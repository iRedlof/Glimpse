#!/usr/bin/env python3
"""Retain private native PNGs after the gate's terminal isolated test command."""

import argparse
import hashlib
import json
import pathlib
import subprocess


VIEWPORT_METHOD = (
    "CalendarKeyboardOwnershipTests/focusedLogicalDateStaysVisibleInCappedViewport(maximumHeight:)"
)


def collect(staging, destination, host_executable, manifest, native_exit):
    receipt = {
        "staging_dir": str(staging), "destination": str(destination),
        "host_executable": str(host_executable), "native_exit_code": native_exit,
        "owned_host_absence_confirmed": False, "remaining_owned_pids": [],
        "preserve_staging": False, "copies": [], "errors": [],
    }
    try:
        # macOS may report /private/tmp for a gate launched through /tmp.
        owned_paths = {str(host_executable), str(host_executable.resolve())}
        # One fresh snapshot, matched only to this run's unique executable path.
        # A build failure before launch is valid absence; no log PID is required.
        result = subprocess.run(["ps", "-axww", "-o", "pid=,comm="], capture_output=True,
                                text=True, timeout=5, check=True)
        process_count = 0
        for row in result.stdout.splitlines():
            if not row.strip():
                continue
            pid, executable = row.strip().split(None, 1)
            if not pid.isdecimal() or int(pid) <= 0:
                raise ValueError("Invalid process identity")
            process_count += 1
            if executable in owned_paths:
                receipt["remaining_owned_pids"].append(int(pid))
        if process_count == 0:
            raise ValueError("Process snapshot contains no valid records")
        if receipt["remaining_owned_pids"]:
            raise ValueError("Owned native host remains; no artifact copy")
        receipt["owned_host_absence_confirmed"] = True
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        receipt["errors"].append(f"Owned host absence unproven: {error}")
        receipt["preserve_staging"] = True

    if receipt["owned_host_absence_confirmed"]:
        try:
            entries = sorted(staging.iterdir())
            destination.mkdir(exist_ok=True)
        except OSError as error:
            receipt["errors"].append(f"Artifact directories: {error}")
            receipt["preserve_staging"] = True
            entries = []
        for source in entries:
            try:
                if source.is_symlink() or not source.is_file() or source.suffix != ".png":
                    raise ValueError("Unexpected staging entry")
                data = source.read_bytes()
                if not data:
                    raise ValueError("Empty PNG")
                source_hash = hashlib.sha256(data).hexdigest()
                target = destination / source.name
                with target.open("xb") as output:
                    output.write(data)
                target_hash = hashlib.sha256(target.read_bytes()).hexdigest()
                if target_hash != source_hash:
                    raise ValueError("Durable PNG hash mismatch")
                receipt["copies"].append({
                    "source": str(source), "destination": str(target), "bytes": len(data),
                    "source_sha256": source_hash, "destination_sha256": target_hash,
                })
            except (OSError, ValueError) as error:
                receipt["errors"].append(f"{source.name}: {error}")
                receipt["preserve_staging"] = True

    # Older archives have no viewport bitmap contract. Native failures retain
    # every completed PNG without replacing the native exit with missing-output errors.
    if native_exit == 0:
        try:
            methods = json.loads(manifest.read_text())["methods"]
            if not isinstance(methods, dict):
                raise ValueError("Invalid method manifest")
            if VIEWPORT_METHOD in methods:
                expected = {
                    name for height in (312, 812)
                    for name in (f"viewport-{height}-before-assertions.png",
                                 f"expected-anchor-{height}-before-assertions.png",
                                 f"viewport-{height}.png")
                }
                copied = {pathlib.Path(row["destination"]).name for row in receipt["copies"]}
                missing = sorted(expected - copied)
                if missing:
                    receipt["errors"].append("Missing required viewport PNGs: " + ", ".join(missing))
        except (OSError, ValueError, KeyError, TypeError) as error:
            receipt["errors"].append(f"Viewport artifact requirement: {error}")
    receipt["exit_code"] = int(bool(receipt["errors"]))
    receipt["preserve_staging"] = bool(receipt["errors"])
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("staging", "destination", "host-executable", "manifest", "receipt", "retain-marker"):
        parser.add_argument("--" + name, type=pathlib.Path, required=True)
    parser.add_argument("--native-exit", type=int, required=True)
    args = parser.parse_args()
    receipt = collect(args.staging, args.destination, args.host_executable, args.manifest, args.native_exit)
    args.receipt.write_text(json.dumps(receipt, indent=2) + "\n")
    # The gate creates this marker before calling us. Unexpected collector or
    # receipt-write failure therefore cannot erase the only staged artifacts.
    if not receipt["preserve_staging"]:
        args.retain_marker.unlink()
    print(f"Keyboard artifacts: {len(receipt['copies'])} copied; {len(receipt['errors'])} errors")
    for error in receipt["errors"]:
        print(error)
    return receipt["exit_code"]


if __name__ == "__main__":
    raise SystemExit(main())
