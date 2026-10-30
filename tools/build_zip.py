#!/usr/bin/env python3
"""Build the module zip into docs/assets/global-hfr.zip without extra dependencies."""
import os
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'module')
OUT = os.path.join(ROOT, 'docs', 'assets', 'global-hfr.zip')

os.makedirs(os.path.dirname(OUT), exist_ok=True)
if os.path.exists(OUT):
    os.remove(OUT)

count = 0
with zipfile.ZipFile(OUT, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for base, dirs, files in os.walk(SRC):
        dirs.sort()
        for name in sorted(files):
            path = os.path.join(base, name)
            rel = os.path.relpath(path, SRC).replace('\\', '/')
            mode = 0o755 if rel.endswith('.sh') else 0o644
            zi = zipfile.ZipInfo(rel, date_time=(2026, 10, 30, 22, 0, 0))
            zi.create_system = 3
            zi.external_attr = (0o100000 | mode) << 16
            zi.compress_type = zipfile.ZIP_DEFLATED
            with open(path, 'rb') as fh:
                z.writestr(zi, fh.read(), compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
            count += 1

print(f'built {OUT} ({count} files, {os.path.getsize(OUT)} bytes)')
