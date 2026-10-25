#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Anand Kumar Anbazhagan
# SPDX-License-Identifier: GPL-2.0-or-later
"""Generate the Glossy Glass panel backgrounds.

Writes panel-background.svg for the plain, translucent, solid and opaque variants of the
Plasma style. Every panel gets a dark frosted fill with 16px rounded corners and no rim,
gloss or shadow. Panels on the bottom edge ("south" prefix) get a much smaller side margin
so a dock's glass hugs its icons: 6px here plus the panel's own 4px spacing = 10px.

Usage: tools/gen-panel-svg.py [plasma-style-dir]   (default: plasma-style/glossy-glass)
"""

import pathlib
import sys

RADIUS = 16
FILL = "#1c1c1e"
TRANSLUCENT_OPACITY = 0.48
OPAQUE_OPACITY = 0.92


def frame(prefix, opacity, y0, margins):
    """One FrameSvg frame: corners, edges, centre, their masks and margin hints."""
    p = prefix + "-" if prefix else ""
    m = "mask-" + p
    fill = f'fill="{FILL}" fill-opacity="{opacity}"'
    left, right, top, bottom = margins
    r = RADIUS
    out = [
        f'<rect id="{p}hint-top-margin" x="600" y="{y0}" width="1" height="{top}" fill="none"/>',
        f'<rect id="{p}hint-bottom-margin" x="610" y="{y0}" width="1" height="{bottom}" fill="none"/>',
        f'<rect id="{p}hint-left-margin" x="600" y="{y0 + 30}" width="{left}" height="1" fill="none"/>',
        f'<rect id="{p}hint-right-margin" x="600" y="{y0 + 40}" width="{right}" height="1" fill="none"/>',
        f'<rect id="{p}hint-stretch-borders" x="600" y="{y0 + 50}" width="1" height="1" fill="none"/>',
    ]
    corners = {
        "topleft": (20, 0, f"M{r},0 L{r},{r} L0,{r} A{r},{r} 0 0 1 {r},0 Z"),
        "topright": (80, 0, f"M0,0 L0,{r} L{r},{r} A{r},{r} 0 0 0 0,0 Z"),
        "bottomleft": (20, 60, f"M{r},{r} L{r},0 L0,0 A{r},{r} 0 0 0 {r},{r} Z"),
        "bottomright": (80, 60, f"M{r},0 L0,0 L0,{r} A{r},{r} 0 0 0 {r},0 Z"),
    }
    for name, (x, dy, d) in corners.items():
        out.append(f'<path id="{p}{name}" transform="translate({x},{y0 + dy})" d="{d}" {fill}/>')
        out.append(f'<path id="{m}{name}" transform="translate({x},{y0 + 160 + dy})" d="{d}" fill="#ffffff"/>')
    edges = {
        "top": (160, 0, 24, r),
        "bottom": (160, 60, 24, r),
        "left": (220, 0, r, 20),
        "right": (260, 0, r, 20),
        "center": (320, 0, 24, 20),
    }
    for name, (x, dy, w, h) in edges.items():
        out.append(f'<rect id="{p}{name}" x="{x}" y="{y0 + dy}" width="{w}" height="{h}" {fill}/>')
        out.append(f'<rect id="{m}{name}" x="{x}" y="{y0 + 160 + dy}" width="{w}" height="{h}" fill="#ffffff"/>')
    return out


def svg(opacity):
    lines = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<svg xmlns="http://www.w3.org/2000/svg" width="700" height="760" viewBox="0 0 700 760">',
    ]
    lines += frame("", opacity, 20, (16, 16, 16, 16))
    # Thick panels: small fixed margins.
    lines += [
        '<rect id="thick-hint-top-margin" x="640" y="10" width="1" height="2" fill="none"/>',
        '<rect id="thick-hint-bottom-margin" x="650" y="10" width="1" height="2" fill="none"/>',
        '<rect id="thick-hint-left-margin" x="640" y="20" width="2" height="1" fill="none"/>',
        '<rect id="thick-hint-right-margin" x="640" y="30" width="2" height="1" fill="none"/>',
        '<rect id="thick-center" x="660" y="10" width="2" height="2" fill="none"/>',
    ]
    # Bottom-edge panels (docks): the glass hugs the icons.
    lines += frame("south", opacity, 400, (6, 6, 1, 1))
    lines.append("</svg>")
    return "\n".join(lines) + "\n"


def main():
    base = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "plasma-style/glossy-glass")
    variants = {
        "widgets": TRANSLUCENT_OPACITY,
        "translucent/widgets": TRANSLUCENT_OPACITY,
        "solid/widgets": OPAQUE_OPACITY,
        "opaque/widgets": OPAQUE_OPACITY,
    }
    for sub, opacity in variants.items():
        target = base / sub / "panel-background.svg"
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(svg(opacity))
        print(f"wrote {target}")


if __name__ == "__main__":
    main()
