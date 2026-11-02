import json
import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest

SCRIPTS = pathlib.Path(__file__).parents[1]

RECORD_COMPONENT = """
import json,os,pathlib
source=next(path for path in pathlib.Path(__file__).parents if (path/'revision.txt').is_file())
workspace=pathlib.Path(os.environ['TMPDIR']).parent
with open(os.environ['FIXTURE_TRACE'],'a') as trace:
    trace.write(json.dumps({'component':COMPONENT,'revision':(source/'revision.txt').read_text(),
                            'path':__file__,'workspace':str(workspace),
                            'workspace_mode':workspace.stat().st_mode & 0o777})+'\\n')
"""


class SourceHistoryContracts(unittest.TestCase):
    def run_fixture(self, event, fail_revision="", new_branch=False, pr_merge=False):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = pathlib.Path(temporary.name)
        scripts = root / "tools/scripts"
        scripts.mkdir(parents=True)
        shutil.copy(SCRIPTS / "test-source-revisions.sh", scripts)
        (scripts / "quality-gate.sh").write_text("""#!/bin/bash
set -euo pipefail
revision=$(cat "$GLIMPSE_SOURCE_ROOT/revision.txt")
printf '%s\\n' "$revision" >> "$OBSERVED"
test "$revision" != "${FAIL_REVISION:-}"
""")
        (scripts / "quality-gate.sh").chmod(0o755)
        subprocess.run(["git", "init", "-b", "main", str(root)], check=True, capture_output=True)

        def git(*args):
            return subprocess.run(["git", "-C", str(root), *args], check=True,
                                  text=True, capture_output=True).stdout.strip()

        git("config", "user.name", "Fixture")
        git("config", "user.email", "fixture@example.invalid")
        commits = []
        for number in range(4 if pr_merge else 3):
            (root / "revision.txt").write_text(str(number))
            git("add", ".")
            git("commit", "-m", f"fixture {number}")
            commits.append(git("rev-parse", "HEAD"))
        git("update-ref", "refs/remotes/origin/main", commits[0])
        output = root / "github-output"
        observed = root / "observed"
        env = {**os.environ, "GLIMPSE_BUILD_ROOT": str(root / "build"),
               "GITHUB_OUTPUT": str(output), "GITHUB_SHA": commits[-1],
               "GITHUB_EVENT_NAME": event, "BEFORE_SHA": "0" * 40 if new_branch else commits[0],
               "PR_BASE_SHA": commits[0], "PR_HEAD_SHA": commits[-2] if pr_merge else commits[-1],
               "OBSERVED": str(observed), "FAIL_REVISION": fail_revision}
        result = subprocess.run(["bash", str(scripts / "test-source-revisions.sh")],
                                cwd=root, env=env, text=True, capture_output=True, timeout=20)
        result_dir = pathlib.Path(output.read_text().strip().split("=", 1)[1])
        return result, commits, result_dir, observed.read_text().splitlines()

    def test_batched_push_tests_every_introduced_commit(self):
        result, commits, results, observed = self.run_fixture("push")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(observed, ["1", "2"])
        self.assertEqual((results / "tested-shas.txt").read_text().splitlines(), commits[1:])
        self.assertEqual(json.loads((results / "history.json").read_text())["base_sha"], commits[0])

    def test_new_branch_uses_main_ancestor(self):
        result, commits, results, observed = self.run_fixture("push", new_branch=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(observed, ["1", "2"])
        self.assertEqual((results / "requested-shas.txt").read_text().splitlines(), commits[1:])

    def test_pr_tests_source_commits_and_merge_result(self):
        result, commits, results, observed = self.run_fixture("pull_request", pr_merge=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(observed, ["1", "2", "3"])
        self.assertEqual((results / "tested-shas.txt").read_text().splitlines(), commits[1:])

    def test_failed_intermediate_commit_blocks_green_head(self):
        result, commits, results, observed = self.run_fixture("push", fail_revision="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(observed, ["1"])
        self.assertEqual((results / "failed-sha.txt").read_text().strip(), commits[1])
        self.assertEqual((results / "tested-shas.txt").read_text(), "")


class ArchivedToolingContracts(unittest.TestCase):
    def write_contracts(self, root, revision, failing_component):
        scripts = root / "tools/scripts"
        tests = scripts / "tests"
        monitoring = root / "tools/monitoring"
        tests.mkdir(parents=True, exist_ok=True)
        monitoring.mkdir(parents=True, exist_ok=True)
        (root / "revision.txt").write_text(str(revision))
        helper = (SCRIPTS / "select-signing-identity.py").read_text()
        if revision == 1 and failing_component == "tooling":
            helper = helper.replace(
                "def select_identity(identity_output, expected_team):",
                "def select_identity(identity_output, expected_team):\n    return 'A' * 40",
            )
        (scripts / "select-signing-identity.py").write_text(helper)
        (tests / "test_fixture.py").write_text(
            "COMPONENT='tooling'\n" + RECORD_COMPONENT + """
import importlib.util,unittest
helper=pathlib.Path(__file__).parents[1]/'select-signing-identity.py'
spec=importlib.util.spec_from_file_location('signing_selector',helper)
selector=importlib.util.module_from_spec(spec)
spec.loader.exec_module(selector)
class SigningContract(unittest.TestCase):
    def test_wrong_team_is_rejected(self):
        output='  1) '+('A'*40)+' "Developer ID Application: Fixture (OTHER12345)"\\n'
        with self.assertRaises(ValueError):
            selector.select_identity(output,'TEAM123456')
""")
        broken_monitoring = revision == 1 and failing_component == "monitoring"
        (monitoring / "test_fixture.py").write_text(
            "COMPONENT='monitoring'\n" + RECORD_COMPONENT +
            "import unittest\nclass MonitorContract(unittest.TestCase):\n"
            f"    def test_revision_is_healthy(self): self.assertFalse({broken_monitoring!r})\n"
        )
        for name, component in (("release-control.py", "version"), ("check-dependency-pins.py", "pins")):
            broken = revision == 1 and failing_component == component
            (scripts / name).write_text(
                f"COMPONENT={component!r}\n" + RECORD_COMPONENT + f"raise SystemExit({int(broken)})\n"
            )
        # The reviewed current runner owns cleanup, even if archived runners predate it.
        (scripts / "quality-gate.sh").write_text("#!/bin/bash\nexit 91\n")
        for name in ("GlimpseCore/Package.resolved",
                     "Glimpse.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"):
            path = root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('{"pins":[]}\n')

    def write_build_stubs(self, bin_dir):
        bin_dir.mkdir()
        for command in ("xcodebuild", "swift"):
            path = bin_dir / command
            path.write_text("""#!/usr/bin/env python3
import json,os,pathlib,sys
args=sys.argv[1:]
source=next(path for path in (pathlib.Path.cwd(),*pathlib.Path.cwd().parents)
            if (path/'revision.txt').is_file())
with open(os.environ['FIXTURE_TRACE'],'a') as trace:
    trace.write(json.dumps({'component':pathlib.Path(sys.argv[0]).name,
                            'revision':(source/'revision.txt').read_text(),
                            'cwd':str(pathlib.Path.cwd())})+'\\n')
for flag in ('-derivedDataPath','--scratch-path','--cache-path','-resultBundlePath'):
    if flag in args:
        output=pathlib.Path(args[args.index(flag)+1])
        output.mkdir(parents=True,exist_ok=True)
        (output/'fixture.txt').write_text('generated fixture evidence\\n')
print('fixture build passed',flush=True)
""")
            path.chmod(0o755)

    def run_quality_history(self, failing_component=""):
        temporary = tempfile.TemporaryDirectory(prefix="glimpse history fixture ")
        self.addCleanup(temporary.cleanup)
        root = pathlib.Path(temporary.name).resolve()
        checkout = root / "checkout"
        subprocess.run(["git", "init", "-b", "main", str(checkout)], check=True, capture_output=True)

        def git(*args):
            return subprocess.run(["git", "-C", str(checkout), *args], check=True,
                                  text=True, capture_output=True).stdout.strip()

        git("config", "user.name", "Fixture")
        git("config", "user.email", "fixture@example.invalid")
        commits = []
        for revision in range(3):
            self.write_contracts(checkout, revision, failing_component)
            git("add", ".")
            git("commit", "-m", f"fixture {revision}")
            commits.append(git("rev-parse", "HEAD"))
        scripts = checkout / "tools/scripts"
        for name in ("quality-gate.sh", "test-source-revisions.sh"):
            shutil.copy(SCRIPTS / name, scripts / name)
        bin_dir = root / "bin"
        self.write_build_stubs(bin_dir)
        runner_temp = root / "runner-temp"
        runner_temp.mkdir()
        (runner_temp / "keep.txt").write_text("unrelated workspace\n")
        durable = root / "durable"
        inherited_temp = durable / "tmp"
        inherited_temp.mkdir(parents=True)
        (inherited_temp / "keep.txt").write_text("inherited temporary files\n")
        output, trace = root / "github-output", root / "trace.jsonl"
        env = {**os.environ, "PATH": str(bin_dir) + os.pathsep + os.environ["PATH"],
               "GLIMPSE_BUILD_ROOT": str(durable), "RUNNER_TEMP": str(runner_temp),
               "TMPDIR": str(inherited_temp), "GITHUB_OUTPUT": str(output),
               "GITHUB_EVENT_NAME": "push", "GITHUB_SHA": commits[-1], "BEFORE_SHA": commits[0],
               "FIXTURE_TRACE": str(trace)}
        for name in ("GLIMPSE_SOURCE_ROOT", "GLIMPSE_RESULTS_DIR"):
            env.pop(name, None)
        result = subprocess.run(["bash", str(scripts / "test-source-revisions.sh")],
                                cwd=checkout, env=env, text=True, capture_output=True, timeout=30)
        results = pathlib.Path(output.read_text().strip().split("=", 1)[1])
        observed = [json.loads(line) for line in trace.read_text().splitlines()]
        return result, commits, results, observed, runner_temp, inherited_temp

    def assert_cleanup(self, observed, runner_temp, inherited_temp):
        workspaces = {pathlib.Path(entry["workspace"]) for entry in observed if "workspace" in entry}
        self.assertTrue(workspaces)
        for workspace in workspaces:
            self.assertEqual(workspace.parent, runner_temp)
            self.assertFalse(workspace.exists(), f"generated workspace leaked: {workspace}")
        self.assertTrue(all(entry["workspace_mode"] == 0o700
                            for entry in observed if "workspace_mode" in entry))
        self.assertEqual(list(runner_temp.iterdir()), [runner_temp / "keep.txt"])
        self.assertEqual((runner_temp / "keep.txt").read_text(), "unrelated workspace\n")
        self.assertEqual((inherited_temp / "keep.txt").read_text(), "inherited temporary files\n")

    def assert_failed_revision(self, component):
        result, commits, results, observed, runner_temp, inherited_temp = self.run_quality_history(component)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((results / "failed-sha.txt").read_text().strip(), commits[1])
        self.assertEqual((results / "requested-shas.txt").read_text().splitlines(), commits[1:])
        self.assertEqual((results / "tested-shas.txt").read_text(), "")
        self.assertEqual(json.loads((results / "history.json").read_text())["base_sha"], commits[0])
        self.assertEqual({entry["revision"] for entry in observed}, {"1"})
        self.assertEqual(observed[-1]["component"], component)
        self.assertFalse(any(entry["component"] in ("xcodebuild", "swift") for entry in observed))
        self.assertTrue((results / commits[1]).is_dir())
        self.assert_cleanup(observed, runner_temp, inherited_temp)

    def test_broken_intermediate_signing_helper_blocks_fixed_head(self):
        self.assert_failed_revision("tooling")

    def test_broken_intermediate_monitoring_blocks_fixed_head(self):
        self.assert_failed_revision("monitoring")

    def test_archived_validators_block_fixed_head(self):
        for component in ("version", "pins"):
            with self.subTest(component=component):
                self.assert_failed_revision(component)

    def test_clean_history_uses_archived_tooling_and_retains_results(self):
        result, commits, results, observed, runner_temp, inherited_temp = self.run_quality_history()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((results / "requested-shas.txt").read_text().splitlines(), commits[1:])
        self.assertEqual((results / "tested-shas.txt").read_text().splitlines(), commits[1:])
        self.assertFalse((results / "failed-sha.txt").exists())
        for component in ("tooling", "monitoring", "version", "pins", "swift"):
            entries = [entry for entry in observed if entry["component"] == component]
            self.assertEqual([entry["revision"] for entry in entries], ["1", "2"])
            if component != "swift":
                for entry, revision in zip(entries, commits[1:]):
                    archived_root = results.parent / f"source-{revision}"
                    self.assertTrue(pathlib.Path(entry["path"]).is_relative_to(archived_root))
        app_commands = [entry for entry in observed if entry["component"] == "xcodebuild"]
        self.assertEqual({entry["revision"] for entry in app_commands}, {"1", "2"})
        for entry in observed:
            if entry["component"] in ("xcodebuild", "swift"):
                source = results.parent / f"source-{commits[int(entry['revision'])]}"
                expected_cwd = source / "GlimpseCore" if entry["component"] == "swift" else source
                self.assertEqual(pathlib.Path(entry["cwd"]), expected_cwd)
        self.assertEqual(len({entry["workspace"] for entry in observed if "workspace" in entry}), 2)
        for revision in commits[1:]:
            evidence = results / revision
            for name in ("resolve.log", "app-tests.log", "core-tests.log"):
                self.assertIn("fixture build passed", (evidence / name).read_text())
            self.assertEqual((evidence / "AppTests.xcresult/fixture.txt").read_text(),
                             "generated fixture evidence\n")
            self.assertEqual((evidence / "dependency-pins.before.sha256").read_text(),
                             (evidence / "dependency-pins.after.sha256").read_text())
            self.assertFalse((results.parent / f"source-{revision}").exists())
        self.assertTrue((results.parent.parent / "swiftpm-cache/fixture.txt").is_file())
        self.assert_cleanup(observed, runner_temp, inherited_temp)


if __name__ == "__main__":
    unittest.main()
