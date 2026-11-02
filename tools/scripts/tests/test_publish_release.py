"""Execute publication traps against a stateful offline GitHub fixture."""
import json
import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest

from test_release_control import SHA, REPO, feed

SCRIPTS = pathlib.Path(__file__).parents[1]
FAKE_GH = r'''#!/usr/bin/env python3
import base64, hashlib, json, os, pathlib, sys
p = pathlib.Path(os.environ["FAKE_GH_STATE"])
s = json.loads(p.read_text())
a = sys.argv[1:]
def save():
    p.write_text(json.dumps(s))
def output(value):
    print(json.dumps(value))
def release():
    r = dict(s["release"])
    r["assets"] = [{"name": n, "state": "uploaded", "size": len(base64.b64decode(d)),
                   "digest": "sha256:" + hashlib.sha256(base64.b64decode(d)).hexdigest()}
                  for n, d in s["assets"].items()]
    return r
if a[0] == "api":
    endpoint = a[1]
    method = a[a.index("--method")+1] if "--method" in a else "GET"
    s.setdefault("requests", []).append({"endpoint": endpoint, "method": method,
                                       "draft": s["release"]["draft"] if s["release"] else None})
    save()
    if "/branches/main" in endpoint:
        if "--jq" in a: print(s["main"])
        else: output({"commit": {"sha": s["main"]}})
    elif endpoint.endswith("/releases/generate-notes"):
        output({"body": "Verified release notes"})
    elif endpoint.endswith("/releases?per_page=100"):
        output([release()] if s["release"] else [])
    elif endpoint.endswith("/releases/latest"):
        output(release() if s["release"] and not s["release"]["draft"]
               else {"id": 7, "tag_name": "v1.4.3"})
    elif endpoint.endswith("/releases") and method == "POST":
        if s["mode"] == "create-failure":
            output({"message": "Create failed"})
            sys.exit(1)
        fields = json.load(sys.stdin)
        s["release"] = {**fields, "id": 8, "published_at": None}
        s["events"].append("create-draft")
        save()
        response = release()
        malformed = {"create-id-string": "8", "create-id-bool": True,
                     "create-id-zero": 0, "create-id-negative": -1}
        if s["mode"] in malformed: response["id"] = malformed[s["mode"]]
        if s["mode"] == "create-error-response": response = {"message": "Bad response"}
        output(response)
    elif "/git/matching-refs/tags/" in endpoint:
        if s["mode"] == "tag-probe-failure" and s["release"] and "tag-probe-failure" not in s["events"]:
            s["events"].append("tag-probe-failure")
            save()
            output({"message": "Tag readback failed"})
            sys.exit(1)
        output([] if not s["release"] or s["release"]["draft"] else [{"ref": "refs/tags/v1.4.4"}])
    elif "/git/ref/tags/" in endpoint:
        output({"object": {"type": "commit", "sha": s["release"]["target_commitish"]}})
    elif "/releases/tags/" in endpoint or endpoint.endswith("/releases/8"):
        if "/releases/tags/" in endpoint and s["release"]["draft"]:
            output({"message": "Not Found", "status": "404"})
            sys.exit(1)
        if method == "GET" and s["mode"] == "readback-failure" and "readback-failure" not in s["events"]:
            s["events"].append("readback-failure")
            save()
            output({"message": "Readback failed"})
            sys.exit(1)
        if method == "PATCH":
            if s["mode"] == "withdraw-failure": sys.exit(1)
            fields = json.load(sys.stdin)
            s["release"].update(fields)
            s["events"].append("withdraw" if fields.get("make_latest") == "false" else "update-draft")
            save()
        if "--jq" in a: print(s["release"]["id"])
        else: output(release())
    else: sys.exit(2)
elif a[0:2] == ["release", "create"]:
    notes = pathlib.Path(a[a.index("--notes-file")+1]).read_text()
    s["release"] = {"id": 8, "tag_name": "v1.4.4", "draft": True,
                    "prerelease": False, "published_at": None,
                    "target_commitish": a[a.index("--target")+1], "body": notes}
    s["events"].append("create-draft")
    save()
elif a[0:2] == ["release", "upload"]:
    files = [pathlib.Path(x) for x in a[2:] if pathlib.Path(x).is_file()]
    for file in files:
        data = file.read_bytes()
        if s["mode"] == "corrupt-draft" and file.suffix == ".dmg": data = b"bad"
        s["assets"][file.name] = base64.b64encode(data).decode()
        if s["mode"] == "upload-failure":
            s["events"].append("partial-upload")
            save()
            sys.exit(1)
    if s["mode"] == "superseded": s["main"] = "b" * 40
    s["events"].append("upload")
    save()
elif a[0:2] == ["release", "download"]:
    directory = pathlib.Path(a[a.index("--dir")+1])
    for i, arg in enumerate(a):
        if arg == "--pattern":
            name = a[i+1]
            (directory/name).write_bytes(base64.b64decode(s["assets"][name]))
elif a[0:2] == ["release", "edit"]:
    if "--draft=false" in a:
        s["release"]["draft"] = False
        s["release"]["published_at"] = "2026-11-02T01:00:00Z"
        s["events"].append("publish")
    save()
else: sys.exit(3)
'''


class PublicationFailureContracts(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temp.name)
        self.scripts = self.root / "tools/scripts"
        self.scripts.mkdir(parents=True)
        shutil.copy(SCRIPTS / "publish-release.sh", self.scripts / "publish-release.sh")
        shutil.copy(SCRIPTS / "release-control.py", self.scripts / "release-control-implementation.py")
        # Keep real controller/CLI decisions; replace only anonymous network transport.
        (self.scripts / "release-control.py").write_text("""import base64,importlib.util,json,os,pathlib,sys
spec=importlib.util.spec_from_file_location('controller',pathlib.Path(__file__).with_name('release-control-implementation.py'))
controller=importlib.util.module_from_spec(spec)
spec.loader.exec_module(controller)
def download(url,destination):
    state=json.loads(pathlib.Path(os.environ['FAKE_GH_STATE']).read_text())
    if state['mode'] in ('public-health-failure','withdraw-failure'):
        raise controller.ReleaseError('Fixture public download failed')
    destination.write_bytes(base64.b64decode(state['assets'][url.rsplit('/',1)[-1]]))
controller.download_public=download
try:
    controller.main()
except Exception as error:
    print(f'Release gate blocked: {error}',file=sys.stderr)
    sys.exit(1)
""")
        # macOS artifact commands are exercised by live audit separately.
        verifier = self.scripts / "verify-dmg.sh"
        verifier.write_text("#!/bin/bash\nexit 0\n")
        verifier.chmod(0o755)
        project = self.root / "Glimpse.xcodeproj"
        project.mkdir()
        (project / "project.pbxproj").write_text(
            "MARKETING_VERSION = 1.4.4;\n" * 4 + "CURRENT_PROJECT_VERSION = 11;\n" * 4
        )
        (self.root / "README.md").write_text("version-1.4.4-green")
        (self.root / "evidence.md").write_text("Completed reviews")
        config = self.root / ".github"
        config.mkdir()
        (config / "release-policy.json").write_text(json.dumps({"repository": REPO}))
        (config / "release-readiness.json").write_text(json.dumps({
            "version": "1.4.4", "build": "11",
            "checks": {name: {"status": "passed", "evidence": "evidence.md"}
                       for name in ("product", "ux", "code", "qa")},
        }))
        artifacts = self.root / "build/release"
        artifacts.mkdir(parents=True)
        (artifacts / "Glimpse-1.4.4.dmg").write_bytes(b"dmg")
        (artifacts / "appcast.xml").write_bytes(feed())
        (self.root / "previous.json").write_text(json.dumps({"tag": "v1.4.3"}))
        self.bin = self.root / "bin"
        self.bin.mkdir()
        gh = self.bin / "gh"
        gh.write_text(FAKE_GH)
        gh.chmod(0o755)
        sleep = self.bin / "sleep"
        sleep.write_text("#!/bin/bash\nexit 0\n")
        sleep.chmod(0o755)
        self.state_path = self.root / "state.json"

    def tearDown(self):
        self.temp.cleanup()

    def run_release(self, mode):
        self.state_path.write_text(json.dumps({
            "mode": mode, "main": SHA, "release": None, "assets": {}, "events": [],
        }))
        env = {**os.environ, "PATH": str(self.bin) + os.pathsep + os.environ["PATH"],
               "FAKE_GH_STATE": str(self.state_path), "VERSION": "1.4.4",
               "GITHUB_REPOSITORY": REPO, "GITHUB_SHA": SHA, "GITHUB_RUN_ID": "42",
               "GITHUB_RUN_ATTEMPT": "1", "GITHUB_OUTPUT": str(self.root / "output")}
        result = subprocess.run(
            ["bash", str(self.scripts / "publish-release.sh"), "build/release", "previous.json"],
            env=env, cwd=self.root, text=True, capture_output=True, timeout=20,
        )
        return result, json.loads(self.state_path.read_text())

    def test_partial_upload_stays_draft_and_does_not_publish(self):
        result, state = self.run_release("upload-failure")
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(state["release"]["draft"])
        self.assertIn("partial-upload", state["events"])
        self.assertNotIn("publish", state["events"])

    def test_corrupt_draft_is_rejected_before_publication(self):
        result, state = self.run_release("corrupt-draft")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("digest", result.stderr)
        self.assertTrue(state["release"]["draft"])
        self.assertNotIn("publish", state["events"])

    def test_public_health_failure_withdraws_owned_release(self):
        result, state = self.run_release("public-health-failure")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("publish", state["events"])
        self.assertIn("withdraw", state["events"])
        self.assertTrue(state["release"]["draft"])
        self.assertNotIn("release_verified=true", (self.root / "output").read_text())

    def test_network_failure_during_withdrawal_is_visible_and_gate_stays_closed(self):
        result, state = self.run_release("withdraw-failure")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("operator recovery is required", result.stderr)
        self.assertFalse(state["release"]["draft"])
        self.assertNotIn("release_verified=true", (self.root / "output").read_text())

    def test_main_advancing_prevents_publication(self):
        result, state = self.run_release("superseded")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Main advanced", result.stderr)
        self.assertTrue(state["release"]["draft"])
        self.assertNotIn("publish", state["events"])

    def test_tagless_draft_publishes_successfully_using_response_id(self):
        result, state = self.run_release("success")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(state["release"]["draft"])
        self.assertIn("publish", state["events"])
        self.assertIn("release_id=8\n", (self.root / "output").read_text())
        self.assertIn("release_verified=true\n", (self.root / "output").read_text())
        self.assertTrue(any(request["endpoint"].endswith("/releases/8")
                            for request in state["requests"]))
        self.assertFalse(any("/releases/tags/" in request["endpoint"] and request["draft"]
                             for request in state["requests"]))

    def test_invalid_create_response_cannot_reach_output_upload_or_publication(self):
        for mode in ("create-id-string", "create-id-bool", "create-id-zero",
                     "create-id-negative", "create-error-response", "create-failure"):
            with self.subTest(mode=mode):
                (self.root / "output").unlink(missing_ok=True)
                result, state = self.run_release(mode)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse((self.root / "output").exists())
                self.assertNotIn("upload", state["events"])
                self.assertNotIn("publish", state["events"])
                self.assertNotIn("invalid int value", result.stderr)
                if state["release"]:
                    self.assertTrue(state["release"]["draft"])

    def test_readback_failure_withdraws_using_validated_numeric_id(self):
        result, state = self.run_release("readback-failure")
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((self.root / "output").is_file(), result.stdout + result.stderr)
        self.assertIn("release_id=8\n", (self.root / "output").read_text())
        self.assertTrue(state["release"]["draft"])
        self.assertNotIn("publish", state["events"])
        self.assertNotIn("invalid int value", result.stderr)
        self.assertGreaterEqual(len([request for request in state["requests"]
                                     if request["endpoint"].endswith("/releases/8")]), 2)

    def test_tag_probe_failure_after_receipt_keeps_validated_id_for_cleanup(self):
        result, state = self.run_release("tag-probe-failure")
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((self.root / "output").is_file(), result.stdout + result.stderr)
        self.assertIn("release_id=8\n", (self.root / "output").read_text())
        self.assertTrue(state["release"]["draft"])
        self.assertNotIn("publish", state["events"])
        self.assertNotIn("invalid int value", result.stderr)
        self.assertGreaterEqual(len([request for request in state["requests"]
                                     if request["endpoint"].endswith("/releases/8")]), 2)


if __name__ == "__main__":
    unittest.main()
