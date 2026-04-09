#!/usr/bin/env python3

import hashlib
import os
import sys
from pathlib import Path

TERMINATOR = b"END\n"


def write_hash_file(filename: Path, values: dict[bytes, bytes]) -> None:
    tmp_filename = filename.with_suffix(filename.suffix + ".tmp")

    with open(tmp_filename, "xb") as handle:
        for key, value in values.items():
            handle.write(b"K " + str(len(key)).encode("utf-8") + b"\n")
            handle.write(key + b"\n")
            handle.write(b"V " + str(len(value)).encode("utf-8") + b"\n")
            handle.write(value + b"\n")
        handle.write(TERMINATOR)

    os.chmod(tmp_filename, 0o600)
    os.replace(tmp_filename, filename)


def main() -> int:
    if len(sys.argv) != 4:
        print("Usage: write_svn_simple_auth.py <config-dir> <realm> <username>", file=sys.stderr)
        return 1

    config_dir = Path(sys.argv[1])
    config_dir.mkdir(parents=True, exist_ok=True)
    os.chmod(config_dir, 0o700)
    realm = sys.argv[2]
    username = sys.argv[3]
    password = os.environ.get("SVN_PASSWORD")
    if not password:
        print("SVN_PASSWORD is required in the environment.", file=sys.stderr)
        return 1

    auth_dir = config_dir / "auth" / "svn.simple"
    auth_dir.mkdir(parents=True, exist_ok=True)
    os.chmod(auth_dir, 0o700)

    digest = hashlib.md5(realm.encode("utf-8")).hexdigest()
    auth_file = auth_dir / digest

    payload = {
        b"svn:realmstring": realm.encode("utf-8"),
        b"username": username.encode("utf-8"),
        b"passtype": b"simple",
        b"password": password.encode("utf-8"),
    }

    write_hash_file(auth_file, payload)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
