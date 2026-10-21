# spark-shell

<picture>
<source media="(prefers-color-scheme: dark)" srcset="assets/logo.svg">
<img src="assets/logo-light.svg" alt="spark-shell" width="150">
</picture>

spark-shell sets up the terminal on a Linux machine or a Mac: tmux, a
prompt, a few everyday tools and one color palette. On Linux it can
also add a simple desktop, and spark, the local AI, can open the apps
for a task you describe.

## Before you install

spark-shell changes your machine. `spark-shell on` replaces your shell
files and your tmux, starship and btop settings (yours are saved as
`.bak` files). It installs packages (sudo) and sets the console colors,
also at boot. On a Mac it sets a Terminal.app profile instead.
`spark-shell on desktop` makes a login on tty1 start the desktop.
`spark-shell on login` puts a login screen on tty1 from the next boot.
`spark-shell quiet boot on` changes how the machine boots.

Each of these says what it will change and asks `Continue? [y/N]`
first. `--dry-run` shows every change and changes nothing.
`spark-shell off` undoes it all. The packages stay installed.

## Install

    git clone https://github.com/forgewright-ai/spark-shell ~/.spark-shell
    ~/.spark-shell/spark-shell on

It runs on Debian, Arch and Void Linux, and on macOS. To update, run
`git -C ~/.spark-shell pull`, then `spark-shell on`. spark is optional.
Without it there are no layouts, no spark chat and no status line.

## Commands

    spark-shell on                    set up the terminal (asks first)
    spark-shell on desktop            add the sway desktop on Linux (asks first)
    spark-shell off desktop           remove the desktop, keep the terminal
    spark-shell on login              a login screen on tty1 (Linux, asks)
    spark-shell off login             the console login on tty1 again
    spark-shell off                   undo it all (packages stay installed)
    spark-shell on --dry-run          show what on would change, change nothing
    spark-shell on --yes              do not ask first
    spark-shell status                show what is set up
    spark-shell check                 test the setup (exit 0 when all is ok)
    spark-shell theme NAME|none       set the colors, or use the terminal's own
    spark-shell theme [list]          show the palette in use, or list them all
    spark-shell font FACE SIZE|none   set the console font, or use its own
    spark-shell font list             list the fonts you can use
    spark-shell quiet login on|off    hide the notice before the login (Linux)
    spark-shell quiet boot on|off     hide the boot menu and messages (Linux)
    spark-shell quiet                 show both settings
    spark-shell layout "WORDS"        open apps for that task, picked by spark
    spark-shell layout save [NAME]    save the last layout
    spark-shell layout [NAME]         list the saved layouts, or open one
    spark-shell layout delete NAME    delete a saved layout
    spark-shell apps                  choose the apps a layout may open
    spark-shell notes                 list your notes, the newest first
    spark-shell notes new|NAME        a new note, or that one, in your editor
    spark-shell notes add WORDS       a new note; "NAME: WORDS" adds a line
    spark-shell notes find WORDS      the notes that say it, and the line
    spark-shell reminders             the reminders ahead, in their groups
    spark-shell reminders add DAY TIME WORDS
                                      tomorrow 9:00 call the dentist
    spark-shell reminders done|snooze|restore NAME
                                      done (kept 30 days), in 10 minutes, back
    spark-shell desktop               start the desktop now (from a console)
    spark-shell desktop keys          list the desktop's keys
    spark-shell desktop wallpaper X   set a picture, a color, default or none
    spark-shell desktop lock          lock the screen now (Super+Escape)
    spark-shell desktop capture screen|area|window
                                      a PNG in ~/pictures/screenshots (Print)
    spark-shell desktop display       the idle and lock minutes, the brightness
    spark-shell desktop display idle|lock N
                                      display off, or lock, after N idle minutes
    spark-shell desktop display brightness N|up|down
                                      the screen's brightness, 1 to 100
    spark-shell desktop keyboard [us br|next]
                                      the keyboard's layouts, or the next one
    spark-shell desktop screen [NAME scale N|mode WxH|on|off|left-of NAME]
                                      list the screens, or set one
    spark-shell bar on|off            show or hide the status line and the bar
    spark-shell bar on|off --desktop  the bar alone (--terminal: the line alone)
    spark-shell want "WORDS"          ask for it, "mute everything": steps run;
                                      a question's are shown, not run
    spark-shell want --json "WORDS"   the steps spark picks, as JSON; none run
    spark-shell want --attach FILE "WORDS"
                                      ask about a text file (txt md)
    spark-shell dialog [SECTION]      open the dialog (Super+d), SECTION first
    spark-shell panel [SECTION]       the dialog's list as text, for scripts
    spark-shell provide SECTION       a dialog section as an MCP server on stdio
    spark-shell sbom [NAME]           list the installed software, or one
    spark-shell sbom --json           write the list as a CycloneDX 1.5 file

## Terminal setup

Type `spark-shell on`. You get tmux, starship, fzf, zoxide, eza, bat,
btop, fd and jq, and shell files that use them. Debian has no starship
package, so there the prompt is the shell's own. Your own settings go
in `~/.config/spark-shell/rc`, which spark-shell reads last and never
writes.

## Colors (theme)

Type `spark-shell theme gruvbox-dark`. You get one palette in tmux, the
prompt, btop, the desktop and the Linux console, also at boot. On a Mac
it is a Terminal.app profile named `spark-shell`. `theme list` shows
the 16 palettes, eight dark and eight light, and your own go in
`~/.config/spark-shell/themes/`.
On Linux the terminals you have open change color at once. A program
that is already running, such as btop, changes when it starts again.

## Font

Type `spark-shell font Terminus 16x32`. You get that console font, now
and at every boot (sudo). On a Mac it sets the Terminal.app font
instead: `spark-shell font Monaco 14`.

## Quiet

Type `spark-shell quiet login on`. You get only the login prompt, with
no notice before it. Type `spark-shell quiet boot on`. You get a boot
with no menu and no kernel messages (hold Shift or Space for the menu).
It edits boot files, so it asks first. Linux only.

## Desktop

Type `spark-shell on desktop`. You get sway (a window manager that
tiles windows) and foot (a terminal), in your palette, and the sound:
PipeWire with WirePlumber, for every program and Bluetooth too. Debian,
Arch and Void only. On Debian and Arch, PipeWire's own user services
run it. On Void it starts with the desktop and stops when you leave it,
and `on desktop` also turns on the seatd service, adds you to the
`_seatd` and `audio` groups, and links PipeWire's two ALSA files into
`/etc/alsa/conf.d`, so ALSA programs play through it (sudo).

## Login

Without `spark-shell on login`, the login screen is the normal console
login on every Linux. Log in on tty1 and the desktop starts. Leave the
desktop and you are logged out. Alt+F2 gives a plain shell with no
desktop. ssh never starts it.

Type `spark-shell on login`. From the next boot, tty1 shows a login
screen in your palette, over your wallpaper: the machine's name, its
Linux and version, the date and the time on a strip down the left, and
the form under them. Type your user name and your password, pick the
desktop or a shell (the arrows or a click), and press Enter. No
account is listed, and a wrong try says only `Wrong user name or
password.` F11 restarts the machine and F12 shuts it down, each after
you type `yes`; a click on a key does what the key does. There is no
AI on the login screen: nobody is logged in yet. A line at the bottom
says whether spark is ready, never its address or its model. After
five idle minutes the screen turns off; a key or a mouse move turns it
back on. Nothing else prints on tty1 before the login screen.

greetd runs the login screen, and swayidle turns it off when idle
(Debian, Arch and Void; sudo). tty2 keeps the
console login, so Alt+F2 always lets you in. tty1 changes hands only
at a boot, never under a login that is running. On Void the screen's
account joins the `_seatd` group, and it may run reboot and poweroff,
nothing else. `spark-shell theme` and the wallpaper reach the screen
too. `spark-shell off login` puts the console login back from the next
boot; greetd's package stays.

## Layouts

Type `spark-shell layout "read the news and play music"`. spark picks
apps for that task and opens them: as sway windows on the desktop, or
as tmux windows anywhere else. Add `--desktop` or `--terminal` to
choose. Every window spark proposes is tied to words of yours, quoted
back, and spark-shell checks the quote: `notes and firefox` opens
Firefox for `firefox` and the editor for `notes`. A window spark can
tie to none of your words is padding; it does not open, and is one
Enter away in the dialog, as `layout  also open btop`. Apps your words
name are always opened, each once. Say `fullscreen` and the main
window fills the screen alone. Say `workspace 3` and the layout opens
there.
On the desktop, `Super+d` opens the dialog, and the words go at its
prompt.

`spark-shell layout save writing` saves the last layout, and
`spark-shell layout writing` opens it again without asking spark. It is
a JSON file in `~/.config/spark-shell/layouts/`. The editor is
`$EDITOR`, else micro, else vi. A missing app is skipped, said in one
line.

## Allowed apps

Type `spark-shell apps`. You get a list of the installed apps and
tools. `Tab` selects or clears a row, `Enter` saves to
`~/.config/spark-shell/apps`. A layout then opens only those apps. With
no list, any app with a desktop entry is allowed.

## Keys

Type `spark-shell desktop keys`. You get these lines. The first
desktop start shows them in the about dialog, and the dialog's `about`
row shows them again.

    Super+Return opens a terminal window.
    Super+d opens the dialog: a place to go, or say what you would like.
    Super+s opens the dialog in spark chat, and Ctrl-D closes it.
    Super+Shift+q closes the window.
    Super+Shift+c reloads sway after spark-shell on.
    Super+Shift+e leaves the desktop.
    Super+arrow moves the focus, as h, j, k, l do; Shift moves the window.
    Super+f makes a window fill the screen.
    Super+r resizes the window, until Enter.
    Super+w makes tabs, Super+Shift+s a stack, Super+e side by side again.
    Super+b puts the next window beside this one, and Super+v below it.
    Super+1..0 go to workspaces 1 to 10; with Shift the window goes there.
    Super+Escape locks the screen; it locks by itself after idle minutes.
    Print captures the screen, Shift+Print an area, Super+Print the window.
    Super+Ctrl+space goes to the next keyboard layout.
    The volume and mute keys set the sound, and the mic mute key the mic.
    The brightness keys set the screen's brightness.
    Typing exit in the first window also leaves the desktop.

## Display, keyboard and screens

`spark-shell desktop display` shows the idle and lock minutes and the
brightness. `display idle 10` turns the display off after 10 idle
minutes, `display lock 15` locks the screen after 15, and 0 means
never; a running desktop takes the change at once. `display
brightness 70` (or `up`, `down`, and the brightness keys) sets a
laptop's backlight through brightnessctl, or a screen's own through
DDC/CI and ddcutil; the bar's `light` gauge sets it with a click or the
wheel. On desktop adds you to the `video` and `i2c` groups for it.

`spark-shell desktop keyboard us br` gives the keyboard two layouts, a
variant after a plus (`us+intl`); Super+Ctrl+space, a click on the
bar's `kb` block and `desktop keyboard next` go to the next one. The
`kb` block shows only with more than one layout.

`spark-shell desktop screen` lists the screens. `desktop screen NAME
scale 1.5`, `mode 2560x1440`, or `left-of`, `right-of`, `above` and
`below` another screen set one, by its port or words of its make and
model; each is sway's at once and kept, by the screen's make, model and
serial, in `~/.config/spark-shell/screens.conf`. `on` and `off` hold
until the desktop starts again, so a later start never comes up with no
screen, and the last screen on stays on. The dialog has a `display` and
a `keyboard` section for the same.

## Notes and reminders

A note is a Markdown file in `~/notes`, its first line its name, so
any editor and any sync reads it. A reminder is an iCalendar event
with its alarm at its time, one `.ics` file each in `~/calendar`, the
standard other calendars read (khal, and the Calendar of a Mac or a
phone through a CalDAV sync). An event, not a to-do: Apple's Reminders
no longer take to-dos over CalDAV, while every calendar takes events.

Both work in a terminal, on the desktop and on a Mac:

    spark-shell notes add groceries: buy oat milk
    spark-shell notes groceries
    spark-shell reminders add tomorrow 9:00 call the dentist
    spark-shell reminders

The day is today, tomorrow, a weekday (fri or friday) or a date
(2026-11-03); the time is 18:30, 9am or 6:30pm; the rest is the words.
A note opens in your editor right in the terminal you typed in, and in
a terminal window from the dialog. A new note you leave empty is not
kept.

When a reminder comes due, the bar shows a `due` block with its words,
a click opens the reminders, and a short sound plays once (PipeWire,
else ALSA; afplay on a Mac). The tmux status line shows it too, in the
accent, so a terminal outside the desktop and a Mac hear and see it.
Both lines check the time every 15 seconds, so nothing more runs for
it. Done takes the reminder away; again in 10 minutes moves it on.

## Lock and capture

After the idle minutes (10 for the display, 15 for the lock) the display
turns off, then the screen locks. Where logind runs (Debian, Arch), it
locks before the machine sleeps too; Void has no logind to say so.
Super+Escape, or `spark-shell desktop lock`, locks it now. The lock is
swaylock over your wallpaper, in the palette: at rest the picture alone,
and a ring comes up with the first key you type.

Print takes a picture of the screen, Shift+Print of an area you drag,
and Super+Print of the window in front; `spark-shell desktop capture
screen|area|window` does the same, and the dialog's `window` section
has the screen and an area. Each picture is a PNG named by the time in
`~/pictures/screenshots`, and it is on the clipboard too (grim, slurp
and wl-clipboard).

## Wallpaper

By default there is no picture. Behind the windows is the ground: the
palette's background a shade darker than the windows, so the
transparent terminals sit on something quieter than themselves. It
follows the palette. Type `spark-shell desktop wallpaper
/path/to/picture.jpg` for a picture of yours. A path from where you
are, or one that starts with `~`, works too. `default` is the ground
again. `none` fills the screen with the windows, solid, in the
palette's background color.

Type `spark-shell desktop wallpaper skyline`. You get one of the 17
wallpapers spark-shell ships in `wallpaper/`, each drawn for a palette.
For the dark ones: skyline (tokyonight-night), fjord (nord), forest
(everforest-dark), sunset (gruvbox-dark), hills (catppuccin-mocha),
dunes (dracula), ripples (rose-pine), contours (selenized-dark) and
embers (any dark palette). For the light ones: morning
(solarized-light), meadow (catppuccin-latte), kites (tokyonight-day),
fields (gruvbox-light), grove (everforest-light), arches
(rose-pine-dawn), shore (selenized-light) and flight (one-light).
Each is its SVG source and a 3840 by 2160 PNG, and the config keeps its
name, so it follows the clone.

Type `spark-shell desktop wallpaper navy`. You get a plain color, and
it stays the same when you change the palette. Give `#rrggbb`, or one
of these names: black, white, gray (or grey), silver, navy, blue, teal,
green, olive, maroon, red, purple, brown, orange. The ground, a
picture and a color are drawn the same way: gaps around the windows,
no border, and the terminals a little transparent. The dialog's `theme`
section sets the transparency. With `none`, the windows are opaque and
touch, and a thin edge in the surface shade parts them. No window is
outlined in the accent; tabs and stacks show the focused title in the
surface shade.

## Bar

On the desktop, a bar sits at the top of the screen. The workspaces are
on the left. A workspace a layout opened carries the layout's words, so
`2 news` reads from a distance. On the right, in groups parted by a thin
line: `lan`, `wifi` and `bt`; `out` and `mic`, each with its gauge;
`due`, a reminder due; `light`, the brightness with its gauge, and `kb`,
the keyboard's layout; `bat`; the date and time; and last, spark-shell's
own sign, the prompt sign in the palette's yellow. The palette has no
block: it is picked in the dialog, where a click on any block leads.

A block appears only for hardware this machine has. No battery, no
`bat`. The kind word is muted and the name is in the text color, as
in `out jabra`. Color is for alarms: `mic` is red while any program
records, and so are `lan down` and a battery under 15. The bar never
changes width: a click never swaps a block's text.

The two gauges are the things you set in the bar itself. A click sets
the level where you clicked, the wheel nudges it by 5, and a right
click mutes. The volume keys do the same for `out`, and the mic mute
key for `mic`.

A click on any other block opens the dialog with that block first.
The sign at the end opens it as Super+d does.
The signs the bar wears are the dialog's: a dot before a connected
device, a warning sign with a red `lan down` or a low battery, a red
dot after `mic` while a program records.

Wi-Fi is set through the tool this machine has: nmcli, iwctl or
wpa_cli. Sound comes from PipeWire, which `on desktop` installs,
through wpctl: a pick of output moves the sound at once, a Bluetooth
headset included. Without PipeWire, the bar reads PulseAudio (pactl)
or plain ALSA (amixer). On plain ALSA a change of
output holds for programs started afterwards, and is written to
`~/.config/alsa/asoundrc`, spark-shell's own file. `spark-shell off`
removes it, and so does `on desktop` once PipeWire is in. Your
`~/.asoundrc` is never touched, and when it sets the
default device itself, spark-shell says so and leaves the choice to it.
A Bluetooth headset that bluez-alsa offers is listed in `out` and `mic`
beside the cards: it plays on A2DP, listens on its call link (SCO, 8
kHz), and its level and mute are bluez-alsa's own. Only one of
bluez-alsa and PipeWire can offer Bluetooth sound: `spark-shell check`
says so when both run.

Type `spark-shell bar off --desktop`. The bar is hidden. `on` brings
it back. Type `spark-shell bar`. You get the state of this bar and of
the status line in tmux; `--terminal` or `--desktop` names one. The
AI and the machine stay on the status line inside each window.

## Dialog

The dialog is one window in the middle of the screen, 60 by 40 cells,
3:4 in a 9 by 18 pixel cell: a plain surface a shade lighter than the
windows behind it, with air around its text and no frame. On a smaller
screen sway keeps the window inside it, and the dialog fits its rows to
the window, down to 36 by 20 cells.
Super+d opens it. Super+s opens it in spark chat. A click on a bar
block opens that block's section: the clock opens the Calendar. Esc
closes it, and so does the key that opened it, pressed again, and so
does a click on the x in its top right corner. A pick that opens an
app or a layout closes it: the window is the receipt. A window that is
fullscreen steps aside for the dialog and is fullscreen again when the
dialog closes with nothing opened.

The top row says where you are (`home`, a place, a section and its
state), then the date and the time as your locale writes them, and a
small march while a step runs. Under it is the prompt, two rows tall:
type a request, Enter sends it, and Shift+Enter starts a new line (Alt+Enter
where a terminal cannot tell the two apart). A longer draft scrolls
inside the two rows, and a paste keeps its lines and never sends. The
row under the prompt says what Enter and Esc do now; a key is drawn as
a key, and nothing else is.

The home lists six places: Apps, Files, Workspace (windows and
layouts), Notes, Calendar (the months and the reminders) and Settings
(sound, microphone, Wi-Fi, Bluetooth, display, keyboard, theme,
wallpaper, the bar, Talk, Connections and About). A place shows only where
this machine has it. The down arrow moves from the prompt into the
list, and up from the first row comes back. A row wears a sign where
there is a state: a dot is in use or connected, a ring is available, a
check is current or saved, a small triangle opens something. A row
that ends in a small arrow opens more. When the list is longer than
the window, its last line says how many rows sit below, and Page Up
and Page Down scroll it.

- `layout`: a saved layout opens on Enter. Words at the prompt make a
  new one. `save what is open now` asks a name for it.
- `wifi`: disconnect the network in use; connect one around, and a new
  network asks its password once, masked; forget a saved one.
- `bt`: connect or disconnect your devices, look for new ones, pair a
  new one, turn Bluetooth off and on.
- `out` and `mic`: use another device, mute and unmute.
- `theme`: the palette, the font bigger or smaller, and the windows'
  transparency.
- `wallpaper`: default, none, the 17 wallpapers with the palette each
  was drawn for, or a plain color, each with a sample of its color;
  `a picture` opens your home folder, offering pictures (jpg, jpeg,
  png, webp), and Enter on one sets it.
- Calendar: this month and the next side by side, today lit and a day
  with a reminder in the accent; the left and right arrows move the
  months while nothing is typed. Under them, the reminders.
- `notes`: a new note, then your notes, the newest first, each with its
  date. Enter opens one in your editor in a terminal window. Said in
  words, `note buy oat milk` makes a note, `groceries: buy oat milk`
  adds a line to the note named groceries, and a question finds the
  note and the line that answer it.
- `reminders`: a new reminder, then the reminders in their groups,
  due, today, tomorrow, this week and later. Enter on new reminder asks
  for when and what, as `tomorrow 9:00 call the dentist`; said in
  words, `remind me to call the dentist tomorrow at 9`. One due has
  done and again in 10 minutes. Done puts the reminder aside in
  `~/calendar/done` for 30 days, and undo brings it back.
- `window`: the windows open now, in front or closed, and how new
  windows sit on a workspace: side by side, in tabs or stacked.
- `bar`: hide the bar at the top of the screen, or show it again.
- `apps`: a terminal window, then a row per app a layout may open.
- `about`: the version, the keys, the licence and the address. It opens
  by itself the first time the desktop starts, and Esc gives the list
  back.
- `files`: your home folder. Enter on a folder opens it, `..` goes back
  up, and Esc walks back the way you came; a folder lists its folders,
  then its files with the size and the date. Enter on a file opens it
  with the app for its kind. A hidden file, a link and anything outside
  your home are never read.

Above the list, what was said and done, the newest first: a check is
a step done, a cross one refused, and an Undo row takes the last step
back while it can be. At the bottom, under a rule, the controls in plain
text: Attach, the model, and the mic at the right. Tab moves
through them and the one in focus is lit; Shift+Tab goes back.

- Attach picks one text or Markdown file from your home (the types
  `DIALOG_ATTACH_TYPES` names), for the next question only: its name
  shows under the prompt with Remove. Picking it sends nothing. It
  goes with the next words, and comes back with them if that request
  fails. A file over 16 kB, empty, or not UTF-8 text is refused with
  the reason: spark reads 16 kB of a file whole, and a longer one is
  never cut without a word. What the file says is read as text, never
  as an instruction.
- The model opens a list: where the model runs (this computer, or the
  spark server this machine is a client of), the models in use,
  installed and not downloaded. Looking changes nothing. Picking one
  says what changes and for whom (every client of that spark), and Enter
  applies it; Esc keeps the one in use. Your draft and file stay. Another
  server or a cloud provider is not available yet, and is shown as such.
- The mic shows while Settings > Talk is click the mic (off hides it).
  Clicking it listens through spark's own voice until a pause and puts
  the words in the draft at the cursor, to read and change; Enter still
  sends. Esc, a click on the mic again, or leaving the window stops it,
  and nothing is kept. Holding Space to talk waits for a newer spark.

`DIALOG_ATTACH`, `DIALOG_MODEL` and `DIALOG_TALK` hide the controls.

Type, and the list shows what matches: places, settings, and every step
the dialog can take, shown or not (`drac` finds the palette). Enter in
the prompt sends the words as a request, even when a row matches them:
the down arrow picks a row. A place's name alone, as `settings` or
`calendar`, opens it. A request goes to spark, the way `spark-shell
want --json` reads it. With spark 1.90 or newer, `spark steps` plans
with the desktop's own tools and what each section offers now; each
step is checked against the list again, drawn, then played. A question
is answered and changes nothing: the steps spark would take are listed
as proposals, run only when you pick one, and naming an app in a
question does not open it. A step that cannot be taken back, as
closing a window or forgetting a network, waits for you to type yes,
whatever its provider says of it; the yes is checked again against what
is offered then. A step that fails or gets no answer stops the steps
after it, and no answer is said as no answer, not as done.

The dialog is a terminal program: keyboard, focus and contrast are its
own, but a screen reader sees text, not controls with names.

The dialog is a program of its own, `spark-dialog`, built from
`dialog/` in this repository. `spark-shell on` installs it for the
desktop from the release of the tag this copy is on, and only when a
key in `allowed-signers` signed the tag and the file has the sha256
that `dialog/dialog.env` pins (x86_64 machines for now). It starts each
section as a provider, `spark-shell provide SECTION`, with no shell
and a short list of settings from your environment. It keeps one line
for each step it played in `~/.local/state/spark-shell/audit`: the
time, who asked, the section, the step and a short digest, never a
name or a password.

With spark 1.90 or newer, `spark-shell on desktop` also puts each of
the 15 providers on spark's MCP list, as `spark mcp add NAME
~/.spark-shell/spark-shell provide NAME`, so the prompt line and `spark
do` know the desktop's tools too. A server of yours already listed under
one of those names stays as it is. `spark-shell off desktop` and
`spark-shell off` take back only spark-shell's own lines.

For scripts and tests, `spark-shell panel SECTION --list` prints a
section's list as text, and `spark-shell panel SECTION ACTION WORDS`
runs one of its steps. Day to day, the dialog and commands such as
`spark-shell notes` are the way in.

## Providers

Every section of the dialog is a provider: `spark-shell provide wifi`
serves the section as an MCP server on stdin and stdout (the Model
Context Protocol, 2025-06-18), for the dialog and for spark itself
later. A step is a tool, as `wifi_connect`
with its title `wifi connect NAME`; the rows are the resource
`spark-shell://wifi/rows`, and a host that subscribes is told when they
change. A tool runs only a step the section offers now, with a row's
own argument, checked as the dialog checks a pick. A tool that cannot be
taken back says so, and a result carries the step that takes it back
when there is one. A password is the tool's own argument: it is never
written down. `spark-shell want --json "WORDS"` prints the steps spark
picks for the words as JSON, each checked the same way, and runs none.
`spark-shell want --attach FILE "WORDS"` asks spark about a text file:
the file's text goes to spark as someone else's text, by its name
alone.

## Status and check

Type `spark-shell status`. You get one row per part, and a last `next`
row when something is left to do. Type `spark-shell check`. You get ok,
warn or FAIL per part, and exit 0 when nothing fails.

## Software list (sbom)

Type `spark-shell sbom`. You get every installed package: version,
licence, description, and whether you chose it. `sbom apps`, `sbom
tools` or `sbom parts` shows one kind. `sbom --json` writes the list to
`~/.local/state/spark-shell/sbom.cdx.json` (CycloneDX 1.5).

## Reference

Config keys, in `~/.config/spark-shell/config` (see `config.example`):
`PROMPT` (starship or plain), `PROMPT_STYLE` (minimal or full),
`DESKTOP` (none or sway), `FONT` (foot's font), `WALLPAPER` (default,
none or a path), `ALPHA` (how solid foot is, 0.85: 15% transparency),
`DESKTOP_BAR` (yes or no), `THEME`, `CONSOLE_FONT`, `QUIET_LOGIN`, `QUIET_BOOT`,
`DIALOG_ATTACH` (yes or no), `DIALOG_ATTACH_TYPES` (txt md),
`DIALOG_MODEL` and `DIALOG_TALK` (yes or no), `DISPLAY_IDLE` and
`DISPLAY_LOCK` (minutes, 0 never), `KEYBOARD` (layouts). The commands
write them.

Files it writes: the shell files, `~/.tmux.conf`, `~/.config/btop/`,
`~/.config/starship.toml`, `~/.config/spark-shell/`,
`~/.config/spark/theme.env`, `~/.local/state/spark-shell/`,
`~/.local/bin/spark-shell`, and for the desktop `~/.config/sway/`,
`~/.config/foot/` and, after a change of output on plain ALSA,
`~/.config/alsa/asoundrc`, and `~/.config/spark-shell/screens.conf`. As
root: the console colors at boot (a systemd unit or a line in
`/etc/rc.local`), the console font, the login notice and boot files for
quiet, and on Void PipeWire's two links in `/etc/alsa/conf.d` and your
place in the `audio` group, and your place in `video` and `i2c` for the
brightness. `off` restores or removes each one.

What leaves the machine: only what the package manager downloads and,
for the desktop, the dialog's release file from GitHub, checked against
the sha256 the signed tree pins. A
layout asks spark, which runs on this machine, with your words, the
screen sizes and the app list; a want at the dialog asks it with your
words, what the bar shows, the list of what it can do (an open window
by its name among it) and the names of your saved layouts. A file only
when you attach one, its text and its name, never its path.
A new Wi-Fi network is saved by the Wi-Fi tool itself.

The settings live in `~/.config/spark-shell/config`, and every run
reads that file. A setting in the environment never stands in for it.

The logo, in `assets/`: spark's block-letter S, then the prompt sign and
a cursor cell. `logo.svg` is for a dark ground and `logo-light.svg` for
a light one; `favicon.svg` and `favicon-light.svg` are the same with no
ground of their own, and `favicon-16.png` to `favicon-26.png`, with
their `-light` twins, are those at the height of a terminal row. The
dialog draws the logo as a pixel grid snapped from `favicon.svg`, a
block 2 by 3 pixels and a shadow line 1, at a whole multiple of its 18
rows.
The S keeps spark's colors and is never recolored.

Uninstall: `spark-shell off`, then delete `~/.spark-shell`.

## Contributing

    git config core.hooksPath .githooks
    sh tests/shell_test.sh

The suite runs in a throwaway HOME. It checks the docs and help too:

- Plain English: short sentences, common words, no made-up terms.
- ASCII only, at most 80 columns, no contractions.
- Capitals only for acronyms and placeholders (`NAME`, `PATH`).

MIT licence (LICENSE). Credits in CREDITS.md. Built with Claude.
