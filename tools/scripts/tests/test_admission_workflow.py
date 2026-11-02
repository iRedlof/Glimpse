"""Admission applies to canonical-main integration; source quality stays independent."""
import ast
import os
import pathlib
import re
import shlex
import subprocess
import tempfile
import textwrap
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]
CANONICAL = "iRedlof/Glimpse"


def evaluate_admission_condition(expression: str, github: dict[str, object]) -> bool:
    """Evaluate the observed equality/conjunction subset without executing Python."""
    tree = ast.parse(expression.replace("&&", " and "), mode="eval")
    allowed = (ast.Expression, ast.BoolOp, ast.And, ast.Compare, ast.Eq,
               ast.NotEq, ast.Attribute, ast.Name, ast.Load, ast.Constant)
    for node in ast.walk(tree):
        if not isinstance(node, allowed):
            raise ValueError(f"Unsupported condition construct: {type(node).__name__}")
        if isinstance(node, ast.Name) and node.id != "github":
            raise ValueError(f"Unsupported context: {node.id}")
        if isinstance(node, ast.Constant) and not isinstance(node.value, str):
            raise ValueError("Only string condition literals are supported")
        if isinstance(node, ast.Compare) and len(node.ops) != 1:
            raise ValueError("Chained comparisons are unsupported")

    def value(node):
        if isinstance(node, ast.Name):
            return github
        if isinstance(node, ast.Constant):
            return node.value
        if isinstance(node, ast.Attribute):
            return value(node.value)[node.attr]
        if isinstance(node, ast.BoolOp):
            return all(value(item) for item in node.values)
        if isinstance(node, ast.Compare):
            left, right = value(node.left), value(node.comparators[0])
            return left == right if isinstance(node.ops[0], ast.Eq) else left != right
        raise ValueError(f"Unsupported condition construct: {type(node).__name__}")

    return bool(value(tree.body))


def event_context(event, *, repository=CANONICAL, base="main",
                  base_repository=CANONICAL, head=CANONICAL,
                  ref="refs/heads/feature"):
    github = {"event_name": event, "repository": repository, "ref": ref, "event": {}}
    if event == "pull_request":
        github["ref"] = "refs/pull/42/merge"
        github["event"] = {
            "pull_request": {
                "base": {"ref": base, "repo": {"full_name": base_repository}},
                "head": {"repo": {"full_name": head}},
            }
        }
    return github


class AdmissionWorkflowContracts(unittest.TestCase):
    def setUp(self):
        self.workflow = (ROOT / ".github/workflows/quality.yml").read_text()
        starts = list(re.finditer(r"^  ([a-z-]+):\n", self.workflow, re.MULTILINE))
        self.jobs = {
            match[1]: self.workflow[
                match.end():starts[index + 1].start() if index + 1 < len(starts)
                else len(self.workflow)
            ]
            for index, match in enumerate(starts)
        }

    def property(self, job, name):
        match = re.search(rf"^    {re.escape(name)}: (.+)$",
                          self.jobs[job], re.MULTILINE)
        self.assertIsNotNone(match, f"{job}.{name} must be present")
        return match[1]

    def test_admission_event_repository_and_base_matrix(self):
        condition = self.property("prior-release", "if")
        cases = [
            ("canonical main", event_context("pull_request"), True),
            ("fork to canonical main",
             event_context("pull_request", head="contributor/Glimpse"), True),
            ("development base", event_context("pull_request", base="develop"), False),
            ("other repository main",
             event_context("pull_request", repository="contributor/Glimpse",
                           base_repository="contributor/Glimpse",
                           head="contributor/Glimpse"), False),
            ("inconsistent base repository",
             event_context("pull_request", base_repository="contributor/Glimpse"), False),
            ("feature push", event_context("push"), False),
            ("reusable main Release quality",
             event_context("push", ref="refs/heads/main"), False),
            ("workflow call", event_context("workflow_call"), False),
            ("manual dispatch", event_context("workflow_dispatch"), False),
        ]
        for name, github, expected in cases:
            with self.subTest(case=name):
                self.assertEqual(evaluate_admission_condition(condition, github), expected)

    def test_retargeted_main_pr_runs_admission_without_a_new_commit(self):
        trigger = re.search(r"^  pull_request:\n((?:    [^\n]*\n)*)",
                            self.workflow, re.MULTILINE)
        self.assertIsNotNone(trigger)
        types = re.search(r"^    types: \[([^\n]+)\]$", trigger[1], re.MULTILINE)
        if trigger[1]:
            self.assertIsNotNone(types, "Read the actual PR activity configuration")
        # GitHub's omitted-types default does not subscribe to base edits.
        activities = set(re.findall(r"[a-z_]+", types[1])) if types else {
            "opened", "synchronize", "reopened",
        }
        condition = self.property("prior-release", "if")
        cases = [
            ("opened main", "opened", "main", CANONICAL, None, True),
            ("opened development", "opened", "develop", CANONICAL, None, False),
            ("retargeted to main", "edited", "main", CANONICAL, "develop", True),
            ("fork retargeted to main", "edited", "main",
             "contributor/Glimpse", "develop", True),
            ("retargeted away from main", "edited", "develop", CANONICAL, "main", False),
            ("main metadata edited", "edited", "main", CANONICAL, None, True),
            ("synchronized main", "synchronize", "main", CANONICAL, None, True),
            ("reopened main", "reopened", "main", CANONICAL, None, True),
            ("closed main", "closed", "main", CANONICAL, None, False),
        ]
        for name, action, base, head, old_base, expected in cases:
            with self.subTest(case=name):
                github = event_context("pull_request", base=base, head=head)
                github["event"]["action"] = action
                # Both bases can point at the same commit; edits need no new SHA.
                github["event"]["pull_request"]["base"]["sha"] = "b" * 40
                github["event"]["pull_request"]["head"]["sha"] = "a" * 40
                if old_base:
                    github["event"]["changes"] = {"base": {"ref": {"from": old_base}}}
                runs_admission = action in activities and evaluate_admission_condition(
                    condition, github,
                )
                self.assertEqual(runs_admission, expected)

    def run_controller_selector(self, script, *, controller_present, expected_base,
                                bootstrap_sha):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            checkout = root / "trusted-controller"
            checkout.mkdir()
            environment = {key: value for key, value in os.environ.items()
                           if not key.startswith("GIT_")}
            environment.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull,
                               GIT_TERMINAL_PROMPT="0")
            for arguments in (["init", "-b", "main"],
                              ["config", "user.name", "Fixture"],
                              ["config", "user.email", "fixture@example.invalid"]):
                subprocess.run(["git", "-C", str(checkout), *arguments],
                               env=environment, check=True, capture_output=True, timeout=10)
            (checkout / "source.txt").write_text("trusted baseline\n")
            subprocess.run(["git", "-C", str(checkout), "add", "."], env=environment,
                           check=True, capture_output=True, timeout=10)
            subprocess.run(["git", "-C", str(checkout), "commit", "-m", "fixture"],
                           env=environment, check=True, capture_output=True, timeout=10)
            source_sha = subprocess.run(
                ["git", "-C", str(checkout), "rev-parse", "HEAD"], env=environment,
                check=True, capture_output=True, text=True, timeout=10,
            ).stdout.strip()
            if controller_present:
                controller = checkout / "tools/scripts/release-control.py"
                controller.parent.mkdir(parents=True)
                controller.write_text("# trusted controller fixture\n")
            output = root / "output"
            environment.update(
                GITHUB_OUTPUT=str(output),
                BOOTSTRAP_BASE_SHA=source_sha if expected_base == "current" else expected_base,
                BOOTSTRAP_SHA=bootstrap_sha,
            )
            result = subprocess.run(["bash", "-euo", "pipefail", "-c", script],
                                    cwd=root, env=environment, capture_output=True,
                                    text=True, timeout=10)
            return result, output.read_text() if output.exists() else "", source_sha

    def test_admission_uses_trusted_controller_and_existing_gate(self):
        job = self.jobs["prior-release"]
        self.assertEqual(self.property("prior-release", "name"), "Previous release verified")
        checkouts = re.findall(
            r"^      - uses: actions/checkout@[^\n]+\n        with:\n"
            r"((?:          [^\n]+\n)+)", job, re.MULTILINE,
        )
        options = [
            dict(line.strip().split(": ", 1) for line in checkout.splitlines())
            for checkout in checkouts
        ]
        self.assertEqual([item["ref"] for item in options],
                         ["main", "${{ steps.controller.outputs.sha }}"])
        for item in options:
            self.assertEqual(item["path"], "trusted-controller")
            self.assertEqual(item["persist-credentials"], "false")
        permissions = re.search(r"^    permissions:\n((?:      [^\n]+\n)+)",
                                job, re.MULTILINE)
        self.assertIsNotNone(permissions)
        self.assertEqual(
            dict(line.strip().split(": ", 1) for line in permissions[1].splitlines()),
            {"contents": "read", "actions": "read", "statuses": "read"},
        )
        selector = re.search(r"^        run: \|\n((?:          [^\n]*\n)+)",
                             job, re.MULTILINE)
        self.assertIsNotNone(selector)
        script = textwrap.dedent(selector[1])
        cases = [
            (True, "invalid", "invalid", True),
            (False, "current", "a" * 40, True),
            (False, "b" * 40, "a" * 40, False),
            (False, "invalid", "a" * 40, False),
            (False, "current", "invalid", False),
        ]
        for present, base, bootstrap, expected in cases:
            with self.subTest(controller_present=present, base=base, bootstrap=bootstrap):
                result, output, source_sha = self.run_controller_selector(
                    script, controller_present=present, expected_base=base,
                    bootstrap_sha=bootstrap,
                )
                self.assertEqual(result.returncode == 0, expected, result.stderr)
                wanted = f"sha={source_sha if present else bootstrap}\n" if expected else ""
                self.assertEqual(output, wanted)
        command = re.search(r"^        run: (python3 [^\n]+)$", job, re.MULTILINE)
        self.assertIsNotNone(command)
        arguments = shlex.split(command[1])
        self.assertEqual(arguments,
                         ["python3", "trusted-controller/tools/scripts/release-control.py", "gate"])
        controller = ast.parse((ROOT / "tools/scripts/release-control.py").read_text())
        declarations = [
            node for node in ast.walk(controller)
            if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
            and node.func.attr == "add_argument" and node.args
            and isinstance(node.args[0], ast.Constant) and node.args[0].value == "command"
        ]
        self.assertEqual(len(declarations), 1)
        choices = next(keyword.value for keyword in declarations[0].keywords
                       if keyword.arg == "choices")
        self.assertIn(arguments[2], ast.literal_eval(choices))

    def test_quality_jobs_do_not_depend_on_admission(self):
        for name in ("tooling", "app-and-core", "app-and-core-fork"):
            with self.subTest(job=name):
                self.assertIsNone(re.search(r"^    needs:", self.jobs[name], re.MULTILINE))
        self.assertEqual(self.property("tooling", "name"), "Release tooling checks")
        self.assertEqual(self.property("app-tests-verified", "name"), "App and core tests")
        self.assertEqual(
            re.findall(r"[a-z-]+", self.property("app-tests-verified", "needs")),
            ["app-and-core", "app-and-core-fork"],
        )

    def test_fork_execution_stays_on_disposable_runner(self):
        self.assertEqual(self.property("app-and-core-fork", "runs-on"), "macos-latest")
        self.assertEqual(self.property("app-and-core", "runs-on"), "[self-hosted, macOS]")
        fork_condition = self.property("app-and-core-fork", "if")
        trusted_alternatives = self.property("app-and-core", "if").split(" || ")
        self.assertEqual(len(trusted_alternatives), 2)
        cases = [
            (event_context("pull_request", head="contributor/Glimpse"), True, False),
            (event_context("pull_request"), False, True),
            (event_context("push"), False, True),
        ]
        for github, expected_fork, expected_trusted in cases:
            with self.subTest(event=github["event_name"], context=github["event"]):
                self.assertEqual(evaluate_admission_condition(fork_condition, github),
                                 expected_fork)
                self.assertEqual(any(evaluate_admission_condition(item, github)
                                     for item in trusted_alternatives), expected_trusted)


if __name__ == "__main__":
    unittest.main()
