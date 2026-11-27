#!/usr/bin/env python3
"""Prints one sha256 for a folder of source files, so a download can be checked before anything in it runs.

usage: python3 -I scripts/tree_sha256.py <folder>

Hashes every file under the folder (a .git folder is skipped), as it is on disk, in sorted path order: for each file
a line "<path> <kind> <sha256 of its bytes>" (kind is "file", "exec" or "link"; a link is hashed by its target and
never followed). The result is the sha256 of those lines. A fresh git checkout and the same files unpacked from the
sources bundle give the same hash. Run it with -I and from outside the folder, so nothing in it is imported.
make_ipa.sh compares it with the pins in ports/ios/pins.sh.
"""
import hashlib
import os
import stat
import sys


def tree_sha256(folder):
    entries = []
    for directory, subfolders, files in os.walk(folder):
        subfolders[:] = [name for name in subfolders if name != ".git" or directory != folder]
        # os.walk lists links to folders as folders; hash them as links and do not walk into them
        for name in list(subfolders):
            if os.path.islink(os.path.join(directory, name)):
                subfolders.remove(name)
                files.append(name)
        for name in files:
            full = os.path.join(directory, name)
            entries.append((os.path.relpath(full, folder).replace(os.sep, "/"), full))
    if not entries:
        raise SystemExit(f"no files in {folder}")
    total = hashlib.sha256()
    for path, full in sorted(entries):
        mode = os.lstat(full).st_mode
        if stat.S_ISLNK(mode):
            kind, data = "link", os.readlink(full).encode("utf-8")
        else:
            kind = "exec" if mode & stat.S_IXUSR else "file"
            with open(full, "rb") as handle:
                data = handle.read()
        total.update(f"{path} {kind} {hashlib.sha256(data).hexdigest()}\n".encode("utf-8"))
    return total.hexdigest()


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    print(tree_sha256(sys.argv[1]))
