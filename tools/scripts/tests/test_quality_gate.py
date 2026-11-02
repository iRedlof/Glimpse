import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest

SCRIPTS = pathlib.Path(__file__).parents[1]


class LocalQualityContracts(unittest.TestCase):
    def test_repeated_local_quality_uses_distinct_result_bundles(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            scripts = root / "tools/scripts"
            scripts.mkdir(parents=True)
            (scripts / "tests").mkdir()
            (root / "tools/monitoring").mkdir()
            for directory in (scripts / "tests", root / "tools/monitoring"):
                (directory / "test_fixture.py").write_text(
                    "import unittest\nclass Fixture(unittest.TestCase):\n def test_available(self): self.assertTrue(True)\n"
                )
            (root / "GlimpseCore").mkdir()
            lockfiles = (root / "GlimpseCore/Package.resolved",
                         root / "Glimpse.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")
            for path in lockfiles:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('{"pins":[]}\n')
            shutil.copy(SCRIPTS / "quality-gate.sh", scripts / "quality-gate.sh")
            for name in ("release-control.py", "check-dependency-pins.py"):
                (scripts / name).write_text("print('fixture source validation passed')\n")
            bin_dir = root / "bin"
            bin_dir.mkdir()
            for name in ("swift", "git"):
                path = bin_dir / name
                path.write_text("#!/bin/bash\nexit 0\n")
                path.chmod(0o755)
            xcode = bin_dir / "xcodebuild"
            xcode.write_text("""#!/usr/bin/env python3
import pathlib,sys
assert '-resultBundlePath' not in sys.argv or 'CODE_SIGNING_ALLOWED=NO' in sys.argv
if '-resultBundlePath' in sys.argv:
    path=pathlib.Path(sys.argv[sys.argv.index('-resultBundlePath')+1])
    if path.exists(): sys.exit(1)
    path.mkdir(parents=True)
""")
            xcode.chmod(0o755)
            env = {**os.environ, "PATH": str(bin_dir) + os.pathsep + os.environ["PATH"]}
            env.pop("GLIMPSE_RESULTS_DIR", None)
            env.pop("GLIMPSE_BUILD_ROOT", None)
            env.pop("GLIMPSE_SOURCE_ROOT", None)
            env.pop("GITHUB_OUTPUT", None)
            for attempt in range(2):
                result = subprocess.run(["bash", str(scripts / "quality-gate.sh")], env=env,
                                        text=True, capture_output=True, timeout=20)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(len(list((root / "build").rglob("AppTests.xcresult"))), 2)

    def test_lockfile_mutation_in_archived_source_fails(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            scripts = root / "controller/tools/scripts"
            (scripts / "tests").mkdir(parents=True)
            (scripts.parent / "monitoring").mkdir()
            for directory in (scripts / "tests", scripts.parent / "monitoring"):
                (directory / "test_fixture.py").write_text(
                    "import unittest\nclass Fixture(unittest.TestCase):\n def test_available(self): self.assertTrue(True)\n"
                )
            source = root / "archived-source"
            lockfiles = (source / "GlimpseCore/Package.resolved",
                         source / "Glimpse.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")
            for path in lockfiles:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("original\n")
            shutil.copy(SCRIPTS / "quality-gate.sh", scripts)
            for name in ("release-control.py", "check-dependency-pins.py"):
                (scripts / name).write_text("print('source validation passed')\n")
            bin_dir = root / "bin"
            bin_dir.mkdir()
            for name in ("git", "xcodebuild"):
                path = bin_dir / name
                path.write_text("#!/bin/bash\nexit 0\n")
                path.chmod(0o755)
            swift = bin_dir / "swift"
            swift.write_text("#!/bin/bash\nprintf 'mutated\\n' > Package.resolved\n")
            swift.chmod(0o755)
            result = subprocess.run(
                ["bash", str(scripts / "quality-gate.sh")],
                env={**os.environ, "PATH": str(bin_dir) + os.pathsep + os.environ["PATH"],
                     "GLIMPSE_SOURCE_ROOT": str(source), "GLIMPSE_BUILD_ROOT": str(root / "external")},
                text=True, capture_output=True, timeout=20,
            )
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("dependency-pins.before.sha256", result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
