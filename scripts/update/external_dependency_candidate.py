#!/usr/bin/env python3
"""Keep dependency candidates transactional and treat transferred artifacts as data."""

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import tarfile
import tempfile

INVENTORY = "docs/dependency-inventory.json"
PUC = "templates/child/github-release-updater-pack/lib/wp-plugin-base/plugin-update-checker"
LINT_IDS = {"shellcheck-binary", "actionlint-binary", "editorconfig-checker-binary", "gitleaks-binary"}
RELEASE_IDS = {"syft-binary", "cosign-binary"}


def paths_for(dependency):
    if dependency in LINT_IDS:
        paths = ["scripts/ci/install_lint_tools.sh"]
    elif dependency in RELEASE_IDS:
        paths = ["scripts/release/install_release_security_tools.sh"]
    elif dependency in {"composer-docker-image", "plugin-check"}:
        paths = ["scripts/lib/wordpress_tooling.sh"]
    elif dependency == "plugin-update-checker-runtime":
        paths = [PUC, "docs/distribution-runtime-updater.md"]
    else:
        raise ValueError(f"Unsupported dependency: {dependency}")
    return paths + [INVENTORY]


def files_for(root, dependency):
    result = {}
    for relative in paths_for(dependency):
        path = root / relative
        files = sorted(path.rglob("*")) if path.is_dir() else [path]
        for file in files:
            if file.is_symlink():
                raise ValueError(f"Symlinks are not allowed: {file}")
            if file.is_file():
                result[file.relative_to(root).as_posix()] = file.read_bytes()
    return result


def stage(root, target, dependency):
    for relative in paths_for(dependency):
        source, destination = root / relative, target / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        if source.is_dir():
            shutil.copytree(source, destination)
        else:
            shutil.copy2(source, destination)


def sync_inventory(root, dependency, old, new):
    path = root / INVENTORY
    data = json.loads(path.read_text())
    entries = [entry for entry in data["dependencies"] if entry["id"] == dependency]
    if len(entries) != 1:
        raise ValueError("Dependency inventory must contain exactly one matching entry")
    pin = entries[0]["pin"]
    pin["pattern"] = pin["pattern"].replace(old, new)
    if pin["pattern"] not in (root / pin["file"]).read_text():
        raise ValueError("Updated source pin and dependency inventory disagree")
    path.write_text(json.dumps(data, indent=2) + "\n")


def commit_stage(root, source, dependency):
    """Swap prepared surfaces; roll back all previous swaps on any failure."""
    pending, applied = [], []
    try:
        for relative in paths_for(dependency):
            destination = root / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            temporary = Path(tempfile.mkdtemp(prefix=".dependency-", dir=destination.parent))
            replacement, backup = temporary / "new", temporary / "old"
            candidate = source / relative
            if candidate.is_dir():
                shutil.copytree(candidate, replacement)
            else:
                shutil.copy2(candidate, replacement)
            pending.append(temporary)
            os.replace(destination, backup)
            applied.append((destination, backup))
            os.replace(replacement, destination)
    except BaseException:
        for destination, backup in reversed(applied):
            if destination.is_dir():
                shutil.rmtree(destination)
            elif destination.exists():
                destination.unlink()
            os.replace(backup, destination)
        raise
    finally:
        for temporary in pending:
            shutil.rmtree(temporary)


def extract_archive(archive, target, prefix):
    """Extract regular files only, never links, devices or paths outside the root."""
    with tarfile.open(archive) as source:
        members = source.getmembers()
        if len(members) > 10000 or sum(member.size for member in members) > 50_000_000:
            raise ValueError("Dependency archive exceeds size limits")
        for member in members:
            path = PurePosixPath(member.name)
            if path.is_absolute() or ".." in path.parts or not path.parts or path.parts[0] != prefix:
                raise ValueError(f"Unsafe archive path: {member.name}")
            if not (member.isfile() or member.isdir()):
                raise ValueError(f"Unsupported archive member: {member.name}")
        for member in members:
            destination = target / member.name
            if member.isdir():
                destination.mkdir(parents=True, exist_ok=True)
            else:
                destination.parent.mkdir(parents=True, exist_ok=True)
                with source.extractfile(member) as content:
                    destination.write_bytes(content.read())


def replace_hashes(path, variable, hashes):
    platforms = ("Linux:x86_64", "Darwin:x86_64", "Darwin:arm64")
    if len(hashes) != len(platforms) or any(not re.fullmatch(r"[a-f0-9]{64}", sha) for sha in hashes):
        raise ValueError("Expected one SHA256 for each supported platform")
    text = path.read_text()
    for platform, sha in zip(platforms, hashes):
        pattern = rf"({re.escape(platform)}\)\n(?:(?!\n\s*;;)[\s\S])*?\n\s*{re.escape(variable)}=)'[a-f0-9]{{64}}'"
        text, count = re.subn(pattern, lambda match: match[1] + "'" + sha + "'", text)
        if count != 1:
            raise ValueError(f"Expected exactly one {variable} pin for {platform}, found {count}")
    path.write_text(text)


def read_outputs(path):
    values = {}
    for line in path.read_text().splitlines():
        key, separator, value = line.partition("=")
        if not separator or key in values:
            raise ValueError("Invalid or duplicate candidate output")
        values[key] = value
    return values


def bundle(root, output_path, artifact, dependency):
    metadata = read_outputs(output_path)
    if metadata.get("dependency_id") != dependency:
        raise ValueError("Candidate dependency does not match its matrix entry")
    payload = {
        "schema_version": 1,
        "dependency_id": dependency,
        "base_sha": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip(),
        "update_needed": metadata.get("update_needed") == "true",
    }
    if payload["update_needed"]:
        payload.update({key: metadata[key] for key in ("branch_name", "pr_title", "commit_message", "from_version", "to_version")})
        payload["body"] = Path(metadata["pr_body_file"]).read_text()
        payload["files"] = {name: base64.b64encode(data).decode("ascii") for name, data in files_for(root, dependency).items()}
    artifact.parent.mkdir(parents=True, exist_ok=True)
    artifact.write_text(json.dumps(payload, sort_keys=True) + "\n")
    print(f"Prepared {dependency} candidate SHA256 {hashlib.sha256(artifact.read_bytes()).hexdigest()}")


def apply_bundle(root, artifact, dependency, output_path, expected_digest):
    if artifact.stat().st_size > 75_000_000:
        raise ValueError("Candidate artifact exceeds size limit")
    if not re.fullmatch(r"[a-f0-9]{64}", expected_digest) or hashlib.sha256(artifact.read_bytes()).hexdigest() != expected_digest:
        raise ValueError("Candidate digest does not match trusted preparation output")
    payload = json.loads(artifact.read_text())
    if payload.get("schema_version") != 1 or payload.get("dependency_id") != dependency:
        raise ValueError("Invalid candidate artifact identity")
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
    if payload.get("base_sha") != head:
        raise ValueError("Candidate was prepared from a different commit")
    if type(payload.get("update_needed")) is not bool:
        raise ValueError("Invalid update_needed value")
    if not payload["update_needed"]:
        output_path.write_text("update_needed=false\n")
        return
    for key in ("branch_name", "pr_title", "commit_message", "from_version", "to_version"):
        value = payload.get(key)
        if not isinstance(value, str) or not value or len(value) > 500 or any(ord(char) < 32 for char in value):
            raise ValueError(f"Invalid candidate metadata: {key}")
    if not re.fullmatch(r"chore/update-[a-z0-9.-]+", payload["branch_name"]):
        raise ValueError("Invalid update branch")
    if not isinstance(payload.get("body"), str) or len(payload["body"]) > 100_000:
        raise ValueError("Invalid PR body")
    allowed = paths_for(dependency)
    with tempfile.TemporaryDirectory(prefix="dependency-apply-") as temporary:
        candidate = Path(temporary)
        stage(root, candidate, dependency)
        if dependency == "plugin-update-checker-runtime":
            shutil.rmtree(candidate / PUC)
        files = payload.get("files")
        if not isinstance(files, dict) or not files or len(files) > 10000:
            raise ValueError("Invalid candidate files")
        for name, content in files.items():
            path = PurePosixPath(name)
            if path.is_absolute() or ".." in path.parts or path.as_posix() != name or not any(name == item or (item == PUC and name.startswith(PUC + "/")) for item in allowed):
                raise ValueError(f"Candidate path is outside the dependency allowlist: {name}")
            destination = candidate / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(base64.b64decode(content, validate=True))
        for item in allowed:
            if item != PUC and item not in files:
                raise ValueError(f"Candidate omitted required surface: {item}")
        sync_inventory(candidate, dependency, payload["to_version"], payload["to_version"])
        commit_stage(root, candidate, dependency)
    body = artifact.parent / "pr-body.md"
    body.write_text(payload["body"])
    outputs = {key: payload[key] for key in ("branch_name", "pr_title", "commit_message")}
    outputs.update(update_needed="true", pr_body_file=str(body.resolve()), git_add_paths=",".join(allowed))
    output_path.write_text("".join(f"{key}={value}\n" for key, value in outputs.items()))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("stage", "commit", "inventory", "extract", "hashes", "bundle", "apply"))
    parser.add_argument("args", nargs="+")
    args = parser.parse_args()
    values = args.args
    if args.command == "stage":
        stage(Path(values[0]), Path(values[1]), values[2])
    elif args.command == "commit":
        commit_stage(Path(values[0]), Path(values[1]), values[2])
    elif args.command == "inventory":
        sync_inventory(Path(values[0]), values[1], values[2], values[3])
    elif args.command == "extract":
        extract_archive(Path(values[0]), Path(values[1]), values[2])
    elif args.command == "hashes":
        replace_hashes(Path(values[0]), values[1], values[2:])
    elif args.command == "bundle":
        bundle(Path(values[0]), Path(values[1]), Path(values[2]), values[3])
    elif args.command == "apply":
        apply_bundle(Path(values[0]), Path(values[1]), values[2], Path(values[3]), values[4])


if __name__ == "__main__":
    main()
