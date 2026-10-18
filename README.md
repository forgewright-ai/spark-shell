# spark-shell

<picture>
<source media="(prefers-color-scheme: dark)" srcset="assets/logo.svg">
<img src="assets/logo-light.svg" alt="spark-shell" width="150">
</picture>

spark-shell sets up the terminal on a Linux machine or a Mac: tmux, a
prompt, a few everyday tools and one colour palette. On Linux it can
also add a simple desktop, and spark, the local AI, can open the apps
for a task you describe.

## Before you install

spark-shell changes your machine. `spark-shell on` replaces your shell
files and your tmux, starship and btop settings (yours are saved as
`.bak` files). It installs packages (sudo) and sets the console colours,
also at boot. On a Mac it sets a Terminal.app profile instead.
`spark-shell on desktop` makes a login on tty1 start the desktop.
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
    spark-shell off                   undo it all (packages stay installed)
    spark-shell on --dry-run          show what on would change, change nothing
    spark-shell on --yes              do not ask first
    spark-shell status                show what is set up
    spark-shell check                 test the setup (exit 0 when all is ok)
    spark-shell theme NAME|none       set the colours, or use the terminal's own
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
    spark-shell desktop               start the desktop now (from a console)
    spark-shell desktop keys          list the desktop's keys
    spark-shell desktop wallpaper X   set a picture, a colour, default or none
    spark-shell bar on|off            show or hide the status line and the bar
    spark-shell bar on|off --desktop  the bar alone (--terminal: the line alone)
    spark-shell sbom [NAME]           list the installed software, or one
    spark-shell sbom --json           write the list as a CycloneDX 1.5 file

## Terminal setup

Type `spark-shell on`. You get tmux, starship, fzf, zoxide, eza, bat,
btop, fd and jq, and shell files that use them. Debian has no starship
package, so there the prompt is the shell's own. Your own settings go
in `~/.config/spark-shell/rc`, which spark-shell reads last and never
writes.

## Colours (theme)

Type `spark-shell theme gruvbox-dark`. You get one palette in tmux, the
prompt, btop, the desktop and the Linux console, also at boot. On a Mac
it is a Terminal.app profile named `spark-shell`. `theme list` shows
the 9 palettes, and your own go in `~/.config/spark-shell/themes/`.
On Linux the terminals you have open change colour at once. A program
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
tiles windows) and foot (a terminal), in your palette. Debian, Arch and
Void only. On Void it also turns on the seatd service and adds you to
the `_seatd` group (sudo).

## Login

The login screen is the normal console login on every Linux. Log in on
tty1 and the desktop starts. Leave the desktop and you are logged out.
Alt+F2 gives a plain shell with no desktop. ssh never starts it.

## Layouts

Type `spark-shell layout "read the news and play music"`. spark picks
apps for that task and opens them: as sway windows on the desktop, or
as tmux windows anywhere else. Add `--desktop` or `--terminal` to
choose. Every window spark proposes is tied to words of yours, quoted
back, and spark-shell checks the quote: `notes and firefox` opens
Firefox for `firefox` and the editor for `notes`. A window spark can
tie to none of your words is padding; it does not open, and is one
Enter away in the panel, as `layout  also open btop`. Apps your words
name are always opened, each once. Say `fullscreen` and the main
window fills the screen alone. Say `workspace 3` and the layout opens
there.
On the desktop, `Super+d` opens the panel, and the words go at its
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

Type `spark-shell desktop keys`. You get these lines. The first window
of the desktop shows them once.

    Super+Return opens a terminal window.
    Super+d opens the panel: pick an option, or say what you would like.
    Super+s opens spark chat in the panel's window, and Ctrl-D closes it.
    Super+Shift+q closes the window.
    Super+Shift+c reloads sway after spark-shell on.
    Super+Shift+e leaves the desktop.
    Super+h, j, k, l or an arrow moves the focus. Shift moves the window.
    Super+f makes a window fill the screen, and Super+r resizes until Enter.
    Super+w makes tabs, Super+Shift+s a stack, Super+e side by side again.
    Super+b and Super+v put the next window beside this one, or below it.
    Super+1 to 0 go to a workspace. Add Shift to send the window there.
    The volume and mute keys set the sound, and the mic mute key the mic.
    Typing exit in the first window also leaves the desktop.

## Wallpaper

By default there is no picture. Behind the windows is the ground: the
palette's background a shade darker than the windows, so the
see-through terminals sit on something quieter than themselves. It
follows the palette. Type `spark-shell desktop wallpaper
/path/to/picture.jpg` for a picture of yours. A path from where you
are, or one that starts with `~`, works too. `default` is the ground
again. `none` fills the screen with the windows, solid, in the
palette's background colour.

Type `spark-shell desktop wallpaper navy`. You get a plain colour, and
it stays the same when you change the palette. Give `#rrggbb`, or one
of these names: black, white, gray, grey, silver, navy, blue, teal,
green, olive, maroon, red, purple, brown, orange. The ground, a
picture and a colour are drawn the same way: gaps around the windows,
and the terminals a little see-through. The panel's `theme` section
sets how much.

## Bar

On the desktop, a bar sits at the top of the screen. The workspaces
are on the left. A workspace a layout opened carries the layout's
words, so `2 news` reads from a distance. On the right, in groups
parted by a thin line: `lan`, `wifi` and `bt`; `out` and `mic`, each
with its gauge; `bat`; the date and time; and last, spark-shell's own
sign, the prompt sign in the palette's yellow. The palette has no
block: it is picked in the panel, where a click on any block leads.

A block appears only for hardware this machine has. No battery, no
`bat`. The kind word is muted and the name is in the text colour, as
in `out jabra`. Colour is for alarms: `mic` is red while any program
records, and so are `lan down` and a battery under 15. The bar never
changes width: a click never swaps a block's text.

The two gauges are the things you set in the bar itself. A click sets
the level where you clicked, the wheel nudges it by 5, and a right
click mutes. The volume keys do the same for `out`, and the mic mute
key for `mic`.

A click on any other block opens the panel with that block first.
The sign at the end opens it as Super+d does.
The signs the bar wears are the panel's: a dot before a connected
device, a warning sign with a red `lan down` or a low battery, a red
dot after `mic` while a program records.

Wi-Fi is set through the tool this machine has: nmcli, iwctl or
wpa_cli. Sound comes from the audio system you have: PipeWire (wpctl),
PulseAudio (pactl), or plain ALSA (amixer). On plain ALSA a change of
output holds for programs started afterwards, and is written to
`~/.config/alsa/asoundrc`, spark-shell's own file. `spark-shell off`
removes it. Your `~/.asoundrc` is never touched.

Type `spark-shell bar off --desktop`. The bar is hidden. `on` brings
it back. Type `spark-shell bar`. You get the state of this bar and of
the status line in tmux; `--terminal` or `--desktop` names one. The
AI and the machine stay on the status line inside each window.

## Panel

The panel is one window, the same size and place every time, in the
middle of the screen: a plain surface a shade lighter than the
windows behind it, with air around its text and no frame. Super+d
opens it. Super+s opens it already in spark chat, on the same
surface. A click on a bar block opens it with that block first. Esc
closes it, and so does the key that opened it, pressed again. It
stays while the mouse moves. A pick that opens an app or a layout
closes it: the window is the receipt. A window that is fullscreen
steps aside for the panel and is fullscreen again when the panel
closes with nothing opened.

The first lines are the same behind every door: the date, the time
large in strokes two cells wide, this month beside it with today a
chip in the accent, and an alarm in red under them when there is
one. The facts are on the bar. The time keeps the minute while the
panel is open. Then one list of everything this machine can do right
now, in sections ordered by use: `spark`, `layout`, `out`, `mic`,
`theme`, `window`, `bar`, `bt`, `apps`, `wifi`. The section you came
from is on top. Every row names its section in a column of its own,
muted, then the thing, with a sign in front where there is a
state: a dot is in use or connected, a ring is available, a check is
current or saved, a small triangle opens something. The picked row is
lit across the window. The sign says
what Enter does: a ring before a network connects it, a dot before
it disconnects, a ring before an output switches to it. Where there
is no thing to point at, the row says the verb: `forget cafe`,
`mute`, `font bigger`. A long section shows what matters and one row
that opens the rest: `wifi` the network in use, the saved ones and
the strongest three, then `12 more`; `theme` the palettes and the
font, then `wallpaper and alpha`. `lan` and `bat` have nothing to
set: a click on one shows the address, speed and gateway; the charge,
the time left and the health. A click on the clock opens the panel as
Super+d does.

The window draws at once from what costs nothing to know. The Wi-Fi
scan and the Bluetooth list take a moment, so they keep their last
answer, for a minute and for half a minute, and fill the list in
place while a small march in the top right corner of the window says
the panel is looking. A pick, a want or a layout shows its pulse in
the same corner, with the seconds from two, and each line of what was
done as it lands under the clock. A check is a step done, a cross one
refused. The window keeps two fixed places: that corner, and the
bottom, where the hint and the prompt are.

- `undo`: one row, there while the last thing done can be taken back,
  as `undo  theme everforest-dark, out unmute`. Enter puts it back.
  The panel reads the state before each step, so the undo is exact.
- The rows you picked most recently come next, in that order, while
  they can still be picked.
- `spark`: one row, `chat`. Enter opens spark chat in this window,
  and Ctrl-D brings the desktop back. The newest conversation goes on.
- `layout`: a saved layout opens on Enter. Words at the prompt make a
  new one. `save what is open now` turns the windows on this
  workspace into a layout, under a name you type.
- `wifi`: disconnect the network in use; connect one around, strongest
  first, and a new network asks its password once; forget a saved one.
- `bt`: connect or disconnect your devices, look for new ones, pair a
  new one, turn Bluetooth off and on.
- `out` and `mic`: use another device, mute and unmute.
- `theme`: one row in the list, the palette and the font size. Enter
  opens the section: a palette, the font bigger or smaller, a
  wallpaper, and how see-through the windows are, more or less. A pick
  applies now, the panel included. New windows take a font change.
- `window`: how new windows sit on a workspace, side by side, in tabs
  or stacked. A pick sets this workspace now and is remembered for new
  ones, reboots included.
- `bar`: hide the bar at the top of the screen, or show it again.
  Super+d opens the panel either way. Remembered too.
- `apps`: a terminal window, then a row per app a layout may open, and
  Enter opens it on this workspace, the way its desktop entry says.
  The last row chooses the allowed apps, in the same window.

Under the list, one line: pick an option, or say what you would like.
The list shows each section's state and everyday steps. Type, and the
search runs over everything the panel can do, shown or not: `drac`
finds the palette from a click on `wifi`. One or two words that name an app
this machine declares, as `Firefox`, open it at once. More words that
name one, as `Firefox and the notes`, open a layout for the task.
Other words that match no row go to spark.
A change is played: `mute everything and dracula, I need some quiet`,
`Firefox fullscreen`, `movie night`, `call mom on the headset` become
steps from that same list, and nothing else: mute `out` and `mic`,
the palette; a layout with Firefox; the HDMI output, a dark palette
and a layout with mpv; connect the headset and move the sound to it.
spark-shell checks every step against the list, plays it and says
what it did, one short line each. A layout step opens its windows,
and the panel closes. A question is answered in the same place, in
a sentence or two: `what is my address`. Words that are no
question and match no step are a task, and a layout opens for them.
The same words work from a shell: `spark-shell panel "mute
everything"`.

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
none or a path), `ALPHA` (how see-through foot is, 0.85), `DESKTOP_BAR`
(yes or no), `THEME`, `CONSOLE_FONT`, `QUIET_LOGIN`, `QUIET_BOOT`. The
commands write them.

Files it writes: the shell files, `~/.tmux.conf`, `~/.config/btop/`,
`~/.config/starship.toml`, `~/.config/spark-shell/`,
`~/.config/spark/theme.env`, `~/.local/state/spark-shell/`,
`~/.local/bin/spark-shell`, and for the desktop `~/.config/sway/`,
`~/.config/foot/` and, after a change of output on plain ALSA,
`~/.config/alsa/asoundrc`. As root: the console colours at boot (a systemd
unit or a line in `/etc/rc.local`), the console font, and the login
notice and boot files for quiet. `off` restores or removes each one.

What leaves the machine: only what the package manager downloads. A
layout asks spark, which runs on this machine, with your words, the
screen sizes and the app list; a want at the panel asks it with your
words, what the bar shows, the list of what it can do and the names of
your saved layouts. Never a window title or a file. A new Wi-Fi network is saved
by the Wi-Fi tool itself.

The settings live in `~/.config/spark-shell/config`, and every run
reads that file. A setting in the environment never stands in for it.

The logo, in `assets/`: spark's block-letter S, then the prompt sign and
a cursor cell. `logo.svg` is for a dark ground and `logo-light.svg` for
a light one; `favicon.svg` and `favicon-light.svg` carry their ground.
The S keeps spark's colours and is never recoloured.

Uninstall: `spark-shell off`, then delete `~/.spark-shell`.

## Contributing

    git config core.hooksPath .githooks
    sh tests/shell_test.sh

The suite runs in a throwaway HOME. It checks the docs and help too:

- Plain English: short sentences, common words, no made-up terms.
- ASCII only, at most 80 columns, no contractions.
- Capitals only for acronyms and placeholders (`NAME`, `PATH`).

MIT licence (LICENSE). Credits in CREDITS.md. Built with Claude.
