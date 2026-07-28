# Visual Direction Decision

Date: 2026-07-11
Status: user-approved direction; corrected v3 target passed verified Gemini and Codex visual gates

## Decision

The user approved architecture Option A and selected a combination of visual directions 1 and 3:

- Normal document/code/mixed archives use a Finder-native list/outline workspace based on direction 1.
- Image/video-heavy folders or archives use the preview-driven workspace from direction 3.
- Direction 1 must be refined further toward native Finder information hierarchy and interaction behavior.

## Stable application shell

Both modes share the same window, toolbar, archive identity, sidebar, command model, selection model and staged-edit state. Switching modes must not open a second product surface or reset navigation.

- Native window titlebar and customizable toolbar.
- Finder-like sidebar groups and disclosure behavior.
- Breadcrumb/path context and Back/Forward navigation.
- Consistent search field and view-mode control.
- Welcome/create surfaces expose `打开` and `创建归档`; an open document toolbar exposes only contextual actions such as `添加`, `解压缩`, `检测完整性`, view, share/more and search.
- Consistent staged-edit/save/recovery model.

## Standard list mode

Default for ordinary and mixed archives.

- Finder-like hierarchical list/outline as the primary content surface.
- Columns: `名称`, `大小`, `压缩后大小`, `类型`, `修改日期` as availability/width permits.
- Sort, resize, reorder and show/hide columns; selection and disclosure follow macOS conventions.
- Right inspector/preview is resizable and collapsible.
- Quick Look preview does not reduce table legibility or cover rows.

## Media preview mode

Default recommendation only when the current folder is strongly media-dominant and the user has not already chosen a view for that archive. It is always manually selectable.

- Archive outline stays visible on the left.
- Large safe preview occupies the central surface.
- Current-folder media appears in an unlabeled bottom filmstrip/list that supports keyboard navigation and multiselection.
- Compact right inspector floats or docks without covering essential preview controls.
- Video preview uses native playback controls, never autoplay with sound, and never executes embedded content.
- The user can switch back to list mode immediately; the app remembers the chosen mode per archive/folder using a local view-state record, never by modifying the archive.

## Content-aware recommendation rules

The app may recommend media mode when at least 70% of visible non-folder entries are supported images/videos and there are at least four media entries. It must not silently switch after the user manually selects a mode. Unsupported, encrypted-without-password, huge or unsafe media remains represented by a normal file row/thumbnail placeholder and explicit state.

The threshold is a design hypothesis to test in user-perspective E2E; it is not a proven constant.

## Liquid Glass constraint

Liquid Glass is limited to the system titlebar/toolbar, sidebar, inspector edge, view-mode control and compact contextual overlays. The list, preview canvas and filmstrip remain content-first and legible. Reduce Transparency/Increase Contrast modes must preserve hierarchy without custom imitation glass.

## Next gate

Generate one revised combined visual target. After it is visible, use this decision and that visual as the basis for the full design specification. No UI code starts until the written specification has passed multi-model QC and user approval.

## QC-3 structural correction

The first combined mock was rejected as an implementation target after verified image-grounded review. The product direction remains unchanged, but the stable shell is corrected as follows:

- one archive sidebar only; no Finder-location sidebar plus second archive tree;
- main area is either the hierarchical list or media preview/filmstrip;
- inspector is optional and collapses first at narrow widths;
- no `更多文件…`, sidebar `+/-`, or visible filmstrip heading;
- no duplicate extract action and no always-visible `创建归档` inside an open document;
- operation history is a toolbar popover/independent window, not a date tree in navigation;
- archive and child counts must reconcile in the fixture.

`adaptive-finder-media-visual-target-v3.png` supersedes the earlier targets after verified image-grounded Gemini review and Codex original-resolution inspection.
