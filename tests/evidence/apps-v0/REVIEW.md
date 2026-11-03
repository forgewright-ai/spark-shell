# Apps v0 native review

This is implementation-session evidence. Independent visual/functional review
and owner approval to merge remain pending.

The PR body records the final head commit and hosted CI run. `native.json` records
the tested release binary, native environment, viewport geometry and observed
interaction checks. `source-sha256.json` records the native checkout's sources,
compared with the submitted files. The release binary is pinned in `dialog/dialog.env`.

The eight primary captures use real Void Linux desktop entries and on-demand
XBPS metadata, with one theme, monospace font at 12 points and scale 1. The
headless Sway output is 1440x1000; its bar reserves 28 pixels. Model and voice
availability are fixtures; no inference or external account is needed for Apps.
All preferences and added test entries belong to a temporary HOME.

| Surface | Compact | Fullscreen | Left snap | Right snap |
| --- | --- | --- | --- | --- |
| Apps | ![Apps compact](apps-compact.png) | ![Apps fullscreen](apps-fullscreen.png) | ![Apps left](apps-snap-left.png) | ![Apps right](apps-snap-right.png) |
| Details | ![Details compact](details-compact.png) | ![Details fullscreen](details-fullscreen.png) | ![Details left](details-snap-left.png) | ![Details right](details-snap-right.png) |

## Visual review, separate from automated checks

1. **Browse and search: pass.** The grouped list keeps compact type and row
   spacing. Fullscreen keeps a centered 60-cell body inside the shared frame; header, prompt, actions and footer retain the same anchors as files. Equal 720x972 snap
   regions have the same internal geometry and sit at y=28. Active search and
   selection survive the complete mode cycle; the Details keycap opens the
   selected app through the configurable key action.
2. **Inspect: pass.** The overview, single Technical details disclosure and
   Preferences group have aligned values and chevrons. Display names are
   lowercase; identifiers and copied paths retain their spelling. Reopening
   Details refreshes package and running-window information. The local fixture
   in [missing metadata](missing-metadata.png) has no package ownership, which is
   shown as Unavailable rather than a guessed version or policy.
3. **Organize and edit: pass.** Category creation, rename, mapping edits, confirmed
   deletion, per-app overrides and hide/restore were exercised through native
   controls. Preferences survive restart. Expanded content and unsaved edits
   survive all four modes. Wrapped preference values share their label's focus
   and click target.
4. **Minimum size: pass at 36x20.** [Long metadata](minimum-long-metadata.png),
   [clipboard completion](minimum-technical-attachment.png) and
   [preferences](minimum-preferences-attachment.png) show the populated footer
   with a long attachment. Values reflow; Page Up/Down and the wheel can reach
   every metadata line. The divider, blank row, controls and bottom inset remain
   reserved. Remove activates its visible target after resizing. A shortened
   model label opens the selector, where its full identity is available.
5. **Launch and recover: pass.** Installed foot and Terminal=true btop launch
   through GIO. Enter and click use the same saved preference. Two btop windows
   establish MRU focus behavior; removing both verifies the launch-if-none path.
   A labelled desktop-entry fixture exercises a declared New window action using
   real foot windows. Home clears from view after confirmed focus and returns
   through Super+Space; [the opened application](application-opened.png) is visible
   without home covering it. [No matches](no-matches.png), [hidden search](hidden-search.png),
   [empty catalog](empty-catalog.png), [discovery failure](discovery-failure.png)
   and [launch failure](launch-failure.png) keep readable feedback and recovery.
   Empty/discovery/launch failure screenshots deliberately use adapter response
   fixtures; native adapter tests separately exercise real unavailable entries.

6. **Dirty exit decisions: pass.** [Unsaved preferences](contract/01-unsaved-preferences.png)
   lead to [Save, Discard or Keep editing](contract/02-exit-decision.png) on
   Esc, conversation navigation and the actual close button. Keep editing is
   selected initially; Esc in the decision returns to the unchanged form.
   Save persists before continuing navigation. A focused row has a non-color
   chevron; focused footer controls and keycaps also use underlining.
7. **Separate drafts: pass.** The [normal request](contract/03-restored-request.png)
   and [Apps filter](contract/04-restored-app-query.png) restore independently.
   Ask from a catalog/folder opens the normal request draft without sending the
   filter. Request text is sent only by a subsequent explicit Ask there.
   Attachments remain owned by the shared request. Category fields cannot be
   sent while editing or while the exit decision is visible.
8. **Save, Cancel and recovery: pass.** [Category Esc](contract/05-category-exit-decision.png)
   retains the field; Cancel discards it. A real filesystem permission failure
   [keeps preference edits](contract/06-save-failure.png) and the stored value.
   Discard then completes the requested navigation. Preference and default
   mapping edits require Save; category creation/rename provide Save and Cancel.
   Save/Cancel/Open retain their slots when Details becomes dirty or clean.
9. **Shared geometry and AI unavailable: pass.** The native proof visits home,
   apps and files in all four modes and compares title/footer columns and window
   rectangles. Fullscreen anchors are column 12 in all three; snapped anchors
   are column 2. The Apps body stays bounded and centered. Both snapped bodies
   have identical spacing. [Details with AI unavailable](contract/07-details-ai-unavailable.png)
   remains usable after restart and restores saved preferences.

| Shared frame | home | apps | files |
| --- | --- | --- | --- |
| Fullscreen | ![home](contract/home-fullscreen.png) | ![apps](contract/apps-fullscreen.png) | ![files](contract/files-fullscreen.png) |
| Left snap | ![home](contract/home-left.png) | ![apps](contract/apps-left.png) | ![files](contract/files-left.png) |
| Right snap | ![home](contract/home-right.png) | ![apps](contract/apps-right.png) | ![files](contract/files-right.png) |

[Contract results](contract/contract.json) record the exact binary checksum,
observations and geometry; matching text captures accompany each screenshot.

The review caught and corrected an input-reader deadlock during resize, a hidden
Details shortcut, a clipboard completion timeout, clipped selected preference
values and metadata that could not be reached while keyboard focus stayed on an
action. The shared frame handles repainting and wrapped control hit targets.
The native resize stress exercise repeated eight complete mode cycles with
pointer interaction; the PTY regression checks repeated resizes without input
and rejects cursor-position queries during those resizes.

## Reproduce

Local validation: 283 Rust tests passed, including 16 Apps regressions. The native
workflow passed all 12 checks recorded in `native.json`; the shared-contract proof passed all four additional flow groups in `contract/contract.json`. Seven adapter tests
passed on Void; macOS runs three portable cases and explicitly skips four GIO
cases. Two independent musl release builds produced the same SHA-256:
`5ae41e3bf0548d6712683f24d3b12ad2b786ed2a5db7d6e347ec49febea204da`.
The PR records the complete push-gate result and hosted CI result for its head.

The conflict resolution incorporates main `9f5e4e9` (v0.122.1), preserving its
installer fixes and release notes alongside the unreleased Apps entry. The
dialog source is unchanged from the preceding Apps submission; the package
version changed, so the binary checksum, native proofs, screenshots and source
hashes were regenerated. The quick gate now has 26 checks, including main's
new installer tests. Hosted push CI and CodeQL results are recorded separately
from the intentionally skipped same-repository pull-request CI run.

```sh
cd dialog
cargo fmt --check
cargo clippy --locked --all-targets -- -D warnings
cargo test --locked
cd ..
python3 tests/apps_test.py
sh tests/gate.sh --quick
```

On Void with Sway, foot, grim, wtype and wl-clipboard available:

```sh
sh tests/dialog_build.sh
python3 tests/apps_desktop_proof.py \
  dialog/target/x86_64-unknown-linux-musl/release/spark-dialog /tmp/apps-proof
python3 tests/apps_contract_desktop_proof.py \
  dialog/target/x86_64-unknown-linux-musl/release/spark-dialog /tmp/apps-contract-proof
```

The native script performs the flows above, records observed checks, compares
left/right terminal composition, copies the original launcher path, and restarts
home to read persisted preferences. It leaves the user's actual desktop and
launcher preferences untouched. `tests/apps_test.py` uses isolated desktop-entry
fixtures for precedence, hidden entries, unavailable executables, field-code
expansion, declared actions and inert metadata inspection. Those GIO cases run
on Linux and explicitly skip on macOS.

## Limits

Cross-module file transfers and their operation lifecycle remain the Files delivery. This increment validates navigation into existing Files, shared frame geometry and separated prompt state; it does not claim transfer integration.

Native validation covers Sway/Wayland on Void. X11 class matching, DBus-activated
applications, Flatpak permissions and other package managers were not exercised
interactively. Sway exposes focus order within groups rather than global focus
timestamps; ambiguous matching windows in separate groups produce a diagnostic
instead of an arbitrary focus choice. New window is offered only for a declared
New window action. An accepted launch without an observed window remains a
request, not a claimed success.

Keyboard navigation, visible focus, pointer targets, reflow and the supplied
palette were reviewed. Screen-reader behavior and formal accessibility
conformance were not assessed. Screenshots establish appearance; the native
interaction checks and tests establish behavior.
