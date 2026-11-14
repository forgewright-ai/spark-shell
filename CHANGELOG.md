# Changelog

## v0.147

The bar is spark's own: spark-bar, a new component.

- spark-bar draws the bar on every screen, at the top or the bottom: the
  logo, the workspaces, then the modules, each in cells kept for it, so
  nothing moves when a value changes. At the default size it is 36 px
  tall with 16 px text and a 24 px logo.
- A workspace's number wears the glyph family's key frame: angle
  brackets in stone, {2} in star, [2] in banner. Star's triangles and
  banner's Roman numbers are gone.
- Sound is the first module you act on from the bar: the sign mutes, the
  gauge takes a click and the wheel, the percent opens the section. A
  device that is missing, or a change that fails, is said in the same
  cells.
- spark-shell bar pin and unpin choose what the bar shows (BAR_PINS). A
  bar short of width drops modules in BAR_OVERFLOW's order.
- Super+equal puts the keyboard on the bar: the arrows move, Enter acts,
  Esc leaves.
- spark-shell on desktop fetches spark-bar, pinned by sha256, and it is
  started again if it ends. Where it cannot run, sway's bar draws the
  line as before. With the tray on, sway's bar hosts the apps' icons
  alone, at the bar's end.

## v0.146.1

- A window that floats keeps the desktop's frame, so its buttons stay
  where they are. An app that draws its own, like Firefox, gives them up
  and shows the band every other window has.
- A terminal rounds its size down to whole characters; those leftover
  pixels are now split between the two sides, so a placed window sits
  with even gaps instead of a wider one at the right and the bottom.

## v0.146

Punctuation while you speak, and a better line when you stop.

- The words are typed with their punctuation and capitals as they are
  said. The word still being spoken is left plain, so the line never
  takes punctuation back.
- When the key is released a larger model writes the line again, for the
  words and the punctuation a streaming model cannot get right.
- Super+period held listens too, with VOICE_PREFIX and VOICE_SUFFIX
  around the words. Super+Space stays plain.
- Every title band ends in the voice meter: eight cells kept for it,
  empty at rest, the levels while it listens. A window name longer than
  its band is cut short, so nothing on the band moves.

## v0.145

The voice is a window's, like its buttons.

- Super+Space runs once a press, not again on every key repeat. Held, it
  listens; tapped, it opens home. That is the shared key working.
- Every title band carries the mic, and the words go to the window that
  has the focus, whatever it is. What they mean is the window's own
  affair.
- VOICE_PREFIX and VOICE_SUFFIX are typed before the first words and
  after the last, so a line can open a prompt of your own.

## v0.144

Voice: hold Super+Space and talk; the words land in the terminal's line.

- Hold Super+Space, or click the mic on a terminal's band: the words go in
  the line as you speak, settled words only, never sent. Release, or
  click again, and they stay.
- The ear, a new component (spark-ear), hears the microphone through
  ALSA and runs sherpa-onnx with a streaming FastConformer model for
  English; spark-shell on desktop fetches both, pinned by sha256.
- Measured on a desktop machine: a word is typed about a second after it
  is spoken, 5% of words come out wrong, the ear takes a sixth of one
  core while it listens and nothing when it does not, and the engine and
  its model are 170 MB on disk.
- VOICE=no leaves the voice out; VOICE_ENGINE names your own engine, a
  command that speaks the ear's contract.
- The mic is red in every palette; while listening it is a dot, with
  five bars that follow your voice. It closes by itself after a minute.
- The words come out in lower case, without punctuation: that is what
  this model gives.
- wtype joins the desktop's packages.

## v0.143

One name through winpad, and no button that does not click.

- The pad's six settings are WINPAD_PLACE, WINPAD_WIDTH,
  WINPAD_SIDE_WIDTH, WINPAD_HEIGHT, WINPAD_VIEW and WINPAD_BAND. A config
  that names them PAD_ is still read, and spark-shell on writes the new
  names once.
- On a machine with no winpad the titles are plain: no close, minimize
  or fill is drawn there.
- A winpad that ends by itself is started again. One stopped on purpose
  stays stopped.
- The update removes the three files spark-pad left in the runtime
  folder.

## v0.142

One window component, winpad, and buttons that move with their window.

- Close, minimize and fill sit at the band's left end, in that order,
  drawn by sway as the start of every title. A dragged window carries
  them.
- On the focused window the buttons wear the title's color, on the
  others each its own: red, yellow and green from the palette. The one
  under the pointer lights as a chip in its color.
- The pad component is winpad now, under one name: the crate, the shell
  module and the files it keeps while it runs. Its three jobs have a
  file each: the pad for the minimized windows, the buttons, and the
  focus order. The pad keeps its name as the place where minimized
  windows wait.
- winpad lays the placed windows out again when a screen changes; the
  bar no longer does.

## v0.141

The focused window wears the accent, and the glyphs follow the window.

- The focused title band and its frame are the palette's accent, with
  the ground's color as text, as the bar's workspace block; the other
  bands stay four percent above the ground.
- The pad reads sway's tree the moment a window command has moved a
  window, told by a tick, and every tenth of a second for two seconds
  after any window event; its backstop is half a second. The glyphs no
  longer trail a placed window.

## v0.140.1

- An update to v0.140 in a running desktop left the pad off until the
  next login, so the title bands had no minimize, fill and close glyphs.
  sway starts the pad when it starts, and a reload does not start it
  again. `spark-shell on` now has sway start the pad, as login does,
  when the desktop is running and no pad is, so `spark-shell update`
  brings it up at once.

## v0.140

The window model: every window has a title band, the keys follow one
rule, and the pad draws the glyphs.

- Each window wears a title band with the app's name and what it shows,
  and a one-pixel frame in the band's own shade: the surface shade on
  the focused window, four percent above the ground on the others. The
  windows sit 8 pixels apart. The terminal's band says terminal and the
  folder the prompt is in.
- The keys: Super+arrow moves the focus, Super+Ctrl+arrow places the
  window (a half, a quarter, the whole screen past the top, the pad past
  the bottom), Super+Shift+arrow moves it in the tiling or to the next
  screen, Super+PageUp/PageDown the workspace before or after. Super+Tab
  goes back to the window before, and again to the one before that.
  Super+m minimizes, Super+q closes. A free window fills the screen or
  goes to the pad in one press.
- The pad runs for the session: it draws the minimize, fill and close
  glyphs at the right end of every title band and takes their clicks,
  and it keeps the order the windows were focused in.
- window place takes min; desktop window takes toggle, move and back.
- ALPHA defaults to 0.95: the windows are nearly solid.

## v0.139

The compositor and the terminal are spoken to through one module each,
and the desktop stays on.

- src/compositor.sh and src/terminal.sh are the only modules that name
  sway, its tools and foot, and lib/compositor.py the only helper; the
  module check refuses any other that does. Each implements a stated
  contract, so another compositor or terminal is one module behind the
  same calls.
- check has two new rows: the compositor and the terminal in use.
- Always on: the lock timer locks and no longer turns the display off;
  the idle screen is the resting state.
- CI times each family's package install and writes the seconds to the
  job summary.

## v0.138

The long functions are short ones with names, and the layout's state
files carry the layout's name. No change in behavior.

- The eight functions over 100 lines are each under 60 now: a
  dispatcher and named helpers. panel_rows and panel_act have one
  helper a section, tool_spec one a domain, provide_one and
  provide_call one a phase of a call, cmd_on and cmd_check_lines one a
  row, provide_files_call one a kind of step. The longest function in
  the shell is 96 lines.
- The layout's state files are layout.last and layout.pending; a file
  under the old name is moved to the new one once, on the next run.
- The credits name the five Monaspace faces the setup installs.
- The brand animation's frames and the script that drew them leave the
  tree: nothing in spark-shell used them.

## v0.137

Names say what things are, and every path written in the tree exists.
No change in behavior.

- test/paths_check.py scans the tracked files for references into the
  tree's folders and fails on any that names nothing; CI and the
  pre-push gate run it.
- The wallpaper crate's folder is component/wallpaper (the binary stays
  spark-wallpaper); the override SPARK_SHELL_WALLPAPER replaces
  SPARK_SHELL_PLAYER, which is still read for one release; the variable
  that says where a layout opens is LAYOUT_ON, with the values desktop
  and terminal.
- The shell modules are named by their domain: config, setup, undo, ask,
  rows, devices and facts replace read, verbs, step, want, provide,
  probes and machine; system.sh is notifications, storage and power; the
  layout code says layout_ where it said desk_.
- The python helpers are wifi, reminders, launch, running, terminal,
  dhcp, bluetooth and layout, with lib/shim/ for the terminal shim; the
  tests follow.
- The dialog crate keeps its login screen in login/ (mod, ui, run) and
  its animation module under that name.
- The three crates carry the release's version, a description without
  the brand and the repository.

## v0.136

The shell script is split into modules with declared interfaces. No
change in behavior apart from a few words in the help text and rows.

- Each module in src/ declares the globals it reads from other modules
  and the ones it sets at source time; test/modules_check.py verifies
  the declarations, flags functions that are never called and flags
  top-level references to modules sourced later. CI and the pre-push
  gate run it.
- core.sh is sourced first and holds the paths, the row printers, the
  CLI flags and the signal traps. font_quiet.sh and session.sh are
  merged into their domains; sources.sh is renamed sections.sh;
  tools.sh and files.sh are split into tools.sh, mcp.sh, files.sh,
  preview.sh and files_provider.sh. Six unused functions are removed.
- The help text and user-facing rows refer to the desktop, the terminal
  and the login screen instead of the underlying programs; rows that
  name a package to install keep the package name.
- The animation scripts move to lib/ and write to gallery/animation and
  the brand frames' folder by default.
- Comments in the ten largest modules are cut by half.

## v0.135

The record starts here.
