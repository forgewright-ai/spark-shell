# files v0 implementation handoff

Status: draft implementation PR. This initial commit contains requirements only; files v0 is not implemented or validated by this commit. Continue implementation on this PR branch. Leave the PR unmerged until owner approval.

Follow the [family guide](https://github.com/forgewright-ai/.github/blob/main/FAMILY.md) and repository conventions. The implementation team owns code structure, reuse and refactoring decisions.

Implement Files v0 in `forgewright-ai/spark-shell`: stable file browsing, explicit single- and dual-pane modes, reliable file operations and broad previews inside home. The composition is accepted as the design direction. Final spacing, density, minimum sizes and media placement must be validated in the native implementation.

# Shared contracts

Inherit the shared home implementation and current shared implementation for typography, theme, prompt, keyboard chips, mouse pointers, hover/focus, transitions, feedback, ASCII activity/progress and footer. Files does not introduce a separate progress or interaction system. Keep the marching indicator beside the action label and the full blank row between footer divider and controls.

Apply the shared interaction rules below. Check PR #213 before starting: apps is still open at handoff creation. Integrate its approved shared changes once available and avoid competing implementations. Super+Space is the configurable home default.

Use the local modular monolith with cohesive feature state and shared action handlers. Keep spark optional and separate from native file work. Existing local process boundaries may serve decoding or isolation; do not create microservices or network round trips for feature modules. The implementation team chooses reuse, refactoring and sequencing; no requirement freezes earlier stabilization code.

# Composition and space

- Single and dual pane are explicit user choices. Resizing never silently switches modes, changes selected columns or shrinks the configured font.

- Each pane retains its location, sorting, selection and scroll position. Name panes by their paths. Source and destination are roles for an operation, not permanent left/right labels.

- Header, prompt, action row, pane status and shared footer have stable positions. Allocate extra space primarily to filenames and visible file rows.

- Prefer compact shared chrome, aligned columns and restrained separators. No checkbox column, empty checkbox outlines, decorative cards or additional toolbars. The user-facing title and navigation label are exactly `files`, lowercase, consistent with `home` and `apps`. Actual filenames retain their original case.

- Offer an explicit compact column preset with name and size. Wider views can use the user's chosen additional metadata columns. Do not hide or rearrange them silently.

- If dual pane cannot remain usable, explain the limit and offer Single pane or Enlarge window. Preserve both pane states and keep the recovery controls accessible.

- Establish practical minimum widths in cells and heights in rows during implementation. Respect display scale, configured font size and actual compositor work area.

# Navigation and selection

Show the active pane through restrained accent treatment at its path. Use the shared subtle row background for focus. Mark selected files with a small borderless accent mark within the filename cell, without shifting filenames or allocating a separate selection column. Focus can move independently of marked files. Each pane reports only its own selection count. Follow the shared file activation rule: single click focuses, mark/modifier-click selects, Enter/double-click opens; hover never changes the authoritative target.

Keyboard, mouse and prompt invoke the same validated native actions. Make pane switching, selection, range selection, preview and file actions keyboard accessible. Exact bindings are implementation decisions after checking shared focus order and existing mappings. F3/F5/F6 and Insert in discussion are proposals, not final assignments; resolve Space against preview/playback/voice and Tab against shared control traversal. Render the configured shortcuts as clickable keycaps.

Keep filenames as stored, including case. Rows remain one line. Middle truncation preserves the beginning and extension; the full focused filename remains accessible through the fixed pane details area and an explicit full-name/path view. Copy path copies the original path. Do not change pane height to accommodate a long name. Fit the selection summary alongside the filename when possible without sacrificing access to the full name.

# Preview

Build on existing preview capabilities. Explicitly enabling preview uses the opposite pane, retains that pane's folder state and follows the focused file in the active list. Closing preview restores the previous folder view exactly. Keep pane boundaries and controls stable. Single-pane preview is explicitly entered and returns to the saved browsing state. Playback-control focus does not change the source file list. Copy/move continue to use that list's marked or focused files and the explicitly displayed destination, as defined in the shared contract.

Broad preview includes text, code, images, PDFs, supported Office/OpenDocument files, audio and video. Unsupported files receive useful metadata, a reason and Open with. Inspect actual format coverage before claiming support; archive content listing was discussed as a possible extension, not a reason to delay the core work.

Audio and video remain paused until Play. Changing the previewed file or closing preview stops playback and cancels obsolete work. Explicit fullscreen playback returns to the prior Files state. This is file inspection, not a background music-player workflow.

Retain useful existing zoom, pan, rotation, paging, waveform and seeking capabilities where appropriate. Keep playback and preview controls predictable and use plain clickable action text; only physical keys receive keycaps. Previewing or selecting never automatically attaches file content to a model or authorizes external requests.

Read/render large files incrementally where supported and bound decoder memory, work duration and caches. Show useful content or controls before expensive optional analysis where possible. Cancel or discard stale results so they cannot replace the current file. Preview must not execute embedded scripts/macros or fetch external resources. Missing decoders and malformed files fail within the pane with a useful recovery action.

The source inspection used snapshot `337e78480272182dfd99a001cd30d44d1c9b9424`, not a required implementation base. [preview.rs](https://github.com/forgewright-ai/spark-shell/blob/337e78480272182dfd99a001cd30d44d1c9b9424/dialog/src/preview.rs) contains content and playback state; the [README](https://github.com/forgewright-ai/spark-shell/blob/337e78480272182dfd99a001cd30d44d1c9b9424/README.md) documents media controls and sway video overlay behavior. This was a source review, not live playback validation. In particular, verify video overlay geometry, focus and cleanup through snapping, scaling and fullscreen.

# Operations and large folders

Browse and search locally; open using the user's chosen applications. Support copy, move, rename, new folder and Trash through native validation and permissions.

Copy/move uses marked files, or the focused file when none are marked. In dual pane, default to the other pane's folder and show the destination before execution, including while that pane is showing preview. Single pane uses an explicit destination choice. Capture the selected source paths and destination at operation start; later navigation never redirects ongoing work.

Handle conflicts explicitly with Skip, Keep both and Replace, with explicit application to remaining conflicts. Never silently overwrite. Trash is the normal deletion action; unavailable Trash must not silently become permanent deletion. Report completed, skipped and failed items, including after cancellation. Offer Undo only when safely supported.

Reuse shared operation feedback. Files supplies the action name, destination, real byte/file counts and cancellation outcomes. Keep browsing usable while safe; prevent conflicting duplicate operations. Do not invent percentages while discovering totals or confuse cancellation with rollback.

Large folders must not block input or impose an arbitrary entry cutoff. Render visible rows and avoid eager expensive metadata reads. Preserve focus and selection by stable identity through loading, sorting and refresh. Avoid constant reshuffling during discovery. Cancel obsolete reads when navigating away. Do not recursively compute folder sizes during browsing; expose that as an action.

Handle empty/no-match states, permission failures, disconnected mounts, changed/disappearing files, long Unicode names, control characters, symlinks and broken targets. Display filenames safely without changing operation paths. Recursive operations must not follow symlink loops. Make the scope of Select all clear: filtered results versus merely visible rows. Reconcile behavior with existing native path policy rather than silently broadening permissions.

# Native acceptance and delivery

The implementation team should exercise realistic scenarios during development and report measured results. No further routine mockup rounds are required.

- Verify compact, fullscreen, left snap and right snap, including resize/restore with selection, scroll, preview and operations active. Preserve state and correct pointer hit targets.

- Test small usable areas, large text, short windows, portrait and wide displays; test mixed scale and monitor changes where available. Establish and document practical minimums. Identify scenarios unavailable in the test environment rather than claiming coverage.

- Test 10,000- and 100,000-entry folders, long similar filenames, changing directories and slow reads. Record responsiveness, time to usable content and memory.

- Exercise text, images, multipage PDFs, supported Office files, audio and video on Void. Include large/malformed files, missing dependencies, rapid focus changes, seeking, cancellation, fullscreen and cleanup. Verify configured resource limits.

- Verify selection semantics, destination capture, conflicts, partial failure, cancellation, Trash and truthful Undo with native test files. Use repository-required checks and meaningful targeted tests.

- Attach native screenshots from the delivered PR head for browsing and preview in the relevant modes, plus reproducible interaction evidence. Check density, filename visibility, consistent font size, fixed controls and footer spacing. CI alone is not visual approval.

# Visual direction

The accepted visual direction uses stable file panes and the shared home frame. It does not prescribe pixel coordinates or exact bindings. In particular: preserve extensions when truncating; do not duplicate selection counts into the other pane; Play is plain text, not a key chip; source paths must agree with the actual pane paths. Shared home input and controls remain authoritative even where the illustration omits or compresses them. Spacing and density are implementation acceptance items.

# Cross module interaction contract

## Prompt scope and state

The current scope is visible beside the prompt or in its breadcrumb: global discovery at home, installed app catalog in apps, and the active folder in files. Plain typing in browse context filters/searches that scope; files defaults to the current folder, with recursive search explicit. Module navigation restores that module's query, focus and view state rather than reinterpreting another module's query.

Keep the shared request draft and explicitly attached context separate from module filters and form fields. Switching scope or entering a command/path interaction must preserve the prior draft. An explicit command or Go to path action identifies the mode and target before execution; matching ordinary filter text to a command name cannot execute it. Reuse existing supported command entry conventions and show the action Enter will perform. Ctrl+Enter sends only the visible normal request text, deliberately, with authorized attachments. It never submits hidden filters or form values.

## Focus and activation

Root navigation and apps retain click/Enter activation. In files, a single row click focuses, a selection mark or configured modifier-click marks, and Enter/double-click opens. Hover is visual only and must not change the authoritative operation target, marked set or previewed file. A stationary pointer cannot override keyboard navigation.

Keep active file-list pane, focused control and marked files as separate state. Preview follows the focused file of its source list only after preview is explicitly enabled. Focusing playback controls does not turn the hidden destination folder into a source. File actions while preview controls are focused still use the source list's marked files, or its focused file, with the destination shown. Closing preview restores the other folder and its state. Choosing another folder list as active explicitly changes the source.

Every action is keyboard accessible through named configurable actions and clickable hints. Do not rely solely on function keys or Insert. Focus and selection need distinct non-color cues. Full names and recovery actions must be accessible without hover.

## Back and unsaved edits

Esc handles the nearest active interaction first: exit fullscreen preview or a transient control, dismiss a confirmation without executing, or leave a form. Dirty forms offer Save, Discard or Keep editing; Escape in that decision keeps editing. At browse level, clear the current query before navigating back. Only at the root with no nearer interaction does Esc request closing home. It never cancels unrelated background work.

Preference forms use explicit Save and Cancel. Edits are a draft until Save succeeds. Failure retains edits with a local explanation; Cancel discards them. Leaving with edits prompts Save, Discard or Keep editing. Resize retains drafts. Standalone commands remain explicit actions and use their normal confirmation/receipt behavior.

## Operation lifetime

Transfers continue while navigating to home or apps. Shared feedback keeps the operation reachable without stealing focus; file identity and destination are captured when the operation starts. Do not introduce a daemon just to achieve this.

In v0, requesting to close home while a transfer is active offers Keep open or Cancel operation and close. Keep open leaves work running. Cancellation uses the shared Stopping state and closes only after the outcome is acknowledged, retaining an honest partial-result summary until the user can read it. Do not offer background-after-close execution unless it is deliberately implemented with an observable lifecycle. Abnormal termination must never imply success or rollback.

## Shared geometry and feedback

Use one shared layout policy for header, prompt, contextual actions, feedback and footer. At a given window size these shared anchors remain fixed across home, apps and files. Content can differ: root/apps lists remain bounded for readability; files can use the wider body for two panes. Align bounded content to a deliberate shared grid rather than leaving it stranded at an arbitrary edge. The team resolves exact native measurements during implementation.

The footer retains its divider, centered open diamond, full blank row and controls. Transient states never consume that spacing. Keep core action slots stable within each module; unavailable actions stay in place with an explanation. Reuse the existing ASCII activity/progress and pointer contracts. No module-specific animation or progress system.

## Integration acceptance

Exercise home -> apps -> Details/preferences -> home -> files -> preview -> transfer -> apps -> home. Verify restored scope and drafts, explicit saves, correct file action targets, accessible focus, ongoing transfer status and guarded close. Repeat key portions after resize/snap and with AI unavailable. Use native evidence from the delivered revision; visual polish and green CI do not establish interaction correctness.

## Delivery

Use safe local fixtures and representative real files with permission. Keep originals unchanged; use disposable copies for transfer and destructive tests. Do not publish personal media, filenames, credentials or machine access details. Coordinate access to local test material directly with the owner.

Validate the complete home -> apps -> files -> preview -> transfer -> apps -> home journey, including AI unavailable, state restoration and closing during a transfer. Report unavailable test configurations honestly.

Continue on this draft PR, titled Files v0 for home. Include implementation, repository-required checks, native screenshots and reproducible interaction results tied to the delivered commit. Verify current main and PR #213 status before shared changes. Do not merge or release without owner approval.
