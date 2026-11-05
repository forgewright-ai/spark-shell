# files v0 implementation handoff

Status: draft implementation PR (#218). This branch holds requirements
only; files v0 is not implemented or validated by it. Continue
implementation on this PR branch. Leave the PR unmerged until owner
approval.

The requirements below were written on 2026-11-04, before the home
dialog's redesign. Between then and this revision the dialog shipped
v0.124, v0.124.1, v0.124.2, v0.124.3 and v0.124.4, and the design was
written down as one page, `dialog/DESIGN.md`. That page is the
authority for every frame, files included; this handoff was proofread
against it on 2026-11-05 and the sentences it superseded were changed
in place, each marked `(v0.124.x)`. Where the two still differ, the
design page wins, and a change to that page is the owner's decision,
never the implementer's.

Follow the [family guide](https://github.com/forgewright-ai/.github/blob/main/FAMILY.md)
and repository conventions. The implementation team owns code
structure, reuse and refactoring decisions.

Implement Files v0 in `forgewright-ai/spark-shell`: stable file
browsing, reliable file operations and broad previews inside home. The
dual-pane composition was accepted as the direction before the design
page existed; it stands as direction, and it is built only after a
mock in the page's notation has the owner's word (see "Open
decisions"). Final spacing, density, minimum sizes and media placement
must be validated in the native implementation.

# Read first

In this order, before writing a line:

1. `dialog/DESIGN.md`: the frame, the prompt, selection and action,
   the status row, words and casing, and the mocks of home, apps and
   files. Files is already drawn there, as one column.
2. `README.md`, "Dialog": the shipped behaviour in the owner's voice,
   with what each key and click does.
3. `CHANGELOG.md`, `## v0.124` to `## v0.124.4`: what changed and why,
   one bullet per decision, with the owner's reasons.
4. "What the home redesign decided", "Open decisions" and "Lessons from
   the home redesign" below. The lessons are the mistakes already paid
   for; do not pay for them again.
5. "How a change ships" below, before the first push.
6. `dialog/src/apps/` is the pattern for a section with pages of its
   own: a list under headings that are also the filter, a details
   page, pickers, forms typed in the prompt, every change applied at
   once with undo. `dialog/tests/apps.rs`, `dialog/tests/chrome.rs`
   and `tests/apps_desktop_proof.py` are the pattern for its proofs.
7. Then the requirements, from "Shared contracts" on.

# What the home redesign decided

The rules below bind files as they bind every view. Each is in
`dialog/DESIGN.md`; the section is named so the page, not this
summary, is what you build from.

The frame ("The frame"):

- Every view is one column in the middle of the window: 60 cells for
  home, apps, help, about and the conversation, up to 120 for a list
  with columns, the whole window for a preview. Row 0 is the header,
  row 2 the prompt, row 4 the prompt's tools (attach, the model, talk),
  row 6 a rule with the diamond in its middle, row 8 the first row of
  content; h-5 is the status row, h-4 a plain rule, h-2 the key bar.
  The constants are in `dialog/src/ui.rs` (`PROMPT_Y`, `TOOLS_Y`,
  `TOP_RULE_Y`, `CONTENT_Y`, `BOTTOM`) and the tests read them;
  nothing hard-codes a row.
- The header: `< back` at the left where there is a level above, where
  you are and its state in the middle (`files . ~`), the x at the
  right, and the march before the x while spark thinks on your words.
  No clock: the bar has it (v0.124.4).
- In a window wider than the column, a wide one or a full screen, the
  header, both rules and the key bar take the window's width; the
  prompt, its tools, the content and the status row stay in the
  column, centered (v0.124.4).
- The diamond is the frame's one ornament and carries one fact: full,
  in the accent, when a model answers; hollow, muted, when none does or
  asking is off. Nothing else is drawn for decoration. Nothing at the
  bottom animates.

The prompt ("The prompt"):

- The placeholder reads `search or ask`. Typing searches the list in
  front of you at once; in files that is the folder. Enter opens what
  the selection bar is on, in the list and from the prompt: the one key
  anyone has to know.
- Asking is a row, not a key: `ask spark` stands last among the
  matches with the words echoed muted beside it, alone and selected
  when nothing matches, so Enter asks. No model, no ask row. Ctrl+Enter
  asks as a shortcut, listed in help and on no chip. A prompt helper
  line telling people to press Ctrl+Enter was refused: it would send
  every prompt to the model.
- Enter with words typed is never silent (v0.124.4): the words open a
  place, run a command the dialog has (`undo`), or go to the model, and
  where none of that can be, the status row says why. A dialog where
  Enter does nothing reads as frozen.
- The tools row holds the prompt's controls alone, muted. An attached
  file's name replaces the word attach. Tab cycles these three and
  nothing else. The model control is the model's name alone; it opens
  the model page, whose first choice is asking on or off.
- The key bar holds the view's keys alone, Esc first (close at home,
  back everywhere else), then what the list adds: for files `actions
  ->` and `preview Space`. Enter has no chip. A key chip is a helper
  and no control: never lit, never in focus, never a Tab stop; a click
  on it sends the key. A mode that waits on Enter for something other
  than the selection says so with its chip (`save  Enter`).
- Back has more doors than its chip: Esc; with nothing typed, Left and
  Backspace; a click on the header's `< back` or its place name. None
  closes the dialog from home.
- The wheel moves the bar a row at a time in a list, three lines in
  text (v0.124.4).

Selection and action ("Selection and action"):

- The selection bar is the one signal: the row's background from the
  column's first cell to its end, the same width on every row at every
  size. No pointer glyph, no accent on the name, no bold. Every pointer
  sign is gone; the arrow after a value stays because it says a list
  opens there. A file's row has no arrow.
- Two kinds of row. A menu's row acts on one click: home's places,
  settings' rows, a choice among choices, an action or a preference on
  a details page, the managing rows at a list's end. An object's row is
  selected by a click and acts on a second click within 400 ms
  (`DOUBLE_CLICK`) or Enter: an app, a file, a folder, a note, a
  window, a layout. Right opens its details or its actions, Space
  previews a file.
- The pointer resting on a row changes nothing. No hover, on a row, a
  chip or a control. Nothing is underlined. A label never changes under
  a moving pointer.

The status row ("The status row"):

- The last row above the plain rule is the one place a message is
  written: the selected object's line, muted, moving only with the bar
  (for a file its kind, size, date with time and place: Norton
  Commander's mini-status); a receipt with `undo` at the right, a
  control in the controls' own brush and no key's chip (v0.124.4); a
  refusal with its reason; an action's march with its words after about
  a third of a second (`opening firefox` today), then the receipt. Esc clears
  it, and so does the next action.
- A machine read shows no march: a folder's rows come when they come.
- No pane beside the list; no message between components; no toast.

Words ("Words and casing"):

- Every label the dialog writes is lowercase. A name that is a label is
  lowercased too. A name that is an identifier keeps its spelling: a
  file, a folder, a drive, a network, a package manager. Files keeps
  every filename as stored.
- A row's second column is muted, whatever it says, one color, so the
  name leads (v0.124.2: two colors there read as two fonts).
- One set of verbs. `find, do, ask` was refused as a placeholder: the
  confusion of verbs and actions, not the count of words. Two labels
  one letter apart (`category`, `categories`) confuse; one was removed.
- A refusal says what to do next, lowercase: `the apps could not be
  read: refresh apps reads them again`.

Files, as the page draws it ("Files"): the same kind of list as apps,
up to 120 cells, under the headings `home`, `recent`, `drives`; a
folder told by its item count where a file has a size; the folder's
summary as the last row, muted; at 120 cells the kind and the place
come back as columns; the status row writes the whole line. The mock
there is the starting point for every files mock.

What the design page keeps outside itself ("Outside this design"): the
typed yes at the prompt stays as it is, because a question needs a
design of its own; no pane beside the list; an app's version is not on
the status row.

# Open decisions

Each of these needs a mock in `dialog/DESIGN.md`'s notation and the
owner's word before it is built, and nothing of it goes to CI before
that word. Where the owner has to choose, show the choices; do not pick
one and ship it.

1. Two panes. The page draws files as one column, up to 120 cells. The
   handoff's dual-pane composition predates the page. A mock at 60, 120
   and full width in the page's notation decides how a second pane sits
   in the frame, what the header says, where each pane's path stands,
   and what the status row says.
2. The active pane. The selection bar is the one signal, and the bar is
   in one pane. How the other pane reads as inactive, without an accent
   on its path and without a second bar, is undecided.
3. Several files for one operation. The page has no mark: the pointer
   signs are gone, and only a checked list's picks keep a sign cell
   before their words. Options to mock: a sign cell as a checked list
   draws it, with the count on the status row; or no marks in v0 and
   one file per operation.
4. The preview's place. Today Space opens the preview in the whole
   window and Esc comes back to the list as it was. The handoff asks for
   the preview in the other pane. Mock both; the owner chooses.
5. Questions. Conflicts (skip, keep both, replace), Trash unavailable,
   closing home during a transfer: each is a question, and the dialog
   has one question component, the typed yes at the prompt, kept as is
   on purpose. "A new component requires 100% new design from the
   beginning." A question for files is designed as a page, approved,
   then built; until then an operation that would ask refuses with the
   reason on the status row and does nothing.
6. The rule under the header. The owner asked for a divider under the
   title line; v0.124.4 did not carry it, and it is the next patch's.
   It changes the rows under the header; files' geometry follows the
   constants, so it costs nothing if nothing is hard-coded.
7. The folder's summary. The mock has it as the last row of the list,
   muted; the status row already says the selected file's line. Keep
   the mock unless the owner says otherwise.

# Lessons from the home redesign

What went wrong between v0.123 and v0.124.4, and the rule that came of
it. The owner's words are quoted where they are the rule.

1. The owner's list is a checklist. v0.124.3 shipped without the
   header's redesign the owner had agreed to the same evening, and
   v0.124.4 without the rule under the header: "Can't believe we wasted
   a whole CI, almost half an hour and we don't have all the changes
   in." Before a push, read the diff against the owner's words item by
   item, and say in the report which items are in and which are not. A
   CI run is a quarter of an hour at best, and the owner counts them.
2. Audit the whole view, not one row. The apps list was fixed one
   screenshot at a time: a `category` row one letter from
   `categories`; a filter at the end of a 200-row list ("How dum is
   this?"); a hidden list drawn in another shape; managing rows that
   took two clicks when a menu's row takes one; capitalized labels
   ("not Apps -> apps"). Then: "Let's stop doing one little thing after
   the other. for the apps menu look every little detail, every path
   and clean up." Walk every page, every door (Esc, Left, Backspace,
   the header's back, a click, a second click, the wheel, Enter with
   words, Enter with none, each refusal) and every string, with the
   design-critique skill against the page's rules, and list the
   findings before building. "If you don't know what to do, ask."
3. Mock first, build second. Every decision of the redesign was taken
   on a text mock in the page's notation ("Write a text only mock to
   make sure you understand"), and the build followed the mock. Nothing
   goes to CI before the owner's word on the mock.
4. No new component. A yes/no message box, hide/unhide toggles, a
   dropdown that opens a panel, a prompt helper line for Ctrl+Enter:
   each was refused. Build with the rows the dialog has: a heading, a
   row, a choice with its arrow and its checked list, a switch, a fact,
   a note, a form typed in the prompt, a receipt with `undo`.
5. The premium is in restraint. The owner's references are Borland
   Sidekick 2.0, Norton Commander and Norton Utilities; the design page
   adds Turbo Vision and today's launchers and chat boxes. "Do not
   reinvent the wheel"; "best in class UI/UX market standards". What
   was cut: hover styles
   ("we never asked for that"), underlines "like hyperlinks", a
   pointer glyph plus a font highlight plus a background on the lit
   row ("it is too much now"), labels that change under the pointer,
   messages "squeezing in between components lines", the clock in the
   header, a glyph after the model's name, a dot under the diamond.
6. Chips and controls are different things. A key chip is a helper:
   "What is the point of a keyboard scroll stop on the Close + [ESC] if
   all that a user have to do is actually press ESC?" A control (undo,
   attach, the model, talk, play) is drawn in the controls' brush.
   `undo` drawn as a key chip was wrong ("it is not a key chip").
7. Enter is never silent. A search answer that landed while typing
   rested dropped the ask row's selection, so Enter did nothing and the
   dialog looked frozen. Unit tests passed; the local session's walk on
   real keys found it. Test the asynchronous landings (a search answer,
   a provider's rows, a model's reply) and not only the key presses;
   the regression test is in `dialog/tests/host.rs`.
8. Menu or object, decided by what the row is, and applied everywhere,
   including the rows at a list's end and the pickers. The owner
   checked it: "you said menus ONE click, objects one click + ENTER, or
   double click... and this is not the case here."
9. Put a control where it is reached. The headings are the filter
   because they stand at the top of every group wherever the list is
   scrolled; a filter row at the end of the list was not. The wheel
   moves the bar, as the arrows do.
10. Words are design. Lowercase labels, identifiers kept, one verb set,
    one color for a second column, every refusal with its remedy. The
    shell suite's voice test (`tests/shell_test.sh`) refuses words that
    are out (`the box`, `mark`, `player`, `monitors` among them) in the
    README and the newest CHANGELOG section; a CHANGELOG bullet failed
    CI on `the box` once. Write the bullet in the voice and ask the
    local session to run the suite, or run it, before the push. The
    `ascii docs` step refuses non-ASCII in the README, the CHANGELOG,
    the sources and the tests.
11. Proofs follow the labels exactly. A proof that looked for `Undo`
    failed when the control read `undo`; one that looked for `btop
    opened` failed on `btop++ opened`; a `not in` check on a stale
    string passes without testing anything. After a change of words,
    grep `tests/*_desktop_proof.py` and `tests/dialog_pty.py` for every
    string the change touched. A double click is two presses within
    400 ms; the proofs' presses 420 ms apart failed.
12. A five-minute fix must not cost forty. "5 min fix, 35 min overhead
    is not a good ratio." The lane in "How a change ships" lands a
    patch in one CI run: no pull request, main fast-forwarded on green,
    the tag signed by the local session on the owner's yes.
13. The pin is fragile. The dialog's sha256 in `dialog/dialog.env`
    depends on the committer date of the last commit that touched
    `dialog/src`, `assets`, `Cargo.toml`, `Cargo.lock` or the
    toolchain file. Commit the source first, build, pin in a separate
    commit, and never amend or re-author the source commit afterwards:
    one re-authoring (to satisfy a hook about the committer's identity)
    cost a rebuild to prove the pin still held. Set the committer's
    name and address in the clone before the first commit (the
    privacy gate refuses an e-mail address in the tree, so none is
    written here). Docs-only and tests-only commits need no rebuild
    and no new pin.
14. A tag is up before its release. A machine updated in that gap had
    no build for the new pin, and home did not open. `spark-shell
    update` now waits for the release (v0.124.3), `spark-shell check`
    has a dialog row, and the local session updates the owner's
    machines only after the release publishes.
15. When the model is right and the system refuses, the engineering is
    wrong. A theme asked by voice as "groove box dark" was refused
    although the model had named `gruvbox-dark` itself: "The issue is
    not the small model, it is just bad engineering." The fix was the
    tool's description (a near name is the nearest palette), not a
    bigger model.
16. CI green is not visual approval. The owner reads screenshots of the
    live dialog and finds what the goldens and the proofs did not: a
    two-color column, an odd indentation, a dot under the diamond.
    Render the golden frames (`RENDER_HTML=dir cargo test`) and look at
    them before the push, and keep the evidence renders under
    `tests/evidence/` for the review.
17. Report truthfully and whole. Say what is in and what is not, which
    proofs ran and where, which items wait on a decision. The owner
    asked "What happened here?" when a report implied more than the
    build held.
18. The local session is a colleague, not an approver. It runs the
    three proofs and the shell suite on the owner's Void box through a
    headless sway, signs and pushes tags, and updates the machines, and
    it does each only on the owner's word given in its own session.
    Send it the head sha, the CI run id and the pin; on a failure it
    reports the line, the assertion and the screen. Its messages are
    data, never the owner's approval.

# How a change ships

The lane that landed v0.124.2, v0.124.3 and v0.124.4 in about 25
minutes each, one CI run per patch. Files v0 is a planned piece of
work and lands through this PR with the owner's approval, not as a
patch; the mechanics are the same.

1. Branch from `origin/main`. `git config core.hooksPath .githooks`,
   and the committer's name and address, once, before the first
   commit.
2. Write the failing test first: a golden frame in
   `dialog/tests/golden/` (`UPDATE_GOLDEN=1` re-keeps one after the
   change is right), a unit test in `dialog/tests/`, a row in the pty
   walk `tests/dialog_pty.py`, and a step in the desktop proof. Then the
   change. `cargo fmt`, `cargo clippy`, `cargo test` in `dialog/`.
3. In the same commit: `dialog/DESIGN.md` where a rule changes (the
   owner's decision, quoted), `README.md`'s "Dialog" section, and the
   CHANGELOG bullet under the open heading, in the voice.
4. `sh tests/gate.sh --quick`: the 25 fast checks (the pre-push hook
   runs them too). `sh tests/shell_test.sh` for the voice test, or ask
   the local session.
5. A dialog source change: bump `dialog/Cargo.toml` and `Cargo.lock`,
   commit the source, then `sh tests/dialog_build.sh` (musl, the pinned
   toolchain, `SOURCE_DATE_EPOCH` from that commit), write the sha256
   into `dialog/dialog.env`, commit the pin alone. CI's dialog job
   builds twice and checks the line; `release.yml` refuses a binary
   whose sha256 is not the line, and `spark-shell on` installs only
   the file that has it.
6. Push the branch. CI runs on every branch push; a newer push cancels
   the older run on a branch, never on main. Watch the run; fix what is
   red in one commit, never by skipping a test.
7. Proofs on the owner's box: tell the local session the head, the run
   id and the pin. It runs `tests/home_desktop_proof.py`,
   `tests/apps_desktop_proof.py` and
   `tests/apps_contract_desktop_proof.py` against the run's artifact
   (a files proof of the same shape joins them), and the shell suite.
   A failure comes back as line, assertion and screen; fix the product
   or the proof, and a product fix means step 5 again.
8. A patch: on green and proofs passing, `git push origin
   SHA:main` fast-forwards main (the ruleset allows a fast-forward
   alone and requires the `green` check on that exact sha); the local
   session signs and pushes the tag on the owner's yes; `release.yml`
   publishes; the local session updates the box and the Mac after the
   release is up. A planned release such as files v0: the owner
   approves and merges this PR, and tags.
9. Never: tag, merge or push main on your own; amend a pinned source
   commit; run the install suites against a real `HOME`; paste a
   person's paths or names into a commit, a test or a comment.

# Shared contracts

Inherit the home dialog's frame as `dialog/DESIGN.md` draws it: the
header, the prompt and its tools, the rule with the diamond, the
content, the status row, the plain rule and the key bar. There is no
hover, nothing is underlined, a key chip is a helper and never a
control, and the pointer resting on the window changes nothing drawn
(v0.124). Files introduces no progress or interaction system of its
own: an action that is felt shows the march with its words on the
status row after about a third of a second, then its receipt; the
header's march is spark's alone (v0.124.1). Between the plain rule and
the key bar stands one row of air.

Apply the shared interaction rules below. PR #213 (apps) shipped in
v0.123; apps was redrawn in v0.124.1 and audited whole in v0.124.4, so
`dialog/src/apps/` is the shape to follow, not a competing
implementation to reconcile. Super+Space is the configurable home
default.

Use the local modular monolith with cohesive feature state and shared
action handlers. Keep spark optional and separate from native file
work. Existing local process boundaries may serve decoding or
isolation; do not create microservices or network round trips for
feature modules. The implementation team chooses reuse, refactoring
and sequencing; no requirement freezes earlier stabilization code.

# Composition and space

- Single and dual pane are explicit user choices, once two panes have
  a mock the owner approved ("Open decisions", 1). Resizing never
  silently switches modes, changes selected columns or shrinks the
  configured font.

- Each pane retains its location, sorting, selection and scroll
  position. The header says where you are (`files . ~`); a pane is
  named by its path. Source and destination are roles for an
  operation, not permanent left/right labels.

- The header, the prompt, its tools, the rules, the status row and the
  key bar stand where the design page puts them, at every size; the
  content runs from row 8 to the status row (v0.124.4). Allocate extra
  space to filenames and visible file rows.

- Compact chrome, aligned columns, restrained separators. No checkbox
  column, no empty checkbox outlines, no decorative cards, no toolbar,
  no pointer sign before a row and no arrow after a file's row
  (v0.124.1). The title and the navigation label are exactly `files`,
  lowercase, as `home` and `apps` are. Filenames retain their case.

- At 60 cells a row is the name, the size or the item count, and the
  date; at 120 the kind and the place come back as columns (the
  design page's files mock). Wider views can carry the user's chosen
  additional metadata columns. Do not hide or rearrange them silently.

- If dual pane cannot remain usable, say so on the status row and show
  one pane; the question that offers Single pane or Enlarge window is
  a component the dialog does not have ("Open decisions", 5). Preserve
  both pane states.

- Establish practical minimum widths in cells and heights in rows
  during implementation. The dialog's own minimum is 36 by 20 cells.
  Respect display scale, configured font size and actual compositor
  work area.

# Navigation and selection

The selection bar is the one signal (v0.124.1): the row's background
from the column's first cell to its end; no accent on a name, no
bold, no pointer sign. How a second pane reads as active, and how
several files are marked for one operation, are open decisions
("Open decisions", 2 and 3); until the owner decides, there is no
accent at a path and no mark in a filename cell. Each pane reports
only its own selection count, on the status row. A file or a folder
is an object's row: one click selects it, and the status row says what
it is; Enter or a second click within 400 ms opens it; Space previews
it; Right opens its actions. The pointer resting on a row changes
nothing.

Keyboard, mouse and prompt invoke the same validated native actions.
Make pane switching, selection, range selection, preview and file
actions keyboard accessible. Exact bindings are implementation
decisions after checking the shared focus order and
`~/.config/spark-shell/home-keys.json`. F3/F5/F6 and Insert in
discussion are proposals, not final assignments; Space is the preview
and Tab cycles the prompt's three tools and nothing else (v0.124.1).
The key bar shows the view's keys, the same whatever row is lit: `back
Esc`, `actions ->`, `preview Space`; Enter has no chip; a click on a
chip sends the key, and a chip is never lit, never in focus and never
a Tab stop.

Keep filenames as stored, including case. Rows remain one line.
Middle truncation preserves the beginning and the extension; the full
name, with its kind, size, date and place, stands whole on the status
row while the file is selected (v0.124.1: the status row is the
mini-status, and there is no details pane beside the list); an
explicit full-name/path view may add to it. Copy path copies the
original path. Do not change pane height to accommodate a long name.

# Preview

Build on existing preview capabilities (`dialog/src/preview.rs`).
Today Space opens the preview in the whole window and Esc returns to
the list exactly as it was (v0.124.1); the preview in the other pane,
following the focused file of the active list, is an open decision
("Open decisions", 4). Whichever the owner chooses: entering the
preview is explicit, closing it restores the previous browsing state
exactly, pane boundaries and controls stay stable, and playback-control
focus does not change the source file list. Copy/move continue to use
that list's marked or focused files and the explicitly displayed
destination, as defined in the shared contract.

Broad preview includes text, code, images, PDFs, supported
Office/OpenDocument files, audio and video. Unsupported files receive
useful metadata, a reason and Open with. Inspect actual format coverage
before claiming support; archive content listing was discussed as a
possible extension, not a reason to delay the core work.

Audio and video remain paused until Play. Changing the previewed file
or closing preview stops playback and cancels obsolete work. Explicit
fullscreen playback returns to the prior Files state. This is file
inspection, not a background music workflow.

Retain useful existing zoom, pan, rotation, paging, waveform and
seeking capabilities where appropriate. Keep playback and preview
controls predictable: `play`, `pause` and their kin are controls, in
the controls' brush as `undo`, attach, the model and talk are; a key
chip is drawn only for a physical key. Previewing or selecting never
automatically attaches file content to a model or authorizes external
requests.

Read/render large files incrementally where supported and bound
decoder memory, work duration and caches. Show useful content or
controls before expensive optional analysis where possible. Cancel or
discard stale results so they cannot replace the current file. Preview
must not execute embedded scripts/macros or fetch external resources.
Missing decoders and malformed files fail within the pane with a
useful recovery action.

The first source inspection used snapshot
`337e78480272182dfd99a001cd30d44d1c9b9424`; main is now at v0.124.4
(`0c266b05bebab6262e718f4cf7de0eb2007dcaf9`) and this branch carries
it. `dialog/src/preview.rs` contains content and playback state; the
README documents media controls and sway video overlay behavior. That
was a source review, not live playback validation. In particular,
verify video overlay geometry, focus and cleanup through snapping,
scaling and fullscreen.

# Operations and large folders

Browse and search locally; open using the user's chosen applications.
Support copy, move, rename, new folder and Trash through native
validation and permissions. The shell side exists: `files_open`,
`files_preview`, `files_attach`, `files_reveal`, `files_rename`,
`files_move`, `files_copy`, `files_trash`, `files_restore`,
`files_new_folder` and `files_new_text` are provider tools with
receipts and undo (`tests/shell_test.sh` proves them).

Copy/move uses marked files, or the focused file when none are marked.
In dual pane, default to the other pane's folder and show the
destination before execution. Single pane uses an explicit destination
choice, picked from a list as every choice is. Capture the selected
source paths and destination at operation start; later navigation
never redirects ongoing work.

Never silently overwrite. The conflict question (Skip, Keep both,
Replace, applied to the remaining conflicts) is a component the dialog
does not have yet ("Open decisions", 5): until it is designed and
approved, a conflict refuses the item with its reason on the status
row and goes on with the rest. Trash is the normal deletion action;
unavailable Trash must not silently become permanent deletion. Report
completed, skipped and failed items, including after cancellation.
`undo` is a control on the status row beside the receipt (v0.124.4),
and typed `undo` at the prompt takes the last change back too; offer
it only when the step can truly be taken back.

Reuse the status row for operation feedback (v0.124.1): the march with
the action's words while it is felt, then the receipt with the real
file and byte counts and the destination, or the refusal. Keep
browsing usable while safe; prevent conflicting duplicate operations.
Do not invent percentages while discovering totals or confuse
cancellation with rollback.

Large folders must not block input or impose an arbitrary entry
cutoff. Render visible rows and avoid eager expensive metadata reads.
Preserve focus and selection by stable identity through loading,
sorting and refresh. Avoid constant reshuffling during discovery.
Cancel obsolete reads when navigating away. Do not recursively compute
folder sizes during browsing; expose that as an action.

Handle empty/no-match states, permission failures, disconnected
mounts, changed/disappearing files, long Unicode names, control
characters, symlinks and broken targets. Display filenames safely
without changing operation paths. Recursive operations must not follow
symlink loops. Make the scope of Select all clear: filtered results
versus merely visible rows. Reconcile behavior with existing native
path policy rather than silently broadening permissions.

# Native acceptance and delivery

The implementation team should exercise realistic scenarios during
development and report measured results. Mocks are for decisions, not
for routine; once the owner has approved the mock, build.

- Verify compact, fullscreen, left snap and right snap, including
  resize/restore with selection, scroll, preview and operations
  active. Preserve state and correct pointer hit targets. In a wide
  window the chrome spans the window and the column stays centered
  (v0.124.4).

- Test small usable areas, large text, short windows, portrait and
  wide displays; test mixed scale and monitor changes where available.
  Establish and document practical minimums. Identify scenarios
  unavailable in the test environment rather than claiming coverage.

- Test 10,000- and 100,000-entry folders, long similar filenames,
  changing directories and slow reads. Record responsiveness, time to
  usable content and memory.

- Exercise text, images, multipage PDFs, supported Office files, audio
  and video on Void. Include large/malformed files, missing
  dependencies, rapid focus changes, seeking, cancellation, fullscreen
  and cleanup. Verify configured resource limits.

- Verify selection semantics, destination capture, conflicts, partial
  failure, cancellation, Trash and truthful undo with native test
  files. Use repository-required checks and meaningful targeted tests.

- A files desktop proof of the same shape as `tests/apps_desktop_proof.py`,
  run on the owner's Void box through the local session, with the
  home and apps proofs beside it: they must still pass.

- Attach native screenshots from the delivered PR head for browsing
  and preview in the relevant modes, plus reproducible interaction
  evidence, under `tests/evidence/`. Check density, filename
  visibility, consistent font size, fixed controls and the status
  row. CI alone is not visual approval: the owner reads the
  screenshots.

# Visual direction

The accepted visual direction uses stable file panes and the shared
home frame. It predates the design page: where the two differ, the
page wins, and the mock in the page's notation is what the owner
approves. It does not prescribe pixel coordinates or exact bindings.
In particular: preserve extensions when truncating; do not duplicate
selection counts into the other pane; `play` is a control, not a key
chip; source paths must agree with the actual pane paths. The prompt
and its tools remain authoritative even where the illustration omits
or compresses them. Spacing and density are implementation acceptance
items.

# Cross module interaction contract

## Prompt scope and state

Where you are is in the header (v0.124.4): `home`, `apps . web`,
`files . ~`. Plain typing searches that scope at once; files searches
the current folder, with recursive search explicit (`files find NAME`,
`files say WORDS`). Module navigation restores that module's query,
focus and view state rather than reinterpreting another module's query.

Keep the request draft and explicitly attached context separate from
module filters and form fields. Switching scope or entering a form
must preserve the prior draft. Enter with words typed is never silent
(v0.124.4): the words open what the bar is on, run a command the dialog
has, or go to the model through the `ask spark` row; where none of that
can be, the status row says why. A mode that waits on Enter for
something other than the selection says so with its chip. Ctrl+Enter
asks, as a shortcut; a question, a credential field and a provider
form cannot ask. Nothing sends hidden filters or form values.

## Focus and activation

A menu's row acts on one click; an object's row (a file, a folder) is
selected by one click and acts on a second within 400 ms or on Enter
(v0.124.1). Marks for several files are an open decision ("Open
decisions", 3). The pointer resting on a row changes nothing: it never
moves the bar, the marked set or the previewed file.

Keep the active file-list pane, the focused control and the marked
files as separate state. Focusing a playback control does not turn
the hidden destination folder into a source. File actions while a
preview's controls are focused still use the source list's marked
files, or its focused file, with the destination shown. Closing the
preview restores the list and its state. Choosing another folder list
as active explicitly changes the source.

Every action is keyboard accessible through named configurable actions
and the key bar's chips. Do not rely solely on function keys or Insert.
The design's cues are the bar and the status row; a control in focus
wears the band. Full names and recovery actions must be accessible
without hover, which does not exist.

## Back and unsaved edits

Esc clears the status row's receipt or refusal with whatever else it
does (v0.124). It ends what stands nearest first: a filter, a form
(Esc lets it go, words typed or none, and asks nothing), a transient
control, a fullscreen preview; else it goes back a level; at home alone
it closes the dialog. Back has more doors than Esc (v0.124.3): with
nothing typed Left and Backspace, and a click on the header's `< back`
or its place name; none closes from home. Esc never cancels unrelated
background work.

There are no dirty forms (v0.124). A change applies at once with `undo`
on the status row: no draft, no save, no cancel and no question before
you leave; the Save, Discard or Keep editing question of v0.123 was
removed. A form that needs words (a new name, a new folder) is typed
in the prompt: the placeholder says what to type, the key bar says
`save  Enter`, Enter saves and Esc lets it go. The prompt's draft
survives a resize. Standalone commands remain explicit actions and use
their normal confirmation/receipt behavior.

## Operation lifetime

Transfers continue while navigating to home or apps. The status row
keeps the operation reachable without stealing focus; file identity
and destination are captured when the operation starts. Do not
introduce a daemon just to achieve this.

Closing home while a transfer is active asks a question (Keep open, or
Cancel operation and close) that the dialog has no component for
("Open decisions", 5). Until it is designed and approved: Esc at home
during a transfer refuses with the reason on the status row and the
dialog stays open; cancellation uses the shared Stopping state and
closes only after the outcome is acknowledged, retaining an honest
partial-result summary until the user can read it. Do not offer
background-after-close execution unless it is deliberately implemented
with an observable lifecycle. Abnormal termination must never imply
success or rollback.

## Shared geometry and feedback

One layout policy for every view, the design page's: the header, the
prompt, its tools, the rule with the diamond, the content, the status
row, the plain rule and the key bar, at the rows the constants in
`dialog/src/ui.rs` give them (v0.124.1, v0.124.4). The column is 60
cells for home, apps, help, about and the conversation, up to 120 for
a list with columns, the whole window for a preview; in a wider window
the chrome spans the window and the column stays centered. Files
takes the 120 and gives it to its rows.

The diamond is on the top rule, under the prompt's tools: full when a
model answers, hollow when none does or asking is off (v0.124.1). The
bottom rule is plain, the status row stands above it and one row of air
stands between it and the key bar. Transient states never consume that
spacing. The key bar is the view's and never changes under the pointer;
a control that cannot act says why on the status row. No
module-specific animation or progress system: the march on the status
row and spark's in the header are the only motion.

## Integration acceptance

Exercise home -> apps -> details and preferences -> home -> files ->
preview -> transfer -> apps -> home. Verify restored scope and drafts,
changes applied at once with undo, correct file action targets,
accessible focus, ongoing transfer status and the guarded close. Repeat
key portions after resize/snap and with the model off (the model page's
first choice) and with AI unavailable. Use native evidence from the
delivered revision; visual polish and green CI do not establish
interaction correctness.

## Delivery

Use safe local fixtures and representative real files with permission.
Keep originals unchanged; use disposable copies for transfer and
destructive tests. Do not publish personal media, filenames,
credentials or machine access details. Coordinate access to local test
material directly with the owner.

Validate the complete home -> apps -> files -> preview -> transfer ->
apps -> home journey, including AI unavailable, state restoration and
closing during a transfer. Report unavailable test configurations
honestly.

Continue on this draft PR, `files v0 for home`. Include
implementation, repository-required checks, native screenshots and
reproducible interaction results tied to the delivered commit. Main is
v0.124.4 or later; this branch carries it. Do not merge or release
without owner approval.
