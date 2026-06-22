# Decisions

## 2026-06

### SwiftUI First

Reason:
Native experience.

### Annotation Inside Overlay

Reason:
Avoid workflow interruption.

### ScreenCaptureKit

Reason:
Best macOS integration.

### Screen Capture Service Boundary

ScreenCaptureKit window acquisition and multi-display region compositing live in a stateless `ScreenCaptureService`. Capture managers own session state, window lifecycle, task cancellation, and result routing, but do not duplicate image-acquisition configuration or bitmap compositing.

Reason:
Keep platform capture mechanics cohesive and reusable while preserving distinct standard and scrolling workflow ownership.

### Completed Capture Result Boundary

The latest completed image and frame, preview panel, standalone editor window, reopen lifecycle, annotation rendering, and copy/save/share integrations are owned by `CaptureResultManager`. Standard and scrolling managers own their active capture sessions and hand completed images to this shared result boundary.

Reason:
Separate active capture orchestration from completed-output state and keep AppKit result presentation from accumulating in either capture workflow manager.

### Required AppKit Window Boundaries

Capture overlays remain custom `NSWindow` instances because they require one screen-saver-level, stationary, transparent window per display across Spaces. The scrolling toolbar, live thumbnail, and completed preview remain `NSPanel` instances because they require nonactivating, floating, click-through, or full-screen auxiliary behavior. The standalone editor remains an `NSWindow` because it must open on the display containing the capture and retain window-local Command-A routing.

SwiftUI continues to own the content of every window and panel. `CaptureErrorPresenter` owns modal capture-error alerts so AppKit activation and alert construction do not spread through workflow managers.

Reason:
SwiftUI scenes do not expose all required window levels, nonactivation, per-screen placement, collection behavior, or responder routing while preserving the current UI behavior.

### Annotation Features Own Their UI and Operations

Shape, Text, and Blur/Redaction are separate feature folders. Each folder owns
its value, specialized SwiftUI views, selection geometry, transforms, output
scaling, and applicable style mutations.

Cross-type document history, common geometry primitives, tool definitions, and
shared controls remain under `Annotation/Shared`. Editor presentations depend on
these feature boundaries and must not reimplement concrete annotation behavior.

Reason:
Keep behavior for each annotation type cohesive and prevent concrete geometry,
rendering, and styling rules from accumulating in editor views or the shared
annotation enum.

### Basic Annotation Controls Boundary

General editing operations that are not specific to Shape, Text, or Blur/Redaction live under `Annotation/BasicAnnotation`. This currently includes the composed controls for undo/redo, zoom, Copy, and Finish. Concrete annotation features, shared cross-type infrastructure, and editor presentation remain sibling folders under `Annotation`.

Reason:
Keep basic editing actions cohesive without placing the entire annotation domain inside a generic container or assigning general actions to a concrete annotation type.

### Manual Scrolling Capture

Scrolling capture accepts a selected window, records the first frame through ScreenCaptureKit, then observes vertical wheel, trackpad, and navigation-key input. After input pauses, it captures pairs of frames until the target is visually stable. Adjacent stable frames are aligned by visual overlap and only new content is appended.

Reason:
Manual window scrolling keeps the target application and pointer under user control, avoids Accessibility permission, and supports the primary webpage, document, PDF, and list use cases without requiring the user to identify an internal viewport.

### Unified Image-Space Scrolling Stitcher

Every adjacent stable frame pair follows one image-space pipeline: diff the pair, merge changed components into a scrolling content region, pad that region for matching, estimate a confidence-scored `(dx, dy)`, and place newly exposed rectangles at the accumulated global canvas origin. Near-full-frame change is represented by a full-image content region rather than a separate whole-page mode. Partial panes, horizontal movement, vertical movement, and diagonal/grid movement therefore share the same state and compositor. Low-confidence pairs do not mutate the canvas.

Reason:
A single spatial model avoids duplicated whole-page and inner-pane heuristics, keeps fixed chrome from being repeated, and permits multiple movement directions without assuming that new pixels always belong below or to the right of the previous frame.

### Cursor-Independent Automatic Scrolling

Superseded by Manual Scrolling Capture for the current implementation.

Selected-window scrolling capture may inspect descendant Accessibility scrollbars and set writable scrollbar values directly. Vertical and horizontal groups are captured in separate passes and combined into one output. No mouse event is generated and the pointer remains entirely under user control. Manual scrolling remains the fallback for region capture, denied Accessibility permission, or applications that do not expose writable scrollbars.

Reason:
Direct scrollbar values can automate scrolling without moving or monopolizing the pointer. Keeping this integration in a focused service prevents Accessibility traversal from spreading into capture UI and preserves the existing ScreenCaptureKit image path.
