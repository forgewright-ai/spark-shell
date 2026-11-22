# Changelog

## v0.162.1

- A workspace's heading fits its window. Its name stays at 28
  pixels; what follows it (its label, this one, its screen) stands
  after it in the smaller text, cut where the window ends. On two
  screens the heading ran past the window's edge.
- A workspace's screen is named by its model, as the display place
  names it, and a laptop's own screen is the built-in screen. The
  port (HDMI-A-1) stays where two screens share a model or one has
  none.
- The dialog is 0.162.1.

## v0.162

- Workspaces, notes, the Calendar, system, help and power read as
  apps, files and settings do: their groups named at 28 pixels, a
  row of words two lines, its name over its words, and a key in the
  smaller text at the row's end, with no box.
- The Calendar shows the time at 72 pixels and the day under it,
  then as many months side by side as the window holds: one at
  home's start size, five at full screen. Each month is named large;
  today is in the accent and underlined, and a day with a reminder
  is in the accent. Left and Right still move the months.
- Help in a wide window is a sheet of its keys in columns.
- A workspace's heading says its number once.
- The dialog is 0.162.0.

## v0.161

- Settings reads as apps and files do: its groups named at 28
  pixels, a setting two lines, its name over what it is set to now.
  The group look is named appearance, and notifications is a group
  of its own.
- A setting is one row on its page: its options side by side, the
  one in use in the accent, and Left and Right change it in place.
  A switch is on and off; a value of a few choices shows them all;
  a longer one stands between its two words (less 35% more). Every
  option is a target a finger hits, 44 pixels at least.
- A text size is auto and an A at each size around the one in use,
  the size after them.
- The bar's place is one row: top, bottom, hidden.
- A wide window shows the lit setting's page beside settings, as
  it does an app's and a file's.
- The dialog, the bar and the pad share one theme library,
  spark-theme: one rule for colors, light and dark, and the glyphs.
  Nothing changes on screen; the bar and the pad are new builds.
- CI checks the crates with cargo-deny-action 2.1.2: its five steps
  are pinned at the sha the upstream v2.1.2 tag names (#34).
- The dialog is 0.161.0.

## v0.160

- A wide window shows the lit app or file beside the list at once,
  in large type: its name at 72 pixels, one line of what it is, its
  facts side by side, and what you do with it. No line and no box
  stand between the list and it. A window is wide from 1280 pixels;
  there Esc goes back and Tab moves the keys into the page.
- A file's page shows what the file holds in the form that suits
  it: a folder's newest names, a text's first lines, a picture at
  its own size, a PDF's first page, a sound's waveform, a video's
  frame. A sound that says its title is named by it. Two panes keep
  the page as a third column from 1900 pixels.
- The groups of apps are named at 28 pixels, and no count stands
  beside a group: the total stays on the line that says where you
  are.
- A file's row is two lines, as an app's: its name, and under it
  what it is, its size and its date. A folder's own folders and
  files stand under those two names. A long name keeps more of its
  letters, in a pane most of all, and two panes have no line
  between them.
- A sound's bars stay a cell wide at full screen, where 28 of them
  stretched to five cells each: there are as many as the window
  holds.
- The trash is used only when it is yours (#27). A trash that came
  with a drive, its files a link to a folder elsewhere, sent
  `delete for good` to that folder. A link at the trash's top, its
  files or its info, a trash of another user, or one the others can
  write is refused, and a path changed after the check leads
  nowhere else.
- Home no longer freezes when a provider stops reading (#28). What
  it sends a provider waits in a queue of 2 MiB at most, a step's
  time limit covers the wait, and a provider that never reads is
  said to have stopped.
- A wired network step keeps a change another editor made right
  after its own write (#29): it was taken for the step's own, and
  undo erased it.
- On a dhcpcd system a failed network step puts the settings file
  back even when dhcpcd is gone or was restarted (#30), and says
  whether the connection was confirmed too.
- On a dhcpcd system every wired network step failed since v0.137:
  the helper was asked for by a name its file no longer has.
- Two settings changed at once both stay (#31). A change read the
  config, then wrote all of it, so the later of two dropped the
  other's line and both said ok. A change now holds a lock from its
  read to its write; one that waits 3 seconds for it says so and
  writes nothing.
- The dialog is 0.160.0.

## v0.159

- A receipt leaves the line over the keys after eight seconds: `out
  at 10%` with its undo stayed there until the next key. The undo
  itself stays: type `undo`. A refusal and a note stay until the
  next key, as before.
- The bar shows at once a sound level set from home. The steps for
  the output and the microphone never asked the bar for a new line,
  so it showed the change at its next one, up to 15 seconds later.

## v0.158.2

- The dialog builds on a Mac again, so the checks before a push pass
  there. Its window is Linux's alone, and since v0.153 the dialog asked
  that window when its frame was drawn, a question the Mac's stand-in
  could not answer; the painter's test used cairo, which only Linux
  builds. Only the build changed: the dialog runs as before. The
  dialog is 0.158.2.

## v0.158.1

- After an update home opens the new dialog. Home stays running while
  it is put away, and Super+Space brings that window back, so a home
  put away before `spark-shell update` kept the dialog it started with
  until a logout: on the owner's box v0.158's fixes did not show. on
  now closes a home that is put away and runs the build the update
  replaced; a home on screen is left as it is.

## v0.158

- A video plays again with home full screen. It started and stopped
  at once, and the screen flickered: to show the video the window
  left full screen with its band on, so its size changed, and a video
  stops when the window changes size. The window now leaves full
  screen with no band and no border, at the size of the screen, and
  takes them back after.
- A photo stays in view when it is zoomed in. Past the zoom where the
  first picture of it runs out of pixels, home asks for a larger one.
  Of a photo that file is 25 MB and more, and home read no picture
  over 8 MB, so the view went empty. It reads up to 64 MB now, what
  4096 by 4096 pixels can take.
- A zoomed picture follows the pointer by the pixel while it is
  dragged, and no longer jumps at the first motion.
- The view names its file: `home / view / ~/pictures / photo.jpg` on
  the line that says where you are. The name was nowhere on screen.
- While the view waits for a large file, the line over the keys says
  `loading NAME` beside the moving bar, as an app that opens has it.
  The animation of the theme no longer plays in the view. A long
  sound says `drawing the waveform` the same way.
- The wheel moves the lit row again, a row a notch, in every list.
  Since v0.155 it scrolled the list in home's own window and left the
  lit row where it was. A drag still scrolls the list.

## v0.157

- Files in its own window is laid out by the pixel, as home and apps
  are. A file is a row of 44 pixels: its name leads, its size and its
  date stand beside it in the smaller text, and the name of a folder
  ends in a slash. In a wide window the size and the date stay beside
  the names. A name too long for its column is cut in its middle.
- The line that says where you are names each folder from your home
  down: `home / files / documents / research`. A click on a folder
  goes there. What the folder holds stands at the end of that line:
  the row that said it is gone, and so is the line of the lit file
  over the keys.
- Four keys stand under a list of files: back, open, view, details.
  Every other key works as before; the details of a file list them.
- The details of a file (F9, or Right on the file) open beside the
  list where the window is 600 pixels wide or more: what the file
  shows (a picture, a page of a PDF, the first lines of a text, the
  picture of a sound), its name, its kind, its size, when it changed,
  and what you do with it, each row with its key. Tab goes to the list
  and back, and the details follow the lit file. Esc closes them. A
  narrower window shows them as a page.
- Two panes stand side by side in the new rows, each under the name
  of its folder. A click on the other pane takes the keys there.
  `second pane` in the details of a file opens the second pane, as
  Ctrl+Tab does.
- In files Right opens the lit folder, Left goes back a level and Tab
  changes the pane. Until now the two arrows changed the pane there.
- Beside a list, Tab goes to what stands beside it and back: the
  details of an app, the details of a file, the other pane. The
  controls at the end of the input (attach, talk) are Shift+Tab from
  the list.
- In a wide window what ends a row (a value, a switch, a key) stays
  within 640 pixels of the start of the row.
- The view of a sound or a video shows again with mpv 0.42: it came
  empty there, with no waveform and no frame. mpv 0.42 prints a
  control character as `?`, and the files provider parted what it
  asked of mpv with one. It asks for a line each now.

## v0.156

- In files the second pane opens again at the size home starts at.
  v0.155 refused it there and said two panes need a window 60 cells
  wide: inside the new frame the rows of a place had 59 columns.
- The lit row of the left pane starts at the edge of the window, as
  every other lit row does.
- Right goes in a level where the lit row opens one: a place of home,
  the details of an app, a list or a page a row opens. Left goes back
  a level, as before. A row that acts stays for Enter: Right opens no
  app and runs no step. Typed words keep both arrows, and in files
  they still change the pane.
- While a list is dragged the pointer is the holding hand.

## v0.155

- Home in its own window is laid out by the pixel: two sizes of text,
  rows a finger can hit, and the keys of the part that holds them. The
  terminal and the login screen draw as before.
- A row of home is 44 pixels high: the place, and what it holds now,
  on one line. A row stays lit while the line is empty: Enter opens it,
  and Down hands the list the keys. What you type finds as before, in
  the same rows.
- An app is a row of two lines: its icon at 32 pixels, its name, and
  under it what the app is, never cut by a column. A category says how
  many apps it has. The app spacing setting sets the row: 40, 46 or 52
  pixels.
- A line under the input says where you are: `home / apps`. A click on
  a name before the last goes there. In apps the count of the list
  stands at its end. The band of the window names the place alone.
- The details of an app (F9) open beside the list where the window is
  600 pixels wide or more: the list becomes a column of names with the
  app lit. Tab goes to the list and back, and the details follow the
  app lit. Esc closes them. A narrower window shows them as a page.
- A list longer than the window shows is cut at its edge, a part of
  the next row in view: no scrollbar says it. Drag the list to scroll
  it; a press let go where it began is the click. Over a list the
  wheel scrolls it, and the lit row stays where it is.
- In a wide window home and apps take the width of the window.
- A draft longer than the line shows the row you are typing, with a
  sign where more of it stands above or under.
- Every other place keeps its rows as they were, inside the new frame.

## v0.154

- A second kind of key may sign a release: a patch key, kept on a
  machine that tags fixes. An install takes what it signed for a patch
  (vX.Y.Z) and for no other tag: a vX.Y stays the release key's alone.
  Whoever holds that machine can sign a patch: a known exposure, taken
  by choice.
- `sh test/tag.sh` is that machine's rule. It tags main under a
  three-part heading when nothing guarded differs from the release it
  patches, the keys of `config.example` are as they were, at most 400
  lines changed, CI passed in main's own run and the fix has rested
  six hours on main. The entry, with the help, is guarded.
- A release needs main's own CI run of its commit: a branch's run may
  be the fast lane's.

## v0.153.1

- A write as root that fails ends `spark-shell on` or `off` there, with
  a row that says what could not be written and why, in the system's
  own words. It was said to have worked: where a file was being put
  back, the copy kept of it was then removed, and the file as it was
  before spark-shell was lost.
- on's last lines then say the two ways on: `spark-shell on` again goes
  on from there once that is fixed, and `spark-shell off` puts back
  what spark-shell changed. off's last lines say that off again goes
  on from there. Nothing is undone for you, and no question is asked.
- The same last lines follow when on or off ends any other way: a step
  with no row of its own, or Ctrl+C.
- The rule that lets you restart and shut down from the dialog, and
  the rule that lets you mount drives, each say their own row when
  they cannot be written, and on goes on. They were said to be in
  place. The console's colors are no longer said to be back when
  their line at boot could not be removed.
- `spark-shell off` removes nothing of yours. A render you changed
  since, or a file of your own where a render stood, is kept beside it
  by its time before the file from before spark-shell comes back.
  `off --dry-run` has a keep row for it.
- `off desktop` keeps its record of the groups it added for the
  brightness while one of them could not be removed, so off desktop
  again finds it.
- The package lists are read from the release that runs. A desktop
  kept the lists of the release it started under, and they outranked
  the file: after an update, a package the new release added was not
  asked for until the next login.
- A key added to a config whose last line had no new line was glued
  onto that line. It stands on a line of its own, and the config is
  replaced in one step when a key is added, as when one is changed.
- The palette's files, `theme.env` among them, are replaced in one
  step. A shell that started while the theme changed could read an
  emptied file.
- On a system with runit, `on` started the bluetooth services again on
  every run, with a root command each time, and a refusal ended `on`
  with no row. A service already enabled is left as it is.
- A window's name with wide characters (ideographs, most emoji) is cut
  by the cells it takes on its band. Counted as one cell each, such a
  name pushed the voice meter off the band's end. The pad counts with
  the unicode-width crate, which the dialog has already.
- A click on the bar shows a workspace whose name holds a quote or a
  backslash. The bar sent the name without them, and sway showed a
  new, empty workspace of that other name.
- The bar's state names the clock and the notifications as dropped on
  a screen too narrow for them.
- On the pad, the windows of the last cell, where several apps fold
  together on the bar, are listed oldest first.
- The pad is laid out again when the bar comes, goes or moves, and no
  longer each time the pointer crosses the bar.
- In the dialog, a section whose first answer came late is asked
  again. It stayed empty until the dialog was opened again.
- With some 240 notes or more, every action there said "private
  details withheld" in place of its receipt and lost its undo. The
  check reads the whole result.
- A plan whose step is refused after an earlier step opened a window
  keeps the dialog open, with the refusal. It closed.
- A password typed for a step spark proposed is not written back into
  the prompt: the step names it and keeps its value back.
- A switch, a quiet row or a preview's key runs no tool that needs its
  question.
- A question from a part of the desktop keeps what was being typed,
  and ends with its call.
- A part of the desktop that stops while it sets a value no longer
  holds every other switch for two minutes.

## v0.153

- Home lists nine places in two groups: apps, files, workspaces, notes
  and calendar; then settings, system, help and power.
- workspace is named workspaces: it lists them all.
- tools is named system, the name this place has on other desktops.
  Its rows are check, space, running, details, updates and software.
  details is the row that was named system.
- about is the last row of system and no longer a place of home.
- In settings, the group that was named system is two: power (power,
  battery) and spark (talk, connections).
- The section's name is system everywhere: `spark-shell panel system`
  and `spark-shell provide system`. `spark-shell on` takes the line
  named tools off spark's MCP list and puts system on it. What the
  section keeps moves to its new folder by itself.
- The bar's status no longer depends on how bash treats a signal it
  catches. The process that takes the redraw signal draws nothing, and
  the lines are drawn by one that catches none. Two faults of bash
  ended the status at a click or a turn of the wheel: the one of
  v0.152, and one in bash 5.2, which is the sh of no system
  spark-shell is proven on.
- Home is shown when its frame is drawn. With no opening animation, a
  first frame slow to paint left home open and not shown: it was shown
  before its window was there. The window now says when its frame is
  with the compositor.
- In a tabbed container every tab's buttons act. Only the last tab's
  did; a click on another tab's button focused the tab.
- The redraw signal goes to the bar's status alone. The pid kept in
  the bar's file outlives a crash and a restart of the machine, and a
  change that redraws the bar sent the signal to whatever program had
  that pid by then, which ended it. The pad sent it the same way.
- With Caps Lock on, the keys with Ctrl work in home.
- On two screens of different scale, home is painted at the scale of
  the screen it is on.
- After a click that opens an app, the pointer's moves over home are
  moves again, not a drag.
- A name with an emoji sign in it no longer puts the rest of its row
  one cell off.
- A paste waits five seconds for the program that holds the text, and
  a held Ctrl+V starts one read.
- A sound's picture takes the new look's tones when the look changes
  while it is open.
- One slow answer from sway no longer leaves the pad and the bar
  reading each later answer one request late.
- A percent sign in a window's name is shown as written: sway read
  %title and its like inside the name.
- The pad takes its key signals from its first moment, and gives the
  keys back when their screen goes.
- The bar draws its dragged copy once the compositor has answered for
  it, and a second button pressed while the bar is dragged does not
  drop it.
- The dialog builds with libloading 0.9.1, and dialog.env pins that
  build.
- The pad builds with libloading 0.9.1, and winpad.env pins that build.
- The bar builds with libloading 0.9.1, and bar.env pins that build.
- The ear and the wallpaper build with libloading 0.9.1, and ear.env
  and wallpaper.env pin those builds.
- CI takes a change by what it touches. A fix of up to 400 lines in a
  module that neither acts as root nor fetches, in the tests or in the
  docs runs lint and the suite on Debian and Fedora. Anything else
  runs every job, and main runs every job at each landing.
  `sh test/lane.sh` names the lane.
- A component whose pin is not written ends a CI run after the builds,
  about three minutes in.
- `sh test/prove.sh` proves a change before a push: the gate, the suite
  as a user and as root the way CI's containers run it, and the
  desktop's proofs, each in a home of its own with sudo refused.
- Dependabot opens one pull request for a crate across the five
  components.

## v0.152.1

- `spark-shell update` moves a Linux install on v0.151 or before again.
  Before it moves, update asks whether the new release's dialog can be
  fetched, by the name of the build it knows, and v0.152 named its
  build spark-dialog-x86_64-linux-gnu: every such install said "not
  published yet" for good. The release now also carries a note under
  the old name, spark-dialog-x86_64-linux-musl, so those installs move
  to this one, whose own code fetches the new build.
- update now asks for the release's SBOM, spark-dialog.cdx.json, the
  last file a release uploads and a name no release changes, so a
  renamed build cannot hold an install back again.

## v0.152

- Home is a window of its own. spark-dialog opens it and draws it with
  cairo and pango, as the bar and the pad draw theirs; foot no longer
  holds it. It wears the band every window wears: its buttons, its
  name, a drag by it.
- Home's top is one line: the prompt, with attach and talk at its end.
  The dialog's own band row is gone, and home names no model: the
  model and its choice are in settings.
- Pictures are painted as they are: a file's view, the apps' icons and
  the opening keep all their tones and their soft edges. In foot they
  were cut to 255.
- Ctrl+V or Ctrl+Shift+V pastes the clipboard. Shift+Insert and the
  middle button paste what the pointer last selected.
- The text cursor is steady, a block while home has the keys and its
  outline while it has not.
- A click on a reminder's or a drive's notification opens home through
  the same opener as Super+Space, so it never opens a second home.
- Where the dialog cannot open a window of its own, home opens in foot
  as before. The login screen stays in the terminal.
- The dialog's release build is spark-dialog-x86_64-linux-gnu: it links
  glibc, as the bar's does, to open Wayland, cairo and pango when it
  runs.
- Where sh is bash (Arch, Fedora, openSUSE) the bar's status no longer
  starts again by itself. A click or the wheel on the bar that came
  while the status looked at the drives could end it; it came back a
  second later, and a sound change that had just failed lost its sign.
  bash ends a shell there, so the look runs apart from the status.
- A setting is written in one step. The config was emptied and then
  written, and a program that started in that instant ran on the
  defaults: after a drag the bar could come back in the default text
  size.

## v0.151

- A dragged bar comes with the pointer: a copy of the bar follows it
  up or down the screen, as a dragged pad does, and the line at the
  other edge still says where it will land. Before, a drag showed the
  pointer alone, and the line once the pointer was past the middle.

## v0.150.2

- After `spark-shell update` the bar runs the new code even when only
  the modules in src/ changed. on started the bar again only when the
  top spark-shell file was newer than the bar, and since v0.136 the
  code is in src/, so an update such as v0.150.1 left the bar on the
  code it read at login until a logout.

## v0.150.1

- The sound and the mic lists come back when ALSA's default never
  answers, as a sound server's plugin does where no server runs. Each
  ask is given three seconds, then the first card stands. Before, the
  list never came, and the program that asked stayed behind it for
  good.

## v0.150

- The bar's status is narrower. The icons of a group stand two cells
  apart and the groups four, where they were three and five, and the
  right edge keeps one cell, as the left does. On a screen 1200 pixels
  wide the status is 90 pixels shorter, and the pad's windows get those
  pixels.
- A click or a tap beside an icon is on it: an icon's target reaches a
  cell past each of its sides, so the icons of a group leave no dead
  space between them, 40 pixels each on a touch screen. A gauge keeps
  its own cells: a click sets its level by where it falls.
- A dragged bar shows where it will land: an accent line across the
  screen's other edge once the pointer is in that half.
- Through a drag the pointer is the holding hand, on the bar and on the
  pad as on a window. Before, a dragged pad showed the four arrows.
- A pad dragged onto the bar shows on the bar, where it will stand,
  with the line at the screen's edge over it.
- A bar that moves takes the pad with it in one step. Before, the pad
  showed for a moment, went and came back, and the bar flashed its
  count meanwhile.
- After the bar moves, the windows the keys placed stand at their places
  on the new area, whole. Before, they were left 44 pixels short.
- The focused window's frame is the accent on every side. Before, a
  tiled window alone on its workspace had a pale line at its right,
  which read as a thicker border than the left one. The drop area of a
  dragged window is tinted in the accent at half its strength.

## v0.149.1

- A window minimized from inside a floating group is on the pad. A
  split or tabs key on a placed window puts it in a group, and the
  group goes to the pad whole: each window in it has its icon there,
  and one of them brings the group back where it was. Before, the
  window was on no pad and could not be brought back. One already lost
  this way is on the pad after the update.
- A wallpaper or theme change leaves no process behind. Since v0.139
  each change on a running desktop left one wallpaper process, about
  9 MB, until logout.

## v0.149

- The bar's signs are icons: the wire, bluetooth, wifi, sound, the
  microphone, brightness, the keyboard, the battery, a reminder,
  notifications and do not disturb. The bar draws each one at the
  text's size and colors it by its state; a muted or silent one is
  hollow. The gauges and the workspaces keep the glyph family's signs.
- Wifi's icon lights its bands by the signal. The battery has an icon:
  full, half, low, and a bolt while it charges.
- The icons need no font: a machine without Monaspace Neon draws the
  same ones.
- The pad stands on the bar, after the workspaces: home, workspaces,
  apps. A minimized window is an icon there, and the windows get back
  the strip the pad kept at an edge. A config that names a place for
  the pad keeps it.
- The pad is still its own. Drag it by its grip, the line before its
  icons, and it floats or docks at an edge as before. Near the bar's
  edge it docks in a strip of its own; it lands on the bar only with
  the pointer on the bar.
- Off the bar the pad is a piece of the bar: the bar's ground and
  height, its grip and a fine edge. The handle across its top is gone.
- The bar moves by the pointer: drag its empty ground to the other half
  of the screen and it stands at that edge. The pointer is a hand on
  what a click acts on.
- sway's mode name stands before the status, so the apps do not move
  when a mode starts.
- The tray's icons are 24 px, as the pad's are.

## v0.148.2

- The idle screen is the clock alone again: the bar and the pad leave a
  screen while it rests, and are back with your workspace.
- On an urgent window's band the close button can be seen: its controls
  wear the title's color, as on the band with the focus.
- What is written on the accent reads at 4.5 to 1 in every palette: the
  plate's digits, the title of the band with the focus, an urgent
  band's title, and the color of a workspace that asks for you. Where a
  palette's own colors already read, nothing changes.

## v0.148.1

- The workspaces stay still: every place is as wide as the plate, so
  nothing moves when you go to another workspace.
- Under the pointer a thing keeps its color and the ground behind it
  lifts one step, on the bar, on the logo and on a window's controls
  alike. Close alone turns red.
- The mic on a window's band wears the title's color, as the other
  controls do.
- A muted level dims its sign with its gauge.
- With the keyboard on the bar, Left and Right always move, and Up and
  Down set a level. A click, or the pointer leaving the bar, gives the
  keys back, as Escape does.
- Where Monaspace Neon is not installed, the bar's keyboard, reminder
  and do not disturb signs are ones DejaVu Sans Mono has, not a box.
  Fedora installs DejaVu Sans and Serif for the signs the mono face
  lacks.
- A terminal fills its window: the wallpaper no longer shows between
  its band, its border and its text.
- Firefox draws no title bar and no round corners of its own under the
  band.

## v0.148

The bar gets a look of its own, and spark-shell its new logo.

- The workspaces are ten places, always, in the glyph family's own
  pair: full where a workspace is, light where none is. Where you are
  is a plate with the number in two digits. A window that asks for you
  turns its place the attention color.
- Color means something: all that is well is the text color, the
  accent is only where you are, red is for what is wrong or records.
- The time stands alone, in bold, after a hairline; the date is in the
  time section. The notifications sign is always beside the time: the
  flag, or the moon in do not disturb, with the count while something
  waits.
- A level shows its gauge only when it is pinned: spark-shell bar pin
  and unpin take out, mic, light and wifi. The speaker is pinned from
  the start: its sign, its gauge, its percent. A change shows at once
  and its digits flow; BAR_MOTION=no stops the flow.
- spark-shell bar hide and show take a module off the bar and put it
  back (BAR_HIDE). BAR_PINS now names the pinned levels; a line from
  v0.147 is still read, and what it left out stays hidden.
- Under the pointer a thing becomes a chip in its own color, as the
  window controls do. With the keyboard on the bar, a line in the
  accent says where the keys are.
- A state is said by a sign's form and tone, never by a second sign
  beside it: muted is hollow in the text color, off and missing are
  dim, wrong is red. A reminder that is due is its sign alone, and the
  battery its number.
- The shell tells spark-bar facts, and spark-bar decides the look.
- The logo is the diamond in the chevron, on the bar and on the pad.

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
