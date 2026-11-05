# Files v0, as built

The frames of v0.125, rendered from the dialog's own golden files
(`dialog/tests/golden`) in the tokyonight-night palette: 60 by 40
cells, and 120 by 40 for the full width ones. They are the decisions of
the files section of `dialog/DESIGN.md` as the code draws them. The
native proofs on a real desktop (`tests/files_desktop_proof.py`, a
headless sway and foot on Void) ride with the pull request as
`native/` beside these, with their `native.json`.

- `files-home.png`: your home at 60 cells, `home`, `recent` and
  `drives` under their headings, the folder's own row last and muted,
  the selected file's whole line on the status row, now with its place
  (`. ~`), actions and preview on the bar.
- `full-files.png`: the same at 120 cells, the kind and the place back
  as columns.
- `files-checked.png`: two files checked with Insert: the sign at the
  row column and every row's words after it, as a checked list draws
  its picks; the status row counts them and sums their size.
- `files-actions.png`: Right on a file: a page of its own, a menu, the
  row's actions first with `check` and its key chip, then the folder's
  under `this folder`.
- `files-two-panes.png`: two panes at 60 cells, each 30: the active
  pane's path in the text color and its rows under the bar, the other
  pane's path muted with no bar; `pane  Ctrl+Tab` wrapped whole to the
  bar's second line.
- `full-files-two-panes.png`: two panes at 120 cells, each the 60-cell
  list; the header names the active pane's place, the status row the
  lit file's line with its place.
- `files-conflict.png`: a copy that meets a name already there: a page
  of choices, the second column muted, `the 2 others too` while more
  remain.
- `files-batch.png`: a batch under way: the march on the status row
  with the file and the count.
- `files-form.png`: rename typed in the prompt, the name prefilled,
  `let go  Esc   save  Enter` on the bar.

## The native proofs

`native/` holds the files proof's own captures from the owner's Void
box, a headless sway and foot at 1440 by 1000 against CI's build of
`24474d3` (run 41961076715, sha256 `02df85d0...`), with `native.json`
(the checks, the captures, the timings of the 10,000-file folder) and
`proofs.log`, the lines of the home, apps and files proofs as they
passed there (13, 14 and 16 checks); `home-native.json` and
`apps-native.json` are those two proofs' manifests.

- `files-compact.png`, `files-fullscreen.png`, `files-snap-left.png`,
  `files-snap-right.png`, `files-minimum.png`: the home folder in every
  mode, the 36 by 20 minimum last.
- `files-status.png`: the lit file's line on the status row.
- `files-checked.png`: two files checked, the count and the size.
- `files-actions.png`: the actions page of a checked file.
- `files-two-panes.png`, `two-panes-compact.png`,
  `two-panes-fullscreen.png`, `two-panes-snap-left.png`,
  `two-panes-snap-right.png`, `files-two-panes-folders.png`: two panes
  on one folder in every mode, then on two folders after Ctrl+Tab.
- `files-conflict.png`, `files-receipt.png`, `files-undo.png`: a copy
  of two checked files that meets a name already there, kept both, the
  receipt with undo, and undo taking both back.
- `files-new-folder.png`: the new folder's form landed.
- `preview-text.png`, `preview-picture.png`: Space on a file, the whole
  window.
