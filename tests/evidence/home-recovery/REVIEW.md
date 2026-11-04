# Home's frame put right, after v0.123

The pictures here are the dialog's own golden frames (`dialog/tests/golden`)
rendered to PNG from their HTML renders, in tokyonight-night at 60 by 40
cells, 150 by 46 for the full screen ones and 40 by 26 for the small one.
They are drawings of the frames the tests hold, not native captures: the
native proofs in `tests/` were brought up to date with this change but
were not run for it, since they need a Sway desktop. Run them before the
tag:

    python3 tests/home_desktop_proof.py BINARY DIRECTORY
    python3 tests/apps_desktop_proof.py BINARY DIRECTORY
    python3 tests/apps_contract_desktop_proof.py BINARY DIRECTORY

## What changed, and where to see it

- One casing rule: every label the dialog writes is lowercase, a supplied
  name keeps its spelling. `home.png`, `settings.png`, `apps.png`.
- The home's ten places single spaced in three groups, purposes muted,
  what a place holds now in the text color. `home.png`, `home-small.png`.
- One frame width per view, in the middle of the window, the header, the
  prompt, the keys, the list, the status row and the footer in it.
  `full-home.png` (60 cells), `full-settings.png` and `full-files.png`
  (120 cells).
- The lit row's band is the list column to the list's end, the same for
  every row; the lit row's name in the accent. `full-home.png`,
  `full-settings.png`, `full-files.png`, `apps.png`.
- The key row is the view's, whatever row is lit or typed; no spinner in
  a label. Every frame; `files-home.png` shows it wrapped at 60 cells
  with the list where it always is.
- No hover, no underline, no focus on a key chip. `turn.png` shows the
  footer with nothing underlined.
- The status row above the rule, the one place a message is written:
  a receipt with Undo in `turn.png` and `section.png`, the planned
  commands in `staged.png`.
- Apps drawn with the dialog's own rows: `apps.png` (the list, the
  managing rows at its end) and `apps-details.png` (the facts, open,
  technical details behind an arrow, the switch and the two choices).

## Validation

- `cargo test --locked` in `dialog/`: every suite green, 66 golden frames
  re-kept after a look at their renders, 26 Apps tests and 7 frame tests
  (`dialog/tests/chrome.rs`) new.
- `cargo fmt --check` and `cargo clippy --locked --all-targets -- -D
  warnings` clean.
- `sh tests/gate.sh --quick`: see the pull request for the run.

## native

Pictures from the three desktop proofs on a real machine, a folder each
under `native/`: `home/` (15), `apps/` (20) and `contract/` (19). They
were taken at 5a67ca6 on Void with sway 1.12, headless, against CI's
build of this branch, the one `dialog/dialog.env` pins, sha256
`641afd004b101a816eeccff2d73893a1651a863d6ab9f3154b01f7877ce0d3bc`.
`home_desktop_proof.py` passed 13 checks, `apps_desktop_proof.py` 14 and
`apps_contract_desktop_proof.py` its 4. Two proofs name pictures alike,
so each keeps its own folder.
