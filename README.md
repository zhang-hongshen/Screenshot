# Screenshot

Native macOS screenshot utility with scrolling capture, PaperKit markup, Vision OCR and image collage.

## Features

- Capture a window or a selected region across displays.
- Annotate in place with PaperKit drawing, shapes and text, plus mosaic and text-erasing brushes.
- Stitch scrolling content vertically and horizontally, including multiple scroll areas.
- Extract text with Vision OCR and copy it to the clipboard.
- Rub over text with the eraser to remove it locally, with background repair and undo/redo in both markup editors.
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

Choose **Mosaic** to paint directly under the rectangular brush, or **Erase Text** to rub out text.
Both tools update the image during dragging, without selecting rectangles or showing processing controls. Repairs appear as you drag; newly visited
areas may take a moment to recognize. The size dropdown offers Small, Medium, Large and Extra Large brushes.
Selecting the tool changes the actual pointer throughout the editor window, including its toolbar, to a single
clearly outlined eraser. Leaving the window or changing tools restores the normal pointer. A complete drag is one
undo step. The window toolbar places zoom before the editing tools and Undo/Redo to their right;
⌘Z / ⇧⌘Z work with either raster brush selected. Right-click the image to Save or Share.
Copy, Save, Share, Finish and OCR all use the repaired image. Processing runs locally without additional dependencies.

Background repair uses interpolation for smooth backgrounds and nearby patches for textures, while trying
to preserve continuous table rules. Complex photos, irregular textures, unrecognized text and icons touching
text can leave remnants or repair artifacts; undo unwanted results and try a smaller stroke.
Text removal retains image snapshots for undo, so repeated edits on long captures use additional memory.

## Permissions and automatic scrolling

Capture requires Screen Recording permission. Automatic scrolling additionally requires Accessibility permission and a build with App Sandbox disabled; the current project enables App Sandbox. Manual scrolling capture remains available.

## Build from source

Open `Screenshot.xcodeproj` in Xcode, select the `Screenshot` scheme and My Mac, resolve its Swift packages, then build and run.

## Releases

Pushing an annotated version tag triggers the release workflow. Release titles contain only the version number; release notes contain only the numbered feature list from the tag body.

## License

See [LICENSE](LICENSE).
