#!/usr/bin/env python3
"""Cooperating package generations, complete ZIP verification and safe installation.

The lock serializes application builds in one checkout. Retained generations are
never reused or automatically deleted, so a consumer's captured paths stay stable.
This is ordinary-error recovery, not protection against a hostile same-user process
or a power-loss durability protocol.
"""

import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import zipfile


class PackageError(Exception):
    """An unsafe or incomplete package operation."""


def safe_path(root, path, kind=None):
    root, path = Path(root).resolve(), Path(path).absolute()
    try:
        relative = path.relative_to(root)
    except ValueError as error:
        raise PackageError(f"Package output escapes project: {path}") from error
    if not relative.parts or ".." in relative.parts:
        raise PackageError(f"Invalid package output: {path}")
    current = root
    for index, part in enumerate(relative.parts):
        current /= part
        try:
            mode = current.lstat().st_mode
        except FileNotFoundError:
            continue
        if stat.S_ISLNK(mode):
            raise PackageError(f"Package output must not be a symbolic link: {current}")
        expected = "directory" if index < len(relative.parts) - 1 else kind
        if expected == "directory" and not stat.S_ISDIR(mode):
            raise PackageError(f"Package output is not a directory: {current}")
        if expected == "file" and not stat.S_ISREG(mode):
            raise PackageError(f"Package output is not a regular file: {current}")
    return path


def check_outputs(root, slug, filename):
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]*", slug):
        raise PackageError("PLUGIN_SLUG must be a simple lowercase plugin slug.")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*\.zip", filename):
        raise PackageError("ZIP_FILE must be a simple zip filename.")
    if any(character in str(Path(root).resolve()) for character in ("\n", "\r")):
        raise PackageError("Package project paths cannot contain newlines.")
    dist = Path(root).resolve() / "dist"
    for path in (dist, dist / "package", dist / "package" / slug, dist / ".generations"):
        safe_path(root, path, "directory")
    for name in (filename, filename + ".sbom.cdx.json", filename + ".sigstore.json", "package-generation.json", ".package.lock"):
        safe_path(root, dist / name, "file")


def digest(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest() if hasattr(hashlib, "file_digest") else hash_stream(stream)


def hash_stream(stream):
    result = hashlib.sha256()
    for data in iter(lambda: stream.read(1024 * 1024), b""):
        result.update(data)
    return result.hexdigest()


def canonical_mode(mode):
    if stat.S_ISDIR(mode):
        return 0o755
    if stat.S_ISREG(mode):
        return 0o755 if mode & 0o111 else 0o644
    raise PackageError("Packages may only contain directories and regular files.")


def tree_manifest(stage, normalize=False):
    stage = Path(stage)
    result = {}
    for path in [stage, *sorted(stage.rglob("*"))]:
        relative = path.relative_to(stage.parent).as_posix()
        if any(ord(char) < 32 or char == "\\" for char in relative):
            raise PackageError(f"Unsupported package path: {relative!r}")
        metadata = path.lstat()
        mode = canonical_mode(metadata.st_mode)
        directory = stat.S_ISDIR(metadata.st_mode)
        if normalize:
            path.chmod(mode)
            os.utime(path, (946684800, 946684800), follow_symlinks=False)
        elif stat.S_IMODE(metadata.st_mode) != mode:
            raise PackageError(f"Noncanonical package permissions: {relative}")
        result[relative + ("/" if directory else "")] = {
            "mode": mode, "sha256": None if directory else digest(path)
        }
    return result


def archive_manifest(archive, slug):
    result = {}
    with zipfile.ZipFile(archive) as source:
        entries = source.infolist()
        if not entries or len(entries) > 100000 or sum(item.file_size for item in entries) > 1_000_000_000:
            raise PackageError("Published plugin archive is empty or exceeds safe extraction limits.")
        canonical_names = set()
        for entry in entries:
            path = PurePosixPath(entry.filename)
            canonical = path.as_posix()
            if (entry.orig_filename != entry.filename
                    or not path.parts or path.parts[0] != slug or path.is_absolute() or ".." in path.parts
                    or entry.filename.rstrip("/") != canonical or "\\" in entry.filename
                    or any(ord(char) < 32 for char in entry.filename)):
                raise PackageError("Published plugin archive contains an unsafe path.")
            if (len(path.parts) == 1 and not entry.is_dir()) or (entry.is_dir() and entry.file_size):
                raise PackageError("Published plugin archive has an invalid plugin root or directory payload.")
            if canonical in canonical_names:
                raise PackageError("Published plugin archive contains duplicate paths.")
            canonical_names.add(canonical)
            source_mode = entry.external_attr >> 16
            entry_type = stat.S_IFMT(source_mode)
            directory = entry.is_dir()
            if entry_type not in (0, stat.S_IFDIR if directory else stat.S_IFREG):
                raise PackageError("Published plugin archive contains an unsupported entry type.")
            # Old signed releases may have DOS attributes or arbitrary umask bits.
            # Recover only safe rw/rx permissions; never restore special bits.
            mode = 0o755 if directory or source_mode & 0o111 else 0o644
            with source.open(entry) as stream:
                checksum = hash_stream(stream)  # Reads every byte, checking decompression and CRC.
            result[entry.filename] = {"mode": mode, "sha256": None if directory else checksum}
        # Reject file/parent collisions even if the offending parent follows its child.
        regular_names = {name for name in result if not name.endswith("/")}
        for name in result:
            if any(parent.as_posix() in regular_names for parent in PurePosixPath(name).parents):
                raise PackageError("Published plugin archive contains a file/directory collision.")
    return result


def verify(archive, stage):
    expected = tree_manifest(stage)
    actual = archive_manifest(archive, Path(stage).name)
    if actual != expected:
        raise PackageError("Archive membership, bytes or permissions do not match the complete staged plugin.")
    # Verification above canonicalizes historical modes for recovery; new packages
    # must already encode exactly the policy, without special bits.
    with zipfile.ZipFile(archive) as source:
        for entry in source.infolist():
            if stat.S_IMODE(entry.external_attr >> 16) != expected[entry.filename]["mode"]:
                raise PackageError("Archive encodes noncanonical package permissions.")
    return expected


def extract(archive, destination, slug):
    manifest = archive_manifest(archive, slug)
    destination = Path(destination)
    if destination.exists() or destination.is_symlink():
        raise PackageError("Extraction destination must not exist.")
    destination.mkdir(mode=0o700, parents=True)
    with zipfile.ZipFile(archive) as source:
        for name, metadata in manifest.items():
            target = destination.joinpath(*PurePosixPath(name).parts)
            target.parent.mkdir(mode=0o755, parents=True, exist_ok=True)
            if name.endswith("/"):
                target.mkdir(mode=0o755, exist_ok=True)
            else:
                with source.open(name) as src, target.open("xb") as dst:
                    shutil.copyfileobj(src, dst)
            target.chmod(metadata["mode"])
    # Implicit directory entries also receive canonical permissions under umask 077.
    for directory in destination.rglob("*"):
        if directory.is_dir():
            directory.chmod(0o755)


def lock(root, command):
    root = Path(root).resolve()
    dist = safe_path(root, root / "dist", "directory")
    dist.mkdir(mode=0o755, exist_ok=True)
    lock_path = safe_path(root, dist / ".package.lock", "file")
    descriptor = os.open(lock_path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        fcntl.flock(descriptor, fcntl.LOCK_EX)
        environment = dict(os.environ, WP_PLUGIN_BASE_PACKAGE_LOCK_ROOT=str(root), WP_PLUGIN_BASE_PACKAGE_LOCK_FD=str(descriptor))
        return subprocess.call(command, env=environment, pass_fds=(descriptor,))
    finally:
        os.close(descriptor)


def held(root):
    try:
        root = Path(root).resolve()
        descriptor = int(os.environ.get("WP_PLUGIN_BASE_PACKAGE_LOCK_FD", "-1"))
        metadata = os.fstat(descriptor)
        target = (root / "dist/.package.lock").lstat()
        return (os.environ.get("WP_PLUGIN_BASE_PACKAGE_LOCK_ROOT") == str(root)
                and stat.S_ISREG(target.st_mode)
                and (metadata.st_dev, metadata.st_ino) == (target.st_dev, target.st_ino))
    except (OSError, ValueError):
        return False


def create(root, slug, filename):
    check_outputs(root, slug, filename)
    parent = Path(root).resolve() / "dist/.generations"
    parent.mkdir(mode=0o755, exist_ok=True)
    return Path(tempfile.mkdtemp(prefix="generation-", dir=parent))


def publish(root, generation, slug, filename, recovered=False):
    root, generation = Path(root).resolve(), Path(generation).resolve()
    check_outputs(root, slug, filename)
    if generation.parent != root / "dist/.generations":
        raise PackageError("Package generation is not in this project's generation store.")
    stage, archive = generation / "package" / slug, generation / filename
    if recovered:
        manifest = tree_manifest(stage)
        actual = archive_manifest(archive, slug)
        # Some historical ZIPs omit explicit directory records.
        files = lambda tree: {name: item for name, item in tree.items() if not name.endswith("/")}
        if files(manifest) != files(actual):
            raise PackageError("Recovered archive bytes do not match the extracted plugin.")
    else:
        manifest = verify(archive, stage)
    # Container-based validators must traverse the completed generation.
    generation.chmod(0o755)
    stage.parent.chmod(0o755)
    record = {"schema_version": 1, "package_dir": str(stage), "zip_path": str(archive),
              "sbom_path": str(archive) + ".sbom.cdx.json", "signature_path": str(archive) + ".sigstore.json",
              "descriptor_path": str(generation / "generation.json"), "sha256": digest(archive), "entries": manifest}
    (generation / "generation.json").write_text(json.dumps(record, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    # Compatibility output replacement is transactional for ordinary exceptions.
    # Consumers use generation.json paths, never this separately-renamed pair.
    transaction = Path(tempfile.mkdtemp(prefix=".package-install-", dir=root / "dist"))
    replacements = [(generation / "package", root / "dist/package"), (archive, root / "dist" / filename)]
    for suffix in (".sbom.cdx.json", ".sigstore.json"):
        source = Path(str(archive) + suffix)
        replacements.append((source if source.is_file() else None, root / "dist" / (filename + suffix)))
    replacements.append((generation / "generation.json", root / "dist/package-generation.json"))
    applied = []
    cleanup_transaction = True
    try:
        for index, (source, destination) in enumerate(replacements):
            candidate, backup = transaction / f"new-{index}", transaction / f"old-{index}"
            if source is not None:
                if source.is_dir():
                    shutil.copytree(source, candidate)
                else:
                    shutil.copy2(source, candidate)
            safe_path(root, destination, "directory" if index == 0 else "file")
            had_previous = destination.exists()
            if had_previous:
                destination.rename(backup)
            applied.append((destination, backup, had_previous))
            if source is not None:
                candidate.rename(destination)
        result(record, os.environ.get("WP_PLUGIN_BASE_PACKAGE_RESULT_FILE"))
        return record
    except BaseException:
        try:
            for destination, backup, had_previous in reversed(applied):
                if destination.is_dir():
                    shutil.rmtree(destination)
                elif destination.exists():
                    destination.unlink()
                if had_previous:
                    backup.rename(destination)
        except OSError as rollback_error:
            cleanup_transaction = False
            raise PackageError(f"Package rollback failed; preserved recovery files at {transaction}: {rollback_error}") from rollback_error
        raise
    finally:
        if cleanup_transaction:
            shutil.rmtree(transaction)


def result(record, output):
    if output:
        path = Path(output)
        descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_APPEND | os.O_NOFOLLOW, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            for key in ("package_dir", "zip_path", "sbom_path", "signature_path", "descriptor_path", "sha256"):
                value = record[key]
                if "\n" in value or "\r" in value:
                    raise PackageError("Package output values cannot contain newlines.")
                stream.write(f"{key}={value}\n")


RESULT_FIELDS = ("package_dir", "zip_path", "sbom_path", "signature_path", "descriptor_path", "sha256")


def unique_keys(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise PackageError(f"Duplicate package descriptor key: {key}")
        result[key] = value
    return result


def check_record(descriptor):
    descriptor = Path(descriptor).absolute()
    generation = descriptor.parent
    if (descriptor.name != "generation.json" or not generation.name.startswith("generation-")
            or generation.parent.name != ".generations" or generation.parent.parent.name != "dist"):
        raise PackageError("Invalid captured generation descriptor path.")
    root = generation.parent.parent.parent
    safe_path(root, descriptor, "file")
    record = json.loads(descriptor.read_text(encoding="utf-8"), object_pairs_hook=unique_keys)
    if (not isinstance(record, dict) or set(record) != set(RESULT_FIELDS) | {"schema_version", "entries"}
            or type(record["schema_version"]) is not int or record["schema_version"] != 1
            or any(not isinstance(record[field], str) or "\n" in record[field] or "\r" in record[field] for field in RESULT_FIELDS)):
        raise PackageError("Invalid captured generation descriptor fields.")
    archive = Path(record["zip_path"])
    stage = Path(record["package_dir"])
    check_outputs(root, stage.name, archive.name)
    expected = {"package_dir": str(generation / "package" / stage.name), "zip_path": str(generation / archive.name),
                "sbom_path": str(generation / archive.name) + ".sbom.cdx.json",
                "signature_path": str(generation / archive.name) + ".sigstore.json", "descriptor_path": str(descriptor)}
    if any(record[key] != value for key, value in expected.items()) or not re.fullmatch(r"[0-9a-f]{64}", record["sha256"]):
        raise PackageError("Captured generation paths do not match its descriptor location.")
    safe_path(root, stage, "directory")
    safe_path(root, archive, "file")
    if digest(archive) != record["sha256"] or tree_manifest(stage) != record["entries"]:
        raise PackageError("Captured package generation changed after verification.")
    return record


def validate_result(path):
    raw = Path(path).read_bytes()
    if b"\r" in raw:
        raise PackageError("Package result contains an unsafe carriage return.")
    fields = {}
    for line in raw.decode("utf-8").splitlines():
        if "=" not in line:
            raise PackageError("Invalid package result record.")
        key, value = line.split("=", 1)
        if key not in RESULT_FIELDS or key in fields:
            raise PackageError("Package result contains duplicate or unexpected fields.")
        fields[key] = value
    if set(fields) != set(RESULT_FIELDS):
        raise PackageError("Package generation result must contain all six fields.")
    record = check_record(fields["descriptor_path"])
    if any(fields[key] != record[key] for key in RESULT_FIELDS):
        raise PackageError("Package result does not match its verified generation descriptor.")
    return fields


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("guard", "held", "lock", "create", "normalize", "verify", "extract", "publish", "recover", "check", "discard", "validate-result", "assert-input", "assert-assets"))
    parser.add_argument("args", nargs=argparse.REMAINDER)
    options = parser.parse_args()
    action, args = options.action, options.args
    if action == "guard":
        check_outputs(*args)
    elif action == "held":
        return 0 if held(*args) else 1
    elif action == "lock":
        return lock(args[0], args[1:])
    elif action == "create":
        print(create(*args))
    elif action == "discard":
        root, generation = Path(args[0]).resolve(), Path(args[1]).absolute()
        if generation.parent != root / "dist/.generations" or not generation.name.startswith("generation-"):
            raise PackageError("Invalid package generation cleanup path.")
        safe_path(root, generation, "directory")
        if generation.exists() and not (generation / "generation.json").exists():
            shutil.rmtree(generation)
    elif action == "normalize":
        tree_manifest(args[0], normalize=True)
    elif action == "verify":
        verify(*args)
    elif action == "extract":
        extract(*args)
    elif action in ("publish", "recover"):
        publish(*args, recovered=action == "recover")
    elif action == "check":
        check_record(args[0])
    elif action == "assert-input":
        record = check_record(args[0])
        if args[1] not in RESULT_FIELDS or args[2] != record[args[1]]:
            raise PackageError("Consumer input does not match its captured package generation.")
    elif action == "assert-assets":
        record = check_record(args[0])
        expected = {record[key] for key in ("zip_path", "sbom_path", "signature_path")}
        if len(args[1:]) != 3 or set(args[1:]) != expected:
            raise PackageError("Publication assets must be exactly the captured ZIP, SBOM and signature.")
    elif action == "validate-result":
        for key, value in validate_result(args[0]).items():
            print(f"{key}={value}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, PackageError, zipfile.BadZipFile, RuntimeError) as error:
        print(f"Package generation failed: {error}", file=sys.stderr)
        sys.exit(1)
