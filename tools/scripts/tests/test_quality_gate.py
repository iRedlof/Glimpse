import hashlib
import json
import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest

from keyboard_xcresult_fixture import METHOD_IDS, cases, current_suite, manifest, parameterized, summary, tree

SCRIPTS = pathlib.Path(__file__).parents[1]
VIEWPORT_PNGS = (
    "viewport-312-before-assertions.png", "expected-anchor-312-before-assertions.png", "viewport-312.png",
    "viewport-812-before-assertions.png", "expected-anchor-812-before-assertions.png", "viewport-812.png",
)


class LocalQualityContracts(unittest.TestCase):
    def run_workspace_fixture(self, app_status=0, explicit_results=False, use_runner_temp=True,
                              keyboard="neither", keyboard_status=0, summary_status=0,
                              tests_status=0, tee_status=0, keyboard_manifest=None, keyboard_summary=None,
                              keyboard_tests=None, bitmap_names=VIEWPORT_PNGS, host_state="absent",
                              artifact_collision=False):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = pathlib.Path(temporary.name).resolve()
        scripts = root / "controller/tools/scripts"
        scripts.mkdir(parents=True)
        source = root / "archived-source"
        source_scripts = source / "tools/scripts"
        (source_scripts / "tests").mkdir(parents=True)
        (source_scripts.parent / "monitoring").mkdir()
        for directory in (source_scripts / "tests", source_scripts.parent / "monitoring"):
            (directory / "test_fixture.py").write_text(
                "import unittest\nclass Fixture(unittest.TestCase):\n def test_available(self): self.assertTrue(True)\n"
            )
        shutil.copy(SCRIPTS / "quality-gate.sh", scripts)
        collector = SCRIPTS / "collect-keyboard-artifacts.py"
        if collector.exists():
            shutil.copy(collector, scripts)
        checker = SCRIPTS / "check-keyboard-xcresult.py"
        if checker.exists():
            shutil.copy(checker, scripts)
        if keyboard in ("both", "production"):
            (source / "Glimpse").mkdir()
            (source / "Glimpse/CalendarKeyboardFocus.swift").write_text("// fixture presence\n")
        if keyboard == "broken-link":
            (source / "Glimpse").mkdir()
            (source / "Glimpse/CalendarKeyboardFocus.swift").symlink_to("missing-focus.swift")
        if keyboard in ("both", "suite"):
            (source / "GlimpseTests").mkdir()
            (source / "GlimpseTests/CalendarKeyboardOwnershipTests.swift").write_text("// fixture presence\n")
        (source_scripts / "keyboard-ownership-methods.json").write_text(
            json.dumps(manifest() if keyboard_manifest is None else keyboard_manifest)
        )
        raw_summary, raw_tests = root / "summary.json", root / "tests.json"
        raw_summary.write_text(json.dumps(summary() if keyboard_summary is None else keyboard_summary))
        raw_tests.write_text(json.dumps(tree() if keyboard_tests is None else keyboard_tests))
        for name in ("release-control.py", "check-dependency-pins.py"):
            (source_scripts / name).write_text("print('fixture source validation passed')\n")
        lockfiles = (source / "GlimpseCore/Package.resolved",
                     source / "Glimpse.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")
        for path in lockfiles:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('{"pins":[]}\n')
        durable = root / "external"
        inherited_temp = durable / "tmp"
        inherited_temp.mkdir(parents=True)
        (inherited_temp / "keep.txt").write_text("inherited temp remains\n")
        runner_temp = root / "runner-temp"
        sibling = runner_temp / "glimpse-quality.sibling"
        sibling.mkdir(parents=True)
        (sibling / "keep.txt").write_text("other workspace remains\n")
        bin_dir = root / "bin"
        bin_dir.mkdir()
        trace = root / "observed.jsonl"
        for name in ("xcodebuild", "swift", "xcrun", "ps"):
            path = bin_dir / name
            path.write_text("""#!/usr/bin/env python3
import json,os,pathlib,sys
args=sys.argv[1:]
with open(os.environ['FIXTURE_TRACE'], 'a') as trace:
    trace.write(json.dumps({'command':pathlib.Path(sys.argv[0]).name,
                            'args':args,'cwd':os.getcwd(),'tmpdir':os.environ['TMPDIR'],
                            'env':{key:os.environ.get(key) for key in (
                                'GLIMPSE_CALENDAR_KEYBOARD_ACCEPTANCE',
                                'TEST_RUNNER_GLIMPSE_CALENDAR_KEYBOARD_ACCEPTANCE',
                                'GLIMPSE_KEYBOARD_MECHANISM_PROBE',
                                'TEST_RUNNER_GLIMPSE_KEYBOARD_MECHANISM_PROBE')},
                            'artifact_dir':os.environ.get('GLIMPSE_KEYBOARD_ARTIFACT_DIR'),
                            'test_runner_artifact_dir':os.environ.get('TEST_RUNNER_GLIMPSE_KEYBOARD_ARTIFACT_DIR'),
                            'workspace_mode':pathlib.Path(os.environ['TMPDIR']).parent.stat().st_mode & 0o777})+'\\n')
if pathlib.Path(sys.argv[0]).name == 'ps':
    assert args == ['-axww','-o','pid=,comm=']
    assert pathlib.Path(os.environ['FIXTURE_NATIVE_DONE']).is_file(), 'checked before native terminal'
    state=os.environ['FIXTURE_HOST_STATE']
    if state == 'error':
        print('fixture process query failed',file=sys.stderr)
        sys.exit(2)
    if state == 'empty':
        sys.exit(0)
    print('301 /Applications/Glimpse.app/Contents/MacOS/Glimpse')
    if state == 'live':
        owned=pathlib.Path(os.environ['TMPDIR']).parent/'DerivedData/Build/Products/Debug/Glimpse.app/Contents/MacOS/Glimpse'
        print('302 '+str(owned))
    sys.exit(0)
if pathlib.Path(sys.argv[0]).name == 'xcrun':
    assert args[:3] == ['xcresulttool','get','test-results']
    assert args[3] in ('summary','tests') and args[4] == '--path'
    assert pathlib.Path(args[5]).name == 'KeyboardOwnershipTests.xcresult'
    raw=pathlib.Path(os.environ['FIXTURE_'+args[3].upper()])
    print(raw.read_text(),flush=True)
    print('fixture extraction diagnostic',file=sys.stderr,flush=True)
    sys.exit(int(os.environ['FIXTURE_'+args[3].upper()+'_STATUS']))
for flag in ('-derivedDataPath','--scratch-path','--cache-path'):
    if flag in args:
        directory=pathlib.Path(args[args.index(flag)+1])
        directory.mkdir(parents=True,exist_ok=True)
        (directory/'fixture.txt').write_text('generated build/cache data\\n')
if '-resultBundlePath' in args:
    assert 'CODE_SIGNING_ALLOWED=NO' in args
    bundle=pathlib.Path(args[args.index('-resultBundlePath')+1])
    bundle.mkdir(parents=True)
    (bundle/'fixture.txt').write_text('test result evidence\\n')
    print('app fixture output',flush=True)
    phase='KEYBOARD' if bundle.name == 'KeyboardOwnershipTests.xcresult' else 'APP'
    if phase == 'KEYBOARD':
        artifact_dir=pathlib.Path(os.environ['GLIMPSE_KEYBOARD_ARTIFACT_DIR'])
        artifact_dir.mkdir(parents=True,exist_ok=True)
        for name in json.loads(os.environ['FIXTURE_BITMAP_NAMES']):
            (artifact_dir/name).write_bytes(bytes.fromhex('89504e470d0a1a0a')+name.encode())
        if os.environ['FIXTURE_ARTIFACT_COLLISION'] == '1':
            destination=bundle.parent/'keyboard-ownership-artifacts'
            destination.mkdir(exist_ok=True)
            (destination/'viewport-312.png').write_text('existing durable evidence')
        pathlib.Path(os.environ['FIXTURE_NATIVE_DONE']).write_text('native command reached terminal exit')
    sys.exit(int(os.environ['FIXTURE_'+phase+'_STATUS']))
print('fixture command output',flush=True)
""")
            path.chmod(0o755)
        tee = bin_dir / "tee"
        tee.write_text("""#!/usr/bin/env python3
import os,pathlib,sys
output=pathlib.Path(sys.argv[1])
text=sys.stdin.read()
output.write_text(text)
print(text,end='',flush=True)
if output.name == 'keyboard-ownership-tests.log':
    sys.exit(int(os.environ['FIXTURE_TEE_STATUS']))
""")
        tee.chmod(0o755)
        env = {**os.environ, "PATH": str(bin_dir) + os.pathsep + os.environ["PATH"],
               "GLIMPSE_BUILD_ROOT": str(durable), "GLIMPSE_SOURCE_ROOT": str(source),
               "RUNNER_TEMP": str(runner_temp), "TMPDIR": str(inherited_temp),
               "GITHUB_OUTPUT": str(root / "github-output"),
               "FIXTURE_TRACE": str(trace), "FIXTURE_APP_STATUS": str(app_status),
               "FIXTURE_KEYBOARD_STATUS": str(keyboard_status),
               "FIXTURE_TEE_STATUS": str(tee_status),
               "FIXTURE_BITMAP_NAMES": json.dumps(list(bitmap_names)),
               "FIXTURE_HOST_STATE": host_state,
               "FIXTURE_NATIVE_DONE": str(root / "native-done"),
               "FIXTURE_ARTIFACT_COLLISION": str(int(artifact_collision)),
               "FIXTURE_SUMMARY_STATUS": str(summary_status), "FIXTURE_TESTS_STATUS": str(tests_status),
               "FIXTURE_SUMMARY": str(raw_summary), "FIXTURE_TESTS": str(raw_tests),
               "GLIMPSE_CALENDAR_KEYBOARD_ACCEPTANCE": "1",
               "TEST_RUNNER_GLIMPSE_CALENDAR_KEYBOARD_ACCEPTANCE": "1",
               "GLIMPSE_KEYBOARD_MECHANISM_PROBE": "1",
               "TEST_RUNNER_GLIMPSE_KEYBOARD_MECHANISM_PROBE": "1"}
        env.pop("GLIMPSE_RESULTS_DIR", None)
        if not use_runner_temp:
            env.pop("RUNNER_TEMP", None)
        if explicit_results:
            env["GLIMPSE_RESULTS_DIR"] = str(durable / "supplied-results")
        result = subprocess.run(["bash", str(scripts / "quality-gate.sh")], env=env,
                                text=True, capture_output=True, timeout=20)
        result_dir = pathlib.Path((root / "github-output").read_text().strip().split("=", 1)[1])
        observed = [json.loads(line) for line in trace.read_text().splitlines()]
        derived = next(pathlib.Path(entry["args"][entry["args"].index("-derivedDataPath") + 1])
                       for entry in observed if "-derivedDataPath" in entry["args"])
        return result, root, source, durable, runner_temp, result_dir, observed, derived.parent

    def assert_workspace_cleanup(self, root, runner_temp, workspace, observed, work_root=None):
        self.assertFalse(workspace.exists(), f"generated workspace leaked: {workspace}")
        self.assertEqual(workspace.parent, work_root or runner_temp)
        self.assertTrue(all(pathlib.Path(entry["tmpdir"]).parent == workspace for entry in observed))
        self.assertTrue(all(entry["workspace_mode"] == 0o700 for entry in observed))
        self.assertEqual((runner_temp / "glimpse-quality.sibling/keep.txt").read_text(),
                         "other workspace remains\n")
        self.assertEqual((root / "external/tmp/keep.txt").read_text(), "inherited temp remains\n")

    def test_success_cleans_private_workspace_and_retains_durable_evidence(self):
        for explicit_results in (False, True):
            with self.subTest(explicit_results=explicit_results):
                result, root, source, durable, runner_temp, results, observed, workspace = (
                    self.run_workspace_fixture(explicit_results=explicit_results)
                )
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assert_workspace_cleanup(root, runner_temp, workspace, observed)
                self.assertEqual(results.parent, durable)
                self.assertEqual((results / "AppTests.xcresult/fixture.txt").read_text(),
                                 "test result evidence\n")
                for name in ("resolve.log", "app-tests.log", "core-tests.log"):
                    self.assertTrue((results / name).read_text())
                self.assertEqual((results / "dependency-pins.before.sha256").read_text(),
                                 (results / "dependency-pins.after.sha256").read_text())
                app = next(entry for entry in observed if "-resultBundlePath" in entry["args"])
                core = next(entry for entry in observed if entry["command"] == "swift")
                self.assertEqual(pathlib.Path(app["cwd"]), source)
                self.assertEqual(pathlib.Path(core["cwd"]), source / "GlimpseCore")
                self.assertEqual(pathlib.Path(core["args"][core["args"].index("--scratch-path") + 1]),
                                 workspace / "core")
                self.assertEqual(pathlib.Path(core["args"][core["args"].index("--cache-path") + 1]),
                                 durable / "swiftpm-cache")
                self.assertTrue((durable / "swiftpm-cache/fixture.txt").is_file())
                self.assertEqual((source / "GlimpseCore/Package.resolved").read_text(), '{"pins":[]}\n')

    def test_app_failure_cleans_workspace_and_retains_partial_results(self):
        for explicit_results in (False, True):
            with self.subTest(explicit_results=explicit_results):
                result, root, source, durable, runner_temp, results, observed, workspace = (
                    self.run_workspace_fixture(app_status=42, explicit_results=explicit_results)
                )
                self.assertEqual(result.returncode, 42, result.stdout + result.stderr)
                self.assert_workspace_cleanup(root, runner_temp, workspace, observed)
                self.assertEqual(results.parent, durable)
                self.assertEqual((results / "AppTests.xcresult/fixture.txt").read_text(),
                                 "test result evidence\n")
                self.assertIn("app fixture output", (results / "app-tests.log").read_text())
                self.assertTrue((results / "resolve.log").read_text())
                self.assertIn("GlimpseCore/Package.resolved",
                              (results / "dependency-pins.before.sha256").read_text())
                self.assertFalse(any(entry["command"] == "swift" for entry in observed))
                self.assertEqual((source / "GlimpseCore/Package.resolved").read_text(), '{"pins":[]}\n')

    def test_without_runner_temp_uses_system_tmp_and_ignores_inherited_tmpdir(self):
        result, root, source, durable, runner_temp, results, observed, workspace = (
            self.run_workspace_fixture(use_runner_temp=False)
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assert_workspace_cleanup(root, runner_temp, workspace, observed, work_root=pathlib.Path("/tmp"))
        self.assertEqual(results.parent, durable)
        self.assertTrue((results / "AppTests.xcresult/fixture.txt").is_file())

    def test_repeated_local_quality_uses_distinct_result_bundles(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            scripts = root / "tools/scripts"
            scripts.mkdir(parents=True)
            (scripts / "tests").mkdir()
            (root / "tools/monitoring").mkdir()
            for directory in (scripts / "tests", root / "tools/monitoring"):
                (directory / "test_fixture.py").write_text(
                    "import unittest\nclass Fixture(unittest.TestCase):\n def test_available(self): self.assertTrue(True)\n"
                )
            (root / "GlimpseCore").mkdir()
            lockfiles = (root / "GlimpseCore/Package.resolved",
                         root / "Glimpse.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")
            for path in lockfiles:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('{"pins":[]}\n')
            shutil.copy(SCRIPTS / "quality-gate.sh", scripts / "quality-gate.sh")
            for name in ("release-control.py", "check-dependency-pins.py"):
                (scripts / name).write_text("print('fixture source validation passed')\n")
            bin_dir = root / "bin"
            bin_dir.mkdir()
            for name in ("swift", "git"):
                path = bin_dir / name
                path.write_text("#!/bin/bash\nexit 0\n")
                path.chmod(0o755)
            xcode = bin_dir / "xcodebuild"
            xcode.write_text("""#!/usr/bin/env python3
import pathlib,sys
assert '-resultBundlePath' not in sys.argv or 'CODE_SIGNING_ALLOWED=NO' in sys.argv
if '-resultBundlePath' in sys.argv:
    path=pathlib.Path(sys.argv[sys.argv.index('-resultBundlePath')+1])
    if path.exists(): sys.exit(1)
    path.mkdir(parents=True)
""")
            xcode.chmod(0o755)
            env = {**os.environ, "PATH": str(bin_dir) + os.pathsep + os.environ["PATH"]}
            env.pop("GLIMPSE_RESULTS_DIR", None)
            env.pop("GLIMPSE_BUILD_ROOT", None)
            env.pop("GLIMPSE_SOURCE_ROOT", None)
            env.pop("GITHUB_OUTPUT", None)
            env["RUNNER_TEMP"] = str(root / "runner-temp")
            for attempt in range(2):
                result = subprocess.run(["bash", str(scripts / "quality-gate.sh")], env=env,
                                        text=True, capture_output=True, timeout=20)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(len(list((root / "build").rglob("AppTests.xcresult"))), 2)

    def test_lockfile_mutation_in_archived_source_fails(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            scripts = root / "controller/tools/scripts"
            scripts.mkdir(parents=True)
            source = root / "archived-source"
            source_scripts = source / "tools/scripts"
            (source_scripts / "tests").mkdir(parents=True)
            (source_scripts.parent / "monitoring").mkdir()
            for directory in (source_scripts / "tests", source_scripts.parent / "monitoring"):
                (directory / "test_fixture.py").write_text(
                    "import unittest\nclass Fixture(unittest.TestCase):\n def test_available(self): self.assertTrue(True)\n"
                )
            lockfiles = (source / "GlimpseCore/Package.resolved",
                         source / "Glimpse.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")
            for path in lockfiles:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("original\n")
            shutil.copy(SCRIPTS / "quality-gate.sh", scripts)
            for name in ("release-control.py", "check-dependency-pins.py"):
                (source_scripts / name).write_text("print('source validation passed')\n")
            bin_dir = root / "bin"
            bin_dir.mkdir()
            for name in ("git", "xcodebuild"):
                path = bin_dir / name
                path.write_text("#!/bin/bash\nexit 0\n")
                path.chmod(0o755)
            swift = bin_dir / "swift"
            swift.write_text("#!/bin/bash\nprintf 'mutated\\n' > Package.resolved\n")
            swift.chmod(0o755)
            env = {**os.environ, "PATH": str(bin_dir) + os.pathsep + os.environ["PATH"],
                   "GLIMPSE_SOURCE_ROOT": str(source), "GLIMPSE_BUILD_ROOT": str(root / "external"),
                   "RUNNER_TEMP": str(root / "runner-temp")}
            env.pop("GLIMPSE_RESULTS_DIR", None)
            env.pop("GITHUB_OUTPUT", None)
            result = subprocess.run(
                ["bash", str(scripts / "quality-gate.sh")],
                env=env,
                text=True, capture_output=True, timeout=20,
            )
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("dependency-pins.before.sha256", result.stdout + result.stderr)

    def test_ordinary_app_disables_inherited_keyboard_opt_ins(self):
        result, _, _, _, _, _, observed, _ = self.run_workspace_fixture()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        app = next(entry for entry in observed if "-resultBundlePath" in entry["args"])
        self.assertEqual(app["env"], {
            "GLIMPSE_CALENDAR_KEYBOARD_ACCEPTANCE": "0",
            "TEST_RUNNER_GLIMPSE_CALENDAR_KEYBOARD_ACCEPTANCE": "0",
            "GLIMPSE_KEYBOARD_MECHANISM_PROBE": "0",
            "TEST_RUNNER_GLIMPSE_KEYBOARD_MECHANISM_PROBE": "0",
        })

    def test_keyboard_phase_is_isolated_serial_locked_and_retains_verified_evidence(self):
        result, root, source, _, runner_temp, results, observed, workspace = (
            self.run_workspace_fixture(keyboard="both")
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assert_workspace_cleanup(root, runner_temp, workspace, observed)
        app_runs = [entry for entry in observed if "-resultBundlePath" in entry["args"]]
        self.assertEqual(len(app_runs), 2)
        keyboard = app_runs[1]
        args = keyboard["args"]
        self.assertEqual(pathlib.Path(keyboard["cwd"]), source)
        self.assertEqual(keyboard["env"], {
            "GLIMPSE_CALENDAR_KEYBOARD_ACCEPTANCE": "1",
            "TEST_RUNNER_GLIMPSE_CALENDAR_KEYBOARD_ACCEPTANCE": "1",
            "GLIMPSE_KEYBOARD_MECHANISM_PROBE": "0",
            "TEST_RUNNER_GLIMPSE_KEYBOARD_MECHANISM_PROBE": "0",
        })
        for flag, value in (("-configuration", "Debug"), ("-parallel-testing-enabled", "NO"),
                            ("-test-timeouts-enabled", "YES"),
                            ("-default-test-execution-time-allowance", "30"),
                            ("-maximum-test-execution-time-allowance", "30")):
            self.assertEqual(args[args.index(flag) + 1], value)
        arch = os.uname().machine
        self.assertEqual(args[args.index("-destination") + 1], f"platform=macOS,arch={arch}")
        for flag in ("-skipMacroValidation", "-disableAutomaticPackageResolution",
                     "-onlyUsePackageVersionsFromResolvedFile", "CODE_SIGNING_ALLOWED=NO",
                     "ONLY_ACTIVE_ARCH=YES", f"ARCHS={arch}", "test"):
            self.assertIn(flag, args)
        selectors = [arg for arg in args if arg.startswith("-only-testing:")]
        self.assertEqual(selectors, ["-only-testing:GlimpseTests/CalendarKeyboardOwnershipTests"])
        self.assertEqual(pathlib.Path(args[args.index("-derivedDataPath") + 1]),
                         workspace / "DerivedData")
        self.assertEqual(pathlib.Path(args[args.index("-resultBundlePath") + 1]),
                         results / "KeyboardOwnershipTests.xcresult")
        self.assertTrue((results / "KeyboardOwnershipTests.xcresult/fixture.txt").is_file())
        for name in ("keyboard-ownership-tests.log", "keyboard-ownership-summary.json",
                     "keyboard-ownership-tests.json", "keyboard-ownership-xcresult.log"):
            self.assertTrue((results / name).read_text())
        receipt = json.loads((results / "keyboard-ownership-acceptance.json").read_text())
        self.assertEqual(receipt["status"], "Passed")
        self.assertEqual(receipt["executed_cases"], 6)
        self.assertEqual(set(receipt["methods"]), set(METHOD_IDS))
        self.assertTrue(any(entry["command"] == "swift" for entry in observed))

    def test_legacy_archive_requires_both_keyboard_files_absent(self):
        result, _, _, _, _, results, observed, _ = self.run_workspace_fixture()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        receipt = results / "keyboard-ownership-acceptance.json"
        self.assertTrue(receipt.is_file())
        self.assertEqual(json.loads(receipt.read_text())["status"], "NotApplicable")
        self.assertFalse(any(entry["command"] == "xcrun" for entry in observed))
        self.assertEqual(sum("-resultBundlePath" in entry["args"] for entry in observed), 1)

    def test_deleting_either_keyboard_file_cannot_bypass_admission(self):
        for presence in ("production", "suite", "broken-link"):
            with self.subTest(presence=presence):
                result, _, _, _, _, results, observed, _ = self.run_workspace_fixture(keyboard=presence)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(any(entry["command"] == "swift" for entry in observed))
                receipt = json.loads((results / "keyboard-ownership-acceptance.json").read_text())
                self.assertEqual(receipt["status"], "Failed")

    def test_keyboard_and_extraction_failures_preserve_exact_exit_and_partial_evidence(self):
        for arguments, status in (({"keyboard_status": 65}, 65),
                                  ({"summary_status": 43}, 43), ({"tests_status": 44}, 44),
                                  ({"tee_status": 45}, 45), ({"keyboard_status": 65, "tee_status": 45}, 65)):
            with self.subTest(arguments=arguments):
                result, root, _, _, runner_temp, results, observed, workspace = (
                    self.run_workspace_fixture(keyboard="both", **arguments)
                )
                self.assertEqual(result.returncode, status, result.stdout + result.stderr)
                self.assert_workspace_cleanup(root, runner_temp, workspace, observed)
                self.assertTrue((results / "KeyboardOwnershipTests.xcresult/fixture.txt").is_file())
                self.assertTrue((results / "keyboard-ownership-tests.log").read_text())
                receipt = json.loads((results / "keyboard-ownership-acceptance.json").read_text())
                self.assertEqual(receipt["status"], "Failed")
                self.assertFalse(any(entry["command"] == "swift" for entry in observed))

    def collection_receipt(self, results):
        path = results / "keyboard-ownership-artifact-collection.json"
        self.assertTrue(path.is_file(), "collector must retain its outcome before workspace cleanup")
        return json.loads(path.read_text())

    def test_isolated_bitmaps_stage_privately_then_retain_hashed_durable_copies(self):
        result, root, _, _, runner_temp, results, observed, workspace = self.run_workspace_fixture(keyboard="both")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        keyboard = next(entry for entry in observed
                        if "-only-testing:GlimpseTests/CalendarKeyboardOwnershipTests" in entry["args"])
        self.assertEqual(pathlib.Path(keyboard["artifact_dir"]), workspace / "keyboard-ownership-artifacts")
        self.assertEqual(keyboard["test_runner_artifact_dir"], keyboard["artifact_dir"])
        receipt = self.collection_receipt(results)
        self.assertTrue(receipt["owned_host_absence_confirmed"])
        self.assertEqual(receipt["errors"], [])
        self.assertEqual(len(receipt["copies"]), 6)
        for copy in receipt["copies"]:
            expected = bytes.fromhex("89504e470d0a1a0a") + pathlib.Path(copy["source"]).name.encode()
            self.assertEqual(pathlib.Path(copy["destination"]).read_bytes(), expected)
            self.assertEqual(copy["source_sha256"], hashlib.sha256(expected).hexdigest())
            self.assertEqual(copy["destination_sha256"], copy["source_sha256"])
        self.assertEqual(sum(entry["command"] == "ps" for entry in observed), 1)
        self.assert_workspace_cleanup(root, runner_temp, workspace, observed)

    def test_native_65_retains_completed_partial_pngs_and_exact_command_exits(self):
        partial = ("viewport-312-before-assertions.png", "expected-anchor-312-before-assertions.png",
                   "viewport-812-before-assertions.png", "expected-anchor-812-before-assertions.png")
        result, root, _, _, runner_temp, results, observed, workspace = self.run_workspace_fixture(
            keyboard="both", keyboard_status=65, bitmap_names=partial,
            summary_status=43, tests_status=44, tee_status=45,
        )
        self.assertEqual(result.returncode, 65)
        receipt = self.collection_receipt(results)
        self.assertEqual(receipt["errors"], [])
        self.assertEqual({pathlib.Path(row["destination"]).name for row in receipt["copies"]}, set(partial))
        self.assertEqual(json.loads((results / "keyboard-ownership-acceptance.json").read_text())["command_exits"],
                         {"xcodebuild": 65, "summary": 43, "tests": 44, "log": 45})
        self.assert_workspace_cleanup(root, runner_temp, workspace, observed)

    def test_live_or_unproven_host_refuses_copy_and_preserves_staging(self):
        for state in ("live", "error", "empty"):
            for native_exit in (0, 65):
                with self.subTest(state=state, native_exit=native_exit):
                    result, _, _, _, _, results, observed, workspace = self.run_workspace_fixture(
                        keyboard="both", keyboard_status=native_exit, host_state=state)
                    self.assertEqual(result.returncode, native_exit or 1)
                    receipt = self.collection_receipt(results)
                    self.assertFalse(receipt["owned_host_absence_confirmed"])
                    self.assertEqual(receipt["copies"], [])
                    self.assertTrue(receipt["errors"])
                    self.assertTrue(workspace.is_dir())
                    self.assertEqual(len(list((workspace / "keyboard-ownership-artifacts").glob("*.png"))), 6)
                    self.assertFalse((results / "keyboard-ownership-artifacts").exists())
                    self.assertFalse(any(entry["command"] == "swift" for entry in observed))

    def test_copy_failure_is_durable_blocks_success_and_preserves_native_failure_priority(self):
        for native_exit in (0, 65):
            with self.subTest(native_exit=native_exit):
                result, _, _, _, _, results, observed, workspace = self.run_workspace_fixture(
                    keyboard="both", keyboard_status=native_exit, artifact_collision=True)
                self.assertEqual(result.returncode, native_exit or 1)
                receipt = self.collection_receipt(results)
                self.assertTrue(receipt["owned_host_absence_confirmed"])
                self.assertTrue(any("viewport-312.png" in error for error in receipt["errors"]))
                self.assertEqual(len(receipt["copies"]), 5)
                self.assertEqual((results / "keyboard-ownership-artifacts/viewport-312.png").read_text(),
                                 "existing durable evidence")
                self.assertTrue(workspace.is_dir())
                self.assertFalse(any(entry["command"] == "swift" for entry in observed))

    def test_successful_viewport_manifest_requires_all_six_named_pngs(self):
        expected, result_summary, result_tests = current_suite()
        result, _, _, _, _, results, _, workspace = self.run_workspace_fixture(
            keyboard="both", keyboard_manifest=expected, keyboard_summary=result_summary,
            keyboard_tests=result_tests, bitmap_names=VIEWPORT_PNGS[:-1])
        self.assertEqual(result.returncode, 1)
        receipt = self.collection_receipt(results)
        self.assertTrue(any("viewport-812.png" in error for error in receipt["errors"]))
        self.assertEqual(len(receipt["copies"]), 5)
        self.assertTrue(receipt["preserve_staging"])
        self.assertTrue(workspace.is_dir())
        self.assertTrue((workspace / "retain-keyboard-artifacts").is_file())
        self.assertEqual(len(list((workspace / "keyboard-ownership-artifacts").glob("*.png"))), 5)
        self.assertEqual(json.loads((results / "keyboard-ownership-acceptance.json").read_text())["status"], "Passed")

    def test_invalid_manifest_collection_error_preserves_staging_and_durable_receipt(self):
        result, _, _, _, _, results, _, workspace = self.run_workspace_fixture(
            keyboard="both", keyboard_manifest={"schema_version": 1, "methods": []})
        self.assertEqual(result.returncode, 1)
        receipt = self.collection_receipt(results)
        self.assertTrue(any("Invalid method manifest" in error for error in receipt["errors"]))
        self.assertEqual(len(receipt["copies"]), 6)
        self.assertTrue(receipt["preserve_staging"])
        self.assertTrue((workspace / "retain-keyboard-artifacts").is_file())
        self.assertEqual(len(list((workspace / "keyboard-ownership-artifacts").glob("*.png"))), 6)

    def test_legacy_manifest_allows_empty_artifacts_after_owned_path_absence(self):
        result, root, _, _, runner_temp, results, observed, workspace = self.run_workspace_fixture(
            keyboard="both", bitmap_names=())
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        receipt = self.collection_receipt(results)
        self.assertEqual(receipt["copies"], [])
        self.assertEqual(receipt["errors"], [])
        self.assertTrue(receipt["owned_host_absence_confirmed"])
        self.assert_workspace_cleanup(root, runner_temp, workspace, observed)

    def test_checked_in_manifest_requires_prepared_fourteen_methods_and_sixteen_cases(self):
        _, result_summary, result_tests = current_suite()
        expected = json.loads((SCRIPTS / "keyboard-ownership-methods.json").read_text())
        result, _, _, _, _, results, _, _ = self.run_workspace_fixture(
            keyboard="both", keyboard_manifest=expected,
            keyboard_summary=result_summary, keyboard_tests=result_tests,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        receipt = json.loads((results / "keyboard-ownership-acceptance.json").read_text())
        self.assertEqual(len(receipt["methods"]), 14)
        self.assertEqual(receipt["executed_cases"], 16)
        for method in ("heldHeaderSpaceActivatesOnceAndConsumesRepeat()",
                       "todayBecomingDisabledHasNoExtraTodayAction()"):
            self.assertEqual(receipt["methods"]["CalendarKeyboardOwnershipTests/" + method], 1)

    def test_exit_zero_cannot_admit_missing_failed_skipped_or_invalid_results(self):
        for scenario in ("zero", "missing", "failed", "skipped", "expected-failure",
                         "invalid-status", "duplicate", "unexpected", "bad-summary",
                         "bad-tree", "bad-manifest", "boolean-schema", "float-schema"):
            with self.subTest(scenario=scenario):
                expected, result_summary, result_tests = manifest(), summary(), tree()
                nodes = cases(result_tests)
                if scenario == "zero":
                    nodes.clear()
                    result_summary.update(totalTestCount=0, passedTests=0)
                elif scenario == "missing":
                    nodes.pop()
                elif scenario in ("failed", "skipped", "expected-failure", "invalid-status"):
                    nodes[0]["result"] = {
                        "failed": "Failed", "skipped": "Skipped",
                        "expected-failure": "Expected Failure", "invalid-status": "Unknown",
                    }[scenario]
                elif scenario == "duplicate":
                    nodes.append(dict(nodes[0]))
                elif scenario == "unexpected":
                    nodes[-1]["nodeIdentifier"] = "OtherSuite/test()"
                elif scenario == "bad-summary":
                    result_summary["totalTestCount"] = "6"
                elif scenario == "bad-tree":
                    result_tests = {"testNodes": "not a node list"}
                elif scenario == "bad-manifest":
                    expected["methods"] = {}
                elif scenario in ("boolean-schema", "float-schema"):
                    expected["schema_version"] = True if scenario == "boolean-schema" else 1.0
                result, root, _, _, runner_temp, results, observed, workspace = (
                    self.run_workspace_fixture(keyboard="both", keyboard_manifest=expected,
                                               keyboard_summary=result_summary, keyboard_tests=result_tests)
                )
                self.assertNotEqual(result.returncode, 0)
                self.assert_workspace_cleanup(root, runner_temp, workspace, observed)
                self.assertTrue((results / "keyboard-ownership-summary.json").is_file())
                self.assertTrue((results / "keyboard-ownership-tests.json").is_file())
                receipt = json.loads((results / "keyboard-ownership-acceptance.json").read_text())
                self.assertEqual(receipt["status"], "Failed")
                self.assertFalse(any(entry["command"] == "swift" for entry in observed))

    def test_parameter_cases_must_all_execute_once_and_pass(self):
        for scenario in ("passed", "failed", "skipped", "missing", "duplicate", "invalid-child"):
            with self.subTest(scenario=scenario):
                expected, result_summary, result_tests = parameterized()
                arguments = cases(result_tests)[-1]["children"]
                if scenario in ("failed", "skipped"):
                    arguments[-1]["result"] = scenario.capitalize()
                elif scenario == "missing":
                    arguments.pop()
                elif scenario == "duplicate":
                    arguments[-1] = dict(arguments[0])
                elif scenario == "invalid-child":
                    arguments[-1]["nodeType"] = "Unrecognized"
                result, _, _, _, _, results, observed, _ = self.run_workspace_fixture(
                    keyboard="both", keyboard_manifest=expected,
                    keyboard_summary=result_summary, keyboard_tests=result_tests,
                )
                if scenario == "passed":
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    receipt_path = results / "keyboard-ownership-acceptance.json"
                    self.assertTrue(receipt_path.is_file())
                    receipt = json.loads(receipt_path.read_text())
                    self.assertEqual(receipt["executed_cases"], 7)
                    self.assertEqual(receipt["methods"]["CalendarKeyboardOwnershipTests/activation(key:)"], 2)
                else:
                    self.assertNotEqual(result.returncode, 0)
                    self.assertFalse(any(entry["command"] == "swift" for entry in observed))

    def test_parameter_argument_children_requires_absent_or_empty_list(self):
        for malformed in (False, 0, "", {}, None, [{}]):
            with self.subTest(children=malformed):
                expected, result_summary, result_tests = parameterized()
                cases(result_tests)[-1]["children"][0]["children"] = malformed
                result, _, _, _, _, results, observed, _ = self.run_workspace_fixture(
                    keyboard="both", keyboard_manifest=expected,
                    keyboard_summary=result_summary, keyboard_tests=result_tests,
                )
                self.assertNotEqual(result.returncode, 0)
                receipt = json.loads((results / "keyboard-ownership-acceptance.json").read_text())
                self.assertEqual(receipt["status"], "Failed")
                self.assertFalse(any(entry["command"] == "swift" for entry in observed))


if __name__ == "__main__":
    unittest.main()
