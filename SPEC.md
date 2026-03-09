# Project: ScreenCap — A Free macOS Screenshot & Annotation Tool

## Prompt for Claude Code

You are building **ScreenCap**, a native macOS application in **Swift/SwiftUI** that serves as a free, open-source alternative to paid screenshot tools. It should be a single-binary menubar app with no account, no subscription, and no server dependency. Everything runs locally.

---

## 1. Architecture Overview

- **Language:** Swift 5.9+
- **UI Framework:** SwiftUI + AppKit (for low-level screen capture and overlay windows)
- **Minimum Target:** macOS 14 (Sonoma). Use `@available` checks where needed.
- **Build System:** Swift Package Manager (SPM). Single Xcode project, no CocoaPods.
- **Distribution:** Unsigned `.app` bundle the user can drag to `/Applications`.
- **Persistence:** UserDefaults for preferences. Screenshots saved to a user-configurable folder (default: `~/Desktop`).
- **No network calls.** Everything is offline and local.

---

## 2. App Lifecycle & Menubar

### 2.1 Menubar-Only App
- Set `LSUIElement = true` in Info.plist (no Dock icon).
- Display a small camera/crosshair icon in the macOS menu bar.
- Clicking the icon opens a dropdown menu with all capture options and recent captures.

### 2.2 Menubar Dropdown Items
```
┌─────────────────────────────┐
│  ⌘⇧3  Capture Fullscreen   │
│  ⌘⇧4  Capture Area         │
│  ⌘⇧5  Capture Window       │
│  ⌘⇧6  Capture Scrolling    │
│  ─────────────────────────  │
│  ⌘⇧7  Record Screen        │
│  ⌘⇧8  Record Area          │
│  ─────────────────────────  │
│  ⌘⇧9  OCR Screen Region    │
│  ⌘⇧0  Color Picker         │
│  ─────────────────────────  │
│  📌 Pin Last Capture        │
│  🕑 Recent Captures ▸       │
│  ─────────────────────────  │
│  ⚙ Preferences…            │
│  ⏻ Quit ScreenCap           │
└─────────────────────────────┘
```

### 2.3 Global Keyboard Shortcuts
- Register global hotkeys using `CGEvent` tap or `MASShortcut`-style approach.
- All shortcuts must be user-configurable in Preferences.
- Defaults shown above (⌘⇧3 through ⌘⇧0).

---

## 3. Core Features — Detailed Specs

### 3.1 Capture Fullscreen
- Capture the entire screen (or let user pick which display if multi-monitor).
- Use `CGWindowListCreateImage` with `kCGWindowListOptionOnScreenOnly`.
- Briefly flash the screen white (like macOS default) and play a camera shutter sound (toggleable in prefs).
- Auto-save to configured folder as PNG. Also copy to clipboard.
- Show a **floating thumbnail preview** (see §4) in the bottom-right corner for 5 seconds.

### 3.2 Capture Area (Region Select)
- Show a full-screen transparent overlay.
- User draws a rectangle by click-dragging. Show a crosshair cursor.
- Display live **pixel dimensions** (e.g., `1280 × 720`) near the selection box.
- While dragging, show a **magnifier loupe** at the cursor with a zoomed pixel grid and the hex color of the pixel under the crosshair.
- Allow the user to:
  - **Hold Space** to reposition the selection box.
  - **Hold Shift** to constrain to a square.
  - **Press Escape** to cancel.
- On release, capture the region, save, copy to clipboard, and show the floating thumbnail.

### 3.3 Capture Window
- When triggered, show a full-screen overlay. As the user hovers over windows, **highlight** the window under the cursor with a colored border/tint.
- On click, capture that window.
- Include the **window shadow** by default (toggleable in prefs) using `CGWindowListCreateImage` with `kCGWindowImageBoundsIgnoreFraming` + shadow option.
- Support capturing a specific **UI element** (like a dialog or popover) if the user holds `⌥` while clicking.

### 3.4 Scrolling Capture
- User selects a region on screen.
- App then auto-scrolls the content and captures sequential frames.
- Stitch frames into a single tall image using vertical image concatenation, with overlap detection (pixel matching on overlapping edges to avoid duplication).
- Implementation approach:
  1. Capture initial visible area.
  2. Send `CGEvent` scroll events to scroll down by a fixed increment.
  3. Capture again after a short delay.
  4. Use pixel-row comparison to find the overlap seam between consecutive frames.
  5. Trim overlap and concatenate vertically.
  6. Repeat until content stops scrolling (detected when two consecutive frames are identical).
- Save final stitched image as PNG.

### 3.5 Screen Recording
- Record the entire screen or a selected area to `.mp4` (H.264) or `.gif`.
- Use `AVFoundation` + `AVAssetWriter` with `CGDisplayStream` for capture.
- Show a **recording toolbar** floating at the top of the screen:
  ```
  [ ⏸ Pause ] [ ⏹ Stop ] [ 00:03:42 ] [ 🎤 Mic: On/Off ]
  ```
- Support **system audio capture** if permitted (via ScreenCaptureKit on macOS 13+).
- Support **microphone audio** overlay (toggleable).
- On stop, save the recording and show the floating thumbnail.
- GIF export: After recording, offer a "Save as GIF" option with configurable FPS (10, 15, 20) and max width.

### 3.6 OCR (Text Recognition)
- User selects a screen region (same flow as Area Capture).
- Run Apple's `VNRecognizeTextRequest` (Vision framework) on the captured image.
- Copy the recognized text to the clipboard immediately.
- Show a small **toast notification** confirming "Text copied to clipboard."
- Support multiple languages (whatever the system Vision framework supports).

### 3.7 Color Picker
- Show a full-screen overlay with a **magnifier loupe** centered on the cursor.
- Display the **hex color**, **RGB values**, and **HSL values** next to the loupe in a floating label.
- On click, copy the hex color (e.g., `#1A2B3C`) to the clipboard.
- Show a toast: "Copied #1A2B3C".
- Keep a history of the last 10 picked colors, viewable from the menubar → Recent Colors.

---

## 4. Floating Thumbnail Preview

After every capture (screenshot or recording), show a small thumbnail in the bottom-right corner of the screen:

```
┌──────────────────────┐
│  [thumbnail image]   │
│                      │
│  ✏️ Edit  📌 Pin  ✕  │
└──────────────────────┘
```

- **Click the thumbnail** → Open it in the built-in Annotation Editor (§5).
- **Drag the thumbnail** → Drag-and-drop the image into any app (Finder, Slack, Mail, etc.). Use `NSPasteboardItem` with the file URL.
- **"Edit" button** → Open the Annotation Editor.
- **"Pin" button** → Pin the screenshot as an always-on-top floating window (see §6).
- **"✕" button** → Dismiss the thumbnail.
- Auto-dismiss after 5 seconds if no interaction.
- The thumbnail window should have `level = .floating` and a subtle shadow + rounded corners.

---

## 5. Annotation Editor

When the user clicks "Edit" on a thumbnail (or opens a capture from "Recent Captures"), open a dedicated annotation window.

### 5.1 Editor Layout
```
┌──────────────────────────────────────────────────┐
│  Toolbar                                         │
│  [Arrow] [Rectangle] [Ellipse] [Line] [Text]    │
│  [Freehand] [Highlight] [Blur] [NumberedStep]   │
│  [Counter] [Crop] [Undo] [Redo]                 │
│                                                  │
│  Color: [● ● ● ● ●]   Size: [S M L]            │
├──────────────────────────────────────────────────┤
│                                                  │
│                                                  │
│              Canvas (captured image)             │
│                                                  │
│                                                  │
├──────────────────────────────────────────────────┤
│  [Copy to Clipboard]  [Save]  [Save As…]         │
└──────────────────────────────────────────────────┘
```

### 5.2 Annotation Tools

| Tool | Behavior |
|------|----------|
| **Arrow** | Draw arrows with customizable color and thickness. Click start point, drag to end. Arrowhead at the end. |
| **Rectangle** | Draw outlined or filled rectangles. Hold `Shift` for square. |
| **Ellipse** | Draw outlined or filled ellipses. Hold `Shift` for circle. |
| **Line** | Straight line. Hold `Shift` for perfectly horizontal/vertical/45°. |
| **Text** | Click to place a text box. Type text. Configurable font size and color. |
| **Freehand** | Freehand drawing with a smooth Bézier path. Pressure-sensitive if available. |
| **Highlight** | Translucent yellow (or chosen color) rectangle overlay — like a highlighter marker. |
| **Blur/Pixelate** | Draw a rectangle over an area to blur or pixelate it (for redacting sensitive info). Use `CIFilter.pixellate` or `CIFilter.gaussianBlur`. |
| **Numbered Step** | Click to place a numbered circle (auto-incrementing: ①, ②, ③…). Great for tutorials. |
| **Counter** | Similar to Numbered Step but smaller and pill-shaped, for labeling UI elements. |
| **Crop** | Drag to select a crop region, then apply. |

### 5.3 Editor Behavior
- All annotations are stored as objects on a layer above the base image (non-destructive until export).
- **Undo/Redo** stack (⌘Z / ⌘⇧Z) for all annotation actions.
- **Select and move** existing annotations by clicking them with the default pointer tool.
- **Delete** selected annotation with `Backspace`/`Delete`.
- When saving, flatten annotations onto the image.
- Export formats: PNG (default), JPEG, TIFF.

---

## 6. Pin to Desktop

- "Pin" creates a borderless, always-on-top `NSWindow` displaying the screenshot.
- The pinned image should be **resizable** by dragging corners.
- Slight drop shadow for visual separation from the desktop.
- Right-click on a pinned image shows: `[Copy] [Close] [Adjust Opacity ▸ 25% / 50% / 75% / 100%]`.
- Multiple screenshots can be pinned simultaneously.

---

## 7. Preferences Window

Build a SwiftUI-based Preferences window with these tabs:

### 7.1 General
- **Save location:** Folder picker (default: `~/Desktop`).
- **File naming format:** Dropdown with options like `Screenshot YYYY-MM-DD at HH.MM.SS`, `ScreenCap_timestamp`, or custom pattern.
- **Default format:** PNG / JPEG / TIFF.
- **JPEG quality** slider (if JPEG selected).
- **After capture:** Checkboxes for "Copy to clipboard", "Show floating thumbnail", "Play sound".
- **Launch at login** toggle.

### 7.2 Shortcuts
- A list of all actions with their current keybindings.
- Click a shortcut field → press new key combo → saves.
- "Restore Defaults" button.

### 7.3 Recording
- **Output format:** MP4 / GIF.
- **Video quality:** Low (720p) / Medium (1080p) / High (Retina native).
- **FPS:** 30 / 60.
- **GIF settings:** Max width, FPS, loop toggle.
- **Audio:** Checkboxes for "System audio" and "Microphone".
- **Show cursor in recording** toggle.

### 7.4 Advanced
- **Include window shadow in captures** toggle.
- **Hide desktop icons during capture** toggle (use `defaults write com.apple.finder CreateDesktop false && killall Finder` — and restore after).
- **Show magnifier during area select** toggle.
- **Thumbnail position:** Bottom-right / Bottom-left / Top-right / Top-left.
- **Thumbnail duration** slider (1–10 seconds).
- **Reset all settings** button.

---

## 8. Quick Access Overlay (Optional Enhancement)

When the user presses a single configurable hotkey (e.g., `⌘⇧X`), show a radial or grid overlay in the center of the screen with all capture modes as icons. User clicks one to activate. Dismiss with `Escape` or clicking outside.

This is a "nice to have" — implement only after all core features work.

---

## 9. Permissions & Entitlements

The app requires:
- **Screen Recording** permission (`NSScreenCaptureUsageDescription`).
- **Accessibility** access if using `CGEvent` taps for global hotkeys.
- **Microphone** access for recording with mic (`NSMicrophoneUsageDescription`).

On first launch, show a friendly onboarding window:
```
┌─────────────────────────────────────┐
│  Welcome to ScreenCap!              │
│                                     │
│  To work properly, we need a few    │
│  permissions:                       │
│                                     │
│  ✅ Screen Recording                │
│  ✅ Accessibility                   │
│  ✅ Microphone (optional)           │
│                                     │
│  [Open System Settings]  [Skip]     │
└─────────────────────────────────────┘
```

---

## 10. Technical Implementation Notes

### 10.1 Screen Capture
- Use `ScreenCaptureKit` (`SCShareableContent`, `SCStream`) on macOS 13+ as the preferred API for window/screen enumeration and capture.
- Fall back to `CGWindowListCreateImage` for older macOS support or when simpler is better.
- For window capture, enumerate windows with `CGWindowListCopyWindowInfo` and filter by `kCGWindowLayer == 0`.

### 10.2 Overlay Windows
- The area selection overlay should be a full-screen `NSWindow` with:
  - `level = .screenSaver` (above everything)
  - `backgroundColor = .clear`
  - `isOpaque = false`
  - `styleMask = .borderless`
  - A custom `NSView` that draws the dimming overlay, selection box, and crosshair.

### 10.3 Global Hotkeys
- Use `CGEvent.tapCreate` with `kCGHeadInsertEventTap` to intercept key events globally.
- Alternatively, use the `HotKey` Swift package (https://github.com/soffes/HotKey) for simplicity.
- Register/unregister on preference changes.

### 10.4 Image Stitching for Scrolling Capture
```swift
// Pseudocode for overlap detection
func findOverlap(imageA: CGImage, imageB: CGImage) -> Int {
    // Compare bottom N rows of imageA with top N rows of imageB
    // Use pixel buffer comparison with a tolerance threshold
    // Return the number of overlapping pixel rows
}
```

### 10.5 File Structure
```
ScreenCap/
├── Package.swift
├── Sources/
│   ├── App/
│   │   ├── ScreenCapApp.swift           // @main, NSApplication delegate
│   │   ├── MenuBarController.swift      // NSStatusItem and menu
│   │   └── AppPermissions.swift         // Permission checking/requesting
│   ├── Capture/
│   │   ├── ScreenCaptureEngine.swift    // Core capture logic
│   │   ├── AreaSelector.swift           // Region selection overlay
│   │   ├── WindowSelector.swift         // Window pick overlay
│   │   ├── ScrollCapture.swift          // Scrolling capture + stitching
│   │   ├── ScreenRecorder.swift         // Video recording
│   │   └── GIFExporter.swift            // MP4 → GIF conversion
│   ├── Tools/
│   │   ├── OCRTool.swift                // Vision framework OCR
│   │   ├── ColorPicker.swift            // Color picking overlay
│   │   └── MagnifierView.swift          // Loupe/magnifier component
│   ├── Editor/
│   │   ├── AnnotationEditor.swift       // Main editor window
│   │   ├── AnnotationCanvas.swift       // Canvas view with annotation rendering
│   │   ├── AnnotationTool.swift         // Protocol + tool implementations
│   │   ├── Tools/
│   │   │   ├── ArrowTool.swift
│   │   │   ├── RectangleTool.swift
│   │   │   ├── EllipseTool.swift
│   │   │   ├── LineTool.swift
│   │   │   ├── TextTool.swift
│   │   │   ├── FreehandTool.swift
│   │   │   ├── HighlightTool.swift
│   │   │   ├── BlurTool.swift
│   │   │   ├── NumberedStepTool.swift
│   │   │   └── CropTool.swift
│   │   └── UndoManager.swift
│   ├── UI/
│   │   ├── FloatingThumbnail.swift      // Post-capture preview
│   │   ├── PinnedImageWindow.swift      // Pinned screenshot window
│   │   ├── PreferencesView.swift        // Settings window
│   │   ├── OnboardingView.swift         // First-launch permissions
│   │   └── Toast.swift                  // Notification toasts
│   └── Utilities/
│       ├── HotkeyManager.swift          // Global shortcut registration
│       ├── ImageUtilities.swift         // Saving, format conversion
│       ├── FileNaming.swift             // Filename pattern generation
│       └── Defaults.swift               // UserDefaults keys/wrappers
└── Resources/
    ├── Assets.xcassets/                 // App icon, menubar icons
    └── Sounds/
        └── shutter.aiff                 // Camera sound effect
```

---

## 11. Build & Run Instructions

```bash
# Clone and build
git clone <repo>
cd ScreenCap
swift build -c release

# Or open in Xcode
open Package.swift
# Set signing to "Sign to Run Locally"
# Build and run (⌘R)
```

---

## 12. Implementation Priority

Build features in this order:

1. **Menubar app shell** — icon, dropdown menu, quit. Get the app lifecycle right.
2. **Fullscreen capture** — simplest capture mode. Validate save + clipboard.
3. **Area capture** — overlay, crosshair, region select, dimension display.
4. **Window capture** — hover highlighting, click to capture.
5. **Floating thumbnail** — post-capture preview with drag-and-drop.
6. **Annotation editor** — canvas + basic tools (arrow, rectangle, text, blur).
7. **Remaining annotation tools** — ellipse, line, freehand, highlight, numbered steps, crop.
8. **Preferences window** — all settings wired up.
9. **Global hotkeys** — register all shortcuts, make configurable.
10. **Pin to desktop** — always-on-top pinned images.
11. **Screen recording** — video capture + toolbar.
12. **GIF export** — convert recordings to GIF.
13. **OCR** — Vision framework text extraction.
14. **Color picker** — magnifier + hex copy.
15. **Scrolling capture** — auto-scroll and stitch.
16. **Onboarding flow** — permission requests on first launch.
17. **Polish** — animations, edge cases, multi-monitor support.

---

## 13. Design Principles

- **Fast.** The app should feel instant. Capture should happen in under 100ms after the user completes their selection.
- **Minimal UI.** No unnecessary chrome. The menubar menu and annotation editor are the only persistent UI.
- **macOS-native.** Use system colors, SF Symbols, native blur effects (`.ultraThinMaterial`). It should feel like it belongs on macOS.
- **Non-destructive.** Never modify the original capture file. Annotations create a new copy.
- **Keyboard-first.** Every action should be triggerable via keyboard.
- **Zero configuration needed.** Sensible defaults that just work out of the box. Power users can customize.

---

## 14. Key Dependencies (Keep Minimal)

| Dependency | Purpose | Notes |
|---|---|---|
| `HotKey` (soffes/HotKey) | Global keyboard shortcuts | Lightweight, well-maintained |
| Native `ScreenCaptureKit` | Screen/window capture | macOS 12.3+ built-in framework |
| Native `Vision` | OCR text recognition | macOS built-in framework |
| Native `AVFoundation` | Screen recording | macOS built-in framework |
| Native `CoreImage` | Blur/pixelate filters | macOS built-in framework |

No Electron. No web views. No heavy frameworks. Keep it lean and native.
