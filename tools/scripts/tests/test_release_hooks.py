"""Local hooks preserve source quality independently of distribution health."""
import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]
HOOKS = ROOT / "tools/scripts/hooks"


class ReleaseHookContracts(unittest.TestCase):
    def fixture_environment(self):
        environment = {key: value for key, value in os.environ.items()
                       if not key.startswith("GIT_")}
        environment.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull,
                           GIT_TERMINAL_PROMPT="0")
        return environment

    def private_command_path(self, root, *, unusable_gh=False):
        commands = root / "command-path"
        commands.mkdir()
        for name in ("bash", "git", "python3", "mkdir", "mktemp", "tar", "rm",
                     "dirname", "chmod"):
            executable = shutil.which(name)
            self.assertIsNotNone(executable, name)
            (commands / name).symlink_to(executable)
        if unusable_gh:
            gh = commands / "gh"
            gh.write_text('#!/bin/bash\nprintf "called\\n" > "$GH_MARKER"\nexit 9\n')
            gh.chmod(0o755)
        return str(commands)

    def write_admission_sentinel(self, scripts):
        (scripts / "release-control.py").write_text(
            "import os, pathlib, sys\n"
            "pathlib.Path(os.environ['ADMISSION_MARKER']).write_text('gate\\n')\n"
            "sys.exit(0 if os.environ['ADMISSION_STATE'] == 'verified' else 1)\n"
        )

    def hook_fixture(self, staged, fail_quality=False, mutate_index=False,
                     foreign_repository=False, *, admission_state="verified",
                     mutate_worktree=False, missing_gh=False):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = pathlib.Path(temporary.name).resolve()
        scripts = root / "tools/scripts"
        (scripts / "hooks").mkdir(parents=True)
        shutil.copy(HOOKS / "pre-commit", scripts / "hooks")
        self.write_admission_sentinel(scripts)
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
            ('printf "changed\\n" > "$ORIGINAL_ROOT/source.txt"\n'
             if mutate_worktree == "tracked" else "") +
            ('printf "new\\n" > "$ORIGINAL_ROOT/new-source.txt"\n'
             if mutate_worktree == "untracked" else "") +
            ("exit 1\n" if fail_quality else "exit 0\n")
        )
        (scripts / "quality-gate.sh").chmod(0o755)
        (root / "source.txt").write_text("original\n")
        env = self.fixture_environment()
        if missing_gh:
            env["PATH"] = self.private_command_path(root)
            self.assertIsNone(shutil.which("gh", path=env["PATH"]))
        subprocess.run(["git", "init", "-b", "main", str(root)],
                       env=env, check=True, capture_output=True)
        subprocess.run(["git", "-C", str(root), "add", "."], env=env, check=True)
        if not staged:
            (root / "unstaged.txt").write_text("must be staged before tests\n")
        marker = root.parent / (root.name + "-quality")
        self.addCleanup(lambda: marker.unlink(missing_ok=True))
        admission = root.parent / (root.name + "-admission")
        self.admission_marker = admission
        self.addCleanup(lambda: admission.unlink(missing_ok=True))
        env.update(QUALITY_MARKER=str(marker), ORIGINAL_ROOT=str(root),
                   NESTED_REPO=str(nested), ADMISSION_MARKER=str(admission),
                   ADMISSION_STATE=admission_state,
                   GLIMPSE_BUILD_ROOT=str(root.parent / (root.name + "-build")))
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

    def make_installer_fixture(self, *, collision=False, linked_worktrees=False):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        directory = pathlib.Path(temporary.name).resolve()
        root = directory / "repo"
        scripts = root / "tools/scripts"
        (scripts / "hooks").mkdir(parents=True)
        for name in ("pre-commit", "pre-push"):
            shutil.copy(HOOKS / name, scripts / "hooks")
        shutil.copy(ROOT / "tools/scripts/install-release-hooks.sh", scripts)
        self.write_admission_sentinel(scripts)
        marker = directory / "admission"
        env = self.fixture_environment()
        env.update(ADMISSION_MARKER=str(marker), ADMISSION_STATE="offline",
                   GLIMPSE_BUILD_ROOT=str(directory / "build"),
                   GH_MARKER=str(directory / "gh-called"))

        def git(*arguments):
            return subprocess.run(["git", "-C", str(root), *arguments], env=env,
                                  check=True, capture_output=True, text=True, timeout=10)

        git("init", "-b", "main")
        git("config", "user.name", "Fixture")
        git("config", "user.email", "fixture@example.invalid")
        git("add", ".")
        git("commit", "-m", "fixture")
        sibling = None
        if linked_worktrees:
            linked = directory / "linked"
            git("worktree", "add", "-b", "fixture-linked", str(linked))
            git("config", "--local", "extensions.worktreeConfig", "true")
            git("config", "--worktree", "core.hooksPath", str(directory / "sibling-hooks"))
            sibling, root = root, linked
        if collision:
            custom = directory / "custom-hooks"
            custom.mkdir()
            (custom / "pre-commit").write_text("preserve this existing hook\n")
            subprocess.run(["git", "-C", str(root), "config", "core.hooksPath", str(custom)],
                           env=env, check=True, capture_output=True, timeout=10)
        return root, sibling, env, marker

    def run_installer(self, root, env):
        return subprocess.run(
            ["/bin/bash", str(root / "tools/scripts/install-release-hooks.sh")],
            cwd=root, env=env, text=True, capture_output=True, timeout=10,
        )

    def configured_hook_path(self, root, env):
        result = subprocess.run(["git", "-C", str(root), "config", "--get", "core.hooksPath"],
                                env=env, text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.strip()

    def test_staged_commit_never_queries_distribution(self):
        for state in ("pending", "failed", "offline"):
            with self.subTest(admission_state=state):
                result, tested = self.hook_fixture(staged=True, admission_state=state)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertTrue(tested)
                self.assertFalse(self.admission_marker.exists())

    def test_staged_commit_does_not_require_gh(self):
        result, tested = self.hook_fixture(staged=True, missing_gh=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(tested)
        self.assertFalse(self.admission_marker.exists())

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

    def test_worktree_changes_during_quality_require_retest(self):
        for mutation in ("tracked", "untracked"):
            with self.subTest(mutation=mutation):
                result, tested = self.hook_fixture(staged=True, mutate_worktree=mutation)
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

    def test_pre_push_is_independent_of_distribution(self):
        for unusable_gh in (False, True):
            for push_input in ("", "refs/heads/example " + "a" * 40 + " refs/heads/example " + "0" * 40 + "\n"):
                with self.subTest(unusable_gh=unusable_gh, empty_input=not push_input):
                    root, _, env, marker = self.make_installer_fixture()
                    env["PATH"] = self.private_command_path(root.parent, unusable_gh=unusable_gh)
                    result = subprocess.run(
                        ["/bin/bash", str(root / "tools/scripts/hooks/pre-push")],
                        cwd=root, env=env, input=push_input,
                        text=True, capture_output=True, timeout=10,
                    )
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertFalse(marker.exists())
                    self.assertFalse(pathlib.Path(env["GH_MARKER"]).exists())

    def test_offline_install_and_repeat_preserve_hook_contract(self):
        root, _, env, marker = self.make_installer_fixture()
        env["PATH"] = self.private_command_path(root.parent)
        for _ in range(2):
            result = self.run_installer(root, env)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(self.configured_hook_path(root, env), str(root / "tools/scripts/hooks"))
            for name in ("pre-commit", "pre-push"):
                self.assertTrue(os.access(root / "tools/scripts/hooks" / name, os.X_OK))
            self.assertFalse(marker.exists())

    def test_existing_custom_hook_path_is_preserved(self):
        root, _, env, marker = self.make_installer_fixture(collision=True)
        expected = self.configured_hook_path(root, env)
        original = (pathlib.Path(expected) / "pre-commit").read_bytes()
        result = self.run_installer(root, env)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Existing core.hooksPath", result.stderr)
        self.assertEqual(self.configured_hook_path(root, env), expected)
        self.assertEqual((pathlib.Path(expected) / "pre-commit").read_bytes(), original)
        self.assertFalse(marker.exists())

    def test_linked_worktree_install_does_not_redirect_sibling(self):
        root, sibling, env, marker = self.make_installer_fixture(linked_worktrees=True)
        before = self.configured_hook_path(sibling, env)
        result = self.run_installer(root, env)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.configured_hook_path(root, env), str(root / "tools/scripts/hooks"))
        self.assertEqual(self.configured_hook_path(sibling, env), before)
        self.assertFalse(marker.exists())


if __name__ == "__main__":
    unittest.main()
