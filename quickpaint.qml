import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Io

ApplicationWindow {
    id: root
    visible: true
    width: 1120
    height: 780
    minimumWidth: 760
    minimumHeight: 540
    title: "OmaPaint"
    color: surface

    property var themeData: ({
        background: "#121212",
        foreground: "#bebebe",
        accent: "#e68e0d",
        selection: "#2a2a2a",
        muted: "#555555"
    })
    readonly property color surface: themeData.background || "#121212"
    readonly property color surfaceRaised: Qt.lighter(surface, 1.18)
    readonly property color surfaceSoft: Qt.lighter(surface, 1.32)
    readonly property color text: themeData.foreground || "#bebebe"
    readonly property color accent: themeData.accent || "#e68e0d"
    readonly property color muted: themeData.muted || "#555555"

    property string tool: "pen"
    property string language: "auto"
    property color ink: "#1f2937"
    property int brushSize: 5
    property int shapeSides: 6
    property bool drawing: false
    property var currentPoints: []
    property var textPoint: ({ x: 0, y: 0 })
    property var textBoxRect: null
    property bool pendingImagePlacement: false
    property var selectionStart: null
    property var selectionEnd: null
    property var selectionRect: null
    property var selectedIndices: []
    property bool movingSelection: false
    property bool scalingSelection: false
    property string scaleCorner: ""
    property var scaleStart: null
    property var scaleOriginalRect: null
    property var scaleOriginalStrokes: []
    property var moveStart: null
    property var moveOriginalRect: null
    property var moveOriginalStrokes: []
    property var clipboardStrokes: []
    property int pasteCount: 0
    property var strokes: []
    property var undoStack: []
    property var redoStack: []
    property var historyLabels: []
    property var redoLabels: []
    property string currentAction: "Gotowe"
    property color canvasBackground: "#ffffff"
    property string rasterBackground: ""
    property var pendingFill: null
    property int pendingFillPixels: 0
    property int fillCaptureSerial: 0
    property string statusText: "Gotowe — narysuj coś ładnego."
    property int documentWidth: 1400
    property int documentHeight: 900
    property real zoom: 1.0
    onZoomChanged: { topRuler.requestPaint(); leftRuler.requestPaint() }
    onDocumentWidthChanged: topRuler.requestPaint()
    onDocumentHeightChanged: leftRuler.requestPaint()

    function currentLanguage() {
        if (language === "pl" || language === "en") return language
        return Qt.locale().name.toLowerCase().indexOf("pl") === 0 ? "pl" : "en"
    }

    function tr(polish, english) {
        return currentLanguage() === "pl" ? polish : english
    }

    function themeLine(line) {
        var m = String(line).match(/^\s*(background|foreground|accent|selection|muted)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
        if (!m) return
        var next = {}
        for (var key in themeData) next[key] = themeData[key]
        next[m[1]] = m[2]
        themeData = next
    }

    Process {
        id: themeProcess
        command: ["bash", "-lc", "theme=$(omarchy theme current | tr '[:upper:] ' '[:lower:]-'); f=\"$HOME/.local/state/omarchy/current/theme/colors.toml\"; [ -f \"$f\" ] || f=\"/usr/share/omarchy/themes/$theme/colors.toml\"; grep -E '^(background|foreground|accent|selection|muted)[[:space:]]*=' \"$f\""]
        stdout: SplitParser { onRead: function(line) { root.themeLine(line) } }
        Component.onCompleted: running = true
    }

    function snapshot() {
        return JSON.stringify({ strokes: strokes,
                                rasterBackground: rasterBackground,
                                canvasBackground: String(canvasBackground) })
    }

    function restoreSnapshot(serialized) {
        var state = JSON.parse(serialized)
        strokes = state.strokes || []
        rasterBackground = state.rasterBackground || ""
        canvasBackground = state.canvasBackground || "#ffffff"
        rasterImage.source = rasterBackground
        currentPoints = []
        selectedIndices = []
        selectionRect = null
        movingSelection = false
    }

    function remember(label) {
        undoStack = undoStack.concat([snapshot()])
        redoStack = []
        historyLabels = historyLabels.concat([label || "Edycja"])
        redoLabels = []
        currentAction = label || "Edycja"
    }

    function selectTool(name) {
        tool = name
        if (name !== "select") selectionRect = null
        if (name !== "select") selectedIndices = []
        statusText = toolLabel(name) + (currentLanguage() === "pl" ? " — wybrano" : " selected")
        canvas.requestPaint()
    }

    function toolLabel(name) {
        var polish = { pen: "Pióro", pencil: "Ołówek", marker: "Marker", eraser: "Gumka",
            fill: "Wypełnienie", line: "Linia", rectangle: "Prostokąt", ellipse: "Elipsa",
            star: "Gwiazda", polygon: "Wielokąt", select: "Zaznaczanie", text: "Tekst" }
        var english = { pen: "Pen", pencil: "Pencil", marker: "Marker", eraser: "Eraser",
            fill: "Fill", line: "Line", rectangle: "Rectangle", ellipse: "Ellipse",
            star: "Star", polygon: "Polygon", select: "Select", text: "Text" }
        return currentLanguage() === "pl" ? (polish[name] || name) : (english[name] || name)
    }

    function toolIcon(name) {
        var icons = { pen: "✎", pencil: "✏", marker: "▰", eraser: "⌫", fill: "▧",
            line: "╱", rectangle: "□", ellipse: "○", star: "☆", polygon: "⬡",
            select: "⌗", text: "T" }
        return icons[name] || "•"
    }

    function addPoint(x, y) {
        var points = currentPoints.slice()
        if (["line", "rectangle", "ellipse", "star", "polygon"].indexOf(tool) >= 0 && points.length > 0)
            points = [points[0], { x: x, y: y }]
        else
            points.push({ x: x, y: y })
        currentPoints = points
        canvas.requestPaint()
    }

    function shapeVertices(stroke) {
        var points = stroke.points || []
        if (points.length < 2) return []
        var first = points[0]
        var last = points[points.length - 1]
        var sides = stroke.tool === "star" ? 5 : Math.max(3, stroke.sides || root.shapeSides)
        var vertices = stroke.tool === "star" ? sides * 2 : sides
        var cx = (first.x + last.x) / 2
        var cy = (first.y + last.y) / 2
        var radiusX = Math.abs(last.x - first.x) / 2
        var radiusY = Math.abs(last.y - first.y) / 2
        var result = []
        for (var vertex = 0; vertex < vertices; vertex++) {
            var angle = -Math.PI / 2 + vertex * Math.PI * 2 / vertices
            var radius = stroke.tool === "star" && vertex % 2 === 1 ? 0.45 : 1
            result.push({ x: cx + Math.cos(angle) * radiusX * radius,
                          y: cy + Math.sin(angle) * radiusY * radius })
        }
        return result
    }

    function pointInPolygon(point, polygon) {
        var inside = false
        for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
            var a = polygon[i], b = polygon[j]
            if (((a.y > point.y) !== (b.y > point.y)) &&
                    point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x)
                inside = !inside
        }
        return inside
    }

    function pointInsideStroke(stroke, x, y) {
        var points = stroke.points || []
        if (points.length < 2) return false
        var first = points[0]
        var last = points[points.length - 1]
        if (stroke.tool === "rectangle")
            return x >= Math.min(first.x, last.x) && x <= Math.max(first.x, last.x) &&
                   y >= Math.min(first.y, last.y) && y <= Math.max(first.y, last.y)
        if (stroke.tool === "ellipse") {
            var rx = Math.max(0.5, Math.abs(last.x - first.x) / 2)
            var ry = Math.max(0.5, Math.abs(last.y - first.y) / 2)
            var dx = x - (first.x + last.x) / 2
            var dy = y - (first.y + last.y) / 2
            return (dx * dx) / (rx * rx) + (dy * dy) / (ry * ry) <= 1
        }
        if (stroke.tool === "star" || stroke.tool === "polygon")
            return pointInPolygon({ x: x, y: y }, shapeVertices(stroke))
        if (stroke.tool === "freehand" && points.length >= 3)
            return pointInPolygon({ x: x, y: y }, points)
        return false
    }

    function fillShapeAt(x, y) {
        for (var i = strokes.length - 1; i >= 0; i--) {
            var stroke = strokes[i]
            if (!pointInsideStroke(stroke, x, y)) continue
            var next = strokes.slice()
            var filled = JSON.parse(JSON.stringify(stroke))
            filled.fill = String(ink)
            next[i] = filled
            remember("Wypełnij kształt")
            strokes = next
            statusText = "Wypełniono kształt kolorem " + String(ink)
            canvas.requestPaint()
            return true
        }
        return false
    }

    function finishStroke() {
        if (!drawing) return
        if (currentPoints.length === 1) {
            var dot = currentPoints[0]
            addPoint(dot.x + 0.1, dot.y + 0.1)
        }
        var next = strokes.slice()
        next.push({ points: currentPoints, tool: tool, color: String(ink), size: brushSize, sides: shapeSides })
        strokes = next
        currentPoints = []
        drawing = false
        if (["line", "rectangle", "ellipse", "star", "polygon"].indexOf(tool) >= 0) {
            var addedIndex = strokes.length - 1
            selectedIndices = [addedIndex]
            selectionRect = boundsForStroke(strokes[addedIndex])
            tool = "select"
        }
        statusText = "Liczba elementów: " + strokes.length
        canvas.requestPaint()
    }

    function drawStroke(ctx, stroke) {
        var points = stroke.points || []
        if (points.length === 0) return
        ctx.save()
        ctx.lineCap = "round"
        ctx.lineJoin = "round"
        ctx.lineWidth = stroke.size * (stroke.tool === "marker" ? 1.7 : stroke.tool === "pencil" ? 0.65 : stroke.tool === "eraser" ? 2.5 : 1)
        if (stroke.tool === "image") {
            var imageFirst = points[0]
            var imageLast = points[points.length - 1]
            if (openedImage.status === Image.Ready)
                ctx.drawImage(openedImage, imageFirst.x, imageFirst.y,
                              imageLast.x - imageFirst.x, imageLast.y - imageFirst.y)
            ctx.restore()
            return
        }
        if (stroke.tool === "text") {
            ctx.globalCompositeOperation = "source-over"
            ctx.fillStyle = stroke.color
            ctx.globalAlpha = 1
            ctx.font = String(stroke.size) + "px sans-serif"
            var text = String(stroke.text || "")
            var maxWidth = stroke.boxWidth || 420
            var lineHeight = stroke.size * 1.25
            var words = text.split(/\s+/)
            var line = ""
            var lineY = points[0].y + stroke.size
            for (var wordIndex = 0; wordIndex < words.length; wordIndex++) {
                var candidate = line.length > 0 ? line + " " + words[wordIndex] : words[wordIndex]
                if (line.length > 0 && ctx.measureText(candidate).width > maxWidth) {
                    ctx.fillText(line, points[0].x, lineY)
                    line = words[wordIndex]
                    lineY += lineHeight
                } else line = candidate
            }
            if (line.length > 0) ctx.fillText(line, points[0].x, lineY)
            ctx.restore()
            return
        }
        if (stroke.tool === "eraser") {
            // The drawing surface is intentionally white, so painting white
            // removes marks cleanly without exposing the gray app frame.
            ctx.globalCompositeOperation = "source-over"
            ctx.strokeStyle = "#ffffff"
            ctx.globalAlpha = 1
        } else {
            ctx.globalCompositeOperation = "source-over"
            ctx.strokeStyle = stroke.color
            ctx.globalAlpha = stroke.tool === "marker" ? 0.38 : 1
        }
        var first = points[0]
        var last = points[points.length - 1]
        ctx.beginPath()
        if (stroke.tool === "line") {
            ctx.moveTo(first.x, first.y)
            ctx.lineTo(last.x, last.y)
            ctx.stroke()
        } else if (stroke.tool === "rectangle") {
            var rectX = Math.min(first.x, last.x)
            var rectY = Math.min(first.y, last.y)
            var rectW = Math.abs(last.x - first.x)
            var rectH = Math.abs(last.y - first.y)
            if (stroke.fill) {
                ctx.fillStyle = stroke.fill
                ctx.fillRect(rectX, rectY, rectW, rectH)
            }
            ctx.strokeRect(rectX, rectY, rectW, rectH)
        } else if (stroke.tool === "ellipse") {
            var centerX = (first.x + last.x) / 2
            var centerY = (first.y + last.y) / 2
            var radiusX = Math.max(0.5, Math.abs(last.x - first.x) / 2)
            var radiusY = Math.max(0.5, Math.abs(last.y - first.y) / 2)
            ctx.save()
            ctx.translate(centerX, centerY)
            ctx.scale(radiusX, radiusY)
            ctx.arc(0, 0, 1, 0, Math.PI * 2)
            ctx.restore()
            if (stroke.fill) {
                ctx.fillStyle = stroke.fill
                ctx.fill()
            }
            ctx.stroke()
        } else if (stroke.tool === "star" || stroke.tool === "polygon") {
            var sides = stroke.tool === "star" ? 5 : Math.max(3, stroke.sides || root.shapeSides)
            var cx = (first.x + last.x) / 2
            var cy = (first.y + last.y) / 2
            var radiusX = Math.abs(last.x - first.x) / 2
            var radiusY = Math.abs(last.y - first.y) / 2
            var vertices = stroke.tool === "star" ? sides * 2 : sides
            ctx.moveTo(cx, cy - radiusY)
            for (var vertex = 1; vertex <= vertices; vertex++) {
                var angle = -Math.PI / 2 + vertex * Math.PI * 2 / vertices
                var radius = stroke.tool === "star" && vertex % 2 === 1 ? 0.45 : 1
                ctx.lineTo(cx + Math.cos(angle) * radiusX * radius,
                           cy + Math.sin(angle) * radiusY * radius)
            }
            if (stroke.fill) {
                ctx.fillStyle = stroke.fill
                ctx.fill()
            }
            ctx.stroke()
        } else {
            ctx.moveTo(points[0].x, points[0].y)
            for (var i = 1; i < points.length; i++) ctx.lineTo(points[i].x, points[i].y)
            if (stroke.fill) {
                ctx.fillStyle = stroke.fill
                ctx.fill()
            }
            ctx.stroke()
        }
        ctx.restore()
    }

    function boundsForStroke(stroke) {
        var points = stroke.points || []
        if (points.length === 0) return null
        if (stroke.tool === "text" && stroke.boxWidth && stroke.boxHeight)
            return { x: points[0].x, y: points[0].y, width: stroke.boxWidth, height: stroke.boxHeight }
        var minX = points[0].x, maxX = points[0].x, minY = points[0].y, maxY = points[0].y
        for (var i = 1; i < points.length; i++) {
            minX = Math.min(minX, points[i].x); maxX = Math.max(maxX, points[i].x)
            minY = Math.min(minY, points[i].y); maxY = Math.max(maxY, points[i].y)
        }
        return { x: minX, y: minY, width: maxX - minX, height: maxY - minY }
    }

    function boundsOverlap(a, b) {
        return a && b && a.x <= b.x + b.width && a.x + a.width >= b.x &&
               a.y <= b.y + b.height && a.y + a.height >= b.y
    }

    function boundsContained(inner, outer) {
        return inner && outer &&
               inner.x >= outer.x && inner.y >= outer.y &&
               inner.x + inner.width <= outer.x + outer.width &&
               inner.y + inner.height <= outer.y + outer.height
    }

    function finishSelection() {
        if (!selectionStart || !selectionEnd) return
        var x = Math.min(selectionStart.x, selectionEnd.x)
        var y = Math.min(selectionStart.y, selectionEnd.y)
        selectionRect = { x: x, y: y,
                          width: Math.abs(selectionEnd.x - selectionStart.x),
                          height: Math.abs(selectionEnd.y - selectionStart.y) }
        selectedIndices = []
        for (var i = 0; i < strokes.length; i++) {
            // A marquee selects complete objects only. This prevents a large
            // background shape from being selected when a smaller text box
            // inside it is selected.
            if (boundsContained(boundsForStroke(strokes[i]), selectionRect)) selectedIndices.push(i)
        }
        // A tiny click selects only the topmost object under the pointer.
        if (selectedIndices.length === 0 && selectionRect.width < 12 && selectionRect.height < 12) {
            for (var top = strokes.length - 1; top >= 0; top--) {
                if (boundsOverlap(boundsForStroke(strokes[top]), selectionRect)) {
                    selectedIndices.push(top)
                    break
                }
            }
        }
        drawing = false
        currentPoints = []
        statusText = "Zaznaczenie gotowe"
        canvas.requestPaint()
    }

    function pointInSelection(x, y) {
        return selectionRect && x >= selectionRect.x && x <= selectionRect.x + selectionRect.width &&
               y >= selectionRect.y && y <= selectionRect.y + selectionRect.height
    }

    function topmostObjectAt(x, y) {
        var probe = { x: x, y: y, width: 0, height: 0 }
        for (var i = strokes.length - 1; i >= 0; i--) {
            var bounds = boundsForStroke(strokes[i])
            if (bounds && x >= bounds.x && x <= bounds.x + bounds.width &&
                    y >= bounds.y && y <= bounds.y + bounds.height) return i
        }
        return -1
    }

    function resizeHandleAt(x, y) {
        if (!selectionRect) return ""
        var radius = 12 / root.zoom
        var corners = [
            { name: "nw", x: selectionRect.x, y: selectionRect.y },
            { name: "ne", x: selectionRect.x + selectionRect.width, y: selectionRect.y },
            { name: "sw", x: selectionRect.x, y: selectionRect.y + selectionRect.height },
            { name: "se", x: selectionRect.x + selectionRect.width, y: selectionRect.y + selectionRect.height }
        ]
        for (var i = 0; i < corners.length; i++)
            if (Math.abs(x - corners[i].x) <= radius && Math.abs(y - corners[i].y) <= radius) return corners[i].name
        return ""
    }

    function scaleSelectedTo(x, y) {
        if (!scaleStart || !scaleOriginalRect || selectedIndices.length === 0) return
        var oldRect = scaleOriginalRect
        var newRect = { x: oldRect.x, y: oldRect.y, width: oldRect.width, height: oldRect.height }
        if (scaleCorner.indexOf("w") >= 0) { newRect.x = Math.min(x, oldRect.x + oldRect.width - 20); newRect.width = oldRect.x + oldRect.width - newRect.x }
        else { newRect.width = Math.max(20, x - oldRect.x) }
        if (scaleCorner.indexOf("n") >= 0) { newRect.y = Math.min(y, oldRect.y + oldRect.height - 20); newRect.height = oldRect.y + oldRect.height - newRect.y }
        else { newRect.height = Math.max(20, y - oldRect.y) }
        var sx = newRect.width / Math.max(1, oldRect.width)
        var sy = newRect.height / Math.max(1, oldRect.height)
        var scaled = JSON.parse(JSON.stringify(scaleOriginalStrokes))
        for (var n = 0; n < selectedIndices.length; n++) {
            var index = selectedIndices[n]
            var item = scaled[index]
            if (!item) continue
            for (var p = 0; p < item.points.length; p++) {
                item.points[p].x = newRect.x + (item.points[p].x - oldRect.x) * sx
                item.points[p].y = newRect.y + (item.points[p].y - oldRect.y) * sy
            }
            if (item.size) item.size = Math.max(1, item.size * ((sx + sy) / 2))
            if (item.tool === "text") {
                item.boxWidth = Math.max(30, (item.boxWidth || oldRect.width) * sx)
                item.boxHeight = Math.max(20, (item.boxHeight || oldRect.height) * sy)
            }
        }
        strokes = scaled
        selectionRect = newRect
        canvas.requestPaint()
    }

    function finishScale() {
        if (!scalingSelection) return
        scalingSelection = false
        drawing = false
        currentAction = "Zmień rozmiar zaznaczenia"
        statusText = currentAction
        canvas.requestPaint()
    }

    function moveSelectedTo(x, y) {
        if (!moveStart || selectedIndices.length === 0) return
        var dx = x - moveStart.x
        var dy = y - moveStart.y
        var moved = JSON.parse(JSON.stringify(moveOriginalStrokes))
        for (var n = 0; n < selectedIndices.length; n++) {
            var index = selectedIndices[n]
            if (!moved[index]) continue
            for (var p = 0; p < moved[index].points.length; p++) {
                moved[index].points[p].x += dx
                moved[index].points[p].y += dy
            }
        }
        strokes = moved
        selectionRect = { x: moveOriginalRect.x + dx, y: moveOriginalRect.y + dy,
                          width: moveOriginalRect.width, height: moveOriginalRect.height }
        canvas.requestPaint()
    }

    function finishMove() {
        if (!movingSelection) return
        movingSelection = false
        drawing = false
        currentAction = "Przenieś zaznaczenie"
        statusText = currentAction
        canvas.requestPaint()
    }

    function copySelection() {
        if (!selectionRect) return
        var copied = []
        var indices = selectedIndices.length > 0 ? selectedIndices : []
        if (indices.length === 0) {
            for (var j = 0; j < strokes.length; j++)
                if (boundsOverlap(boundsForStroke(strokes[j]), selectionRect)) indices.push(j)
        }
        for (var i = 0; i < indices.length; i++) copied.push(strokes[indices[i]])
        clipboardStrokes = JSON.parse(JSON.stringify(copied))
        pasteCount = 0
        statusText = "Skopiowano elementów: " + copied.length
    }

    function cutSelection() {
        if (!selectionRect) return
        copySelection()
        if (clipboardStrokes.length === 0) return
        remember("Wytnij zaznaczenie")
        var remaining = []
        for (var i = 0; i < strokes.length; i++) {
            if (!boundsOverlap(boundsForStroke(strokes[i]), selectionRect)) remaining.push(strokes[i])
        }
        strokes = remaining
        statusText = "Wycięto zaznaczenie"
        canvas.requestPaint()
    }

    function pasteSelection() {
        if (clipboardStrokes.length === 0) return
        remember("Wklej zaznaczenie")
        pasteCount += 1
        var offset = 20 * pasteCount
        var pasted = strokes.slice()
        for (var i = 0; i < clipboardStrokes.length; i++) {
            var source = clipboardStrokes[i]
            var points = []
            for (var j = 0; j < source.points.length; j++)
                points.push({ x: source.points[j].x + offset, y: source.points[j].y + offset })
            pasted.push({ points: points, tool: source.tool, text: source.text, color: source.color,
                          size: source.size, sides: source.sides })
        }
        strokes = pasted
        selectedIndices = []
        for (var k = strokes.length - clipboardStrokes.length; k < strokes.length; k++) selectedIndices.push(k)
        selectionRect = null
        for (var s = 0; s < selectedIndices.length; s++) {
            var b = boundsForStroke(strokes[selectedIndices[s]])
            if (!b) continue
            if (!selectionRect) selectionRect = { x: b.x, y: b.y, width: b.width, height: b.height }
            else {
                var right = Math.max(selectionRect.x + selectionRect.width, b.x + b.width)
                var bottom = Math.max(selectionRect.y + selectionRect.height, b.y + b.height)
                selectionRect.x = Math.min(selectionRect.x, b.x)
                selectionRect.y = Math.min(selectionRect.y, b.y)
                selectionRect.width = right - selectionRect.x
                selectionRect.height = bottom - selectionRect.y
            }
        }
        tool = "select"
        statusText = "Wklejono zaznaczenie"
        canvas.requestPaint()
    }

    function undo() {
        if (undoStack.length === 0) return
        var undoneLabel = historyLabels.length > 0 ? historyLabels[historyLabels.length - 1] : "Edycja"
        redoStack = redoStack.concat([snapshot()])
        redoLabels = redoLabels.concat([undoneLabel])
        restoreSnapshot(undoStack[undoStack.length - 1])
        undoStack = undoStack.slice(0, undoStack.length - 1)
        historyLabels = historyLabels.slice(0, historyLabels.length - 1)
        currentAction = "Cofnij: " + undoneLabel
        statusText = currentAction
        canvas.requestPaint()
    }

    function redo() {
        if (redoStack.length === 0) return
        var redoneLabel = redoLabels.length > 0 ? redoLabels[redoLabels.length - 1] : "Edycja"
        undoStack = undoStack.concat([snapshot()])
        historyLabels = historyLabels.concat([redoneLabel])
        restoreSnapshot(redoStack[redoStack.length - 1])
        redoStack = redoStack.slice(0, redoStack.length - 1)
        redoLabels = redoLabels.slice(0, redoLabels.length - 1)
        currentAction = "Ponów: " + redoneLabel
        statusText = currentAction
        canvas.requestPaint()
    }

    function clearCanvas() {
        if (strokes.length === 0) return
        remember("Wyczyść płótno")
        strokes = []
        statusText = "Wyczyszczono płótno"
        canvas.requestPaint()
    }

    function newCanvas() {
        if (strokes.length > 0) remember("Nowe płótno")
        strokes = []
        canvasBackground = "#ffffff"
        rasterBackground = ""
        rasterImage.source = ""
        redoStack = []
        redoLabels = []
        statusText = "Nowe płótno gotowe"
        canvas.requestPaint()
    }

    function saveCanvas(url) {
        canvas.grabToImage(function(result) {
            var path = url.toString().replace(/^file:\/\//, "")
            result.saveToFile(path)
            statusText = "Zapisano " + path.split("/").pop()
        })
    }

    function commitFilledCanvas() {
        if (pendingFillPixels <= 0) return
        var filledPixels = pendingFillPixels
        pendingFillPixels = 0
        fillCaptureSerial += 1
        var filePath = "/tmp/omapaint-fill-" + fillCaptureSerial + ".png"
        canvas.grabToImage(function(result) {
            // Persist the changed frame as a real PNG. This avoids relying on
            // data URLs, which are not consistently reloaded by Qt Quick's
            // Image element in all compositor configurations.
            if (!result.saveToFile(filePath)) {
                root.statusText = "Nie można zapisać wypełnionego obrazu"
                return
            }
            root.rasterBackground = "file://" + filePath
            rasterImage.cache = false
            rasterImage.source = ""
            rasterImage.source = root.rasterBackground
            root.strokes = []
            root.selectedIndices = []
            root.selectionRect = null
            root.statusText = "Wypełniono pikseli: " + filledPixels
            canvas.requestPaint()
        })
    }

    function openCanvas(url) {
        openedImage.source = url
        strokes = []
        canvasBackground = "#ffffff"
        pendingImagePlacement = true
        rasterBackground = ""
        rasterImage.source = ""
        currentPoints = []
        selectionRect = null
        selectedIndices = []
        undoStack = []
        redoStack = []
        historyLabels = []
        redoLabels = []
        statusText = "Otwieranie: " + url.toString().split("/").pop()
    }

    function placeOpenedImage() {
        if (!pendingImagePlacement || openedImage.status !== Image.Ready) return
        pendingImagePlacement = false
        var imageWidth = Math.max(1, openedImage.sourceSize.width)
        var imageHeight = Math.max(1, openedImage.sourceSize.height)
        var maxWidth = documentWidth * 0.8
        var maxHeight = documentHeight * 0.8
        var fit = Math.min(1, maxWidth / imageWidth, maxHeight / imageHeight)
        var width = Math.max(1, imageWidth * fit)
        var height = Math.max(1, imageHeight * fit)
        var x = (documentWidth - width) / 2
        var y = (documentHeight - height) / 2
        strokes = [{ points: [{ x: x, y: y }, { x: x + width, y: y + height }],
                     tool: "image", source: openedImage.source.toString(),
                     originalWidth: imageWidth, originalHeight: imageHeight }]
        selectionRect = { x: x, y: y, width: width, height: height }
        selectedIndices = [0]
        tool = "select"
        statusText = "Obraz dodany — przeciągnij narożnik, aby zmienić rozmiar"
        canvas.requestPaint()
    }

    function resizeDocument(newWidth, newHeight) {
        newWidth = Math.max(64, Math.min(5000, Math.round(newWidth)))
        newHeight = Math.max(64, Math.min(5000, Math.round(newHeight)))
        if (newWidth === documentWidth && newHeight === documentHeight) return
        remember("Zmień rozmiar płótna")
        var sx = newWidth / documentWidth
        var sy = newHeight / documentHeight
        var scaled = JSON.parse(JSON.stringify(strokes))
        for (var i = 0; i < scaled.length; i++) {
            var item = scaled[i]
            for (var j = 0; j < item.points.length; j++) {
                item.points[j].x *= sx
                item.points[j].y *= sy
            }
            if (item.size) item.size = Math.max(1, item.size * ((sx + sy) / 2))
            if (item.boxWidth) item.boxWidth *= sx
            if (item.boxHeight) item.boxHeight *= sy
        }
        strokes = scaled
        documentWidth = newWidth
        documentHeight = newHeight
        statusText = "Zmieniono rozmiar płótna na " + newWidth + " × " + newHeight
        canvas.requestPaint()
    }

    function setInk(color) {
        ink = color
        statusText = "Ustawiono kolor: " + color
    }

    function colorBytes(value) {
        var raw = String(value)
        var rgb = raw.match(/rgba?\((\d+),\s*(\d+),\s*(\d+)/)
        if (rgb) return [Number(rgb[1]), Number(rgb[2]), Number(rgb[3]), 255]
        var hex = raw.replace("#", "")
        if (hex.length < 6) return [0, 0, 0, 255]
        return [parseInt(hex.slice(0, 2), 16), parseInt(hex.slice(2, 4), 16), parseInt(hex.slice(4, 6), 16), 255]
    }

    function addFillAt(x, y) {
        if (strokes.length === 0 && rasterBackground === "") {
            remember("Wypełnij tło")
            canvasBackground = String(ink)
            statusText = "Wypełniono całe tło kolorem " + String(ink)
            canvas.requestPaint()
            return
        }
        // Shapes are kept as document objects, so fill them directly. This
        // makes the color persistent in history, PNG export, and redraws.
        if (fillShapeAt(x, y)) return
        remember("Wypełnij kolorem")
        pendingFill = { x: x, y: y, color: String(ink) }
        statusText = "Wypełnianie obszaru..."
        canvas.requestPaint()
    }

    function floodFill(ctx, x, y, color) {
        var image = ctx.getImageData(0, 0, canvas.width, canvas.height)
        var data = image.data
        var width = image.width
        var height = image.height
        var startX = Math.max(0, Math.min(width - 1, Math.round(x)))
        var startY = Math.max(0, Math.min(height - 1, Math.round(y)))
        var start = (startY * width + startX) * 4
        var target = [data[start], data[start + 1], data[start + 2], data[start + 3]]
        var replacement = colorBytes(color)
        var tolerance = 18
        if (Math.abs(target[0] - replacement[0]) <= tolerance &&
                Math.abs(target[1] - replacement[1]) <= tolerance &&
                Math.abs(target[2] - replacement[2]) <= tolerance &&
                Math.abs(target[3] - replacement[3]) <= tolerance) return 0
        function matches(index) {
            return Math.abs(data[index] - target[0]) <= tolerance &&
                   Math.abs(data[index + 1] - target[1]) <= tolerance &&
                   Math.abs(data[index + 2] - target[2]) <= tolerance &&
                   Math.abs(data[index + 3] - target[3]) <= tolerance
        }
        var stack = [[startX, startY]]
        var changed = 0
        while (stack.length > 0) {
            var point = stack.pop()
            var px = point[0], py = point[1]
            if (px < 0 || py < 0 || px >= width || py >= height) continue
            var index = (py * width + px) * 4
            if (!matches(index)) continue
            var left = px
            while (left >= 0 && matches((py * width + left) * 4)) left--
            left++
            var spanUp = false
            var spanDown = false
            for (var scanX = left; scanX < width && matches((py * width + scanX) * 4); scanX++) {
                var scanIndex = (py * width + scanX) * 4
                data[scanIndex] = replacement[0]; data[scanIndex + 1] = replacement[1]
                data[scanIndex + 2] = replacement[2]; data[scanIndex + 3] = replacement[3]
                changed++
                if (py > 0) {
                    var upMatches = matches(((py - 1) * width + scanX) * 4)
                    if (upMatches && !spanUp) { stack.push([scanX, py - 1]); spanUp = true }
                    else if (!upMatches) spanUp = false
                }
                if (py < height - 1) {
                    var downMatches = matches(((py + 1) * width + scanX) * 4)
                    if (downMatches && !spanDown) { stack.push([scanX, py + 1]); spanDown = true }
                    else if (!downMatches) spanDown = false
                }
            }
        }
        ctx.putImageData(image, 0, 0)
        return changed
    }

    function addTextAt(value, x, y) {
        value = String(value || "").trim()
        if (value.length === 0) return
        remember("Dodaj tekst")
        var next = strokes.slice()
        var box = textBoxRect || { x: x, y: y, width: 420, height: Math.max(80, brushSize * 8) }
        next.push({ points: [{ x: box.x, y: box.y }], tool: "text", text: value,
                    color: String(ink), size: Math.max(12, brushSize * 4),
                    boxWidth: Math.max(30, box.width), boxHeight: Math.max(20, box.height) })
        strokes = next
        statusText = "Dodano tekst"
        textBoxRect = null
        selectedIndices = [strokes.length - 1]
        selectionRect = boundsForStroke(strokes[strokes.length - 1])
        tool = "select"
        canvas.requestPaint()
    }

    function finishTextBox() {
        if (!selectionStart || !selectionEnd) return
        var rect = { x: Math.min(selectionStart.x, selectionEnd.x),
                     y: Math.min(selectionStart.y, selectionEnd.y),
                     width: Math.abs(selectionEnd.x - selectionStart.x),
                     height: Math.abs(selectionEnd.y - selectionStart.y) }
        if (rect.width < 12 || rect.height < 12)
            rect = { x: selectionStart.x, y: selectionStart.y, width: 420, height: 100 }
        textBoxRect = rect
        textPoint = { x: rect.x, y: rect.y }
        selectionRect = rect
        drawing = false
        currentPoints = []
        textDialog.open()
        canvas.requestPaint()
    }

    function zoomAt(viewportX, viewportY, deltaY) {
        if (deltaY === 0) return
        var oldZoom = root.zoom
        var nextZoom = Math.max(0.5, Math.min(2.5, oldZoom * (deltaY > 0 ? 1.1 : 0.9)))
        if (nextZoom === oldZoom) return
        var documentX = (viewport.contentX + viewportX) / oldZoom
        var documentY = (viewport.contentY + viewportY) / oldZoom
        root.zoom = nextZoom
        Qt.callLater(function() {
            viewport.contentX = Math.max(0, documentX * nextZoom - viewportX)
            viewport.contentY = Math.max(0, documentY * nextZoom - viewportY)
            viewport.returnToBounds()
        })
    }

    FileDialog {
        id: saveDialog
        title: root.tr("Zapisz rysunek", "Save drawing")
        fileMode: FileDialog.SaveFile
        nameFilters: ["Obraz PNG (*.png)"]
        currentFile: "my-drawing.png"
        onAccepted: root.saveCanvas(selectedFile)
    }

    Dialog {
        id: resizeDialog
        title: root.tr("Zmień rozmiar płótna", "Resize canvas")
        modal: true
        standardButtons: Dialog.Ok | Dialog.Cancel
        onOpened: {
            widthField.text = String(root.documentWidth)
            heightField.text = String(root.documentHeight)
        }
        onAccepted: root.resizeDocument(Number(widthField.text), Number(heightField.text))
        contentItem: ColumnLayout {
            implicitWidth: 280
            spacing: 10
            Label { text: root.tr("Zmień wymiary eksportowanego obrazu.", "Change the exported image dimensions."); color: root.text; wrapMode: Text.WordWrap; Layout.fillWidth: true }
            RowLayout {
                Label { text: root.tr("Szerokość", "Width"); color: root.text; Layout.preferredWidth: 70 }
                TextField { id: widthField; Layout.fillWidth: true; inputMethodHints: Qt.ImhDigitsOnly }
                Label { text: "px"; color: root.muted }
            }
            RowLayout {
                Label { text: root.tr("Wysokość", "Height"); color: root.text; Layout.preferredWidth: 70 }
                TextField { id: heightField; Layout.fillWidth: true; inputMethodHints: Qt.ImhDigitsOnly }
                Label { text: "px"; color: root.muted }
            }
        }
    }

    Dialog {
        id: colorDialog
        title: root.tr("Własny kolor", "Custom color")
        modal: true
        standardButtons: Dialog.Ok | Dialog.Cancel
        onOpened: colorField.text = String(root.ink)
        onAccepted: {
            var value = colorField.text.trim()
            if (/^#[0-9A-Fa-f]{6}$/.test(value)) root.setInk(value)
            else root.statusText = root.tr("Użyj koloru w formacie #e68e0d", "Use a color like #e68e0d")
        }
        contentItem: ColumnLayout {
            implicitWidth: 260
            spacing: 10
            Label { text: root.tr("Wpisz sześciocyfrowy kolor HEX.", "Enter a six-digit hex color."); color: root.text }
            TextField { id: colorField; Layout.fillWidth: true; placeholderText: "#e68e0d"; selectByMouse: true }
            Rectangle {
                Layout.fillWidth: true
                height: 28
                radius: 6
                color: /^#[0-9A-Fa-f]{6}$/.test(colorField.text) ? colorField.text : root.surfaceSoft
                border.color: root.muted
                visible: /^#[0-9A-Fa-f]{6}$/.test(colorField.text)
            }
        }
    }

    Dialog {
        id: textDialog
        title: root.tr("Dodaj tekst", "Add text")
        modal: true
        standardButtons: Dialog.Ok | Dialog.Cancel
        onOpened: textField.text = ""
        onAccepted: root.addTextAt(textField.text, root.textPoint.x, root.textPoint.y)
        contentItem: ColumnLayout {
            implicitWidth: 300
            spacing: 10
            Label { text: root.tr("Wpisz tekst, który ma pojawić się na płótnie.", "Type the text to place on the canvas."); color: root.text }
            TextField { id: textField; Layout.fillWidth: true; placeholderText: "Hello OmaPaint"; selectByMouse: true }
        }
    }

    FileDialog {
        id: openDialog
        title: root.tr("Otwórz PNG", "Open PNG")
        fileMode: FileDialog.OpenFile
        nameFilters: ["Obraz PNG (*.png)", "Wszystkie obrazy (*.png *.jpg *.jpeg *.webp)"]
        onAccepted: root.openCanvas(selectedFile)
    }

    Image {
        id: openedImage
        visible: false
        asynchronous: true
        fillMode: Image.Stretch
        onStatusChanged: {
            if (status === Image.Ready) {
                root.statusText = "Otwarto: " + source.toString().split("/").pop()
                root.placeOpenedImage()
                canvas.requestPaint()
            } else if (status === Image.Error) {
                root.statusText = "Nie można otworzyć obrazu"
            }
        }
    }

    Image {
        id: rasterImage
        visible: false
        asynchronous: true
        onStatusChanged: if (status === Image.Ready) canvas.requestPaint()
    }

    Timer {
        id: fillCaptureTimer
        // Let the Canvas scene graph commit the flood-filled frame before
        // grabToImage() reads it. A zero-delay timer can still run before the
        // scene graph has rendered the onPaint result.
        interval: 100
        repeat: false
        onTriggered: root.commitFilledCanvas()
    }

    Shortcut { sequence: "Ctrl+Z"; onActivated: root.undo() }
    Shortcut { sequence: "Ctrl+Shift+Z"; onActivated: root.redo() }
    Shortcut { sequence: "Ctrl+O"; onActivated: openDialog.open() }
    Shortcut { sequence: "Ctrl+S"; onActivated: saveDialog.open() }
    Shortcut { sequence: "Ctrl+N"; onActivated: root.newCanvas() }
    Shortcut { sequence: "Ctrl+C"; onActivated: root.copySelection() }
    Shortcut { sequence: "Ctrl+X"; onActivated: root.cutSelection() }
    Shortcut { sequence: "Ctrl+V"; onActivated: root.pasteSelection() }

        header: ToolBar {
        background: Rectangle { color: root.surface; opacity: 0.98 }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 8
            Label { text: "OmaPaint"; color: root.accent; font.bold: true; font.pixelSize: 17; Layout.rightMargin: 4 }
            Label { text: root.tr("Edytor obrazów", "Image editor"); color: root.muted; font.pixelSize: 11; Layout.rightMargin: 12 }
            ToolButton { text: root.tr("Otwórz", "Open"); onClicked: openDialog.open(); ToolTip.visible: hovered; ToolTip.text: root.tr("Otwórz obraz", "Open image") }
            ToolButton { text: root.tr("Rozmiar", "Resize"); onClicked: resizeDialog.open(); ToolTip.visible: hovered; ToolTip.text: root.tr("Zmień rozmiar płótna", "Resize canvas") }
            ToolButton { text: "↶"; font.pixelSize: 21; enabled: root.undoStack.length > 0; onClicked: root.undo(); ToolTip.visible: hovered; ToolTip.text: root.tr("Cofnij", "Undo") }
            ToolButton { text: "↷"; font.pixelSize: 21; enabled: root.redoStack.length > 0; onClicked: root.redo(); ToolTip.visible: hovered; ToolTip.text: root.tr("Ponów", "Redo") }
            Item { Layout.fillWidth: true }
            ComboBox {
                id: languageSelector
                model: ["auto", "pl", "en"]
                currentIndex: model.indexOf(root.language)
                displayText: root.language === "auto" ? root.tr("Automatyczny", "Automatic") : (root.language === "pl" ? "Polski" : "English")
                implicitWidth: 125
                onActivated: root.language = model[currentIndex]
                ToolTip.visible: hovered
                ToolTip.text: root.tr("Język interfejsu", "Interface language")
            }
            Button { text: root.tr("Zapisz PNG", "Save PNG"); highlighted: true; onClicked: saveDialog.open() }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        anchors.topMargin: 10
        spacing: 10

        Rectangle {
            Layout.fillWidth: true
            height: 62
            radius: 12
            color: root.surface
            border.color: root.muted
            border.width: 1
            Flickable {
                id: toolbarViewport
                anchors.fill: parent
                anchors.margins: 8
                clip: true
                contentWidth: toolbarContents.implicitWidth
                contentHeight: height
                boundsBehavior: Flickable.StopAtBounds

                RowLayout {
                    id: toolbarContents
                    width: implicitWidth
                    height: toolbarViewport.height
                    spacing: 10
                Row {
                    spacing: 3
                    Repeater {
                        model: ["pen", "pencil", "marker", "eraser", "fill", "line", "rectangle", "ellipse", "star", "polygon", "select", "text"]
                        delegate: Button {
                            required property string modelData
                            text: root.toolIcon(modelData)
                            font.pixelSize: 18
                            width: 38
                            height: 38
                            checkable: true
                            checked: root.tool === modelData
                            onClicked: root.selectTool(modelData)
                            palette.button: checked ? root.accent : root.surfaceSoft
                            palette.buttonText: checked ? "#111111" : root.text
                            ToolTip.visible: hovered
                            ToolTip.text: root.toolLabel(modelData)
                        }
                    }
                }
                Rectangle { width: 1; height: 28; color: root.muted; opacity: 0.5 }
                Label { text: root.tr("Kolor", "Color"); color: root.muted }
                Row {
                    spacing: 6
                    Repeater {
                        model: ["#1f2937", "#ef4444", "#f59e0b", "#10b981", "#3b82f6", "#8b5cf6", "#ec4899", "#ffffff"]
                        delegate: RoundButton {
                            required property string modelData
                            width: 23; height: 23; padding: 0
                            background: Rectangle { radius: width / 2; color: modelData; border.color: "#ffffff55" }
                            onClicked: root.setInk(modelData)
                        }
                    }
                }
                Rectangle {
                    width: 28; height: 28; radius: 6
                    color: String(root.ink)
                    border.width: 2
                    border.color: root.text
                    ToolTip.visible: true
                    ToolTip.text: root.tr("Wybrany kolor: ", "Selected color: ") + String(root.ink)
                }
                Button { text: root.tr("Własny", "Custom"); onClicked: colorDialog.open() }
                Rectangle { width: 1; height: 28; color: root.muted; opacity: 0.5 }
                Label { text: root.tr("Rozmiar", "Size"); color: root.muted }
                Slider { from: 1; to: 48; value: root.brushSize; Layout.preferredWidth: 135; onMoved: root.brushSize = Math.round(value) }
                Label { text: root.brushSize + " px"; color: root.text; Layout.preferredWidth: 38 }
                Label { text: root.tr("Boki", "Sides"); color: root.muted }
                SpinBox { from: 3; to: 12; value: root.shapeSides; editable: true; Layout.preferredWidth: 74; onValueModified: root.shapeSides = value }
                Rectangle { width: 1; height: 28; color: root.muted; opacity: 0.5 }
                Label { text: root.tr("Powiększenie", "Zoom"); color: root.muted }
                Slider { from: 0.5; to: 2.5; stepSize: 0.1; value: root.zoom; Layout.preferredWidth: 110; onMoved: root.zoom = value }
                Label { text: Math.round(root.zoom * 100) + "%"; color: root.text; Layout.preferredWidth: 42 }
                Item { Layout.fillWidth: true }
                Button { text: root.tr("Wyczyść", "Clear"); onClicked: root.clearCanvas() }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumWidth: 0
            spacing: 10

        Rectangle {
            id: canvasFrame
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: 1
            Layout.fillHeight: true
            radius: 12
            color: root.surface
            border.color: root.muted
            border.width: 1
            clip: true

            Canvas {
                id: topRuler
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 28
                z: 2
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.fillStyle = String(root.surfaceRaised)
                    ctx.fillRect(0, 0, width, height)
                    ctx.strokeStyle = String(root.muted)
                    ctx.fillStyle = String(root.text)
                    ctx.font = "10px sans-serif"
                    var origin = 32 + canvas.x * root.zoom - viewport.contentX
                    var step = 50 * root.zoom
                    for (var value = 0; value <= root.documentWidth; value += 50) {
                        var x = origin + value * root.zoom
                        if (x < 32 || x > width) continue
                        var tick = value % 100 === 0 ? 16 : 9
                        ctx.beginPath(); ctx.moveTo(x, height); ctx.lineTo(x, height - tick); ctx.stroke()
                        if (value % 100 === 0) ctx.fillText(String(value), x + 3, 11)
                    }
                }
            }

            Canvas {
                id: leftRuler
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                width: 28
                z: 2
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.fillStyle = String(root.surfaceRaised)
                    ctx.fillRect(0, 0, width, height)
                    ctx.strokeStyle = String(root.muted)
                    ctx.fillStyle = String(root.text)
                    ctx.font = "10px sans-serif"
                    var origin = 28 + canvas.y * root.zoom - viewport.contentY
                    for (var value = 0; value <= root.documentHeight; value += 50) {
                        var y = origin + value * root.zoom
                        if (y < 28 || y > height) continue
                        var tick = value % 100 === 0 ? 16 : 9
                        ctx.beginPath(); ctx.moveTo(width, y); ctx.lineTo(width - tick, y); ctx.stroke()
                        if (value % 100 === 0) {
                            ctx.save(); ctx.translate(11, y + 3); ctx.rotate(-Math.PI / 2)
                            ctx.fillText(String(value), 0, 0); ctx.restore()
                        }
                    }
                }
            }

            Flickable {
                id: viewport
                anchors.fill: parent
                anchors.topMargin: 28
                anchors.leftMargin: 28
                anchors.rightMargin: 10
                anchors.bottomMargin: 10
                clip: true
                contentWidth: Math.max(width, root.documentWidth * root.zoom)
                contentHeight: Math.max(height, root.documentHeight * root.zoom)
                interactive: false
                boundsBehavior: Flickable.StopAtBounds

                Canvas {
                    id: canvas
                    width: root.documentWidth
                    height: root.documentHeight
                    x: Math.max(0, (viewport.width - width * root.zoom) / 2) / root.zoom
                    y: Math.max(0, (viewport.height - height * root.zoom) / 2) / root.zoom
                    scale: root.zoom
                    antialiasing: true
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    ctx.fillStyle = String(root.canvasBackground)
                    ctx.fillRect(0, 0, width, height)
                    if (rasterImage.status === Image.Ready)
                        ctx.drawImage(rasterImage, 0, 0, width, height)
                    ctx.save()
                    for (var i = 0; i < root.strokes.length; i++) root.drawStroke(ctx, root.strokes[i])
                    if (root.currentPoints.length > 0)
                        root.drawStroke(ctx, { points: root.currentPoints, tool: root.tool, color: String(root.ink), size: root.brushSize })
                    ctx.restore()
                    if (root.pendingFill) {
                        var fillRequest = root.pendingFill
                        root.pendingFill = null
                        var changed = root.floodFill(ctx, fillRequest.x, fillRequest.y, fillRequest.color)
                        if (changed > 0) {
                            // Keep the mutated frame alive until the paint
                            // callback has returned. Capturing synchronously
                            // here can produce a stale/empty image in Qt Quick.
                            root.pendingFillPixels = changed
                            fillCaptureTimer.start()
                        } else {
                            root.undoStack = root.undoStack.slice(0, root.undoStack.length - 1)
                            root.historyLabels = root.historyLabels.slice(0, root.historyLabels.length - 1)
                            root.statusText = "W tym miejscu nie ma obszaru do wypełnienia"
                        }
                    }
                    if (root.selectionRect) {
                        ctx.save()
                        ctx.globalAlpha = 1
                        ctx.strokeStyle = String(root.accent)
                        ctx.lineWidth = 2 / root.zoom
                        ctx.setLineDash([8 / root.zoom, 5 / root.zoom])
                        ctx.strokeRect(root.selectionRect.x, root.selectionRect.y,
                                       root.selectionRect.width, root.selectionRect.height)
                        ctx.setLineDash([])
                        ctx.fillStyle = String(root.accent)
                        var handleSize = 8 / root.zoom
                        var halfHandle = handleSize / 2
                        var handlePoints = [
                            [root.selectionRect.x, root.selectionRect.y],
                            [root.selectionRect.x + root.selectionRect.width, root.selectionRect.y],
                            [root.selectionRect.x, root.selectionRect.y + root.selectionRect.height],
                            [root.selectionRect.x + root.selectionRect.width, root.selectionRect.y + root.selectionRect.height]
                        ]
                        for (var h = 0; h < handlePoints.length; h++)
                            ctx.fillRect(handlePoints[h][0] - halfHandle, handlePoints[h][1] - halfHandle, handleSize, handleSize)
                        ctx.restore()
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    preventStealing: true
                    hoverEnabled: true
                    onPressed: {
                        if (root.tool === "fill") {
                            root.addFillAt(mouse.x, mouse.y)
                            return
                        }
                        if (root.tool === "select") {
                            var resizeCorner = root.resizeHandleAt(mouse.x, mouse.y)
                            if (resizeCorner && root.selectedIndices.length > 0) {
                                root.remember("Zmień rozmiar zaznaczenia")
                                root.scalingSelection = true
                                root.scaleCorner = resizeCorner
                                root.scaleStart = { x: mouse.x, y: mouse.y }
                                root.scaleOriginalRect = { x: root.selectionRect.x, y: root.selectionRect.y,
                                                           width: root.selectionRect.width, height: root.selectionRect.height }
                                root.scaleOriginalStrokes = JSON.parse(JSON.stringify(root.strokes))
                                root.drawing = true
                                return
                            }
                            if (root.selectionRect && root.selectedIndices.length > 0 && root.pointInSelection(mouse.x, mouse.y)) {
                                // When objects overlap, clicking inside the
                                // current selection picks the topmost object
                                // under the pointer instead of moving the
                                // whole stack as one glued group.
                                var topmost = root.topmostObjectAt(mouse.x, mouse.y)
                                if (topmost >= 0 && (root.selectedIndices.length > 1 || root.selectedIndices.indexOf(topmost) < 0)) {
                                    root.selectedIndices = [topmost]
                                    root.selectionRect = root.boundsForStroke(root.strokes[topmost])
                                }
                                root.remember("Przenieś zaznaczenie")
                                root.movingSelection = true
                                root.moveStart = { x: mouse.x, y: mouse.y }
                                root.moveOriginalRect = { x: root.selectionRect.x, y: root.selectionRect.y,
                                                          width: root.selectionRect.width, height: root.selectionRect.height }
                                root.moveOriginalStrokes = JSON.parse(JSON.stringify(root.strokes))
                                root.drawing = true
                                return
                            }
                            root.selectionStart = { x: mouse.x, y: mouse.y }
                            root.selectionEnd = root.selectionStart
                            root.drawing = true
                            root.selectionRect = null
                            root.addPoint(mouse.x, mouse.y)
                            return
                        }
                        if (root.tool === "text") {
                            root.selectionStart = { x: mouse.x, y: mouse.y }
                            root.selectionEnd = root.selectionStart
                            root.selectionRect = { x: mouse.x, y: mouse.y, width: 1, height: 1 }
                            root.drawing = true
                            return
                        }
                        root.remember("Draw " + root.tool)
                        root.drawing = true
                        root.currentPoints = []
                        root.addPoint(mouse.x, mouse.y)
                    }
                    onPositionChanged: {
                        if (pressed && root.drawing && root.scalingSelection) {
                            root.scaleSelectedTo(mouse.x, mouse.y)
                        } else if (pressed && root.drawing && root.movingSelection) {
                            root.moveSelectedTo(mouse.x, mouse.y)
                        } else if (pressed && root.drawing && root.tool === "select") {
                            root.selectionEnd = { x: mouse.x, y: mouse.y }
                            root.selectionRect = { x: Math.min(root.selectionStart.x, mouse.x), y: Math.min(root.selectionStart.y, mouse.y), width: Math.abs(mouse.x - root.selectionStart.x), height: Math.abs(mouse.y - root.selectionStart.y) }
                            canvas.requestPaint()
                        } else if (pressed && root.drawing && root.tool === "text") {
                            root.selectionEnd = { x: mouse.x, y: mouse.y }
                            root.selectionRect = { x: Math.min(root.selectionStart.x, mouse.x),
                                                   y: Math.min(root.selectionStart.y, mouse.y),
                                                   width: Math.abs(mouse.x - root.selectionStart.x),
                                                   height: Math.abs(mouse.y - root.selectionStart.y) }
                            canvas.requestPaint()
                        } else if (pressed && root.drawing) root.addPoint(mouse.x, mouse.y)
                        else if (!pressed) root.statusText = Math.round(mouse.x) + " × " + Math.round(mouse.y)
                    }
                    onWheel: function(wheel) {
                        var point = viewport.mapFromItem(canvas, wheel.x, wheel.y)
                        root.zoomAt(point.x, point.y, wheel.angleDelta.y)
                        wheel.accepted = true
                    }
                    onReleased: root.scalingSelection ? root.finishScale() : (root.movingSelection ? root.finishMove() : (root.tool === "select" ? root.finishSelection() : (root.tool === "text" ? root.finishTextBox() : root.finishStroke())))
                    onCanceled: root.scalingSelection ? root.finishScale() : (root.movingSelection ? root.finishMove() : (root.tool === "select" ? root.finishSelection() : (root.tool === "text" ? root.finishTextBox() : root.finishStroke())))
                }
            }
        }
        Rectangle {
            id: historyPanel
            Layout.minimumWidth: 210
            Layout.preferredWidth: 210
            Layout.maximumWidth: 210
            Layout.fillHeight: true
            radius: 12
            color: root.surfaceRaised
            border.color: root.muted
            border.width: 1
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 8
                RowLayout {
                    Layout.fillWidth: true
                    Label { text: root.tr("Historia", "History"); color: root.text; font.bold: true; Layout.fillWidth: true }
                    Label { text: root.currentAction; color: root.muted; font.pixelSize: 11; elide: Text.ElideRight }
                }
                ListView {
                    id: historyList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    model: root.historyLabels.length > 0 ? root.historyLabels : [root.tr("Brak działań", "No actions yet")]
                    delegate: Label {
                        text: (root.historyLabels.length > 0 ? (index + 1) + ". " : "") + modelData
                        color: root.historyLabels.length > 0 && index === root.historyLabels.length - 1 ? root.accent : root.muted
                        font.pixelSize: 12
                        elide: Text.ElideRight
                        width: historyList.width
                    }
                }
            }
        }
        }
        Rectangle {
            Layout.fillWidth: true
            height: 26
            radius: 6
            color: root.surfaceRaised
            border.color: root.muted
            border.width: 1
            Label {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                verticalAlignment: Text.AlignVCenter
                text: root.statusText
                color: root.muted
                font.pixelSize: 12
                elide: Text.ElideRight
            }
        }
    }
}
}
