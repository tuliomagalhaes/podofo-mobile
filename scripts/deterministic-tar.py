#!/usr/bin/env python3
"""Create a byte-stable gzip tarball from regular project files."""
import gzip
import os
import sys
import tarfile

if len(sys.argv) < 4:
    raise SystemExit('usage: deterministic-tar.py OUTPUT ROOT PATH...')
output, root, *inputs = sys.argv[1:]
root = os.path.realpath(root)
paths = []
for relative in inputs:
    candidate = os.path.realpath(os.path.join(root, relative))
    if candidate != root and not candidate.startswith(root + os.sep):
        raise SystemExit(f'input escapes root: {relative}')
    if os.path.isfile(candidate):
        paths.append(candidate)
    elif os.path.isdir(candidate):
        for base, directories, files in os.walk(candidate):
            directories.sort()
            for name in sorted(files):
                paths.append(os.path.join(base, name))
    else:
        raise SystemExit(f'missing input: {relative}')
with open(output, 'wb') as stream:
    with gzip.GzipFile(filename='', mode='wb', fileobj=stream, mtime=0) as compressed:
        with tarfile.open(mode='w', fileobj=compressed, format=tarfile.PAX_FORMAT) as archive:
            for path in sorted(paths):
                if os.path.islink(path) or not os.path.isfile(path):
                    raise SystemExit(f'only regular non-symlink files are allowed: {path}')
                info = archive.gettarinfo(path, arcname=os.path.relpath(path, root))
                info.uid = info.gid = 0
                info.uname = info.gname = ''
                info.mtime = 0
                info.pax_headers = {}
                with open(path, 'rb') as source:
                    archive.addfile(info, source)
