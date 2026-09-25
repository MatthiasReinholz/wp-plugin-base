#!/usr/bin/env python3
"""Recover legacy ownership from the project's reviewed HEAD templates and config.

No historical scripts execute. The current trusted renderer proves that current
host files equal the previous template generation before returning a receipt.
"""
import argparse
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import tempfile

SCRIPT_DIR = Path(__file__).resolve().parent


def git(root, *arguments):
    result = subprocess.run(["git", "-C", str(root), *arguments], check=False,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            env={key: value for key, value in os.environ.items() if not key.startswith("GIT_")})
    if result.returncode:
        raise ValueError("Previous committed automation templates are unavailable.")
    return result.stdout


def recover(root, config, output):
    root = root.resolve(strict=True)
    if Path(git(root, "rev-parse", "--show-toplevel").decode().strip()).resolve() != root:
        raise ValueError("Legacy ownership recovery requires the project Git root.")
    config = Path(config).resolve(strict=True).relative_to(root).as_posix()
    selected = [".wp-plugin-base/templates/child", config, "package.json", "package-lock.json",
                "composer.json", "composer.lock", ".wp-plugin-base-admin-ui/package.json",
                ".wp-plugin-base-admin-ui/package-lock.json"]
    tree = git(root, "ls-tree", "-rz", "--full-tree", "HEAD", "--", *selected)
    with tempfile.TemporaryDirectory(prefix="wpb-legacy-ownership-") as temporary:
        previous = Path(temporary)
        for entry in tree.split(b"\0"):
            if not entry:
                continue
            metadata, encoded = entry.split(b"\t", 1)
            mode, kind, digest = metadata.decode("ascii").split()
            name = encoded.decode("utf-8")
            parts = PurePosixPath(name).parts
            if (kind != "blob" or mode not in ("100644", "100755") or not parts
                    or name.startswith("/") or "\\" in name or str(PurePosixPath(name)) != name
                    or any(part in (".", "..") or part.casefold() == ".git" for part in parts)
                    or any(ord(character) < 32 or ord(character) == 127 for character in name)):
                raise ValueError("Historical automation inputs contain unsupported paths or types.")
            target = previous / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(git(root, "cat-file", "blob", digest))
            target.chmod(0o755 if mode == "100755" else 0o644)
        if not (previous / config).is_file() or not (previous / ".wp-plugin-base/templates/child").is_dir():
            raise ValueError("Committed vendor templates and matching config are required for legacy ownership recovery.")
        for name in (".github", ".gitlab", ".gitlab-ci.yml"):
            current = root / name
            target = previous / name
            if current.is_symlink():
                raise ValueError("Automation metadata must not use symbolic links.")
            if current.is_dir():
                shutil.copytree(current, target, symlinks=True)
            elif current.is_file():
                shutil.copy2(current, target)
        # Strip loaded config variables as well as transport context. Only the
        # historical config may choose the old template generation.
        schema = json.loads((SCRIPT_DIR.parent.parent / "docs/config-schema.json").read_text())
        environment = {key: value for key, value in os.environ.items()
                        if key not in schema["keys"] and not key.startswith(("GIT_", "WP_PLUGIN_BASE_"))}
        environment["WP_PLUGIN_BASE_ROOT"] = str(previous)
        result = subprocess.run(["bash", str(SCRIPT_DIR / "capture_automation_ownership.sh"), config],
                                env=environment, check=False, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if result.returncode:
            raise ValueError("Current automation does not match the previous committed templates. Capture ownership before import or reconcile customized automation explicitly.")
        shutil.copyfile(previous / ".wp-plugin-base-automation.json", output)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    parser.add_argument("config", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        recover(args.root, args.config, args.output)
    except (ValueError, OSError, UnicodeError) as error:
        parser.exit(1, f"{error}\n")
