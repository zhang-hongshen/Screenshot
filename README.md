# Screenshot

Native macOS screenshot utility with scrolling capture, PaperKit markup, Vision OCR and image collage.

## Features

- Capture a window or a selected region across displays.
- Annotate in place with drawing, shapes, text and blur through PaperKit.
- Stitch scrolling content vertically and horizontally, including multiple scroll areas.
- Extract text with Vision OCR and copy it to the clipboard.
- Combine captures into an image collage, then copy, save or share the result.
- Configure global shortcuts and reopen the latest capture from the menu bar.

## Requirements

- macOS 26 or later.
- Xcode 27 or later to build from source.

## Installation

Download the DMG from [GitHub Releases](https://github.com/zhang-hongshen/Screenshot/releases), open it, and move Screenshot to Applications. For an ad-hoc signed build, macOS may require approval in System Settings → Privacy & Security.

## Getting started

1. Start Capture from the menu bar or your configured global shortcut.
2. Select a window or region, then annotate or extract text.
3. For a long image, start Scrolling Capture, scroll the content, then finish and export.

## Permissions and automatic scrolling

Capture requires Screen Recording permission. Automatic scrolling additionally requires Accessibility permission and a build with App Sandbox disabled; the current project enables App Sandbox. Manual scrolling capture remains available.

## Build from source

Open `Screenshot.xcodeproj` in Xcode, select the `Screenshot` scheme and My Mac, resolve its Swift packages, then build and run.

## Releases

Pushing an annotated version tag triggers the release workflow. Release titles contain only the version number; release notes contain only the numbered feature list from the tag body.

## License

See [LICENSE](LICENSE).
