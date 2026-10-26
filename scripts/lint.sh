#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Anand Kumar Anbazhagan
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Checks that need no running Plasma. Tools that aren't installed are skipped with a note;
# CI installs them all. With KDE's QML modules present (a Plasma desktop, or the Arch CI
# job), QML is also type-checked against the real Plasma APIs.

set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT" || exit 1

failed=0
fail() { echo "FAIL: $*"; failed=1; }
pass() { echo "ok:   $*"; }
skip() { echo "skip: $*"; }

WIDGET_ID="io.github.akanbaz.glossydock"

# --- metadata ---------------------------------------------------------------
python3 - <<'EOF' || failed=1
import json, sys

files = {
    "plasmoid/metadata.json": ("Plasma/Applet", "io.github.akanbaz.glossydock"),
    "plasma-style/glossy-glass/metadata.json": ("Plasma/Theme", "glossy-glass"),
    "panel-template/metadata.json": ("Plasma/LayoutTemplate", "io.github.akanbaz.glossydock.panel"),
}
ok = True
versions = set()
for path, (structure, plugin_id) in files.items():
    try:
        data = json.load(open(path))
    except Exception as e:
        print(f"FAIL: {path}: {e}")
        ok = False
        continue
    kp = data.get("KPlugin", {})
    for key, want in (("KPackageStructure", structure),):
        if data.get(key) != want:
            print(f"FAIL: {path}: {key} is {data.get(key)!r}, expected {want!r}")
            ok = False
    if kp.get("Id") != plugin_id:
        print(f"FAIL: {path}: Id is {kp.get('Id')!r}, expected {plugin_id!r}")
        ok = False
    for key in ("Name", "Version", "License", "Description"):
        if not kp.get(key):
            print(f"FAIL: {path}: KPlugin.{key} is missing")
            ok = False
    versions.add(kp.get("Version"))
if len(versions) != 1:
    print(f"FAIL: package versions differ: {sorted(map(str, versions))}")
    ok = False
print("ok:   metadata (ids, structures, one version: %s)" % ", ".join(map(str, versions)) if ok else "")
sys.exit(0 if ok else 1)
EOF

# The widget id must match everywhere it is referenced.
for f in panel-template/contents/layout.js install.sh uninstall.sh; do
    grep -q "\"$WIDGET_ID\"\|'$WIDGET_ID'\|=\"$WIDGET_ID\"" "$f" || fail "$f doesn't reference $WIDGET_ID"
done
pass "widget id referenced consistently"

# --- XML: config schema and SVGs --------------------------------------------
python3 - <<'EOF' || failed=1
import glob, sys, xml.dom.minidom
ok = True
paths = ["plasmoid/contents/config/main.xml"] + glob.glob("plasma-style/**/*.svg", recursive=True)
for path in paths:
    try:
        xml.dom.minidom.parse(path)
    except Exception as e:
        print(f"FAIL: {path}: {e}")
        ok = False
if ok:
    print(f"ok:   {len(paths)} XML/SVG files are well-formed")
sys.exit(0 if ok else 1)
EOF

# Every config key the QML reads must exist in main.xml, and vice versa.
python3 - <<'EOF' || failed=1
import glob, re, sys, xml.dom.minidom
schema = {e.getAttribute("name") for e in xml.dom.minidom.parse("plasmoid/contents/config/main.xml").getElementsByTagName("entry")}
used = set()
for path in glob.glob("plasmoid/contents/ui/*.qml"):
    text = open(path).read()
    used |= set(re.findall(r"Plasmoid\.configuration\.(\w+)", text))
    used |= set(re.findall(r"\bcfg_(\w+)\b", text))
missing = sorted(used - schema)
unused = sorted(schema - used)
if missing:
    print("FAIL: config keys used but not in main.xml: " + ", ".join(missing))
if unused:
    print("FAIL: config keys in main.xml but never used: " + ", ".join(unused))
if not missing and not unused:
    print(f"ok:   config keys match main.xml ({len(schema)} keys)")
sys.exit(1 if missing or unused else 0)
EOF

# The committed SVGs must be exactly what the generator produces. (Compared in Python:
# minimal images such as archlinux:latest don't ship cmp/diff.)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
python3 tools/gen-panel-svg.py "$tmp/style" >/dev/null
python3 - "$tmp/style" <<'PY' && pass "style SVGs match tools/gen-panel-svg.py" || failed=1
import pathlib, sys
fresh = pathlib.Path(sys.argv[1])
stale = [f for f in ("widgets", "translucent/widgets", "solid/widgets", "opaque/widgets")
         if (fresh / f / "panel-background.svg").read_bytes()
         != pathlib.Path("plasma-style/glossy-glass", f, "panel-background.svg").read_bytes()]
for f in stale:
    print(f"FAIL: plasma-style/glossy-glass/{f}/panel-background.svg is out of date; run tools/gen-panel-svg.py")
sys.exit(1 if stale else 0)
PY

# --- shell --------------------------------------------------------------------
shell_files=(install.sh uninstall.sh scripts/*.sh plasmoid/contents/code/actions.sh)
for f in "${shell_files[@]}"; do
    case "$(head -1 "$f")" in
    *bash*) bash -n "$f" || fail "$f: syntax" ;;
    *) sh -n "$f" || fail "$f: syntax" ;;
    esac
done
pass "shell syntax"
if command -v shellcheck >/dev/null 2>&1; then
    shellcheck -S warning "${shell_files[@]}" && pass "shellcheck" || fail "shellcheck"
else
    skip "shellcheck not installed"
fi

# actions.sh must read a launcher given as a percent-encoded file:// URL (a folder with a
# space and a non-ASCII name), using plain `sh` (dash on Debian/Ubuntu, as in CI).
actdir="$tmp/My Apps é"
mkdir -p "$actdir"
printf '[Desktop Entry]\nType=Application\nName=Test\nExec=true\nActions=first;second;\n\n[Desktop Action first]\nName=First action\nExec=true\n\n[Desktop Action second]\nName=Second action\nIcon=document-new\nExec=true\n' >"$actdir/test.desktop"
encoded=$(python3 -c 'import sys, urllib.parse; print("file://" + urllib.parse.quote(sys.argv[1]))' "$actdir/test.desktop")
listed=$(sh plasmoid/contents/code/actions.sh list "$encoded" | cut -f1,2 | tr '\t\n' ':;')
if [[ "$listed" == "first:First action;second:Second action;" ]]; then
    pass "actions.sh lists actions from a percent-encoded file:// launcher"
else
    fail "actions.sh on $encoded listed [$listed]"
fi

# actions.sh must stay quiet and succeed on bad input.
out=$(sh plasmoid/contents/code/actions.sh list applications:does-not-exist.desktop; sh plasmoid/contents/code/actions.sh list "")
if [[ $? -eq 0 && -z "$out" ]]; then pass "actions.sh handles missing launchers"; else fail "actions.sh on missing launcher"; fi

# --- QML ----------------------------------------------------------------------
qml_files=(plasmoid/contents/ui/*.qml plasmoid/contents/config/*.qml)

# Qt 6 tools only: a plain "qmlformat" on PATH may be Qt 5's, which rejects Qt 6 syntax.
qt6_tool() {
    local name=$1 dir
    for dir in /usr/lib/qt6/bin /usr/lib/qt6/libexec /usr/lib/x86_64-linux-gnu/qt6/bin /usr/lib64/qt6/bin /usr/lib/qt6; do
        [[ -x "$dir/$name" ]] && { echo "$dir/$name"; return; }
    done
    command -v "${name}6" 2>/dev/null || true
}

qmlformat_bin=$(qt6_tool qmlformat)
if [[ -n "$qmlformat_bin" ]]; then
    for f in "${qml_files[@]}"; do
        "$qmlformat_bin" "$f" >/dev/null 2>"$tmp/qmlformat.err" || { fail "$f: QML syntax"; cat "$tmp/qmlformat.err"; }
    done
    pass "QML syntax (qmlformat)"
else
    skip "qmlformat not installed"
fi

qmllint_bin=$(qt6_tool qmllint)
qml_import_dir=$(ls -d /usr/lib/qt6/qml /usr/lib/x86_64-linux-gnu/qt6/qml /usr/lib64/qt6/qml 2>/dev/null | head -1 || true)
if [[ -n "$qmllint_bin" && -n "$qml_import_dir" && -d "$qml_import_dir/org/kde/plasma/plasmoid" ]]; then
    # i18n() is provided by Plasma at runtime, and Loader items are untyped; everything
    # else (unknown types, imports, properties, syntax) is an error.
    for f in "${qml_files[@]}"; do
        "$qmllint_bin" -I "$qml_import_dir" "$f" >"$tmp/lint.out" 2>&1
        grep -E '^(Warning|Error):' "$tmp/lint.out" \
            | grep -vE 'Unqualified access \[unqualified\]|Member "(uuid|hasThumbnail)" not found on type|on type "QObject" \[missing-property\]' \
            >"$tmp/lint.real" || true
        if [[ -s "$tmp/lint.real" ]]; then
            fail "$f: qmllint"
            cat "$tmp/lint.real"
        fi
    done
    pass "QML type-checked against KDE modules (qmllint)"
else
    skip "qmllint or KDE QML modules not available; QML not type-checked"
fi

echo
if [[ $failed -ne 0 ]]; then
    echo "Lint failed."
    exit 1
fi
echo "All checks passed."
