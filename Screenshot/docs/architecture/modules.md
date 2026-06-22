# Modules

The project is compiled as one application module. The “modules” below are logical components defined by ownership and dependency boundaries.

## System Overview

```text
Menu bar / global shortcut
          │
          ▼
    CaptureManager ────────────────┐
    │           │                  │
    ▼           ▼                  ▼
Capture       Preview       Standalone editor
overlays       panel
    │                              │
    ├── RegionSelection            ├── AnnotationDocument
    ├── WindowDetector             ├── AnnotationToolbar
    └── in-place annotations       └── AnnotationCanvas
          │                              │
          └──────── Annotation models ───┘
                         │
                         ▼
              AnnotationEditorService
                         │
        ScreenCaptureKit / Core Image / pasteboard /
                 save panel / sharing services
```

## Application Shell

### `ScreenshotApp`

Responsibilities:

- initialize menu-bar-only application behavior;
- register the global shortcut;
- expose menu commands and the Settings scene; and
- route standard capture and reopen commands to `CaptureManager.shared`, and scrolling capture commands to `ScrollCaptureManager.shared`.

It does not own capture state. The process-wide capture managers outlive individual SwiftUI scene and window hierarchies.

## Capture Coordinator

### `CaptureManager`

`CaptureManager` is the standard window/region capture and completed-output workflow state machine. It is `@MainActor` because it owns AppKit windows, observable UI state, and task transitions.

Owned state:

- one `CaptureOverlayWindow` per active display, reduced to one retained window during editing;
- an optional preview panel and standalone editor window;
- active `WindowDetector` and shared `RegionSelection` instances;
- window-detection, capture, and keyboard-monitor lifetimes;
- the most recently completed image and capture frame; and
- the shared `AnnotationEditorService`.

Responsibilities:

- start, dismiss, and tear down capture sessions;
- create overlays for all current `NSScreen` instances;
- transition from window/region selection into in-place editing;
- hide overlays before ScreenCaptureKit takes an image;
- capture each intersected display and composite pieces into one sRGB image;
- render and dispatch copy, save, share, and finish actions;
- show the post-capture preview and standalone editor;
- retain the last completed image for reopening; and
- present capture errors.

### `ScrollCaptureManager`

`ScrollCaptureManager` owns the complete scrolling-capture workflow: selected-window overlays, detector and selection state, backdrop/control/thumbnail windows, input monitors, cancellable capture tasks, stable-frame capture, stitching, window-mask resizing, preview updates, and teardown. It passes only the completed image and original frame to `CaptureManager` so scrolling results use the shared standalone editor and latest-capture lifecycle.

### Scrolling capture components

- `ScrollCaptureStitcher` diffs each adjacent stable pair, merges changed components into one content region, uses a padded copy of that region for confidence-scored 2D translation matching, and places only newly exposed region rectangles at accumulated global canvas offsets. Full-window and inner-pane scrolling use the same composition path; pixels outside the content region are emitted once.
- `ScrollCaptureManager` captures the selected window through ScreenCaptureKit, observes horizontal or vertical user scrolling input, debounces it, waits for two stable frames, and submits accepted frames to the stitcher. It applies a nine-slice-resized selected-window alpha mask to the completed bitmap before presenting the editor through `CaptureManager`.
- `ScrollCaptureBackdropView` renders the selected-rectangle cutout in click-through per-display windows while scrolling remains under user control.

The implementation does not generate input, move the pointer, inspect application documents, or require Accessibility access. Capture remains selected-window-only, while stitching accepts horizontal, vertical, and combined 2D movement.

Concurrency model:

- public workflow methods and mutable state are main-actor isolated;
- structured `Task` values are retained so detection and capture can be cancelled;
- a capture UUID prevents an old task's cleanup from clearing a newer operation;
- short delays after hiding windows prevent overlays from appearing in captures.

Current coupling:

- overlay views call the singleton directly for capture and export actions;
- the manager constructs all AppKit/SwiftUI window bridges;
- export actions are represented by a private enum, so they are not a public module API.

## Capture Overlay

### `CaptureOverlayWindow` and `CaptureOverlayState`

The window is the AppKit boundary needed for capture UI across Spaces and full-screen apps. It is borderless, transparent, stationary, placed at screen-saver level, and allowed to become key without becoming main.

Its `@Observable` state holds:

- whether the overlay has entered editing mode;
- the optional window alpha mask; and
- the pixelated source image used by redaction annotations.

### `CaptureOverlayView`

Responsibilities:

- switch between selection and editing presentation;
- render hovered-window highlights and region selections;
- interpret click/drag gestures as window capture or region creation/move/resize;
- request an alpha mask for the highlighted window;
- host annotation creation, selection, deletion, undo/redo, Copy, and Finish; and
- position annotation controls relative to the selected capture rectangle.

State ownership:

- durable annotations are held by a local `AnnotationDocument`;
- draft annotation, selected IDs, marquee, current tool, and style values are SwiftUI `@State`;
- capture geometry is shared across display overlays through `RegionSelection`;
- edit readiness and captured assets come from the retained window's `CaptureOverlayState`.

The view does not call ScreenCaptureKit directly. It requests standard workflow operations from `CaptureManager` and scrolling operations from `ScrollCaptureManager`.

### `RegionSelection`

This `@MainActor @Observable` model owns one global AppKit-coordinate rectangle. Its interaction state machine supports:

- creating a rectangle from a drag origin;
- moving an existing rectangle;
- resizing from eight handles; and
- rejecting selections smaller than 2 × 2 points.

`RegionSelectionView` is a read-only renderer for this model.

### `WindowDetector`

This `@MainActor @Observable` service runs a cancellable polling loop:

- refresh ScreenCaptureKit windows every eight iterations;
- inspect pointer position every 75 ms;
- preserve Core Graphics front-to-back ordering;
- exclude the current process, non-layer-zero, transparent, off-screen, and very small windows; and
- publish the first eligible window under the pointer.

### `ScreenCoordinates`

This stateless utility is the single conversion boundary for the coordinate systems used by AppKit, ScreenCaptureKit, SwiftUI overlays, and per-display capture source rectangles. Capture and overlay code should use these functions instead of duplicating Y-axis inversions or display offsets.

## Annotation Domain and Editing

Annotation-domain Swift source is organized into sibling responsibility folders under `Annotation/`. These folders are source-organization boundaries inside the single application module; they do not create separate Swift modules.

### Annotation values

`Annotation` is an identity-preserving enum over:

- `ShapeAnnotation`: rectangle, rounded rectangle, ellipse, line, or arrow with color and line width;
- `TextAnnotation`: text, position, font family, size, weight, and color; and
- `BlurAnnotation`: a rectangle that displays a pixelated section of the source image.

The feature is labeled Redact in the UI, but its implementation is pixelation rather than blur or destructive removal.

Each concrete annotation is a feature boundary:

- `ShapeAnnotation/` contains the shape value, shape kinds, rendering view, selection geometry, translation, resizing, output scaling, and shape style operations.
- `TextAnnotation/` contains the text value, rendering and inline-input views, selection geometry, translation, resizing, output scaling, and text style operations.
- `BlurAnnotation/` contains the redaction value, pixelated rendering view, selection geometry, translation, resizing, and output scaling.

Concrete behavior belongs to these type folders. The shared `Annotation` enum preserves heterogeneous identity and dispatches common operations to the corresponding concrete value; it must not duplicate type-specific geometry or styling rules.

### Shared annotation core

`Shared/Core/` owns cross-type concepts:

- `Annotation` provides the heterogeneous collection boundary and common-operation dispatch;
- `AnnotationDocument` owns annotation storage and snapshot-based history;
- `AnnotationGeometryTransform` supplies common point and rectangle mapping used by concrete type operations; and
- `AnnotationTool` defines the tools exposed by both editing presentations.

`Shared/UI/` owns the composed annotation toolbar, tool buttons, selection outlines, marquees, and resize handles. `BasicAnnotation/` owns the general toolbar controls for undo/redo, optional zoom, Copy, and Finish. Shared UI may compose basic and concrete annotation controls, but concrete annotations do not depend on editor windows or capture workflow services.

### `AnnotationDocument`

This `@MainActor @Observable` reference owns annotations and undo/redo history. Each add or remove operation stores a full previous annotation array. Undo and redo therefore operate at annotation-operation granularity, not per gesture update or property change.

Editing operations include add, multi-select by intersection, delete, move, resize, and applicable style updates. Live transforms use document previews and commit one history entry when the gesture ends.

### Shared presentation

- `AnnotationToolbar` selects annotation tools and styles, then composes `BasicAnnotationControls` for undo/redo, optional zoom, Copy, and Finish.
- `BasicAnnotationControls` renders general editing operations that are not owned by Shape, Text, or Blur/Redaction.
- `ShapeAnnotationView`, `TextAnnotationView`, and `BlurAnnotationView` render concrete values from their corresponding feature folders.
- `AnnotationSelectionOutline` and `AnnotationSelectionMarquee` render selection feedback.
- `TextAnnotationInputView` manages focused inline text entry.
- `Editor/AnnotationCanvas` combines the base image, type-specific annotation views, redaction pixels, and optional selection UI. `AnnotationEditorService` also uses it for final rendering with selection UI disabled.

### In-place and standalone editors

`CaptureOverlayView` implements the in-place editor over the live desktop selection. `AnnotationEditorView` implements editing of the last completed image in a normal resizable window.

They intentionally share the annotation model, document, toolbar, and rendering primitives. Gesture handling and transient state are duplicated, so changes to editing behavior must currently be applied to both views.

Dependency direction inside `Annotation/` is:

```text
Overlay editor / standalone Editor
        → Shared/Core + Shared/UI + BasicAnnotation
        → ShapeAnnotation / TextAnnotation / BlurAnnotation

Shared Annotation dispatch
        → concrete type operations

Concrete annotation features
        ✕ Overlay
        ✕ CaptureManager / ScrollCaptureManager
        ✕ editor window lifecycle
```

## Rendering and Export

### `AnnotationEditorService`

Responsibilities:

- generate a full-image Core Image pixellation source at scale 14;
- render the base image and annotations with SwiftUI `ImageRenderer`;
- optionally apply a captured window alpha mask;
- copy an `NSImage` to the system pasteboard;
- encode and save PNG through `NSSavePanel`; and
- show `NSSharingServicePicker` for a rendered image.

Rendering preserves output pixel density by deriving the `ImageRenderer` scale from the source image representation.

The service is main-actor isolated because rendering and AppKit integrations are UI-bound.

## Preview and Reopen Flow

### `CapturePreviewWindow` and `CapturePreviewView`

The preview is a floating, nonactivating panel positioned near the bottom-right of the display containing most of the captured frame. It contains the completed image, opens the standalone editor when clicked, and can be dismissed from a hover control.

### `AnnotationEditorWindow` and `AnnotationEditorView`

The standalone editor is a normal titled, resizable document-style window. It edits the last completed bitmap with a new annotation document. Finish copies the newly rendered image and returns to the preview. Copy leaves the editor open.

Only the latest in-memory capture can be reopened. There is no persistent history or disk-backed document model.

## Settings and Shortcut

`ShortcutsSettingsView` configures the `KeyboardShortcuts.Name.capture` binding. The registered default is Command-1. `GeneralSettingsView` is informational and has no persisted preferences.

## Runtime Flows

### Window or region capture

1. A menu command or global shortcut calls `CaptureManager.start()`.
2. The manager clears reopenable state, creates a detector and shared selection, and opens one overlay per display.
3. Pointer movement updates the hovered window; dragging creates or adjusts a region.
4. A window click or Return on a valid region calls `finishCapture`.
5. The manager retains one overlay, hides all overlays, captures the selection, and enters in-place editing.
6. The user annotates and chooses Copy or Finish.
7. The manager hides the overlay, captures the current screen contents again, composites annotations, then performs the action.
8. Finish copies the result, closes capture UI, and shows the preview. Copy writes to the pasteboard and returns to editing.

The initial capture taken when editing begins supplies the redaction pixels. The final export takes a fresh capture, matching the in-place editing requirement that output reflect the screen at completion time.

### Reopen completed capture

1. Finish stores the rendered result and its frame before showing the preview.
2. Clicking the preview, or choosing Reopen Last Capture later, opens the standalone editor.
3. The standalone editor renders new annotations onto the stored bitmap.
4. Finish copies the new result and replaces the current preview image.

## Architectural Constraints

- Keep ScreenCaptureKit calls inside services, primarily `CaptureManager` and `ScrollCaptureManager`.
- Keep AppKit limited to application/window lifecycle and system integrations.
- Keep observable mutable UI state main-actor isolated.
- Preserve in-place editing inside the capture overlay; the standalone editor is only for completed captures.
- Do not introduce another dependency without a concrete need; Apple frameworks cover the current system integrations.
