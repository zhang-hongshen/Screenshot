# Current Implementation State

Status date: 2026-06-22

Screenshot is a functioning native macOS menu bar application with window capture, region capture, scrolling capture, in-place annotation, clipboard output, post-capture preview, and an in-memory reopen editor. The implementation is compact and SwiftUI-first, with AppKit used for overlay/panel windows and system integrations.

Annotation source is organized by responsibility. `BasicAnnotation` owns general editing operations such as undo/redo, zoom, Copy, and Finish. Shape, Text, and Blur/Redaction folders each contain their model, specialized UI, and type-specific geometry, scaling, and style operations. Cross-type document/history, tool, and shared selection UI lives under `Shared`, while the standalone presentation lives under `Editor`.

## Platform and Build

- Main target: `Screenshot`
- Deployment target: macOS 15.0
- UI: SwiftUI with targeted AppKit window wrappers
- Capture: ScreenCaptureKit
- Shortcut dependency: KeyboardShortcuts 3.0.1
- Application mode: menu bar accessory app
- Sandbox and Hardened Runtime: enabled
- Persistence: KeyboardShortcuts preference only; captures and annotation documents are in memory

## Implemented Feature Matrix

| Area | Current behavior | Status |
| --- | --- | --- |
| Menu bar | Capture, Reopen Last Capture, Settings, and Quit commands | Implemented |
| Global shortcut | Configurable recorder with Command-1 default | Implemented |
| Overlay lifecycle | One screen-saver-level overlay per display; Escape cancels | Implemented |
| Window detection | Highlights the frontmost eligible window under the pointer | Implemented |
| Window shape | Uses a ScreenCaptureKit alpha capture when available, with rounded-rectangle fallback | Implemented |
| Window capture | Click captures the hovered window's frame without cursor | Implemented |
| Region creation | Drag in global screen coordinates with live dimensions | Implemented |
| Region adjustment | Move and resize from eight handles; Return enters editing | Implemented |
| Multi-display capture | Captures intersected displays independently and composites at the highest display scale | Implemented |
| Scrolling capture | Captures a selected window after stable user-driven scroll pauses and spatially stitches adjacent frames with detected 2D offsets | Implemented |
| In-place editing | Retains an overlay and annotates over the selected live-screen region | Implemented |
| Shapes | Rectangle, rounded rectangle, ellipse, line, and arrow | Implemented |
| Text | Inline entry with font family, size, weight, and color controls | Implemented |
| Redaction | Rectangular pixelation using a precomputed source image | Implemented |
| Annotation selection | Select is the default tool; its marquee selects by intersecting bounds and Command+A selects all annotations | Implemented |
| Annotation deletion | Delete or Backspace removes every selected annotation; undo and redo include deletion | Implemented |
| Standalone annotation editor | Reopen completed captures; create, select, move, resize, restyle, and delete annotations with undo/redo | Implemented |
| Standalone editor zoom | Zoom In and Zoom Out change canvas magnification from 50% through 400% while preserving the visible editing area | Implemented |
| Copy | Copies the rendered result and keeps the editor open | Implemented |
| Finish | Copies the rendered result, closes capture UI, and shows a preview | Implemented |
| Save | PNG rendering and `NSSavePanel` service path exist | Not exposed in current UI |
| Share | `NSSharingServicePicker` service path exists | Not exposed in current UI |
| Preview | Floating thumbnail after successful Finish or Save; click opens editor | Implemented |
| Reopen | Reopens the latest completed in-memory image | Implemented |
| General settings | Informational text only | Partial |
| Permission guidance | No dedicated screen-recording permission flow or guidance UI | Not implemented |
| Capture history | Only one in-memory latest capture | Out of scope per PRD |

## Capture Behavior

### Starting and cancelling

Capture starts from the menu bar, Command-1 menu equivalent, or the configurable global shortcut. Starting a new session discards any preview, open editor, and stored last capture. Re-entrant starts are ignored while overlays, transitions, or capture tasks are active.

The manager creates one transparent `CaptureOverlayWindow` per current display. The shared `WindowDetector` and `RegionSelection` let the overlays present one global capture interaction. Escape cancels the active capture and tears down monitors, tasks, windows, and selection state.

### Window capture

`WindowDetector` combines ScreenCaptureKit window metadata with Core Graphics front-to-back ordering. It excludes the Screenshot process itself, off-screen windows, windows smaller than 40 points in either dimension, nonzero window layers, and transparent windows.

The hovered window receives an accent-color highlight. A separate ScreenCaptureKit capture supplies an alpha mask for accurate visible window shape; failures fall back to a rounded rectangle. A click with less than five points of movement selects the window.

### Region capture

A drag creates a region. Subsequent drags inside the region move it, and drags near one of eight handles resize it. The overlay displays point dimensions and accepts Return or keypad Enter when a valid region exists. Regions smaller than 2 × 2 points are discarded.

### Scrolling capture

Scrolling capture starts from the menu bar or its configurable Command-2 default shortcut. It reuses the normal multi-display overlay but accepts only a highlighted window click; region selection is disabled for this first version. After selection, the per-display overlays become click-through backdrops that retain the normal dimming outside the selected window while leaving it clear and interactive. The ScreenCaptureKit window alpha mask is carried into this backdrop, so its cutout follows the selected application's real rounded corners.

The first window frame is captured immediately with a desktop-independent ScreenCaptureKit window filter. Global monitors observe horizontal or vertical wheel and trackpad activity plus Space, Page Up, Page Down, and arrow keys. They never consume or generate input. After input pauses for 250 ms, capture takes consecutive frames 100 ms apart for up to six comparisons. A candidate is accepted only when two consecutive downsampled frames have a sufficiently small mean pixel difference, preventing active rendering from entering the stitch sequence.

`ScrollCaptureStitcher` uses one path for every adjacent accepted pair. It downsamples and diffs the pair, merges nearby changed components into one content region, treats near-full-frame change as a full-image region, and pads the region for matching without including that padding in composition. A coarse-to-fine luminance search estimates `(dx, dy)` only from changed evidence inside the region and produces a score and confidence. Accepted viewports accumulate global origins; the compositor removes their rectangular overlap and draws only newly exposed rectangles at the correct global position. This naturally handles vertical, horizontal, diagonal/grid, full-window, and inner-pane movement while emitting surrounding fixed pixels once. Each accepted pair records its content region, offset, overlap, new-content rectangles, score, and confidence. Low-confidence pairs return `noOverlap` without changing the canvas. Unchanged frames are ignored, capture is bounded to 100 frames, and each output dimension is capped at 32,768 pixels.

The scrolling control is a compact nonactivating toolbar containing only Cancel and Finish. Its panel is sized from the SwiftUI toolbar's actual fitting size instead of a hardcoded frame. It stays above the dimming backdrops, and the backdrop converts that exact panel frame into overlay coordinates and cuts it out as a capsule whose radius is half the measured height. The toolbar always shares the selection's horizontal center. It is centered inside the selection's top edge when the selection has enough room; for a small selection it moves above or below the selection. No thumbnail is shown before scrolling begins. After the first stable post-scroll frame is accepted, a separate click-through vertical live thumbnail appears outside the selection, with fixed width and growing height, preferring the right side before the left. The backdrops, toolbar, and thumbnail are excluded from the ScreenCaptureKit filter.

Finishing creates one in-memory image at the source capture scale and opens it in the existing standalone annotation editor. For selected-window scrolling captures, the original alpha mask is nine-slice resized across the stitched dimensions: corner pixels remain unchanged while opaque center and edge sections extend. The resized mask is alpha-composited onto the bitmap before it is used by the live thumbnail or editor, so the screenshot remains visible and capture presentation, editing, Copy, and Finish share the same rounded silhouette. Capture never finishes because scrolling stops or repeated frames are unchanged. Only the Finish button completes the capture; Escape or Cancel discards it.

### Screen capture and compositing

`ScreenCaptureService` intersects the selected global AppKit rectangle with every available `NSScreen`, maps screens to `SCDisplay` values, and captures each display-local source rectangle. Pieces are drawn into an sRGB bitmap at the highest point-to-pixel scale among intersected displays. The cursor is excluded.

Overlay windows are ordered out and capture waits 100 ms before ScreenCaptureKit runs. Capture failures restore the retained window where possible and present an AppKit error alert.

`CaptureErrorPresenter` centralizes application activation and the modal AppKit error alert used by both capture workflows.

## In-Place Annotation

Selecting a window or region first triggers a capture used as the redaction source, then returns the retained overlay to editing mode. The selection can still be adjusted; resizing a window-derived selection clears its alpha mask and converts presentation to rectangular region editing.

Available tools:

- Select: the default tool; drag a marquee to select annotations or press Command+A to select all, then press Delete or Backspace to remove the selection.
- Shape: rectangle, rounded rectangle, ellipse, line, or arrow.
- Text: click to place a focused field, then submit text.
- Redact: drag a rectangle that reveals a pixelated version of the initial captured image.

Available styles include a fixed color palette, line widths from 1 to 12 points, installed font families, font sizes from 8 to 144 points, and regular/semibold/bold weights.

Undo and redo use whole-array snapshots. The overlay records add and delete operations. The standalone editor also records style, move, and resize operations when committed; live transforms preview without creating a history entry for every pointer update.

Selection outlines and the active marquee are transient editing UI and are excluded from exported screenshots. Selection in the capture overlay remains intentionally limited: users can select and delete annotations, but cannot move, resize, edit text, reorder, or restyle an existing annotation. The standalone editor provides the fuller manipulation behavior described below.

## Output and Rendering

Final output is generated by a SwiftUI `ImageRenderer` over `AnnotationCanvas`. The renderer combines:

- the current source screenshot;
- shape and text annotations;
- rectangular portions of the pixelated image for redaction; and
- the window alpha mask for window captures.

Selection outlines and marquees are omitted from output. Renderer scale is derived from the source representation to retain pixel density.

The overlay toolbar currently exposes:

- Copy: takes a fresh capture of the selected screen region, renders annotations, copies the result, and restores the editor.
- Finish: takes a fresh capture, renders and copies it, closes the capture overlay, and shows the preview.

The fresh export capture means screen content can change between entering annotation mode and choosing Copy or Finish. Redaction pixels, however, come from the earlier capture taken when editing began.

PNG save and system sharing are implemented in `AnnotationEditorService` and wired through private manager actions, but neither overlay nor standalone toolbar currently exposes Save or Share controls. Successful Save would close the overlay and show a preview.

## Preview and Standalone Editor

Finish stores the completed image and original capture frame in memory, then displays a 360-point-wide floating preview near the bottom-right of the display with the largest overlap with the capture. The preview:

- appears across Spaces;
- opens the standalone editor when clicked; and
- shows a dismiss button while hovered.

The menu bar's Reopen Last Capture command opens the same editor after the preview is dismissed. The editor supports the same annotation creation tools, Copy, and Finish over the stored bitmap. Existing annotations can be selected directly or with a marquee, moved by dragging, resized from four corner handles, restyled with the applicable shape/text controls, and deleted. Multi-selection move, resize, restyle, and delete operations are supported. These mutations participate in undo and redo alongside annotation creation and deletion.

The editor starts a new annotation document each time; annotations from an earlier completed editing session are flattened into the stored image. Selection outlines, resize handles, and marquees are transient editor UI and are excluded from rendered output. Closing the editor does not discard the stored latest image. Starting a new capture does.

The standalone toolbar provides Zoom Out and Zoom In controls with a percentage indicator. Zoom uses discrete levels from 50% through 400% relative to the fitted canvas, adds two-axis scrolling when needed, and preserves the normalized center of the visible editing area when magnification changes. Annotation gestures continue to map through the displayed canvas size into image coordinates. Zoom is viewport-only state: Copy and Finish still render from the original image-coordinate annotations at the screenshot's original output dimensions and pixel density. The in-place capture overlay does not expose zoom controls.

## Settings

The Settings scene has two tabs:

- Shortcuts embeds KeyboardShortcuts recorders for standard capture and scrolling capture. Their defaults are Command-1 and Command-2, respectively.
- General explains that completed screenshots are copied and that editing occurs in the overlay.

There are no settings for output location, preview behavior, cursor capture, image format, or startup behavior. There is also no permission status or guidance UI.

## State and Concurrency

- `CaptureManager`, `ScrollCaptureManager`, `CaptureResultManager`, `ScreenCaptureService`, `WindowDetector`, `RegionSelection`, `AnnotationDocument`, and `AnnotationEditorService` are main-actor isolated, directly or through project-wide default isolation.
- `CaptureResultManager` owns the latest completed image and frame, preview/editor presentation, reopen state, annotation rendering, and output integrations shared by standard and scrolling capture.
- Observation uses `@Observable` for shared mutable models and SwiftUI `@State` for view-local editor state.
- Window detection and capture use retained cancellable tasks.
- `ScrollCaptureManager` owns scrolling selection, backdrop/control/thumbnail windows, ScreenCaptureKit frame capture, stitching, masking, and a cancellable debounce task plus global scroll and key monitors that are removed when the session finishes or is cancelled.
- Local AppKit key monitoring handles Return and Escape during capture. While the in-place editor is active, it also routes Delete/Backspace and Forward Delete to the selected annotations because the overlay canvas is not guaranteed to be the AppKit first responder.
- There is no background persistence, database, networking, or cloud integration.

## Known Limitations and Risks

- The selected rectangle can span displays and final bitmap compositing supports that case, but in-place editing retains only one display-sized overlay window. A selection extending beyond that display can be clipped or difficult to edit.
- Mixed-scale multi-display captures are composited at the highest scale. Lower-scale pieces are upscaled, and display color spaces are normalized into an sRGB canvas.
- Window detection is polling-based and refreshes shareable window metadata roughly every 600 ms; fast window changes can briefly leave stale highlighting.
- There is no explicit Screen Recording permission onboarding, status check, or recovery workflow.
- Save and Share are implemented below the view layer but are unreachable from current toolbars.
- Annotation gesture/state logic is duplicated between `CaptureOverlayView` and `AnnotationEditorView`, increasing the chance of behavioral drift.
- Annotation selection bounds for text are estimated from character count rather than measured layout.
- Standalone-editor resize supports four corner handles but not edge-only handles, rotation, or aspect-ratio locking.
- Existing text annotations can be moved, resized, and restyled, but their text content cannot be edited after creation.
- Undo/redo stores complete annotation arrays, which is simple but scales memory use with annotation count and history depth.
- Capture state is in memory only and is lost when the application exits.
- Scrolling capture currently supports selected windows only; region capture and automatic scrolling are not implemented.
- Overlap detection requires recognizable shared visual content. Animation, video, lazy loading, large scroll jumps, repetitive textures, or independently moving panes can cause a frame to be rejected.
- Manual scrolling is limited to 100 accepted frames and 32,768 pixels per output dimension.

## Test and Verification State

- `ScreenshotTests` contains only the generated empty example test.
- `ScreenshotUITests` contains generated launch and launch-performance tests without feature assertions.
- There are no automated tests for coordinate conversion, selection geometry, capture compositing, annotation history, rendering, shortcut behavior, or window lifecycle.
- Committed synthetic unit tests cover unchanged frames, a partial vertical pane, a partial horizontal pane, full-image diagonal movement, a multi-step 2D grid including negative movement, and low-confidence rejection without canvas mutation.
- ScreenCaptureKit behavior, permissions, multi-display layouts, Spaces/full-screen behavior, and pasteboard/save/share integrations require manual testing on macOS hardware.
- Manual scrolling capture still requires compatibility testing across browsers, document viewers, multi-pane apps, mixed-scale displays, sticky chrome, and real horizontal or mixed-direction input.

## Product Scope Alignment

The implementation aligns with the PRD's lightweight native capture workflow and its non-goals: there is no OCR, AI, screen recording, cloud sync, or capture history. Core window, region, and scrolling capture plus in-place annotation are present. The largest outstanding product requirements visible in the source are permission guidance, exposed Save/Share actions, complete annotation manipulation, and robust multi-display editing presentation.
