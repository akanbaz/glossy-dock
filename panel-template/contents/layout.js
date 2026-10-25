// SPDX-FileCopyrightText: 2026 Anand Kumar Anbazhagan
// SPDX-License-Identifier: GPL-2.0-or-later
//
// "Glossy Dock" in Add Panel: one centered, floating dock on the screen it was added to.
// Prefers the bottom edge, then any free edge, so it never stacks on an existing panel.

var panel = new Panel
var panelScreen = panel.screen
var freeEdges = {"bottom": true, "top": true, "left": true, "right": true}

for (var i = 0; i < panelIds.length; ++i) {
    var other = panelById(panelIds[i])
    if (other.screen == panelScreen && other.id != panel.id) {
        freeEdges[other.location] = false
    }
}

var edges = ["bottom", "left", "right", "top"]
panel.location = "bottom"
for (var e = 0; e < edges.length; ++e) {
    if (freeEdges[edges[e]]) {
        panel.location = edges[e]
        break
    }
}

// 42px at the default font size; scales with the user's font/grid unit.
panel.height = Math.round(gridUnit * 42 / 18)
panel.floating = true
panel.lengthMode = "fit"
panel.alignment = "center"
panel.hiding = "dodgewindows"
panel.opacity = "translucent"

panel.addWidget("io.github.akanbaz.glossydock")
