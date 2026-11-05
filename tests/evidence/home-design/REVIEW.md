# The dialog's design, as built

The frames of v0.124.1, rendered from the dialog's own golden files
(`dialog/tests/golden`) in the tokyonight-night palette: 60 by 40
cells, 150 by 46 for the full screen ones and 40 by 26 for the small
one. They are the decisions of `dialog/DESIGN.md` as the code draws
them; the native proofs on a real desktop are under `../home-recovery`
for v0.124 and ride with this release's pull request.

- `home.png`: the frame's two strips, the prompt's tools under the
  prompt with the diamond's rule under them, the key bar at the bottom
  over a plain rule; the menu breathing, two rows of air between its
  groups; the second column as state where a section has spoken.
- `home-small.png`: the minimum window single spaces the same menu.
- `full-home.png`: the same column in the middle of the screen, the
  selection bar across it with nothing else changed on the row.
- `apps.png`: the apps under their headings at column 4, names and
  roles lowercase, no sign before a row, the managing rows at the end
  with the arrow after a value; the selected app's line on the status
  row; the view's keys alone on the bar.
- `apps-details.png`: a details page, the name lowercase, facts, open,
  technical details behind an arrow, the preferences.
- `files-home.png` and `full-files.png`: files at 60 and at 120 cells,
  a folder told by its count, the selected file's whole line on the
  status row, actions and preview on the bar.
- `settings.png` and `section.png`: a list with signs that mean
  something (a check, a ring) keeps its sign column; one with none
  starts its words at column 4.

## Validation

- `cargo test --locked` in `dialog/`: every suite green, the golden
  frames re-kept after a look at these renders; new tests in
  `dialog/tests/chrome.rs` for the two strips, the ask row, the click
  rule and the mini-status, and home's state column.
- `cargo fmt --check` and `cargo clippy --locked --all-targets -- -D
  warnings` clean.
- The native proofs and CI: see the pull request.
