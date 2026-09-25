#!/usr/bin/env python3
"""Compare package contents: exit 0 for equal, 1 for different, 2 for errors."""

import filecmp
import os
import sys


def same_contents(left, right):
    """Return equality; filesystem failures must propagate to the caller."""
    with os.scandir(left) as entries:
        left_entries = {entry.name: entry for entry in entries if entry.name != '.svn'}
    with os.scandir(right) as entries:
        right_entries = {entry.name: entry for entry in entries if entry.name != '.svn'}
    if left_entries.keys() != right_entries.keys():
        return False
    for name, source in left_entries.items():
        target = right_entries[name]
        if source.is_symlink() or target.is_symlink():
            if not (source.is_symlink() and target.is_symlink()
                    and os.readlink(source.path) == os.readlink(target.path)):
                return False
        elif source.is_dir(follow_symlinks=False) and target.is_dir(follow_symlinks=False):
            if not same_contents(source.path, target.path):
                return False
        elif source.is_file(follow_symlinks=False) and target.is_file(follow_symlinks=False):
            if not filecmp.cmp(source.path, target.path, shallow=False):
                return False
        elif source.is_dir(follow_symlinks=False) or target.is_dir(follow_symlinks=False):
            return False
        else:
            raise OSError(f'Unsupported package entry: {name}')
    return True


if __name__ == '__main__':
    if len(sys.argv) != 3:
        print('Usage: compare_package_trees.py <source-directory> <target-directory>', file=sys.stderr)
        raise SystemExit(2)
    try:
        result = 0 if same_contents(sys.argv[1], sys.argv[2]) else 1
    except (OSError, RecursionError) as error:
        print(f'Package comparison failed: {error}', file=sys.stderr)
        result = 2
    raise SystemExit(result)
