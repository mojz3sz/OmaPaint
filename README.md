# OmaPaint

OmaPaint is a lightweight Paint-style drawing app built with Qt 6 and Qt Quick, designed to fit naturally into an Omarchy desktop while remaining usable on other Linux distributions.

## Preview

![OmaPaint preview](screenshot.png)

## Run

```bash
cmake -S . -B build
cmake --build build
./run-omapaint.sh
```

You can also install `org.omarchy.OmaPaint.desktop` into `~/.local/share/applications/`.

## Features

- Pen, pencil, marker, eraser, bucket fill, shapes, star, polygon and text tools
- Text boxes with wrapping and resize handles
- Movable and resizable image objects opened from PNG/JPEG/WebP files
- Layers with visibility and opacity controls
- Simple mode by default, with an optional Layers panel toggle for advanced workflows
- Selection, move, resize, cut, copy and paste
- Undo/redo history
- PNG export
- Canvas resizing and zooming with pointer-centered mouse-wheel zoom
- Rulers and an Omarchy theme-aware dark interface
- Polish, English and automatic system-locale interface modes

## Requirements

- Linux with Qt 6.2 or newer, Qt Quick, Qt Quick Controls and Qt Quick Dialogs
- CMake 3.21 or newer (qmake6 is also supported)
- An Omarchy desktop is optional; its active theme is used when available, otherwise OmaPaint uses default colors

## Packages

Packaging definitions are included in `packaging/` and `debian/`:

- Debian/Ubuntu: build from the repository root with `dpkg-buildpackage -us -uc`
- Arch/Omarchy: build with `makepkg -si packaging/arch/PKGBUILD`

The standalone Qt 6 application does not require Quickshell. Package definitions retain the current `0.5.1` metadata until the planned `0.6.0` release is prepared.

## License

This project is currently shared as-is. Add a license before redistributing it as a packaged application.
