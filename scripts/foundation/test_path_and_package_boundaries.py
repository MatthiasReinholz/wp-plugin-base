#!/usr/bin/env python3
"""Exercise repository containment and complete updater packaging boundaries."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class PathAndPackageBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="wp-base-path-boundary-")
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name).resolve()
        self.child = self.base / "child"
        shutil.copytree(ROOT / "tests/fixtures/standard-plugin", self.child)
        self.outside = self.base / "outside"
        self.outside.mkdir()
        self.sentinel = self.outside / "sentinel.txt"
        self.sentinel.write_text("Preserve external data.\n")
        self.environment = dict(os.environ, WP_PLUGIN_BASE_ROOT=str(self.child))

    def configure(self, **values):
        with (self.child / ".wp-plugin-base.env").open("a") as config:
            for key, value in values.items():
                config.write(f"\n{key}={value}\n")

    def run_script(self, relative, *arguments):
        return subprocess.run(
            ["bash", str(ROOT / relative), *arguments],
            env=self.environment,
            capture_output=True,
            text=True,
            check=False,
        )

    def assert_failed_safely(self, result):
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.sentinel.read_text(), "Preserve external data.\n")

    def canonicalize(self, path):
        return subprocess.run(
            [
                "bash", "-c",
                'source "$1"; ROOT_DIR="$2"; '
                'wp_plugin_base_assert_path_within_root "$3" Fixture && '
                'wp_plugin_base_canonicalize_path "$3"',
                "fixture", str(ROOT / "scripts/lib/load_config.sh"),
                str(self.child), str(path),
            ],
            capture_output=True,
            text=True,
            check=False,
        )

    def test_contained_paths_and_links_stay_supported(self):
        directory = self.child / "directory with spaces"
        directory.mkdir()
        (directory / "value.txt").write_text("inside")
        (self.child / "relative-link").symlink_to(directory.name)
        (self.child / "absolute-link").symlink_to(directory / "value.txt")
        cases = {
            self.child / "missing/../new/file.txt": self.child / "new/file.txt",
            self.child / "relative-link/value.txt": directory / "value.txt",
            self.child / "absolute-link": directory / "value.txt",
            self.child / "relative-link/new/file.txt": directory / "new/file.txt",
        }
        for path, expected in cases.items():
            with self.subTest(path=path):
                result = self.canonicalize(path)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), str(expected))

    def test_nonexistent_traversal_is_rejected_before_generation(self):
        (self.child / ".wp-plugin-base").symlink_to(ROOT, target_is_directory=True)
        self.configure(DISTIGNORE_FILE="missing/../../outside/escape.distignore")
        result = self.run_script("scripts/update/sync_child_repo.sh")
        self.assert_failed_safely(result)
        self.assertFalse((self.outside / "escape.distignore").exists())
        self.assertFalse((self.child / ".editorconfig").exists())
        self.assertFalse((self.child / "missing").exists())

    def test_final_symlinks_and_loops_are_rejected(self):
        for name, target in (
            ("existing-link", self.sentinel),
            ("dangling-link", self.outside / "missing.txt"),
            ("loop", self.child / "loop"),
        ):
            link = self.child / name
            link.symlink_to(target)
            with self.subTest(name=name):
                self.assert_failed_safely(self.canonicalize(link))
        self.assertFalse((self.outside / "missing.txt").exists())

    def test_linked_build_script_cannot_execute_outside_root(self):
        script = self.outside / "build.sh"
        marker = self.outside / "executed"
        script.write_text(f'#!/usr/bin/env bash\ntouch "{marker}"\n')
        (self.child / "build.sh").symlink_to(script)
        self.configure(BUILD_SCRIPT="build.sh")
        self.assert_failed_safely(self.run_script("scripts/ci/build_zip.sh"))
        self.assertFalse(marker.exists())
        self.assertFalse((self.child / "dist").exists())

    def test_package_output_links_are_rejected_before_build_or_delete(self):
        for output in ("dist", "dist/package", "dist/standard-plugin.zip"):
            with self.subTest(output=output):
                link = self.child / output
                link.parent.mkdir(parents=True, exist_ok=True)
                link.symlink_to(self.outside, target_is_directory=True)
                self.configure(BUILD_SCRIPT="build.sh")
                (self.child / "build.sh").write_text("touch build-executed\n")
                (self.outside / "package").mkdir(exist_ok=True)
                protected = self.outside / "package/sentinel.txt"
                protected.write_text("Keep the previous package.\n")
                result = self.run_script("scripts/ci/build_zip.sh")
                self.assert_failed_safely(result)
                self.assertEqual(protected.read_text(), "Keep the previous package.\n")
                self.assertFalse((self.child / "build-executed").exists())
                self.assertFalse((self.outside / "standard-plugin.zip").exists())
                link.unlink()

    def test_build_cannot_replace_output_directory_with_link(self):
        self.configure(BUILD_SCRIPT="build.sh")
        (self.child / "build.sh").write_text(f'ln -s "{self.outside}" dist\n')
        self.assert_failed_safely(self.run_script("scripts/ci/build_zip.sh"))
        self.assertFalse((self.outside / "standard-plugin.zip").exists())

    def test_plugin_slug_cannot_escape_package_directory(self):
        self.configure(PLUGIN_SLUG="../../../outside")
        self.assert_failed_safely(self.run_script("scripts/ci/build_zip.sh"))
        self.assertFalse((self.child / "dist").exists())

    def test_runtime_updater_requires_all_managed_php(self):
        shutil.copytree(
            ROOT / "templates/child/github-release-updater-pack/lib",
            self.child / "lib",
        )
        self.configure(
            PLUGIN_RUNTIME_UPDATE_PROVIDER="github-release",
            PLUGIN_RUNTIME_UPDATE_SOURCE_URL="https://github.com/example/standard-plugin",
        )
        complete = self.run_script("scripts/ci/build_zip.sh")
        self.assertEqual(complete.returncode, 0, complete.stdout + complete.stderr)
        for relative in (
            "lib/wp-plugin-base/wp-plugin-base-runtime-updater.php",
            "lib/wp-plugin-base/plugin-update-checker/load-v5p7.php",
            "lib/wp-plugin-base/plugin-update-checker/Puc/v5p7/Autoloader.php",
        ):
            with self.subTest(excluded=relative):
                self.configure(PACKAGE_EXCLUDE=relative)
                result = self.run_script("scripts/ci/build_zip.sh")
                self.assert_failed_safely(result)
                self.assertIn(relative, result.stderr)
                self.assertFalse((self.child / "dist/standard-plugin.zip").exists())

    def test_enabled_runtime_packs_reject_missing_or_empty_manifest(self):
        partial = self.base / "partial-foundation"
        shutil.copytree(ROOT / "scripts/lib", partial / "scripts/lib")
        (partial / "scripts/ci").mkdir()
        shutil.copy2(ROOT / "scripts/ci/build_zip.sh", partial / "scripts/ci/build_zip.sh")
        for pack, setting in (
            ("github-release-updater-pack", "GITHUB_RELEASE_UPDATER_ENABLED"),
            ("rest-operations-pack", "REST_OPERATIONS_PACK_ENABLED"),
            ("admin-ui-pack", "ADMIN_UI_PACK_ENABLED"),
        ):
            self.configure(**{setting: "true"})
            template = partial / "templates/child" / pack
            for state in ("missing", "empty"):
                with self.subTest(pack=pack, manifest=state):
                    if state == "empty":
                        template.mkdir(parents=True)
                    result = self.run_script(str(partial / "scripts/ci/build_zip.sh"))
                    self.assert_failed_safely(result)
                    self.assertIn("no authoritative PHP manifest", result.stderr)
                    self.assertIn(pack, result.stderr)
                    self.assertFalse((self.child / "dist/standard-plugin.zip").exists())
            self.configure(**{setting: "false"})


if __name__ == "__main__":
    unittest.main()
