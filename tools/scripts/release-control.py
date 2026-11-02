#!/usr/bin/env python3
"""Fail-closed GitHub release identity, artifact, publication, and rollback gates."""
import argparse
import base64
import datetime
import hashlib
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile
import urllib.parse
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parents[2]
SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"


class ReleaseError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise ReleaseError(message)


class GitHub:
    """The CLI supplies credentials; tokens never enter logs or subprocess arguments."""
    def __init__(self, repository):
        self.repository = repository

    def command(self, arguments, data=None):
        try:
            result = subprocess.run(
                ["gh", *arguments], input=data, text=True, capture_output=True, timeout=180
            )
        except (OSError, subprocess.TimeoutExpired) as error:
            raise ReleaseError("GitHub request failed; release gate remains closed") from error
        require(result.returncode == 0, "GitHub request failed; release gate remains closed")
        return result.stdout

    def api(self, endpoint, method="GET", fields=None):
        arguments = ["api", endpoint, "--method", method]
        if fields is not None:
            arguments += ["--input", "-"]
        output = self.command(arguments, json.dumps(fields) if fields is not None else None)
        return json.loads(output) if output.strip() else {}

    def download(self, tag, directory, names):
        arguments = ["release", "download", tag, "--repo", self.repository, "--dir", str(directory)]
        for name in names:
            arguments += ["--pattern", name]
        self.command(arguments)

    def download_run(self, run_id, directory, name):
        self.command(["run", "download", str(run_id), "--repo", self.repository,
                      "--dir", str(directory), "--name", name])


def read_json(path):
    try:
        return json.loads(pathlib.Path(path).read_text())
    except (OSError, ValueError) as error:
        raise ReleaseError(f"Cannot read JSON: {path}") from error


def resolve_tag(github, repo, tag):
    reference = github.api(f"repos/{repo}/git/ref/tags/{urllib.parse.quote(tag, safe='')}")
    obj = reference["object"]
    for _ in range(5):
        if obj["type"] == "commit":
            return obj["sha"]
        require(obj["type"] == "tag", "Release tag does not identify a commit")
        obj = github.api(f"repos/{repo}/git/tags/{obj['sha']}")["object"]
    raise ReleaseError("Release tag nesting is invalid")


def verify_release_source(github, repo, release, source):
    if release["draft"]:
        require(release.get("target_commitish") == source, "Draft release source mismatch")
        # GitHub may defer creating a new tag until a draft is published.
        refs = github.api(f"repos/{repo}/git/matching-refs/tags/{release['tag_name']}")
        if not any(ref["ref"] == "refs/tags/" + release["tag_name"] for ref in refs):
            return
    require(resolve_tag(github, repo, release["tag_name"]) == source, "Release tag source mismatch")


def validate_feed(data, repo, version, build, size):
    try:
        root = ET.fromstring(data)
        items = root.findall("./channel/item")
        require(len(items) == 1, "Appcast must contain exactly one current release")
        item = items[0]
        enclosure = item.find("enclosure")
        require(enclosure is not None, "Appcast enclosure is missing")
        expected = f"https://github.com/{repo}/releases/download/v{version}/Glimpse-{version}.dmg"
        require(enclosure.get("url") == expected, "Appcast URL does not match the exact release")
        require(enclosure.get("length") == str(size), "Appcast length does not match DMG")
        require(item.findtext(SPARKLE + "version") == str(build), "Appcast build does not match")
        require(item.findtext(SPARKLE + "shortVersionString") == version, "Appcast version does not match")
        signature = enclosure.get(SPARKLE + "edSignature", "")
        require(len(base64.b64decode(signature, validate=True)) == 64, "Invalid Sparkle signature")
        return signature
    except (ET.ParseError, ValueError) as error:
        raise ReleaseError("Invalid appcast XML or signature") from error


def validate_assets(directory, release, manifest, repo):
    names = [f"Glimpse-{manifest['version']}.dmg", "appcast.xml"]
    assets = {}
    for asset in release["assets"]:
        require(asset["name"] not in assets, "Duplicate release asset")
        assets[asset["name"]] = asset
    for name in names:
        require(name in assets and name in manifest["assets"], f"Missing required asset: {name}")
        asset, expected = assets[name], manifest["assets"][name]
        require(asset.get("state") == "uploaded", f"Incomplete release asset: {name}")
        data = (directory / name).read_bytes()
        digest = hashlib.sha256(data).hexdigest()
        require(digest == expected["sha256"], f"Asset digest differs from manifest: {name}")
        require(asset.get("digest") == "sha256:" + digest, f"GitHub asset digest mismatch: {name}")
        require(len(data) == expected["size"] == asset["size"], f"Asset size mismatch: {name}")
    validate_feed(
        (directory / "appcast.xml").read_bytes(), repo, manifest["version"], manifest["build"],
        manifest["assets"][names[0]]["size"],
    )


def require_successful_run(run, source):
    require(run["head_sha"] == source and run["status"] == "completed" and run["conclusion"] == "success",
            "Previous release workflow has not completed successfully for the exact remote source")


def require_verified_job(github, repo, run_id, name="release-verified", attempt=None):
    scope = f"/attempts/{attempt}" if attempt is not None else ""
    jobs = github.api(f"repos/{repo}/actions/runs/{run_id}{scope}/jobs?per_page=100")["jobs"]
    require(any(j["name"] == name and j["conclusion"] == "success" for j in jobs),
            f"Final {name} job has not succeeded")


def verify_healthy_release(github, repo, policy):
    """Validate public distribution independently of later main revisions."""
    release = github.api(f"repos/{repo}/releases/latest")
    require(not release["draft"] and not release["prerelease"], "Previous release is not public stable")
    source = resolve_tag(github, repo, release["tag_name"])
    with tempfile.TemporaryDirectory(prefix="glimpse-release-gate-") as temporary:
        directory = pathlib.Path(temporary)
        legacy = policy.get("legacy_release", {})
        if release["tag_name"] == legacy.get("tag"):
            require(source == legacy["source_sha"], "Legacy release source changed")
            manifest = legacy
        else:
            require(any(a["name"] == "release-manifest.json" for a in release["assets"]),
                    "Previous release manifest is missing")
            github.download(release["tag_name"], directory, ["release-manifest.json"])
            manifest = read_json(directory / "release-manifest.json")
            require(manifest.get("schema") == 1, "Unsupported release manifest")
            require(manifest.get("repository") == repo and manifest.get("source_sha") == source,
                    "Release manifest source identity mismatch")
            require(manifest.get("artifact_validation") == "passed", "Artifact validation is missing")
        run = github.api(f"repos/{repo}/actions/runs/{manifest['workflow_run_id']}")
        require_successful_run(run, source)
        require(run.get("path") == ".github/workflows/release.yml" and run.get("head_branch") == "main",
                "Public release was not produced by the main Release workflow")
        if release["tag_name"] != legacy.get("tag"):
            publishing_attempt = manifest.get("workflow_run_attempt")
            require(isinstance(publishing_attempt, int) and 1 <= publishing_attempt <= run["run_attempt"],
                    "Release manifest workflow identity mismatch")
            require_verified_job(github, repo, run["id"], "build", attempt=(
                publishing_attempt if publishing_attempt != run["run_attempt"] else None
            ))
            require_verified_job(github, repo, run["id"])
        require(release["tag_name"] == "v" + manifest["version"], "Release tag/version mismatch")
        github.download(release["tag_name"], directory, list(manifest["assets"]))
        feed_repo = legacy.get("repository", repo) if release["tag_name"] == legacy.get("tag") else repo
        validate_assets(directory, release, manifest, feed_repo)
    return {**manifest, "tag": release["tag_name"], "release_id": release["id"]}


def internal_only(github, repo, base, head, require_descendant=False):
    comparison = github.api(f"repos/{repo}/compare/{base}...{head}")
    statuses = ("ahead",) if require_descendant else ("ahead", "identical")
    require(comparison["status"] in statuses, "Source is not descended from the verified source")
    require(comparison.get("total_commits", 0) <= 250 and len(comparison.get("files", [])) < 300,
            "Source comparison is truncated; refusing internal-only classification")
    files = comparison.get("files", [])
    def allowed(path):
        return path.startswith(("docs/", ".claude/", ".github/", "tools/")) or path in (
            "README.md", "CLAUDE.md", "AGENTS.md", ".gitignore", ".gitattributes",
        )
    return all(allowed(f["filename"]) and allowed(f.get("previous_filename", f["filename"])) for f in files)


def load_run_record(github, run, prefix, filename):
    with tempfile.TemporaryDirectory(prefix="glimpse-run-record-") as temporary:
        directory = pathlib.Path(temporary)
        github.download_run(run["id"], directory, f"{prefix}-{run['id']}-{run['run_attempt']}")
        return read_json(directory / filename)


def verify_recovery(github, repo, failed_run, healthy, expected_sha, source_scoped=False):
    runs = github.api(f"repos/{repo}/actions/workflows/recovery.yml/runs?per_page=20")["workflow_runs"]
    if source_scoped:
        require(isinstance(runs, list) and len(runs) < 20,
                "Recovery listing is truncated; refusing draft handoff")
        require(all(isinstance(run, dict) and isinstance(run.get("head_sha"), str) and
                    re.fullmatch(r"[0-9a-f]{40}", run["head_sha"])
                    for run in runs), "Recovery listing identity is malformed")
        runs = [run for run in runs if run["head_sha"] == expected_sha]
    require(runs, "Failed release has no verified recovery workflow")
    recovery = runs[0]
    if source_scoped:
        require(type(recovery.get("id")) is int and recovery["id"] > 0 and
                type(recovery.get("run_attempt")) is int and recovery["run_attempt"] > 0 and
                recovery.get("head_branch") == "main", "Recovery workflow identity is malformed")
    require_successful_run(recovery, expected_sha)
    require(recovery.get("path") == ".github/workflows/recovery.yml",
            "Recovery workflow identity mismatch")
    require_verified_job(github, repo, recovery["id"], "recovery-verified")
    record = load_run_record(github, recovery, "release-recovery", "release-recovery.json")
    require(record.get("failed_run_id") == failed_run["id"] and
            record.get("failed_run_attempt") == failed_run["run_attempt"] and
            record.get("failed_source_sha") == expected_sha and
            record.get("healthy_source_sha") == healthy["source_sha"] and
            record.get("healthy_tag") == healthy["tag"] and
            record.get("recovery_run_id") == recovery["id"] and
            record.get("recovery_run_attempt") == recovery["run_attempt"] and
            record.get("rollback_verified") is True, "Recovery record identity mismatch")


def release_identity(value):
    require(type(value) is int and value > 0, "Release ID must be a positive integer")
    return value


def draft_owner(body):
    require(isinstance(body, str) and body.count("<!-- glimpse-run:") == 1,
            "Draft must have exactly one workflow ownership marker")
    matches = re.findall(r"<!-- glimpse-run:([1-9][0-9]*) sha:([0-9a-f]{40}) -->", body)
    require(len(matches) == 1, "Draft workflow ownership marker is malformed")
    run, source = matches[0]
    return int(run), source


def require_tagless(github, repo, tag):
    refs = github.api(f"repos/{repo}/git/matching-refs/tags/{urllib.parse.quote(tag, safe='')}")
    require(isinstance(refs, list) and len(refs) < 100 and
            all(isinstance(ref, dict) and isinstance(ref.get("ref"), str) for ref in refs),
            "Tag reference listing is malformed or truncated")
    require(not any(ref["ref"] == "refs/tags/" + tag for ref in refs),
            "Release tag already exists; a previously published version cannot be reused")


def private_draft_owner(release, tag, expected_id=None):
    require(isinstance(release, dict), "Draft release response is malformed")
    identity = release_identity(release.get("id"))
    require(expected_id is None or identity == expected_id, "Draft release ID changed")
    require(release.get("tag_name") == tag, "Draft release tag mismatch")
    require(release.get("draft") is True and release.get("prerelease") is False,
            "Release must remain a private stable draft")
    require("published_at" in release and release["published_at"] is None,
            "Previously published releases cannot be reused")
    owner = draft_owner(release.get("body"))
    require(release.get("target_commitish") == owner[1], "Draft release source mismatch")
    return owner


def prove_draft_handoff(github, repo, policy, release, owner, source):
    run_id, old_source = owner
    failed = github.api(f"repos/{repo}/actions/runs/{run_id}")
    require(isinstance(failed, dict) and type(failed.get("id")) is int and
            failed.get("id") == run_id and failed.get("head_sha") == old_source and
            failed.get("status") == "completed" and
            failed.get("conclusion") in ("failure", "cancelled", "timed_out") and
            failed.get("head_branch") == "main" and failed.get("event") == "push" and
            failed.get("path") == ".github/workflows/release.yml" and
            type(failed.get("run_attempt")) is int and failed["run_attempt"] > 0,
            "Draft owner is not the exact failed completed main Release run")
    healthy = verify_healthy_release(github, repo, policy)
    verify_recovery(github, repo, failed, healthy, old_source, source_scoped=True)
    require(old_source != source and internal_only(github, repo, old_source, source, require_descendant=True),
            "Draft handoff requires an internal-only descendant")
    require(release.get("assets") == [], "Recovered draft handoff requires an empty draft")


def prepare_draft(github, repo, policy, tag, source, run_id, notes):
    """Create or transfer only a proven private draft; never touch tags or assets."""
    require(re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+", tag), "Invalid release tag")
    require(re.fullmatch(r"[0-9a-f]{40}", source), "Invalid source SHA")
    require(type(run_id) is int and run_id > 0, "Invalid workflow run ID")
    require(draft_owner(notes) == (run_id, source), "New draft ownership marker mismatch")
    releases = github.api(f"repos/{repo}/releases?per_page=100")
    require(isinstance(releases, list) and len(releases) < 100 and
            all(isinstance(release, dict) for release in releases),
            "Release listing is malformed or truncated")
    matches = [release for release in releases if release.get("tag_name") == tag]
    require(len(matches) <= 1, "Ambiguous releases for the requested tag")
    identity = None
    if matches:
        listed = matches[0]
        identity = release_identity(listed.get("id"))
        owner = private_draft_owner(listed, tag, identity)
        release = github.api(f"repos/{repo}/releases/{identity}")
        require(private_draft_owner(release, tag, identity) == owner and
                release.get("body") == listed.get("body"), "Draft changed during ownership inspection")
        if owner[0] == run_id:
            require(owner[1] == source, "Same-run draft source mismatch")
        else:
            prove_draft_handoff(github, repo, policy, release, owner, source)
        current = github.api(f"repos/{repo}/releases/{identity}")
        require(private_draft_owner(current, tag, identity) == owner and
                current.get("body") == release.get("body") and current.get("assets") == release.get("assets"),
                "Draft changed before its ownership update")
    require_tagless(github, repo, tag)
    require(github.api(f"repos/{repo}/branches/main")["commit"]["sha"] == source,
            "Main advanced during draft preparation")
    fields = {"tag_name": tag, "target_commitish": source, "name": tag,
              "body": notes, "draft": True, "prerelease": False}
    endpoint = f"repos/{repo}/releases" + (f"/{identity}" if identity is not None else "")
    response = github.api(endpoint, "PATCH" if identity is not None else "POST", fields)
    receipt = release_identity(response.get("id") if isinstance(response, dict) else None)
    require(private_draft_owner(response, tag, identity) == (run_id, source),
            "Draft response ownership mismatch")
    return receipt


def prepare_bootstrap_recovery(github, repo, policy, failed=None, healthy=None, inspector_id=None):
    """Read-only proof for one audited failure predating installation of Recovery."""
    config = policy.get("legacy_recovery", {})
    require(config, "No audited first-install recovery is configured")
    failed = failed or github.api(f"repos/{repo}/actions/runs/{config['failed_run_id']}")
    require(failed["id"] == config["failed_run_id"] and
            failed["run_attempt"] == config["failed_run_attempt"] and
            failed["head_sha"] == config["source_sha"] and
            failed["head_branch"] == "main" and failed["path"] == ".github/workflows/release.yml" and
            failed["status"] == "completed" and failed["conclusion"] in ("failure", "cancelled", "timed_out"),
            "First-install failed-run identity mismatch")
    main = github.api(f"repos/{repo}/branches/main")["commit"]["sha"]
    if main != config["source_sha"]:
        require(inspector_id is not None, "Main changed after first-install failure")
        inspector = github.api(f"repos/{repo}/actions/runs/{inspector_id}")
        require(inspector["head_sha"] == main and inspector["head_branch"] == "main" and
                inspector["path"] == ".github/workflows/release.yml" and inspector["event"] == "push" and
                inspector["status"] in ("queued", "in_progress"),
                "First-install predecessor requires the current active Release push")
        commit = github.api(f"repos/{repo}/commits/{main}")
        require([parent["sha"] for parent in commit["parents"]] == [config["source_sha"]],
                "First-install Release source is not the failed revision's direct child")
    runs = github.api(f"repos/{repo}/actions/workflows/release.yml/runs?branch=main&per_page=20")["workflow_runs"]
    runs = [run for run in runs if run["id"] != inspector_id]
    require(runs and runs[0]["id"] == failed["id"] and
            runs[0]["run_attempt"] == failed["run_attempt"] and runs[0]["status"] == "completed",
            "Another release supersedes first-install recovery")
    jobs = github.api(
        f"repos/{repo}/actions/runs/{failed['id']}/attempts/{failed['run_attempt']}/jobs?per_page=100")["jobs"]
    build_jobs = [job for job in jobs if job["name"] == "build"]
    require(len(jobs) < 100 and len(build_jobs) == 1 and
            build_jobs[0]["status"] == "completed" and build_jobs[0]["conclusion"] == "skipped",
            "First-install recovery requires a skipped build")
    healthy = healthy or verify_healthy_release(github, repo, policy)
    require(healthy["tag"] == config["healthy_tag"] and
            healthy["source_sha"] == config["healthy_source_sha"] and
            healthy["workflow_run_id"] == config["healthy_run_id"],
            "First-install healthy distribution identity mismatch")
    releases = github.api(f"repos/{repo}/releases?per_page=100")
    marker = f"<!-- glimpse-run:{failed['id']} sha:{failed['head_sha']} -->"
    require(len(releases) < 100 and not any(
        release["tag_name"] == config["failed_tag"] or marker in (release.get("body") or "")
        for release in releases), "First-install failure has a publication")
    refs = github.api(f"repos/{repo}/git/matching-refs/tags/{config['failed_tag']}")
    require(not any(ref["ref"] == "refs/tags/" + config["failed_tag"] for ref in refs),
            "First-install failure has a release tag")
    require(github.api(f"repos/{repo}/branches/main")["commit"]["sha"] == main,
            "Main changed during first-install verification")
    return {
        "state": "success", "context": f"glimpse/bootstrap-recovery/{failed['id']}/{failed['run_attempt']}",
        "description": f"Verified {healthy['tag']} at {healthy['source_sha']}; failed run {failed['id']} attempt {failed['run_attempt']}; no publication",
        "target_url": f"https://github.com/{repo}/actions/runs/{failed['id']}",
    }


def verify_bootstrap_recovery(github, repo, policy, failed, healthy, inspector_id=None):
    expected = prepare_bootstrap_recovery(github, repo, policy, failed, healthy, inspector_id)
    statuses = github.api(f"repos/{repo}/commits/{failed['head_sha']}/statuses?per_page=100")
    require(len(statuses) < 100, "First-install recovery status listing is truncated")
    matching = [status for status in statuses if status["context"] == expected["context"]]
    require(matching, "First-install recovery has no verified GitHub status")
    status = matching[0]  # GitHub returns statuses newest first; later revocation wins.
    config = policy["legacy_recovery"]
    require(status.get("id") == config["status_id"] and
            status.get("creator", {}).get("id") == config["creator_id"] and
            all(status.get(key) == value for key, value in expected.items()),
            "First-install recovery GitHub status identity mismatch")
    require(datetime.datetime.fromisoformat(status["created_at"].replace("Z", "+00:00")) >=
            datetime.datetime.fromisoformat(failed["updated_at"].replace("Z", "+00:00")),
            "First-install recovery status predates failure completion")


def verify_previous(github, repo, policy, expected_sha=None, ignore_run_id=None):
    main = github.api(f"repos/{repo}/branches/main")["commit"]["sha"]
    expected_sha = expected_sha or main
    healthy = verify_healthy_release(github, repo, policy)
    runs = github.api(f"repos/{repo}/actions/workflows/release.yml/runs?branch=main&per_page=20")["workflow_runs"]
    runs = [run for run in runs if run["id"] != ignore_run_id]
    require(runs, "No previous release workflow found")
    run = runs[0]
    require(run["head_sha"] == expected_sha and run["status"] == "completed",
            "Previous release workflow has not completed successfully for the exact remote source")
    if run["conclusion"] == "success":
        if expected_sha == healthy["source_sha"]:
            if run["id"] != healthy["workflow_run_id"]:
                require_verified_job(github, repo, run["id"])
        else:
            require_verified_job(github, repo, run["id"])
            require(internal_only(github, repo, healthy["source_sha"], expected_sha),
                    "Unreleased app changes cannot use internal-only verification")
    else:
        require(run["conclusion"] in ("failure", "cancelled", "timed_out"),
                "Previous release did not complete successfully")
        bootstrap = policy.get("legacy_recovery", {})
        if (bootstrap.get("failed_run_id") == run["id"] and
                bootstrap.get("failed_run_attempt") == run["run_attempt"] and
                bootstrap.get("source_sha") == expected_sha):
            verify_bootstrap_recovery(github, repo, policy, run, healthy, ignore_run_id)
        else:
            verify_recovery(github, repo, run, healthy, expected_sha)
    return {**healthy, "verified_remote_sha": expected_sha}


def recover_release(github, repo, policy, failed_run_id):
    failed = github.api(f"repos/{repo}/actions/runs/{failed_run_id}")
    source = failed["head_sha"]
    require(failed["status"] == "completed" and failed["conclusion"] in ("failure", "cancelled", "timed_out") and
            failed["head_branch"] == "main" and failed["path"] == ".github/workflows/release.yml",
            "Recovery target is not a failed completed main Release run")
    latest_run = github.api(f"repos/{repo}/actions/workflows/release.yml/runs?branch=main&per_page=1")["workflow_runs"][0]
    require(latest_run["id"] == failed["id"] and latest_run["status"] == "completed",
            "Another release is active or supersedes this recovery")
    require(github.api(f"repos/{repo}/branches/main")["commit"]["sha"] == source,
            "Main advanced; recovery must bind the exact failed source")
    marker = f"<!-- glimpse-run:{failed['id']} sha:{source} -->"
    releases = github.api(f"repos/{repo}/releases?per_page=100")
    owned = [r for r in releases if marker in (r.get("body") or "")]
    for release in owned:
        artifacts = github.api(f"repos/{repo}/actions/runs/{failed['id']}/artifacts?per_page=100")["artifacts"]
        candidates = [a for a in artifacts if not a["expired"] and
                      a["name"].startswith(f"previous-release-{failed['id']}-")]
        require(candidates, "Failed release has no retained previous-release verification record")
        previous_artifact = max(candidates, key=lambda artifact: artifact["id"])
        with tempfile.TemporaryDirectory(prefix="glimpse-previous-record-") as temporary:
            directory = pathlib.Path(temporary)
            github.download_run(failed["id"], directory, previous_artifact["name"])
            previous = read_json(directory / "previous-release.json")
        withdraw(github, repo, release["id"], source, failed["id"], previous["tag"])
    healthy = verify_healthy_release(github, repo, policy)
    require(healthy["workflow_run_id"] != failed["id"],
            "Failed workflow still owns the public distribution")
    require(github.api(f"repos/{repo}/branches/main")["commit"]["sha"] == source, "Main changed during recovery")
    recovered_at = datetime.datetime.now(datetime.timezone.utc)
    failed_at = failed.get("updated_at")
    recovery_seconds = None
    if failed_at:
        recovery_seconds = (recovered_at - datetime.datetime.fromisoformat(failed_at.replace("Z", "+00:00"))).total_seconds()
    return {
        "schema": 1, "failed_run_id": failed["id"], "failed_run_attempt": failed["run_attempt"],
        "failed_source_sha": source, "healthy_source_sha": healthy["source_sha"],
        "healthy_tag": healthy["tag"], "rollback_verified": True,
        "recovery_run_id": int(os.environ["GITHUB_RUN_ID"]),
        "recovery_run_attempt": int(os.environ["GITHUB_RUN_ATTEMPT"]),
        "recovered_at": recovered_at.isoformat(), "recovery_seconds": recovery_seconds,
    }


def withdraw(github, repo, release_id, source_sha, run_id, previous_tag):
    """Only hide this run's release. Never delete tags, assets, or rewrite source."""
    release_identity(release_id)
    release = github.api(f"repos/{repo}/releases/{release_id}")
    marker = f"<!-- glimpse-run:{run_id} sha:{source_sha} -->"
    require(marker in (release.get("body") or ""), "Release is not owned by this workflow")
    verify_release_source(github, repo, release, source_sha)
    if not release["draft"]:
        github.api(f"repos/{repo}/releases/{release_id}", "PATCH", {"draft": True, "make_latest": "false"})
    # A previous stable release becomes latest automatically when this one is
    # drafted. The caller verifies /releases/latest and its download afterwards.
    latest = github.api(f"repos/{repo}/releases/latest")
    require(latest["tag_name"] == previous_tag, "Rollback did not restore the previous latest release")


def version_values(root=ROOT):
    project = (root / "Glimpse.xcodeproj/project.pbxproj").read_text()
    versions = re.findall(r"MARKETING_VERSION = ([0-9.]+);", project)
    builds = re.findall(r"CURRENT_PROJECT_VERSION = ([0-9]+);", project)
    require(len(versions) == 4 and len(set(versions)) == 1, "Four marketing versions must agree")
    require(len(builds) == 4 and len(set(builds)) == 1, "Four build numbers must agree")
    require(re.fullmatch(r"\d+\.\d+\.\d+", versions[0]), "Version must be X.Y.Z")
    badge = f"version-{versions[0]}-green"
    require(badge in (root / "README.md").read_text(), "README version badge does not agree")
    return versions[0], builds[0]


def check_readiness(version, build, root=ROOT):
    readiness = read_json(root / ".github/release-readiness.json")
    require(readiness.get("version") == version and readiness.get("build") == build,
            "Readiness review does not match release version/build")
    for name in ("product", "ux", "code", "qa"):
        check = readiness.get("checks", {}).get(name, {})
        evidence = check.get("evidence", "")
        require(check.get("status") == "passed", f"Release readiness is pending: {name}")
        require(evidence and not pathlib.Path(evidence).is_absolute() and
                ".." not in pathlib.Path(evidence).parts and (root / evidence).is_file(),
                f"Release readiness evidence is missing: {name}")
    return readiness


def write_output(values, path):
    pathlib.Path(path).write_text(json.dumps(values, indent=2) + "\n")


def create_manifest(args, repo):
    version, build = version_values()
    check_readiness(version, build)
    sha = os.environ["GITHUB_SHA"]
    require(re.fullmatch(r"[0-9a-f]{40}", sha), "Invalid source SHA")
    directory = pathlib.Path(args.directory)
    files = [directory / f"Glimpse-{version}.dmg", directory / "appcast.xml"]
    manifest = {
        "schema": 1, "repository": repo, "version": version, "build": build,
        "source_sha": sha, "workflow_run_id": int(os.environ["GITHUB_RUN_ID"]),
        "workflow_run_attempt": int(os.environ["GITHUB_RUN_ATTEMPT"]),
        "artifact_validation": "passed",
        "created_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "assets": {p.name: {"sha256": hashlib.sha256(p.read_bytes()).hexdigest(),
                            "size": p.stat().st_size} for p in files},
    }
    validate_feed(files[1].read_bytes(), repo, version, build, files[0].stat().st_size)
    write_output(manifest, directory / "release-manifest.json")


def download_public(url, destination):
    """Use the platform certificate store, preserving TLS and redirect checks."""
    require(urllib.parse.urlsplit(url).scheme == "https", "Public downloads require HTTPS")
    try:
        result = subprocess.run(
            ["/usr/bin/curl", "--disable", "--fail", "--silent", "--show-error", "--location",
             "--proto", "=https", "--proto-redir", "=https", "--max-time", "60",
             "--output", str(destination), url],
            text=True, capture_output=True, timeout=70)
    except (OSError, subprocess.TimeoutExpired) as error:
        destination.unlink(missing_ok=True)
        raise ReleaseError("Public release download failed; release remains unverified") from error
    if result.returncode != 0:
        destination.unlink(missing_ok=True)
        raise ReleaseError(f"Public release download failed (curl exit {result.returncode}); release remains unverified")
    require(destination.is_file(), "Public release download produced no file")


def verify_release(github, repo, policy, tag, directory, public=False, metadata_only=False, release_id=None):
    if public:
        require(release_id is None, "Public verification requires the actual release tag")
        release = github.api(f"repos/{repo}/releases/tags/{tag}")
    else:
        release_identity(release_id)
        release = github.api(f"repos/{repo}/releases/{release_id}")
        owner = private_draft_owner(release, tag, release_id)
        require(owner == (int(os.environ["GITHUB_RUN_ID"]), os.environ["GITHUB_SHA"]),
                "Draft release ownership/source mismatch")
        require_tagless(github, repo, tag)
    require(release.get("tag_name") == tag, "Release tag mismatch")
    directory.mkdir(parents=True, exist_ok=True)
    names = [f"Glimpse-{tag.removeprefix('v')}.dmg", "appcast.xml", "release-manifest.json"]
    if public:
        require(not release["draft"] and not release["prerelease"], "Release is still a draft or prerelease")
        latest = github.api(f"repos/{repo}/releases/latest")
        require(latest["id"] == release["id"], "Published release is not latest")
        for name in names:
            url = f"https://github.com/{repo}/releases/download/{tag}/{name}"
            download_public(url, directory / name)
        latest_url = f"https://github.com/{repo}/releases/latest/download/appcast.xml"
        download_public(latest_url, directory / "latest-appcast.xml")
        require((directory / "latest-appcast.xml").read_bytes() == (directory / "appcast.xml").read_bytes(),
                "Latest Sparkle feed does not match the published release")
    else:
        require(release["draft"], "Release must remain a draft before verification")
        github.download(tag, directory, names)
    manifest = read_json(directory / "release-manifest.json")
    require(manifest.get("repository") == repo and manifest.get("source_sha") == os.environ["GITHUB_SHA"],
            "Downloaded release manifest source mismatch")
    require(manifest.get("workflow_run_id") == int(os.environ["GITHUB_RUN_ID"]),
            "Downloaded release is owned by another workflow")
    require(manifest.get("schema") == 1 and manifest.get("artifact_validation") == "passed",
            "Downloaded release artifact validation is missing")
    require(isinstance(manifest.get("workflow_run_attempt"), int) and
            1 <= manifest["workflow_run_attempt"] <= int(os.environ["GITHUB_RUN_ATTEMPT"]),
            "Downloaded release attempt identity mismatch")
    verify_release_source(github, repo, release, manifest["source_sha"])
    validate_assets(directory, release, manifest, repo)
    if not metadata_only:
        subprocess.run([str(ROOT / "tools/scripts/verify-dmg.sh"), str(directory),
                        manifest["version"], manifest["build"], manifest["source_sha"]], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("gate", "version", "readiness", "manifest", "draft", "verify", "withdraw", "recover", "bootstrap-record", "classify"))
    parser.add_argument("--policy", default=str(ROOT / ".github/release-policy.json"))
    parser.add_argument("--expected-sha")
    parser.add_argument("--ignore-run-id", type=int)
    parser.add_argument("--output")
    parser.add_argument("--directory", default="build/release")
    parser.add_argument("--tag")
    parser.add_argument("--notes-file")
    parser.add_argument("--public", action="store_true")
    parser.add_argument("--metadata-only", action="store_true")
    parser.add_argument("--release-id", type=int)
    parser.add_argument("--previous-tag")
    parser.add_argument("--failed-run-id", type=int)
    parser.add_argument("--base-sha")
    parser.add_argument("--root", default=str(ROOT))
    args = parser.parse_args()
    policy = read_json(args.policy)
    repo = policy["repository"]
    github = GitHub(repo)
    if args.command == "gate":
        result = verify_previous(github, repo, policy, args.expected_sha, args.ignore_run_id)
        if args.output:
            write_output(result, args.output)
        print(f"Verified previous GitHub release {result['tag']} at {result['source_sha']}")
    elif args.command in ("version", "readiness"):
        source_root = pathlib.Path(args.root)
        version, build = version_values(source_root)
        if args.command == "readiness":
            check_readiness(version, build, source_root)
        print(json.dumps({"version": version, "build": build}))
    elif args.command == "manifest":
        create_manifest(args, repo)
    elif args.command == "draft":
        print(prepare_draft(github, repo, policy, args.tag, os.environ["GITHUB_SHA"],
                            int(os.environ["GITHUB_RUN_ID"]), pathlib.Path(args.notes_file).read_text()))
    elif args.command == "verify":
        verify_release(github, repo, policy, args.tag, pathlib.Path(args.directory),
                       args.public, args.metadata_only, args.release_id)
    elif args.command == "withdraw":
        withdraw(github, repo, args.release_id, os.environ["GITHUB_SHA"],
                 int(os.environ["GITHUB_RUN_ID"]), args.previous_tag)
    elif args.command == "recover":
        write_output(recover_release(github, repo, policy, args.failed_run_id), args.output)
    elif args.command == "bootstrap-record":
        write_output(prepare_bootstrap_recovery(github, repo, policy), args.output)
    elif args.command == "classify":
        print("internal" if internal_only(github, repo, args.base_sha, os.environ["GITHUB_SHA"]) else "app")


if __name__ == "__main__":
    try:
        main()
    except (ReleaseError, KeyError, OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"Release gate blocked: {error}", file=sys.stderr)
        sys.exit(1)
