# Project Structure

This document describes the repository as implemented on 2026-06-22. The application is one native macOS target organized by feature folders; the folders are architectural boundaries, not separate Swift modules.

## Repository Layout

```text
Screenshot/
├── Screenshot.xcodeproj/              Xcode project and Swift package resolution
├── Screenshot/                        Main application target
│   ├── ScreenshotApp.swift            App entry point and menu bar commands
│   ├── Annotation/                    Annotation models, controls, and editor
│   │   ├── BasicAnnotation/           General undo, zoom, copy, and finish controls
│   │   ├── BlurAnnotation/            Redaction model, rendering, and operations
│   │   ├── ShapeAnnotation/           Shape model, rendering, types, and operations
│   │   ├── TextAnnotation/            Text model, input/rendering, and operations
│   │   ├── Editor/                    Standalone editor presentation
│   │   └── Shared/                    Cross-type core and shared controls
│   ├── Assets.xcassets/               App icon and accent color catalogs
│   ├── Extensions/                    KeyboardShortcuts name registration
│   ├── Overlay/                       Capture windows, selection state, and capture UI
│   ├── Preview/                       Post-capture thumbnail panel
│   ├── Services/                      Capture orchestration and system integrations
│   ├── Settings/                      Settings scene content
│   └── docs/                          Product, architecture, and implementation notes
├── ScreenshotTests/                   Swift Testing unit-test target
└── ScreenshotUITests/                 XCTest UI-test target
```

## Build and Target Structure

- `Screenshot` is the only application target. It builds the file-system-synchronized `Screenshot/` directory.
- `ScreenshotTests` and `ScreenshotUITests` are separate test targets. They currently contain only generated example and launch tests.
- The app targets macOS 15.0, uses an automatically generated Info.plist, enables App Sandbox and Hardened Runtime, and uses main-actor default isolation.
- `KeyboardShortcuts` 3.0.1 is the only third-party package. SwiftUI, AppKit, ScreenCaptureKit, Core Image, and Uniform Type Identifiers come from Apple frameworks.
- The application uses accessory activation policy, so it operates as a menu bar app without a normal Dock presence.

## Main Target

### Application entry point

`ScreenshotApp.swift` defines the `@main` SwiftUI application. It:

- switches the process to accessory activation policy;
- registers the global capture shortcut callback;
- provides Capture, Reopen Last Capture, Settings, and Quit menu bar commands; and
- owns the SwiftUI Settings scene.

### `Services/`

System-facing and workflow coordination code lives here.

- `CaptureManager.swift` is the main-actor singleton for standard window/region selection, capture tasks, in-place editing, and live-overlay export coordination.
- `ScrollCaptureManager.swift` is the main-actor singleton for scrolling-window selection, scrolling UI windows, input monitoring, stable-frame capture, stitching, masking, and scrolling-session teardown.
- `CaptureResultManager.swift` owns the latest completed image, preview and standalone editor windows, reopen lifecycle, annotation rendering, and copy/save/share integrations shared by both capture workflows.
- `CaptureErrorPresenter.swift` is the focused AppKit boundary for activating the application and presenting capture failures.
- `ScreenCaptureService.swift` owns stateless ScreenCaptureKit window acquisition and multi-display region compositing shared by the workflow managers.
- `WindowDetector.swift` polls ScreenCaptureKit shareable content and Core Graphics window ordering to identify the frontmost eligible window under the pointer.
- `ScreenCoordinates.swift` centralizes conversions among AppKit's bottom-left global coordinates, ScreenCaptureKit's top-left coordinates, per-screen source rectangles, and SwiftUI overlay coordinates.
- `ScrollCaptureStitcher.swift` verifies frame stability, detects pairwise changed-content regions, estimates confidence-scored 2D translations, and composites newly exposed rectangles at accumulated global canvas offsets.
- `AnnotationEditorService.swift` creates the pixelated source used for redaction, renders annotations into an image, and integrates with the pasteboard, save panel, and sharing picker.
- `Prompts.md` contains contributor prompt templates and is not part of the runtime.

### `Overlay/`

The capture overlay combines SwiftUI interaction with the small amount of AppKit required for full-screen system windows.

- `CaptureOverlayWindow.swift` defines the borderless, screen-saver-level window created once per display and its observable editing state.
- `CaptureOverlayView.swift` contains window/region capture interaction and the in-place annotation UI. It is the largest presentation component and holds per-overlay editing state.
- `RegionSelection.swift` is the observable model for creating, moving, and resizing a global capture rectangle.
- `RegionSelectionView.swift` renders outside dimming, borders, resize handles, dimensions, and Return-key guidance.
- `ScrollCaptureBackdropView.swift` keeps outside-selection dimming visible during manual scrolling without intercepting pointer input.
- `WindowHighlightView.swift` renders alpha-aware hovered-window highlighting and the corresponding editing mask.

### `Annotation/`

Source is organized by annotation feature and editing responsibility. Each concrete type folder owns its value, specialized UI, and type-specific operations.

- `BasicAnnotation/` owns general editing controls for undo/redo, optional zoom, Copy, and Finish.
- `ShapeAnnotation/` owns `ShapeAnnotation`, `ShapeType`, shape rendering, geometry transforms, scaling, and shape style mutations.
- `TextAnnotation/` owns `TextAnnotation`, text rendering/input, geometry transforms, scaling, and font/color mutations.
- `BlurAnnotation/` owns the pixelated-redaction value, rendering, geometry transforms, and scaling.
- `Shared/Core/` contains the unifying `Annotation` enum, `AnnotationDocument`, shared `AnnotationEditingSession`, common geometry transform primitives, and tool definitions. The enum dispatches to type-specific operations rather than implementing them itself.
- `Shared/UI/` contains controls and transient selection UI shared by all annotation types.
- `Editor/` contains the standalone editor window/view and the export-time `AnnotationCanvas` composition.

The standalone editor and overlay editor share annotation models, basic controls, rendering views, and a view-owned `AnnotationEditingSession` for tool/style, document/draft, text-entry, and selection state. Each presentation retains its distinct gesture mapping and presentation-specific transient state.

### `Preview/`

- `CapturePreviewWindow.swift` defines a floating, nonactivating AppKit panel that can appear across Spaces.
- `CapturePreviewView.swift` displays the completed image, opens the standalone editor on click, and shows a dismiss button on hover.

### `Settings/`

- `SettingsView.swift` defines General and Shortcuts tabs.
- `ShortcutsSettingsView.swift` embeds the `KeyboardShortcuts.Recorder` for the capture shortcut.
- `GeneralSettingsView.swift` currently contains informational text only.

### `Extensions/`

`KeyboardShortcuts.Name+.swift` registers the persisted `capture` shortcut and its default Command-1 binding.

### `Assets.xcassets/`

The asset catalog contains the global accent color and app icon sets. The app currently relies primarily on SF Symbols for interface icons.

## Documentation Structure

- `docs/product/PRD.md` defines product scope and non-goals.
- `docs/product/features/` contains feature-level goals and requirements.
- `docs/architecture/` records the source layout, module responsibilities, and architectural decisions.
- `docs/implementation/` records implemented behavior, known issues, and remaining work.
- `AGENTS.md` and `CODE_STYLE.md` define repository-specific contribution rules.

## Dependency Direction

The intended dependency flow is:

```text
ScreenshotApp
    → CaptureManager / ScrollCaptureManager
        → Overlay / Preview / Annotation windows and views
        → CaptureResultManager / CaptureErrorPresenter / WindowDetector / ScreenCaptureService / ScreenCoordinates
            → AnnotationEditorService
        → ScreenCaptureKit and AppKit integrations

Overlay and standalone editor views
    → Annotation models, document, toolbar, and renderers

Settings
    → KeyboardShortcuts
```

Views call `CaptureManager.shared` for standard capture/export actions and `ScrollCaptureManager.shared` for scrolling capture. Both workflow managers hand completed images to `CaptureResultManager`, which owns the shared latest-capture, preview, editor, and reopen lifecycle.
