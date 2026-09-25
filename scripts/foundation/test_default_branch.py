#!/usr/bin/env python3
"""Exercise downstream branch policy without widening foundation trust."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class DefaultBranch(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="wpb-branch-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        shutil.copytree(ROOT / "tests/fixtures/standard-plugin", self.root, dirs_exist_ok=True)
        (self.root / ".wp-plugin-base").symlink_to(ROOT, target_is_directory=True)
        self.config = self.root / ".wp-plugin-base.env"
        self.original = self.config.read_text()
        self.env = dict(os.environ, WP_PLUGIN_BASE_ROOT=str(self.root))
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)

    def configure(self, branch, provider="github"):
        self.config.write_text(self.original + f"\nDEFAULT_BRANCH={branch}\nAUTOMATION_PROVIDER={provider}\n")

    def run_script(self, script, *args, success=True):
        result = subprocess.run(["bash", str(ROOT / "scripts" / script), *args], cwd=self.root,
                                env=self.env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        self.assertEqual(result.returncode == 0, success, result.stdout)
        return result.stdout

    def identity(self, scope, branch, provider="github-release", tag=""):
        result = subprocess.run(["bash", "-c", 'source "$1"; wp_plugin_base_provider_sigstore_identity_regex "$2" "$(wp_plugin_base_provider_default_api_base "$2")" owner/plugin "$3" "$4" "$5"',
                                  "bash", str(ROOT / "scripts/lib/provider.sh"), provider, scope, tag, branch],
                                text=True, capture_output=True, check=True)
        return result.stdout.strip()

    def test_exact_signing_identity_separates_foundation_and_plugin(self):
        for branch in ("main", "trunk", "release.1", "stable/current"):
            with self.subTest(branch=branch):
                expression = self.identity("plugin", branch)
                prefix = "https://github.com/owner/plugin/.github/workflows/release.yml@refs/heads/"
                self.assertRegex(prefix + branch, expression)
                self.assertIsNone(re.search(expression, prefix + "untrusted"))
                self.assertIsNone(re.search(expression, prefix + branch + "/extra"))
                if "." in branch:
                    self.assertIsNone(re.search(expression, prefix + branch.replace(".", "X")))
                foundation = self.identity("foundation", branch)
                self.assertRegex("https://github.com/owner/plugin/.github/workflows/release-foundation.yml@refs/heads/main", foundation)
                self.assertIsNone(re.search(foundation, "https://github.com/owner/plugin/.github/workflows/release-foundation.yml@refs/heads/trunk"))
        gitlab = self.identity("plugin", "trunk", "gitlab-release", "1.2.3")
        self.assertIn("1\\.2\\.3", gitlab)
        self.assertNotIn("trunk", gitlab)

    def test_generated_branch_is_a_string_and_policy_is_exact(self):
        for branch in ("main", "trunk", "stable/current", "true", "null", "123", "0"):
            with self.subTest(branch=branch):
                self.configure(branch)
                self.run_script("update/sync_child_repo.sh")
                self.run_script("ci/audit_workflows.sh", str(self.root), branch)
                result = subprocess.run(["ruby", "-ryaml", "-rjson", "-e", 'doc=YAML.load_file(ARGV[0]); print JSON.generate((doc["on"] || doc[true])["pull_request"]["branches"])',
                                          str(self.root / ".github/workflows/ci.yml")], text=True, capture_output=True, check=True)
                self.assertIn(branch, json.loads(result.stdout))
                release = (self.root / ".github/workflows/release.yml").read_text()
                self.assertIn(f"github.ref == 'refs/heads/{branch}'", release)
                update = (self.root / ".github/workflows/update-foundation.yml").read_text()
                self.assertIn(f'"{branch}"', update)

    def test_invalid_branch_rejected_before_generation(self):
        for branch in ("HEAD", "refs/heads/trunk", "pull/1/head", "a..b", "-flag", "a.lock", "a//b", "a/../b"):
            with self.subTest(branch=branch):
                self.configure(branch)
                self.run_script("ci/validate_config.sh", "--scope", "sync", success=False)

    def test_historical_retry_and_new_signing_context(self):
        self.configure("main")
        self.run_script("ci/check_release_context.sh", str(self.config), "trunk", "true")
        self.run_script("ci/check_release_context.sh", str(self.config), "trunk", "false", success=False)
        self.configure("trunk")
        self.run_script("ci/check_release_context.sh", str(self.config), "trunk", "false")
        self.config.write_text(self.config.read_text() + "AUTOMATION_PROFILE=local\n")
        self.run_script("ci/check_release_context.sh", str(self.config), "trunk", "true", success=False)

    def test_release_pr_must_target_configured_branch(self):
        binary = self.root / "bin"
        binary.mkdir()
        client = binary / "curl"
        client.write_text('#!/bin/sh\nprintf \'%s\\n\' "$@" > "$BRANCH_FIXTURE_RESPONSE.args"\ncat "$BRANCH_FIXTURE_RESPONSE"\n')
        client.chmod(0o755)
        response = self.root / "response.json"
        self.env.update(PATH=str(binary) + os.pathsep + self.env["PATH"], GH_TOKEN="fixture", GITLAB_TOKEN="fixture", BRANCH_FIXTURE_RESPONSE=str(response))
        sha = "a" * 40
        for provider in ("github", "gitlab"):
            self.configure("trunk", provider)
            for actual, success in (("main", False), ("trunk", True)):
                entry = {"merged_at": "now", "base": {"ref": actual}, "head": {"ref": "release/1.2.3"}, "merge_commit_sha": sha}
                if provider == "gitlab":
                    entry = {"state": "merged", "target_branch": actual, "source_branch": "release/1.2.3", "merge_commit_sha": sha}
                response.write_text(json.dumps([entry]))
                self.run_script("ci/check_release_pr.sh", "owner/plugin", "1.2.3", sha, success=success)
        self.configure("trunk", "gitlab")
        self.config.write_text(self.config.read_text() + "AUTOMATION_API_BASE=https://untrusted.invalid/api\n")
        response.write_text(json.dumps([{"merged_at": "now", "base": {"ref": "trunk"},
                                        "head": {"ref": "release/1.2.3"}, "merge_commit_sha": sha}]))
        self.run_script("ci/check_release_pr.sh", "owner/plugin", "1.2.3", sha, "github", "https://api.github.com")
        arguments = Path(str(response) + ".args").read_text()
        self.assertIn("https://api.github.com/repos/owner/plugin/commits/", arguments)
        self.assertNotIn("untrusted.invalid", arguments)


if __name__ == "__main__":
    unittest.main()
