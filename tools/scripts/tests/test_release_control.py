"""Contract tests exercise release decisions without contacting GitHub."""
import copy
import hashlib
import importlib.util
import json
import pathlib
import tempfile
import types
import unittest
from unittest.mock import patch

MODULE = pathlib.Path(__file__).parents[1] / "release-control.py"
if MODULE.exists():
    spec = importlib.util.spec_from_file_location("release_control", MODULE)
    release_control = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(release_control)
else:
    release_control = None

SHA = "a" * 40
REPO = "owner/Glimpse"


def feed(url=None, build="11", version="1.4.4", size=3):
    url = url or f"https://github.com/{REPO}/releases/download/v1.4.4/Glimpse-1.4.4.dmg"
    return f'''<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel><item><sparkle:version>{build}</sparkle:version>
    <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
    <enclosure url="{url}" length="{size}" sparkle:edSignature="{'A' * 86}=="/>
    </item></channel></rss>'''.encode()


class FakeGitHub:
    def __init__(self, directory):
        self.directory = directory
        self.calls = []
        self.sha = SHA
        self.release = {
            "id": 8, "tag_name": "v1.4.4", "draft": False, "prerelease": False,
            "target_commitish": SHA,
            "body": "<!-- glimpse-run:42 sha:" + SHA + " -->", "assets": [],
        }
        self.run = {
            "id": 42, "head_sha": SHA, "status": "completed",
            "conclusion": "success", "event": "push", "head_branch": "main",
            "path": ".github/workflows/release.yml", "run_attempt": 1,
        }
        self.jobs = {"jobs": [{"name": "release-verified", "conclusion": "success"},
                              {"name": "build", "conclusion": "success"}]}
        self.latest_run = None
        self.recovery_run = None
        self.recovery_record = None
        self.bootstrap_statuses = []
        self.failed_jobs = None
        self.releases = []
        self.comparison = {"status": "ahead", "total_commits": 1, "files": [{"filename": "docs/release.md"}]}
        self.files = {"Glimpse-1.4.4.dmg": b"dmg", "appcast.xml": feed()}
        self.manifest = {
            "schema": 1, "repository": REPO, "source_sha": SHA, "version": "1.4.4",
            "build": "11", "workflow_run_id": 42, "workflow_run_attempt": 1,
            "artifact_validation": "passed",
            "assets": {
                name: {"sha256": hashlib.sha256(data).hexdigest(), "size": len(data)}
                for name, data in self.files.items()
            },
        }
        self.files["release-manifest.json"] = json.dumps(self.manifest).encode()
        self.sync_assets()

    def sync_assets(self):
        self.release["assets"] = [
            {"name": name, "size": len(data), "state": "uploaded",
             "digest": "sha256:" + hashlib.sha256(data).hexdigest()}
            for name, data in self.files.items()
        ]

    def api(self, endpoint, method="GET", fields=None):
        self.calls.append((endpoint, method, fields))
        if method != "GET":
            self.release.update(fields)
            return self.release
        if "/branches/" in endpoint:
            return {"commit": {"sha": self.sha}}
        if endpoint.endswith("/releases/latest") and self.release["draft"]:
            return {"id": 7, "tag_name": "v1.4.3"}
        if endpoint.endswith("/releases/latest") or endpoint.endswith("/releases/8") or "/releases/tags/" in endpoint:
            return copy.deepcopy(self.release)
        if "/git/ref/tags/" in endpoint:
            return {"object": {"sha": SHA, "type": "commit"}}
        if "/git/matching-refs/tags/" in endpoint:
            return []
        if "/actions/workflows/recovery.yml" in endpoint:
            return {"workflow_runs": [self.recovery_run] if self.recovery_run else []}
        if "/actions/workflows/release.yml" in endpoint:
            return {"workflow_runs": [copy.deepcopy(self.latest_run or self.run)]}
        if endpoint.endswith("/actions/runs/42"):
            return copy.deepcopy(self.run)
        if "/actions/runs/42/jobs" in endpoint:
            return self.jobs
        if "/actions/runs/42/attempts/1/jobs" in endpoint:
            return self.jobs
        if endpoint.endswith("/actions/runs/43"):
            return self.latest_run
        if "/actions/runs/43/jobs" in endpoint:
            return self.jobs
        if "/actions/runs/43/attempts/1/jobs" in endpoint:
            return self.failed_jobs or self.jobs
        if "/actions/runs/44/jobs" in endpoint:
            return {"jobs": [{"name": "recovery-verified", "conclusion": "success"}]}
        if "/compare/" in endpoint:
            return self.comparison
        if "/releases?per_page=100" in endpoint:
            return self.releases
        if "/commits/" in endpoint and "/statuses" in endpoint:
            return self.bootstrap_statuses
        raise AssertionError(endpoint)

    def download(self, tag, directory, names):
        for name in names:
            (directory / name).write_bytes(self.files[name])

    def download_run(self, run_id, directory, name):
        (directory / "release-recovery.json").write_text(json.dumps(self.recovery_record))


class ReleaseContracts(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(release_control, "release controller has not been implemented")
        self.temp = tempfile.TemporaryDirectory()
        self.directory = pathlib.Path(self.temp.name)
        self.github = FakeGitHub(self.directory)

    def tearDown(self):
        self.temp.cleanup()

    def gate(self):
        return release_control.verify_previous(self.github, REPO, {"legacy_release": {}})

    def test_verified_exact_source_and_artifacts_unlock_gate(self):
        self.assertEqual(self.gate()["source_sha"], SHA)

    def test_pinned_legacy_feed_survives_repository_rename(self):
        previous_repo = "previous/Glimpse"
        self.github.files["appcast.xml"] = feed(
            url=f"https://github.com/{previous_repo}/releases/download/v1.4.4/Glimpse-1.4.4.dmg")
        self.github.sync_assets()
        legacy = {**self.github.manifest, "repository": previous_repo, "tag": "v1.4.4",
                  "assets": {
                      name: {"sha256": hashlib.sha256(data).hexdigest(), "size": len(data)}
                      for name, data in self.github.files.items()
                      if name != "release-manifest.json"
                  }}
        result = release_control.verify_previous(
            self.github, REPO, {"legacy_release": legacy})
        self.assertEqual(result["source_sha"], SHA)
        self.assertTrue(all(endpoint.startswith(f"repos/{REPO}/")
                            for endpoint, _, _ in self.github.calls))

    def test_legacy_repository_alias_cannot_approve_new_feed(self):
        previous_repo = "previous/Glimpse"
        self.github.files["appcast.xml"] = feed(
            url=f"https://github.com/{previous_repo}/releases/download/v1.4.4/Glimpse-1.4.4.dmg")
        self.github.manifest["assets"]["appcast.xml"] = {
            "sha256": hashlib.sha256(self.github.files["appcast.xml"]).hexdigest(),
            "size": len(self.github.files["appcast.xml"]),
        }
        self.github.files["release-manifest.json"] = json.dumps(self.github.manifest).encode()
        self.github.sync_assets()
        with self.assertRaisesRegex(release_control.ReleaseError, "Appcast URL"):
            release_control.verify_previous(self.github, REPO, {
                "legacy_release": {"tag": "v1.4.3", "repository": previous_repo}})

    def test_pending_previous_run_blocks_gate(self):
        self.github.run["status"] = "in_progress"
        with self.assertRaisesRegex(release_control.ReleaseError, "completed successfully"):
            self.gate()

    def test_failed_previous_run_blocks_gate(self):
        self.github.run["conclusion"] = "failure"
        with self.assertRaises(release_control.ReleaseError):
            self.gate()

    def test_unreleased_remote_commit_blocks_gate(self):
        self.github.sha = "b" * 40
        with self.assertRaises(release_control.ReleaseError):
            self.gate()

    def test_missing_final_verification_job_blocks_gate(self):
        self.github.jobs = {"jobs": [{"name": "build", "conclusion": "success"}]}
        with self.assertRaisesRegex(release_control.ReleaseError, "release-verified"):
            self.gate()

    def test_tag_wrong_source_blocks_gate(self):
        original = self.github.api
        self.github.api = lambda endpoint, **kwargs: (
            {"object": {"type": "commit", "sha": "b" * 40}}
            if "/git/ref/tags/" in endpoint else original(endpoint, **kwargs)
        )
        with self.assertRaisesRegex(release_control.ReleaseError, "source"):
            self.gate()

    def test_changed_dmg_bytes_block_gate(self):
        self.github.files["Glimpse-1.4.4.dmg"] = b"bad"
        with self.assertRaisesRegex(release_control.ReleaseError, "digest"):
            self.gate()

    def test_missing_manifest_blocks_gate(self):
        del self.github.files["release-manifest.json"]
        self.github.sync_assets()
        with self.assertRaisesRegex(release_control.ReleaseError, "manifest"):
            self.gate()

    def test_manifest_future_workflow_attempt_blocks_gate(self):
        self.github.manifest["workflow_run_attempt"] = 2
        self.github.files["release-manifest.json"] = json.dumps(self.github.manifest).encode()
        self.github.sync_assets()
        with self.assertRaisesRegex(release_control.ReleaseError, "workflow identity"):
            self.gate()

    def test_later_successful_same_source_dispatch_preserves_original_publication_identity(self):
        self.github.latest_run = {**self.github.run, "id": 43, "event": "workflow_dispatch"}
        self.assertEqual(self.gate()["workflow_run_id"], 42)

    def test_successful_rerun_uses_original_publication_attempt_jobs(self):
        self.github.run["run_attempt"] = 2
        self.assertEqual(self.gate()["workflow_run_attempt"], 1)

    def test_failed_actual_publication_attempt_cannot_be_unlocked_by_later_success(self):
        self.github.run["run_attempt"] = 2
        original = self.github.api
        def api(endpoint, **kwargs):
            if "/attempts/1/jobs" in endpoint:
                return {"jobs": [{"name": "build", "conclusion": "failure"}]}
            return original(endpoint, **kwargs)
        self.github.api = api
        with self.assertRaisesRegex(release_control.ReleaseError, "build"):
            self.gate()

    def test_transient_final_job_retry_anchors_successful_original_build(self):
        self.github.run["run_attempt"] = 2
        original = self.github.api
        def api(endpoint, **kwargs):
            if "/attempts/1/jobs" in endpoint:
                return {"jobs": [{"name": "build", "conclusion": "success"},
                                 {"name": "release-verified", "conclusion": "failure"}]}
            return original(endpoint, **kwargs)
        self.github.api = api
        self.assertEqual(self.gate()["workflow_run_attempt"], 1)

    def test_final_metadata_recheck_rejects_withdrawn_release(self):
        self.github.release["draft"] = True
        original = self.github.api
        def api(endpoint, **kwargs):
            if "/releases/tags/" in endpoint:
                return self.github.release
            return original(endpoint, **kwargs)
        self.github.api = api
        with self.assertRaisesRegex(release_control.ReleaseError, "draft"):
            release_control.verify_release(self.github, REPO, {}, "v1.4.4",
                                           self.directory, public=True, metadata_only=True)

    def test_final_metadata_recheck_accepts_original_assets_on_later_attempt(self):
        with patch.dict("os.environ", {"GITHUB_SHA": SHA, "GITHUB_RUN_ID": "42", "GITHUB_RUN_ATTEMPT": "2"}), \
             patch.object(release_control, "download_public",
                          side_effect=lambda url, path: path.write_bytes(self.github.files[url.rsplit("/", 1)[1]])), \
             patch.object(release_control.subprocess, "run") as signed_check:
            release_control.verify_release(self.github, REPO, {}, "v1.4.4",
                                           self.directory, public=True, metadata_only=True)
        signed_check.assert_not_called()

    def test_final_metadata_recheck_refuses_public_artifact_change(self):
        with patch.dict("os.environ", {"GITHUB_SHA": SHA, "GITHUB_RUN_ID": "42", "GITHUB_RUN_ATTEMPT": "2"}), \
             patch.object(release_control, "download_public",
                          side_effect=lambda url, path: path.write_bytes(
                              b"bad" if url.endswith(".dmg") else self.github.files[url.rsplit("/", 1)[1]])):
            with self.assertRaisesRegex(release_control.ReleaseError, "digest"):
                release_control.verify_release(self.github, REPO, {}, "v1.4.4",
                                               self.directory, public=True, metadata_only=True)

    def test_public_download_certificate_failure_stays_visible(self):
        destination = self.directory / "partial"
        destination.write_bytes(b"partial untrusted output")
        with patch.object(release_control.subprocess, "run",
                          return_value=types.SimpleNamespace(returncode=60)):
            with self.assertRaisesRegex(release_control.ReleaseError, "download failed"):
                release_control.download_public("https://github.com/owner/repo/file", destination)
        self.assertFalse(destination.exists())

    def test_public_download_rejects_plain_http(self):
        with self.assertRaisesRegex(release_control.ReleaseError, "HTTPS"):
            release_control.download_public("http://github.com/owner/repo/file",
                                            self.directory / "download")

    def test_stale_latest_public_feed_blocks_verification(self):
        def download(url, path):
            path.write_bytes(b"stale" if "/releases/latest/" in url else
                             self.github.files[url.rsplit("/", 1)[1]])
        with patch.dict("os.environ", {"GITHUB_SHA": SHA, "GITHUB_RUN_ID": "42",
                                      "GITHUB_RUN_ATTEMPT": "1"}), \
             patch.object(release_control, "download_public", side_effect=download):
            with self.assertRaisesRegex(release_control.ReleaseError, "Latest Sparkle feed"):
                release_control.verify_release(self.github, REPO, {}, "v1.4.4",
                                               self.directory, public=True, metadata_only=True)

    def test_failed_same_source_dispatch_can_recover_unchanged_distribution(self):
        self.github.latest_run = {**self.github.run, "id": 43, "event": "workflow_dispatch", "conclusion": "failure"}
        with patch.dict("os.environ", {"GITHUB_RUN_ID": "44", "GITHUB_RUN_ATTEMPT": "1"}):
            result = release_control.recover_release(self.github, REPO, {}, 43)
        self.assertTrue(result["rollback_verified"])
        self.assertEqual(result["healthy_source_sha"], SHA)

    def test_changed_github_asset_digest_blocks_gate(self):
        self.github.release["assets"][0]["digest"] = "sha256:" + "0" * 64
        with self.assertRaisesRegex(release_control.ReleaseError, "digest"):
            self.gate()

    def test_rollback_that_does_not_restore_latest_fails_closed(self):
        original = self.github.api
        def stale_latest(endpoint, *args, **kwargs):
            if endpoint.endswith("/releases/latest"):
                return {"tag_name": "v1.4.4"}
            return original(endpoint, *args, **kwargs)
        self.github.api = stale_latest
        with self.assertRaisesRegex(release_control.ReleaseError, "restore"):
            release_control.withdraw(self.github, REPO, 8, SHA, 42, "v1.4.3")

    def test_wrong_appcast_url_is_rejected(self):
        with self.assertRaisesRegex(release_control.ReleaseError, "URL"):
            release_control.validate_feed(feed(url="https://evil.example/file.dmg"), REPO, "1.4.4", "11", 3)

    def test_wrong_build_is_rejected(self):
        with self.assertRaisesRegex(release_control.ReleaseError, "build"):
            release_control.validate_feed(feed(build="10"), REPO, "1.4.4", "11", 3)

    def test_multiple_appcast_items_are_rejected(self):
        xml = feed().replace(b"</channel>", b"<item/></channel>")
        with self.assertRaises(release_control.ReleaseError):
            release_control.validate_feed(xml, REPO, "1.4.4", "11", 3)

    def test_network_failure_blocks_without_mutation(self):
        def offline(*args, **kwargs):
            raise release_control.ReleaseError("GitHub request failed")
        self.github.api = offline
        with self.assertRaises(release_control.ReleaseError):
            self.gate()
        self.assertEqual(self.github.calls, [])

    def test_withdraw_only_release_owned_by_current_run(self):
        release_control.withdraw(self.github, REPO, 8, SHA, 42, "v1.4.3")
        writes = [call for call in self.github.calls if call[1] != "GET"]
        self.assertEqual(writes, [
            (f"repos/{REPO}/releases/8", "PATCH", {"draft": True, "make_latest": "false"}),
        ])

    def test_withdraw_refuses_another_runs_release(self):
        with self.assertRaisesRegex(release_control.ReleaseError, "owned"):
            release_control.withdraw(self.github, REPO, 8, SHA, 99, "v1.4.3")
        self.assertTrue(all(call[1] == "GET" for call in self.github.calls))

    def test_withdraw_is_idempotent_when_already_draft(self):
        self.github.release["draft"] = True
        release_control.withdraw(self.github, REPO, 8, SHA, 42, "v1.4.3")
        self.assertTrue(all(call[1] == "GET" for call in self.github.calls))

    def test_withdraw_network_failure_is_visible(self):
        original = self.github.api
        def fail_write(endpoint, method="GET", fields=None):
            if method == "PATCH":
                raise release_control.ReleaseError("GitHub request failed")
            return original(endpoint, method, fields)
        self.github.api = fail_write
        with self.assertRaisesRegex(release_control.ReleaseError, "GitHub request failed"):
            release_control.withdraw(self.github, REPO, 8, SHA, 42, "v1.4.3")

    def failed_main(self):
        self.github.sha = "b" * 40
        self.github.latest_run = {**self.github.run, "id": 43, "head_sha": self.github.sha, "conclusion": "failure"}

    def bootstrap_fixture(self):
        self.failed_main()
        self.github.releases = []
        self.github.latest_run["updated_at"] = "2026-11-01T23:54:18Z"
        self.github.failed_jobs = {"jobs": [{"name": "build", "status": "completed",
                                             "conclusion": "skipped"}]}
        self.github.bootstrap_statuses = [{
            "id": 567, "context": "glimpse/bootstrap-recovery/43/1", "state": "success",
            "creator": {"id": 123}, "created_at": "2026-11-02T00:00:00Z",
            "target_url": f"https://github.com/{REPO}/actions/runs/43",
            "description": f"Verified v1.4.4 at {SHA}; failed run 43 attempt 1; no publication",
        }]
        return {"legacy_release": {}, "legacy_recovery": {
            "failed_run_id": 43, "failed_run_attempt": 1,
            "source_sha": self.github.sha, "failed_tag": "v1.4.5", "creator_id": 123,
            "healthy_tag": "v1.4.4", "healthy_source_sha": SHA, "healthy_run_id": 42,
            "status_id": 567,
        }}

    def test_exact_first_install_recovery_status_unlocks_remediation(self):
        policy = self.bootstrap_fixture()
        self.assertEqual(release_control.verify_previous(self.github, REPO, policy)[
            "verified_remote_sha"], self.github.sha)
        self.assertTrue(all(method == "GET" for _, method, _ in self.github.calls))

    def test_bootstrap_record_preparation_is_read_only(self):
        policy = self.bootstrap_fixture()
        result = release_control.prepare_bootstrap_recovery(self.github, REPO, policy)
        self.assertEqual(result["state"], "success")
        self.assertEqual(result["description"], self.github.bootstrap_statuses[0]["description"])
        self.assertTrue(all(method == "GET" for _, method, _ in self.github.calls))

    def test_bootstrap_missing_status_stays_closed(self):
        policy = self.bootstrap_fixture()
        self.github.bootstrap_statuses = []
        with self.assertRaises(release_control.ReleaseError):
            release_control.verify_previous(self.github, REPO, policy)

    def test_bootstrap_preparation_refuses_changed_or_active_remote(self):
        for scenario in ("main", "run", "active"):
            with self.subTest(scenario=scenario):
                policy = self.bootstrap_fixture()
                if scenario == "main":
                    self.github.sha = "c" * 40
                elif scenario == "run":
                    self.github.latest_run["id"] = 44
                else:
                    self.github.latest_run["status"] = "in_progress"
                with self.assertRaises(release_control.ReleaseError):
                    release_control.prepare_bootstrap_recovery(self.github, REPO, policy)

    def test_bootstrap_status_identity_failures_stay_closed(self):
        for field, value in (("id", 999), ("state", "failure"), ("creator", {"id": 999}),
                             ("description", "not an audit"), ("target_url", "https://example.com"),
                             ("created_at", "2026-11-01T23:00:00Z")):
            with self.subTest(field=field):
                policy = self.bootstrap_fixture()
                self.github.bootstrap_statuses[0][field] = value
                with self.assertRaises(release_control.ReleaseError):
                    release_control.verify_previous(self.github, REPO, policy)

    def bootstrap_transition(self):
        policy = self.bootstrap_fixture()
        failed = copy.deepcopy(self.github.latest_run)
        self.github.sha = "c" * 40
        current = {**failed, "id": 44, "head_sha": self.github.sha, "status": "in_progress",
                   "conclusion": None, "event": "push"}
        commit = {"parents": [{"sha": failed["head_sha"]}]}
        original = self.github.api
        def api(endpoint, **kwargs):
            if "/actions/workflows/release.yml/" in endpoint:
                return {"workflow_runs": [current, failed]}
            if endpoint.endswith("/actions/runs/43"):
                return failed
            if endpoint.endswith("/actions/runs/44"):
                return current
            if endpoint.endswith("/commits/" + self.github.sha):
                return commit
            return original(endpoint, **kwargs)
        self.github.api = api
        return policy, current, commit

    def test_bootstrap_allows_exact_first_push_inspection_of_its_parent(self):
        policy, _, _ = self.bootstrap_transition()
        result = release_control.verify_previous(
            self.github, REPO, policy, expected_sha="b" * 40, ignore_run_id=44)
        self.assertEqual(result["verified_remote_sha"], "b" * 40)

    def test_bootstrap_predecessor_requires_exact_active_push_and_parent(self):
        for scenario in ("dispatch", "source", "completed", "parent", "no_inspector"):
            with self.subTest(scenario=scenario):
                self.github.api = FakeGitHub.api.__get__(self.github)
                policy, current, commit = self.bootstrap_transition()
                if scenario == "dispatch":
                    current["event"] = "workflow_dispatch"
                elif scenario == "source":
                    current["head_sha"] = "d" * 40
                elif scenario == "completed":
                    current["status"] = "completed"
                elif scenario == "parent":
                    commit["parents"][0]["sha"] = "d" * 40
                with self.assertRaises(release_control.ReleaseError):
                    release_control.verify_previous(
                        self.github, REPO, policy, expected_sha="b" * 40,
                        ignore_run_id=None if scenario == "no_inspector" else 44)
        self.github.api = FakeGitHub.api.__get__(self.github)

    def test_newer_failed_bootstrap_status_revokes_old_success(self):
        policy = self.bootstrap_fixture()
        self.github.bootstrap_statuses.insert(0, {
            **self.github.bootstrap_statuses[0], "state": "failure"})
        with self.assertRaises(release_control.ReleaseError):
            release_control.verify_previous(self.github, REPO, policy)

    def test_bootstrap_cannot_approve_build_or_publication(self):
        for scenario in ("build", "release", "tag", "healthy"):
            with self.subTest(scenario=scenario):
                policy = self.bootstrap_fixture()
                if scenario == "build":
                    self.github.failed_jobs["jobs"][0]["conclusion"] = "success"
                elif scenario == "release":
                    self.github.releases = [{"tag_name": "v1.4.5", "body": ""}]
                elif scenario == "tag":
                    original = self.github.api
                    self.github.api = lambda endpoint, **kwargs: (
                        [{"ref": "refs/tags/v1.4.5"}] if "/git/matching-refs/" in endpoint
                        else original(endpoint, **kwargs))
                else:
                    policy["legacy_recovery"]["healthy_source_sha"] = "c" * 40
                with self.assertRaises(release_control.ReleaseError):
                    release_control.verify_previous(self.github, REPO, policy)
                self.github.api = FakeGitHub.api.__get__(self.github)

    def test_bootstrap_is_bound_to_exact_run_attempt_and_source(self):
        for field, value in (("failed_run_id", 44), ("failed_run_attempt", 2),
                             ("source_sha", "c" * 40)):
            with self.subTest(field=field):
                policy = self.bootstrap_fixture()
                policy["legacy_recovery"][field] = value
                with self.assertRaises(release_control.ReleaseError):
                    release_control.verify_previous(self.github, REPO, policy)

    def recovered_main(self):
        self.failed_main()
        self.github.recovery_run = {
            **self.github.run, "id": 44, "head_sha": self.github.sha, "path": ".github/workflows/recovery.yml",
        }
        self.github.recovery_record = {
            "failed_run_id": 43, "failed_run_attempt": 1, "failed_source_sha": self.github.sha,
            "healthy_source_sha": SHA, "healthy_tag": "v1.4.4",
            "recovery_run_id": 44, "recovery_run_attempt": 1, "rollback_verified": True,
        }

    def test_failed_new_main_without_recovery_stays_blocked(self):
        self.failed_main()
        with self.assertRaisesRegex(release_control.ReleaseError, "recovery"):
            self.gate()

    def test_verified_recovery_allows_remediation_commit(self):
        self.recovered_main()
        self.assertEqual(self.gate()["verified_remote_sha"], self.github.sha)

    def test_pending_recovery_cannot_unlock_failed_main(self):
        self.recovered_main()
        self.github.recovery_run["status"] = "in_progress"
        with self.assertRaises(release_control.ReleaseError):
            self.gate()

    def test_recovery_for_another_source_cannot_unlock_main(self):
        self.recovered_main()
        self.github.recovery_record["failed_source_sha"] = "c" * 40
        with self.assertRaisesRegex(release_control.ReleaseError, "Recovery record"):
            self.gate()

    def test_successful_docs_revision_can_reuse_healthy_public_release(self):
        self.failed_main()
        self.github.latest_run["conclusion"] = "success"
        self.assertEqual(self.gate()["source_sha"], SHA)

    def test_unreleased_app_revision_cannot_claim_internal_verification(self):
        self.failed_main()
        self.github.latest_run["conclusion"] = "success"
        self.github.comparison["files"] = [{"filename": "Glimpse/GlimpseApp.swift"}]
        with self.assertRaisesRegex(release_control.ReleaseError, "Unreleased app"):
            self.gate()

    def test_recovery_without_partial_publication_verifies_healthy_release(self):
        self.failed_main()
        with patch.dict("os.environ", {"GITHUB_RUN_ID": "44", "GITHUB_RUN_ATTEMPT": "1"}):
            result = release_control.recover_release(self.github, REPO, {}, 43)
        self.assertTrue(result["rollback_verified"])
        self.assertEqual(result["healthy_source_sha"], SHA)

    def test_recovery_withdraws_partial_publication_using_retained_inspection_record(self):
        self.failed_main()
        self.github.latest_run["run_attempt"] = 2
        partial = {"id": 9, "tag_name": "v1.4.5", "draft": False,
                   "target_commitish": self.github.sha,
                   "body": f"<!-- glimpse-run:43 sha:{self.github.sha} -->"}
        original = self.github.api
        def api(endpoint, method="GET", fields=None):
            if "/releases?per_page=100" in endpoint:
                return [partial]
            if "/actions/runs/43/artifacts" in endpoint:
                return {"artifacts": [{"id": 100, "name": "previous-release-43-1", "expired": False}]}
            if endpoint.endswith("/releases/9"):
                if method == "PATCH":
                    partial.update(fields)
                return partial
            if endpoint.endswith("/releases/latest") and not partial["draft"]:
                return partial
            if "/git/ref/tags/v1.4.5" in endpoint:
                return {"object": {"type": "commit", "sha": self.github.sha}}
            return original(endpoint, method, fields)
        self.github.api = api
        downloaded = []
        def record(run_id, directory, name):
            downloaded.append(name)
            (directory / "previous-release.json").write_text(json.dumps({"tag": "v1.4.4"}))
        self.github.download_run = record
        with patch.dict("os.environ", {"GITHUB_RUN_ID": "44", "GITHUB_RUN_ATTEMPT": "1"}):
            result = release_control.recover_release(self.github, REPO, {}, 43)
        self.assertTrue(partial["draft"])
        self.assertTrue(result["rollback_verified"])
        self.assertEqual(downloaded, ["previous-release-43-1"])

    def test_recovery_refuses_active_release(self):
        self.failed_main()
        self.github.latest_run["status"] = "in_progress"
        with self.assertRaises(release_control.ReleaseError):
            release_control.recover_release(self.github, REPO, {}, 43)

    def test_truncated_compare_cannot_skip_app_publication(self):
        self.github.comparison["total_commits"] = 251
        with self.assertRaisesRegex(release_control.ReleaseError, "truncated"):
            release_control.internal_only(self.github, REPO, SHA, "b" * 40)

    def test_app_renamed_into_docs_is_not_internal_only(self):
        self.github.comparison["files"] = [
            {"filename": "docs/archive.swift", "previous_filename": "Glimpse/GlimpseApp.swift"}
        ]
        self.assertFalse(release_control.internal_only(self.github, REPO, SHA, "b" * 40))

    def test_pending_review_blocks_release_even_with_evidence(self):
        root = self.directory
        (root / ".github").mkdir()
        (root / "evidence.md").write_text("Review underway")
        (root / ".github/release-readiness.json").write_text(json.dumps({
            "version": "1.4.4", "build": "11", "checks": {
                name: {"status": "pending" if name == "qa" else "passed", "evidence": "evidence.md"}
                for name in ("product", "ux", "code", "qa")
            },
        }))
        with self.assertRaisesRegex(release_control.ReleaseError, "qa"):
            release_control.check_readiness("1.4.4", "11", root)

    def test_readiness_for_previous_version_cannot_approve_next_release(self):
        root = self.directory
        (root / ".github").mkdir()
        (root / ".github/release-readiness.json").write_text(json.dumps({"version": "1.4.3", "build": "10"}))
        with self.assertRaisesRegex(release_control.ReleaseError, "version/build"):
            release_control.check_readiness("1.4.4", "11", root)


if __name__ == "__main__":
    unittest.main()
