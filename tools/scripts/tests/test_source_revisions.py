import json
import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest

SCRIPTS = pathlib.Path(__file__).parents[1]


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


if __name__ == "__main__":
    unittest.main()
