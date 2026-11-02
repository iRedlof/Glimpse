"""Hooks must reject operations when they cannot verify remote release state."""
import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]
HOOKS = ROOT / "tools/scripts/hooks"


class ReleaseHookContracts(unittest.TestCase):
    def hook_fixture(self, staged, fail_quality=False, mutate_index=False,
                     foreign_repository=False):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = pathlib.Path(temporary.name).resolve()
        scripts = root / "tools/scripts"
        (scripts / "hooks").mkdir(parents=True)
        shutil.copy(HOOKS / "pre-commit", scripts / "hooks")
        (scripts / "release-control.py").write_text("print('verified remote fixture')\n")
        nested = root.parent / (root.name + "-nested")
        self.addCleanup(lambda: shutil.rmtree(nested, ignore_errors=True))
        (scripts / "quality-gate.sh").write_text(
            '#!/bin/bash\nprintf "executed\\n" > "$QUALITY_MARKER"\n' +
            ('set -e\ngit init -b main "$NESTED_REPO" >/dev/null\n'
             'test "$(git -C "$NESTED_REPO" rev-parse --show-toplevel)" = "$NESTED_REPO"\n'
             'git -C "$NESTED_REPO" config user.name Nested\n'
             'git -C "$NESTED_REPO" config user.email nested@example.invalid\n'
             'printf "nested\\n" > "$NESTED_REPO/source.txt"\n'
             'git -C "$NESTED_REPO" add .\n'
             'git -C "$NESTED_REPO" commit -m nested >/dev/null\n'
             if foreign_repository else "") +
            ('printf "changed\\n" > "$ORIGINAL_ROOT/source.txt"\ngit -C "$ORIGINAL_ROOT" add source.txt\n'
             if mutate_index else "") +
            ("exit 1\n" if fail_quality else "exit 0\n")
        )
        (scripts / "quality-gate.sh").chmod(0o755)
        subprocess.run(["git", "init", "-b", "main", str(root)], check=True, capture_output=True)
        subprocess.run(["git", "-C", str(root), "add", "."], check=True)
        if not staged:
            (root / "unstaged.txt").write_text("must be staged before tests\n")
        marker = root.parent / (root.name + "-quality")
        self.addCleanup(lambda: marker.unlink(missing_ok=True))
        env = {**os.environ, "QUALITY_MARKER": str(marker), "ORIGINAL_ROOT": str(root),
               "NESTED_REPO": str(nested),
               "GLIMPSE_BUILD_ROOT": str(root.parent / (root.name + "-build"))}
        if foreign_repository:
            env.update(GIT_DIR=str(root / ".git"), GIT_INDEX_FILE=str(root / ".git/index"),
                       GIT_WORK_TREE=str(root), GIT_PREFIX="")
        result = subprocess.run(
            ["bash", str(scripts / "hooks/pre-commit")], cwd=root,
            env=env,
            text=True, capture_output=True, timeout=10,
        )
        self.addCleanup(lambda: shutil.rmtree(root.parent / (root.name + "-build"), ignore_errors=True))
        return result, marker.exists()

    def test_staged_snapshot_clears_hook_repository_environment(self):
        # Real Git hooks export these variables; nested tests must own their repos.
        result, tested = self.hook_fixture(staged=True, foreign_repository=True)
        self.assertTrue(tested)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_index_changes_during_quality_require_retest(self):
        # An editor/agent staging new source while tests run must invalidate proof.
        result, tested = self.hook_fixture(staged=True, mutate_index=True)
        self.assertTrue(tested)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Source changed during tests", result.stderr)

    def test_unstaged_source_blocks_commit_before_quality(self):
        result, tested = self.hook_fixture(staged=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(tested)
        self.assertIn("Stage all source changes", result.stderr)

    def test_staged_source_requires_quality_success(self):
        for fail_quality in (False, True):
            with self.subTest(quality_failure=fail_quality):
                result, tested = self.hook_fixture(staged=True, fail_quality=fail_quality)
                self.assertTrue(tested)
                self.assertEqual(result.returncode == 0, not fail_quality)

    def test_both_hooks_fail_closed_when_github_is_unreachable(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = pathlib.Path(temporary)
            repo = directory / "repo"
            (repo / "tools/scripts/hooks").mkdir(parents=True)
            (repo / ".github").mkdir()
            subprocess.run(["git", "init", "-b", "main", str(repo)], check=True, capture_output=True)
            shutil.copy(ROOT / ".github/release-policy.json", repo / ".github")
            shutil.copy(ROOT / "tools/scripts/release-control.py", repo / "tools/scripts")
            for name in ("pre-commit", "pre-push"):
                shutil.copy(HOOKS / name, repo / "tools/scripts/hooks")
            gh = directory / "gh"
            gh.write_text("#!/bin/bash\nexit 1\n")
            gh.chmod(0o755)
            env = {**os.environ, "PATH": str(directory) + os.pathsep + os.environ["PATH"]}
            for name in ("pre-commit", "pre-push"):
                with self.subTest(hook=name):
                    result = subprocess.run(
                        ["bash", str(repo / "tools/scripts/hooks" / name)], cwd=repo, env=env,
                        input="", text=True, capture_output=True, timeout=10,
                    )
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn("GitHub request failed", result.stderr)


if __name__ == "__main__":
    unittest.main()
