"""Draft ownership and recovered handoff decisions use offline REST fixtures."""
import copy
import inspect
import pathlib
import tempfile
import unittest
from unittest.mock import patch

from test_release_control import FakeGitHub, REPO, SHA, release_control

OLD_SOURCE = "b" * 40
CURRENT_SOURCE = "c" * 40
TAG = "v1.4.5"


def marker(run, source):
    return f"<!-- glimpse-run:{run} sha:{source} -->"


class DraftIdentityContracts(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = pathlib.Path(self.temp.name)
        self.reset_fixture()

    def reset_fixture(self):
        self.github = FakeGitHub(self.directory)
        self.github.sha = CURRENT_SOURCE
        self.failed = {**self.github.run, "id": 43, "head_sha": OLD_SOURCE, "conclusion": "failure"}
        self.github.recovery_run = {**self.github.run, "id": 44, "head_sha": OLD_SOURCE,
                                    "path": ".github/workflows/recovery.yml"}
        self.github.recovery_record = {
            "failed_run_id": 43, "failed_run_attempt": 1, "failed_source_sha": OLD_SOURCE,
            "healthy_source_sha": SHA, "healthy_tag": "v1.4.4",
            "recovery_run_id": 44, "recovery_run_attempt": 1, "rollback_verified": True,
        }
        self.draft = {"id": 9, "tag_name": TAG, "draft": True, "prerelease": False,
                      "published_at": None, "target_commitish": OLD_SOURCE,
                      "body": marker(43, OLD_SOURCE), "assets": []}
        self.listing = self.recoveries = None
        self.refs = []
        self.readbacks = 0
        self.change_on_readback = False
        self.advance_main_on_readback = False
        self.response_id = 9
        self.original_api = self.github.api
        self.github.api = self.api

    def api(self, endpoint, method="GET", fields=None):
        if endpoint.endswith("/releases?per_page=100"):
            value = self.listing if self.listing is not None else [self.draft]
        elif endpoint.endswith("/releases/9"):
            self.readbacks += method == "GET"
            if self.change_on_readback and self.readbacks == 2:
                self.draft["body"] = marker(99, OLD_SOURCE)
            if self.advance_main_on_readback and self.readbacks == 2:
                self.github.sha = OLD_SOURCE
            if method == "PATCH":
                self.draft.update(fields)
                value = {**self.draft, "id": self.response_id}
            else:
                value = self.draft
        elif endpoint.endswith("/releases") and method == "POST":
            self.draft = {**fields, "id": 9, "published_at": None, "assets": []}
            value = {**self.draft, "id": self.response_id}
        elif endpoint.endswith("/actions/runs/43"):
            value = self.failed
        elif "/actions/workflows/recovery.yml/" in endpoint:
            value = {"workflow_runs": self.recoveries if self.recoveries is not None
                     else [self.github.recovery_run]}
        elif "/git/matching-refs/tags/" in endpoint:
            value = self.refs
        else:
            return self.original_api(endpoint, method, fields)
        self.github.calls.append((endpoint, method, fields))
        return copy.deepcopy(value)

    def prepare(self):
        prepare = getattr(release_control, "prepare_draft", None)
        self.assertTrue(callable(prepare), "The controller must prepare drafts by structured REST identity")
        return prepare(self.github, REPO, {}, TAG, CURRENT_SOURCE, 50,
                       "Verified notes\n" + marker(50, CURRENT_SOURCE))

    def writes(self):
        return [call for call in self.github.calls if call[1] != "GET"]

    def assert_rejected_without_mutation(self):
        with self.assertRaises(release_control.ReleaseError):
            self.prepare()
        self.assertEqual(self.writes(), [])

    def test_recovered_internal_descendant_updates_same_numeric_draft(self):
        self.assertEqual(self.prepare(), 9)
        self.assertEqual(len(self.writes()), 1)
        endpoint, method, fields = self.writes()[0]
        self.assertEqual((endpoint, method), (f"repos/{REPO}/releases/9", "PATCH"))
        self.assertEqual(fields["target_commitish"], CURRENT_SOURCE)
        self.assertEqual(fields["body"], "Verified notes\n" + marker(50, CURRENT_SOURCE))
        self.assertTrue(fields["draft"])
        self.assertEqual(self.draft["id"], 9)
        self.assertGreaterEqual(self.readbacks, 2)
        self.assertTrue(any("/compare/" + OLD_SOURCE + "..." + CURRENT_SOURCE in call[0]
                            for call in self.github.calls))
        self.assertTrue(any(call[0].endswith("/releases/latest") for call in self.github.calls))
        mutation = next(index for index, call in enumerate(self.github.calls) if call[1] == "PATCH")
        self.assertEqual(self.github.calls[mutation - 1][0], f"repos/{REPO}/branches/main")

    def test_same_run_retry_still_checks_exact_source_and_never_public_state(self):
        self.draft.update(body=marker(50, CURRENT_SOURCE), target_commitish=CURRENT_SOURCE)
        self.refs = [{"ref": "refs/tags/" + TAG + "-preview"}]
        self.assertEqual(self.prepare(), 9)
        self.assertFalse(any("/recovery.yml/" in call[0] for call in self.github.calls))
        self.assertGreaterEqual(self.readbacks, 2)

    def test_new_empty_draft_uses_structured_creation_response(self):
        self.listing = []
        self.assertEqual(self.prepare(), 9)
        self.assertEqual(self.writes()[0][:2], (f"repos/{REPO}/releases", "POST"))
        self.assertEqual(self.draft["assets"], [])

    def test_invalid_candidate_ids_cannot_mutate(self):
        for invalid in (True, "9", 0, -1, 9.0, None):
            with self.subTest(identity=invalid):
                self.reset_fixture()
                self.draft["id"] = invalid
                self.assert_rejected_without_mutation()

    def test_malformed_creation_and_update_ids_keep_publishing_closed(self):
        for create in (False, True):
            for invalid in (True, "9", 0, -1, 9.0, None, 10):
                with self.subTest(create=create, identity=invalid):
                    self.reset_fixture()
                    if create:
                        self.listing = []
                    self.response_id = invalid
                    if create and invalid == 10:
                        # A new ID is valid; it has no previous identity to disagree with.
                        continue
                    with self.assertRaises(release_control.ReleaseError):
                        self.prepare()
                    self.assertTrue(self.draft["draft"])

    def test_unowned_ambiguous_or_wrong_source_drafts_are_rejected(self):
        for body, target in (
            ("unowned notes", OLD_SOURCE),
            (marker(43, OLD_SOURCE) + "\n" + marker(50, CURRENT_SOURCE), OLD_SOURCE),
            (marker(43, OLD_SOURCE) + "\n<!-- glimpse-run:bad -->", OLD_SOURCE),
            (marker(43, OLD_SOURCE), "main"),
            (marker(50, OLD_SOURCE), OLD_SOURCE),
        ):
            with self.subTest(body=body, target=target):
                self.reset_fixture()
                self.draft.update(body=body, target_commitish=target)
                self.assert_rejected_without_mutation()

    def test_public_previously_published_or_tagged_drafts_cannot_be_reused(self):
        for same_run in (False, True):
            for condition in ("public", "published", "missing-published-state", "tagged"):
                with self.subTest(same_run=same_run, condition=condition):
                    self.reset_fixture()
                    if same_run:
                        self.draft.update(body=marker(50, CURRENT_SOURCE), target_commitish=CURRENT_SOURCE)
                    if condition == "public":
                        self.draft["draft"] = False
                    elif condition == "published":
                        self.draft["published_at"] = "2026-11-02T01:00:00Z"
                    elif condition == "missing-published-state":
                        del self.draft["published_at"]
                    else:
                        self.refs = [{"ref": "refs/tags/" + TAG}]
                    self.assert_rejected_without_mutation()

    def test_ambiguous_or_truncated_release_listing_cannot_mutate(self):
        for listing in ([self.draft, self.draft], [self.draft] * 100, {"message": "Error"}):
            with self.subTest(listing_type=type(listing).__name__, count=len(listing)):
                self.github.calls.clear()
                self.listing = listing
                self.assert_rejected_without_mutation()

    def test_malformed_or_truncated_tag_reference_listing_cannot_mutate(self):
        for refs in ({"message": "Error"}, [{"ref": None}], [{"ref": "refs/tags/other"}] * 100):
            with self.subTest(refs_type=type(refs).__name__, count=len(refs)):
                self.github.calls.clear()
                self.refs = refs
                self.assert_rejected_without_mutation()

    def test_handoff_requires_completed_failed_main_release_and_exact_recovery(self):
        changes = (("status", "in_progress"), ("conclusion", "success"),
                   ("head_sha", CURRENT_SOURCE), ("head_branch", "feature"),
                   ("path", ".github/workflows/other.yml"), ("event", "pull_request"),
                   ("run_attempt", 2), ("id", 99))
        for field, value in changes:
            with self.subTest(field=field):
                self.reset_fixture()
                self.failed[field] = value
                self.assert_rejected_without_mutation()
        for field, value in (("failed_run_id", 99), ("failed_run_attempt", 2),
                             ("failed_source_sha", CURRENT_SOURCE), ("healthy_source_sha", OLD_SOURCE),
                             ("healthy_tag", "v1.4.3"), ("recovery_run_id", 99),
                             ("recovery_run_attempt", 2), ("rollback_verified", False)):
            with self.subTest(record_field=field):
                self.reset_fixture()
                self.github.recovery_record[field] = value
                self.assert_rejected_without_mutation()

    def test_newest_source_recovery_is_selected_without_weakening_ordinary_gate(self):
        unrelated = {**self.github.recovery_run, "id": 45, "head_sha": CURRENT_SOURCE,
                     "status": "in_progress"}
        self.recoveries = [unrelated, self.github.recovery_run]
        self.assertEqual(self.prepare(), 9)
        with self.assertRaises(release_control.ReleaseError):
            release_control.verify_recovery(
                self.github, REPO, self.failed, {"source_sha": SHA, "tag": "v1.4.4"}, OLD_SOURCE)

    def test_newer_invalid_source_recovery_or_truncated_listing_blocks_handoff(self):
        valid = self.github.recovery_run
        for recoveries in ([], [{**valid, "id": 45, "status": "in_progress"}, valid],
                           [valid] * 20):
            with self.subTest(count=len(recoveries)):
                self.github.calls.clear()
                self.recoveries = recoveries
                self.assert_rejected_without_mutation()

    def test_unverified_healthy_release_or_recovery_job_blocks_handoff(self):
        for condition in ("healthy", "recovery-job"):
            with self.subTest(condition=condition):
                self.reset_fixture()
                if condition == "healthy":
                    self.github.release["assets"][0]["digest"] = "sha256:" + "0" * 64
                else:
                    original = self.original_api
                    self.original_api = lambda endpoint, method="GET", fields=None: (
                        {"jobs": [{"name": "recovery-verified", "conclusion": "failure"}]}
                        if "/actions/runs/44/jobs" in endpoint else original(endpoint, method, fields))
                self.assert_rejected_without_mutation()

    def test_app_changes_non_descendant_or_truncated_comparison_block_handoff(self):
        for comparison in (
            {"status": "diverged", "total_commits": 1, "files": []},
            {"status": "identical", "total_commits": 0, "files": []},
            {"status": "ahead", "total_commits": 251, "files": []},
            {"status": "ahead", "total_commits": 1, "files": [{"filename": "Glimpse/App.swift"}]},
            {"status": "ahead", "total_commits": 1,
             "files": [{"filename": "docs/App.swift", "previous_filename": "Glimpse/App.swift"}]},
        ):
            with self.subTest(comparison=comparison):
                self.reset_fixture()
                self.github.comparison = comparison
                self.assert_rejected_without_mutation()

    def test_main_or_candidate_changing_before_update_cannot_mutate(self):
        for condition in ("main", "candidate"):
            with self.subTest(condition=condition):
                self.reset_fixture()
                if condition == "main":
                    self.advance_main_on_readback = True
                else:
                    self.change_on_readback = True
                self.assert_rejected_without_mutation()

    def test_recovered_handoff_does_not_adopt_a_draft_with_existing_assets(self):
        self.draft["assets"] = [{"name": "unproven-artifact.zip"}]
        self.assert_rejected_without_mutation()

    def verify_by_id(self, **kwargs):
        self.assertIn("release_id", inspect.signature(release_control.verify_release).parameters,
                      "Draft verification must select its explicit numeric release ID")
        return release_control.verify_release(
            self.github, REPO, {}, "v1.4.4", self.directory, release_id=9,
            metadata_only=True, **kwargs)

    def test_tagless_draft_verifies_by_id_without_rest_tag_lookup(self):
        self.draft.update(tag_name="v1.4.4", body=marker(42, SHA), target_commitish=SHA,
                          assets=copy.deepcopy(self.github.release["assets"]))
        with patch.dict("os.environ", {"GITHUB_SHA": SHA, "GITHUB_RUN_ID": "42", "GITHUB_RUN_ATTEMPT": "1"}):
            self.verify_by_id()
        self.assertTrue(any(call[0].endswith("/releases/9") for call in self.github.calls))
        self.assertFalse(any("/releases/tags/" in call[0] for call in self.github.calls))

    def test_draft_readback_identity_is_checked_before_asset_download(self):
        for field, value in (("id", 10), ("tag_name", "v9.9.9"), ("draft", False),
                             ("prerelease", True), ("published_at", "2026-11-02T01:00:00Z"),
                             ("target_commitish", OLD_SOURCE), ("body", marker(99, SHA)),
                             ("body", marker(42, SHA) + "\n" + marker(99, SHA))):
            with self.subTest(field=field, value=value):
                self.reset_fixture()
                self.draft.update(tag_name="v1.4.4", body=marker(42, SHA), target_commitish=SHA)
                self.draft[field] = value
                with patch.dict("os.environ", {"GITHUB_SHA": SHA, "GITHUB_RUN_ID": "42",
                                               "GITHUB_RUN_ATTEMPT": "1"}), \
                     patch.object(self.github, "download") as download:
                    with self.assertRaises(release_control.ReleaseError):
                        self.verify_by_id()
                download.assert_not_called()

    def test_public_verification_cannot_use_draft_id_selector(self):
        with self.assertRaises(release_control.ReleaseError):
            self.verify_by_id(public=True)


if __name__ == "__main__":
    unittest.main()
