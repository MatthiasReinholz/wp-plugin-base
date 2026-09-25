#!/usr/bin/env python3
"""Local profile ownership and real clean-checkout package contracts."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

FOUNDATION = Path(__file__).resolve().parents[2]


class LocalConformance(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="wpb-local-contract-")
        self.root = Path(self.temp.name) / "plugin"
        shutil.copytree(FOUNDATION / "tests/fixtures/standard-plugin", self.root)
        vendored = self.root / ".wp-plugin-base"
        vendored.mkdir()
        shutil.copytree(FOUNDATION / "templates", vendored / "templates")
        for directory in ("scripts", "docs"):
            (vendored / directory).symlink_to(FOUNDATION / directory, target_is_directory=True)
        self.config = self.root / ".wp-plugin-base.env"
        self.config.write_text(self.config.read_text() + "\nAUTOMATION_PROFILE=local\n")
        self.env = {k: v for k, v in os.environ.items() if not any(word in k for word in ("TOKEN", "PASSWORD", "SECRET"))}
        self.env["WP_PLUGIN_BASE_ROOT"] = str(self.root)
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)

    def tearDown(self):
        self.temp.cleanup()

    def run_script(self, script, *args, success=True):
        result = subprocess.run(["bash", str(FOUNDATION / "scripts" / script), *args], env=self.env,
                                cwd=self.root, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        self.assertEqual(result.returncode == 0, success, result.stdout)
        return result.stdout

    def configure(self, **values):
        lines = self.config.read_text().splitlines()
        self.config.write_text("\n".join(line for line in lines if line.split("=", 1)[0] not in values) + "\n" +
                                "\n".join(f"{key}={value}" for key, value in values.items()) + "\n")

    def builder(self, code=None, manifest=False):
        (self.root / "scripts").mkdir(exist_ok=True)
        build = self.root / "scripts/build.sh"
        build.write_text(code or "mkdir -p build\nprintf 'console.log(1);\\n' > build/index.js\nprintf '<?php return [];\\n' > build/index.asset.php\n")
        self.configure(BUILD_SCRIPT="scripts/build.sh", BUILD_OUTPUTS="build/index.js,build/index.asset.php",
                        PACKAGE_INCLUDE="standard-plugin.php,readme.txt,includes,build")
        if manifest:
            self.configure(BUILD_OUTPUT_MANIFEST="build/manifest.json")
            with build.open("a") as stream:
                stream.write("python3 - <<'PY'\nimport hashlib,json\nfrom pathlib import Path\nfiles=[{'path':str(p),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(Path('build').rglob('*')) if p.is_file() and p.name!='manifest.json']\nPath('build/manifest.json').write_text(json.dumps({'schema_version':1,'artifacts':files}))\nPY\n")
        return build

    def metadata(self, version="1.2.3-beta.1"):
        (self.root / "standard-plugin.php").write_text("<?php\n/*\n * Plugin Name: Standard Plugin\n * Description: Local fixture.\n * Version: " + version + "\n * Requires at least: 6.9\n * Requires PHP: 8.1\n * Author: Example\n * License: GPL-2.0-or-later\n * Text Domain: standard-plugin\n */\ndefine('STANDARD_PLUGIN_VERSION', '" + version + "');\n")
        (self.root / "readme.txt").write_text("=== Standard Plugin ===\nContributors: example\nRequires at least: 6.9\nRequires PHP: 8.1\nTested up to: 6.9\nStable tag: " + version + "\nLicense: GPL-2.0-or-later\n")

    def test_clean_checkout_local_full_validation(self):
        self.builder(manifest=True)
        # All host clients are blocked; local validation never attempts them.
        blocked = self.root / "blocked"
        blocked.mkdir()
        for client in ("curl", "gh", "wget"):
            target = blocked / client
            target.write_text("#!/bin/sh\necho 'unexpected host access' >&2\nexit 99\n")
            target.chmod(0o755)
        self.env["PATH"] = str(blocked) + os.pathsep + self.env["PATH"]
        self.run_script("update/sync_child_repo.sh")
        self.assertFalse((self.root / "build").exists())
        self.assertIn("/build/", (self.root / ".gitignore").read_text())
        self.assertFalse((self.root / ".github/workflows").exists())
        self.run_script("ci/validate_project.sh")
        self.assertTrue((self.root / "dist/standard-plugin.zip").is_file())
        receipt = json.loads((self.root / ".wp-plugin-base-automation.json").read_text())
        self.assertEqual(receipt["files"], {})

    def test_managed_local_managed_transitions(self):
        self.configure(AUTOMATION_PROFILE="managed")
        self.run_script("update/sync_child_repo.sh")
        custom = self.root / ".github/workflows/application.yml"
        custom.write_text("name: Application\non: workflow_dispatch\njobs: {}\n")
        managed = self.root / ".github/workflows/release.yml"
        expected = managed.read_bytes()
        self.configure(AUTOMATION_PROFILE="local")
        self.run_script("update/sync_child_repo.sh")
        self.assertFalse(managed.exists())
        self.assertEqual(custom.read_text(), "name: Application\non: workflow_dispatch\njobs: {}\n")
        receipt = (self.root / ".wp-plugin-base-automation.json").read_bytes()
        self.run_script("update/sync_child_repo.sh")
        self.assertEqual(receipt, (self.root / ".wp-plugin-base-automation.json").read_bytes())
        self.configure(AUTOMATION_PROFILE="managed")
        self.run_script("update/sync_child_repo.sh")
        self.assertEqual(expected, managed.read_bytes())

    def test_modified_managed_conflict_precedes_mutation(self):
        self.configure(AUTOMATION_PROFILE="managed")
        self.run_script("update/sync_child_repo.sh")
        managed = self.root / ".github/workflows/release.yml"
        managed.write_text(managed.read_text() + "\n# custom change\n")
        editor = self.root / ".editorconfig"
        editor.write_text("application change sentinel\n")
        self.configure(AUTOMATION_PROFILE="local")
        self.assertIn("Managed automation was edited", self.run_script("update/sync_child_repo.sh", success=False))
        self.assertTrue(managed.exists())
        self.assertEqual(editor.read_text(), "application change sentinel\n")

    def test_initial_local_preserves_unknown_same_name(self):
        custom = self.root / ".github/workflows/release.yml"
        custom.parent.mkdir(parents=True)
        custom.write_text("# own release\n")
        self.run_script("update/sync_child_repo.sh")
        self.assertEqual(custom.read_text(), "# own release\n")
        self.configure(AUTOMATION_PROFILE="managed")
        self.assertIn("Application-owned automation conflicts", self.run_script("update/sync_child_repo.sh", success=False))
        self.assertEqual(custom.read_text(), "# own release\n")

    def test_legacy_exact_templates_can_be_reconciled(self):
        self.configure(AUTOMATION_PROFILE="managed")
        self.run_script("update/sync_child_repo.sh")
        (self.root / ".wp-plugin-base-automation.json").unlink()
        self.configure(AUTOMATION_PROFILE="local")
        self.run_script("update/sync_child_repo.sh")
        self.assertFalse((self.root / ".github/workflows/release.yml").exists())

    def test_capture_legacy_before_vendor_update(self):
        self.configure(AUTOMATION_PROFILE="managed")
        template = self.root / ".wp-plugin-base/templates/child/.github/workflows/release.yml"
        template.write_text(template.read_text() + "\n# old published template\n")
        self.run_script("update/sync_child_repo.sh")
        (self.root / ".wp-plugin-base-automation.json").unlink()
        before = (self.root / ".github/workflows/release.yml").read_bytes()
        self.run_script("update/capture_automation_ownership.sh")
        self.assertEqual(before, (self.root / ".github/workflows/release.yml").read_bytes())
        template.write_text(template.read_text().replace("# old published template", "# updated published template"))
        self.run_script("update/sync_child_repo.sh")
        self.assertIn("updated published template", (self.root / ".github/workflows/release.yml").read_text())

    def test_first_upgrade_uses_committed_previous_templates(self):
        self.configure(AUTOMATION_PROFILE="managed", FOUNDATION_VERSION="v1.9.0")
        templates = self.root / ".wp-plugin-base/templates"
        legacy = json.loads((FOUNDATION / "tests/fixtures/legacy-automation-templates.json").read_text())
        for name, content in legacy["templates"].items():
            target = templates / "child" / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(content)
        self.run_script("update/sync_child_repo.sh")
        (self.root / ".wp-plugin-base-automation.json").unlink()
        old_workflow_bytes = (self.root / ".github/workflows/release.yml").read_bytes()
        self.run_script("update/capture_automation_ownership.sh")
        self.run_script("ci/validate_project.sh")
        self.assertEqual(old_workflow_bytes, (self.root / ".github/workflows/release.yml").read_bytes())
        (self.root / ".wp-plugin-base-automation.json").unlink()
        subprocess.run(["git", "-C", str(self.root), "add", "-f", ".wp-plugin-base/templates", ".wp-plugin-base.env", ".github"], check=True)
        subprocess.run(["git", "-C", str(self.root), "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-qm", "Record previous published template generation"], check=True)
        shutil.rmtree(templates)
        shutil.copytree(FOUNDATION / "templates", templates)
        self.configure(FOUNDATION_VERSION="v1.9.1")
        workflow = self.root / ".github/workflows/release.yml"
        original = workflow.read_bytes()
        workflow.write_bytes(original + b"\n# application customization\n")
        self.run_script("update/sync_child_repo.sh", success=False)
        self.assertEqual(workflow.read_bytes(), original + b"\n# application customization\n")
        self.assertFalse((self.root / ".wp-plugin-base-automation.json").exists())
        workflow.write_bytes(original)
        self.run_script("update/sync_child_repo.sh")
        self.assertEqual(json.loads((self.root / ".wp-plugin-base-automation.json").read_text())["profile"], "managed")
        self.assertIn("v1.9.1", (self.root / "CONTRIBUTING.md").read_text())
        self.assertIn("steps.package.outputs.zip_path", (self.root / ".github/workflows/ci.yml").read_text())

    def test_profile_change_requires_reconciliation(self):
        self.configure(AUTOMATION_PROFILE="managed")
        self.run_script("update/sync_child_repo.sh")
        self.configure(AUTOMATION_PROFILE="local")
        self.assertIn("profile changed", self.run_script("ci/validate_project.sh", success=False))

    def test_local_publication_stays_disabled_with_credentials(self):
        self.env["GH_TOKEN"] = "fixture-never-used"
        self.run_script("ci/check_automation_profile.sh", success=False)
        self.run_script("ci/validate_config.sh", "--scope", "release", success=False)

    def test_missing_source_rejected_before_custom_build(self):
        self.builder("touch ran\n")
        self.configure(PACKAGE_INCLUDE="standard-plugin.php,readme.txt,missing-source.php,build")
        self.run_script("ci/build_zip.sh", success=False)
        self.assertFalse((self.root / "ran").exists())

    def test_incomplete_success_does_not_reuse_stale_output(self):
        self.builder()
        self.run_script("ci/build_zip.sh")
        previous = (self.root / "dist/standard-plugin.zip").read_bytes()
        self.builder("mkdir -p build\nprintf 'console.log(2);' > build/index.js\n")
        self.assertIn("Required build artifact is missing", self.run_script("ci/build_zip.sh", success=False))
        self.assertEqual(previous, (self.root / "dist/standard-plugin.zip").read_bytes())

    def test_output_traversal_symlink_and_directory_rejected(self):
        self.builder("touch ran\n")
        for output in ("../outside.js", "dist/file.js", "standard-plugin.php", ".gitignore", ".distignore", ".wp-plugin-base.env", "build/*.js"):
            with self.subTest(output=output):
                self.configure(BUILD_OUTPUTS=output)
                self.run_script("ci/build_zip.sh", success=False)
                self.assertFalse((self.root / "ran").exists())
        self.configure(BUILD_OUTPUTS="build/index.js")
        (self.root / "build").symlink_to(Path(self.temp.name), target_is_directory=True)
        self.run_script("ci/build_zip.sh", success=False)
        self.assertFalse((self.root / "ran").exists())

    def output_helper(self, mode, **values):
        env = dict(self.env, ROOT_DIR=str(self.root), MAIN_PLUGIN_FILE="standard-plugin.php",
                    README_FILE="readme.txt", BUILD_SCRIPT="scripts/build.sh", BUILD_OUTPUTS="",
                    BUILD_OUTPUT_MANIFEST="build/manifest.json", PACKAGE_INCLUDE="",
                    CONFIG_PATH=str(self.config), DISTIGNORE_FILE=".distignore",
                    WP_PLUGIN_BASE_SECURITY_SUPPRESSIONS_FILE="")
        env.update(values)
        return subprocess.run(["ruby", str(FOUNDATION / "scripts/lib/build_outputs.rb"), mode], env=env,
                              cwd=self.root, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)

    def test_manifest_preserves_all_configured_source_aliases(self):
        self.builder()
        source = self.root / "build/input.txt"
        source.parent.mkdir()
        source.write_bytes(b"required source must survive\n")
        alias = self.root / "source-alias.txt"
        alias.symlink_to("build/input.txt")
        keys = ("MAIN_PLUGIN_FILE", "README_FILE", "BUILD_SCRIPT", "DISTIGNORE_FILE",
                "WP_PLUGIN_BASE_SECURITY_SUPPRESSIONS_FILE", "CONFIG_PATH")
        for key in keys:
            for value in ("./build/input.txt", str(source), "source-alias.txt"):
                for mode in ("inputs", "prepare"):
                    with self.subTest(key=key, value=value, mode=mode):
                        result = self.output_helper(mode, **{key: value})
                        self.assertNotEqual(result.returncode, 0, result.stdout)
                        self.assertIn("must not contain required source", result.stdout)
                        self.assertEqual(source.read_bytes(), b"required source must survive\n")
                        self.assertTrue(alias.is_symlink())

    def test_explicit_outputs_preserve_configured_source_aliases(self):
        self.builder()
        source = self.root / "build/input.txt"
        source.parent.mkdir()
        source.write_bytes(b"required source must survive\n")
        alias = self.root / "source-alias.txt"
        alias.symlink_to("build/input.txt")
        for key in ("MAIN_PLUGIN_FILE", "README_FILE", "BUILD_SCRIPT", "DISTIGNORE_FILE",
                    "WP_PLUGIN_BASE_SECURITY_SUPPRESSIONS_FILE", "CONFIG_PATH"):
            for value in ("./build/input.txt", str(source), "source-alias.txt"):
                with self.subTest(key=key, value=value):
                    result = self.output_helper("prepare", BUILD_OUTPUTS="build/input.txt",
                                                BUILD_OUTPUT_MANIFEST="", **{key: value})
                    self.assertNotEqual(result.returncode, 0, result.stdout)
                    self.assertIn("reserved/source path", result.stdout)
                    self.assertEqual(source.read_bytes(), b"required source must survive\n")

    def test_output_preparation_requires_sources_before_deletion(self):
        self.builder()
        generated = self.root / "build/previous.js"
        generated.parent.mkdir()
        generated.write_bytes(b"previous generated bytes\n")
        for key in ("MAIN_PLUGIN_FILE", "README_FILE", "BUILD_SCRIPT"):
            with self.subTest(key=key):
                result = self.output_helper("prepare", **{key: "./missing-source"})
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertIn("Required source input not found", result.stdout)
                self.assertEqual(generated.read_bytes(), b"previous generated bytes\n")

    def test_output_preparation_protects_filesystem_identity(self):
        self.builder()
        source = self.root / "build/input.txt"
        source.parent.mkdir()
        source.write_bytes(b"required source must survive\n")
        alias = self.root / "hardlink.txt"
        os.link(source, alias)
        result = self.output_helper("prepare", BUILD_OUTPUTS="build/input.txt", BUILD_OUTPUT_MANIFEST="",
                                    README_FILE="hardlink.txt")
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("reserved/source path", result.stdout)
        self.assertEqual(source.read_bytes(), b"required source must survive\n")
        if (self.root / "BUILD/INPUT.TXT").exists():
            for manifest, output in (("BUILD/manifest.json", ""), ("", "BUILD/INPUT.TXT")):
                with self.subTest(manifest=manifest, output=output):
                    result = self.output_helper("prepare", README_FILE="build/input.txt",
                                                BUILD_OUTPUT_MANIFEST=manifest, BUILD_OUTPUTS=output)
                    self.assertNotEqual(result.returncode, 0, result.stdout)
                    self.assertEqual(source.read_bytes(), b"required source must survive\n")
            result = self.output_helper("prepare", DISTIGNORE_FILE="BUILD/absent.distignore")
            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertIn("must not contain required source", result.stdout)
            self.assertEqual(source.read_bytes(), b"required source must survive\n")

    def test_generated_paths_keep_tilde_literal(self):
        self.builder()
        source = self.root / "~/input.txt"
        source.parent.mkdir()
        source.write_bytes(b"literal tilde source must survive\n")
        for value in ("~/input.txt", "./~/input.txt"):
            for manifest, output in (("~/manifest.json", ""), ("", "~/input.txt")):
                with self.subTest(value=value, manifest=manifest, output=output):
                    result = self.output_helper("prepare", README_FILE=value,
                                                BUILD_OUTPUT_MANIFEST=manifest, BUILD_OUTPUTS=output)
                    self.assertNotEqual(result.returncode, 0, result.stdout)
                    self.assertNotIn("Required source input not found", result.stdout)
                    self.assertEqual(source.read_bytes(), b"literal tilde source must survive\n")
        result = self.output_helper("inputs", README_FILE="~/input.txt")
        self.assertEqual(result.returncode, 0, result.stdout)

    def test_generated_output_reserved_names_are_case_insensitive(self):
        self.builder()
        for name in ("DIST", ".Git", ".GITHUB", ".GITLAB", "Node_Modules", "Vendor", ".WP-PLUGIN-BASE-cache"):
            with self.subTest(name=name):
                directory = self.root / name
                directory.mkdir(exist_ok=True)
                sentinel = directory / "preserve.txt"
                sentinel.write_bytes(b"reserved tree must survive\n")
                result = self.output_helper("prepare", BUILD_OUTPUT_MANIFEST=f"{name}/manifest.json")
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertIn("reserved/source path", result.stdout)
                self.assertEqual(sentinel.read_bytes(), b"reserved tree must survive\n")
        for name in ("AGENTS.MD", ".Gitignore", ".GITATTRIBUTES", ".EDITORCONFIG", "Contributing.Md", "Security.Md"):
            with self.subTest(name=name):
                target = self.root / name
                target.write_bytes(b"managed source must survive\n")
                result = self.output_helper("prepare", BUILD_OUTPUT_MANIFEST="", BUILD_OUTPUTS=name)
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertIn("reserved/source path", result.stdout)
                self.assertEqual(target.read_bytes(), b"managed source must survive\n")

    def test_builder_rejects_manifest_source_overlap_before_running(self):
        self.builder("touch ran\n")
        directory = self.root / "build"
        directory.mkdir()
        script = directory / "build.sh"
        script.write_text("touch ran\n")
        self.configure(BUILD_SCRIPT="./build/build.sh", BUILD_OUTPUTS="", BUILD_OUTPUT_MANIFEST="build/manifest.json")
        self.assertIn("must not contain required source", self.run_script("ci/build_zip.sh", success=False))
        self.assertEqual(script.read_text(), "touch ran\n")
        self.assertFalse((self.root / "ran").exists())
        self.configure(BUILD_SCRIPT="scripts/build.sh")
        for key, name in (("MAIN_PLUGIN_FILE", "standard-plugin.php"), ("README_FILE", "readme.txt")):
            with self.subTest(key=key):
                target = directory / name
                shutil.copyfile(self.root / name, target)
                expected = target.read_bytes()
                self.configure(**{key: str(target)})
                self.assertIn("must not contain required source", self.run_script("ci/build_zip.sh", success=False))
                self.assertEqual(target.read_bytes(), expected)
                self.assertFalse((self.root / "ran").exists())
                self.configure(**{key: name})

    def test_manifest_omission_digest_and_duplicate_rejected(self):
        for alteration in ("data['artifacts'].pop()", "data['artifacts'][0]['sha256']='0'*64", "data['artifacts'].append(data['artifacts'][0])"):
            with self.subTest(alteration=alteration):
                build = self.builder(manifest=True)
                with build.open("a") as stream:
                    stream.write("python3 - <<'PY'\nimport json\nfrom pathlib import Path\np=Path('build/manifest.json')\ndata=json.loads(p.read_text())\n" + alteration + "\np.write_text(json.dumps(data))\nPY\n")
                self.run_script("ci/build_zip.sh", success=False)

    def test_excluded_required_output_fails_package(self):
        self.builder(manifest=True)
        self.configure(PACKAGE_EXCLUDE="build/index.js")
        self.run_script("ci/build_zip.sh", success=False)

    def test_output_symlink_swap_rejected_after_build(self):
        self.builder("mkdir -p build\nln -s ../standard-plugin.php build/index.js\nprintf '<?php return [];\\n' > build/index.asset.php\n")
        self.run_script("ci/build_zip.sh", success=False)

    def test_experimental_metadata_is_explicit_and_aligned(self):
        self.metadata()
        self.run_script("ci/validate_wordpress_metadata.sh", success=False)
        self.run_script("ci/validate_wordpress_metadata.sh", "--purpose", "development")
        self.run_script("ci/check_versions.sh")
        p = self.root / "readme.txt"
        p.write_text(p.read_text().replace("1.2.3-beta.1", "1.2.3-beta.2"))
        self.run_script("ci/validate_wordpress_metadata.sh", "--purpose", "development", success=False)
        self.run_script("ci/check_versions.sh", success=False)


if __name__ == "__main__":
    unittest.main()
