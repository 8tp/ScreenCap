<p align="center">
  <img src="https://img.icons8.com/sf-regular-filled/96/228BE6/screenshot.png" alt="ScreenCap Logo" width="96" height="96">
</p>

<h1 align="center">ScreenCap</h1>

<p align="center">
  <strong>A free, native macOS screenshot & annotation app.</strong><br>
  The free, open-source alternative to paid screenshot tools.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS_14+-000000?style=flat-square&logo=apple&logoColor=white" alt="macOS 14+">
  <img src="https://img.shields.io/badge/swift-5.9+-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift 5.9+">
  <img src="https://img.shields.io/badge/license-MIT-blue?style=flat-square" alt="MIT License">
  <img src="https://img.shields.io/badge/dependencies-1-brightgreen?style=flat-square" alt="Dependencies: 1">
  <img src="https://img.shields.io/badge/size-~2MB-purple?style=flat-square" alt="Size ~2MB">
  <img src="https://img.shields.io/badge/network-none-gray?style=flat-square" alt="No network">
</p>

<p align="center">
  <em>No account. No subscription. No telemetry. Just screenshots.</em>
</p>

---

## Why ScreenCap?

|  | Paid Alternatives | macOS Built-in | **ScreenCap** |
|:--|:--:|:--:|:--:|
| Price | $29+/yr | Free | **Free** |
| Area capture with dimensions | Yes | No | **Yes** |
| Annotation editor | Yes | Markup only | **Yes** |
| Scrolling capture | Yes | No | **Yes** |
| Screen recording | Yes | Yes | **Yes** |
| OCR text extraction | Yes | No | **Yes** |
| Color picker | Yes | No | **Yes** |
| Pin to desktop | Yes | No | **Yes** |
| GIF export | Yes | No | **Yes** |
| Open source | No | No | **Yes** |
| Privacy (no network) | Varies | Yes | **Yes** |

---

## Features

### Capture
- **Fullscreen** -- Instant full-screen capture with flash & sound
- **Area Select** -- Crosshair overlay with live pixel dimensions, shift-to-square
- **Window** -- Hover to highlight, click to capture (with optional shadow)
- **Scrolling** -- Auto-scroll and stitch into a single tall image

### Record
- **Screen Recording** -- Full screen or selected area to MP4 (H.264)
- **GIF Export** -- Convert any recording to GIF with configurable FPS and size
- **Recording Toolbar** -- Floating pause/stop/timer controls

### Tools
- **OCR** -- Select a region, extract text to clipboard via Apple Vision
- **Color Picker** -- Magnifier loupe with hex/RGB, click to copy

### Edit
- **Annotation Editor** -- Arrow, rectangle, ellipse, line, text, freehand, highlight, blur/pixelate, numbered steps, crop
- **Undo/Redo** -- Full undo stack for all annotation actions
- **Export** -- Save as PNG, JPEG, or TIFF

### Extras
- **Floating Thumbnail** -- Post-capture preview with drag-and-drop to any app
- **Pin to Desktop** -- Always-on-top pinned screenshots with adjustable opacity
- **Launch at Login** -- Optional startup toggle from Preferences for installed app bundles
- **Toast Notifications** -- Non-intrusive confirmation messages

---

## Keyboard Shortcuts

| Shortcut | Action |
|:---------|:-------|
| `Ctrl+Shift+1` | Open the all-in-one capture toolbar |
| `Ctrl+Shift+3` | Capture Fullscreen |
| `Ctrl+Shift+4` | Capture Area |
| `Ctrl+Shift+5` | Capture Window |
| `Ctrl+Shift+6` | Capture Scrolling |
| `Ctrl+Shift+7` | Record Screen |
| `Ctrl+Shift+8` | Record Area |
| `Ctrl+Shift+9` | OCR Screen Region |
| `Ctrl+Shift+0` | Color Picker |

ScreenCap now defaults to a conflict-free shortcut profile on first launch so it does not fire alongside Apple's built-in screenshot shortcuts. You can switch to a `Cmd+Shift` compatibility profile in Preferences, but macOS screenshot shortcuts should be disabled first if you do.

---

## Installation

### Build from Source

```bash
git clone https://github.com/8tp/ScreenCap.git
cd screencap/ScreenCap
swift build -c release
```

### Open in Xcode

```bash
cd screencap/ScreenCap
open Package.swift
# Set signing to "Sign to Run Locally"
# Build and run (Cmd+R)
```

### Requirements
- macOS 14 (Sonoma) or later
- Xcode 15+ (for building)
- Screen Recording permission (prompted on first use)

---

## Architecture

```
ScreenCap/Sources/
  App/           App lifecycle, menubar, permissions
  Capture/       Screenshot engine, area/window/scroll capture, recording, GIF
  Editor/        Annotation editor, canvas, 10 drawing tools, background presets
  Tools/         OCR (Vision), color picker, magnifier
  UI/            Floating thumbnail, pin window, preferences, onboarding, toasts
  Utilities/     Global hotkeys, image I/O, user defaults
```

### Runtime Flow

1. `MenuBarController` receives menu and hotkey actions.
2. Capture actions route into `ScreenCaptureEngine`, `ScreenRecorder`, `ScrollCapture`, `OCRTool`, or `ColorPickerTool`.
3. Captures and recordings feed `FloatingThumbnailController`.
4. Thumbnails can open `AnnotationEditorController` or pin images to the desktop.
5. `PreferencesView` updates shared defaults and shortcut configuration.

### Tech Stack

| Layer | Technology |
|:------|:-----------|
| UI Framework | SwiftUI + AppKit |
| Screen Capture | ScreenCaptureKit / CGWindowListCreateImage |
| Recording | AVFoundation + AVAssetWriter |
| OCR | Vision (VNRecognizeTextRequest) |
| Image Filters | CoreImage (CIPixellate, CIGaussianBlur) |
| Global Hotkeys | [soffes/HotKey](https://github.com/soffes/HotKey) |
| Persistence | UserDefaults |

---

## Preferences

| Tab | Settings |
|:----|:---------|
| **General** | Save location, launch at login, image format (PNG/JPEG/TIFF), JPEG quality, clipboard/thumbnail/sound toggles |
| **Capture** | Capture delay, hide desktop icons, window shadow |
| **Shortcuts** | Switch between conflict-free `Ctrl+Shift` and macOS-style `Cmd+Shift` shortcut profiles |
| **Advanced** | Thumbnail position & duration, reset all |

---

## Privacy

ScreenCap makes **zero network calls**. Everything runs locally on your Mac. No accounts, no analytics, no tracking. Your screenshots never leave your machine.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

---

## License

[MIT](LICENSE) -- free for personal and commercial use.

---

<p align="center">
  <sub>Built with Swift, SwiftUI, and AppKit. One dependency. No compromises.</sub>
</p>
