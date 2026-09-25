#!/usr/bin/env python3
"""Extract a verified plugin payload under its configured root, rejecting unsafe paths."""

import pathlib
import stat
import sys
import zipfile

archive, destination, slug = sys.argv[1:]
with zipfile.ZipFile(archive) as source:
    if not source.infolist():
        raise SystemExit("Published plugin archive is empty.")
    entries = source.infolist()
    if len(entries) > 100000 or sum(entry.file_size for entry in entries) > 1_000_000_000:
        raise SystemExit("Published plugin archive exceeds safe extraction limits.")
    seen = set()
    for entry in entries:
        path = pathlib.PurePosixPath(entry.filename)
        if path in seen:
            raise SystemExit("Published plugin archive contains duplicate paths.")
        seen.add(path)
        if (path.is_absolute() or ".." in path.parts or "\\" in entry.filename
                or not path.parts or path.parts[0] != slug
                or stat.S_ISLNK(entry.external_attr >> 16)):
            raise SystemExit("Published plugin archive contains an unsafe path.")
    source.extractall(destination)
