import importlib.util
import json
import os
import pathlib
import shlex
import subprocess
import tempfile
import unittest
from unittest import mock

SCRIPTS = pathlib.Path(__file__).parents[1]
HELPER = SCRIPTS / "select-signing-identity.py"
WORKFLOW = SCRIPTS.parents[1] / ".github/workflows/release.yml"
TEAM = "TEAM123456"
IDENTITY = "A" * 40
SECOND_IDENTITY = "B" * 40
ORIGINAL_KEYCHAINS = ["/Users/Fixture/User Keychains/login.keychain-db", "/Library/Keychains/System.keychain"]
CERTIFICATE_FILES = ["build_certificate.p12", "AppleRoot.cer", "AppleWWDRCAG3.cer", "DeveloperIDG2CA.cer"]


def identity_line(sha=IDENTITY, name=f"Developer ID Application: Fixture ({TEAM})"):
    return f'  1) {sha} "{name}"\n'


def workflow_run(name):
    for section in WORKFLOW.read_text().split("      - name: ")[1:]:
        if not section.startswith(name + "\n"):
            continue
        lines = section.splitlines()
        start = lines.index("        run: |") + 1
        run = []
        for line in lines[start:]:
            if line.startswith("          "):
                run.append(line[10:])
            elif not line.strip():
                run.append("")
            else:
                break
        return "\n".join(run)
    raise AssertionError(f"Missing release step: {name}")


class SigningIdentitySelection(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec = importlib.util.spec_from_file_location("signing_identity", HELPER)
        cls.helper = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.helper)

    def test_selects_distribution_identity_and_ignores_development(self):
        identities = identity_line(SECOND_IDENTITY, f"Apple Development: Fixture ({TEAM})")
        identities += identity_line(IDENTITY.lower()) + "  2 valid identities found\n"
        self.assertEqual(self.helper.select_identity(identities, TEAM), IDENTITY)

    def test_missing_distribution_identity_fails(self):
        for identities in ("  0 valid identities found\n",
                           identity_line(name=f"Apple Development: Fixture ({TEAM})")):
            with self.subTest(identities=identities), self.assertRaises(ValueError):
                self.helper.select_identity(identities, TEAM)

    def test_wrong_team_fails_even_when_expected_team_is_also_present(self):
        wrong = identity_line(SECOND_IDENTITY, "Developer ID Application: Other (WRONG12345)")
        for identities in (wrong, identity_line() + wrong):
            with self.subTest(identities=identities), self.assertRaises(ValueError):
                self.helper.select_identity(identities, TEAM)

    def test_multiple_distribution_identities_fail(self):
        with self.assertRaises(ValueError):
            self.helper.select_identity(identity_line() + identity_line(SECOND_IDENTITY), TEAM)

    def test_invalid_identity_and_team_formats_fail(self):
        for identities in (identity_line("not-a-sha"), identity_line()[:-1] + " (CSSMERR_TP_CERT_EXPIRED)\n"):
            with self.subTest(identities=identities), self.assertRaises(ValueError):
                self.helper.select_identity(identities, TEAM)
        with self.assertRaises(ValueError):
            self.helper.select_identity(identity_line(), "")

    def test_security_is_scoped_to_exact_keychain_with_spaces(self):
        keychain = "/private/tmp/job signing/job.keychain-db"
        with mock.patch.object(self.helper.subprocess, "run",
                               return_value=subprocess.CompletedProcess([], 0, identity_line(), "")) as run:
            self.assertEqual(self.helper.identity_from_keychain(keychain, TEAM), IDENTITY)
        args, kwargs = run.call_args
        self.assertEqual(args[0], ["security", "find-identity", "-v", "-p", "codesigning", keychain])
        self.assertTrue(kwargs["check"])
        self.assertTrue(kwargs["capture_output"])
        self.assertGreater(kwargs["timeout"], 0)
        self.assertLessEqual(kwargs["timeout"], 30)

    def test_security_error_and_timeout_fail_without_command_output(self):
        errors = (subprocess.CalledProcessError(7, ["security"], output="private output",
                                               stderr="private output"),
                  subprocess.TimeoutExpired(["security"], 1, output="private output"))
        for error in errors:
            with self.subTest(error=type(error).__name__):
                with mock.patch.object(self.helper.subprocess, "run", side_effect=error):
                    with self.assertRaises(RuntimeError) as raised:
                        self.helper.identity_from_keychain("/tmp/job.keychain-db", TEAM)
                self.assertNotIn("private output", str(raised.exception))

    def test_cli_security_failure_emits_no_identity_or_raw_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            security = root / "security"
            security.write_text("#!/bin/bash\nprintf 'private output\\n' >&2\nexit 7\n")
            security.chmod(0o755)
            result = subprocess.run(
                ["python3", str(HELPER), "--keychain", str(root / "job keychain"), "--team-id", TEAM],
                env={**os.environ, "PATH": str(root) + os.pathsep + os.environ["PATH"]},
                text=True, capture_output=True, timeout=10,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(result.stdout, "")
            self.assertNotIn("private output", result.stderr)

    def test_cli_success_prints_only_selected_sha(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            security = root / "security"
            security.write_text("#!/bin/bash\nprintf '%s\\n' " + shlex.quote(identity_line()) + "\n")
            security.chmod(0o755)
            result = subprocess.run(
                ["python3", str(HELPER), "--keychain", str(root / "job keychain"), "--team-id", TEAM],
                env={**os.environ, "PATH": str(root) + os.pathsep + os.environ["PATH"]},
                text=True, capture_output=True, timeout=10,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, IDENTITY + "\n")
            self.assertEqual(result.stderr, "")


class ReleaseSigningContracts(unittest.TestCase):
    def run_fixture(self, scripts, smoke_status=0, verify_status=0, setup=None):
        temporary = tempfile.TemporaryDirectory(prefix="signing fixture ")
        self.addCleanup(temporary.cleanup)
        root = pathlib.Path(temporary.name).resolve()
        (root / "build").mkdir()
        runner_temp = root / "runner temp"
        runner_temp.mkdir()
        (runner_temp / "keep.txt").write_text("caller data\n")
        bin_dir = root / "bin"
        bin_dir.mkdir()
        trace = root / "observed.jsonl"
        for command in ("xcodebuild", "codesign"):
            executable = bin_dir / command
            executable.write_text("""#!/usr/bin/env python3
import json,os,pathlib,sys
args=sys.argv[1:]
record={'command':pathlib.Path(sys.argv[0]).name,'args':args}
if '-exportOptionsPlist' in args:
    import plistlib
    with open(args[args.index('-exportOptionsPlist')+1],'rb') as source:
        record['export_options']=plistlib.load(source)
if '-exportPath' in args:
    (pathlib.Path(args[args.index('-exportPath')+1])/'Glimpse.app').mkdir(parents=True)
with open(os.environ['FIXTURE_TRACE'],'a') as trace:
    trace.write(json.dumps(record)+'\\n')
if '--sign' in args:
    assert pathlib.Path(args[-1]).is_file()
    sys.exit(int(os.environ['FIXTURE_SMOKE_STATUS']))
if '--verify' in args:
    sys.exit(int(os.environ['FIXTURE_VERIFY_STATUS']))
""")
            executable.chmod(0o755)
        keychain = runner_temp / "job signing.keychain-db"
        env = {**os.environ, "PATH": str(bin_dir) + os.pathsep + os.environ["PATH"],
               "RUNNER_TEMP": str(runner_temp), "DERIVED_DATA": str(root / "Derived Data"),
               "SIGNING_IDENTITY": IDENTITY, "SIGNING_KEYCHAIN": str(keychain), "TEAM_ID": TEAM,
               "GITHUB_RUN_ID": "12345", "FIXTURE_TRACE": str(trace),
               "FIXTURE_SMOKE_STATUS": str(smoke_status), "FIXTURE_VERIFY_STATUS": str(verify_status)}
        if setup:
            env.update(setup(root, runner_temp, bin_dir))
        result = subprocess.run(["bash", "-c", "set -euo pipefail\n" + "\n".join(scripts)],
                                cwd=root, env=env, text=True, capture_output=True, timeout=10)
        records = [json.loads(line) for line in trace.read_text().splitlines()] if trace.exists() else []
        return result, root, keychain, records

    def test_archive_and_export_use_the_same_manual_identity(self):
        archive = workflow_run("Archive")
        self.assertIn("CODE_SIGN_STYLE=Manual", archive)
        self.assertIn('CODE_SIGN_IDENTITY="$SIGNING_IDENTITY"', archive)
        result, root, keychain, records = self.run_fixture([archive, workflow_run("Export")])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        archive_args = records[0]["args"]
        self.assertEqual([arg for arg in archive_args if arg.startswith("CODE_SIGN_STYLE=")],
                         ["CODE_SIGN_STYLE=Manual"])
        self.assertEqual([arg for arg in archive_args if arg.startswith("CODE_SIGN_IDENTITY=")],
                         [f"CODE_SIGN_IDENTITY={IDENTITY}"])
        self.assertIn(f"DEVELOPMENT_TEAM={TEAM}", archive_args)
        flags = next(arg.split("=", 1)[1] for arg in archive_args if arg.startswith("OTHER_CODE_SIGN_FLAGS="))
        self.assertEqual(shlex.split(flags), ["--keychain", str(keychain)])
        self.assertEqual(records[1]["export_options"]["signingStyle"], "manual")
        self.assertEqual(records[1]["export_options"]["signingCertificate"], IDENTITY)
        self.assertEqual(records[1]["export_options"]["teamID"], TEAM)

    def test_selection_uses_job_keychain_and_publishes_same_signing_inputs(self):
        install = workflow_run("Install signing certificate")
        self.assertIn("select-signing-identity.py", install)
        self.assertIn('--keychain "$KEYCHAIN_PATH"', install)
        self.assertIn('--team-id "$TEAM_ID"', install)
        self.assertIn("SIGNING_IDENTITY=%s", install)
        self.assertIn("SIGNING_KEYCHAIN=%s", install)
        self.assertIn('"$SIGNING_IDENTITY" "$KEYCHAIN_PATH"', install)
        self.assertIn('security list-keychains -d user -s "$KEYCHAIN_PATH"', install)
        self.assertIn("TEAM_ID: ${{ secrets.TEAM_ID }}", WORKFLOW.read_text())

    def test_smoke_uses_selected_key_and_cleans_probe_on_success_and_failure(self):
        smoke = workflow_run("Validate signing identity")
        self.assertLess(WORKFLOW.read_text().index("- name: Validate signing identity"),
                        WORKFLOW.read_text().index("- name: Archive"))
        for sign_status, verify_status in ((0, 0), (41, 0), (0, 43)):
            with self.subTest(sign_status=sign_status, verify_status=verify_status):
                result, root, keychain, records = self.run_fixture(
                    [smoke, workflow_run("Archive")], smoke_status=sign_status, verify_status=verify_status
                )
                self.assertEqual(result.returncode, sign_status or verify_status, result.stdout + result.stderr)
                signing = records[0]["args"]
                self.assertEqual(signing[signing.index("--sign") + 1], IDENTITY)
                self.assertEqual(signing[signing.index("--keychain") + 1], str(keychain))
                self.assertIn("--timestamp=none", signing)
                self.assertFalse(pathlib.Path(signing[-1]).parent.exists())
                self.assertEqual((root / "runner temp/keep.txt").read_text(), "caller data\n")
                if not sign_status and not verify_status:
                    self.assertIn("--verify", records[1]["args"])
                    self.assertEqual(records[2]["command"], "xcodebuild")
                else:
                    self.assertFalse(any(record["command"] == "xcodebuild" for record in records))

    def write_fake_security(self, bin_dir):
        security = bin_dir / "security"
        security.write_text("""#!/usr/bin/env python3
import json,os,pathlib,shlex,sys
args=sys.argv[1:]
record={'command':'security','args':args}
if args[0]=='import' and pathlib.Path(args[1]).name=='build_certificate.p12':
    record['certificate_mode']=pathlib.Path(args[1]).stat().st_mode & 0o777
with open(os.environ['FIXTURE_TRACE'],'a') as trace:
    trace.write(json.dumps(record)+'\\n')
if args[0]=='list-keychains':
    if '-s' in args: sys.exit(int(os.environ.get('FIXTURE_RESTORE_STATUS','0')))
    print(shlex.join(json.loads(os.environ['FIXTURE_ORIGINAL_KEYCHAINS'])))
if 'certificate_mode' in record: sys.exit(int(os.environ.get('FIXTURE_IMPORT_STATUS','0')))
""")
        security.chmod(0o755)

    def test_import_failure_creates_private_certificate_and_always_cleans_job_files(self):
        def setup(root, runner_temp, bin_dir):
            self.write_fake_security(bin_dir)
            for name in ("curl", "base64"):
                executable = bin_dir / name
                executable.write_text("""#!/usr/bin/env python3
import pathlib,sys
args=sys.argv[1:]
pathlib.Path(args[args.index('-o')+1]).write_bytes(b'fixture certificate data')
""")
                executable.chmod(0o755)
            openssl = bin_dir / "openssl"
            openssl.write_text("#!/bin/bash\nprintf 'fixture-password\\n'\n")
            openssl.chmod(0o755)
            return {"MACOS_CERTIFICATE": "fixture data", "MACOS_CERTIFICATE_PWD": "fixture password",
                    "FIXTURE_IMPORT_STATUS": "73",
                    "FIXTURE_ORIGINAL_KEYCHAINS": json.dumps(ORIGINAL_KEYCHAINS)}

        install = workflow_run("Install signing certificate")
        script = ("set +e\n(set -euo pipefail\n" + install + ")\n"
                  "install_status=$?\nset -e\n" + workflow_run("Clean up") + '\nexit "$install_status"')
        result, root, keychain, records = self.run_fixture([script], setup=setup)
        self.assertEqual(result.returncode, 73, result.stdout + result.stderr)
        imported = next(record for record in records if "certificate_mode" in record)
        self.assertEqual(imported["certificate_mode"], 0o600)
        for name in CERTIFICATE_FILES:
            self.assertFalse((root / "runner temp" / name).exists(), name)
        restored = next(record["args"] for record in records
                        if record["args"][0] == "list-keychains" and "-s" in record["args"])
        self.assertEqual(restored, ["list-keychains", "-d", "user", "-s", *ORIGINAL_KEYCHAINS])
        self.assertFalse((root / "runner temp/original-keychains.txt").exists())
        self.assertEqual((root / "runner temp/keep.txt").read_text(), "caller data\n")

    def test_restore_failure_retains_restore_record_and_cleans_certificate_files(self):
        def setup(root, runner_temp, bin_dir):
            self.write_fake_security(bin_dir)
            for name in CERTIFICATE_FILES:
                (runner_temp / name).write_text("remaining job certificate data\n")
            (runner_temp / "original-keychains.txt").write_text(shlex.join(ORIGINAL_KEYCHAINS))
            return {"FIXTURE_RESTORE_STATUS": "71",
                    "FIXTURE_ORIGINAL_KEYCHAINS": json.dumps(ORIGINAL_KEYCHAINS)}

        result, root, keychain, records = self.run_fixture([workflow_run("Clean up")], setup=setup)
        self.assertNotEqual(result.returncode, 0)
        for name in CERTIFICATE_FILES:
            self.assertFalse((root / "runner temp" / name).exists(), name)
        self.assertEqual((root / "runner temp/original-keychains.txt").read_text(),
                         shlex.join(ORIGINAL_KEYCHAINS))
        self.assertEqual((root / "runner temp/keep.txt").read_text(), "caller data\n")


if __name__ == "__main__":
    unittest.main()
