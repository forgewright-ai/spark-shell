# Changelog

## Unreleased

- Display undo preserves custom scale values and exact native refresh rates.
- Wi-Fi manager detection no longer starts iwd while another manager owns
  the radio. iwd password entry uses a private terminal and waits for its
  masked prompt before Enter. The password stays off command arguments.
  Native simulated-radio checks cover all three backends, IPv4 and DNS
  changes, and undo; the older password leak is the negative control.

- Printers expose the configured CUPS queues and your pending jobs. Choose
  a default, pause or resume a queue, or confirm cancellation of one job.
  Native permissions still apply; no service or queue is added implicitly.

- Files can hand a folder to the native file manager. macOS uses its own
  opener. A failed launch is a refusal; a request is not reported as proof
  that an application opened the file.

- Saved layouts apply native window rules to newly opened containers only.
  Terminal minimums use real cell counts after the split is sized; btop
  waits for 80 columns and 24 rows, floating if the split cannot fit it.

- Battery details on macOS read the native power status and time estimate.
  A laptop no longer reports no battery because Linux files are absent.
- A closed output pipe now runs cleanup, including the first bar header.
  Temporary folders and the bar PID file no longer remain after that exit.

- Network rows join hidden networks through the existing native tool.
  Passwords stay on stdin; the WPA tool derives a key before sending it.
  A bare system offers native setup without replacing another manager.
  Active NetworkManager connections expose IPv4 and DNS settings with undo
  and failure recovery. IP settings for other managers remain pending.

- Display rows open each screen's native choices: scale, resolution,
  arrangement and power, all with undo. On and off persist across login;
  the last active screen stays on, and login recovers an all-off layout.

- Time preferences share a 12 or 24 hour clock and the first weekday across
  the desktop. The clock section reports native sync status and offers a
  time zone change through the system, with confirmation and permission.

- Bluetooth setup installs and enables the native services. Pairing uses
  a temporary agent for the chosen device, with codes and confirmation
  carried by the dialog. Submitted codes stay in memory. Removing a paired
  device requires typed confirmation; check reports the native service.

- A click on a dialog key chip takes the same action as the key. The
  Calendar's arrow chip moves each way; destructive steps still need yes.
- The login address walk checks each pointer through an optional reference.

- Pointer controls set touchpad tap to click, natural scrolling and
  mouse/touchpad speed, live and for the next login (#74).
- Keyboard controls set repeat delay, repeat rate and Caps Lock as
  itself, Control or Escape. Direct controls and typed tools share the
  native settings, validation and undo (#80).

- The provider watcher test waits for the action and its update before
  changing the palette outside it. Slow runners observe both changes.
- The desktop shares the palette's dark or light preference through native
  settings and restores its prior value on off. Native desktop portals
  provide file pickers and screen sharing, with the session environment
  handed to them when sway starts. App themes stay under their own control.

- The dialog's language prompt carries view and selection context into a
  bounded spark task. One typed action is confirmed and executed before
  its actual result drives the next decision. Questions keep the goal;
  cancellation and uncertain outcomes stop continuation. Direct controls
  require no model. Provider output schemas are checked when declared.
  This adapter requires spark's `do --tools` support.
- Task context retains visible dates, times and exact row actions.
  Provider descriptions distinguish saving note text from opening an
  editor and state the reminder provider's future-time requirement.
- Optional native preparation validates and resolves an action before
  review. Reminders show an explicit date and time; a past time asks for
  clarification without creating an event or calling the model again.


## v0.103

The system foundation, first part (Priority I of the product
guidelines): the notifications, the drives and the power.

- New: the notifications. Until now nothing showed them, so an app's
  notification was lost. mako shows them now, in the top right corner
  under the bar, on the dialog's surface, in the palette and the text
  face: the app's name muted, what it says in bold, the words under it.
  The newest is on top, three at most, each gone after eight seconds
  into a history of ten; a critical one stays until it is dismissed and
  has a red edge. Do not disturb keeps them out of sight (a critical one
  still shows), the bar says so, and it holds across logins
  (DO_NOT_DISTURB in the config). The dialog's Notifications turns it on
  and off, dismisses what is on the screen, shows the last one again and
  lists the last few, and so does `spark-shell desktop notifications`. A
  reminder due comes as a notification too, once, and a click on it
  opens the reminders. A new look reaches the next notification at once;
  check has a notify row (#71)
- Fixed: on Void the desktop ran with no session bus, as no logind makes
  one, so no program's notification could reach mako or anything else.
  sway starts inside dbus-run-session where there is no session bus;
  the families with logind keep their own (#71)
- New: the drives. A USB stick or a card you plug in comes as a
  notification, and a click on it opens the dialog's Storage: each drive
  with its parts, Enter mounts one and opens one that is mounted in your
  file manager (a terminal in it where there is none), then unmount,
  eject (every part unmounted, the drive powered off) and this
  computer's free space. Nothing mounts by itself. udisks2 mounts with
  no root where logind says you sit at the screen; on Void `on desktop`
  writes a polkit rule that lets you mount, eject and power off a
  removable drive, nothing more. The disk the system runs from and a
  disk the system mounts itself are never listed, and an encrypted drive
  says how to unlock it. `spark-shell desktop storage` does the same in
  a terminal; check has a storage row (#73)
- New: the power. The dialog's Power locks the screen, suspends, logs
  out, restarts and shuts down, and log out, restart and shut down ask
  for a typed yes. Suspend locks the screen first, whoever asks. Where
  logind runs it does them for you, and a restart it refuses while
  another login is open says why. On Void `on desktop` writes a sudo
  rule, checked by visudo, that lets you run zzz, reboot and poweroff,
  each with no argument, and nothing else. What the power button and the
  lid do is said, from logind's settings or acpid's handler, and never
  changed. `spark-shell desktop power` does the same; check has a power
  row (#72)
- The dialog's Settings has Storage beside the network, Notifications
  after the keyboard and Power before the battery, and Enter's key says
  Mount, Unmount, Eject, Dismiss, Show, Lock, Suspend, Log out, Restart
  or Shut down. The column of states moves one cell right, on the home
  too, so the longest name, Notifications, keeps two cells of air
- Fixed: a state too long for the dialog's header was cut with the space
  before its dot gone, the dot against the section's name: the cut keeps
  it now
- Packages: mako, notify-send (libnotify) and udisks2 in every family's
  desktop list, dbus-user-session on Debian and Ubuntu, dbus on Void,
  each name looked up on its family's own index first
- Decided: the Priority I assessment (2026-10-24) found ten gaps, one
  issue each (#71 to #80); these three come first, as a new desktop
  meets them on its first day, and the other seven wait for triage

## v0.102

- Fixed: the idle screen started by hand (`spark-shell desktop idle`) had
  no way out. A key did nothing, and Ctrl-C ended the saver or the clock
  but left an empty workspace in front with no bar: only swayidle, when
  it had brought the idle screen up itself, put them back. The idle
  screen now keeps the name of the workspace it left, and whatever ends
  its window (a key, a mouse move, Ctrl-C, the window closed, or
  `desktop idle off`) brings that workspace and the bar back, by name,
  so two ways out at once land in the same place. The saver and the
  clock read their terminal, the mouse's moves included (#70)

## v0.101

Security fixes, the idle screen's saver, and spark's progress
animations in the dialog.

- Fixed: a saved theme is a folder that can come from another machine,
  and `theme NAME` kept its look.env values as they were, in lines that
  sway and sh read again: a folder could carry a command. look.env is
  read the way the config is now, and each value is held to its shape
  before anything changes: the font, the wallpaper, the picture (a file
  of the folder's own, not a link), the transparency and the pointer. A
  folder that fails is refused in one line that names the key, and
  nothing changes. The config's own FONT and WALLPAPER get the same
  checks, no value with a control character is written to it, and a
  picture with a quote or a backslash in its path is refused when it is
  picked (#61)
- Fixed: a new network's password went to nmcli, iwctl or wpa_cli as an
  argument, where any account on the machine could read it while the
  tool ran. It goes on the tool's standard input now: nmcli reads it at
  its own prompt (--ask), iwctl at its agent's, and wpa_cli takes it as
  a command on stdin, with no history file. A password with a control
  character is refused. The suite holds each of the three to it with a
  stand-in that keeps its arguments apart: the password is never among
  them (#62)
- Fixed: the state folder, the saved themes and the notes took the
  default permissions, so another account on the machine could read
  them. They are yours alone now: the folders 0700 and each note
  spark-shell writes 0600, and `on` makes the folders already there
  private, with a row (#63)
- Fixed: the release workflow checked a tag against the allowed-signers
  file inside that same tag, so a tag could vouch for itself. It checks
  a tag against the release before it now, and walks the chain of
  releases behind it, as spark's does (#64)
- New: CodeQL reads the dialog's Rust, the Python helpers and the
  workflows on every push to main, every pull request and once a week
  (#65)
- New: the idle screen can show a saver behind its clock: spark,
  starfield or drift, from lib/saver.py (python3 and its standard
  library). `desktop display saver NAME` picks one, and `saver clock`,
  the default, is the clock alone; the dialog's display section has a
  row for it, and check says which is in use. A saver writes only the
  cells that change, ten times a second, and the idle screen goes when
  the lock comes, so nothing runs behind the lock or a dark screen. No
  python3, or a saver that fails, leaves the clock (#66)
- New: the dialog's bar shows spark's own five progress animations, by
  the kind of work: a light bouncing while spark thinks, an arrow while
  a place's rows come, arrows moving right while a step runs, one step
  after another when more wait behind it, and a bar growing and
  shrinking while a model loads (#67)
- Fixed: the dialog's display section said "display off" for the idle
  minutes and "lock" alone for the lock minutes, while the command said
  idle screen, and lock and display off. The receipts and the tools'
  words say what each setting does now (#68)
- Fixed: with NetworkManager, the wifi section read every network around
  with two spaces before its name and every saved one with a space after
  it, so a connect from the dialog named a network that was not in the
  list. The names come through as they are now, a colon in one included
  (#69)
- Fixed: on a Mac, `on --dry-run` said WSL has no console, for the
  palette and for the login screen. It names macOS now (#38)

## v0.100

- Fixed: after Esc, the dialog's window sometimes stayed open a moment
  as a plain terminal, its cursor blinking, and a key pressed then was
  printed in it. The dialog gave the terminal back first, then waited for
  each of its providers to stop, and a provider busy with a request held
  the window open: about half a second right after opening, and once 1.5 s
  with 18 providers. The dialog now closes each provider's input and exits
  at once, and the window goes with it: 1 to 2 ms where it took up to half
  a second, timed at a terminal. Each provider ends the request it is
  answering and leaves on its own, its temporary folder with it. A
  provider runs in a process group of its own, so the window closing never
  cuts one short in the middle of a step, and an answer that finds the
  dialog gone no longer ends one mid-request (#60)

## v0.99

- Fixed: on the lock screen, the keyboard's layout under the ring sat
  on swaylock's own black, and on a light palette its dark text could
  not be read: the lock gave swaylock the label's text color and
  nothing more. The label's ground is the ring's own inside now, the
  palette's background at 90%, with the text in the text color and no
  border, in every palette (#57)
- Fixed: on a Mac, the machine's name on the tmux line came from
  scutil when /usr/sbin was on the PATH of the run, and from the
  network's name when it was not, so check called the look out of date
  and on wrote it again. scutil is called by its full path now (#58)
- Fixed: in the dialog's Calendar, left and right moved the months only
  while the focus was in the prompt. Once the down arrow went into the
  reminders under the months, they did nothing, and the key row lost
  Month. With nothing typed, they move the months wherever the focus is
  now, and the key row says so there too (#59)

## v0.98

The revamp arc (#55): the Linux families spark supports, the drawings
without gdk-pixbuf's thumbnailer, a proof of the desktop per family.

- New: Fedora and openSUSE Tumbleweed, each a file of package names in
  distro/ checked against its own repository (dnf and zypper over rpm,
  where a provider counts as installed, as spark's bootstrap reads it),
  and Ubuntu as the Debian family it is, its names looked up in CI. The
  login screen knows the account greetd's package makes on each, named
  in the family's file, and dnf brings greetd's SELinux policy with
  greetd. A refused install names the family's own upgrade step (#55)
- Fixed: on Arch the wallpaper drawings could not be drawn in another
  palette, nor a picture of yours read for a theme: gdk-pixbuf 2.44
  dropped its thumbnailer, which drew them, and Fedora and Tumbleweed
  ship none either. rsvg-convert, librsvg's own, draws them now, and the
  thumbnailer stands in where a distro still has it (Debian, Ubuntu,
  Void). A picture of yours goes inside a square SVG that rsvg-convert
  draws small, its margins clear, and look.py skips a clear pixel. Each
  family's file names the package (librsvg2-bin, librsvg, librsvg-utils,
  librsvg2-tools, rsvg-convert), and a todo row names it when it is
  missing (#55)
- Fixed: on WSL 2, on desktop and on login wrote DESKTOP=sway and
  LOGIN=yes where no tty1 and no desktop can come. Both refuse in one
  line now, as they do on macOS, and status and check say na. The
  terminal is what WSL gets (#55)
- Changed: quiet boot on Fedora and openSUSE says why it does not: they
  boot through grub2-mkconfig, whose entries spark-shell does not edit,
  and both boot quiet already (#55)
- Changed: the prompt row reads the family's package list for starship
  instead of naming managers; the todo for an unknown Linux names every
  family; the sbom reads rpm on Fedora and openSUSE, with dnf's memory
  of what was asked for (#55)
- Fixed: a wallpaper or picture path with one of ; ` $ ( ) | & < > was
  written to the config, which refuses such a value at its next read, so
  every later run stopped at the config. The path is refused in one line
  now, before anything is written, and no such value is ever written.
  The dialog's release file is fetched with --proto-redir =https, as the
  font's is (#55)
- CI: fedora, opensuse and ubuntu jobs look every package name up on
  their own family, and a desktop job installs the desktop's packages in
  each family's container, runs spark-shell on as a plain user, reads
  the sway config with sway -C and starts a headless sway with a foot
  in it (tests/desktop_proof.sh): a proof without a screen, said so (#55)

## v0.97

- Changed: the dialog follows spark's own prompt. Words that go to
  spark come back as commands, one a line, in the prompt where they were
  typed: read them, change or take out a line, and Enter runs them in
  order; Esc drops them. Nothing spark plans runs before that Enter,
  and a step that cannot be taken back still asks for the typed yes. A
  command typed in the dialog's own words, as display brightness 30,
  runs at once with no model. The prompt grows to five rows, so every
  command is in sight before Enter (#53)
- Changed: a turn is the command as it ran, then what came of it. The
  line about to run and the Undo row are gone: Undo is at the end of
  the result it takes back. A result reads like a reply, as dracula is
  on, never the command again, and a refusal says why in plain words,
  never a tool's name (#53)
- Fixed: a request worded as a question, as can you change the theme
  to gruvbox-dark, only listed its step as proposed, not run. Its step
  comes back to the prompt now, as every step does (#52)
- Fixed: dim display 25% was refused before it ran. The dialog held a
  level to the rows on screen, which list only brighter and dimmer. A
  value the step's own range bounds passes on that range; a name (a
  network, a window, a layout) is still held to the list (#50)
- Fixed: a layout saved under a name showed by the words it was made
  from, in the Workspace and in its back list. It shows by its name now
  (#51)
- New: spark-shell layout rename NAME NEW, and a rename row under each
  saved layout in the dialog, which asks for the new name (#54)

## v0.96

- Changed: where a moving window would land shows as a soft tint of
  the accent, a quarter of it, instead of a block at half strength.
  The shapes are sway's own (the middle of a window swaps, a strip at
  an edge splits there, a bar at the edge of a row moves the window out
  of it) and stay; the tint keeps the text under them readable. The
  line on the side of a window alone in a split takes the same tint
  and becomes a quiet hint. sway halves the color it is given and
  draws it premultiplied, so the accent goes in with each channel
  halved and alpha 80: a plain alpha drew the area brighter, not
  softer (#49)

## v0.95

- Fixed: a new drawing of the pointer showed only after the next
  login. sway loads a cursor theme when it starts, and again only for
  a new name or size, so the closed hand of v0.94 stayed unseen on a
  desktop already running. on, and so update, now sets the pointer
  one pixel bigger and back when the drawing is newer than the one
  sway loaded, once per drawing (#48)

## v0.94

- Fixed: moving a window showed the pointing hand. sway asks for the
  image named grab while a window moves, and the spark pointer had
  given that name to the pointing hand. grab is the closed hand now,
  drawn since v0.84 and never shown until today (#46)
- Fixed: dragging a tiled window showed no place to drop it. sway
  draws that place in the focused window's indicator color, at half
  strength, and the indicator had the edge's color, clear over a
  wallpaper. The focused indicator is the accent now. sway also colors
  with it the side of a window left alone in a split, where the next
  window opens; a window alone on its workspace has no edge any more
  (smart_borders), so it never shows that line (#47)

## v0.93

- Fixed: a question's proposals sat at the end of the exchange, under
  older steps and their Undo, far from the question that made them.
  Each request now carries what it left to pick: a question's
  proposals right under it, under "proposed, not run", and the Undo
  right under the step it takes back. A blank row parts one request
  from the next (#44)
- Fixed: a layout asked for "zen, micro, a terminal window" opened zen
  and micro, and only suggested the terminal: "terminal" and "window"
  ground no window on their own, so the shell the model tied to them
  counted as padding. A shell is grounded by the words that name a
  terminal (terminal, shell, console); every other window keeps the
  rule, and "btop in a terminal" still opens btop alone (#45)

## v0.92

- Fixed: the wifi bars on the status bar ended at uneven heights, while
  the same bars on the dialog's home lined up. Font hinting moved each
  block glyph by its own fraction of a pixel. The bar now draws the
  bars in a family of their own, `spark-shell bars`, which a fontconfig
  rule of spark-shell's draws without hinting
  (`~/.config/fontconfig/conf.d/50-spark-shell.conf`). The text and the
  gauges keep their hinting, and `off desktop` removes the rule (#43)

## v0.91

- Changed: the idle screen draws the time in the Calendar's large
  figures, in the accent, at the lower left, and the date under it in
  the dialog's muted color, which reads on the dimmed wallpaper. A
  window too small for the figures keeps the time on one line (#42)

## v0.90

What his first morning on v0.89 found (#39, #40, #41).

- Fixed: after a step, words typed that named no row lit the step's
  Undo, so Enter undid the step: "change theme to nord" worked, and the
  next request put the theme before it back. Words that name no row
  light Ask spark, wherever it sits, and Enter sends them; the Undo and
  a proposal run only when picked (#39)
- Changed: the about page has no logo, and the dialog draws none
  anywhere now. It starts with the version, the licence and the
  address, then each key on one line, its sentence up to the first
  comma, in their groups. A group is drawn whole or not at all, so no
  key is cut at the window's edge, and the last line names
  `spark-shell desktop keys`, which has every sentence whole (#40)
- Changed: the Calendar shows the time in large figures again, above
  the months, as it did before v0.80, with its am or pm on a
  twelve-hour clock (#41)

## v0.89

The home and the look, from his review of 2026-10-23: a look change is
one moment, open terminals and the dialog change color in place, the
home says what each place holds, and the theme section is built around
its choices (#33 to #37, #27, #28, #32). With them, the terminal's font
(#26) and the sound from boot (#23).

- Fixed: a theme change passed through five states in two seconds:
  sway reloaded, the wallpaper and the bar went dark, the new picture
  showed behind windows still in the old colors, and the dialog took
  the windows' ground before its own. A look change is one moment now:
  what takes time first (the palette's files, the drawing drawn in the
  palette), then one burst (every open terminal, sway's colors, the
  bar, the pointer), and the new wallpaper drawn over the old before
  sway lets the old one go, so no frame is black. Nothing reloads sway
  for a look. On a test desktop the whole screen changes in one frame,
  about 0.4 s after Enter in the dialog. The dialog's window reads its
  own foot config, `dialog.ini`, so the next one opens in the new
  colors too. `on` reloads sway only when its file changed, and sends
  the look to the open windows, so an update reaches them too (#33)
- Fixed: open terminals kept the prompt and spark's line in an older
  palette's color until `exec $SHELL` and `clear`. foot.ini sets five
  slots after the sixteen (the accent, the muted color and the dialog's
  three shades), and a look change sends them to every open window. In
  foot the prompt (a starship twin of its config, `starship-foot.toml`),
  spark's line (`SPARK_ACCENT_SGR=1;38;5;16`) and the dialog draw in
  them, so text already on the screen changes color with the look. The
  console, tmux and the Mac keep the sixteen. spark takes the slots in
  chat and in do from v1.100.1 (spark #94) (#34)
- Fixed: wallpaper none set the windows solid and edge to edge, a
  transparency change that no row named, so the next drawing could not
  be seen behind them. Wallpaper none is gone: the ground is the choice
  with no picture, a config or a word that says none reads as the
  ground, and no wallpaper changes the transparency. A transparency
  change reaches the open windows at once (#35)
- Changed: the home says what each place holds: the apps by name, your
  home folder, the windows and the layouts, the notes, the next
  reminder, the network and the theme. Typed words light the row they
  name, and Enter runs it with no model call (#28); words that name no
  row light Ask spark, the first row while words are typed, and Enter
  sends them. The row under the prompt names what Enter does to the lit
  row, and at rest says only what Esc does (#36)
- Changed: the theme section starts with the wallpaper, the text size
  and the transparency, one row each, and left and right change a value
  in place. Then the palettes, dark and light, each with a chip of its
  colors and the drawing it brings, and yours: saved themes, save this
  look as, a theme from a picture, the terminal's own colors (palette
  none). The ten rows of looks before are gone; `theme back` stays. The
  wallpaper list shows the lit drawing as a picture in your palette, and
  holds the drawings, a picture of yours, a color (asked for: a name or
  #rrggbb) and the ground. A provider's row may carry a chip, a value
  and a picture: the rows schema of #1 grows by three fields (#36)
- Fixed: the header cut a long title in the middle of a word. It cuts at
  a word and ends with an ellipsis, and the theme's state is its palette
  alone: the wallpaper, the text size and the transparency are rows (#27)
- Fixed: a step was worded as its section, so the Undo of a wallpaper
  picked from the list read `theme none`. A step is worded by its own
  tool, the same in the exchange and on the Undo line (#32)
- Fixed: every open of the dialog showed the progress bar for about two
  seconds while sixteen providers started, and each of them checked its
  rows every few seconds, shown or not. A provider stopped by the dialog
  left its temp folder behind, and a dialog whose window was gone kept
  running with its providers. The progress bar shows for work you asked
  for, a provider checks only while its rows are on screen, a signal
  ends a provider through its own cleanup, and the dialog ends with its
  window (#37)
- Changed: the sound runs from boot on Void (#23). `on desktop` writes
  one service of yours, `spark-shell-sound`, under spark's supervisor,
  and links PipeWire's own `pipewire.conf.d` files, so PipeWire starts
  WirePlumber and its PulseAudio server itself. A console login gets
  the same private runtime dir, so spark's voice plays with the desktop
  off, and a PipeWire the desktop already runs is left alone until you
  leave the desktop. `spark-shell check` says where PipeWire runs from
  (boot, login or the desktop), and `off desktop` stops the service and
  removes it with the links
- Changed: the terminal's font is Monaspace Neon 1.400, by GitHub Next,
  the type of spark's page (#26). `spark-shell on` installs it for foot
  and for Terminal.app on a Mac: Arch's otf-monaspace, elsewhere the
  release's zip, installed only when its sha256 is the one spark-shell
  pins; offline, a todo row says so and foot keeps DejaVu Sans Mono.
  The default FONT is Monaspace Neon at 11; a FONT on DejaVu Sans Mono,
  or a Mac's Menlo-Regular, moves to it once at its size, a saved theme
  on the old face takes the new one at its size, the login screen gets
  its own copy, and the Linux console keeps its bitmap font

## v0.88

The want path from a login outside the desktop (#31).

- Fixed: a login outside the desktop (ssh, a service, the MCP host of
  spark) has no `XDG_RUNTIME_DIR` on Void, so PipeWire did not answer
  it and the sound was read through plain ALSA: the wrong output, no
  volume, no mute, and `want "mute the sound"` said "out: mute is not
  on the panel now". The private directory the desktop made is taken
  when it is a real directory of yours at 0700. It is never made or
  changed there.
- Fixed: mute, unmute and a level go by the sound's state, not by the
  rows. Mute when muted is a receipt that leaves the undo as it was,
  and an output with no volume control says so in one line. Before,
  `out level 50` on it said "out at 50%" while nothing took it.
- Fixed: the brightness tool takes the words its gate takes: up, down
  (5 from the level now) or 1 to 100, as text, its schema's type. Its
  schema said 0 to 100 and no step, so a planner sent 0 for "mute
  everything and turn the screen down" and the gate refused it; now
  that is `display brightness down`. A want and an MCP call take up,
  down or a number. The dialog takes up and down, its brighter and
  dimmer rows; a number there waits for a change to the dialog.

## v0.87

His live test of v0.86, the same night (#29).

- Fixed: a step that names what is in use is a receipt, never
  "not on the panel now". The row in use carries no tool, and the
  provider's gate took only the rows' tools as the allowlist.
- Fixed: after a step run from a folder (the wallpaper list, a files
  folder), the dialog reads that folder again, so the check moves to
  the row chosen. Before, only the section's rows were read again, and
  the list offered the step a second time.
- Fixed: `theme none` left the open terminals in the palette before it.
  The repaint sent a reset, and a running foot resets to the colors it
  started with. On the desktop the repaint says foot's sixteen outright.
- Changed: the wallpaper list starts with default and none, as the
  palettes start with none.
- Added: `spark-shell update` moves the clone to the newest release
  signed by a key in its own `allowed-signers`, names the newer tags it
  skipped, and runs `on --yes` from the new tree when the terminal is
  set up; `--dry-run` says the move. The README said `git pull`, which
  takes main as it is, signed or not; the dialog was held to a signed
  tag and the shell that installs it was not (#30)

## v0.86

A theme from words that name two colors, the save from words, the
dialog's exchange and the look of none (#25, his reports of the evening
v0.85 landed).

- Changed: `theme "WORDS"` and the theme_words tool take the hue of the
  accent beside the hue of the ground (same when the words name one
  color), and a short name from the words. A flag or a brand is one
  look with two hues; the tool's words say one request is one look, and
  a second words step in one plan is refused. A theme save that the
  model orders before the words step runs after it. lib/look.py takes
  `--accent`.
- Fixed: the dialog's gate took the save row, which asks the person for
  the name, as naming things, so a save from words could never pass. A
  row whose tool asks for the argument binds no name now; `theme save
  NAME` and `layout save NAME` from words work.
- Added: at the dialog's home, Esc clears what the last request left on
  the screen, the receipts, the refusals, the undo and the proposals;
  the key row says `Clear Esc` while they are up, and the next Esc
  closes. Before, only closing the dialog cleared them.
- Changed: `theme none` on the desktop is foot's own sixteen, the
  starlight set foot draws with no config, with its text on its ground;
  the console keeps its own. Before, the desktop took the console's VGA
  sixteen, black windows and grey text, which read as broken one click
  from the sixteen palettes.
- Changed: `none` is no look to come back to: it is not noted in the
  history, so the dialog's back list and `theme back` skip it (it showed
  twice in a filtered list).
- Changed: a palette with a drawing of its own brings it over a plain
  color, the ground or none too, as its row says; only a picture of
  yours stays. The palette rows and `theme list` name the drawing only
  when it would come. Before, a plain color stayed when the palette
  changed, a rule from before the drawings: gruvbox-dark, whose row
  says sunset, picked over teal kept the teal.
- Changed: a saved theme goes by the name you gave it in the back rows,
  the receipts and the dialog's title, whatever words made it; its row
  names what the palette came from (the words, or the picture's file).
  A plan that saves a theme and then applies it by name said the save
  twice: that palette step is dropped, not refused.

## v0.85

The theme end to end (#24): one choice brings the rest, saved and
tracked like layouts, generated from a picture or from words.

- Added: `theme save NAME`, `theme delete NAME`, `theme back`, and
  `theme list` with the saved themes and the last ten looks. A saved
  theme is a folder `~/.config/spark-shell/themes/NAME/`: the palette,
  the wallpaper's SVG and PNG or the picture, the text size, the
  transparency, the pointer; it copies to another machine. The last
  ten looks are a history under the state, with the time; a look not
  saved lives there under its own name. Layouts keep the same history:
  `layout back`, and a layout made from words is kept for it, so it
  opens again with no model call. One set of functions holds both.
- Added: the palette brings the drawing made for it when a shipped
  drawing is on; a picture or a color of yours stays. The second line
  of each shipped SVG names the role of every color it uses, so any
  drawing is drawn again in any palette (gdk-pixbuf renders it, the PNG
  under the state); `theme wallpaper NAME` picks one for the palette in
  use. `desktop wallpaper` moved under theme and says so.
- Added: `theme picture PATH`, a theme from a picture of yours by color
  math in lib/look.py (Python's standard library): the text at 7 to 1
  on the background, the accent, the muted color and the six hues at 3
  to 1, dark or light as the picture is; the picture is the wallpaper.
  `theme "WORDS"` asks spark for a hue, a warmth, a contrast and light
  or dark (the theme_words tool, its one task) and makes the palette
  from them; the drawing in use is drawn again in it. Both apply at
  once.
- Added: the idle screen. After the idle minutes the wallpaper dims to
  the ground and the time sits at the lower left in the muted color,
  the date under it: one foot window at twice the text size, alone on a
  workspace named idle, no gaps and no border. The display turns off
  with the lock at the lock minutes. `desktop idle` shows it now.
- Changed: `theme text N` is the one text size. foot, the bar, the
  dialog, the login, the lock and the idle screen take it, and the
  pointer's size follows it: 24 pixels up to 13 points, 32 up to 19, 48
  above. It lives inside FONT as before. `theme transparency N` is the
  windows' transparency as a percent.
- Changed: the dialog's theme section opens with the saved themes and
  `save this look as`, then the last ten looks with the time, then the
  palettes with the drawing each carries and `a theme from a picture`,
  then the wallpaper as a row that opens the drawings, a picture of
  yours, the colors, default and none; the font rows are the text size
  now. The wallpaper section is gone into it. The header names the
  look: the theme, the text size, the wallpaper. A row applies at once;
  the desktop is the preview.
- Added: the tools theme_save, theme_delete, theme_back, theme_text,
  theme_wallpaper, theme_wallpaper_picture, theme_picture, theme_words,
  layout_delete and layout_back; theme_font, wallpaper_use and
  wallpaper_picture are gone. A tool may take more than one argument
  now (theme_words takes four words, each from a closed set).

## v0.84

The pointer and the window edge (#22, two findings of a new user at the
desktop).

- Added: the spark pointer, two cursor themes drawn from geometry by
  lib/pointer.py, spark-white and spark-black: a notched arrow with no
  stem, a hand, the I-beam, the resize arrows and brackets, an
  hourglass, every straight edge on a whole pixel, in 24, 32, 48, 64
  and 96. `on desktop` writes them under ~/.local/share/icons, the
  login screen gets a copy under /usr/share/icons, and `off desktop`
  removes them. sway showed its built-in set before: the X bitmaps of
  1999, with a hand hanging from its top-right pixel.
- Added: `POINTER` in the config, a cursor theme's name and size. Empty,
  a dark palette gets spark-white and a light one spark-black; sway
  hands the name and the size to every program it starts. `check` has
  a pointer row.
- Changed: every window has a four-pixel edge, the same focused or not,
  so two windows are parted by an eight-pixel strip the mouse can grab:
  the pointer shows the resize arrows over it and a drag resizes. Over
  a wallpaper the edge is transparent and the outer gap grows by it, so
  the look of v0.82 stays; with none the edge is the surface shade. sway
  offers a resize edge only where a window has a border, and the old
  one-pixel line was no target.
- Changed: the keys name the mouse: the strip between two windows,
  Super+right-drag by a corner, Super+left-drag to move.

## v0.83

The README leads a new reader to a first task.

- Changed: the README opens with what spark-shell does on each system,
  gives a first task (check, then a note) and a Help section, reads
  the layouts and the notes and reminders sections in shorter
  sentences, and says the tmux status line still shows the name and a
  reminder due without spark (#21).

## v0.82

Flat windows and readable quiet words (the owner's picks).

- Changed: no outline around the focused window (#19). While a
  wallpaper is on, windows have no border and the gaps part them; with
  none, a thin edge in the surface shade parts them, so two windows
  never merge. Tabs and stacks show the focused title in the surface
  shade. Nothing outlines in the accent; an urgent window keeps the
  alarm. The windows open take the new border at once.
- Changed: the dialog's quiet words read at 4.5 to 1 on every palette
  (#18). They start at the palette's muted lifted a third toward the
  text, as before, and are lifted further where they read lower. The
  palettes' own colors stay their authors': on solarized-light and
  tokyonight-day, whose text reads under 4.5 to 1, the quiet words
  stop at the text's own color.
- Fixed: typing a section's name listed it twice, the setting and the
  section's own "more" row (#20). The search leaves that row out, as
  the section's view does.

## v0.81.1

- Fixed: words never reached a reminder, a note, the display, the
  keyboard or the wallpaper. The sections the want path offers spark
  stopped at the bar's and the window's: "set reminder gym in 10
  minutes" got no step, and "reminders add gym in 10 minutes" a layout.
  The want path now offers every section the dialog has (#16).
- Fixed: a reminder said in spoken order had no time: spark passes
  "call the dentist tomorrow at 9" as said, and only "tomorrow 9:00
  call the dentist" was read. The day and the time may now come last
  ("gym at 6pm", "dinner fri at 8:30pm", "pay rent on mon at 10"); a
  bare number is a time only after "at".

## v0.81

Light themes, as many as the dark ones (the owner's ask), and reminders
a while from now.

- Added: seven light palettes, so there are eight dark and eight light:
  catppuccin-latte, tokyonight-day, gruvbox-light, everforest-light,
  rose-pine-dawn and selenized-light, the official light siblings of
  six of the dark ones, and one-light (Atom's One Light). Each file
  names its upstream; the colors are the upstream's own.
- Added: a wallpaper drawn for each, in the style of the others: meadow
  (catppuccin-latte), kites (tokyonight-day), fields (gruvbox-light),
  grove (everforest-light), arches (rose-pine-dawn), shore
  (selenized-light) and flight (one-light). 17 wallpapers in all, each
  its SVG and a 3840 by 2160 PNG.
- Fixed: "set reminder gym in 10 minutes" got no step. A reminder now
  takes a while from now too, before the words or after them: in 10
  minutes, in 2 hours, in an hour. The step's description says so, so
  spark offers it.
- Fixed: a long state in the dialog's header ran into the date; it now
  stops two cells short of it.

## v0.80.2

From the owner's first look at v0.80.

- Changed: Talk is a row of Settings, showing click the mic or off,
  not a control in the footer. The footer is Attach, the model and the
  mic, and the mic shows only while talk is click the mic.
- Changed: Files opens at your home folder, picked, typed or from the
  bar, not at a list whose one row is that folder.
- Changed: the Calendar's hint draws the left and right arrows apart,
  so they read as two keys.
- Changed: the about lists the keys alone, then the version with its
  licence, then the address; the version left the header. The
  sentences with no key (the volume and brightness keys, typing exit)
  stay in `spark-shell desktop keys` and the README. The keyboard
  layout key reads "goes to the next keyboard layout." It ran past the
  window before.
- Fixed: `spark-shell check` and `spark-shell bar` read the bar's line,
  and a reminder due then had its one chime rung there, from a shell
  that may reach no sound, and never again on the bar. They now look
  without ringing; the chime is the bar's and the tmux line's alone.
- Changed: the test suite fetches no dialog from GitHub. On a tag, the
  checkout is at its release and the suite's own `on` raced the release
  job for the file; `SPARK_SHELL_DIALOG_URL=none` now says there is no
  release to fetch from, and the dialog's own tests keep their local
  folder.

## v0.80.1

- Fixed: a theme set from the dialog changed every window but the
  dialog, which kept its old colors until it was opened again. A theme
  step's result now carries the palette as it is, and the dialog
  repaints itself and its ground with it at once.

## v0.80

A new home for the dialog: six places, the prompt at the top, and
steps that are careful about what they run.

- Changed: the dialog's home is six places: Apps, Files, Workspace
  (windows and layouts), Notes, Calendar (the months and the reminders)
  and Settings (each device and look section, Connections and About).
  A place shows only where this machine has it. The home's old mix of
  rows and recent picks is gone; typing still finds every step.
- Changed: the prompt sits at the top of every view, two rows tall.
  Enter sends, Shift+Enter starts a new line (Alt+Enter where a
  terminal cannot tell them apart), a longer draft scrolls inside the
  two rows, and a paste keeps its lines and never sends. The row under
  it says what Enter and Esc do now, and only keys are drawn as keys.
  What was said and done shows above the list, the newest first.
- Changed: the window is 60 by 40 cells, 3:4 with a 9 by 18 pixel
  cell, and the dialog fits its rows to a smaller window, down to 36 by
  20 cells. The header is the place's name, then the date and the time
  as your locale writes them (12 or 24 hours), then close.
- Changed: the footer, under a rule: Attach, the model, Talk, and the
  mic, as plain text; Tab and Shift+Tab move through them.
- Changed: Attach takes one text or Markdown file for the next question
  only, shown under the prompt with Remove. A request that fails gives
  back its words and its file. A file over 16 kB (what spark reads
  whole), empty, or not UTF-8 text is refused with the reason, never
  cut unseen (it was a megabyte, and spark sent 16 kB of it).
- Changed: the model list says where the model runs (this computer, or
  the spark server this machine is a client of), shows the models in
  use, installed and not downloaded, and says for whom a change counts
  before Enter applies it. Your draft and file stay. Another server or a
  cloud provider shows as not available yet.
- Changed: Talk picks click-to-talk or off. What is heard goes into the
  draft at the cursor, never sent by itself; Esc, a second click or
  leaving the window stops it with nothing kept. Holding Space waits for
  a newer spark.
- Changed: Enter in the prompt sends the words as a request, even when a
  row matches them; the down arrow picks a row. A place's name alone
  still opens it.
- Fixed: a question changed things. A question is answered and now runs
  nothing: the steps spark would take are proposals, run only when
  picked (in the dialog) or said as a request (at the terminal), and
  naming an app in a question no longer opens it.
- Fixed: whether a step waits for a typed yes was the provider's word
  alone. This machine keeps its own list (forget a network, close a
  window, save a layout over another, pair a device) on top of the
  hint, the yes is checked again against what is offered when it is
  typed, and `spark-shell want` at a terminal asks for it too, where
  before it ran such a step at once. With no terminal, the step is kept.
- Fixed: a step that failed or got no answer let the steps after it run.
  They are now not run, and no answer is said as no answer: it may or
  may not have happened.
- Fixed: a reminder done had its file deleted while the step said it
  was safe. Done now puts it aside in `~/calendar/done` for 30 days, and
  undo, or `spark-shell reminders restore NAME`, brings it back.
- Changed: the Calendar draws the two months and, under them, the
  reminders as rows to add, set done or snooze; the time is the
  header's, so the large figures are gone.
- Changed: the workflows run actions/upload-artifact 7.0.2 (dependabot
  #2).
- Changed: the workflows run actions/checkout 7.0.1 (dependabot #3).

## v0.79

Notes and reminders of their own (the owner's review of v0.78: a
reminder set from a terminal went through `spark-shell panel`, and the
home dialog showed notes but no reminders).

- Added: `spark-shell notes`. Alone, your notes with their dates, the
  newest first; `new` or a note's name opens it in your editor, right
  in the terminal you typed in (in a terminal window when there is no
  terminal, as from the dialog); `add WORDS` and `find WORDS` as the
  dialog's. A new note left empty is not kept.
- Added: `spark-shell reminders`. Alone, the reminders ahead under
  their groups, each with its time; `add DAY TIME WORDS` (tomorrow 9:00
  call the dentist), `done NAME` and `snooze NAME`. Notes and reminders
  are files, so both work on a Mac too.
- Added: a reminder due on tmux's status line, before spark's line, in
  the accent: a terminal outside the desktop and a Mac see it, and the
  short sound plays there too (afplay on a Mac). The bar and the line
  both ask every 15 seconds; a lock keeps the sound to once.
- Changed: the reminders section opens with `new reminder`, a row like
  `new note`: Enter asks for when and what, and the hint says how (`fri
  9am call the vet`). The "say it" line that stood in its place is gone.
  A tool's argument may now carry a description, and the dialog's hint
  says it when it asks for that argument.
- Fixed: the home dialog had no reminders unless one was due (a
  reminder ahead was a look-only row). It now shows `new reminder` and
  the next one ahead with its day and time; Enter on it opens the rest.
- Fixed: notes find failed when the last note looked at did not say the
  words (the loop ended false under set -e). The dialog never saw it:
  there the step runs inside an if.
- Changed: help. Notes and reminders have their lines; `spark-shell
  panel` is the dialog's list as text, for scripts, and its words form
  is `spark-shell want`.

## v0.78

Notes, reminders and a Calendar that uses the space (the owner's picks
from the mock-ups: the Calendar layout B, notes as Markdown in ~/notes,
reminders as iCalendar in ~/calendar, a due reminder a bar block and a
short sound, a note opened in the editor).

- Added: Notes. The dialog's `notes` section: a new note, then the
  notes, the newest first, the date a column. A note is a Markdown file
  in ~/notes, its first line its name. Enter opens it in the editor
  (EDITOR, else nano, else vi) in a foot window. Tools for spark:
  notes_new, notes_open, notes_add (`NAME: TEXT` adds a line to the
  note named so, else a new note) and notes_find (the note and the line
  that say the words).
- Added: Reminders. The `reminders` section: due, today, tomorrow, this
  week and later, the time a column. A reminder is an iCalendar event
  (RFC 5545) with its alarm at its time, one .ics file each in
  ~/calendar, its time local; events other tools write there are read
  too, a time in UTC turned local. Tools: reminders_add (when: today,
  tomorrow, a weekday or a date as `2026-11-03`, then a time as 18:30
  or 9am, then the words), reminders_done and reminders_snooze (10 minutes on).
- Added: a due reminder. The bar's line, every 15 seconds, finds one
  due: a `due` block (the word muted, a dot in the accent, the words),
  a short sound once (assets/chime.wav, made for spark-shell; PipeWire,
  else ALSA), and a click opens the reminders, where it has done and
  again in 10 minutes.
- Changed: the Calendar. The time, then this month and the next side
  by side, a day with a reminder in the accent, then the agenda of the
  reminders ahead in their groups, the times lined up on the right.
  The rows schema gains `date`, a day as `2026-10-20`, for it.
- Changed: a column that starts or ends with a figure lines up on its
  right edge (a time, Fri 20:00), as a size does.
- Fixed: which screen answers DDC/CI was kept on disk, so a "none"
  from a session without the i2c group yet (before its next login)
  outlived the reboot and hid the bar's light block for an hour. The
  answer lives in the runtime directory now, which a reboot clears; a
  bus or none is kept 10 minutes, and a screen asleep one.

## v0.77

The display, the keyboard and the screens (the owner's word: the idle
minutes a setting, `desktop display idle|lock N`, with brightness, the
keyboard layout and screens in the same arc).

- Added: `spark-shell desktop display idle N` and `lock N`, the
  minutes before the display turns off and before the screen locks (0:
  never), kept as DISPLAY_IDLE and DISPLAY_LOCK (10 and 15 by
  default). The sway template's swayidle line comes from them, and a
  running desktop takes a change at once (its swayidle started again).
  v0.76 had them fixed in the template.
- Added: the brightness. `desktop display brightness N|up|down`, the
  brightness keys and the bar's new `light` gauge (a click sets it,
  the wheel nudges it) set a laptop's backlight through brightnessctl,
  or a screen's own through DDC/CI and ddcutil, on the screen's bus
  (which screen answers is kept 10 minutes, its level 60 seconds), one
  ddcutil at a time. On desktop adds you to the video and i2c groups
  that exist, recorded, and loads i2c-dev now; off desktop takes back
  only those groups.
- Added: the keyboard. KEYBOARD holds the layouts by their xkb names,
  a variant after a plus (`us us+intl br`); `desktop keyboard us br`
  sets them (a name xkb does not list is refused), and Super+Ctrl+space,
  `desktop keyboard next` and a click on the bar's new `kb` block go to
  the next. `kb` shows the layout in use, only with more than one.
- Added: screens. `desktop screen` lists them by port, make, model and
  serial, with mode, scale and place; `desktop screen NAME scale N`,
  `mode WxH`, `left-of`, `right-of`, `above` and `below` another set
  one, at once in sway and kept in ~/.config/spark-shell/screens.conf
  by make, model and serial (sway's own words, Unknown for a part a
  screen does not give), which the sway template includes. `on` and
  `off` hold until the desktop starts again, so no start comes up with
  no screen; the last screen on stays on.
- Added: the dialog's `display` section (the minutes, brighter and
  dimmer, a row per screen) and `keyboard` section (the layouts, the
  next), with five tools for spark: display_idle, display_lock,
  display_brightness, keyboard_use, keyboard_next.
- Changed: PKG_DESKTOP adds brightnessctl and ddcutil (Void i2c-tools,
  Debian brightness-udev).
- Fixed: two screens that share make, model and serial (no serial, the
  same model) go by their ports, so a change to one never sets both.
- Fixed: the dialog failed with "Illegal number" when sway gave no
  answer about its windows; it now counts none.

## v0.76

The lock and screen capture (the owner's picks: off, then lock; the
lock screen A of the mock-ups, the wallpaper alone so a picture stands
as art; screen capture with the standard tools; every folder
lowercase).

- Added: ten idle minutes turn the display off and fifteen lock the
  screen, and where logind runs (Debian, Arch) it locks before the
  machine sleeps (swayidle in the sway template; Void has no logind to
  tell it). Super+Escape and `spark-shell desktop lock` lock it now.
- Added: the lock is swaylock over the desktop's own wallpaper (a
  picture, or the ground or a color), in the palette: at rest nothing
  over the picture; the ring comes up with the first key, in the
  accent, the key in the text color, a wrong password in the red, then
  the count of wrong tries. A lock already up stays.
- Added: screen capture. Print takes the screen in use, Shift+Print an
  area you drag (slurp), Super+Print the window in front; `spark-shell
  desktop capture screen|area|window` does the same, and the dialog's
  window section has two rows for it (a tool, window_capture), run a
  second after the dialog closes so it is not in the picture. A PNG
  named by the time lands in ~/pictures/screenshots and on the
  clipboard (wl-copy).
- Changed: PKG_DESKTOP adds swayidle, swaylock, grim, slurp and
  wl-clipboard on Debian, Arch and Void.
- Changed: the about dialog groups the key rows in five: Print counts
  as a combo, and the lock and capture keys sit in a group of their
  own before the two plain sentences.

## v0.75

PipeWire with the desktop (the owner's word: build it next, one arc,
with the volume keys and the bar on it, proven on a real machine).

- Added: `spark-shell on desktop` installs the sound with the desktop,
  PKG_SOUND: PipeWire, WirePlumber, its PulseAudio server, its ALSA
  files and Bluetooth sound, by each family's names. The login screen
  alone does not take them. On Arch with pulseaudio installed,
  pipewire-pulse is left out with a todo that says how to take it:
  pacman refuses the conflict unasked, and every package with it.
- Added: where systemd runs, the packages' own user services start
  PipeWire at every login, and spark-shell adds nothing. On Void
  nothing would: `spark-shell desktop` starts PipeWire, WirePlumber
  and pipewire-pulse before sway and stops them when sway ends (none
  when one already answers, and neither WirePlumber nor pipewire-pulse
  when a pipewire.conf.d file has PipeWire start them, the Void
  handbook's way). It runs with no session bus; WirePlumber then leaves
  out only its device reservation.
- Added: on Void, `on desktop` links PipeWire's two ALSA files into
  /etc/alsa/conf.d (Debian's and Arch's packages put them there
  themselves), so ALSA programs play through PipeWire, and adds you to
  the audio group, since without logind nothing opens the sound
  devices to the person at the screen. Each step is recorded, as
  seatd's are, and `off desktop` undoes only those.
- Added: check has a sound row: PipeWire answers, with the output and
  the mic it uses, or it starts with the desktop. A warn each says a
  missing link or group, an ~/.asoundrc of yours that sends ALSA's
  default elsewhere, and bluez-alsa running beside PipeWire (only one
  of them can offer Bluetooth sound).
- Changed: the bar's own ~/.config/alsa/asoundrc goes once PipeWire
  is in: PipeWire moves the sound itself. The bar, the volume keys and
  a pick of output already spoke wpctl; tests now drive that path.
- Fixed: an ~/.asoundrc that sets no default was taken as one that
  does, so a pick of output on plain ALSA could be refused naming no
  file.

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
- Fixed: an update while the login screen runs. The screen's programs
  (its binary, the session, the window, the run file, the boot hook)
  are put in place by a rename, never written over: Linux refuses a
  write to a running binary, and sh reads a script as it runs.
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
