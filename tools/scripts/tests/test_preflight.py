"""Run the real preflight against isolated machine-prerequisite fixtures."""

import json
import os
import pathlib
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest


SCRIPTS = pathlib.Path(__file__).resolve().parents[1]
TEAM = "ABCDE12345"
IDENTITY = "A" * 40
PUBLIC_KEY = "r3bpqxl5pEGWf6atYS0ZWP3FZyTVVcFAfDj22fuCioE="
IDENTITIES = (
    f'  1) {IDENTITY.lower()} "Developer ID Application: Fixture ({TEAM})"\n'
    "  1 valid identities found\n"
)
PRIVATE_SENTINEL = "fixture-private-key-must-not-be-read"
DIAGNOSTIC_SENTINEL = "fixture-untrusted-security-diagnostic"

# Native credential queries, Xcode, GitHub and installed tools are the external
# boundary. Policy loading, shell control flow and identity selection stay real.
FAKE_COMMAND = r'''
import json,os,pathlib,sys
command=pathlib.Path(sys.argv[0]).name
args=sys.argv[1:]
with open(os.environ['FIXTURE_TRACE'],'a') as target:
    target.write(json.dumps({'command':command,'args':args})+'\n')
failure=os.environ.get('FIXTURE_FAIL','')
root=pathlib.Path(os.environ['FIXTURE_ROOT'])
if command=='xcodebuild':
    if args!=['-version']: sys.exit(98)
    if failure=='xcode': sys.exit(37)
    print('Xcode Fixture\nBuild version Fixture')
elif command=='security':
    if args[:4]==['find-identity','-v','-p','codesigning']:
        if failure=='identity':
            print(os.environ['FIXTURE_DIAGNOSTIC'],file=sys.stderr)
            sys.exit(37)
        print(os.environ['FIXTURE_IDENTITIES'],end='')
    elif args[:5]==['find-generic-password','-s','https://sparkle-project.org','-a','ed25519']:
        if failure=='sparkle-key': sys.exit(37)
        if '-w' in args: print(os.environ['FIXTURE_PRIVATE'])
        else: print('    "icmt"<blob>="'+os.environ['FIXTURE_PUBLIC']+'"')
    else: sys.exit(98)
elif command=='xcrun':
    if args!=['notarytool','history','--keychain-profile','AC_PASSWORD']: sys.exit(98)
    if failure=='notary': sys.exit(37)
elif command=='defaults':
    if args!=['read',str(root/'Glimpse/Info.plist'),'SUPublicEDKey']: sys.exit(37)
    if failure=='public-key': sys.exit(37)
    print(os.environ['FIXTURE_PUBLIC'])
elif command=='find':
    if failure=='sparkle-bin': sys.exit(0)
    bin_dir=root/'Sparkle artifacts/artifacts/sparkle/Sparkle/bin'
    if '-name' in args:
        tool=bin_dir/args[args.index('-name')+1]
        if tool.is_file(): print(tool)
    else: print(bin_dir)
elif command=='gh':
    if args==['--version']: print('gh version Fixture')
    elif args==['auth','status']:
        if failure=='gh-auth': sys.exit(37)
    else: sys.exit(98)
else:
    # A check must never install, import, sign, launch or publish.
    sys.exit(98)
'''


class PreflightContracts(unittest.TestCase):
    def run_fixture(self, *, keychain="existing", identities=IDENTITIES,
                    failure="", policy="valid", missing_command=None,
                    missing_tool=None, nonexecutable_tool=None, setup=False,
                    unrelated_cwd=False):
        temporary = tempfile.TemporaryDirectory(prefix="preflight fixture ")
        self.addCleanup(temporary.cleanup)
        root = pathlib.Path(temporary.name).resolve()
        scripts = root / "tools/scripts"
        scripts.mkdir(parents=True)
        helper = scripts / "preflight.sh"
        shutil.copyfile(SCRIPTS / "preflight.sh", helper)
        self.assertEqual(helper.read_bytes(), (SCRIPTS / "preflight.sh").read_bytes())
        shutil.copyfile(SCRIPTS / "select-signing-identity.py",
                        scripts / "select-signing-identity.py")
        bin_dir = root / "fake bin"
        bin_dir.mkdir()
        trace = root / "observed.jsonl"
        for command in ("xcodebuild", "security", "xcrun", "defaults", "find",
                        "gh", "create-dmg", "brew", "generate_keys", "codesign",
                        "open", "osascript"):
            if command == missing_command:
                continue
            executable = bin_dir / command
            executable.write_text(f"#!{sys.executable}\n" + FAKE_COMMAND)
            executable.chmod(0o755)
        # No system/user PATH can accidentally supply an omitted release tool.
        for utility in ("dirname", "head", "grep", "sed"):
            executable = shutil.which(utility)
            self.assertIsNotNone(executable)
            (bin_dir / utility).symlink_to(executable)
        (bin_dir / "python3").symlink_to(sys.executable)
        sparkle = root / "Sparkle artifacts/artifacts/sparkle/Sparkle/bin"
        sparkle.mkdir(parents=True)
        for tool in ("sign_update", "generate_appcast", "generate_keys"):
            if tool == missing_tool:
                continue
            executable = sparkle / tool
            executable.write_text(f"#!{sys.executable}\n" + FAKE_COMMAND)
            executable.chmod(0o644 if tool == nonexecutable_tool else 0o755)
        policy_file = root / ".github/release-policy.json"
        policy_file.parent.mkdir()
        if policy != "missing":
            policy_file.write_text("not JSON" if policy == "malformed"
                                   else json.dumps({"team_id": "" if policy == "invalid-team"
                                                    else TEAM}))
        info = root / "Glimpse/Info.plist"
        info.parent.mkdir()
        info.write_bytes(plistlib.dumps({"SUPublicEDKey": PUBLIC_KEY}))
        keychain_file = root / "existing signing keychain.keychain-db"
        keychain_file.write_bytes(b"fixture keychain placeholder\n")
        env = {**os.environ, "PATH": str(bin_dir),
               "FIXTURE_ROOT": str(root), "FIXTURE_TRACE": str(trace),
               "FIXTURE_IDENTITIES": identities, "FIXTURE_FAIL": failure,
               "FIXTURE_PUBLIC": PUBLIC_KEY, "FIXTURE_PRIVATE": PRIVATE_SENTINEL,
               "FIXTURE_DIAGNOSTIC": DIAGNOSTIC_SENTINEL}
        env.pop("GLIMPSE_SIGNING_KEYCHAIN", None)
        keychain_value = {
            "existing": str(keychain_file), "missing": str(root / "absent.keychain-db"),
            "relative": "existing signing keychain.keychain-db",
            "directory": str(root), "empty": "", "unset": None,
        }[keychain]
        if keychain_value is not None:
            env["GLIMPSE_SIGNING_KEYCHAIN"] = keychain_value
        cwd = root
        if unrelated_cwd:
            cwd = root / "unrelated caller"
            cwd.mkdir()
        args = ["/bin/bash", str(helper)] + (["--setup"] if setup else [])
        result = subprocess.run(args, cwd=cwd, env=env, text=True, capture_output=True,
                                input="s\n" if setup else "", timeout=25)
        observed = [json.loads(line) for line in trace.read_text().splitlines()]
        return result, root, keychain_file, observed

    def assert_not_ready(self, result):
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("Machine is ready for releases", result.stdout)

    def test_ready_requires_policy_identity_in_explicit_keychain_with_spaces(self):
        result, _, keychain, observed = self.run_fixture()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        identity_queries = [record["args"] for record in observed
                            if record["command"] == "security"
                            and record["args"][0] == "find-identity"]
        self.assertEqual(identity_queries,
                         [["find-identity", "-v", "-p", "codesigning", str(keychain)]])

    def test_unset_empty_relative_absent_and_directory_keychains_are_not_ready(self):
        for keychain in ("unset", "empty", "relative", "missing", "directory"):
            with self.subTest(keychain=keychain):
                result, _, _, observed = self.run_fixture(keychain=keychain)
                self.assert_not_ready(result)
                self.assertFalse(any(record["command"] == "security"
                                     and record["args"][0] == "find-identity"
                                     for record in observed))

    def test_missing_wrong_team_ambiguous_and_malformed_identities_are_not_ready(self):
        invalid = (
            "  0 valid identities found\n",
            f'  1) {IDENTITY} "Developer ID Application: Fixture (ZZZZZ99999)"\n',
            IDENTITIES + f'  2) {"B" * 40} "Developer ID Application: Other ({TEAM})"\n',
            f'  1) bad-sha "Developer ID Application: Fixture ({TEAM})"\n',
        )
        for identities in invalid:
            with self.subTest(identities=identities):
                result, _, _, _ = self.run_fixture(identities=identities)
                self.assert_not_ready(result)

    def test_failed_identity_query_is_not_ready_and_does_not_echo_raw_output(self):
        result, _, _, _ = self.run_fixture(failure="identity")
        self.assert_not_ready(result)
        self.assertNotIn(DIAGNOSTIC_SENTINEL, result.stdout + result.stderr)

    def test_missing_malformed_and_invalid_team_policy_are_not_ready(self):
        for policy in ("missing", "malformed", "invalid-team"):
            with self.subTest(policy=policy):
                result, _, _, _ = self.run_fixture(policy=policy)
                self.assert_not_ready(result)

    def test_missing_notarization_profile_is_not_ready_even_in_setup_skip(self):
        for setup in (False, True):
            with self.subTest(setup=setup):
                result, _, _, observed = self.run_fixture(failure="notary", setup=setup)
                self.assert_not_ready(result)
                self.assertFalse(any(record["command"] == "xcrun"
                                     and "store-credentials" in record["args"]
                                     for record in observed))

    def test_missing_sparkle_key_entry_or_source_public_key_is_not_ready(self):
        for failure in ("sparkle-key", "public-key"):
            with self.subTest(failure=failure):
                result, _, _, _ = self.run_fixture(failure=failure)
                self.assert_not_ready(result)

    def test_sparkle_preflight_reads_metadata_without_requesting_private_key(self):
        result, _, _, observed = self.run_fixture()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        queries = [record["args"] for record in observed
                   if record["command"] == "security"
                   and record["args"][0] == "find-generic-password"]
        self.assertEqual(queries, [["find-generic-password", "-s",
                                   "https://sparkle-project.org", "-a", "ed25519"]])
        self.assertNotIn(PRIVATE_SENTINEL, result.stdout + result.stderr)

    def test_missing_or_nonexecutable_sparkle_tools_are_not_ready(self):
        cases = (
            {"failure": "sparkle-bin"}, {"missing_tool": "sign_update"},
            {"missing_tool": "generate_appcast"}, {"nonexecutable_tool": "sign_update"},
        )
        for case in cases:
            with self.subTest(case=case):
                result, _, _, _ = self.run_fixture(**case)
                self.assert_not_ready(result)

    def test_missing_github_auth_cli_or_dmg_tool_is_not_ready(self):
        for case in ({"failure": "gh-auth"}, {"missing_command": "gh"},
                     {"missing_command": "create-dmg"}):
            with self.subTest(case=case):
                result, _, _, _ = self.run_fixture(**case)
                self.assert_not_ready(result)

    def test_prerequisites_resolve_from_script_root_when_called_elsewhere(self):
        result, root, _, observed = self.run_fixture(unrelated_cwd=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        reads = [record["args"] for record in observed if record["command"] == "defaults"]
        self.assertEqual(reads, [["read", str(root / "Glimpse/Info.plist"), "SUPublicEDKey"]])

    def test_check_and_already_ready_setup_do_not_mutate_credentials_or_publish(self):
        for setup in (False, True):
            with self.subTest(setup=setup):
                result, _, _, observed = self.run_fixture(setup=setup)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                for record in observed:
                    self.assertNotIn(record["command"], ("brew", "generate_keys", "codesign",
                                                        "open", "osascript", "create-dmg"))
                    if record["command"] == "security":
                        self.assertIn(record["args"][0], ("find-identity",
                                                         "find-generic-password"))
                        self.assertNotIn("-w", record["args"])
                    if record["command"] == "gh":
                        self.assertIn(record["args"], (["--version"], ["auth", "status"]))
                    if record["command"] == "xcrun":
                        self.assertEqual(record["args"],
                                         ["notarytool", "history", "--keychain-profile",
                                          "AC_PASSWORD"])


if __name__ == "__main__":
    unittest.main()
