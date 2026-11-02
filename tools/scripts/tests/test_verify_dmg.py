"""Run downloaded-DMG verification with offline native command fixtures."""
import json
import os
import pathlib
import plistlib
import shutil
import subprocess
import tempfile
import unittest

from test_release_control import REPO, SHA, feed
from test_signing_identity import TEAM

SCRIPTS = pathlib.Path(__file__).parents[1]
PUBLIC_KEY = "fixture Sparkle public key"
VERSION = "1.4.5"
BUILD = "12"


class DownloadedDMGContracts(unittest.TestCase):
    def run_fixture(self, mode="success"):
        temporary = tempfile.TemporaryDirectory(prefix="downloaded dmg fixture ")
        self.addCleanup(temporary.cleanup)
        root = pathlib.Path(temporary.name).resolve()
        scripts = root / "tools/scripts"
        scripts.mkdir(parents=True)
        for name in ("verify-dmg.sh", "release-control.py"):
            shutil.copy(SCRIPTS / name, scripts / name)
        policy = root / ".github/release-policy.json"
        policy.parent.mkdir()
        policy.write_text(json.dumps({"repository": REPO, "bundle_id": "fixture.Glimpse",
                                      "team_id": TEAM, "sparkle_public_key": PUBLIC_KEY}))
        app_contents = root / "source/Glimpse.app/Contents"
        app_contents.mkdir(parents=True)
        (app_contents / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "fixture.Glimpse", "CFBundleShortVersionString": VERSION,
            "CFBundleVersion": BUILD, "GlimpseSourceSHA": SHA, "SUPublicEDKey": PUBLIC_KEY,
            "SUFeedURL": f"https://github.com/{REPO}/releases/latest/download/appcast.xml",
        }))
        artifacts = root / "downloaded release"
        artifacts.mkdir()
        dmg = artifacts / f"Glimpse-{VERSION}.dmg"
        dmg.write_bytes(b"fixture downloaded disk image\n")
        (artifacts / "appcast.xml").write_bytes(feed(
            url=f"https://github.com/{REPO}/releases/download/v{VERSION}/Glimpse-{VERSION}.dmg",
            version=VERSION, build=BUILD, size=dmg.stat().st_size))
        bin_dir = root / "bin"
        bin_dir.mkdir()
        trace = root / "observed.jsonl"
        for command in ("codesign", "xcrun", "spctl", "hdiutil", "swift"):
            executable = bin_dir / command
            executable.write_text("""#!/usr/bin/env python3
import json,os,pathlib,shutil,sys
command=pathlib.Path(sys.argv[0]).name
args=sys.argv[1:]
mode=os.environ['FIXTURE_MODE']
dmg=args[-1].endswith('.dmg')
with open(os.environ['FIXTURE_TRACE'],'a') as trace:
    trace.write(json.dumps({'command':command,'args':args})+'\\n')
if command=='codesign':
    if '--verify' in args and dmg and mode=='invalid-signature': sys.exit(23)
    if '-dvv' in args:
        if dmg and mode=='display-failure': sys.exit(24)
        team=os.environ['FIXTURE_TEAM']
        authority='Developer ID Application: Fixture ('+team+')'
        if dmg and mode=='wrong-authority': authority='Apple Development: Fixture ('+team+')'
        if dmg and mode=='wrong-team': team='OTHER12345'
        if dmg and mode=='team-prefix': team+='OTHER'
        print('Authority='+authority,file=sys.stderr)
        if not (dmg and mode=='missing-team'): print('TeamIdentifier='+team,file=sys.stderr)
        if not dmg: print('flags=0x10000(runtime)',file=sys.stderr)
elif command=='xcrun':
    if args[:2]!=['stapler','validate']: sys.exit(2)
    if dmg and mode=='invalid-ticket': sys.exit(25)
elif command=='spctl':
    if dmg and mode=='gatekeeper-rejected': sys.exit(3)
elif command=='hdiutil':
    if args[0]=='attach':
        mount=pathlib.Path(args[args.index('-mountpoint')+1])
        shutil.copytree(os.environ['FIXTURE_APP'],mount/'Glimpse.app')
    elif args[0]=='detach':
        for child in pathlib.Path(args[-1]).iterdir():
            shutil.rmtree(child) if child.is_dir() else child.unlink()
    else: sys.exit(2)
""")
            executable.chmod(0o755)
        env = {**os.environ, "PATH": str(bin_dir) + os.pathsep + os.environ["PATH"],
               "FIXTURE_MODE": mode, "FIXTURE_TRACE": str(trace), "FIXTURE_TEAM": TEAM,
               "FIXTURE_APP": str(app_contents.parent), "TMPDIR": str(root)}
        result = subprocess.run(
            ["bash", str(scripts / "verify-dmg.sh"), str(artifacts), VERSION, BUILD, SHA],
            cwd=root, env=env, text=True, capture_output=True, timeout=10)
        observed = [json.loads(line) for line in trace.read_text().splitlines()]
        return result, dmg, observed

    def test_valid_container_is_verified_and_assessed_before_mounting(self):
        result, dmg, observed = self.run_fixture()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        container = [entry for entry in observed if entry["args"][-1] == str(dmg)]
        self.assertIn({"command": "codesign", "args": ["--verify", "--strict", "--verbose=2", str(dmg)]},
                      container)
        self.assertIn({"command": "codesign", "args": ["-dvv", str(dmg)]}, container)
        ticket = {"command": "xcrun", "args": ["stapler", "validate", str(dmg)]}
        assessment = {"command": "spctl", "args": ["--assess", "--type", "open", "--context",
                                                   "context:primary-signature", "--verbose=2", str(dmg)]}
        self.assertIn(assessment, container)
        mount = next(entry for entry in observed if entry["command"] == "hdiutil")
        self.assertLess(observed.index(ticket), observed.index(assessment))
        self.assertLess(observed.index(assessment), observed.index(mount))
        self.assertEqual(mount["args"][:3], ["attach", "-readonly", "-nobrowse"])
        app = pathlib.Path(mount["args"][mount["args"].index("-mountpoint") + 1]) / "Glimpse.app"
        self.assertIn({"command": "codesign", "args": ["--verify", "--deep", "--strict", str(app)]},
                      observed)
        self.assertIn({"command": "spctl", "args": ["--assess", "--type", "execute", "--verbose=2", str(app)]},
                      observed)
        sparkle = next(entry for entry in observed if entry["command"] == "swift")
        self.assertEqual(sparkle["args"][1:], [PUBLIC_KEY, "A" * 86 + "==", str(dmg)])
        self.assertEqual(observed[-1], {"command": "hdiutil", "args": ["detach", str(app.parent)]})
        self.assertFalse(app.parent.exists())

    def test_dmg_signature_ticket_or_gatekeeper_failure_blocks_mount_and_sparkle(self):
        for mode, expected in (("invalid-signature", 23), ("display-failure", 24),
                               ("invalid-ticket", 25), ("gatekeeper-rejected", 3)):
            with self.subTest(mode=mode):
                result, dmg, observed = self.run_fixture(mode)
                self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
                self.assertFalse(any(entry["command"] in ("hdiutil", "swift") for entry in observed))

    def test_wrong_or_missing_developer_id_team_blocks_mount(self):
        for mode in ("wrong-authority", "wrong-team", "missing-team", "team-prefix"):
            with self.subTest(mode=mode):
                result, dmg, observed = self.run_fixture(mode)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("Downloaded DMG signing identity mismatch", result.stderr)
                self.assertFalse(any(entry["command"] in ("hdiutil", "swift") for entry in observed))


if __name__ == "__main__":
    unittest.main()
