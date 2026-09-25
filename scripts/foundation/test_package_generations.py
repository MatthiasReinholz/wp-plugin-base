#!/usr/bin/env python3
"""Reproduce concurrent builds, option poisoning, failure and permission boundaries."""

import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("package_generation", ROOT / "scripts/lib/package_generation.py")
PACKAGES = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PACKAGES)


class PackageGenerations(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="wp-package-generations-")
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name).resolve()
        self.child = self.base / "child"
        shutil.copytree(ROOT / "tests/fixtures/standard-plugin", self.child)
        self.environment = dict(os.environ, WP_PLUGIN_BASE_ROOT=str(self.child))
        for key in tuple(self.environment):
            if key.startswith("WP_PLUGIN_BASE_PACKAGE_"):
                del self.environment[key]
        self.configure(PACKAGE_INCLUDE="standard-plugin.php,readme.txt")
        self.builder = ["bash", str(ROOT / "scripts/ci/build_zip.sh")]

    def configure(self, **values):
        with (self.child / ".wp-plugin-base.env").open("a") as stream:
            for key, value in values.items():
                stream.write(f"\n{key}={value}\n")

    def build(self, **environment):
        result = subprocess.run(self.builder, cwd=self.child, env=dict(self.environment, **environment), capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return json.loads((self.child / "dist/package-generation.json").read_text())

    def assert_retained(self, previous):
        self.assertEqual(json.loads((self.child / "dist/package-generation.json").read_text()), previous)
        self.assertEqual(hashlib.sha256((self.child / "dist/standard-plugin.zip").read_bytes()).hexdigest(), previous["sha256"])
        self.assertEqual(PACKAGES.tree_manifest(self.child / "dist/package/standard-plugin"), previous["entries"])

    def test_archive_options_cannot_omit_required_files(self):
        record = self.build(ZIPOPT="-x standard-plugin/readme.txt", UNZIP="-x *", UNZIPOPT="-x *", ZIPINFO="-x *")
        with zipfile.ZipFile(record["zip_path"]) as archive:
            self.assertIn("standard-plugin/readme.txt", archive.namelist())
            self.assertIsNone(archive.testzip())

    def test_failed_inputs_compression_and_verification_keep_last_good_generation(self):
        previous = self.build()
        self.configure(PACKAGE_INCLUDE="standard-plugin.php,readme.txt,absent-source")
        result = subprocess.run(self.builder, cwd=self.child, env=self.environment, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assert_retained(previous)
        self.configure(PACKAGE_INCLUDE="standard-plugin.php,readme.txt")
        commands = self.base / "bin"
        commands.mkdir()
        fake_zip = commands / "zip"
        fake_zip.write_text("#!/bin/sh\nexit 72\n")
        fake_zip.chmod(0o755)
        environment = dict(self.environment, PATH=f"{commands}:{os.environ['PATH']}")
        result = subprocess.run(self.builder, cwd=self.child, env=environment, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assert_retained(previous)
        fake_zip.write_text("#!/usr/bin/env python3\nimport sys,zipfile\nwith zipfile.ZipFile(sys.argv[3], 'w') as z:\n z.writestr('standard-plugin/standard-plugin.php','incorrect')\n")
        result = subprocess.run(self.builder, cwd=self.child, env=environment, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("do not match", result.stderr)
        self.assert_retained(previous)

    def test_failed_result_delivery_restores_previous_compatibility_outputs(self):
        previous = self.build()
        (self.child / "standard-plugin.php").write_text("<?php // attempted new bytes\n")
        result = subprocess.run(self.builder, cwd=self.child,
                                env=dict(self.environment, WP_PLUGIN_BASE_PACKAGE_RESULT_FILE=str(self.base)),
                                capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assert_retained(previous)

    def test_captured_generation_survives_later_build_and_alias_changes(self):
        output = self.base / "result"
        first = self.build(WP_PLUGIN_BASE_PACKAGE_RESULT_FILE=str(output))
        captured = dict(line.split("=", 1) for line in output.read_text().splitlines())
        self.assertEqual(captured["zip_path"], first["zip_path"])
        first_bytes = Path(first["zip_path"]).read_bytes()
        (self.child / "standard-plugin.php").write_text("<?php // second generation\n")
        second = self.build()
        self.assertNotEqual(first["sha256"], second["sha256"])
        self.assertEqual(Path(captured["zip_path"]).read_bytes(), first_bytes)
        self.assertEqual(PACKAGES.tree_manifest(first["package_dir"]), first["entries"])
        # A paused consumer later hashes and uploads these captured bytes.
        self.assertEqual(hashlib.sha256(Path(captured["zip_path"]).read_bytes()).hexdigest(), captured["sha256"])

    def test_result_requires_complete_unique_fields_bound_to_descriptor(self):
        result_path = self.base / "result"
        record = self.build(WP_PLUGIN_BASE_PACKAGE_RESULT_FILE=str(result_path))
        valid = result_path.read_text()
        self.assertEqual(PACKAGES.validate_result(result_path)["sha256"], record["sha256"])
        corruptions = [
            "\n".join(valid.splitlines()[:-1]) + "\n",
            valid + valid.splitlines()[0] + "\n",
            valid.replace(record["zip_path"], str(self.child / "dist/standard-plugin.zip")),
            valid.replace(record["sha256"], "0" * 64),
            valid.replace("\n", "\r\n"), valid + "extra=field\n",
        ]
        for value in corruptions:
            result_path.write_text(value)
            with self.assertRaises(PACKAGES.PackageError):
                PACKAGES.validate_result(result_path)
        result_path.write_text(valid)
        Path(record["zip_path"]).write_bytes(b"changed after verification")
        with self.assertRaises(PACKAGES.PackageError):
            PACKAGES.validate_result(result_path)

    def test_paused_consumers_reject_arguments_from_a_later_generation(self):
        first = self.build()
        for key in ("sbom_path", "signature_path"):
            Path(first[key]).write_text("{}")
        (self.child / "standard-plugin.php").write_text("<?php // subsequent build\n")
        self.build()
        legacy_zip = str(self.child / "dist/standard-plugin.zip")
        legacy_stage = str(self.child / "dist/package/standard-plugin")
        notes = self.base / "notes"
        notes.write_text("Release notes")
        binary = self.base / "consumer-bin"
        binary.mkdir()
        marker_file = self.base / "external-action"
        for command in ("gh", "curl", "cosign", "syft", "svn"):
            path = binary / command
            path.write_text(f'#!/bin/sh\ntouch "{marker_file}"\nexit 99\n')
            path.chmod(0o755)
        environment = dict(self.environment, PATH=f"{binary}:{os.environ['PATH']}",
                            SVN_USERNAME="fixture", SVN_PASSWORD="fixture", GITHUB_REPOSITORY="example/plugin",
                            CI_PROJECT_PATH="example/plugin", GITLAB_TOKEN="fixture")
        for field, suffix in (("package_dir", "DIR"), ("zip_path", "ZIP"), ("sbom_path", "SBOM"),
                              ("signature_path", "SIGNATURE"), ("descriptor_path", "DESCRIPTOR"), ("sha256", "SHA256")):
            environment["WP_PLUGIN_BASE_PACKAGE_" + suffix] = first[field]
        cases = (
            ("sign_release.sh", [legacy_zip, first["signature_path"]]),
            ("generate_sbom.sh", [legacy_stage, first["sbom_path"]]),
            ("publish_github_release.sh", ["1.2.3", "1.2.3", str(notes), legacy_zip, first["sbom_path"], first["signature_path"]]),
            ("publish_gitlab_release.sh", ["1.2.3", "1.2.3", str(notes), legacy_zip, first["sbom_path"], first["signature_path"]]),
            ("deploy_wordpress_org.sh", ["1.2.3", ".wp-plugin-base.env", legacy_stage]),
            ("validate_wordpress_org_deploy.sh", ["1.2.3", ".wp-plugin-base.env", legacy_stage]),
            ("deploy_woocommerce_com.sh", ["1.2.3", ".wp-plugin-base.env", legacy_zip]),
        )
        for script, arguments in cases:
            with self.subTest(script=script):
                result = subprocess.run(["bash", str(ROOT / "scripts/release" / script), *arguments],
                                        cwd=self.child, env=environment, capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("captured", result.stderr)
                self.assertFalse(marker_file.exists())

    def test_custom_generators_are_serialized_before_snapshot(self):
        self.configure(BUILD_SCRIPT="build.sh", BUILD_OUTPUTS="build/value.txt", PACKAGE_INCLUDE="standard-plugin.php,readme.txt,build")
        (self.child / "build.sh").write_text('''set -eu
mkdir -p build
printf '%s' "$GENERATION_VALUE" > build/value.txt
touch "$GENERATION_VALUE.entered"
if [ "$GENERATION_VALUE" = first ]; then
  while [ ! -f first.release ]; do sleep 0.02; done
fi
''')
        first_result, second_result = self.base / "first-result", self.base / "second-result"
        first = subprocess.Popen(self.builder, cwd=self.child, env=dict(self.environment, GENERATION_VALUE="first", WP_PLUGIN_BASE_PACKAGE_RESULT_FILE=str(first_result)), stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.addCleanup(lambda: first.poll() is None and first.kill())
        deadline = time.monotonic() + 20
        while not (self.child / "first.entered").exists() and time.monotonic() < deadline:
            time.sleep(0.02)
        self.assertTrue((self.child / "first.entered").exists())
        second = subprocess.Popen(self.builder, cwd=self.child, env=dict(self.environment, GENERATION_VALUE="second", WP_PLUGIN_BASE_PACKAGE_RESULT_FILE=str(second_result)), stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.addCleanup(lambda: second.poll() is None and second.kill())
        time.sleep(0.3)
        self.assertFalse((self.child / "second.entered").exists())
        (self.child / "first.release").touch()
        for process in (first, second):
            stdout, stderr = process.communicate(timeout=30)
            self.assertEqual(process.returncode, 0, stdout + stderr)
        for result, expected in ((first_result, "first"), (second_result, "second")):
            captured = dict(line.split("=", 1) for line in result.read_text().splitlines())
            with zipfile.ZipFile(captured["zip_path"]) as archive:
                self.assertEqual(archive.read("standard-plugin/build/value.txt").decode(), expected)

    def test_umask_and_timezone_do_not_change_modes_or_archive_bytes(self):
        self.configure(PACKAGE_INCLUDE="standard-plugin.php,readme.txt,executable")
        executable = self.child / "executable"
        executable.write_text("#!/bin/sh\nexit 0\n")
        executable.chmod(0o6755)
        archives = []
        for mask, timezone in (("022", "UTC"), ("077", "Pacific/Honolulu")):
            result = subprocess.run(["bash", "-c", 'umask "$1"; exec bash "$2"', "fixture", mask, self.builder[1]], cwd=self.child, env=dict(self.environment, TZ=timezone), capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            record = json.loads((self.child / "dist/package-generation.json").read_text())
            archives.append(Path(record["zip_path"]).read_bytes())
            self.assertEqual(stat.S_IMODE(Path(record["package_dir"]).parent.stat().st_mode), 0o755)
            self.assertEqual(stat.S_IMODE(Path(record["zip_path"]).parent.stat().st_mode), 0o755)
            destination = self.base / f"extract-{mask}"
            old_umask = os.umask(int(mask, 8))
            try:
                PACKAGES.extract(record["zip_path"], destination, "standard-plugin")
            finally:
                os.umask(old_umask)
            self.assertEqual(stat.S_IMODE((destination / "standard-plugin").stat().st_mode), 0o755)
            self.assertEqual(stat.S_IMODE((destination / "standard-plugin/readme.txt").stat().st_mode), 0o644)
            self.assertEqual(stat.S_IMODE((destination / "standard-plugin/executable").stat().st_mode), 0o755)
        self.assertEqual(*archives)

    def test_complete_verifier_rejects_changed_extra_duplicate_unsafe_and_corrupt_archives(self):
        record = self.build()
        original = Path(record["zip_path"])
        for kind in ("changed", "extra", "missing", "duplicate", "unsafe", "mode", "corrupt"):
            with self.subTest(kind=kind):
                changed = self.base / f"{kind}.zip"
                with zipfile.ZipFile(original) as source, zipfile.ZipFile(changed, "w") as target:
                    for entry in source.infolist():
                        if kind == "missing" and entry.filename.endswith("readme.txt"):
                            continue
                        data = source.read(entry)
                        if kind == "changed" and entry.filename.endswith("readme.txt"):
                            data += b"changed"
                        if kind == "mode" and entry.filename.endswith("readme.txt"):
                            entry.external_attr = (stat.S_IFREG | 0o666) << 16
                        target.writestr(entry, data)
                    if kind in ("extra", "unsafe", "duplicate"):
                        name = {"extra": "standard-plugin/extra", "unsafe": "standard-plugin/../outside", "duplicate": "standard-plugin/readme.txt"}[kind]
                        target.writestr(name, "extra")
                if kind == "corrupt":
                    changed.write_bytes(changed.read_bytes()[:30])
                with self.assertRaises((PACKAGES.PackageError, zipfile.BadZipFile)):
                    PACKAGES.verify(changed, record["package_dir"])

    def test_recovery_rejects_nul_names_before_zipfile_can_normalize_them(self):
        archive = self.base / "nul-name.zip"
        with zipfile.ZipFile(archive, "w") as target:
            target.writestr("standard-plugin/readme.txtQ", "readme")
        archive.write_bytes(archive.read_bytes().replace(b"standard-plugin/readme.txtQ", b"standard-plugin/readme.txt\x00"))
        destination = self.base / "unsafe-extraction"
        with self.assertRaises(PACKAGES.PackageError):
            PACKAGES.extract(archive, destination, "standard-plugin")
        self.assertFalse(destination.exists())

    def test_ordinary_install_failure_rolls_back_all_legacy_outputs(self):
        previous = self.build()
        generation = PACKAGES.create(self.child, "standard-plugin", "standard-plugin.zip")
        shutil.copytree(Path(previous["package_dir"]).parent, generation / "package")
        shutil.copy2(previous["zip_path"], generation / "standard-plugin.zip")
        original = Path.rename
        counter = 0

        def fail_second_install(path, target):
            nonlocal counter
            if path.name.startswith("new-"):
                counter += 1
                if counter == 2:
                    raise OSError("injected ordinary installation failure")
            return original(path, target)

        from unittest.mock import patch
        with patch.object(Path, "rename", fail_second_install), self.assertRaises(OSError):
            PACKAGES.publish(self.child, generation, "standard-plugin", "standard-plugin.zip")
        self.assert_retained(previous)


    def test_failed_rollback_keeps_previous_payload_for_explicit_recovery(self):
        previous = self.build()
        generation = PACKAGES.create(self.child, "standard-plugin", "standard-plugin.zip")
        shutil.copytree(Path(previous["package_dir"]).parent, generation / "package")
        shutil.copy2(previous["zip_path"], generation / "standard-plugin.zip")
        original = Path.rename

        def fail_install_and_rollback(path, target):
            if path.name in ("new-1", "old-1"):
                raise OSError("injected installation/rollback failure")
            return original(path, target)

        from unittest.mock import patch
        with patch.object(Path, "rename", fail_install_and_rollback), self.assertRaises(PACKAGES.PackageError):
            PACKAGES.publish(self.child, generation, "standard-plugin", "standard-plugin.zip")
        retained = list((self.child / "dist").glob(".package-install-*/old-1"))
        self.assertEqual(len(retained), 1)
        self.assertEqual(hashlib.sha256(retained[0].read_bytes()).hexdigest(), previous["sha256"])


if __name__ == "__main__":
    unittest.main()
