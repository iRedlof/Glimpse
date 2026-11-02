import json
import os
import pathlib
import subprocess
import tempfile
import unittest

from test_signing_identity import workflow_run


class HeadlessDMGContracts(unittest.TestCase):
    def run_fixture(self, packaging_status=0, notary_status=0, staple_status=0,
                    validation_status=0, include_app_notary=False, include_icon=False):
        temporary = tempfile.TemporaryDirectory(prefix="release dmg fixture ")
        self.addCleanup(temporary.cleanup)
        root = pathlib.Path(temporary.name).resolve()
        app_binary = root / "build/export/Glimpse.app/Contents/MacOS/Glimpse"
        app_binary.parent.mkdir(parents=True)
        app_binary.write_bytes(b"signed fixture app contents\n")
        if include_icon:
            icon = root / "tools/resources/AppIcon.icns"
            icon.parent.mkdir(parents=True)
            icon.write_bytes(b"fixture icon\n")
        bin_dir = root / "bin"
        bin_dir.mkdir()
        trace = root / "observed.jsonl"
        for command in ("create-dmg", "xcrun", "codesign", "ditto", "sleep",
                        "sips", "DeRez", "Rez", "SetFile"):
            executable = bin_dir / command
            executable.write_text("""#!/usr/bin/env python3
import json,os,pathlib,shutil,sys
command=pathlib.Path(sys.argv[0]).name
args=sys.argv[1:]
with open(os.environ['FIXTURE_TRACE'],'a') as trace:
    trace.write(json.dumps({'command':command,'args':args})+'\\n')
if command=='create-dmg':
    if '--skip-jenkins' not in args:
        print('fixture Finder AppleScript timed out (-1712)',file=sys.stderr)
        sys.exit(64)
    status=int(os.environ['FIXTURE_PACKAGING_STATUS'])
    if status: sys.exit(status)
    output,source=pathlib.Path(args[-2]),pathlib.Path(args[-1])
    contents=pathlib.Path(str(output)+'.contents')
    shutil.copytree(source,contents)
    if '--app-drop-link' in args:
        (contents/'Applications').symlink_to('/Applications',target_is_directory=True)
    output.write_bytes(b'fixture disk image\\n')
elif command=='xcrun':
    if args[:2]==['notarytool','submit']:
        sys.exit(int(os.environ['FIXTURE_NOTARY_STATUS']))
    ticket=pathlib.Path(args[-1]+'.ticket')
    if args[:2]==['stapler','staple']:
        status=int(os.environ['FIXTURE_STAPLE_STATUS'])
        if status: sys.exit(status)
        ticket.write_text('fixture notarization ticket\\n')
    elif args[:2]==['stapler','validate']:
        status=int(os.environ['FIXTURE_VALIDATION_STATUS'])
        if status: sys.exit(status)
        if not ticket.is_file(): sys.exit(19)
    else:
        sys.exit(2)
elif command=='codesign':
    print('Authority=Developer ID Application: Fixture')
    print('Runtime Version=fixture')
elif command=='ditto':
    pathlib.Path(args[-1]).write_bytes(b'fixture notarization archive\\n')
""")
            executable.chmod(0o755)
        env = {**os.environ, "PATH": str(bin_dir) + os.pathsep + os.environ["PATH"],
               "VERSION": "1.4.4", "APPLE_ID": "fixture@example.invalid",
               "APPLE_ID_PASSWORD": "fixture-password", "TEAM_ID": "TEAM123456",
               "FIXTURE_TRACE": str(trace), "FIXTURE_PACKAGING_STATUS": str(packaging_status),
               "FIXTURE_NOTARY_STATUS": str(notary_status), "FIXTURE_STAPLE_STATUS": str(staple_status),
               "FIXTURE_VALIDATION_STATUS": str(validation_status), "TMPDIR": str(root)}
        script = workflow_run("Create and notarize DMG")
        if include_app_notary:
            script = workflow_run("Notarize app") + "\n" + script
        script += "\nprintf 'passed\\n' > workflow-proceeded.txt\n"
        result = subprocess.run(["bash", "-e", "-o", "pipefail", "-c", script],
                                cwd=root, env=env, text=True, capture_output=True, timeout=15)
        observed = [json.loads(line) for line in trace.read_text().splitlines()]
        return result, root, observed

    def test_headless_packaging_preserves_app_drop_link_and_notary_validation(self):
        result, root, observed = self.run_fixture(include_app_notary=True, include_icon=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        packaging = next(entry for entry in observed if entry["command"] == "create-dmg")
        self.assertIn("--skip-jenkins", packaging["args"])
        drop = packaging["args"].index("--app-drop-link")
        self.assertEqual(packaging["args"][drop + 1:drop + 3], ["450", "190"])
        icon = packaging["args"].index("--volicon")
        self.assertEqual(packaging["args"][icon + 1], "./tools/resources/AppIcon.icns")
        self.assertEqual(packaging["args"][-2:],
                         ["./build/Glimpse-1.4.4.dmg", "./build/dmg_staging"])
        source = root / "build/export/Glimpse.app/Contents/MacOS/Glimpse"
        staged = root / "build/dmg_staging/Glimpse.app/Contents/MacOS/Glimpse"
        contents = root / "build/Glimpse-1.4.4.dmg.contents"
        self.assertEqual(staged.read_bytes(), source.read_bytes())
        self.assertEqual((contents / "Glimpse.app/Contents/MacOS/Glimpse").read_bytes(), source.read_bytes())
        self.assertEqual(os.readlink(contents / "Applications"), "/Applications")
        signing = [entry["args"] for entry in observed if entry["command"] == "codesign"]
        self.assertEqual(signing, [["-dvv", "./build/export/Glimpse.app"]])
        notarization = [entry["args"] for entry in observed
                        if entry["command"] == "xcrun" and entry["args"][:2] == ["notarytool", "submit"]]
        for args, artifact in zip(notarization, ["./build/Glimpse-notarize.zip", "./build/Glimpse-1.4.4.dmg"]):
            self.assertEqual(args, ["notarytool", "submit", artifact,
                                   "--apple-id", "fixture@example.invalid",
                                   "--password", "fixture-password", "--team-id", "TEAM123456", "--wait"])
        self.assertEqual(len(notarization), 2)
        stapling = [entry["args"] for entry in observed
                    if entry["command"] == "xcrun" and entry["args"][0] == "stapler"]
        self.assertEqual(stapling, [
            ["stapler", "staple", "./build/export/Glimpse.app"],
            ["stapler", "validate", "./build/export/Glimpse.app"],
            ["stapler", "staple", "./build/Glimpse-1.4.4.dmg"],
            ["stapler", "validate", "./build/Glimpse-1.4.4.dmg"],
        ])
        self.assertFalse((root / "build/Glimpse-notarize.zip").exists())
        self.assertTrue((root / "workflow-proceeded.txt").is_file())

    def test_packaging_failure_propagates_and_skips_notarization(self):
        result, root, observed = self.run_fixture(packaging_status=64)
        self.assertEqual(result.returncode, 64, result.stdout + result.stderr)
        self.assertEqual([entry["command"] for entry in observed], ["create-dmg"])
        self.assertFalse((root / "build/Glimpse-1.4.4.dmg").exists())
        self.assertFalse((root / "workflow-proceeded.txt").exists())

    def test_notary_failure_propagates_and_skips_stapling(self):
        result, root, observed = self.run_fixture(notary_status=17)
        self.assertEqual(result.returncode, 17, result.stdout + result.stderr)
        commands = [entry["args"][:2] for entry in observed if entry["command"] == "xcrun"]
        self.assertEqual(commands, [["notarytool", "submit"]])
        self.assertFalse((root / "workflow-proceeded.txt").exists())

    def test_permanent_staple_failure_cannot_pass_validation(self):
        result, root, observed = self.run_fixture(staple_status=25)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        stapling = [entry["args"][:2] for entry in observed
                    if entry["command"] == "xcrun" and entry["args"][0] == "stapler"]
        self.assertEqual(stapling, [["stapler", "staple"]] * 3 + [["stapler", "validate"]])
        self.assertEqual(len([entry for entry in observed if entry["command"] == "sleep"]), 3)
        self.assertFalse((root / "workflow-proceeded.txt").exists())

    def test_staple_validation_failure_blocks_following_steps(self):
        result, root, observed = self.run_fixture(validation_status=19)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertEqual(observed[-1]["args"],
                         ["stapler", "validate", "./build/Glimpse-1.4.4.dmg"])
        self.assertFalse((root / "workflow-proceeded.txt").exists())


if __name__ == "__main__":
    unittest.main()
