import json
import os
import pathlib
import shutil
import subprocess
import unittest

from ai_date_search_xcresult_fixture import EXPECTED, cases, fixture_directory, metadata
from keyboard_xcresult_fixture import current_suite

SCRIPTS = pathlib.Path(__file__).parents[1]
OPT_INS = ("GLIMPSE_CALENDAR_KEYBOARD_ACCEPTANCE", "TEST_RUNNER_GLIMPSE_CALENDAR_KEYBOARD_ACCEPTANCE")
PROBES = ("GLIMPSE_KEYBOARD_MECHANISM_PROBE", "TEST_RUNNER_GLIMPSE_KEYBOARD_MECHANISM_PROBE")
VIEWPORT_PNGS = (
    "viewport-312-before-assertions.png", "expected-anchor-312-before-assertions.png", "viewport-312.png",
    "viewport-812-before-assertions.png", "expected-anchor-812-before-assertions.png", "viewport-812.png",
)

# All native commands and process enumeration are substituted only at the external
# boundary. The actual proposed gate, checker and unchanged collector execute.
COMMAND_STUB = """#!/usr/bin/env python3
import json,os,pathlib,sys
command=pathlib.Path(sys.argv[0]).name
args=sys.argv[1:]
done=pathlib.Path(os.environ['FIXTURE_ROOT'])/'last-native.json'
phase=json.loads(done.read_text()) if done.exists() else None
entry={'command':command,'args':args,'cwd':os.getcwd(),'tmpdir':os.environ['TMPDIR'],
       'env':{key:os.environ.get(key) for key in (
           'GLIMPSE_CALENDAR_KEYBOARD_ACCEPTANCE','TEST_RUNNER_GLIMPSE_CALENDAR_KEYBOARD_ACCEPTANCE',
           'GLIMPSE_KEYBOARD_MECHANISM_PROBE','TEST_RUNNER_GLIMPSE_KEYBOARD_MECHANISM_PROBE')},
       'artifact_dir':os.environ.get('GLIMPSE_KEYBOARD_ARTIFACT_DIR'),
       'runner_artifact_dir':os.environ.get('TEST_RUNNER_GLIMPSE_KEYBOARD_ARTIFACT_DIR'),
       'workspace_mode':pathlib.Path(os.environ['TMPDIR']).parent.stat().st_mode & 0o777,
       'completed_phase':phase}
with open(os.environ['FIXTURE_TRACE'],'a') as trace:
    trace.write(json.dumps(entry)+'\\n')
options=json.loads(os.environ['FIXTURE_OPTIONS'])
if command=='ps':
    assert args==['-axww','-o','pid=,comm='] and phase in ('KEYBOARD','AI')
    state=options.get('host_state','absent') if phase=='AI' else 'absent'
    if state=='error':
        print('synthetic process query error',file=sys.stderr)
        sys.exit(2)
    if state=='empty':
        sys.exit(0)
    print('301 /Applications/Glimpse.app/Contents/MacOS/Glimpse')
    if state=='live':
        owned=pathlib.Path(os.environ['TMPDIR']).parent/'DerivedData/Build/Products/Debug/Glimpse.app/Contents/MacOS/Glimpse'
        print('302 '+str(owned))
    sys.exit(0)
if command=='xcrun':
    assert args[:3]==['xcresulttool','get','test-results'] and args[4]=='--path'
    bundles={'KeyboardOwnershipTests.xcresult':'keyboard','AIDateSearchIntegrationTests.xcresult':'ai'}
    suite=bundles[pathlib.Path(args[5]).name]
    assert args[3] in ('summary','tests')
    print((pathlib.Path(os.environ['FIXTURE_ROOT'])/(suite+'-'+args[3]+'.json')).read_text(),flush=True)
    print('synthetic '+suite+' '+args[3]+' diagnostic',file=sys.stderr,flush=True)
    sys.exit(options.get(args[3]+'_exit',0) if suite=='ai' else 0)
if command=='tee':
    text=sys.stdin.read()
    target=pathlib.Path(args[0]); target.write_text(text)
    print(text,end='',flush=True)
    sys.exit(options.get('log_exit',0) if target.name=='ai-date-search-integration-tests.log' else 0)
if command=='uname':
    assert args==['-m']
    print('arm64')
    sys.exit(0)
for flag in ('-derivedDataPath','--scratch-path','--cache-path'):
    if flag in args:
        directory=pathlib.Path(args[args.index(flag)+1])
        directory.mkdir(parents=True,exist_ok=True)
        (directory/'synthetic.txt').write_text('synthetic build output')
if '-resultBundlePath' in args:
    bundle=pathlib.Path(args[args.index('-resultBundlePath')+1])
    bundle.mkdir(parents=True); (bundle/'synthetic.txt').write_text('synthetic bundle')
    suites={'KeyboardOwnershipTests.xcresult':'KEYBOARD','AIDateSearchIntegrationTests.xcresult':'AI'}
    phase=suites.get(bundle.name,'APP')
    if phase=='KEYBOARD':
        staging=pathlib.Path(os.environ['GLIMPSE_KEYBOARD_ARTIFACT_DIR'])
        for name in json.loads(os.environ['FIXTURE_PNGS']):
            (staging/name).write_bytes(b'synthetic nonempty PNG fixture')
    if phase in ('KEYBOARD','AI'):
        done.write_text(json.dumps(phase))
    print('synthetic '+phase+' terminal output',flush=True)
    sys.exit(options.get('native_exit',0) if phase=='AI' else
             options.get('keyboard_exit',0) if phase=='KEYBOARD' else 0)
print('synthetic command output',flush=True)
"""


class AIDateSearchGateContracts(unittest.TestCase):
    def run_gate(self, *, pair=("file", "file"), keyboard=False, options=None,
                 ai_manifest=None, ai_tests=None):
        root = fixture_directory(self, "gate-")
        controller = root / "controller/tools/scripts"
        controller.mkdir(parents=True)
        for name in ("quality-gate.sh", "check-keyboard-xcresult.py", "collect-keyboard-artifacts.py"):
            shutil.copy2(SCRIPTS / name, controller / name)
        # A poisoned controller manifest proves that the archive owns membership.
        (controller / "ai-date-search-integration-methods.json").write_text('{"wrong":"controller"}\n')
        source = root / "archive"
        source_scripts = source / "tools/scripts"
        (source_scripts / "tests").mkdir(parents=True)
        (source / "tools/monitoring").mkdir()
        for directory in (source_scripts / "tests", source / "tools/monitoring"):
            (directory / "test_fixture.py").write_text(
                "import os,unittest\nclass Fixture(unittest.TestCase):\n"
                " def test_ordinary_opt_in_is_zero(self):\n"
                "  self.assertEqual(os.environ['GLIMPSE_CALENDAR_KEYBOARD_ACCEPTANCE'],'0')\n")
        (source / "GlimpseTests").mkdir()
        suite = source / "GlimpseTests/AIDateSearchIntegrationTests.swift"
        manifest = source_scripts / "ai-date-search-integration-methods.json"
        content = ("// synthetic presence only\n", json.dumps(EXPECTED if ai_manifest is None else ai_manifest))
        for path, kind, text in zip((suite, manifest), pair, content):
            if kind == "file":
                path.write_text(text)
            elif kind == "directory":
                path.mkdir()
            elif kind == "broken-link":
                path.symlink_to("missing-fixture")
            elif kind == "symlink":
                target = path.with_name(path.name + ".target")
                target.write_text(text)
                path.symlink_to(target)
            elif kind == "fifo":
                os.mkfifo(path)
            else:
                self.assertEqual(kind, "absent")
        keyboard_manifest, keyboard_summary, keyboard_tests = current_suite()
        if keyboard:
            (source / "Glimpse").mkdir()
            (source / "Glimpse/CalendarKeyboardFocus.swift").write_text("// synthetic presence\n")
            (source / "GlimpseTests/CalendarKeyboardOwnershipTests.swift").write_text("// synthetic presence\n")
        (source_scripts / "keyboard-ownership-methods.json").write_text(json.dumps(keyboard_manifest))
        ai_summary, default_ai_tests = metadata()
        for name, document in (("ai-summary", ai_summary), ("ai-tests", default_ai_tests if ai_tests is None else ai_tests),
                               ("keyboard-summary", keyboard_summary), ("keyboard-tests", keyboard_tests)):
            (root / (name + ".json")).write_text(json.dumps(document) + "\n")
        for name in ("release-control.py", "check-dependency-pins.py"):
            (source_scripts / name).write_text("print('synthetic source validation')\n")
        for relative in ("GlimpseCore/Package.resolved",
                         "Glimpse.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"):
            path = source / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('{"pins":[]}\n')
        bin_dir = root / "bin"; bin_dir.mkdir()
        for name in ("xcodebuild", "xcrun", "swift", "ps", "tee", "uname"):
            path = bin_dir / name
            path.write_text(COMMAND_STUB); path.chmod(0o755)
        inherited = root / "inherited"; inherited.mkdir()
        (inherited / "keep.txt").write_text("inherited\n")
        runner = root / "runner"; runner.mkdir()
        sibling = runner / "glimpse-quality.sibling"; sibling.mkdir()
        (sibling / "keep.txt").write_text("sibling\n")
        trace = root / "trace.jsonl"
        env = {**os.environ, "PATH": str(bin_dir) + os.pathsep + os.environ["PATH"],
               "GLIMPSE_BUILD_ROOT": str(root / "build"), "GLIMPSE_SOURCE_ROOT": str(source),
               "GLIMPSE_RESULTS_DIR": str(root / "results"), "RUNNER_TEMP": str(runner),
               "TMPDIR": str(inherited), "FIXTURE_ROOT": str(root), "FIXTURE_TRACE": str(trace),
               "FIXTURE_OPTIONS": json.dumps(options or {}), "FIXTURE_PNGS": json.dumps(VIEWPORT_PNGS),
               **{key: "1" for key in OPT_INS + PROBES}}
        env.pop("GITHUB_OUTPUT", None)
        command = ["bash", str(controller / "quality-gate.sh")]
        result = subprocess.run(command, env=env, text=True, capture_output=True, timeout=20)
        (root / "stdout.log").write_text(result.stdout); (root / "stderr.log").write_text(result.stderr)
        (root / "command.json").write_text(json.dumps(
            {"argv": command, "timeout_seconds": 20, "exit": result.returncode}, indent=2) + "\n")
        self.assertTrue(trace.is_file(), result.stdout + result.stderr)
        observed = [json.loads(line) for line in trace.read_text().splitlines()]
        derived = next(pathlib.Path(entry["args"][entry["args"].index("-derivedDataPath") + 1])
                       for entry in observed if "-derivedDataPath" in entry["args"])
        self.assertEqual((inherited / "keep.txt").read_text(), "inherited\n")
        self.assertEqual((sibling / "keep.txt").read_text(), "sibling\n")
        self.assertTrue(all(entry["workspace_mode"] == 0o700 for entry in observed))
        return result, root, root / "results", observed, derived.parent

    def receipt(self, results, name="ai-date-search-integration-acceptance.json"):
        path = results / name
        self.assertTrue(path.is_file(), f"missing retained receipt: {path}")
        return json.loads(path.read_text())

    def test_ai_runs_after_keyboard_collection_alone_and_before_core_with_bounded_flags(self):
        result, root, results, observed, workspace = self.run_gate(keyboard=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        native = [(index, entry) for index, entry in enumerate(observed)
                  if entry["command"] == "xcodebuild" and "-resultBundlePath" in entry["args"]]
        self.assertEqual(len(native), 3, "ordinary app, isolated keyboard, isolated AI required")
        app, keyboard, ai = (entry for _, entry in native)
        self.assertEqual(app["env"], {key: "0" for key in OPT_INS + PROBES})
        for entry, selected in ((keyboard, "CalendarKeyboardOwnershipTests"), (ai, "AIDateSearchIntegrationTests")):
            args = entry["args"]
            self.assertEqual([arg for arg in args if arg.startswith("-only-testing:")],
                             ["-only-testing:GlimpseTests/" + selected])
            for flag, value in (("-parallel-testing-enabled", "NO"), ("-test-timeouts-enabled", "YES"),
                                ("-default-test-execution-time-allowance", "30"),
                                ("-maximum-test-execution-time-allowance", "30"),
                                ("-destination", "platform=macOS,arch=arm64"), ("-configuration", "Debug")):
                self.assertEqual(args[args.index(flag) + 1], value)
            for flag in ("-skipMacroValidation", "-disableAutomaticPackageResolution",
                         "-onlyUsePackageVersionsFromResolvedFile", "ARCHS=arm64",
                         "ONLY_ACTIVE_ARCH=YES", "CODE_SIGNING_ALLOWED=NO"):
                self.assertIn(flag, args)
            self.assertEqual(entry["env"], {**{key: "1" for key in OPT_INS}, **{key: "0" for key in PROBES}})
            self.assertEqual(entry["artifact_dir"], entry["runner_artifact_dir"])
            self.assertEqual(pathlib.Path(entry["artifact_dir"]).parent, workspace)
        ai_index = native[-1][0]
        self.assertTrue(any(index < ai_index and entry["command"] == "ps"
                            and entry["completed_phase"] == "KEYBOARD" for index, entry in enumerate(observed)))
        self.assertEqual(sum(entry["command"] == "xcrun" and
                             "KeyboardOwnershipTests.xcresult" in " ".join(entry["args"])
                             for entry in observed[:ai_index]), 2)
        ai_ps = next(index for index, entry in enumerate(observed)
                     if entry["command"] == "ps" and entry["completed_phase"] == "AI")
        core_index = next(index for index, entry in enumerate(observed) if entry["command"] == "swift")
        self.assertLess(ai_index, ai_ps)
        self.assertLess(ai_ps, core_index)
        self.assertEqual(observed[core_index]["env"], {key: "0" for key in OPT_INS + PROBES})
        self.assertEqual(self.receipt(results)["methods"], EXPECTED["methods"])
        self.assertEqual(self.receipt(results)["executed_cases"], 18)
        self.assertEqual(self.receipt(results, "keyboard-ownership-acceptance.json")["executed_cases"], 16)
        self.assertFalse(workspace.exists())

    def test_empty_ai_png_staging_is_collected_with_absence_receipt_without_keyboard_images(self):
        result, root, results, observed, workspace = self.run_gate()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        receipt = self.receipt(results, "ai-date-search-integration-artifact-collection.json")
        self.assertTrue(receipt["owned_host_absence_confirmed"])
        self.assertEqual(receipt["copies"], [])
        self.assertFalse(receipt["preserve_staging"])
        self.assertEqual(receipt["exit_code"], 0)
        self.assertEqual(list((results / "ai-date-search-integration-artifacts").iterdir()), [])
        self.assertEqual(self.receipt(results)["methods"], EXPECTED["methods"])
        self.assertFalse(workspace.exists())
        self.assertEqual((results / "dependency-pins.before.sha256").read_text(),
                         (results / "dependency-pins.after.sha256").read_text())

    def test_legacy_pair_both_absent_is_not_applicable_and_never_selects_ai(self):
        result, root, results, observed, workspace = self.run_gate(pair=("absent", "absent"))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        receipt = self.receipt(results)
        self.assertEqual(receipt["status"], "NotApplicable")
        self.assertIn("Legacy archive", receipt["reason"])
        self.assertFalse(any("-only-testing:GlimpseTests/AIDateSearchIntegrationTests" in entry["args"]
                             for entry in observed))
        self.assertTrue(any(entry["command"] == "swift" for entry in observed))
        self.assertFalse(workspace.exists())

    def test_partial_broken_directory_symlink_or_fifo_pair_fails_before_native_ai(self):
        pairs = (("file", "absent"), ("absent", "file"), ("broken-link", "absent"),
                 ("absent", "broken-link"), ("broken-link", "broken-link"), ("directory", "file"),
                 ("file", "directory"), ("symlink", "file"), ("file", "symlink"),
                 ("fifo", "file"), ("file", "fifo"))
        for pair in pairs:
            with self.subTest(pair=pair):
                result, root, results, observed, workspace = self.run_gate(pair=pair)
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertEqual(self.receipt(results)["status"], "Failed")
                self.assertFalse(any("-only-testing:GlimpseTests/AIDateSearchIntegrationTests" in entry["args"]
                                     for entry in observed))
                self.assertFalse(any(entry["command"] == "swift" for entry in observed))
                self.assertFalse(workspace.exists())

    def test_every_pipeline_exit_retains_metadata_receipt_and_stops_before_core(self):
        for field, code in (("native_exit", 65), ("log_exit", 7), ("summary_exit", 8), ("tests_exit", 9)):
            with self.subTest(field=field):
                result, root, results, observed, workspace = self.run_gate(options={field: code})
                self.assertEqual(result.returncode, code, result.stdout + result.stderr)
                receipt = self.receipt(results)
                self.assertEqual(receipt["status"], "Failed")
                self.assertEqual(receipt["command_exits"][{"native_exit": "xcodebuild", "log_exit": "log",
                                                           "summary_exit": "summary", "tests_exit": "tests"}[field]], code)
                for name in ("tests.log", "summary.json", "tests.json", "xcresult.log",
                             "artifact-collection.json", "artifact-collection.log"):
                    self.assertTrue((results / ("ai-date-search-integration-" + name)).is_file())
                self.assertIn("synthetic AI terminal output", (results / "ai-date-search-integration-tests.log").read_text())
                self.assertIn("diagnostic", (results / "ai-date-search-integration-xcresult.log").read_text())
                self.assertFalse(any(entry["command"] == "swift" for entry in observed))
                self.assertFalse(workspace.exists())

    def test_owned_host_live_or_unknown_retains_private_marker_and_fails(self):
        for state in ("live", "error", "empty"):
            with self.subTest(state=state):
                result, root, results, observed, workspace = self.run_gate(options={"host_state": state})
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                collection = self.receipt(results, "ai-date-search-integration-artifact-collection.json")
                self.assertFalse(collection["owned_host_absence_confirmed"])
                self.assertTrue(collection["preserve_staging"])
                self.assertTrue(collection["errors"])
                self.assertTrue((workspace / "retain-ai-date-search-integration-artifacts").is_file())
                self.assertTrue((workspace / "ai-date-search-integration-artifacts").is_dir())
                self.assertFalse(any(entry["command"] == "swift" for entry in observed))
                # A strict metadata pass alone cannot override collector/host failure.
                self.assertEqual(self.receipt(results)["status"], "Passed")

    def test_missing_argument_cannot_pass_the_gate_even_when_native_exits_zero(self):
        _, tests = metadata()
        cases(tests)[0]["children"].pop()
        result, root, results, observed, workspace = self.run_gate(ai_tests=tests)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        receipt = self.receipt(results)
        self.assertEqual(receipt["status"], "Failed")
        self.assertIn("Missing or unexpected parameter execution", receipt["errors"])
        self.assertFalse(any(entry["command"] == "swift" for entry in observed))
        self.assertTrue((results / "AIDateSearchIntegrationTests.xcresult/synthetic.txt").is_file())

    def test_keyboard_failure_prevents_any_ai_host_or_core_phase(self):
        result, root, results, observed, workspace = self.run_gate(keyboard=True, options={"keyboard_exit": 65})
        self.assertEqual(result.returncode, 65, result.stdout + result.stderr)
        self.assertEqual(self.receipt(results, "keyboard-ownership-acceptance.json")["status"], "Failed")
        self.assertFalse(any("-only-testing:GlimpseTests/AIDateSearchIntegrationTests" in entry["args"]
                             for entry in observed))
        self.assertFalse(any(entry["command"] == "swift" for entry in observed))
        self.assertFalse(workspace.exists())


if __name__ == "__main__":
    unittest.main()
