# AGENTS.md

This file is for every AI agent and human contributor working in this repository. Read it in full before making changes. If it conflicts with any other document, this file wins.

## Project Overview

Screenshot is a native macOS menu bar app for taking screenshots, targeting macOS 26+.

- **Capture**: click a window or drag a region; the selection can be moved and resized before capturing
- **In-place markup**: after selecting, the overlay itself becomes a PaperKit markup editor with Copy, Save, Share and Finish, so the user never leaves the screen they captured
- **Scrolling capture (the main feature)**: the user scrolls a window or region and the result shows it **as if it sat on an endless screen**. Every scroll area (sidebar, document, inspector) appears at its full length and width, side by side, with the window's toolbars and status bars around them
- **Preview and editor**: after Finish, a floating thumbnail appears; clicking it, or *Open Latest Capture*, opens the latest screenshot in a markup window
- **Collage**: normal screenshots pile up in the corner preview (at most 6). *Combine* opens a canvas where the user drags them into place (edges snap together); the result is the rectangle around them, transparent where nothing covers it, and opens in the markup window. Scrolling captures are shown on their own and never combined
- **Extract Text**: in either markup editor, *Extract Text* (⇧⌘C) reads the text in the screenshot (a selection or a long scrolling capture) with Vision and copies it, so chat logs, error alerts and documents need not be typed out
- Screenshots live only in memory, in the corner preview and the editor. No history, cloud or screen recording

## Design Principles

1. **Native first**: SwiftUI for UI, ScreenCaptureKit for pixels, PaperKit for markup, Vision for text, Core Graphics for image work, Accessibility only where scrolling needs it. The only third-party package is `KeyboardShortcuts` (global hotkeys and their recorder; the system's only built-in alternative is the old Carbon `RegisterEventHotKey`). Adding any other dependency needs the repository owner's approval.
2. **Never fight the user**: Screenshot never moves the pointer, never consumes the user's input and never synthesizes input during manual capture. It only watches.
3. **What you scrolled is what you get**: scrolling capture records exactly what the user scrolled through. Automatic scrolling must not make the page load more than it showed when capture started (see Known Issues).

## Architecture

All code lives in the app target, organized by folder. Folders are boundaries, not Swift modules.

```
Screenshot/
├── ScreenshotApp.swift   menu bar, global shortcuts, Settings scene, "markup-editor" WindowGroup
├── Capture/              selection overlay: CaptureWindow (one per display), CaptureView, RegionSelection
├── Markup/
│   ├── Core/             MarkupDocument (PaperMarkup + blur regions), layout math, toolbar metrics
│   └── UI/               PaperKit bridge (tool state), MarkupCanvasView, toolbar controls, blur overlay, MarkupEditorView
├── ScrollCapture/        everything for scrolling capture (see below)
├── Preview/              floating thumbnails after captures
├── Collage/              CollageArrangement (positions, snapping), CollageRenderer, CollageEditorView
├── Services/             CaptureManager, CaptureResultManager, ScreenCaptureService, ScreenCoordinates,
│                         WindowDetector, MarkupRenderer, TextRecognizer, ImageExportService, CaptureErrorPresenter
├── Settings/             Shortcuts and General (Open at Login) tabs
└── Extensions/           KeyboardShortcuts names, KeyCode constants
ScreenshotTests/          Swift Testing
```

- **CaptureManager** runs a normal capture: overlays on every display → selection → captures the region with the overlay hidden → turns the overlay under the pointer into the editor. Export captures the region **again** so the result shows the screen as it is at that moment, then renders markup on top.
- **CaptureResultManager** (`@Observable`) holds the latest finished image and the preview's images, and fits the preview panel to them. Normal captures are added (`addToPreview`), a scrolling capture replaces them (`showPreview`). The `markup-editor` window reads `latestImage` and gets a fresh editor (`.id`) for each new image; the `collage` window reads `previewImages`.
- **CollageArrangement** keeps each screenshot at its own pixel size and where the user dropped it (top-left origin). They start side by side; the dragged one comes to the front, and an edge within 8 screen points of another piece's edge snaps onto it. The collage is the union of all frames; `CollageRenderer` draws them on a clear canvas, so gaps stay transparent. While dragging, the canvas keeps the scale it had when the drag began.
- **ScreenCoordinates** is the only place that converts between AppKit (bottom-left origin, global), ScreenCaptureKit / Accessibility / `CGImage.cropping` (top-left origin) and overlay coordinates. Do not invert Y anywhere else.
- **MarkupRenderer** flattens image + blur regions + PaperKit markup (+ optional window alpha mask) at the source's pixel density.
- **TextRecognizer** reads the screenshot itself (not the markup, so blurred text is read too) with Vision's `RecognizeTextRequest` (accurate, language detected automatically). Vision shrinks what it reads, so an image taller than it is wide (at least 1000 px) is read in square strips that overlap by 200 px; a line belongs to the strip whose own rows hold its centre, so a line cut by one strip's edge is read whole by the next and never twice. Lines are joined in Vision's order, strip after strip.
- Managers are `@MainActor` singletons (`.shared`) because they own process-wide windows and event monitors that outlive any SwiftUI view.

### Scrolling Capture

```
ScrollCaptureManager        session: selection overlay, backdrop, control panel, live preview, event monitors
├── manual   ScrollCaptureCanvas      one ScrollCaptureStitcher per scrolled area
└── auto     ExpandedWindowCapture    ScrollArea (Accessibility) → ScrollAreaCapture per area
             both end in ExpandedWindowComposer → one image of the window on an "endless screen"
```

- **Manual** (default): from start until the user presses *Finish*, Screenshot watches **the picture, not the input**, so scroll wheel, trackpad, dragging a scroll bar and keyboard scrolling all count. While the picture moves, frames are captured **back to back** (so neighbouring frames always overlap): the next frame is taken (`async let`) while the current one is stitched off the main thread (`@concurrent`). While it stands still (`ScrollCaptureCanvas.Change.unchanged`), a frame is taken every ~50 ms more and the stitchers are skipped. Global scroll-wheel and key monitors are used only to leave Auto mode and for Escape. The live preview beside the capture (redrawn at most 10 times a second) shows the picture so far, outlines the part on screen, and warns when a frame moved too far to be joined. Region captures look up `SCShareableContent` once per session.
- **ScrollCaptureCanvas** finds what changed since the previous frame (`FrameComparison.changedRegions`). A change outside the known areas becomes a new area **only if its two frames line up as a scroll**, so spinners and hover effects are ignored. All new changes of a frame are tried together first (in a sparse view such as Finder's icon grid every icon is its own change, and one plain icon can line up at a wrong offset), then one by one, biggest first. A new area is then fitted to the whole scroll view (`FrameComparison.scrollViewRect`): a line belongs when it is plain background, when moving it explains its change (it leaves at most a tenth as many pixels wrong as changed), or when it is unchanged, mostly background and the same after the move (an icon's faint shadow). Edge columns across the move that do not belong are cut off first (the first changes include the moving scroll bar thumb), then the area extends outwards until a line stayed put with something drawn along most of it (divider, sidebar, scroll bar track, toolbar). Once the scroll view is covered, its content blurred under a Liquid Glass toolbar falls inside it and is ignored. Each area has its own stitcher, so areas can be scrolled in any order and in both directions. When Accessibility is already allowed, an area snaps to the app's real scroll-view frame.
- **ScrollCaptureStitcher** handles one area. Scrolling is a pure vertical or horizontal move, so each frame is squeezed by Core Graphics into row and column **profiles** (64 gray values per pixel row / column, stored line after line so one Accelerate call compares a whole overlap), and the move is a 1-D search: coarse (every 4th line, 16 values), then exact at full resolution around the 3 best coarse guesses and the last move (in a repeating grid a wrong offset can win the coarse search). The axis of the last move is tried first. Frames are shrunk in their own colour space before turning gray (`CGImage.smallGrayCopy`): colour-matching a full Retina frame to gray costs ~25 ms. Edges that do not move on the first move along an axis (sticky headers, status bars) are kept once; so are translucent bars (Liquid Glass toolbars), whose blurred lines change but do not line up after the move (at most a quarter of the area). A frame that matches better unmoved (a video playing) is not a move. Only the newly revealed strip of each frame is copied and kept, so memory follows the output size. Pairs that do not line up (mean difference > 3 gray levels, or up to 8 when the move still removes four fifths of the change, as with parallax cards; or less than 15 % overlap) are rejected without changing anything. Limit: 32,768 px per side. A 2800 × 1800 px frame takes about 20 ms in Release and 55 ms in Debug, including change detection (`FrameComparison`, whose small copy of the previous frame the canvas keeps).
- **ScrollCaptureFrameRecorder** (Debug builds only) saves every frame a manual capture hands to the canvas as `frame-NNNN.png` in `~/Library/Containers/com.zhanghongshen.Screenshot/Data/Library/Caches/ScrollCaptureFrames/<start time>/` (the folder is printed to the console). The canvas depends only on these frames, so a bad capture can be replayed exactly.
- **ExpandedWindowComposer** grows the window like a real resized window: it repeats one row/column inside each area's span (side-by-side areas share the growth), the last one that is plain outside the areas, so an unscrolled sidebar gets an empty gap instead of stretched text, draws each area at full size on its own background colour, and keeps toolbars above and status bars below. `WindowMask` then re-applies the window's rounded corners (nine-slice).
- **Auto** (window captures only, button *Auto*): `ScrollArea.areas(in:)` walks the target window's Accessibility tree for the outermost `AXScrollArea`s. Areas with scroll bars are moved by setting the scroll bar value (exact, learns the step size from the first measured move); areas without (some web views) get scroll-wheel events posted to the app's process, never moving the pointer. Each area is walked like a snake (down, right, up, right…), then scroll positions are restored.

## Build Configuration

- Settings live in Xcode; no xcconfig files. Bundle ID `com.zhanghongshen.Screenshot`, module `Screenshot`.
- Swift 5 language mode, default `@MainActor` isolation, Approachable Concurrency, `MemberImportVisibility`.
- App Sandbox and Hardened Runtime are enabled. **Accessibility (Auto mode, area snapping) does not work for sandboxed apps**; see Known Issues.
- Test images `ScreenshotTests/TestResources/*.jpg` are also members of the app target (synchronized-group exception).
- **Do not casually edit `project.pbxproj`.** Write the Xcode steps and hand them to the repository owner. New code goes straight into the synchronized `Screenshot/` folder.

## Build, Test and Run

```bash
xcodebuild -project Screenshot.xcodeproj -scheme Screenshot -destination 'platform=macOS' build
xcodebuild test -project Screenshot.xcodeproj -scheme Screenshot -destination 'platform=macOS'
```

The repository owner builds, runs and tests locally. In a sandboxed agent session, SwiftPM cannot resolve `KeyboardShortcuts`; type-check with `swiftc -typecheck` against a stand-in module instead, and say so in the reply.

## Coding Conventions

### Owner's Principles

These come first; every other convention serves them.

1. **A beginner can read it.** Plain Swift: `guard`, `switch`, `for` loops, concrete types. No clever tricks, no generics or protocols unless truly needed.
2. **Readable without comments.** Clear names explain the code. Every type gets one short `///` line saying what it is for; other comments only explain a *why* the code can't show.
3. **No over-engineering.** No protocols with one implementation, no layers "for later", no configuration nobody asked for. A new `Manager`/`Service` needs a real lifecycle or platform boundary of its own.
4. **Concise.** Short functions, short files, no duplicated code, no dead code.
5. **Newest stable APIs**: Observation (`@Observable`, `@State`, `@Bindable`), `Tab`, `onChange(of:) { old, new in }`, Swift concurrency. No `ObservableObject`, Combine or `DispatchQueue.main.async` for new code.
6. **Minimal tests.** See below.

### Naming and Files

- Spell names out (`index`, not `idx`); booleans read as assertions (`isEditing`, `opensAtLogin`); side-effecting methods are verbs.
- One primary type per file, named after it; extensions are `Type+Feature.swift`. Group longer files with `// MARK: -`.
- No `public`; mark file-local members `private`. 4-space indent, lines under ~120 characters, one parameter per line for long calls.
- Magic numbers that mean something get a name (`KeyCode.escape`, not `53`).

### SwiftUI and AppKit

- SwiftUI owns the content of every window. AppKit is used only where SwiftUI cannot do the job, and each use says why in its `///` line:

| Location | AppKit type | Reason |
|---|---|---|
| `CaptureWindow` | `NSWindow` | screen-saver level, one per display, joins all Spaces and full-screen apps |
| `CapturePreviewWindow`, `ScrollCaptureControlWindow`, `ScrollCaptureThumbnailWindow` | `NSPanel` | float above other apps without activating Screenshot; click-through thumbnail |
| `MarkupCanvasView` | `NSViewControllerRepresentable` | PaperKit only ships AppKit view controllers on macOS |
| `ImageExportService` | `NSSavePanel`, `NSSharingServicePicker`, `NSPasteboard` | system integrations |
| `ScrollCaptureManager`, `CaptureManager` | `NSEvent` monitors | watch keys and scrolling outside the app |

- Keep a view's `init` cheap; heavy work (pixelation, captures) goes in the model or `.task`.
- Prefer `$model.property` / `Bindable(model).property` over hand-written `Binding(get:set:)`.

### Testing

- Test only core logic: stitching, the scrolling canvas and composer, coordinate/compositor orientation, markup document and layout math, collage arrangement, text recognition strips.
- No tests for SwiftUI views, Apple frameworks, edge cases or input variations. One table-driven test beats many near-duplicates.
- Swift Testing only (`@Test`, `#expect`, `@testable import Screenshot`). Synthetic pictures are generated in code (`Pattern` in `ScrollCaptureTests`) so results are exact and repeatable.

## Hard Rules

1. Never move the pointer or consume user input. Posting scroll-wheel events is allowed only inside Auto mode, only to the captured app's process.
2. Never ship a capture that contains Screenshot's own overlays: hide them and wait before capturing, or exclude the app from the ScreenCaptureKit filter.
3. Request Accessibility permission only when the user presses *Auto*; manual capture must keep working without any permission except Screen Recording.
4. Do not add third-party dependencies or edit `project.pbxproj` without the repository owner.
5. Commit messages follow Conventional Commits (`feat(scroll): …`, `fix(markup): …`, `docs: …`).

## Progress

| Area | Status |
|---|---|
| Window/region capture, multi-display compositing | ✅ |
| In-place PaperKit markup, Blur regions, Copy/Save/Share/Finish | ✅ |
| Preview thumbnail, standalone markup window, Open at Login | ✅ |
| Extract Text (Vision OCR) in both markup editors | ✅ Code complete, strip math unit tested; **needs trying on real chats and long captures** |
| Collage of normal screenshots from the preview | ✅ Code complete, arrangement unit tested; **needs trying in the app** |
| Scrolling capture, manual, several areas, vertical + horizontal | ✅ Code complete, unit tested on synthetic frames; **needs trying on real apps** |
| Scrolling capture, automatic (Accessibility) | 🚧 First version; requires App Sandbox off; lazy-loading behaviour not solved |

## Markup Toolbar

- Every control is a native SwiftUI control: `MarkupToolControls` (Select / Draw / Blur picker, pen and width menu, `ColorPicker`, Shapes menu, Text), `ExtractTextButton` and `MarkupExportControls` (Copy, Save, Share). Their bodies have no container, so the window's `.toolbar` shows each as its own item; the capture overlay puts the same controls in a Liquid Glass capsule.
- PaperKit's own `MarkupToolbarViewController` is never shown. `MarkupEditorBridge` sets `drawingTool` / `indirectPointerTouchMode` on the markup controller directly and passes a hidden toolbar instance as the sender of PaperKit's insert-shape / text calls.

## Known Issues

- **Accessibility vs. App Sandbox**: sandboxed apps cannot use Accessibility on other apps, so *Auto* and area snapping do nothing while App Sandbox is on. Manual capture is unaffected (it finds areas from pixels). To try Auto: target *Screenshot* → Signing & Capabilities → remove *App Sandbox*, then allow Screenshot in System Settings → Privacy & Security → Accessibility.
- **Lazy loading in Auto mode**: scrolling an infinite feed to the end makes it load more. Open question: stop at the content length reported when capture starts (the scroll area's content element `AXSize`) and ignore anything appended later, or stop one screen before the end. Not implemented yet.
- While Auto runs or after it finished, manual watching is off; scrolling with the wheel, trackpad or keys switches back to manual, but dragging a scroll bar does not.
- Manual areas are found from changed pixels and grown over background and moved lines. Growth stops early at a line that stays put with something drawn on it inside the scroll view (a pinned watermark), or at empty margins whose colour differs from the view's background; later changes outside the area are ignored. Accessibility snapping fixes this when allowed. Growing costs about 90 ms (Release) for a 2800 × 1800 frame, once per new area.
- A few rows between an area and a glass bar below it (Finder's path bar) are covered by the bar's edge blur, stay outside the area and keep the first frame's content (e.g. the tops of the next icons).
- Animations, video, or content that changes while scrolling can make a pair fail to line up; such frames are skipped, not stitched wrongly. Parallax pictures (App Store cards) are stitched, but can show a seam inside the picture.
- Diagonal moves (2-D scrolling in maps or spreadsheets) are not matched; scroll one axis at a time.
- Overlay scroll bars appear in the frames while scrolling. Areas found from pixels leave them out, but an area snapped to the Accessibility frame includes them, which can leave pieces of the scroller along its right edge.
- A very fast flick can move more than a screen between two frames; the preview then asks the user to scroll back a little.
- Shape colour and line style use PaperKit's defaults; there is no inspector for a selected shape yet.
- Scroll-wheel Auto mode cannot restore the original scroll position, and can't tell whether a web view accepted the events.
- Making the final image of a very long capture takes a moment (about 0.2 s for 2800 × 5400 px).
- In-place editing uses one display-sized overlay; a selection spanning displays is captured correctly but edited only on one.
- Blur regions are not part of PaperKit's undo history.
- Collage pieces cannot be resized, and screenshots from displays with different pixel densities appear at different sizes.
- The preview panel floats above the collage window and can cover its bottom right corner.
- Extract Text gives no feedback beyond the clipboard: a beep when no text was found or Vision failed. Side-by-side areas of a scrolling capture (sidebar and document) are read strip by strip, so their lines interleave every strip. Very wide horizontal captures are read in one piece and small text may be missed. Mixed Chinese and English relies on Vision's automatic language detection.
- The `ScreenshotUITests` target still exists in the project but has no sources.
