#!/usr/bin/env python3
"""Exercise every updater and the untrusted-artifact boundary without network writes."""

import copy
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("candidate", ROOT / "scripts/update/external_dependency_candidate.py")
candidate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(candidate)
IDS = sorted(candidate.LINT_IDS | candidate.RELEASE_IDS | {"plugin-check", "plugin-update-checker-runtime", "composer-docker-image"})


class DependencyUpdates(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="dependency-contract-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "repository"
        self.root.mkdir()
        for relative in ("scripts", "docs", ".github"):
            shutil.copytree(ROOT / relative, self.root / relative)
        inventory = json.loads((ROOT / candidate.INVENTORY).read_text())
        for item in inventory["dependencies"]:
            for name in (item.get("lockfile"), item.get("pin", {}).get("file")):
                if name:
                    destination = self.root / name
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(ROOT / name, destination)
        subprocess.run(["git", "init", "-q"], cwd=self.root, check=True)
        subprocess.run(["git", "-c", "user.name=Fixture", "-c", "user.email=fixture@example.test", "commit", "--allow-empty", "-qm", "baseline"], cwd=self.root, check=True)
        self.bin = Path(self.temporary.name) / "bin"
        self.bin.mkdir()
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ["PATH"], RUNNER_TEMP=self.temporary.name, GITHUB_TOKEN="fixture-github-secret")
        (self.bin / "curl").write_text('''#!/usr/bin/env python3
import json, os, pathlib, sys
args=sys.argv[1:]; url=args[-1]; output=None
if any('Bearer fixture' in arg for arg in args):
    raise SystemExit('Credential appeared in curl argv')
for key in ('-fsSLo','-o'):
    if key in args: output=args[args.index(key)+1]
if os.environ.get('FAIL_DOWNLOAD') == 'true': sys.exit(1)
version=os.environ['CANDIDATE_VERSION']
if 'api.github.com' in url:
    data=json.dumps([{'tag_name': ('v' if 'plugin-check/' not in url else '')+version,'draft':False,'prerelease':False,'author':{'login':'davidperezgar'},'published_at':'2020-01-01T00:00:00Z'}]).encode()
elif 'auth.docker.io' in url: data=b'{"token":"fixture"}'
elif 'registry-1.docker.io' in url: data=('docker-content-digest: sha256:'+'f'*64+'\\r\\n').encode()
elif '/archive/' in url: data=pathlib.Path(os.environ['PUC_ARCHIVE']).read_bytes()
elif url.endswith('.pem'): data=b'-----BEGIN CERTIFICATE-----\\nfixture\\n-----END CERTIFICATE-----'
elif url.endswith('_checksums.txt'):
    import hashlib
    data=''.join(hashlib.sha256(asset.encode()).hexdigest()+'  '+asset+'\\n' for asset in ['syft_'+version+'_'+platform+'.tar.gz' for platform in ['linux_amd64','darwin_amd64','darwin_arm64']]).encode()
else: data=url.rsplit('/',1)[-1].encode()
if output: pathlib.Path(output).write_bytes(data)
else: sys.stdout.buffer.write(data)
''')
        (self.bin / "curl").chmod(0o755)
        (self.bin / "cosign").write_text('#!/usr/bin/env bash\n[[ "${FAIL_SIGNATURE:-false}" != true ]]\n')
        (self.bin / "cosign").chmod(0o755)
        self.output = Path(self.temporary.name) / "outputs"

    def prepare(self, dependency, failure=False):
        pin = next(item["pin"]["pattern"] for item in json.loads((self.root / candidate.INVENTORY).read_text())["dependencies"] if item["id"] == dependency)
        import re
        version = re.search(r"[0-9]+\.[0-9]+(?:\.[0-9]+)?", pin)
        self.env["CANDIDATE_VERSION"] = (version[0].split(".")[0] + ".99.0") if version else "2.99.0"
        archive = Path(self.temporary.name) / "puc.tar.gz"
        with tarfile.open(archive, "w:gz") as tar:
            content = ("<?php\n/**\n * Plugin Update Checker Library " + self.env["CANDIDATE_VERSION"] + "\n */\n").encode()
            member = tarfile.TarInfo("plugin-update-checker-" + self.env["CANDIDATE_VERSION"] + "/plugin-update-checker.php")
            member.size = len(content)
            tar.addfile(member, io.BytesIO(content))
        self.env["PUC_ARCHIVE"] = str(archive)
        result = subprocess.run(["bash", str(self.root / "scripts/update/prepare_external_dependency_update.sh"), dependency, str(self.output)], cwd=self.root, env=self.env, capture_output=True, text=True)
        if failure:
            self.assertNotEqual(result.returncode, 0)
        else:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def test_all_handlers_produce_complete_applicable_candidates(self):
        for dependency in IDS:
            with self.subTest(dependency=dependency):
                self.prepare(dependency)
                values = candidate.read_outputs(self.output)
                self.assertEqual(values["update_needed"], "true")
                self.assertIn(candidate.INVENTORY, values["git_add_paths"].split(","))
                self.assertTrue(Path(values["pr_body_file"]).is_file())
                body = Path(values["pr_body_file"]).read_text()
                if dependency not in candidate.RELEASE_IDS:
                    self.assertIn("upstream repository, release, or registry metadata", body)
                    self.assertNotIn("selected from GitHub repository and release metadata", body)
                artifact = Path(self.temporary.name) / "artifact.json"
                candidate.bundle(self.root, self.output, artifact, dependency)
                candidate.apply_bundle(self.root, artifact, dependency, self.output, hashlib.sha256(artifact.read_bytes()).hexdigest())
                validator = subprocess.run(["bash", str(self.root / "scripts/ci/validate_dependency_inventory.sh"), str(self.root)], capture_output=True, text=True)
                self.assertEqual(validator.returncode, 0, validator.stderr)
                self.output.unlink()

    def test_update_entrypoints_resolve_generated_child_and_configured_runtimes(self):
        def workflow(relative):
            result = subprocess.run(["ruby", "-rjson", "-ryaml", "-e", "puts JSON.generate(YAML.load_file(ARGV[0]))", str(ROOT / relative)], check=True, capture_output=True, text=True)
            return json.loads(result.stdout)

        child = Path(self.temporary.name) / "child"
        shutil.copytree(ROOT / "tests/fixtures/standard-plugin", child)
        foundation = child / ".wp-plugin-base"
        for directory in ("scripts", "docs", "templates", ".github"):
            shutil.copytree(ROOT / directory, foundation / directory)
        config_path = child / ".wp-plugin-base.env"
        with config_path.open("a") as config:
            config.write("\nPHP_VERSION=8.3\nNODE_VERSION=24.15.0\n")
        env = dict(self.env, WP_PLUGIN_BASE_ROOT=str(child), GITHUB_OUTPUT=str(self.output))
        subprocess.run(["bash", str(foundation / "scripts/update/sync_child_repo.sh")], cwd=child, env=env, check=True, capture_output=True, text=True)
        subprocess.run(["git", "init", "-q"], cwd=child, check=True)
        self.assertFalse((child / "scripts").exists())

        for relative in (".github/workflows/update-foundation.yml", "templates/child/.github/workflows/update-foundation.yml"):
            with self.subTest(workflow=relative):
                steps = workflow(relative)["jobs"]["update"]["steps"]
                for step in steps:
                    for helper in re.findall(r"(?:bash|source) ((?:\.wp-plugin-base/)?scripts/[^\s]+)", step.get("run", "")):
                        self.assertTrue(helper.startswith(".wp-plugin-base/"), helper)
                        self.assertTrue((child / helper).is_file(), helper)
                for name in ("Read config", "Read project runtime config"):
                    step = next(step for step in steps if step["name"] == name)
                    command = step["run"].replace("${{ inputs.config_path }}", ".wp-plugin-base.env")
                    subprocess.run(["bash", "-euo", "pipefail", "-c", command], cwd=child, env=env, check=True, capture_output=True, text=True)
                values = candidate.read_outputs(self.output)
                self.assertEqual(values["node_version"], "24.15.0")
                self.assertEqual(values["php_version"], "8.3")
                self.output.unlink()
                for action, version in (("actions/setup-node@", "node"), ("shivammathur/setup-php@", "php")):
                    setup = next(step for step in steps if step.get("uses", "").startswith(action))
                    self.assertEqual(setup["with"][version + "-version"], "${{ steps.runtime.outputs." + version + "_version }}")
                    self.assertLess(steps.index(setup), next(index for index, step in enumerate(steps) if step["name"] == "Regenerate managed files"))
                remote = next(step["run"] for step in steps if step["name"] == "Add foundation remote")
                for key, value in values.items():
                    remote = remote.replace("${{ steps.config.outputs." + key + " }}", value)
                subprocess.run(["bash", "-euo", "pipefail", "-c", remote], cwd=child, env=env, check=True, capture_output=True, text=True)

        steps = workflow(".github/workflows/update-external-dependency.yml")["jobs"]["validate"]["steps"]
        execute = next(index for index, step in enumerate(steps) if step["name"] == "Install and validate candidate in an unprivileged job")
        for action, key, version in (("actions/setup-node@", "node-version", "22"), ("shivammathur/setup-php@", "php-version", "8.3")):
            setup = next(step for step in steps if step.get("uses", "").startswith(action))
            self.assertEqual(setup["with"][key], version)
            self.assertLess(steps.index(setup), execute)

    def test_workflow_preserves_candidate_isolation(self):
        def workflow(name):
            result = subprocess.run(["ruby", "-rjson", "-ryaml", "-e", "puts JSON.generate(YAML.load_file(ARGV[0]))", str(ROOT / ".github/workflows" / name)], check=True, capture_output=True, text=True)
            return json.loads(result.stdout)

        dispatcher = workflow("update-plugin-check.yml")["jobs"]["update"]
        self.assertEqual(dispatcher["uses"], "./.github/workflows/update-external-dependency.yml")
        self.assertEqual(dispatcher["with"]["dependency_id"], "${{ matrix.dependency_id }}")
        self.assertFalse(dispatcher["strategy"]["fail-fast"])
        self.assertEqual(sorted(dispatcher["strategy"]["matrix"]["dependency_id"]), IDS)
        jobs = workflow("update-external-dependency.yml")["jobs"]

        def assert_isolated(candidate_jobs):
            self.assertEqual(candidate_jobs["validate"]["needs"], "prepare")
            self.assertEqual(sorted(candidate_jobs["publish"]["needs"]), ["prepare", "validate"])
            self.assertEqual(candidate_jobs["prepare"]["outputs"]["artifact_id"], "${{ steps.upload.outputs.artifact-id }}")
            self.assertEqual(candidate_jobs["prepare"]["outputs"]["candidate_sha256"], "${{ steps.prepare.outputs.candidate_sha256 }}")
            for name in ("prepare", "validate", "publish"):
                job = candidate_jobs[name]
                expected_permissions = {"contents": "write", "pull-requests": "write"} if name == "publish" else {"contents": "read"}
                self.assertEqual(job["permissions"], expected_permissions)
                steps = job["steps"]
                checkout = next(step for step in steps if step.get("uses", "").startswith("actions/checkout@"))
                self.assertEqual(checkout["with"]["ref"], "${{ github.sha }}")
                self.assertFalse(checkout["with"]["persist-credentials"])
                if name != "publish":
                    self.assertNotIn("secrets.", json.dumps(job))
                if name == "prepare":
                    producer = next(step for step in steps if step.get("id") == "prepare")
                    self.assertIn("prepare_external_dependency_update.sh", producer["run"])
                    self.assertIn("external_dependency_candidate.py bundle", producer["run"])
                    self.assertIn("sha256sum", producer["run"])
                    upload = next(step for step in steps if step.get("id") == "upload")
                    self.assertTrue(upload["uses"].startswith("actions/upload-artifact@"))
                    self.assertLess(steps.index(producer), steps.index(upload))
                    continue
                download = next(step for step in steps if step.get("uses", "").startswith("actions/download-artifact@"))
                self.assertEqual(download["with"]["artifact-ids"], "${{ needs.prepare.outputs.artifact_id }}")
                apply = next(step for step in steps if step.get("id") == "candidate")
                self.assertEqual(apply["env"]["EXPECTED_DIGEST"], "${{ needs.prepare.outputs.candidate_sha256 }}")
                self.assertIn("external_dependency_candidate.py apply", apply["run"])
                self.assertIn('"$EXPECTED_DIGEST"', apply["run"])
                self.assertLess(steps.index(download), steps.index(apply))
                if name == "validate":
                    execution = next(step for step in steps if "foundation/validate.sh --mode ci" in step.get("run", ""))
                    self.assertLess(steps.index(apply), steps.index(execution))
                if name == "publish":
                    self.assertIn("create_or_update_pr.sh", steps[-1]["run"])
                    self.assertEqual(steps[-1]["env"]["GIT_ADD_PATHS"], "${{ steps.candidate.outputs.git_add_paths }}")
                    self.assertNotIn("secrets.", json.dumps(steps[:-1]))
                    self.assertNotRegex(json.dumps(steps), "install_lint_tools|install_release_security_tools|foundation/validate")

        assert_isolated(jobs)
        for boundary in ("validation-permission", "producer-digest", "download-identity", "apply-digest", "publication-secret"):
            with self.subTest(boundary=boundary):
                changed = copy.deepcopy(jobs)
                if boundary == "validation-permission":
                    changed["validate"]["permissions"]["contents"] = "write"
                elif boundary == "producer-digest":
                    changed["prepare"]["outputs"]["candidate_sha256"] = "${{ needs.validate.outputs.digest }}"
                elif boundary == "download-identity":
                    download = next(step for step in changed["publish"]["steps"] if step.get("uses", "").startswith("actions/download-artifact@"))
                    download["with"]["artifact-ids"] = "${{ needs.validate.outputs.artifact_id }}"
                elif boundary == "apply-digest":
                    apply = next(step for step in changed["publish"]["steps"] if step.get("id") == "candidate")
                    apply["env"]["EXPECTED_DIGEST"] = "${{ needs.validate.outputs.digest }}"
                else:
                    changed["publish"]["steps"][0]["env"] = {"GH_TOKEN": "${{ secrets.WP_PLUGIN_BASE_PR_TOKEN }}"}
                with self.assertRaises(AssertionError):
                    assert_isolated(changed)

    def test_failed_preparation_preserves_all_original_files(self):
        dependency = "editorconfig-checker-binary"
        before = candidate.files_for(self.root, dependency)
        self.env["FAIL_DOWNLOAD"] = "true"
        self.prepare(dependency, failure=True)
        self.assertEqual(candidate.files_for(self.root, dependency), before)
        self.assertFalse(self.output.exists())

    def test_bad_signature_cannot_change_release_tool_pins(self):
        before = candidate.files_for(self.root, "syft-binary")
        self.env["FAIL_SIGNATURE"] = "true"
        self.prepare("syft-binary", failure=True)
        self.assertEqual(candidate.files_for(self.root, "syft-binary"), before)

    def test_publication_rejects_unrelated_paths_and_commit_mismatch(self):
        self.prepare("plugin-check")
        artifact = Path(self.temporary.name) / "artifact.json"
        candidate.bundle(self.root, self.output, artifact, "plugin-check")
        with self.assertRaisesRegex(ValueError, "digest"):
            candidate.apply_bundle(self.root, artifact, "plugin-check", self.output, "0" * 64)
        original = json.loads(artifact.read_text())
        before = candidate.files_for(self.root, "plugin-check")
        for name in ("../escaped", ".github/workflows/ci.yml", "scripts/update/create_or_update_pr.sh", "/tmp/escaped"):
            payload = dict(original, files=dict(original["files"]))
            payload["files"][name] = "bWFsaWNpb3Vz"
            artifact.write_text(json.dumps(payload))
            with self.assertRaises(ValueError):
                candidate.apply_bundle(self.root, artifact, "plugin-check", self.output, hashlib.sha256(artifact.read_bytes()).hexdigest())
            self.assertEqual(candidate.files_for(self.root, "plugin-check"), before)
        original["base_sha"] = "0" * 40
        artifact.write_text(json.dumps(original))
        with self.assertRaises(ValueError):
            candidate.apply_bundle(self.root, artifact, "plugin-check", self.output, hashlib.sha256(artifact.read_bytes()).hexdigest())

    def test_archive_rejects_links_and_traversal(self):
        for name, kind in (("dependency/../../escaped", tarfile.REGTYPE), ("dependency/link", tarfile.SYMTYPE)):
            archive = Path(self.temporary.name) / "unsafe.tar"
            with tarfile.open(archive, "w") as tar:
                entry = tarfile.TarInfo(name)
                entry.type = kind
                entry.linkname = "/tmp/escaped"
                tar.addfile(entry)
            with self.assertRaises(ValueError):
                candidate.extract_archive(archive, Path(self.temporary.name) / "extract", "dependency")

    def test_platform_hashes_ignore_initializers_and_fail_closed(self):
        path = self.root / "scripts/ci/install_lint_tools.sh"
        candidate.replace_hashes(path, "editorconfig_checker_sha256", [str(index) * 64 for index in (1, 2, 3)])
        self.assertIn("editorconfig_checker_sha256=''", path.read_text())
        before = path.read_bytes()
        with self.assertRaises(ValueError):
            candidate.replace_hashes(path, "missing_sha256", ["a" * 64] * 3)
        self.assertEqual(before, path.read_bytes())


if __name__ == "__main__":
    unittest.main()
