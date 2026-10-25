#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Anand Kumar Anbazhagan
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Build release files into dist/:
#   glossy-dock-<version>.plasmoid             the widget (install with kpackagetool6 or "Get New Widgets")
#   glossy-glass-plasma-style-<version>.tar.gz  the Plasma style
#   glossy-dock-panel-template-<version>.tar.gz the "Glossy Dock" panel template
#   glossy-dock-<version>.tar.gz                everything, with install.sh
#   SHA256SUMS

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DIST="$ROOT/dist"
version=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["KPlugin"]["Version"])' "$ROOT/plasmoid/metadata.json")

rm -rf "$DIST"
mkdir -p "$DIST"

python3 - "$ROOT" "$DIST" "$version" <<'EOF'
import os
import sys
import tarfile
import zipfile

root, dist, version = sys.argv[1:4]

# Fixed timestamps and ordering so the same sources always give the same archives.
EPOCH = 315532800  # 1980-01-01, the earliest time zip can store


def files_under(base):
    for dirpath, dirnames, filenames in os.walk(base):
        dirnames.sort()
        for name in sorted(filenames):
            path = os.path.join(dirpath, name)
            yield path, os.path.relpath(path, base)


def zip_dir(base, out):
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for path, rel in files_under(base):
            info = zipfile.ZipInfo(rel, date_time=(1980, 1, 1, 0, 0, 0))
            info.external_attr = (0o755 if os.access(path, os.X_OK) else 0o644) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            with open(path, "rb") as f:
                z.writestr(info, f.read())


def tar_paths(out, entries):
    def clean(info):
        info.uid = info.gid = 0
        info.uname = info.gname = ""
        info.mtime = EPOCH
        return info

    with tarfile.open(out, "w:gz") as t:
        for src, arcname in entries:
            if os.path.isdir(src):
                for path, rel in files_under(src):
                    t.add(path, os.path.join(arcname, rel), filter=clean)
            else:
                t.add(src, arcname, filter=clean)


# The .plasmoid is a zip with metadata.json at its root.
zip_dir(os.path.join(root, "plasmoid"), os.path.join(dist, f"glossy-dock-{version}.plasmoid"))
tar_paths(os.path.join(dist, f"glossy-glass-plasma-style-{version}.tar.gz"),
          [(os.path.join(root, "plasma-style", "glossy-glass"), "glossy-glass")])
tar_paths(os.path.join(dist, f"glossy-dock-panel-template-{version}.tar.gz"),
          [(os.path.join(root, "panel-template"), "io.github.akanbaz.glossydock.panel")])

top = f"glossy-dock-{version}"
tar_paths(os.path.join(dist, f"{top}.tar.gz"),
          [(os.path.join(root, p), os.path.join(top, p)) for p in
           ("plasmoid", "plasma-style", "panel-template", "install.sh", "uninstall.sh", "README.md", "LICENSE")])
EOF

(cd "$DIST" && sha256sum -- * > SHA256SUMS)
echo "Built $version:"
ls -1 "$DIST"
