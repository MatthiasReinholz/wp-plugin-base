#!/usr/bin/env python3
"""Safely extract a verified release while retaining the executable distinction."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib"))
from package_generation import PackageError, extract  # noqa: E402

if __name__ == "__main__":
    try:
        extract(*sys.argv[1:])
    except (OSError, ValueError, PackageError) as error:
        raise SystemExit(str(error)) from error
