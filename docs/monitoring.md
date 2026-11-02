# Glimpse runtime monitoring

`tools/monitoring/health-check.py` performs one read-only observation of the installed app. A Codex heartbeat or other explicitly configured scheduler can run it repeatedly and notify from its JSON events. The script does not install a recurring job or send notifications by itself.

## Run

Requires macOS and Python 3.9 or newer; uses only the standard library.

```sh
python3 tools/monitoring/health-check.py
```

The default files are outside Git:

- `~/Library/Application Support/Glimpse Monitoring/health-state.json` stores the prior observation and previously seen report identities.
- `~/Library/Application Support/Glimpse Monitoring/health-latest.json` stores the latest full result.

Override both paths when using a separate monitor or testing:

```sh
python3 tools/monitoring/health-check.py \
  --state-file /tmp/glimpse-qa/monitor/state.json \
  --output-file /tmp/glimpse-qa/monitor/latest.json
```

State and output paths must be distinct and outside the repository containing the script. Writes use temporary files and atomic replacement. A nonblocking file lock prevents concurrent checks from overwriting the same prior state.

Successful observations, including observed process absence, exit `0`. The JSON `availability`, `events`, and `notify` fields determine action. Persistence failures exit `2` with a `monitor_failed` event; argument errors also exit `2`. A concurrent check returns `notify: false` and a `skipped` reason.

## Scheduler notification contract

Inspect `notify` and `events`, and stay quiet when `notify` is false. Notify only for a meaningful event:

| Event | Meaning |
| --- | --- |
| `process_missing` | No process has the exact installed executable path. Intentional quit is possible; this does not establish a crash. |
| `duplicate_processes` | More than one process uses that exact executable. |
| `availability_recovered` | A running installed process is observed after another availability state. |
| `process_restarted` | PID changed or lifetime counters reset. A planned update/relaunch can cause this. |
| `installed_version_changed` | Installed version/build evidence changed. |
| `new_crash_report` | A report newly encountered after initialization matches production identity and executable path. |
| `observation_incomplete` | Process, metadata, state, or crash evidence is incomplete, or its set of errors changed. |
| `observation_recovered` | Observation errors cleared. |
| `monitor_failed` | The checker could not persist evidence. |

An unchanged missing or duplicate state does not repeatedly notify. Moving the same report into `Retired` does not generate another crash event. A healthy first run establishes a baseline and stays quiet; its already retained reports are recorded without labeling them new. A missing/duplicate/incomplete first run emits the relevant observation event.

A corrupted state file is reported explicitly before a new baseline is established. Baseline reset can limit historical deduplication, so keep the state file between runs. Separate automation instances need separate state paths.

When the user intentionally quits Glimpse or wants monitoring paused, pause the scheduler. **Never automatically relaunch the app or change its launch-at-login configuration.** The checker has no such actions.

## Observation scope and limits

The sole process match is:

```text
/Applications/Glimpse.app/Contents/MacOS/Glimpse
```

Development apps, test hosts, and other executables merely named `Glimpse` are excluded. The checker reads version/build only from `/Applications/Glimpse.app/Contents/Info.plist` and verifies `com.rohit.Glimpse`.

Retained reports are scanned recursively under user and system `Library/Logs/DiagnosticReports`, including `Retired`. Only Glimpse-named `.ips` and `.crash` files are read. A crash record must identify Glimpse by its exact process name or bundle identifier, reject any contradictory identity, and include the exact installed executable path. Test crashes with the same name and bundle identifier but a build-directory executable path are excluded.

The saved report summary contains the report path, stable incident/hash identity, capture time, exception type, and signal. It does not copy stack traces, application-specific data, queries, calendar records, unrelated process rows, or unrelated reports.

Each `ps` query has a five-second timeout. Each crash scan has an eight-second elapsed limit, a 250-report limit, and an 8 MiB per-file read limit. Missing/unreadable roots, malformed or oversized reports, and exhausted limits mark evidence incomplete; they are not treated as successful zero-crash observations. These limits bound normal local work; a blocking filesystem operation itself cannot be interrupted by the scanner's elapsed check.

The result always includes a `limitations` statement. No retained matching report establishes crash-free operation. The script does not query menu-item visibility or login-item disposition and does not invoke `sfltool` or request administrator credentials. Those observations remain separate manual checks; see `docs/qa-baseline.md`.

## Metrics

Each process record includes PID, elapsed seconds, cumulative CPU seconds, RSS bytes, and macOS `ps` CPU percentage. The latter is an OS estimate without a fixed sampling window and must not be described as a one-minute measurement.

From the second successful check onward, `cpu_interval` reports cumulative CPU used across the explicit interval between observations, only when PID and lifetime counters establish the same process instance:

```text
average_percent = 100 × change in cumulative CPU seconds / interval seconds
```

The interval is unavailable on the first check, after process replacement/counter reset, for duplicates, or after an observation-clock reversal. Cumulative CPU is rounded by `ps`, so short intervals have limited precision. RSS is an instantaneous resident-memory sample, not total or peak application memory.

The script records metrics without emitting an alert for every CPU/RSS fluctuation. Compare several observations after builds and interactions settle; investigate sustained CPU or continuing memory growth with a targeted process sample. Availability and crash evidence cannot be inferred from a CPU value of zero.

## Verify

```sh
python3 -m unittest discover -s tools/monitoring -p 'test_*.py' -v
```

The fixture suite covers exact process filtering, duplicates, missing/recovery and changed failures, bounded/unreadable crash evidence, production versus test reports, Retired deduplication, legacy report format, PID reuse, CPU windows, corrupted state, and atomic output. Tests do not start or stop applications or change macOS settings.

The 2026-11-01 live read-only run used `/tmp/glimpse-qa/monitor` and identified only installed PID 2805 at version 1.4.3/build 10. Its crash scan completed with zero retained production matches and emitted no notification. That run does not establish unattended reliability on another machine.
