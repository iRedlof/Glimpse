"""Offline traces of the actual local helper; native release tools are fakes."""

import json
import os
import pathlib
import plistlib
import shlex
import shutil
import subprocess
import tempfile
import unittest

SCRIPTS = pathlib.Path(__file__).parents[1]
TEAM = "TEAM123456"
IDENTITY = "A" * 40
SOURCE_SHA = "c" * 40
APP_BYTES = b"fixture exported signed application\n"
IDENTITIES = (
    f'  1) {"B" * 40} "Apple Development: Fixture ({TEAM})"\n'
    f'  2) {IDENTITY.lower()} "Developer ID Application: Fixture ({TEAM})"\n'
    "  2 valid identities found\n"
)

# The doubles implement filesystem results consumed by the actual helper.
# They replace only external release operations and gate callbacks.
FAKE_COMMAND = r'''#!/usr/bin/env python3
import json,os,pathlib,plistlib,shutil,sys
command=pathlib.Path(sys.argv[0]).name
args=sys.argv[1:]
record={'command':command,'args':args}
if command=='xcodebuild' and '-exportOptionsPlist' in args:
    with open(args[args.index('-exportOptionsPlist')+1],'rb') as source:
        record['export_options']=plistlib.load(source)
if command=='xcodebuild' and 'archive' in args:
    info=next(arg.split('=',1)[1] for arg in args if arg.startswith('INFOPLIST_FILE='))
    with open(info,'rb') as source:
        record['archive_info']=plistlib.load(source)
with open(os.environ['FIXTURE_TRACE'],'a') as trace:
    trace.write(json.dumps(record)+'\n')
failure=os.environ.get('FIXTURE_FAIL','')
stage=command
if command=='release-control.py': stage=args[0]
if command=='xcodebuild': stage='export' if '-exportArchive' in args else 'archive'
if command=='codesign':
    stage='dmg-sign' if '--sign' in args else 'dmg-verify' if '--verify' in args else 'app-display'
if command=='xcrun':
    if args[:2]==['notarytool','history']: stage='notary-history'
    elif args[:2]==['notarytool','submit']:
        stage='dmg-notary' if args[2].endswith('.dmg') else 'app-notary'
    elif args[:2]==['stapler','staple']:
        stage='dmg-staple' if args[2].endswith('.dmg') else 'app-staple'
    else: sys.exit(98)
if failure==stage: sys.exit(37)
if command=='git':
    if args==['status','--porcelain']:
        if os.environ.get('FIXTURE_DIRTY')=='1': print(' M Glimpse/source.swift')
    elif args==['rev-parse','HEAD']: print('c'*40)
    elif args[:2]==['config','--get']: sys.exit(1)
    else: sys.exit(98)
elif command=='release-control.py':
    if args==['version']: print(json.dumps({'build':'12'}))
    elif args not in (['gate'],['readiness']): sys.exit(98)
elif command in ('quality-gate.sh','verify-dmg.sh'): pass
elif command=='security':
    if args[:4]!=['find-identity','-v','-p','codesigning']: sys.exit(98)
    print(os.environ['FIXTURE_IDENTITIES'],end='')
elif command=='find': print(os.environ['FIXTURE_SPARKLE_BIN'])
elif command=='xcodebuild':
    if '-exportArchive' in args:
        app=pathlib.Path(args[args.index('-exportPath')+1])/'Glimpse.app'
        binary=app/'Contents/MacOS/Glimpse'
        binary.parent.mkdir(parents=True)
        binary.write_bytes(b'fixture exported signed application\n')
        archive=pathlib.Path(args[args.index('-archivePath')+1])
        shutil.copyfile(archive/'Info.plist',app/'Contents/Info.plist')
    else:
        archive=pathlib.Path(args[args.index('-archivePath')+1])
        archive.mkdir()
        with open(archive/'Info.plist','wb') as target:
            plistlib.dump(record['archive_info'],target)
elif command=='codesign':
    if stage=='app-display':
        print('Authority=Developer ID Application: Fixture')
        print('Runtime Version=fixture')
    elif stage=='dmg-sign':
        artifact=pathlib.Path(args[-1])
        artifact.write_bytes(artifact.read_bytes()+b'fixture container signature\n')
elif command=='ditto': pathlib.Path(args[-1]).write_bytes(b'fixture app notary archive\n')
elif command=='create-dmg':
    output,source=map(pathlib.Path,args[-2:])
    contents=pathlib.Path(str(output)+'.contents')
    shutil.copytree(source,contents)
    if '--app-drop-link' in args:
        (contents/'Applications').symlink_to('/Applications',target_is_directory=True)
    output.write_bytes(b'fixture disk image\n')
elif command=='Rez':
    artifact=pathlib.Path(args[args.index('-o')+1])
    artifact.write_bytes(artifact.read_bytes()+b'fixture icon resource\n')
elif command=='DeRez': print('fixture icon resource')
elif command in ('sips','SetFile','xcrun','sign_update'): pass
elif command=='generate_appcast':
    (pathlib.Path(args[-1])/'appcast.xml').write_text('<fixture-appcast/>\n')
else: sys.exit(98)
'''


class LocalReleaseContracts(unittest.TestCase):
    def run_fixture(self, *, identities=IDENTITIES, keychain="existing", headless=None,
                    failure="", dirty=False, include_icon=False):
        temporary = tempfile.TemporaryDirectory(prefix="local release fixture ")
        self.addCleanup(temporary.cleanup)
        root = pathlib.Path(temporary.name).resolve()
        scripts = root / "tools/scripts"
        scripts.mkdir(parents=True)
        bin_dir = root / "fake bin"
        bin_dir.mkdir()
        trace = root / "observed.jsonl"
        commands = (
            "git", "security", "find", "xcodebuild", "codesign", "xcrun",
            "ditto", "create-dmg", "sips", "DeRez", "Rez", "SetFile",
            "gh", "open", "osascript", "installer", "generate_keys",
        )
        for command in commands:
            executable = bin_dir / command
            executable.write_text(FAKE_COMMAND)
            executable.chmod(0o755)
        helper = scripts / "release-upload.sh"
        shutil.copyfile(SCRIPTS / "release-upload.sh", helper)
        self.assertEqual(helper.read_bytes(), (SCRIPTS / "release-upload.sh").read_bytes())
        shutil.copyfile(SCRIPTS / "select-signing-identity.py", scripts / "select-signing-identity.py")
        for command in ("release-control.py", "quality-gate.sh", "verify-dmg.sh"):
            callback = scripts / command
            callback.write_text(FAKE_COMMAND)
            callback.chmod(0o755)
        sparkle = root / "fake Sparkle bin"
        sparkle.mkdir()
        for command in ("sign_update", "generate_appcast"):
            executable = sparkle / command
            executable.write_text(FAKE_COMMAND)
            executable.chmod(0o755)
        policy = root / ".github/release-policy.json"
        policy.parent.mkdir()
        policy.write_text(json.dumps({"repository": "fixture/Glimpse", "team_id": TEAM}))
        project = root / "Glimpse.xcodeproj/project.pbxproj"
        project.parent.mkdir()
        project.write_text("MARKETING_VERSION = 1.4.5;\n")
        info = root / "Glimpse/Info.plist"
        info.parent.mkdir()
        info.write_bytes(plistlib.dumps({"CFBundleIdentifier": "com.rohit.Glimpse"}))
        if include_icon:
            icon = root / "tools/resources/AppIcon.icns"
            icon.parent.mkdir()
            icon.write_bytes(b"fixture icon\n")
        keychain_file = root / "existing signing keychain.keychain-db"
        keychain_file.write_bytes(b"fixture keychain placeholder\n")
        env = {**os.environ, "PATH": str(bin_dir) + os.pathsep + os.environ["PATH"],
               "FIXTURE_TRACE": str(trace), "FIXTURE_IDENTITIES": identities,
               "FIXTURE_SPARKLE_BIN": str(sparkle), "FIXTURE_FAIL": failure,
               "FIXTURE_DIRTY": "1" if dirty else "0",
               "GLIMPSE_BUILD_ROOT": str(root / "local artifacts")}
        for variable in ("GLIMPSE_SIGNING_KEYCHAIN", "GLIMPSE_HEADLESS_DMG"):
            env.pop(variable, None)
        keychain_value = {
            "existing": str(keychain_file), "missing": str(root / "absent.keychain-db"),
            "relative": "existing signing keychain.keychain-db",
            "directory": str(keychain_file.parent), "empty": "", "unset": None,
        }[keychain]
        if keychain_value is not None:
            env["GLIMPSE_SIGNING_KEYCHAIN"] = keychain_value
        if headless is not None:
            env["GLIMPSE_HEADLESS_DMG"] = headless
        result = subprocess.run(["bash", str(helper)], cwd=root, env=env, text=True,
                                capture_output=True, timeout=25)
        observed = [json.loads(line) for line in trace.read_text().splitlines()] if trace.exists() else []
        self.assert_no_mutations(observed)
        return result, root, keychain_file, observed

    def assert_no_mutations(self, observed):
        for record in observed:
            command, args = record["command"], record["args"]
            self.assertNotIn(command, ("gh", "open", "osascript", "installer", "generate_keys"))
            if command == "security":
                self.assertEqual(args[:4], ["find-identity", "-v", "-p", "codesigning"])
            if command == "git":
                self.assertIn(args, (["status", "--porcelain"], ["rev-parse", "HEAD"],
                                     ["config", "--get", "glimpse.buildRoot"]))

    def records_for(self, observed, command):
        return [record for record in observed if record["command"] == command]

    def assert_stopped(self, result, observed, blocked_command):
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("Release v1.4.5 Complete", result.stdout)
        self.assertFalse(self.records_for(observed, blocked_command), observed)

    def test_policy_identity_query_uses_exact_existing_keychain(self):
        result, _, keychain, observed = self.run_fixture()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        lookup = self.records_for(observed, "security")
        self.assertEqual([record["args"] for record in lookup],
                         [["find-identity", "-v", "-p", "codesigning", str(keychain)]])

    def test_archive_uses_manual_policy_identity_and_quoted_keychain(self):
        result, _, keychain, observed = self.run_fixture()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        archive = self.records_for(observed, "xcodebuild")[0]
        self.assertIn("CODE_SIGN_STYLE=Manual", archive["args"])
        self.assertIn(f"CODE_SIGN_IDENTITY={IDENTITY}", archive["args"])
        self.assertIn(f"DEVELOPMENT_TEAM={TEAM}", archive["args"])
        flags = next(arg.split("=", 1)[1] for arg in archive["args"]
                     if arg.startswith("OTHER_CODE_SIGN_FLAGS="))
        self.assertEqual(shlex.split(flags), ["--keychain", str(keychain)])

    def test_export_uses_same_manual_policy_identity(self):
        result, _, _, observed = self.run_fixture()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        export = self.records_for(observed, "xcodebuild")[1]
        self.assertEqual(export["export_options"], {
            "method": "developer-id", "signingStyle": "manual",
            "signingCertificate": IDENTITY, "teamID": TEAM,
        })

    def test_source_metadata_and_final_verifier_retain_exact_committed_sha(self):
        result, root, _, observed = self.run_fixture()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        archive = self.records_for(observed, "xcodebuild")[0]
        self.assertEqual(archive["archive_info"]["GlimpseSourceSHA"], SOURCE_SHA)
        verify = self.records_for(observed, "verify-dmg.sh")[0]
        self.assertEqual(verify["args"][1:], ["1.4.5", "12", SOURCE_SHA])
        self.assertEqual(pathlib.Path(verify["args"][0]).parent, root / "local artifacts")
        self.assertEqual(pathlib.Path(verify["args"][0]).name[:14], "local-release.")

    def test_missing_relative_nonexistent_and_directory_keychains_stop_before_archive(self):
        for keychain in ("unset", "empty", "relative", "missing", "directory"):
            with self.subTest(keychain=keychain):
                result, _, _, observed = self.run_fixture(keychain=keychain)
                self.assert_stopped(result, observed, "xcodebuild")
                self.assertFalse(self.records_for(observed, "security"))

    def test_untrusted_or_ambiguous_identity_output_stops_before_archive(self):
        valid = f'  1) {IDENTITY} "Developer ID Application: Fixture ({TEAM})"\n'
        wrong = f'  2) {"B" * 40} "Developer ID Application: Other (WRONG12345)"\n'
        for identities in (
            "  0 valid identities found\n",
            f'  1) {IDENTITY} "Apple Development: Fixture ({TEAM})"\n',
            wrong, valid + wrong, valid + valid,
            f'  1) invalid-sha "Developer ID Application: Fixture ({TEAM})"\n',
        ):
            with self.subTest(identities=identities):
                result, _, _, observed = self.run_fixture(identities=identities)
                self.assert_stopped(result, observed, "xcodebuild")

    def test_identity_query_error_is_fatal_before_archive(self):
        result, _, _, observed = self.run_fixture(failure="security")
        self.assert_stopped(result, observed, "xcodebuild")

    def test_final_icon_edits_precede_exact_container_signing_and_strict_verification(self):
        result, _, keychain, observed = self.run_fixture(include_icon=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        packaging = self.records_for(observed, "create-dmg")[0]
        dmg = packaging["args"][-2]
        signing = self.records_for(observed, "codesign")[1:]
        self.assertEqual([record["args"] for record in signing], [
            ["--force", "--sign", IDENTITY, "--keychain", str(keychain), "--timestamp", dmg],
            ["--verify", "--strict", "--verbose=2", dmg],
        ])
        ordered = [
            packaging, self.records_for(observed, "SetFile")[0], *signing,
            next(record for record in observed if record["command"] == "xcrun"
                 and record["args"][:3] == ["notarytool", "submit", dmg]),
            next(record for record in observed if record["command"] == "xcrun"
                 and record["args"] == ["stapler", "staple", dmg]),
            self.records_for(observed, "sign_update")[0],
            self.records_for(observed, "generate_appcast")[0],
            self.records_for(observed, "verify-dmg.sh")[0],
        ]
        self.assertEqual([observed.index(record) for record in ordered],
                         sorted(observed.index(record) for record in ordered))
        notary = [record["args"] for record in observed if record["command"] == "xcrun"
                  and record["args"][:2] == ["notarytool", "submit"]]
        self.assertEqual(len(notary), 2)
        for args in notary:
            self.assertEqual(args[3:], ["--keychain-profile", "AC_PASSWORD", "--wait"])

    def test_styled_default_and_headless_opt_in_preserve_exported_app_and_drop_link(self):
        for headless, expected_skip in ((None, False), ("0", False), ("1", True)):
            with self.subTest(headless=headless):
                result, _, _, observed = self.run_fixture(headless=headless)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                packaging = self.records_for(observed, "create-dmg")[0]["args"]
                self.assertEqual("--skip-jenkins" in packaging, expected_skip)
                for option, values in (
                    ("--window-size", ["600", "400"]),
                    ("--icon", ["Glimpse.app", "150", "190"]),
                    ("--app-drop-link", ["450", "190"]),
                ):
                    index = packaging.index(option)
                    self.assertEqual(packaging[index + 1:index + 1 + len(values)], values)
                contents = pathlib.Path(packaging[-2] + ".contents")
                self.assertEqual((contents / "Glimpse.app/Contents/MacOS/Glimpse").read_bytes(), APP_BYTES)
                self.assertEqual(os.readlink(contents / "Applications"), "/Applications")
                with (contents / "Glimpse.app/Contents/Info.plist").open("rb") as info:
                    self.assertEqual(plistlib.load(info)["GlimpseSourceSHA"], SOURCE_SHA)

    def test_invalid_headless_setting_stops_before_packaging(self):
        for headless in ("", "true", "2", "01"):
            with self.subTest(headless=headless):
                result, _, _, observed = self.run_fixture(headless=headless)
                self.assert_stopped(result, observed, "create-dmg")

    def test_dmg_sign_or_strict_check_failure_blocks_dmg_notary_and_completion(self):
        for failure in ("dmg-sign", "dmg-verify"):
            with self.subTest(failure=failure):
                result, _, _, observed = self.run_fixture(failure=failure)
                self.assertEqual(result.returncode, 37, result.stdout + result.stderr)
                dmg_notary = [record for record in observed if record["command"] == "xcrun"
                              and record["args"][:2] == ["notarytool", "submit"]
                              and record["args"][2].endswith(".dmg")]
                self.assertFalse(dmg_notary)
                self.assertNotIn("Release v1.4.5 Complete", result.stdout)
                self.assertFalse(self.records_for(observed, "sign_update"))

    def test_gate_readiness_dirty_source_and_quality_fail_closed(self):
        for failure, dirty in (("gate", False), ("readiness", False), ("", True),
                               ("quality-gate.sh", False)):
            with self.subTest(failure=failure, dirty=dirty):
                result, _, _, observed = self.run_fixture(failure=failure, dirty=dirty)
                self.assert_stopped(result, observed, "xcodebuild")

    def test_external_failure_never_reports_verified_local_completion(self):
        for failure in ("notary-history", "archive", "export", "app-notary", "app-staple",
                        "create-dmg", "dmg-notary", "dmg-staple", "sign_update",
                        "generate_appcast", "verify-dmg.sh"):
            with self.subTest(failure=failure):
                result, _, _, observed = self.run_fixture(failure=failure)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertNotIn("Release v1.4.5 Complete", result.stdout)
                if failure != "verify-dmg.sh":
                    self.assertFalse(self.records_for(observed, "verify-dmg.sh"))


if __name__ == "__main__":
    unittest.main()
