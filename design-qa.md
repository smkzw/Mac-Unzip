# Archive Workbench Design QA

- Source visual truth: `/Users/smkzw/Documents/AI Products/.worktrees/foundation/design/assets/adaptive-finder-media-visual-target-v3.png`
- Implementation screenshot: `/Users/smkzw/Documents/AI Products/.worktrees/foundation/.superpowers/sdd/task-6-visual/light-1487x1058.png`
- Accepted light implementation screenshot: `/Users/smkzw/Documents/AI Products/.worktrees/foundation/.superpowers/sdd/task-6-visual/light-iteration6-1487x1058.png`
- Viewport: normalized 1487 × 1058
- State: light appearance, media fixture, `首页主视觉.png` selected
- Full-view comparison evidence: both original-resolution images were loaded together in the same comparison input on 2026-07-11.
- Focused-region evidence: a separate crop was not required in this pass because toolbar text, sidebar rows, inspector metadata, main preview, all five strip items, and status text are legible at the shared 1487 × 1058 resolution.

## Findings — iteration 1

- [P1] Capture includes a large black desktop surround instead of the window-only composition.
  - Surface: layout, colors, polish.
  - Evidence: the source window fills the frame; the implementation is inset inside black margins.
  - Impact: proportions and Liquid Glass/window appearance cannot be judged faithfully.
  - Fix: crop the real window bounds before normalization, preserve rounded-corner transparency or a neutral desktop background, and do not scale the surrounding desktop into the target frame.

- [P1] Toolbar hierarchy does not match the approved Finder-style target.
  - Surface: layout, icons, copy, interaction affordance.
  - Evidence: implementation replaces back/forward with a sidebar toggle, shows a second `归档工作台` title, and hides the visible labels under `添加`、`解压缩`、`检测完整性`; the source has back/forward, one archive title/count block, and visible Chinese primary-action labels.
  - Impact: the header reads like a different app structure and primary actions are harder to scan.
  - Fix: remove the duplicate app title, restore native back/forward buttons, move sidebar toggling out of this slot, and show the three primary Chinese labels while keeping other utility actions icon-only with Chinese help/accessibility text.

- [P1] Main preview and media strip use the wrong vertical proportions.
  - Surface: spacing, layout, image quality.
  - Evidence: implementation leaves a large empty band above and below a short image; the source starts the image higher and gives it substantially more height before a compact strip.
  - Impact: the selected content is no longer the visual focus.
  - Fix: reduce top/bottom empty space, let the image fit the available center while preserving aspect ratio, and reserve a compact fixed-height strip/status region.

- [P2] Inspector is compressed into one gray card instead of the source's open vertical information rhythm.
  - Surface: spacing, shape/surfaces, typography.
  - Evidence: implementation groups all fields in a compact tinted rounded block; source uses plain stacked labels and values with larger vertical separation.
  - Impact: metadata hierarchy and native Finder resemblance drift.
  - Fix: remove the enclosing card treatment; use native section spacing, label/value hierarchy, and the source order across the full inspector column.

- [P2] Sidebar icon/color/weight treatment is too heavy.
  - Surface: color, typography, icons.
  - Evidence: unselected folders and item counts are black/bold; source uses blue folder symbols and lighter regular secondary counts.
  - Impact: navigation looks denser and less Finder-native.
  - Fix: use system-blue folder symbols, regular count weight, and selected-row foregrounds that remain legible under the system accent.

- [P2] Media-strip thumbnails are placeholder-like and the fifth item clips.
  - Surface: image quality, layout, content.
  - Evidence: three items are large black SF glyphs on gray boxes and `品牌指南.pdf` is clipped; source shows five complete differentiated thumbnails.
  - Impact: the media workflow feels unfinished and violates the selected target's content density.
  - Fix: use the real landscape raster for image/video-related thumbnails (with native play overlay for video), native document/icon treatment for SVG/PDF, reduce item width/gaps, and keep all five labels/sizes visible inside the center column.

## Required fidelity surfaces

- Fonts and typography: system font family is appropriate; title duplication, count weight, inspector hierarchy, and primary-action visible labels require correction.
- Spacing and layout rhythm: window crop, toolbar distribution, preview height, strip density, and inspector vertical rhythm require correction.
- Colors and visual tokens: system surfaces are appropriate; sidebar icons/counts and black capture surround require correction.
- Image quality and asset fidelity: main generated raster is sharp and directionally faithful; strip imagery is not yet faithful.
- Copy and content: filenames and inspector values match; duplicate app title and missing visible primary labels do not.

## Comparison history

- Iteration 1: six P1/P2 groups recorded above; no visual fixes accepted yet.
- Iteration 2: window-only capture and toolbar back/forward/visible primary labels improved, but the light-state screenshot regressed the core shell: sidebar and inspector collapsed to edge slivers, the main image became oversized/cropped, and the media strip overlaid the image instead of occupying its own region. This iteration is rejected and requires another light-state pass.
- Iteration 3: pinned sidebar and inspector widths restored; the full image fits, all five strip items are visible, the strip no longer overlaps content, and toolbar hierarchy remains improved. Remaining P2 drift: the preview begins about 38 px lower than the source and the strip thumbnails are slightly shorter; one more light-state sizing pass is required.
- Iteration 4: thumbnail sizing improved, but fixed-height pressure removed the required bottom status region and the main image remained about 48 px too low. This iteration is rejected; the next pass must move the image/strip stack upward by reducing pre-image flexible space while restoring the dedicated bottom status region.
- Iteration 5: the image/strip stack moved upward and preserved fidelity, but remained roughly 24 px below target and the bottom status was only partially visible. The next pass must remove the remaining top gap and pin the status region fully inside the window.
- Iteration 6: accepted for the light state. Pinned columns, toolbar hierarchy, full image, five-item strip, open inspector rhythm, and bottom status are all intact. The remaining roughly 15 px optical image-top drift is minor and below P2 severity.
- Variant pass 1: dark and Reduce Transparency states pass. Increase Contrast is rejected because the selected sidebar row overlaps the titlebar traffic-light controls and the inspector `信息` heading disappears; fresh-relaunch reproduction or a layout fix is required.
- Variant pass 2: the app-wide contrast transform causing the titlebar overlap was removed. The corrected Increase Contrast state preserves the toolbar, traffic lights, `信息` heading, pinned columns, strip, and status; it passes alongside dark and Reduce Transparency.
- Independent-review fixes, visual pass 3: dark, real-environment-wired Reduce Transparency, and Increase Contrast pass. The recaptured light state is rejected because an unexpected `归档工作台` window title reappeared and displaced the search field; deterministic title suppression/stabilization and a corrected light capture are required.
- User-observed toolbar/filename pass 4: accepted at default and 900 pt widths. The archive title stays inside the safe titlebar region, primary actions are `添加`/`解压缩`, `检测完整性` and other low-frequency actions moved into a visible Chinese `操作` menu, the ambiguous ellipsis control is gone, search remains trailing, and no system overflow chevron appears. Media filenames/sizes use plain single-line text below the thumbnail; their frames do not intersect each other or the rounded thumbnail selection frame. Final scheme and accessibility variants remain pending after these changes.
- Final variant pass 5: light, dark, Reduce Transparency, and 900 pt states pass. Increase Contrast is rejected because a custom horizontal border crosses the archive subtitle `84 项`; the top edge must be removed or moved below the complete toolbar/title region before final acceptance.
- Final variant pass 6: the redundant high-contrast top border was removed. Archive title/subtitle, traffic lights, toolbar, content separators, inspector, strip labels, and status remain distinct with no overlap; Increase Contrast now passes with the other accepted states.

## Implementation checklist

1. Correct window-only capture and toolbar structure.
2. Rebalance preview/strip/inspector/sidebar proportions and treatments.
3. Replace placeholder strip thumbnails and eliminate clipping.
4. Recapture the same light state and compare both full-resolution images together.
5. Only after light passes, capture dark, reduced-transparency, and increased-contrast states.

## Follow-up polish

- Recheck optical alignment of SF Symbols after the structural fixes.

final result: passed
