#!/usr/bin/env python3
"""Both targets must build the same resolved dependency graph."""
import json
import argparse
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--root", default=str(ROOT))
ROOT = pathlib.Path(parser.parse_args().root)
PATHS = [
    ROOT / "GlimpseCore/Package.resolved",
    ROOT / "Glimpse.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
]
try:
    graphs = []
    for path in PATHS:
        data = json.loads(path.read_text())
        graphs.append({pin["identity"]: pin["state"] for pin in data["pins"]})
    if graphs[0] != graphs[1]:
        raise ValueError("App and core resolved dependency pins differ")
    for identity, state in graphs[0].items():
        if not state.get("revision") or not state.get("version") or state.get("branch"):
            raise ValueError(f"Dependency requires an immutable version/revision pin: {identity}")
except (OSError, KeyError, ValueError) as error:
    print(f"Dependency gate blocked: {error}", file=sys.stderr)
    sys.exit(1)
print(f"Verified {len(graphs[0])} matching app/core dependency pins")
