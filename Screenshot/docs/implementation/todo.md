# Implementation Todo

`CaptureManager` now owns standard capture and output workflows, while `ScrollCaptureManager` owns the complete scrolling-capture workflow and state.
Stateless ScreenCaptureKit image acquisition and multi-display compositing now live in `ScreenCaptureService` rather than workflow managers.

## Completed

- Add `Annotation/BasicAnnotation` as the owner of general undo/redo, zoom, Copy, and Finish controls while keeping concrete annotation features, shared infrastructure, and editor presentation as sibling folders.
- Organize annotation source by concrete feature so Shape, Text, and Blur/Redaction each own their model, UI, and operations, with shared core/UI and standalone editor boundaries.
- Make Select the default annotation tool in both the capture overlay and standalone editor.
- Support marquee selection of one, multiple, or all annotations.
- Select all annotations with Command+A while Select is active.
- Delete all selected annotations with Delete/Backspace or Forward Delete while preserving undo/redo history, including explicit key routing in the in-place overlay.
- Exclude selection outlines and marquees from exported screenshots.
- Add scrolling capture from the menu bar and a configurable Command-2 default shortcut.
- Reuse highlighted-window selection for manual scrolling capture while disabling unsupported region selection.
- Support debounced horizontal or vertical wheel, trackpad, and navigation-key scrolling without consuming or synthesizing input.
- Capture consecutive ScreenCaptureKit frames after scrolling and accept the next frame only after visual stability is confirmed.
- Detect the changed content region in each adjacent stable pair and align it by a confidence-scored 2D translation.
- Keep stable pixels outside the detected content region once while expanding the content canvas by global frame placement.
- Exclude scrolling controls from captured frames and open the completed result in the existing standalone annotation editor.
- Keep scrolling controls responsive and mouse input available by excluding Screenshot windows from the ScreenCaptureKit filter.
- Retain click-through outside-selection dimming, keep a two-button toolbar at the selection's top center, and place an axis-aware live thumbnail outside the selection.
- Move the scrolling toolbar outside selections that cannot contain it, and defer thumbnail creation and axis-aware placement until scrolling begins.
- Keep the scrolling toolbar above the dimming backdrop and horizontally centered on the capture region in both inside and outside placements.
- Exclude the outside scrolling-toolbar capsule from the backdrop mask so translucent controls retain their undimmed appearance.
- Size the scrolling toolbar panel from its SwiftUI fitting size and use that exact rectangle for the backdrop cutout.
- Match the toolbar backdrop cutout to the measured capsule shape rather than exposing rectangular corners.
- Preserve the selected window alpha mask in the scrolling backdrop so its cutout matches the application's rounded corners.
- Apply the selected window's alpha mask to the stitched bitmap so rounded corners remain identical in capture, editor, preview, and export.
- Composite the resized window mask by alpha so the live thumbnail and final screenshot remain visible.
- Infer stable and changing pixels independently for every adjacent frame pair.
- Replace directional append heuristics with one pairwise diff and confidence-scored 2D translation pipeline.
- Place vertical, horizontal, and diagonal/grid frames by accumulated global canvas offsets while emitting unchanged surrounding pixels once.
- Record the detected content region, `(dx, dy)`, overlap, new-content rectangles, score, and confidence for every accepted pair.
- Reject low-confidence pairs without mutating the stitched canvas or fabricating a seam.
- Add committed synthetic unit coverage for unchanged frames, partial vertical and horizontal panes, full-image diagonal motion, multi-step 2D grids, and low-confidence rejection.
- Keep scrolling capture active through unchanged frames; only Finish completes it and only Escape/Cancel discards it.
- Add standalone-editor Zoom In and Zoom Out controls with centered, scrollable canvas magnification that remains independent of exported image geometry and quality.

## Annotation Editing

- Share gesture and transient editing state between the capture overlay and standalone editor to prevent behavioral drift.
- Bring move, resize, and restyle operations to selected annotations in the capture overlay without introducing a separate editor during capture.
- Allow the standalone editor to edit the content of an existing text annotation.
- Replace estimated text selection bounds with measured text layout bounds.
- Add edge resize handles and optional aspect-ratio locking where useful.
- Add unit tests for annotation translation, resizing, styling, selection geometry, and undo/redo transactions.

## Capture and Output

- Expose the implemented Save and Share actions in the relevant toolbars.
- Add explicit Screen Recording permission status, onboarding, and recovery guidance.
- Improve editing presentation for selections spanning multiple displays.
- Add output-pixel and size-limit coverage beyond the committed geometry/alignment tests.
- Add region-selection scrolling capture after the selected-window workflow is robust.

## Validation

- Add automated coverage for coordinate conversion and multi-display compositing.
- Add UI coverage for reopening a completed capture and manipulating annotations in the standalone editor.
- Add UI coverage for standalone-editor Zoom In and Zoom Out behavior and verify that zoom does not change Copy or Finish output dimensions or pixel density.
- Manually verify editor selection, move, resize, restyle, Copy, and Finish at standard and Retina image scales.
- Manually verify selected-window vertical, horizontal, and mixed-direction scrolling capture in browsers, documents, PDFs, lists, and multi-pane apps, including cancellation, dynamic content, keyboard scrolling, and Retina/mixed-scale displays.
