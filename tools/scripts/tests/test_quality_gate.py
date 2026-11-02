import json
import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest

SCRIPTS = pathlib.Path(__file__).parents[1]


class LocalQualityContracts(unittest.TestCase):
    def run_workspace_fixture(self, app_status=0, explicit_results=False, use_runner_temp=True):
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
        for name in ("xcodebuild", "swift"):
            path = bin_dir / name
            path.write_text("""#!/usr/bin/env python3
import json,os,pathlib,sys
args=sys.argv[1:]
with open(os.environ['FIXTURE_TRACE'], 'a') as trace:
    trace.write(json.dumps({'command':pathlib.Path(sys.argv[0]).name,
                            'args':args,'cwd':os.getcwd(),'tmpdir':os.environ['TMPDIR'],
                            'workspace_mode':pathlib.Path(os.environ['TMPDIR']).parent.stat().st_mode & 0o777})+'\\n')
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
    sys.exit(int(os.environ['FIXTURE_APP_STATUS']))
print('fixture command output',flush=True)
""")
            path.chmod(0o755)
        env = {**os.environ, "PATH": str(bin_dir) + os.pathsep + os.environ["PATH"],
               "GLIMPSE_BUILD_ROOT": str(durable), "GLIMPSE_SOURCE_ROOT": str(source),
               "RUNNER_TEMP": str(runner_temp), "TMPDIR": str(inherited_temp),
               "GITHUB_OUTPUT": str(root / "github-output"),
               "FIXTURE_TRACE": str(trace), "FIXTURE_APP_STATUS": str(app_status)}
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


if __name__ == "__main__":
    unittest.main()
