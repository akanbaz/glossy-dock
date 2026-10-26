/*
    SPDX-FileCopyrightText: 2026 Anand Kumar Anbazhagan
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// Measures how much of its square an icon's artwork really fills. Many icons (often web
// app and Electron icons) ship with transparent padding, so at the same size they look
// smaller than icons whose artwork reaches the edges. The dock draws those icons larger
// to even this out.
//
// Usage: call measure(key, source, size); `measured(key, fill)` follows, where fill is the
// visible artwork's larger side divided by size (0..1]. Jobs run one at a time.

import QtQuick
import org.kde.kirigami as Kirigami

Item {
    id: fitter

    signal measured(string key, real fill)

    property var queue: []
    property var current: null
    // Alpha above this counts as artwork (ignores faint shadows and antialiasing).
    readonly property int alphaThreshold: 40

    width: 1
    height: 1

    function measure(key, source, size) {
        if (!key || !source || !(size > 0)) {
            return
        }
        queue.push({ key: key, source: source, size: Math.round(size) })
        next()
    }

    function next() {
        if (current || queue.length === 0) {
            return
        }
        current = queue.shift()
        probe.width = current.size
        probe.height = current.size
        probe.source = current.source
        settle.restart()
    }

    function finish(fill) {
        const job = current
        current = null
        if (job) {
            fitter.measured(job.key, fill)
        }
        next()
    }

    // Rendered off to the side, never seen: grabToImage needs a live item in a window.
    Kirigami.Icon {
        id: probe
        x: -10000
        roundToIconSize: false
        animated: false
    }

    // Give the probe a frame to render its new icon before grabbing it.
    Timer {
        id: settle
        interval: 80
        onTriggered: {
            if (!probe.grabToImage(result => {
                grabbed.source = result.url
            }, Qt.size(fitter.current.size, fitter.current.size))) {
                fitter.finish(1)
            }
        }
    }

    // The grab's URL only loads in an Image element (not in Canvas.loadImage), and a Canvas
    // can draw an Image element; reading the pixels back gives the artwork's extent.
    Image {
        id: grabbed
        x: -10000
        cache: false
        onStatusChanged: {
            if (status === Image.Ready && fitter.current) {
                canvas.requestPaint()
            } else if (status === Image.Error) {
                fitter.finish(1)
            }
        }
    }

    Canvas {
        id: canvas
        x: -10000
        width: 256
        height: 256
        renderTarget: Canvas.Image
        renderStrategy: Canvas.Immediate
        onPaint: {
            if (!fitter.current || grabbed.status !== Image.Ready) {
                return
            }
            const size = Math.min(fitter.current.size, width, height)
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            ctx.drawImage(grabbed, 0, 0)
            const data = ctx.getImageData(0, 0, size, size).data
            let minX = size, minY = size, maxX = -1, maxY = -1
            for (let y = 0; y < size; y++) {
                for (let x = 0; x < size; x++) {
                    if (data[(y * size + x) * 4 + 3] > fitter.alphaThreshold) {
                        if (x < minX) minX = x
                        if (x > maxX) maxX = x
                        if (y < minY) minY = y
                        if (y > maxY) maxY = y
                    }
                }
            }
            grabbed.source = ""
            // An empty icon (nothing above the threshold) is left alone.
            fitter.finish(maxX < 0 ? 1 : Math.max(maxX - minX + 1, maxY - minY + 1) / size)
        }
    }
}
