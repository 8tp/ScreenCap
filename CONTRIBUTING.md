# Contributing to ScreenCap

Thanks for your interest in contributing! ScreenCap is a community-driven project and we welcome contributions of all kinds.

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/YOUR_USERNAME/screencap.git`
3. Open the project: `cd screencap/ScreenCap && open Package.swift`
4. Create a branch: `git checkout -b feature/your-feature-name`

## Development Setup

- **Xcode 15+** required
- **macOS 14 (Sonoma)** minimum deployment target
- Set signing to "Sign to Run Locally" in Xcode
- Grant Screen Recording permission when prompted

## Project Structure

```
ScreenCap/Sources/
  App/         - App lifecycle, menubar controller, permissions
  Capture/     - Screenshot & recording engines
  Editor/      - Annotation editor, canvas, tools
  Tools/       - OCR, color picker, magnifier
  UI/          - Floating thumbnail, preferences, onboarding, toasts
  Utilities/   - Hotkeys, image utilities, defaults, file naming
```

## Guidelines

### Code Style
- Pure Swift/SwiftUI + AppKit. No Electron, no web views.
- Use SF Symbols for icons. Use system colors.
- Follow existing naming conventions in the codebase.
- No external dependencies beyond `soffes/HotKey`.

### Pull Requests
- Keep PRs focused on a single feature or fix.
- Include a clear description of what changed and why.
- Test on macOS 14+ before submitting.
- Ensure `swift build` passes without errors.

### Commit Messages
- Use present tense: "Add feature" not "Added feature"
- Be concise but descriptive
- Reference issue numbers where applicable

## Reporting Issues

- Use GitHub Issues for bug reports and feature requests
- Include macOS version and steps to reproduce for bugs
- Screenshots are always helpful

## Architecture Decisions

- **ScreenCaptureKit** is the primary capture API, with `CGWindowListCreateImage` as fallback
- All data stays local. No network calls, no telemetry, no accounts.
- Menubar-only app (`LSUIElement = true`). No Dock icon.
- UserDefaults for persistence. No Core Data.
