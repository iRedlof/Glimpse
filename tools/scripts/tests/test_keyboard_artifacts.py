import importlib.util
import json
import pathlib
import subprocess
import tempfile
import unittest
from unittest import mock


path = pathlib.Path(__file__).parents[1] / "collect-keyboard-artifacts.py"
spec = importlib.util.spec_from_file_location("keyboard_artifacts", path)
collector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(collector)


class KeyboardArtifactContracts(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = pathlib.Path(temporary.name)
        self.stage = self.root / "stage"
        self.stage.mkdir()
        self.destination = self.root / "durable"
        self.manifest = self.root / "manifest.json"
        self.manifest.write_text(json.dumps({"methods": {"Legacy/test()": 1}}))
        self.host = self.root / "DerivedData/Build/Products/Debug/Glimpse.app/Contents/MacOS/Glimpse"
        process = mock.patch.object(
            collector.subprocess, "run",
            return_value=subprocess.CompletedProcess([], 0, "101 /Applications/Other.app/Other\n", ""),
        )
        process.start()
        self.addCleanup(process.stop)

    def collect(self):
        return collector.collect(self.stage, self.destination, self.host, self.manifest, 0)

    def test_durable_readback_mismatch_is_recorded_and_preserves_original_staging(self):
        source = self.stage / "fixture.png"
        source.write_bytes(b"original fixture bytes")
        original_read = pathlib.Path.read_bytes

        def corrupt_durable_read(path):
            return b"corrupt durable bytes" if path.parent == self.destination else original_read(path)

        with mock.patch.object(pathlib.Path, "read_bytes", corrupt_durable_read):
            receipt = self.collect()
        self.assertEqual(receipt["exit_code"], 1)
        self.assertEqual(receipt["copies"], [])
        self.assertTrue(receipt["preserve_staging"])
        self.assertTrue(any("hash mismatch" in error for error in receipt["errors"]))
        self.assertEqual(source.read_bytes(), b"original fixture bytes")

    def test_unexpected_or_empty_entries_fail_without_following_links(self):
        outside = self.root / "outside.png"
        outside.write_bytes(b"outside evidence")
        (self.stage / "link.png").symlink_to(outside)
        (self.stage / "empty.png").touch()
        (self.stage / "directory.png").mkdir()
        receipt = self.collect()
        self.assertEqual(receipt["exit_code"], 1)
        self.assertEqual(receipt["copies"], [])
        self.assertEqual(len(receipt["errors"]), 3)
        self.assertTrue(receipt["preserve_staging"])
        self.assertEqual(outside.read_bytes(), b"outside evidence")
        self.assertEqual(list(self.destination.iterdir()), [])

    def test_canonical_process_path_cannot_hide_live_host_behind_work_directory_alias(self):
        real = self.root / "real"
        real.mkdir()
        alias = self.root / "work-alias"
        alias.symlink_to(real, target_is_directory=True)
        self.host = alias / "Glimpse"
        process = subprocess.CompletedProcess([], 0, "302 " + str(self.host.resolve()) + "\n", "")
        with mock.patch.object(collector.subprocess, "run", return_value=process):
            receipt = self.collect()
        self.assertFalse(receipt["owned_host_absence_confirmed"])
        self.assertEqual(receipt["remaining_owned_pids"], [302])
        self.assertTrue(receipt["preserve_staging"])
        self.assertFalse(self.destination.exists())

    def test_long_owned_path_cannot_be_hidden_by_default_ps_width(self):
        self.host = self.root / ("long-owned-directory-" * 10) / "Glimpse"
        self.assertGreater(len(str(self.host)), 120)
        (self.stage / "fixture.png").write_bytes(b"owned fixture bytes")

        def process_listing(command, **kwargs):
            # Model ps column truncation unless unlimited width was requested.
            unlimited = "-axww" in command or "-ww" in command
            executable = str(self.host) if unlimited else str(self.host)[:80]
            return subprocess.CompletedProcess(command, 0, "302 " + executable + "\n", "")

        with mock.patch.object(collector.subprocess, "run", side_effect=process_listing):
            receipt = self.collect()
        self.assertFalse(receipt["owned_host_absence_confirmed"])
        self.assertEqual(receipt["remaining_owned_pids"], [302])
        self.assertTrue(receipt["preserve_staging"])
        self.assertEqual(receipt["copies"], [])
        self.assertFalse(self.destination.exists())

    def test_receipt_write_failure_does_not_release_workspace_retention_marker(self):
        marker = self.root / "retain-keyboard-artifacts"
        marker.touch()
        arguments = [
            str(path), "--staging", str(self.stage), "--destination", str(self.destination),
            "--host-executable", str(self.host), "--manifest", str(self.manifest),
            "--native-exit", "0", "--retain-marker", str(marker),
            "--receipt", str(self.root / "missing-parent/receipt.json"),
        ]
        with mock.patch("sys.argv", arguments), self.assertRaises(OSError):
            collector.main()
        self.assertTrue(marker.is_file())


if __name__ == "__main__":
    unittest.main()
