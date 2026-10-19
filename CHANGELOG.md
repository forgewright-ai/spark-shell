# Changelog

## v0.74

The login screen after its first real boot (the owner's checks at the
screen: a click on desktop or shell did nothing, lines printed before
the screen; and his ask for an idle screen saver, the standard kind).

- Fixed: the mouse on the login screen. A click on desktop or shell
  picks it, a click on a field or its label moves the focus there, and
  a click on a key chip or its words does what the key does: F11 and
  F12 still open the confirm, which still takes a typed yes. The
  screen and the clicks share one layout, and a test clicks every
  target on the drawn screen.
- Fixed: the lines on tty1 before the login screen (swaybg's `Found
  config` and a foot warning). The screen's session clears tty1, hides
  its cursor and sends what sway, swaybg, swayidle and foot say to
  login.log in the screen account's runtime directory.
- Added: after five idle minutes the login screen turns the display
  off (swayidle, `output * power off`); a key or a mouse move turns it
  back on. Nobody is logged in there, so nothing is locked. The
  desktop's own idle and lock is a decision of its own.
- Changed: PKG_LOGIN is greetd and swayidle on Debian, Arch and Void.

## v0.73

The login screen, the Login component (the owner's picks from the
mock-ups: the strip down the left, dots for the password, no account
listed, no AI before a login, spark's state without its address or
its model, the distro and its version).

- Added: `spark-shell on login` and `off login` (and `login on|off`),
  a switch of its own beside the desktop: LOGIN=yes in the config.
  From the next boot greetd shows the login screen on tty1: sway with
  one foot window that fills the screen, clear over the wallpaper
  (never fullscreen, where foot draws its background solid), running
  `spark-dialog login`. On the strip: the machine's name, its Linux
  (PRETTY_NAME, and the kernel when the distro has no version, as Void
  and Arch), the date and the time; the form for a user name, the
  password (a dot each character), the desktop or a shell; a hint;
  spark ready or not running; F11 restart and F12 shut down, each after
  a typed yes.
- Added: `spark-dialog login`, in the one binary the tree pins. It
  talks to greetd over its socket (create_session, the password as the
  answer to PAM's first question, start_session with your login shell).
  The password is in one buffer, wiped when it is sent, cleared or
  dropped, and never logged. A wrong try says only `Wrong user name or
  password.` An account that asks for more than a password is refused
  in one line.
- Added: the root files, written when they differ and named in the
  question first: /etc/spark-shell/login (the session, the window, the
  palette, sway's and foot's settings, the wallpaper), a copy of the
  pinned dialog in /usr/local/lib/spark-shell, greetd's config.toml (the
  package's kept as config.toml.spark-shell-orig). On Void the screen's
  account joins `_seatd`, and a sudoers file, checked by visudo first,
  lets it run reboot and poweroff, nothing else.
- Added: tty1 changes hands only at a boot. systemd enables greetd and
  disables getty@tty1, starting or stopping neither. On Void a line in
  /etc/rc.local runs login-boot before runit starts its services. tty2
  keeps the console login. `off login` undoes exactly what the records
  in /etc/spark-shell/login say, and while greetd runs the screen's
  files stay until the next boot.
- Added: `theme` and the wallpaper reach the login screen too. status
  and check have a login row. The shell session the screen offers
  never starts the desktop (SPARK_SHELL_SESSION=shell, read by the
  rc file).
- Changed: the help, the README, config.example and CREDITS (greetd)
  name the login screen.
- Fixed: status named the ground's color before it had read the
  palette, so the wall row said `()` and the shell printed an error.

## v0.72

Ten wallpapers ship with spark-shell (issue 10, the owner's word).

- Added: `wallpaper/`, ten wallpapers drawn for the palettes, each its
  SVG source and a 3840 by 2160 PNG: skyline (tokyonight-night), fjord
  (nord), forest (everforest-dark), sunset (gruvbox-dark), hills
  (catppuccin-mocha), dunes (dracula), ripples (rose-pine), contours
  (selenized-dark), morning (solarized-light) and embers, in spark's
  ember hues, for any dark palette. Flat shapes in each palette's own
  colors, the detail at the edges and the bottom, the middle calm
  behind the windows.
- Added: `spark-shell desktop wallpaper NAME` takes one by its name;
  the config keeps the name and the clone's own file is drawn, so it
  follows the clone. No palette's default changes.
- Changed: the dialog's wallpaper section lists them in a group of
  their own, each with the palette it was drawn for and a sample of its
  main color, then the colors in theirs. A row's first column lines up
  on its right edge only when it is a number (a size, a count); words
  line up on their left.
- Fixed: a section's subtitle follows its state. It was read once when
  the dialog started, so after a pick the header still said the old
  wallpaper, level or palette; each rows read now carries the state.

## v0.71

Found by hand at v0.70, and the owner's picks (issue 9).

- Added: the Calendar. The clock section shows the time in large
  figures and this month, today lit; the left and right arrows show the
  month before and after. A click on the clock opens it.
- Added: `wallpaper` is a section of its own, beside theme: default,
  none and each color with a sample of its color, and `a picture`,
  which opens your home folder offering pictures (jpg, jpeg, png, webp);
  Enter on one sets it. The tools are wallpaper_use and
  wallpaper_picture, and `desktop on` puts the new section on spark's
  MCP list too.
- Changed: transparency, the industry's word, in place of see-through:
  `spark-shell theme transparency more|less` (see-through is still
  read), the rows "transparency 15%", "more transparency", "less
  transparency", and the tool theme_transparency.
- Changed: the sections are grouped by what you do: apps, layout and
  window; out and mic; bt and wifi; theme, wallpaper and bar; then files
  and about. The home dialog shows three apps and a more row.
- Changed: the hint is the keys alone, the arrows as one key, then Esc,
  which closes, or goes back where there is a view to go back to.
- Changed: plus, the model and talk are drawn as plain text, for they
  are controls, not keys; the one Tab focuses is lit, and talk while it
  listens or plus with a file attached is in the accent.
- Fixed: a click on the prompt sign at the end of the bar opens the
  whole dialog at its prompt; it opened an empty clock page.
- Fixed: the about is a page of its own and shows no exchange, and its
  tagline is gone.
- Changed: on plain ALSA, when your own ~/.asoundrc or a file it
  includes picks the sound device, out and mic list the devices with no
  pick that could only be refused, and one row names that file; a
  refusal names it too.
- Changed: American spelling everywhere, color; tmux keeps its own
  spelling in its syntax. The status row names the slots as slot 3. The
  wallpaper colors list gray once (grey is still read).
- Changed: the text list's section column is nine wide, as wide as
  wallpaper, the longest section's name.

## v0.70

The desktop's tools on spark's MCP list (issue 8, his word on the card).

- Added: with spark 1.90 or newer, `on desktop` puts each of the 15
  providers on spark's MCP list through `spark mcp add NAME
  ~/.spark-shell/spark-shell provide NAME` (the clone's own path), so
  the prompt line, `spark do` and /do know the desktop's tools. A
  server of yours already listed under one of those names stays, and a
  row says so; a line an older clone wrote is replaced. spark-shell
  never writes spark's file itself.
- Added: `off desktop` and `off` take spark-shell's own lines back with
  `spark mcp rm NAME`, and `off --dry-run` names them.
- Added: a check row, mcp: the 15 providers on the list, or how many
  with the remedy. With an older spark it is na and nothing is written.

## v0.69

The want path asks spark's planner (issue 7, his word on the card).

- Changed: with spark 1.90 or newer, words that match no row go to
  `spark steps`: the desktop's tools on its stdin (the sections offered
  here, the about and undo, never the files', whose path is picked and
  never said), and as its about the bar's facts and the names each tool
  takes now (the outputs, devices, networks, windows, layouts and apps,
  as the rows write them), so "play it on my headset" names the headset
  as listed. A name not listed whole is refused in one line, never
  guessed. Each step comes back as a tool call, maps to its section's
  step and is checked against the list as before. Measured on a Void
  machine with gemma4-26b-a4b, 22 wants three times each: 58 of 66
  right where the old path had 39, in the same time (p50 4.4 s). Six of
  the eight left were refused in one line because the machine was
  already that way (the mic not muted, new windows already side by
  side); two wrote less see-through for fully solid.
- Changed: on that path, words that get no step get the answer or the
  one line, no step on the panel does that. spark picks `layout new`
  itself for a task, so the shell no longer turns a stray sentence into
  a layout (make me a sandwich).
- Added: the dialog plays a planned undo as its undo row, and a planned
  about opens its about.
- With an older spark the path is the one before.

## v0.68

Found by hand at v0.67 (issue 6).

- Changed: the logo in the about is sharp. The favicon is pixel art, and
  at a 19 px row its blocks fell between pixels, each color was cut to
  16 levels, and the thin shadow lines were lost. The dialog now draws
  it as a pixel grid snapped from the favicon: a block 2 by 3 pixels, a
  shadow line 1 pixel, the prompt sign the same above and below its
  tip, the exact colors, at a whole multiple of its 18 rows (36 on a
  HiDPI screen). A row shorter than 18 pixels keeps the 16 px logo.
- Added: on plain ALSA, a Bluetooth headset that bluez-alsa offers is
  listed in out and mic beside the cards. A pick plays on its A2DP link,
  or listens on its call link (SCO), for programs started from then on,
  in spark-shell's own ALSA file; the bar names it, and its level and
  mute are bluez-alsa's mixer. A card picked after it takes the playing
  back and keeps the headset's mic.
- Fixed: when your own ~/.asoundrc, or a file it includes, sets the
  default device, a pick in out says so and writes nothing. Before, a
  card pick wrote a file your default overrode.

## v0.67

Found by hand at v0.66 (issue 5).

- Fixed: the about opened from the home dialog, by its row or by typing
  about, now shows the logo. It showed only when the dialog started on
  the about. Its cells are blanked first, so the clock of the home
  dialog never shows through the logo.
- Fixed: the arrows in the hint are key chips, as Esc is: a key named on
  the screen is a chip, everywhere.

## v0.66

Found by hand at v0.65 (issue 4): the about could not be found, and a
mistyped word opened an app.

- Fixed: a search in the dialog finds the about's own row. v0.64 left
  the whole about section out of a search, so typing `about` showed
  nothing; the key sentences still stay out.
- Added: a section's name typed alone (`about`, `files`, `wifi`) and
  Enter opens that section. It never goes to the model, and a theme row
  is never applied by typing `theme`.
- Added: when the list is longer than the dialog, its last line says how
  many rows sit below (`8 more`).
- Fixed: a word or two that gets no step from spark is now the one
  honest line, no step on the panel does that. Since v0.55 such words
  were a task and a layout opened for them: `about` opened aerc in a
  workspace named about. Longer words that name a task still open a
  layout, as `writing with vi and the prompt shell` does.

## v0.65

The last release of the dialog's arc (issue 1): files, the first new
provider.

- Added: `spark-shell provide files`, the folders the host hands over as
  its roots (MCP `roots/list`; the dialog hands over your home) and a
  rows resource per folder under them: its folders, then its files with
  the size and the date as columns, a folder's own rows as its children,
  `..` back up, the count and the size at the end. Three read-only
  tools: open (the app for the file's kind, through xdg-open), show (a
  text file's first lines) and attach (a text file for the next words).
  Every path is held to four named lines before anything reads it: it
  resolves to itself (no link is followed), it sits under a root (never
  / itself), no part of it is hidden, and it is a regular file or a
  folder.
- Added: the files section in the dialog, a folder view that drills
  down and walks back with Esc, and its columns lined up.
- Added: plus in the composer. It opens your home filtered by
  `DIALOG_ATTACH_TYPES`; Enter on a file attaches it (the chip shows its
  name), the next words go to spark as a question about it
  (`spark-shell want --attach`), and plus again lets it go. The dialog
  checks the file sits under your home before anything reads it.
- Changed: the dialog declares the `roots` capability now that a
  provider uses it, as the review asked.

## v0.64

The second release of the dialog's arc (issue 1): the dialog replaces
the panel on the desktop.

- Added: the dialog, one window of 60 by 44 cells in the middle of the
  screen. A one-row header: the date and the time on the home dialog, a
  section's name and its state on its own, a march while a step runs,
  and close as x. The rows of every section under it, the exchange
  above the hint with the newest line nearest the prompt, then the
  prompt and two chips, the model and talk. Super+d and Super+s open
  it, a click on a bar block opens it with that block first, and the
  about dialog takes the splash's place at the first desktop start.
- Added: `spark-dialog`, a Rust MCP host (`dialog/`), one static musl
  binary. It starts every section as `spark-shell provide SECTION` with
  no shell and a named list of settings, reads each tool's hints with
  the spec's defaults, gates every step the model picks (a tool listed
  now, its arguments by its schema, a name that is a row's own), asks a
  typed yes for a step that cannot be taken back, masks a password and
  keeps it nowhere, scrubs every string a provider hands it, caps lines
  and resources, times every request out, and keeps one line per step
  in `~/.local/state/spark-shell/audit`, numbers and names only. It
  uses its own client rather than rmcp: the SDK's client alone is 65
  crates of an async runtime, and the dialog needs none.
- Added: the binary's channel. The release workflow builds `dialog/` at
  a signed tag, refuses to publish when the build's sha256 is not the
  one `dialog/dialog.env` pins in the tagged tree, attests the build and
  publishes the binary, its sha256 and its SBOM. `spark-shell on`
  installs the binary only from the release of a tag a key in the new
  `allowed-signers` signed, only when the file has the tree's sha256,
  and `spark-shell dialog` runs it only while it still has. The build is
  reproducible: CI builds it twice and compares.
- Added: `spark-shell dialog [SECTION|about|chat]`, the window's verb.
  On a Mac, `spark-shell panel` stays the list in the terminal.
- Changed: the providers' rows carry a group and the arguments the
  dialog asks for (a new network's password, a layout's name); the
  about's rows are the keys.
- Changed: the key sentences open with one combo and a verb each, so
  the about shows them in two columns; Super+d and Super+s say the
  dialog. The README follows them.
- Added: a dialog job in CI (the format, clippy, the golden renders in
  two palettes, the host against stub providers, the build twice, the
  binary at a pty with no network, cargo-deny) and a zizmor job over the
  workflows; Dependabot for the actions and the dialog's crates.

## v0.63

The first of three releases for the dialog that replaces the panel
(issue 1). Nothing on the screen changes.

- Added: `spark-shell provide SECTION`, every panel section but spark as
  an MCP server on stdin and stdout, protocol 2025-06-18. Its steps are
  tools with a title the model may say (`wifi connect NAME`), a closed
  input schema and every hint written out, since an unmarked tool counts
  as destructive. Its rows are the resource `spark-shell://SECTION/rows`,
  a host that subscribes is told when they change, and a long step
  reports its progress. A call runs only a step the section offers now,
  with a row's own argument, then the panel's own check. A result
  carries the step that takes it back. Only MCP reaches stdout. spark is
  no provider: its one row is the chat, which the dialog holds itself.
- Added: `spark-shell want "WORDS"`, the panel's prompt from anywhere;
  `--json` prints the steps spark picks, each checked and named as a
  tool, and runs none, for the dialog; `--attach FILE` asks spark about
  a text file, sent by its name alone.
- Added: the dialog's keys, `DIALOG_ATTACH`, `DIALOG_ATTACH_TYPES`,
  `DIALOG_MODEL` and `DIALOG_TALK`. The types default to `txt md`, not
  the five first planned: spark reads text, so a PDF or a picture waits
  for a reader of its own.
- Changed: the favicons have no ground of their own, and come as PNGs at
  the heights of a terminal row, 16, 19, 22 and 26 pixels, dark and
  light.
- Fixed: a network, a device or a window named with an escape or a
  direction control could redraw the panel; such characters are dropped
  from every name. A name with a star or a bracket in it is used as
  written. The panel's journal folder is yours alone.
- Changed: the README says a window's name rides a want, as it does, and
  a file only when you attach one.

## v0.62.1

- Fixed: a terminal window was listed as `foot`, so `close aerc` found
  nothing; it goes by what runs in it now. A close or focus step acts on
  one window by its id, never on every window of an app. `apps close
  NAME` is read as `window close NAME`.

## v0.62

- Fixed: a want typed at the splash, or a pick in the panel, ran on a
  blank window with only the march showing. The glance is drawn again
  before the step runs.
- Fixed: words about closing an app, as `close the window with
  firefox`, opened it. They never open an app or a layout now.
- Added: `window close NAME` and `window focus NAME` for the windows
  that are open. Typing a window's name finds the rows, and spark picks
  them from the list.

## v0.61

- Added: the splash. The first time the desktop starts, the panel's
  window opens over the first terminal with the logo, the version, the
  keys, the licence and the address, and the prompt under them. The
  panel's new `about` row, last in the list, shows it again. The first
  terminal no longer prints the keys.
- Added: a sign in the panel's top right corner; a click on it closes
  the panel, as Esc does. With fzf 0.57 or newer, fzf holds the date and
  the time as its first lines, so the corner hears the click.
- Changed: a key named on the screen looks like a key: the hint under
  the list reads the arrow keys, pick an option, or say what you would
  like, Esc closes; the splash and the receipts that name a key follow.

## v0.60

- Changed: the default wallpaper is the ground, the palette's
  background a shade darker than the windows, and it follows the
  palette. The forge picture leaves the repository. `default` means the
  ground; a picture of yours by path, a color, or `none` work as
  before.
- Added: spark-shell's own sign at the far right of the bar, the prompt
  sign in the palette's yellow. A click on it opens the panel as
  Super+d does.

## v0.59

- Added: the logo, in `assets/`: spark's block-letter S with the prompt
  sign and a cursor cell, in two inks by the ground, and a favicon for
  each. The README shows it. Nothing else changes.

## v0.58

- Changed: the list after Super+d is short, each section's state and
  everyday steps; `theme` is one row with the palette and the font
  size. Typing searches everything the panel can do, shown or not, so
  a palette is still one Enter away from anywhere. The prompt cleared,
  the short list is back.
- Added: `bar` in the panel, `hide` and `show`, remembered across
  reboots as before.
- Added: `window` in the panel: side by side, tabs or stacked. It sets
  the workspace you are on now and is remembered for new ones, as
  `WINDOWS` in the config. The keys that do the same, Super+w,
  Super+Shift+s, Super+e, Super+b and Super+v, are in the keys list.
- Added: `apps  terminal`, a terminal window from the panel, as
  Super+Return.
- Changed: alpha is said as see-through. The theme section shows
  `windows see-through 15%`, with `more see-through` and `less
  see-through` as the steps, in tenths. The config key is still
  `ALPHA`, and `theme alpha N` still works.
- Changed: a terminal window is titled `terminal` at the prompt and
  with the program's name while one runs, so sway's tabs never say
  `foot`.

## v0.57

- Changed: the march has one place, the top right corner of the
  window, on the date's row, whether the panel is looking around or a
  pick is running. The lines of a step land under the clock as before.
  The window keeps two fixed places: that corner, and the bottom with
  the hint and the prompt.
- Changed: the bar has no `theme` block. Every click on the bar opens
  the same panel, and the palette is picked there.
- Changed: a plain color wallpaper is drawn like a picture, with the
  gaps around the windows and the translucent terminals and bar. Only
  `none` gives full, opaque windows. A running sway gives the gaps to
  the workspaces already open, not only to new ones.

## v0.56

- Changed: one view behind every door. The panel opens on the date,
  the time large beside this month, and an alarm in red when there is
  one; the facts stay on the bar, and a block's title line is gone
  from the window. The window is 76 by 36 cells, so the list keeps
  its rows. The time keeps the minute while the panel is open. A
  click on the clock opens the same view.
- Changed: a pick that opens an app or a layout closes the panel. The
  window is the receipt. A pick that could not open stays, with why.
- Changed: with the focused window fullscreen, Super+d still shows the
  panel: the window steps aside, and is fullscreen again when the
  panel closes with nothing opened.
- Fixed: a palette or a font picked in the panel was drawn with the
  shades the panel opened with, and the facts named the old palette.
  The panel reads its settings again after every pick and paints its
  own window.
- Fixed: the window left its temporary files behind on every run.

## v0.55

- Changed: the panel is a surface, not a framed window. Its background
  is a shade of the palette's towards the text, the windows behind it
  keep theirs, the border is gone, and there is air around the text,
  sized from the font. The picked row is lit across the window. The
  window is 76 by 30 cells. Super+s opens spark chat on the same
  surface.
- Changed: the glance after Super+d starts with the date, the time at
  the right edge, and the facts under them, muted. It no longer calls
  itself `bar`.
- Changed: every row names its section in a column of its own, muted,
  so the things line up: `wifi` and `layout` begin their text at the
  same cell. The section that opened the panel is in the accent on
  its title line.
- Changed: the clock. The time is drawn in strokes two cells wide, so
  the figures keep their shape, and this month sits beside it with
  today a chip in the accent, the week names and the days four cells
  apart.
- Fixed: a theme picked in the panel repainted the panel's own window
  flat; it takes its surface again.
- Needs fzf 0.54 or newer for the lit row and the pointer gone; an
  older fzf gets the same list with a one-cell pointer.

## v0.54.1

- Changed: the layout's model reads the need part by part, at `and`
  and commas, one window each: `notes and firefox` is an editor and
  Firefox, never one window for both.
- Fixed: `firefox fullscreen` opened Firefox and skipped the
  fullscreen. An app's name with a layout word beside it is a layout.
- Fixed: words that are no question and get no step from spark, as
  `writing with vi and the prompt shell`, were answered with the bar's
  facts. They are a task now, and a layout opens for them.

## v0.54

- Changed: a layout opens what your words ask for, all of it, and
  nothing else. Every window spark proposes now carries the words of
  yours it is for, quoted back, and spark-shell checks the quote
  against your words. `notes and firefox` opens Firefox and the editor
  spark picked for the notes. A window tied to none of your words, or
  only to a word like fullscreen, is padding: it does not open and is
  offered as a row. Apps your words name still always open.

## v0.53.2

- New: what spark also suggested for a layout is one Enter away. After
  `notes and firefox`, the panel offers `layout  also open micro`, and
  Enter opens it on that workspace. Your words still decide what opens
  by itself: the apps they name.

## v0.53

- Fixed: `Firefox workspace 2 fullscreen` at the panel opened two
  Firefox windows and then asked spark for more, which answered that
  it could not. An app named in more than two words is a layout for
  the whole sentence, and that is the whole answer. A named app opens
  once; the model's second copy is dropped.
- New: a layout can be fullscreen. Say `fullscreen` and the main
  window fills the screen alone once it is there. Say `workspace 3`
  and the layout opens there. Both are read from your words by
  spark-shell itself, never left to the model.
- Changed: a layout asked from the panel closes with the workspace
  alone, since the panel has its own row to save it.

## v0.52.2

- Fixed: a pick or a want from the window failed with "march: not
  found" since v0.51. The pulse's kind was handed to the command as
  its first word. The window now has a test of its own, driven by a
  stand-in for fzf.

## v0.52

- New: undo. Every step, from a pick or a want, writes its inverse
  before it acts; one row, `undo  theme everforest-dark, out unmute`,
  stays at the top while the last thing done can be taken back, and
  Enter puts it back. Sound, palette, font, wallpaper, alpha, Wi-Fi
  and Bluetooth connections can be taken back; a layout and an app
  opened cannot, and say nothing.
- New: the apps are rows. Each app a layout may open is a row, and
  Enter opens it on this workspace the way its desktop entry says. One
  or two words that name an app open it at once, with no model asked;
  more words that name one open a layout for the task.
- New: `layout  save what is open now` turns the windows on this
  workspace into a saved layout, under a name you type.
- New: the rows you picked most recently come first, in that order,
  while they can still be picked. The panel keeps the last five.
- The journal is two plain files under the state directory, `undo`
  and `recent`.

## v0.51

- Changed: the panel draws at once and fills in place. It opened only
  after the Wi-Fi scan and the Bluetooth list had answered; now what
  costs nothing to know draws first, the scan and the list keep their
  last answer with its age (a minute, half a minute) and land in the
  list while a march says the panel is looking. A pick, a want and a
  layout show a pulse with the seconds from two, and each line of what
  was done as it lands. A check is a step done, a cross one refused.
- Changed: the glance. After Super+d the first lines are the date and
  time, the bar's facts in words and, when there is one, an alarm on a
  line of its own: `lan down`, a low battery, a recording mic.
- Changed: sections in order of use, spark, layout, out, mic, theme, bt,
  apps, wifi, and a long one shows what matters with a row for the
  rest: wifi the network in use, the saved ones and the strongest
  three, then `N more`; theme the palettes and the font, then
  `wallpaper and alpha`.
- Fixed: `Firefox fullscreen` at the panel opens a layout with Firefox,
  every time. Words that name an app this machine declares are a
  layout by the machine's own word, not by spark's reading of them,
  which had answered "I cannot" twice. A word that is merely a command,
  as `what`, is not an app.
- Changed: a click on the clock shows the time large, five rows tall in
  the palette's accent, and this month under it, today in the accent. The
  month is no longer a list of rows.
- Changed: a question at the prompt has what the bar shows, so `what is
  my address` is answered with the address.

## v0.50

- Changed: one door. Super+d opens the panel, Super+s opens it already
  in spark chat, and Super+p is gone: the two panel keys opened the
  same list. A `spark  chat` row is the panel's first; Enter on it
  opens the conversation in the same window.
- New: a question at the panel's prompt is answered there, in a
  sentence or two. A change is still played as steps.
- Changed: `spark-shell panel chat` is the chat verb; `desktop --chat`
  still works. The chat window is the panel's, one rule in sway.

## v0.49.1

- Fixed: a palette picked after login did not reach the bar's name, and
  the panel could refuse the pick as the palette in use. spark-shell
  exported its settings and then started sway, so every window, the
  bar and the panel kept the settings of login time, and a key in the
  environment won over the file. The file wins now, and sway starts
  without the keys.

## v0.49

- Changed: the panel stays while the mouse moves. It closed when the
  focus left it, and the focus follows the mouse. Esc closes it, and
  so does the key that opened it, pressed again.
- Fixed: a want that names a program or a task, as `Firefox
  fullscreen` or `write notes`, becomes a layout step. The list given
  to spark read "new WORDS", and the model copied those words back as
  a step the panel refused.
- Changed: `look` is `theme`, on the bar and in the panel. A palette
  row is its name alone.
- Changed: less to read. A row names the thing and its sign says what
  Enter does: a ring before a network connects it, a dot before it
  disconnects, a ring before an output switches to it. The line under
  the list reads "Pick an option, or say what you would like." A step
  says what it did in a few words, as `theme dracula` or `font 12`. The
  model's why line is gone; the steps say it. The highlighted row is
  the cursor. `bt` rows read `find new devices` and `turn off`.

## v0.48

- Changed: one panel. The bar's panel and the layout prompt are one
  window now, the same size and place every time, in the middle of the
  screen. Super+p opens it, Super+d opens it with your layouts first,
  a click on a bar block opens it with that block first. One list in
  sections: `layout`, the bar's blocks, `apps`. Words at the prompt are
  a want across all of it: `movie night` can set the output, the
  palette and open a layout. `spark-shell panel [WHAT]` and
  `spark-shell panel "WORDS"`; `bar panel` and `bar "WORDS"` still
  work. The panel no longer moves under the block you clicked.
- Changed: signs. A dot for in use or connected, a ring for available,
  a check for current or saved, a triangle for a row that opens
  something; a warning sign on the bar with `lan down` and a low
  battery, a red dot after `mic` while a program records, a dot after
  `bt` with a connected device. The prompt is the same angle starship
  draws. The look rows are the palettes' names alone.
- Changed: spark chat's window has the panel's size and place.
- Gone: the layout prompt's own window and its picker of saved
  layouts, the panel's own placement. `spark-shell layout --ask` opens
  the panel with the layouts first.

## v0.47

- Changed: the panel is the bar's, not the block's. A click on a block
  still opens it right under that block, with a line about the block,
  but the list below holds everything the bar can do right now: the
  block's rows first, then the other blocks' in the bar's order, each
  row with its block's word in front. Typing narrows across every
  block, and the prompt asks what you want to change: `mute everything
  and dracula, I need some quiet` is played as steps from that same
  list. Tab is gone, the list is one. Super+p opens the panel with no
  block picked, its first line the whole bar restated.
- Changed: the rows say what Enter does: `connect cafe`, `disconnect
  home`, `pair Buds`, `use HDMI`. A few letters match as typed, not by
  skipping letters, so words that are a want never land on a row by
  chance.
- The window is 4 rows taller.

## v0.46

- New: the bar's panel. A click on a block opens a small window right
  under it, in the palette's colors: a line that says what the block
  is about, a list where Enter acts, a hint row and a prompt. Super+p
  opens it from the keyboard, Tab walks the pages, Esc or a click
  anywhere else closes it. `wifi` lists the networks around and
  connects, disconnects and forgets; `bt` connects, disconnects, looks
  for new devices and pairs; `out` and `mic` switch devices and mute;
  `lan`, `bat` and the clock show the address and speed, the charge
  and time left, and this month.
- New: `look`, a last block with the palette's name. Its page sets the
  palette, the font size, the wallpaper and alpha, and applies the pick
  now.
- New: words at the panel's prompt, or `spark-shell bar "WORDS"`, are
  what you want. spark turns them into steps from what this machine can
  do right now, spark-shell checks each step against that list, plays
  it and says what it did.
- New: `mic` has a gauge like `out`, set the same way, where the mic
  has a level control.
- Changed: the bar never changes width. The address no longer swaps
  into the `lan` or `wifi` block for 5 seconds; the panel shows it. A
  click on `out` opens its page instead of moving to the next output
  without a word, and a click on `mic` opens its page instead of
  muting it; the mic gauge's right click mutes.
- Wi-Fi is set through nmcli, iwctl or wpa_cli, whichever answers on
  this machine.

## v0.45.1

- Fixed: on plain ALSA, a click on `out` wrote a file ALSA refuses, and
  with it ALSA dropped its whole configuration, so every program lost
  its sound until the file was gone. The line said `defaults.pcm.card
  NAME`; alsa.conf sets that card as a number, and only
  `defaults.pcm.!card NAME` may replace it with a name. The bar writes
  the `!` form now, mends a file v0.45 wrote when it starts, and takes
  back at once a file ALSA still refuses, saying so in the block for 5
  seconds.

## v0.45

- New: a bar at the top of the desktop's screen. On the left the
  workspaces, and a workspace a layout opened carries the layout's
  words, as in `2 news`. On the right, in groups parted by a thin line:
  `lan` and `wifi` and `bt`, then `out` with the volume gauge and
  `mic`, then `bat`, then the date and time. A block appears only for
  hardware this machine has.
- The kind word is muted and the name is in the text color, as in
  `out jabra`. Color is for alarms: `mic` is red while any program
  records, and so are `lan down` and a battery under 15.
- The volume gauge is the one thing you can set. A click sets the level
  where you clicked, the wheel nudges it by 5, a right click mutes. A
  click on `out` moves sound to the next output, a click on `mic` mutes
  or unmutes it, a click on `lan` or `wifi` shows the address for 5
  seconds. The volume keys and the mic mute key do the same.
- Sound comes from the audio system you have: PipeWire (wpctl),
  PulseAudio (pactl), or plain ALSA (amixer). On plain ALSA a change of
  output holds for programs started afterwards and is written to
  `~/.config/alsa/asoundrc`, spark-shell's own file, which
  `spark-shell off` removes.
- `spark-shell bar on|off` now sets both the status line in tmux and
  the bar. `--terminal` or `--desktop` picks one. The config key is
  `DESKTOP_BAR`. `status` has a `bar` row and `check` a `top` row.

## v0.44

- A layout line with a comma in an `exec` is refused. sway reads a
  comma as the start of a second command, so a layout from the model
  could have run a program nobody checked.

## v0.43

- `spark-shell layout` now always opens the apps your words name, even
  when spark left them out: "writing with vi and shell window" opens a
  shell and vi. Other apps spark picks are only suggested. spark's
  reason for its picks is shown only when the layout opens exactly as
  spark answered.
- `spark-shell theme NAME` now changes the colors of the terminals you
  have open on Linux, foot windows on the desktop too. Before, they
  kept the old colors until the next login. Inside tmux the colors
  go to the terminal tmux runs in. `theme none` gives each terminal
  its own colors back. One line says how many terminals changed.
- New: `spark-shell desktop wallpaper COLOR` puts a plain color
  behind the windows: `#rrggbb` or a name such as navy or teal. The
  color stays the same when you change the palette. It is saved as
  `#rrggbb` in the config.
- `spark-shell desktop wallpaper` now takes a path from where you are,
  or one that starts with `~`, and saves it as the full path.

## v0.42

- `spark-shell on` now says what it will change and asks
  `Continue? [y/N]` first. So do `on desktop` and `quiet boot on`.
  `--yes` skips the question. `off` never asks.
- The login screen is now the normal console login on every Linux.
  Logging in on tty1 starts the desktop, and leaving the desktop logs
  you out. Alt+F2 gives a plain shell. greetd and tuigreet are no
  longer used, and the fire background is gone. If v0.41 set up
  greetd, `spark-shell on` turns it off from the next boot. Its
  packages stay.
- The desktop now works on Void too. `on desktop` turns on the seatd
  service and adds you to the `_seatd` group (sudo).
- New: `spark-shell layout "WORDS"`. spark picks apps for what you
  describe and opens them: as sway windows on the desktop, or as tmux
  windows anywhere else (`--desktop` or `--terminal` to choose). Apps
  your words name are opened, and other apps spark picks are only
  suggested. `layout save`, `layout NAME`, `layout delete NAME` and
  `layout` save, open, delete and list layouts in
  `~/.config/spark-shell/layouts/`.
- New: `spark-shell apps` chooses which apps a layout may open.
- In a layout the editor is `$EDITOR`, else micro, else vi. A missing
  app is skipped, said in one line.
- The README, the help and every message are rewritten in plain
  English. The status row for the desktop is now named desktop.
- The studio example layout is gone from the repository.

## v0.41

- The palette, the font and quiet came home from spark core, which
  dropped `spark theme`, `spark font` and `spark quiet login|boot` in
  1.62. They are `spark-shell theme [NAME|list|show]`,
  `spark-shell font [FACE SIZE|list]` and
  `spark-shell quiet [login|boot on|off]`, the look's own verbs beside
  the look. The config keys are `THEME`,
  `CONSOLE_FONT`, `QUIET_LOGIN` and `QUIET_BOOT`, each with a comment
  in config.example.
- The 9 palettes ship in `themes/`, copied from spark 1.61 with each
  file's upstream and licence line kept. CREDITS lists every upstream
  and its licence, and kbd (`setvtrgb`, `setfont`) under the tools.
- `lib/terminal_profile.py` is the Terminal.app helper, ported from
  spark 1.61 with the Python 3 standard library only, so Apple's
  `/usr/bin/python3` runs it. `apply THEME_ENV FACE SIZE` builds the
  `spark-shell` profile, makes it the default and sets it on every
  open window. `remove` takes it away with the `spark-PALETTE` profiles
  an older spark wrote, by their exact names (a `sparkle` of yours
  stays), and Basic is the default again; a remove that could not
  write exits 1. `has-profile` says whether the profile is still there,
  so `on` and `check` never trust the stamp alone. `fonts` and
  `has-font FACE` answer from Spotlight. The key map spark carried for
  micro is gone: key bindings are an app's business, not the look's.
  `SPARK_SHELL_NO_APPLY=1` builds and prints and never touches
  Terminal.app. `tests/profile_test.py` holds it.
- Void is supported: the terminal seat, the palette, the font and
  quiet. The desktop and the login box stay with the Debian and Arch
  families.
- The login screen is handed back by spark-shell's own records alone:
  its copies of `/etc/issue` and `/etc/motd` and a mark for 10-uname.
  An issue it did not write stays, and nothing moves while spark's own
  `/etc/issue.orig` is there.
- The kernel line keeps the cursor: a quiet boot without a quiet login
  left a console with none. The login screen still turns it on.
- On an Arch ESP (vfat, closed to a user) root reads and tests
  `loader.conf`, a failed chmod is no error, and `quiet boot on`
  reaches `mkinitcpio -P`.
- The palette line goes before a last `exit 0` in `/etc/rc.local`, a
  file keeps a last line with no newline, and an rc.local spark-shell
  made leaves with its line. `theme none` asks for root only when a
  root file is there, and the screen is not cleared over a todo row.

## v0.40

- Every document, the help and the program's words speak with one
  voice, spark's, from its `docs/CONTRIBUTING.md`. That is the README,
  CREDITS, config.example, the templates' comments, the help header,
  the rows and the refusals. The words are the seat, this machine, the
  login box, the status line, a screen, the app list. The README's
  Contributing section lists spark-shell's own words.
- The README is the seat at an AI box, with one home per topic. The
  login box has its section, and the keys are the sway template's ten
  sentences and nothing else. The desk section is short paragraphs.
  The wallpaper, the marks, the sbom and the kept desk's JSON are each
  explained once. The README's command block is the help's source.
- `spark-shell desktop keys` says `Super+s` opens a small window with
  spark chat, and the move, fill and workspace sentences lost their
  semicolons. `Enter` names the key alone.
- CREDITS lists diffutils (Arch) and ends every bullet with a period.
  config.example says where starship comes from in one line, pointing
  at the README.
- tests/shell_test.sh holds the mechanical half: the words that are
  out, capitals, contractions, widths.

## v0.39

- The btop render no longer carries a `color_theme` line: btop on a tty
  ignores it. `THEME_BTOP` in spark's theme.env is no longer read; the
  key may be there or not.

## v0.38

- One pair of switches. `spark-shell on` is the terminal seat;
  `spark-shell on desktop` adds the desktop and the login box;
  `spark-shell off desktop` takes those back and keeps the seat;
  `spark-shell off` takes everything back. `apply` is folded into `on`:
  run `on` again after `spark theme NAME` or a `git pull` and it renders
  what changed (a new login does the user's half by itself). `desktop
  on|off` and `apply` still work as spellings. Every row, refusal and
  remedy says the new words.
- `off --dry-run` and `off desktop --dry-run` print what they would hand
  back and touch nothing; they had acted.
- A dry run's last line counts every `would` row it printed; `on
  --dry-run` had counted the package and unit steps only and could close
  "Nothing to do" under a list of would rows.

## v0.37

- `spark-shell desktop off` under a running login box no longer strands
  you: the greeter's Enter still runs `spark-shell desktop`, and with the
  desktop off that now lands in your shell (one line says so) instead of
  a refusal that sent you back to the greeter until a reboot. The `off`
  row says what happens until the next boot.

## v0.36

The seat at an AI box, revamped: what a new user needs and nothing
more, and the desktop grown into the seat it is for.

- The tools are the hands of an AI box: tmux, starship, fzf, zoxide,
  eza, bat, btop, fd, and jq for the desk. yazi is gone (the package,
  the pinned release on Debian, the rendered `~/.config/yazi/theme.toml`
  and its rows), and with it `unzip`; `vi` as a safety net is gone
  (`ex-vi-compat`, `vim-tiny`); ripgrep and pacman-contrib are gone.
  Installed packages stay where they are: the package manager removes
  them if you want (`pacman -Rns yazi ex-vi-compat ripgrep
  pacman-contrib unzip`), and a rendered yazi theme is yours to delete,
  and `off` hands a theme of yours back from .bak.
- No .gitconfig: `GIT_NAME`, `GIT_EMAIL`, the render, the `git` status
  row and the template are gone; git's identity is git's own (`git
  config --global user.name`). A .gitconfig an earlier version rendered
  stays as it is; it is git's file now.
- starship comes from the package manager where one exists: `starship`
  from Arch's extra (`PKG_SHELL`) and from Homebrew. The pinned download
  and its sha256 pins are gone, and with them the last fetch outside the
  package manager. Debian 13 has no starship package: there the rc
  files draw the shell's own prompt. A starship an earlier version put
  in ~/.local/bin shadows the package's: remove it once with
  `rm ~/.local/bin/starship`.
- `check` has a real `bar` row: `spark bar line` is run, exit 0 is ok,
  a failure is a FAIL with the remedy; without spark the row reads na.
  It had passed whenever spark was on PATH.
- The shims for machines that no longer exist are gone: the micro look
  of v0.2 handed back at every run, the adoption of files spark's old
  in-tree layer rendered (a file marked by anything but spark-shell
  goes to .bak, like any file of yours), and the seeding of the config
  from spark's site.env.
- The help and the README name every verb: `status`, `bar`, `sbom`,
  `desktop apps|tools|keep|forget|wallpaper`. "What leaves this
  machine" names the one model call (`spark edit`, on this machine)
  and nothing else.
- `Super+s` opens spark's own prompt, `spark chat`, in a small floating
  window on the workspace you are on, in the palette's color; Ctrl-D
  ends the conversation and the window goes with it. Without spark the
  window says so and Enter closes it. The stacking layout moves to
  `Super+Shift+s`.
- `spark-shell desktop keys` says the desktop's keys in whole
  sentences. The sentences live in the sway template, one `# key:`
  line above each binding, so the verb, the render and the README say
  the same thing; the suite holds the README to them. The first
  desktop start on a machine shows them once, in the first window,
  before the shell (`~/.local/state/spark-shell/desktop.seen` marks
  it); never again, the verb is there any time.
- `spark-shell status` ends with a `next` row naming the one next step
  when something is off: spark to install, `spark-shell desktop on`,
  the login box (sudo once), a reboot. Nothing off, no row.
- A kept desk is the model's answer, one JSON object (`words`, `why`,
  `main`, `side`), not the sway lines it made once: the lines are
  rendered again each time it opens, for the screens and the workspace
  there now; `desk.last` holds the same shape, so `keep` is still a
  copy, and the file is yours to edit. A desk kept before this release
  (sway lines under a `# desk:` header) is refused with one sentence
  naming the file and the words to make it again.
- A desk knows the screens: the brief names them left and right with
  their sizes (`swaymsg -t get_outputs`, name and mode only), and the
  answer may put a window on one (`"screen": "left"|"right"|NAME`).
  Each screen a desk uses is its own workspace, the main's first,
  reached by `focus output NAME` then `workspace number N`; nothing is
  pinned to an output, dragging and floating stay yours. Opened on
  fewer screens than it names, a desk lands on the one there and says
  which in one line. The gate passes `focus output` only for a name
  sway reports.
- Rooms: a desk plays as a tmux session where there is no sway (a
  console login, ssh, a Mac): one window per app, named by it, the
  main first, attached from a terminal or switched to inside tmux. The
  player is chosen by where you ask from (SWAYSOCK and a swaymsg that
  answers: windows; else rooms), never guessed; `--rooms` and
  `--windows` force one, at the prompt too. Rooms hold terminal apps;
  a graphical app in the answer is skipped with its line, a kept desk
  opens what the machine has. `shell` and `editor` are desk words
  (`editor` is your `$EDITOR`, else micro). `desks/studio` in the
  repository is the first kept desk of the shape: `cp` it into
  `~/.config/spark-shell/desks` and `spark-shell desktop studio` opens
  the shell, the editor, newsboat, w3m and aerc, one room each.

## v0.35

- A desk you kept may open any program the machine has (never a
  shell or a way to root): the gate had refused newsboat in a kept
  desk once the inventory became the declared apps. The model's own
  answer stays inside the list it was given, and the refusal says
  which it is: "not on the desk's list (spark-shell desktop apps
  marks it)" or "not on this machine".

## v0.34

- `spark-shell desktop apps` shows the apps, `spark-shell desktop
  tools` the tools; one list of marks behind both.

## v0.33

- `keep` takes all your words (`keep reading and music` ->
  `reading-and-music`), and bare `keep` names the desk after its own
  words; only the first word had been taken. `desktop reading and
  music` replays it when kept, else it is a need. `keep` and `forget`
  work at the `desk>` prompt too.
- A kept desk replays like a fresh one: the dialog follows it to the
  new workspace, the why line from the file is shown, the pulse while
  windows come, Enter closes. It had jumped to an empty workspace with
  no word.
- The picker is one row per package, not per command (1000+ rows had
  become 230): apps, then the tools you chose, then dependency tools.
  A marked row wears a `*`; Tab flips a mark, Enter saves what you
  flipped. A marked package whose command has another name (ripgrep,
  rg) reaches the desk by the command.

## v0.32

- `spark-shell sbom [apps|tools|parts|NAME] [--json]`: the box's
  software bill of materials in the package manager's words (pacman,
  dpkg, brew): version, licence, description, chosen or dependency,
  commands, desktop entries with their XDG categories; kind follows
  (an app declares itself with an entry, a tool is a command, a part
  is neither). `--json` writes CycloneDX 1.5, spark's own format.
- The desk's inventory is what the box declares: every app with a
  desktop entry, plus a program your words name. The list of chosen
  packages is gone (it had offered mkinitcpio, greetd and fzf as apps).
- `spark-shell desktop apps`: a picker (fzf, Tab marks, Enter saves)
  over the box's apps and tools; the marks live in
  ~/.config/spark-shell/apps, yours, `name[: your words]`. Marked, the
  desk offers exactly those, with your words beside the machine's.
- tmux declares itself as an app of the desktop (a rendered entry).
- `status` has an `apps` row; `check` an `apps` row (a marked app that
  is gone is a FAIL with the remedy).

## v0.31

- The pulse also runs while a window is awaited, not only while the
  model writes: the seconds between the why line and the first window
  had shown nothing.

## v0.30

- The prompt takes the focus back before "Enter closes": Enter had
  been going to the app opened last. What it shows is what a person
  reads: the why, one line per window with its outcome (`w3m
  duckduckgo.com`, `mpv radio.m3u -- no window`), any refusal; the
  sway lines come with `-v` and live in the kept file. `-v` and
  `--dry-run` after the words are flags, not words.

## v0.29

- The prompt's header in whole sentences: "Say what you are about to
  do and press Enter. Up and Down pick a desk you kept. Esc closes."
  The window is taller (40 ppt), so the why line stays in view.

## v0.28

- The packages you chose reach the model in the package's own words
  (pacman's, dpkg's or brew's one-line description): "internet
  browsing" had opened avahi's SSH-server browser because w3m's line
  said only "a tool you chose". A shell or a way to root is not in the
  list at all.

## v0.27

- The `Super+d` prompt window follows the desk to its workspace and
  stays, on top, until Enter: the model's why line and any refusal are
  read, not lost with the window when the workspace switched.
- The `desk>` prompt is an fzf line when fzf is there (the tools row
  installs it): the arrows move over the kept desks, Enter takes the
  words or the desk under the cursor, Esc closes, a header says so.
  A bare `read` had thrown escape codes at the arrows and ignored Esc.
- While the model writes, the prompt shows the pulse every spark prompt
  shows (`*` in the accent, `.` `..` `...` muted, 0.35 s), at a tty only.

## v0.26

- The `desk>` prompt (Super+d) no longer repeats your words on a
  second line; the command-line form still names the need first.

## v0.25

- An app opens the way its own desktop entry says: the Exec line with
  its file/URL field taking the model's args, or dropped. mpv's entry
  is `mpv --player-operation-mode=pseudo-gui -- %U`, so a music desk
  gets an idle player window instead of nothing (bare `mpv` ends at
  once with nothing to play).

## v0.24

- A desk whose window never came (mpv with nothing to play) no longer
  cuts the window before it: the split meant for it is skipped, and
  the next window lands where that one would have. The model's brief
  asks for as few windows as the work takes, never an app the need
  does not call for (aerc had been padding "writing and music").

## v0.23

- A desk from your words: `spark-shell desktop "focused news reading
  and music"` asks the model (spark edit, from nothing, one JSON
  answer: why, a main window and its width, the side windows) for the
  windows the need calls for, from the apps this machine has -- its
  desktop entries, the packages you chose, a tool the words name --
  and sway opens them on the next empty workspace, main at the left,
  the rest stacked at the right. `Super+d` asks at a small floating
  prompt. `keep NAME`, `NAME`, `forget NAME`: a kept desk is a text
  file of sway commands, replayed with no model call; bare `desktop`
  inside the desktop lists them. Every line passes one gate before
  sway sees it (a desk verb, no shell syntax -- sway hands exec to
  sh -c -- and exec only of an app in the inventory, never a shell or
  a way to root). From a console with no desktop, the words wait for
  the one it starts. The `check` desktop row wants jq; `status` has a
  `desks` row.

## v0.22

- `ALPHA` in the config: foot over a picture, 0 to 1, default 0.85
  (0.95 hid the forge; 0.9 had let a bright car through -- the number
  depends on the picture, so it is yours).

## v0.21

- The forge is the desktop's default wallpaper: `wallpapers/` ships the
  smith at work in 1920x1080 and 2560x1664 (JPEG, the maintainer's
  own, CC BY-NC-ND 4.0); `WALLPAPER` defaults to `default` = the 1080
  one from the clone, `spark-shell desktop wallpaper default` returns to
  it, `none` and a PATH as before.

## v0.20

- The look follows the palette by itself: the login profiles run
  `spark-shell follow`, which re-renders the user's files when
  theme.env changed since the last render (a cksum stamp in
  ~/.local/state/spark-shell/theme.seen) and says so in one line;
  quiet otherwise. `spark theme nord` had left sway's border and
  foot's background in gruvbox through a reboot, waiting for an apply
  nobody had been told to run. The login box (root's files) still
  follows at `spark-shell apply`.

## v0.19

- `vi` as a safety net (`ex-vi-compat` on Arch, `vim-tiny` on Debian,
  in `PKG_SHELL`): what falls back to vi when EDITOR is unset (yazi,
  git, crontab, visudo) opened nothing on a minimal Arch. The editor
  you use stays yours (`~/.config/spark-shell/rc`).

## v0.18

- `~/.config/spark-shell/rc`: yours, sourced last by both rc files,
  never written here. The rc files are spark-shell's symlinks, so a
  line of your own (`export EDITOR=micro`; yazi's Enter on a file was
  exit 127 without one) had nowhere to live.

## v0.17

- The login box's Enter runs `spark-shell desktop` too (tuigreet's
  `--cmd`), not bare sway: v0.12 wrapped only the F3 session, so the
  default still spilled sway's stderr onto tty1 at every reboot.

## v0.16

- yazi, the file manager, joins the tools: a package on Arch
  (`PKG_CLI`) and Homebrew; on Debian, which has none, a pinned
  release (26.9.1, sha256, `yazi` and `ya` into ~/.local/bin, unzipped
  -- `unzip` joins `PKG_CLI` on both distros). A rendered
  `~/.config/yazi/theme.toml`: no icon glyphs (they want a Nerd Font),
  the accent word on the current directory. The `tools` rows name it.
- The login box's fire was not lit: tuigreet prints its help on stderr,
  so the flag check saw nothing. Read.

## v0.15

- The login box burns: tuigreet's DOOM fire (`--background doom`) in
  the palette, where the installed tuigreet knows the flag (0.11 and
  newer; Debian 13's 0.9 gets the plain box). About six percent of one
  core while the box waits, nothing once you are in; F4 switches it for
  one boot.

## v0.14

- foot over a wallpaper is `alpha=0.95` (was 0.9): a bright picture
  read through the text more than the number suggested.

## v0.13

- `spark-shell desktop wallpaper PATH|none`: a picture behind the
  windows. `WALLPAPER` in the config; sway `output * bg "PATH" fill`
  with gaps 8/12, foot `alpha=0.9` (opaque and edge to edge with
  `none`, as before); a live sway reloads; the verb bare names the
  current one; a missing file falls back to the palette's color with a
  `todo` row, and a path is refused unless absolute and readable. A
  `wall` status row.

## v0.12

- The login box's desktop session is `spark-shell desktop` (the clone's
  path), not bare `sway`: sway's and foot's stderr go to
  `~/.local/state/spark-shell/sway.log` and the cursor comes back, the
  same as starting it by hand. A reboot from inside the desktop had
  printed foot's broken-pipe lines on tty1.

## v0.11

- `spark-shell desktop on|off`: the desktop and the login box together.
  `on` writes `DESKTOP=sway` into the config (the file made if missing,
  the one line replaced, every other kept) and takes the path `on` takes
  with it (`desktop_apply`, one code path for `on`, `apply` and this
  verb): the packages, foot.ini and sway/config, and now the login box.
  `off` writes `DESKTOP=none`, hands the two renders back and undoes the
  box; packages stay. `spark-shell desktop` alone still starts sway now.
- The login box: greetd with tuigreet on tty1 (`PKG_GREETER` in
  `distro/*.env`: greetd + greetd-tuigreet on Arch, greetd + tuigreet on
  Debian 13; names verified 2026-09-20; none on Ubuntu LTS). A small box
  on the themed console -- the machine's short name, Login, Password,
  the clock -- drawn in the palette's slots as ratatui's color words
  (`tui_name`, the placeholders `@ACCENT_TUI@ @MUTED_TUI@ @BG_TUI@
  @FG_TUI@`; BG and FG by their nearest slot, `default` = black and
  gray). Enter is the desktop (sway), F2 the console session (a login
  shell on tty1); `--remember`, `--remember-session`.
- Root renders, a new class: `/etc/greetd/config.toml`, the two session
  files in `/etc/greetd/spark-shell/`, and a `greetd.service` drop-in
  (`After=spark-console.service`, so the first frame is already in the
  palette). Written through sudo only when the render differs from the
  disk; `--dry-run` says `would`; no sudo to be had is a `todo` row. A
  config.toml that is not ours goes to `config.toml.spark-orig` once and
  comes back on off. Then `systemctl enable greetd.service` and
  `disable getty@tty1.service` (greetd first, so tty1 never loses its
  login), and the reverse on off -- never a start or stop: greetd takes
  tty1 at the next boot, the session this runs in is not touched.
- `apply` re-renders the root files too: a palette change reaches the
  login box. `status`'s desk row adds `login box: greetd at boot` or
  `getty`; `check` gains a `greeter` row (`na` with DESKTOP=none and on
  macOS; the files, the render and the two unit states, remedy
  `spark-shell desktop on`). `off` undoes the box as well.
- `SPARK_SHELL_ROOT=DIR` (tests only): every root path under DIR, plain
  writes, systemctl from PATH. The suite runs in a throwaway root as it
  does in a throwaway HOME; a stub systemctl logs its calls. CI gains a
  `debian:13` job, where distro/debian.env's names are looked up (the
  apt-cache step leaves the Ubuntu job: no tuigreet there); the Arch
  job looks up PKG_GREETER too. The e-mail gate (hook and CI) no longer
  reads a systemd instance name (`getty@tty1.service`) as an address.

## v0.10

- The plain look is for the look, not for content. tmux is told foot can
  take RGB (`terminal-features ",foot*:RGB"`), so a picture or text art
  drawn in a pane keeps its colors under the desktop instead of being
  approximated to 256. Every rendered file still names slots only; on
  the console nothing changes, there is no RGB to take.

## v0.9

- foot: `pad=4x4 center`. A grid never fills a window exactly; foot put
  the pixels left over at the bottom, and with 8 px of padding that read
  as a blank line under the last row (23 px at 1920x1080, cell 10x19).
  Four pixels and `center` split what is left evenly, one more row.

## v0.8

- The desktop ends with its first terminal: `exit` in the foot it opened
  is the console again (sway's `exec` runs `foot; swaymsg exit`). An
  empty sway was a black screen with nothing to type into; Super+Shift+e
  still works, Super+Return still opens more windows.
- foot.ini names ONE color section, for the foot installed: `[colors]`
  before foot 1.26 (Debian 13 has 1.21), `[colors-dark]` from 1.26 on
  (Arch has 1.28) -- v0.6 rendered both, and foot 1.28 shows an
  "invalid section name: colors" error in the window for the one it
  dropped (`foot_colors`, from `foot --version`; 1.26+ when foot is not
  there yet, as in a dry run).

## v0.7

- The starship prompt is starship's again: the `spark MODEL` /
  `spark down` segment of v0.5 is gone from both styles (too much on
  the prompt line). The three color exports stay; spark's prompt cache
  is still written by spark, read by nothing here.

## v0.6

- A desktop. `DESKTOP=sway` in the config and `on` installs sway, foot
  and DejaVu Sans Mono from the distro (`PKG_DESKTOP` in
  `distro/*.env`; names verified on Debian 13 and Arch, 2026-09-20) and
  renders `~/.config/foot/foot.ini` and `~/.config/sway/config`;
  `apply` re-renders them (and `swaymsg reload`s a running sway); `off`
  hands both back, marker-guarded like every render. `spark-shell
  desktop` starts sway on this console, as a child: its stderr goes to
  `~/.local/state/spark-shell/sway.log`, the cursor is put back on the
  console after it exits, its exit status is ours. It refuses, one line
  each, on macOS, with `DESKTOP=none`, without sway, without the
  renders, inside a desktop already (`WAYLAND_DISPLAY`), and without a
  seat (`XDG_VTNR` unset: ssh has no seat, a console login does).
  `status` gains a `desk` row, `check` a `desktop` row (`na` with
  `DESKTOP=none` and on macOS). Default `none`: nothing changes for a
  box that has not asked.
- The HEX class. foot is the desktop's twin of the console palette: the
  one surface that gives the sixteen slots their colors, so it, and
  sway's borders beside it, take the palette's own rrggbb
  (`HEX_BG`, `HEX_FG`, `HEX_ACCENT`, `HEX_MUTED`, `HEX_ANSI_0..15`,
  filled at the end of `theme_load`: a `#rrggbb` stripped, a color
  word the VGA sixteen that `spark theme none` programs). The templates
  carry `@HEX_*@` placeholders and the hex lands at render time, so the
  gate's rule stays: no hex in a template, every other render still
  names slots. foot's colors sit in `[colors]` (foot 1.21, Debian 13)
  and `[colors-dark]` (foot 1.26 and newer; Arch ships 1.28, which
  dropped `[colors]`): each foot reads the section it knows and logs
  the other to stderr once, nothing in the window.
- `FONT` in the config (foot's own spec; default `DejaVu Sans
  Mono:size=12`). On Arch, sway depends on the virtual `ttf-font`:
  `ttf-dejavu` provides it, `ttf-jetbrains-mono` does not (pacman would
  add a second family on its own), which is why the desktop's face is
  DejaVu.
- sway stays bare, since tmux owns the terminal: no bar (the tmux line
  is the bar), no titlebars (`default_border pixel 2`), no xwayland; a
  new window is foot running the login shell, never tmux itself. The
  keys are i3's. Every directive used is in sway 1.10 (Debian 13) and
  1.12 (Arch).

## v0.5

- The prompt's color. `on` and `apply` render
  `~/.config/spark-shell/sgr.sh`, three exports from the palette slots
  (`SPARK_ACCENT_SGR='1;<code>'`, `SPARK_MUTED_SGR='<code>'`,
  `SPARK_WARN_SGR='1;31'`; a slot below 8 is 30+n, above is 82+n, so
  console-safe 30-37 and 90-97 only, bold at most), and the rc files
  source it right before spark's hook line. spark 1.41 or newer reads
  them at a tty and paints its hint row, `spark chat` and `spark do`
  with them; a pipe never sees them, and without the file the prompt
  stays plain. `off` removes the render; `spark-shell status` names the
  pair beside the slots (`SGR 1;91 / 90`). The interface stays one file
  each way: spark writes `theme.env`, spark-shell writes `sgr.sh`.
- A spark segment in starship, both styles, right before the `>`:
  `spark MODEL` in the accent while spark answers, `spark down` in red
  when it stopped, nothing when spark is not there. It reads spark's own
  prompt cache (`~/.local/state/spark/prompt`, KEY=value) with sh
  builtins -- one `sh` per module, no python on a prompt -- and draws
  its space only when it has something to say. The blank hint row above
  stays.

## v0.4

- No editor. spark-shell installs no editor (it never did) and now
  configures none either: no `EDITOR=micro` in the rc files, no
  `editor = micro` in the rendered .gitconfig, no micro colorscheme and
  no seed in micro's settings.json. An editor's look is its own plugin's
  business (spark-micro), and which editor you use is yours. What v0.2
  rendered is handed back once: a `spark.micro` it wrote is removed and
  the `colorscheme` key it seeded is dropped, so micro never points at a
  scheme that is gone.

## v0.3

- No guessed git identity. A `.gitconfig` is rendered only when both
  `GIT_NAME` and `GIT_EMAIL` are in the config (typed, or seeded from an
  old site.env); unset, none is written and git's identity is yours to
  set. A `.gitconfig` you already have is never touched, even with an
  identity in the config. v0.2 wrote `<user> <user@host>` on a machine
  with neither, which is nobody's identity.
- No projects folder. `on` no longer makes `~/projects`, the `WORKSPACE`
  key is gone (an old one in the config is ignored), and `check` has no
  backup row scanning it: where your work lives is not the look's
  business.

## v0.2

- The Nerd Font is gone: `on` no longer downloads it, `check` has no
  font row, the Brewfile has no cask, and `unzip` and `fontconfig` left
  the package lists (they served only the font). A machine that is a
  bare Linux console cannot draw a `.ttf`, and the look below no longer
  needs one anywhere. A font directory an earlier `on` left at
  `~/.local/share/fonts/JetBrainsMonoNerdFont` is not touched -- nothing
  spark-shell did not render is ever removed; `rm -r` it and `fc-cache
  -f` if you want it gone.
- One plain look: every render draws with ASCII and names colors by
  palette slot, never by hex -- tmux without the truecolor override and
  without the console hook (`colour0`..`colour15` need none), starship
  with ASCII git marks and its color words, btop in `force_tty` with
  tty graphs, micro's colorscheme in its sixteen color words, bat on
  its `ansi` theme with numbers only, fzf with `--no-unicode
  --color=16`. The accent and the muted tone become the nearest of the
  palette's sixteen at render time (`spark-shell status` names the
  pair); spark's `theme.env` is read as before. `MICRO_TRUECOLOR` is no
  longer exported, and the status line asks `spark bar line` with
  `SPARK_ASCII=1`.
- `apply` and `on` also unset, in a running tmux, what the v0.1 render
  had set and a reload cannot undo (the console hook, the appended
  truecolor override), so the new look lands without a restart.
- The rc files carry spark's one marked hook line (`config/spark/hook.`)
  instead of sourcing its widget and completion themselves: spark's rc
  row sees the marker and never appends a second line -- which, with
  `~/.bashrc` a symlink into this clone, used to land in the tracked
  template and dirty the checkout.

## v0.1

- The shell layer, out of spark and on its own: everything spark
  v1.19's `spark shell on` did lives here now -- the tools (tmux,
  starship, fzf, zoxide, eza, bat, btop), the JetBrainsMono Nerd Font,
  the terminfo entry, the rc files, and the rendered look (tmux,
  starship, btop, micro's colorscheme) painted from spark's
  `theme.env`.
- One command: `spark-shell on|off|status|apply|check|bar`. `apply` is
  the second half of `spark theme NAME`; `off` hands everything back
  from `.bak`, or removes what had no before -- never an empty husk.
- Choices in `~/.config/spark-shell/config` (PROMPT, PROMPT_STYLE,
  WORKSPACE, GIT_NAME, GIT_EMAIL), seeded once from spark's site.env
  on a machine that ran the old layer; files the old layer rendered
  are adopted in place.
