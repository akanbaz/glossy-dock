#!/bin/sh
# SPDX-FileCopyrightText: 2026 Anand Kumar Anbazhagan
# SPDX-License-Identifier: GPL-2.0-or-later
#
# App actions from a launcher's .desktop file, for the dock's right-click menu.
#   actions.sh list <launcher-url>           -> one "id<TAB>name<TAB>icon" line per action
#   actions.sh run  <launcher-url> <action>  -> starts that action, detached
# <launcher-url> is "applications:foo.desktop", "file:///path/foo.desktop" or a path.
# Prints nothing and exits 0 when the launcher or action can't be found.

set -u

url=${2-}
[ -n "$url" ] || exit 0

find_desktop_file() {
    id=$1
    dirs="${XDG_DATA_HOME:-$HOME/.local/share}:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
    dirs="$dirs:/var/lib/flatpak/exports/share:$HOME/.local/share/flatpak/exports/share:/var/lib/snapd/desktop"
    # Desktop file IDs map "-" to subdirectories: kde4-foo.desktop may be kde4/foo.desktop.
    alt=$(printf '%s' "$id" | sed 's|-|/|')
    old_ifs=$IFS
    IFS=:
    for d in $dirs; do
        [ -n "$d" ] || continue
        for candidate in "$d/applications/$id" "$d/applications/$alt"; do
            if [ -f "$candidate" ]; then
                IFS=$old_ifs
                printf '%s\n' "$candidate"
                return 0
            fi
        done
    done
    IFS=$old_ifs
    return 1
}

case "$url" in
applications:*) path=$(find_desktop_file "${url#applications:}") || exit 0 ;;
file://*) path=${url#file://} ;;
*) path=$url ;;
esac

[ -f "$path" ] || exit 0

# Locale candidates for localized names, most specific first: de_DE@euro -> de_DE, de.
locale=${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}
locale=${locale%%.*}
locale=${locale%%@*}
lang=${locale%%_*}

case "${1-}" in
list)
    awk -F= -v loc="$locale" -v lang="$lang" '
        /^\[/ { group = $0; next }
        group == "[Desktop Entry]" && $1 == "Actions" { n = split($2, order, ";") }
        group ~ /^\[Desktop Action .*\]$/ {
            a = substr(group, 17, length(group) - 17)
            value = substr($0, length($1) + 2)
            if ($1 == "Name") name[a] = value
            else if (loc != "" && $1 == "Name[" loc "]") lname[a] = value
            else if (lang != "" && $1 == "Name[" lang "]" && !(a in lname)) lname[a] = value
            else if ($1 == "Icon") icon[a] = value
        }
        END {
            for (i = 1; i <= n; i++) {
                a = order[i]
                if (a == "") continue
                label = (a in lname) ? lname[a] : name[a]
                if (label != "") printf "%s\t%s\t%s\n", a, label, icon[a]
            }
        }' "$path"
    ;;
run)
    action=${3-}
    [ -n "$action" ] || exit 0
    exec_line=$(awk -F= -v want="[Desktop Action $action]" '
        /^\[/ { group = $0; next }
        group == want && $1 == "Exec" { print substr($0, 6); exit }' "$path")
    [ -n "$exec_line" ] || exit 0
    # Drop desktop-entry field codes (%u %U %f %F %i %c %k ...) and unescape %%.
    exec_line=$(printf '%s' "$exec_line" | sed -E 's/(^|[[:space:]])%[fFuUdDnNickvm]([[:space:]]|$)/\1\2/g; s/%%/%/g')
    if command -v setsid >/dev/null 2>&1; then
        setsid -f sh -c "$exec_line" >/dev/null 2>&1 </dev/null
    else
        nohup sh -c "$exec_line" >/dev/null 2>&1 </dev/null &
    fi
    ;;
esac
exit 0
