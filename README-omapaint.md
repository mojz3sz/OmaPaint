# OmaPaint

A small Qt 6/Qt Quick drawing app designed to feel at home beside Omacalc and Omawrite.

## Run

```bash
cmake -S . -B build
cmake --build build
./run-omapaint.sh
```

You can also launch `org.omarchy.OmaPaint.desktop` from a desktop menu after copying it to `~/.local/share/applications/`.

## Included

- Pen, pencil, marker, and eraser tools
- Palette swatches plus a custom color picker
- Brush size slider
- Undo/redo with `Ctrl+Z` and `Ctrl+Shift+Z`
- New canvas, clear canvas, PNG export with `Ctrl+S`
- Open PNG and common image files, then draw over them
- Layers panel with add/delete, visibility, opacity, and layer selection
- History panel with action labels and undo/redo tracking
- Line, rectangle, ellipse, five-point star, configurable polygon, and text tools
- Pixel rulers around the canvas
- Movable rectangular selections with `Ctrl+C`, `Ctrl+X`, and `Ctrl+V`
- Fill/bucket tool for enclosed areas
- Zoom with the slider or mouse wheel, centered on the pointer
- Omarchy theme-aware colors, loaded from the active theme
- Default colors on systems without Omarchy
