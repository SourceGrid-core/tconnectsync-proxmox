from hashlib import sha256
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
INSTALLER = ROOT / "install.sh"


class InstallerManifestTests(unittest.TestCase):
    def test_archive_is_pinned_and_checksum_is_sha256(self):
        source = INSTALLER.read_text()
        commit = re.search(r'^repo_commit="([0-9a-f]{40})"$', source, re.MULTILINE)
        digest = re.search(r'^archive_sha256="([0-9a-f]{64})"$', source, re.MULTILINE)
        self.assertIsNotNone(commit)
        self.assertIsNotNone(digest)
        self.assertIn("codeload.github.com/SourceGrid-core/tconnectsync-proxmox/tar.gz/${repo_commit}", source)
        self.assertIn("sha256sum --check --status", source)

    def test_raw_fallback_digests_match_runtime_files(self):
        source = INSTALLER.read_text()
        entries = re.findall(r"fetch_raw_file ([^ ]+) ([0-9a-f]{64})", source)
        checksums = dict(entries)
        expected_paths = {
            "config/tconnectsync.env.example",
            "scripts/check-config.py",
            "scripts/install-debian.sh",
            "scripts/provision-proxmox.sh",
            "scripts/update-container.sh",
            "scripts/update.sh",
            "systemd/tconnectsync.service",
        }
        self.assertTrue(expected_paths.issubset(checksums))
        for path in expected_paths:
            with self.subTest(path=path):
                actual = sha256((ROOT / path).read_bytes()).hexdigest()
                self.assertEqual(checksums[path], actual)

    def test_sources_are_https_and_not_github_archive_host(self):
        source = INSTALLER.read_text()
        self.assertIn("https://codeload.github.com/", source)
        self.assertIn("https://raw.githubusercontent.com/", source)
        self.assertNotIn("https://github.com/SourceGrid-core/tconnectsync-proxmox/archive", source)
        self.assertNotIn("--insecure", source)


if __name__ == "__main__":
    unittest.main()
