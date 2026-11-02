#!/usr/bin/env python3
"""Select one valid Developer ID Application identity from the CI keychain."""

import argparse
import pathlib
import re
import subprocess
import sys

IDENTITY_LINE = re.compile(r'\s*\d+\)\s+([0-9A-Fa-f]{40})\s+"([^"]+)"\s*')
IDENTITY_PREFIX = "Developer ID Application: "
SECURITY_TIMEOUT_SECONDS = 15


def select_identity(identity_output, expected_team):
    if not re.fullmatch(r"[A-Z0-9]{10}", expected_team):
        raise ValueError("Expected a valid Apple team identifier.")
    identities = []
    for line in identity_output.splitlines():
        if IDENTITY_PREFIX not in line:
            continue
        match = IDENTITY_LINE.fullmatch(line)
        if not match:
            raise ValueError("Invalid Developer ID Application identity output.")
        sha, name = match.groups()
        if not name.startswith(IDENTITY_PREFIX):
            continue
        if not name.endswith(f" ({expected_team})"):
            raise ValueError("Developer ID Application identity belongs to an unexpected team.")
        identities.append(sha.upper())
    if len(identities) != 1:
        raise ValueError("Expected exactly one valid Developer ID Application identity.")
    return identities[0]


def identity_from_keychain(keychain_path, expected_team):
    if not pathlib.Path(keychain_path).is_absolute():
        raise ValueError("Expected an absolute path to the job signing keychain.")
    try:
        result = subprocess.run(
            ["security", "find-identity", "-v", "-p", "codesigning", keychain_path],
            check=True, capture_output=True, text=True, timeout=SECURITY_TIMEOUT_SECONDS,
        )
    except (OSError, subprocess.SubprocessError):
        raise RuntimeError("Unable to read signing identities from the job keychain.") from None
    return select_identity(result.stdout, expected_team)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--keychain", required=True)
    parser.add_argument("--team-id", required=True)
    args = parser.parse_args()
    try:
        identity = identity_from_keychain(args.keychain, args.team_id)
    except (ValueError, RuntimeError) as error:
        print(str(error), file=sys.stderr)
        return 1
    print(identity)
    return 0


if __name__ == "__main__":
    sys.exit(main())
