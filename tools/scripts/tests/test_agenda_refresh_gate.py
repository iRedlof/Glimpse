import hashlib
import json
import os
import pathlib
import shutil
import subprocess
import unittest

from agenda_refresh_xcresult_fixture import AGENDA_PNGS, EXPECTED, cases, fixture_directory, metadata
from ai_date_search_xcresult_fixture import EXPECTED as AI_EXPECTED, metadata as ai_metadata
from keyboard_xcresult_fixture import settings_suite
from test_ai_date_search_gate import OPT_INS, PROBES, VIEWPORT_PNGS

SCRIPTS = pathlib.Path(__file__).parents[1]

# Only external command boundaries are synthetic. The real gate, checker and
# collector run against an isolated source archive and private work dir.
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
       'agenda_artifact_dir':os.environ.get('GLIMPSE_AGENDA_ARTIFACT_DIR'),
       'runner_agenda_artifact_dir':os.environ.get('TEST_RUNNER_GLIMPSE_AGENDA_ARTIFACT_DIR'),
       'workspace_mode':pathlib.Path(os.environ['TMPDIR']).parent.stat().st_mode & 0o777,
       'completed_phase':phase}
with open(os.environ['FIXTURE_TRACE'],'a') as trace:
    trace.write(json.dumps(entry)+'\\n')
options=json.loads(os.environ['FIXTURE_OPTIONS'])
bundles={'KeyboardOwnershipTests.xcresult':'KEYBOARD',
         'AIDateSearchIntegrationTests.xcresult':'AI','AgendaRefreshTests.xcresult':'AGENDA'}
if command=='ps':
    assert args==['-axww','-o','pid=,comm='] and phase in ('KEYBOARD','AI','AGENDA')
    state=options.get('host_state','absent') if phase=='AGENDA' else 'absent'
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
    suite=bundles[pathlib.Path(args[5]).name].lower()
    assert args[3] in ('summary','tests')
    print((pathlib.Path(os.environ['FIXTURE_ROOT'])/(suite+'-'+args[3]+'.json')).read_text(),flush=True)
    print('synthetic '+suite+' '+args[3]+' diagnostic',file=sys.stderr,flush=True)
    sys.exit(options.get(args[3]+'_exit',0) if suite=='agenda' else 0)
if command=='tee':
    text=sys.stdin.read()
    target=pathlib.Path(args[0]); target.write_text(text)
    print(text,end='',flush=True)
    sys.exit(options.get('log_exit',0) if target.name=='agenda-refresh-tests.log' else 0)
if command=='uname':
    assert args==['-m']
    print('arm64')
    sys.exit(0)
assert command in ('xcodebuild','swift'), 'unexpected command boundary'
for flag in ('-derivedDataPath','--scratch-path','--cache-path'):
    if flag in args:
        directory=pathlib.Path(args[args.index(flag)+1])
        directory.mkdir(parents=True,exist_ok=True)
        (directory/'synthetic.txt').write_text('synthetic build output')
if '-resultBundlePath' in args:
    bundle=pathlib.Path(args[args.index('-resultBundlePath')+1])
    bundle.mkdir(parents=True); (bundle/'synthetic.txt').write_text('synthetic bundle')
    phase=bundles.get(bundle.name,'APP')
    if phase=='KEYBOARD':
        staging=pathlib.Path(os.environ['GLIMPSE_KEYBOARD_ARTIFACT_DIR'])
        for name in json.loads(os.environ['FIXTURE_PNGS']):
            (staging/name).write_bytes(b'synthetic nonempty PNG fixture')
    if phase=='AGENDA' and os.environ.get('GLIMPSE_AGENDA_ARTIFACT_DIR'):
        staging=pathlib.Path(os.environ['GLIMPSE_AGENDA_ARTIFACT_DIR'])
        for name in options.get('agenda_pngs',json.loads(os.environ['FIXTURE_AGENDA_PNGS'])):
            data=b'synthetic nonempty Agenda PNG fixture'
            if name==options.get('agenda_empty_png'):
                data=b''
            (staging/name).write_bytes(data)
    if phase in ('KEYBOARD','AI','AGENDA'):
        done.write_text(json.dumps(phase))
    print('synthetic '+phase+' terminal output',flush=True)
    sys.exit(options.get('native_exit',0) if phase=='AGENDA' else
             options.get('ai_exit',0) if phase=='AI' else 0)
print('synthetic command output',flush=True)
"""


class AgendaRefreshGateContracts(unittest.TestCase):
    def run_gate(self, *, pair=("file", "file"), preceding=False, options=None,
                 agenda_manifest=None, agenda_tests=None):
        root = fixture_directory(self, "agenda-gate-")
        controller = root / "controller/tools/scripts"
        controller.mkdir(parents=True)
        for name in ("quality-gate.sh", "check-keyboard-xcresult.py", "collect-keyboard-artifacts.py"):
            shutil.copy2(SCRIPTS / name, controller / name)
        (controller / "agenda-refresh-methods.json").write_text('{"wrong":"controller"}\n')
        source = root / "archive"
        source_scripts = source / "tools/scripts"
        (source_scripts / "tests").mkdir(parents=True)
        (source / "tools/monitoring").mkdir()
        for directory in (source_scripts / "tests", source / "tools/monitoring"):
            (directory / "test_fixture.py").write_text(
                "import os,unittest\nclass Fixture(unittest.TestCase):\n"
                " def test_ordinary_opt_ins_are_zero(self):\n"
                "  for key in ('GLIMPSE_CALENDAR_KEYBOARD_ACCEPTANCE',"
                "'TEST_RUNNER_GLIMPSE_CALENDAR_KEYBOARD_ACCEPTANCE',"
                "'GLIMPSE_KEYBOARD_MECHANISM_PROBE','TEST_RUNNER_GLIMPSE_KEYBOARD_MECHANISM_PROBE'):\n"
                "   self.assertEqual(os.environ[key],'0')\n")
        (source / "GlimpseTests").mkdir()
        suite = source / "GlimpseTests/CalendarAgendaRefreshTests.swift"
        manifest = source_scripts / "agenda-refresh-methods.json"
        content = ("// synthetic presence only\n",
                   json.dumps(EXPECTED if agenda_manifest is None else agenda_manifest))
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
        keyboard_manifest, keyboard_summary, keyboard_tests = settings_suite()
        self.assertEqual(
            keyboard_manifest,
            json.loads((SCRIPTS / "keyboard-ownership-methods.json").read_text()),
        )
        if preceding:
            (source / "Glimpse").mkdir()
            (source / "Glimpse/CalendarKeyboardFocus.swift").write_text("// synthetic presence\n")
            (source / "GlimpseTests/CalendarKeyboardOwnershipTests.swift").write_text("// synthetic presence\n")
            (source / "GlimpseTests/AIDateSearchIntegrationTests.swift").write_text("// synthetic presence\n")
            (source_scripts / "ai-date-search-integration-methods.json").write_text(json.dumps(AI_EXPECTED))
        (source_scripts / "keyboard-ownership-methods.json").write_text(json.dumps(keyboard_manifest))
        ai_summary, ai_tests = ai_metadata()
        agenda_summary, default_agenda_tests = metadata()
        for name, document in (("agenda-summary", agenda_summary),
                               ("agenda-tests", default_agenda_tests if agenda_tests is None else agenda_tests),
                               ("ai-summary", ai_summary), ("ai-tests", ai_tests),
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
               "FIXTURE_AGENDA_PNGS": json.dumps(AGENDA_PNGS),
               **{key: "1" for key in OPT_INS + PROBES}}
        env.pop("GITHUB_OUTPUT", None)
        for key in ("GLIMPSE_AGENDA_ARTIFACT_DIR", "TEST_RUNNER_GLIMPSE_AGENDA_ARTIFACT_DIR"):
            env.pop(key, None)
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
        return result, root / "results", observed, derived.parent

    def receipt(self, results, name="agenda-refresh-acceptance.json"):
        path = results / name
        self.assertTrue(path.is_file(), f"missing retained receipt: {path}")
        return json.loads(path.read_text())

    def test_agenda_runs_alone_after_ai_collection_and_metadata_before_core(self):
        result, results, observed, workspace = self.run_gate(preceding=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        native = [(index, entry) for index, entry in enumerate(observed)
                  if entry["command"] == "xcodebuild" and "-resultBundlePath" in entry["args"]]
        self.assertEqual(len(native), 4, "ordinary app plus three separately isolated suites required")
        app, keyboard, ai, agenda = (entry for _, entry in native)
        self.assertEqual(app["env"], {key: "0" for key in OPT_INS + PROBES})
        self.assertEqual(pathlib.Path(agenda["args"][agenda["args"].index("-resultBundlePath") + 1]).name,
                         "AgendaRefreshTests.xcresult")
        for entry, selected in ((keyboard, "CalendarKeyboardOwnershipTests"),
                                (ai, "AIDateSearchIntegrationTests"), (agenda, "CalendarAgendaRefreshTests")):
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
        self.assertEqual(agenda["agenda_artifact_dir"], agenda["runner_agenda_artifact_dir"])
        self.assertEqual(agenda["agenda_artifact_dir"], agenda["artifact_dir"])
        agenda_index = native[-1][0]
        self.assertTrue(any(index < agenda_index and entry["command"] == "ps"
                            and entry["completed_phase"] == "AI" for index, entry in enumerate(observed)))
        self.assertEqual(sum(entry["command"] == "xcrun" and
                             "AIDateSearchIntegrationTests.xcresult" in " ".join(entry["args"])
                             for entry in observed[:agenda_index]), 2)
        agenda_metadata = [(index, entry) for index, entry in enumerate(observed)
                           if entry["command"] == "xcrun" and
                           "AgendaRefreshTests.xcresult" in " ".join(entry["args"])]
        self.assertEqual([entry["args"][3] for _, entry in agenda_metadata], ["summary", "tests"])
        agenda_ps = next(index for index, entry in enumerate(observed)
                         if entry["command"] == "ps" and entry["completed_phase"] == "AGENDA")
        core_index = next(index for index, entry in enumerate(observed) if entry["command"] == "swift")
        self.assertLess(agenda_index, agenda_ps)
        self.assertLess(agenda_ps, agenda_metadata[0][0])
        self.assertLess(agenda_metadata[-1][0], core_index)
        self.assertEqual(observed[core_index]["env"], {key: "0" for key in OPT_INS + PROBES})
        self.assertEqual(self.receipt(results)["methods"], EXPECTED["methods"])
        self.assertEqual(self.receipt(results)["executed_cases"], 23)
        self.assertEqual(
            self.receipt(results, "keyboard-ownership-acceptance.json")["executed_cases"],
            sum(json.loads((SCRIPTS / "keyboard-ownership-methods.json").read_text())["methods"].values()),
        )
        self.assertEqual(self.receipt(results, "ai-date-search-integration-acceptance.json")["executed_cases"], 18)
        self.assertFalse(workspace.exists())

    def assert_agenda_copies(self, results, receipt, names):
        self.assertEqual({pathlib.Path(row["destination"]).name for row in receipt["copies"]}, set(names))
        self.assertEqual({path.name for path in (results / "agenda-refresh-artifacts").iterdir()}, set(names))
        for row in receipt["copies"]:
            data = pathlib.Path(row["destination"]).read_bytes()
            self.assertGreater(len(data), 0)
            self.assertEqual(hashlib.sha256(data).hexdigest(), row["source_sha256"])
            self.assertEqual(row["source_sha256"], row["destination_sha256"])

    def test_all_fourteen_agenda_images_are_retained_before_core(self):
        result, results, observed, workspace = self.run_gate()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        receipt = self.receipt(results, "agenda-refresh-artifact-collection.json")
        self.assertTrue(receipt["owned_host_absence_confirmed"])
        self.assert_agenda_copies(results, receipt, AGENDA_PNGS)
        self.assertFalse(receipt["preserve_staging"])
        self.assertEqual(receipt["exit_code"], 0)
        self.assertTrue(any(entry["command"] == "swift" for entry in observed))
        self.assertFalse(workspace.exists())
        self.assertEqual((results / "dependency-pins.before.sha256").read_text(),
                         (results / "dependency-pins.after.sha256").read_text())

    def test_empty_missing_or_empty_file_agenda_images_block_core_and_preserve_staging(self):
        # Partial and zero-byte cases must keep every other completed owned image.
        for options, copied, missing in (
            ({"agenda_pngs": []}, (), AGENDA_PNGS),
            ({"agenda_pngs": list(AGENDA_PNGS[:-1])}, AGENDA_PNGS[:-1], (AGENDA_PNGS[-1],)),
            ({"agenda_empty_png": AGENDA_PNGS[-1]}, AGENDA_PNGS[:-1], (AGENDA_PNGS[-1],)),
            ({"agenda_pngs": list(VIEWPORT_PNGS)}, VIEWPORT_PNGS, AGENDA_PNGS),
        ):
            with self.subTest(options=options):
                result, results, observed, workspace = self.run_gate(options=options)
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                receipt = self.receipt(results, "agenda-refresh-artifact-collection.json")
                self.assertTrue(receipt["owned_host_absence_confirmed"])
                self.assert_agenda_copies(results, receipt, copied)
                self.assertTrue(receipt["preserve_staging"])
                self.assertTrue((workspace / "retain-agenda-refresh-artifacts").is_file())
                self.assertTrue((workspace / "agenda-refresh-artifacts").is_dir())
                for name in copied:
                    self.assertEqual((workspace / "agenda-refresh-artifacts" / name).read_bytes(),
                                     (results / "agenda-refresh-artifacts" / name).read_bytes())
                for name in missing:
                    self.assertTrue(any(name in error for error in receipt["errors"]), receipt)
                self.assertEqual(self.receipt(results)["status"], "Passed")
                self.assertFalse(any(entry["command"] == "swift" for entry in observed))
                self.assertFalse((results / "dependency-pins.after.sha256").exists())
                self.assertTrue((results / "AgendaRefreshTests.xcresult/synthetic.txt").is_file())

    def test_malformed_capture_contract_blocks_core_with_completed_artifacts_preserved(self):
        contracts = (None, [], "selected-error-dark.png", {}, list(AGENDA_PNGS[:-1]),
                     list(AGENDA_PNGS) + ["extra.png"],
                     list(AGENDA_PNGS[:-1]) + [AGENDA_PNGS[0]],
                     list(AGENDA_PNGS[:-1]) + ["../outside.png"],
                     list(AGENDA_PNGS[:-1]) + ["/absolute.png"],
                     list(AGENDA_PNGS[:-1]) + ["nested\\image.png"],
                     list(AGENDA_PNGS[:-1]) + ["image.txt"],
                     list(AGENDA_PNGS[:-1]) + [True])
        for contract in contracts:
            with self.subTest(contract=contract):
                manifest = {**EXPECTED, "required_pngs": contract}
                result, results, observed, workspace = self.run_gate(agenda_manifest=manifest)
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                receipt = self.receipt(results, "agenda-refresh-artifact-collection.json")
                self.assert_agenda_copies(results, receipt, AGENDA_PNGS)
                self.assertTrue(receipt["preserve_staging"])
                self.assertTrue(receipt["errors"])
                self.assertTrue((workspace / "retain-agenda-refresh-artifacts").is_file())
                self.assertEqual(self.receipt(results)["status"], "Passed")
                self.assertFalse(any(entry["command"] == "swift" for entry in observed))

    def test_native_failure_retains_completed_images_without_missing_output_override(self):
        for names in ((), (AGENDA_PNGS[0],)):
            with self.subTest(names=names):
                result, results, observed, workspace = self.run_gate(
                    options={"native_exit": 65, "agenda_pngs": list(names)})
                self.assertEqual(result.returncode, 65, result.stdout + result.stderr)
                receipt = self.receipt(results, "agenda-refresh-artifact-collection.json")
                self.assert_agenda_copies(results, receipt, names)
                self.assertEqual(receipt["errors"], [])
                self.assertFalse(receipt["preserve_staging"])
                self.assertFalse(workspace.exists())
                self.assertEqual(self.receipt(results)["command_exits"]["xcodebuild"], 65)
                self.assertFalse(any(entry["command"] == "swift" for entry in observed))

    def test_both_absent_legacy_pair_never_selects_agenda(self):
        result, results, observed, workspace = self.run_gate(pair=("absent", "absent"))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.receipt(results)["status"], "NotApplicable")
        self.assertFalse(any("-only-testing:GlimpseTests/CalendarAgendaRefreshTests" in entry["args"]
                             for entry in observed))
        self.assertTrue(any(entry["command"] == "swift" for entry in observed))
        self.assertFalse(workspace.exists())

    def test_partial_nonregular_or_symlink_pair_fails_without_agenda_or_core(self):
        for pair in (("file", "absent"), ("absent", "file"), ("broken-link", "absent"),
                     ("absent", "broken-link"), ("broken-link", "broken-link"), ("directory", "file"),
                     ("file", "directory"), ("symlink", "file"), ("file", "symlink"),
                     ("fifo", "file"), ("file", "fifo")):
            with self.subTest(pair=pair):
                result, results, observed, workspace = self.run_gate(pair=pair)
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertEqual(self.receipt(results)["status"], "Failed")
                self.assertFalse(any("-only-testing:GlimpseTests/CalendarAgendaRefreshTests" in entry["args"]
                                     for entry in observed))
                self.assertFalse(any(entry["command"] == "swift" for entry in observed))
                self.assertFalse(workspace.exists())

    def test_raw_phase_exits_keep_metadata_receipts_and_stop_core(self):
        for field, code in (("native_exit", 65), ("log_exit", 7), ("summary_exit", 8), ("tests_exit", 9)):
            with self.subTest(field=field):
                result, results, observed, workspace = self.run_gate(options={field: code})
                self.assertEqual(result.returncode, code, result.stdout + result.stderr)
                receipt = self.receipt(results)
                self.assertEqual(receipt["status"], "Failed")
                phase = {"native_exit": "xcodebuild", "log_exit": "log",
                         "summary_exit": "summary", "tests_exit": "tests"}[field]
                self.assertEqual(receipt["command_exits"][phase], code)
                for name in ("tests.log", "summary.json", "tests.json", "xcresult.log",
                             "artifact-collection.json", "artifact-collection.log"):
                    self.assertTrue((results / ("agenda-refresh-" + name)).is_file())
                self.assertIn("synthetic AGENDA terminal output", (results / "agenda-refresh-tests.log").read_text())
                self.assertIn("diagnostic", (results / "agenda-refresh-xcresult.log").read_text())
                self.assertFalse(any(entry["command"] == "swift" for entry in observed))
                self.assertFalse(workspace.exists())

    def test_unproven_owned_host_absence_retains_private_staging_and_marker(self):
        for state in ("live", "error", "empty"):
            with self.subTest(state=state):
                result, results, observed, workspace = self.run_gate(options={"host_state": state})
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                collection = self.receipt(results, "agenda-refresh-artifact-collection.json")
                self.assertFalse(collection["owned_host_absence_confirmed"])
                self.assertTrue(collection["preserve_staging"])
                self.assertTrue(collection["errors"])
                self.assertTrue((workspace / "retain-agenda-refresh-artifacts").is_file())
                self.assertTrue((workspace / "agenda-refresh-artifacts").is_dir())
                self.assertFalse(any(entry["command"] == "swift" for entry in observed))
                self.assertEqual(self.receipt(results)["status"], "Passed")

    def test_malformed_manifest_or_missing_case_fails_despite_zero_native_exit(self):
        _, incomplete = metadata()
        cases(incomplete)[9]["children"].pop()
        for options in ({"agenda_manifest": {"schema_version": 1, "methods": {}}},
                        {"agenda_tests": incomplete}):
            with self.subTest(options=next(iter(options))):
                result, results, observed, workspace = self.run_gate(**options)
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertEqual(self.receipt(results)["status"], "Failed")
                self.assertFalse(any(entry["command"] == "swift" for entry in observed))
                self.assertTrue((results / "AgendaRefreshTests.xcresult/synthetic.txt").is_file())

    def test_ai_failure_prevents_agenda_and_core(self):
        result, results, observed, workspace = self.run_gate(preceding=True, options={"ai_exit": 65})
        self.assertEqual(result.returncode, 65, result.stdout + result.stderr)
        self.assertEqual(self.receipt(results, "ai-date-search-integration-acceptance.json")["status"], "Failed")
        self.assertFalse(any("-only-testing:GlimpseTests/CalendarAgendaRefreshTests" in entry["args"]
                             for entry in observed))
        self.assertFalse(any(entry["command"] == "swift" for entry in observed))
        self.assertFalse(workspace.exists())


if __name__ == "__main__":
    unittest.main()
