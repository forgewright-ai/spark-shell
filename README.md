# spark-shell

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
choose. Apps your words name are always opened. Other apps spark picks
are only suggested. If your words name no app, spark's picks are opened.
On the desktop, `Super+d` opens the panel with your layouts first, and
the words go at its prompt.

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
    Super+d opens the panel with your layouts first: say what you want to do.
    Super+s opens spark chat in a small window, and Ctrl-D closes it.
    Super+p opens the panel: pick a row, or say what you want.
    Super+Shift+q closes the window.
    Super+Shift+c reloads sway after spark-shell on.
    Super+Shift+e leaves the desktop.
    Super+h, j, k, l or an arrow moves the focus. Shift moves the window.
    Super+f makes a window fill the screen, and Super+r resizes until Enter.
    Super+1 to 0 go to a workspace. Add Shift to send the window there.
    The volume and mute keys set the sound, and the mic mute key the mic.
    Typing exit in the first window also leaves the desktop.

## Wallpaper

Type `spark-shell desktop wallpaper /path/to/picture.jpg`. You get that
picture behind the windows. A path from where you are, or one that
starts with `~`, works too. `default` gives the wallpaper that comes
with spark-shell. `none` gives the palette's background colour.

Type `spark-shell desktop wallpaper navy`. You get a plain colour, and
it stays the same when you change the palette. Give `#rrggbb`, or one
of these names: black, white, gray, grey, silver, navy, blue, teal,
green, olive, maroon, red, purple, brown, orange.

## Bar

On the desktop, a bar sits at the top of the screen. The workspaces
are on the left. A workspace a layout opened carries the layout's
words, so `2 news` reads from a distance. On the right, in groups
parted by a thin line: `lan`, `wifi` and `bt`; `out` and `mic`, each
with its gauge; `bat`; the date and time; and `look`, the palette's
name.

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

The panel is one small window, the same size and place every time, in
the middle of the screen, in the palette's colours. Super+p opens it.
Super+d opens it with your layouts first. A click on a bar block opens
it with that block first. Esc, or a click anywhere else, closes it.

The first line says what opened it: the network, its strength as
bars and the address; the saved layouts and the last one; or the
whole bar after Super+p. Then one list of everything this machine can
do right now, in sections: `layout`, the bar's blocks in the bar's
order, `apps`. The section you came from is on top. Every row names
its section and what Enter does, as in `wifi  connect cafe`, `out
use HDMI` or `look  dracula`, with a sign in front where there is a
state: a dot is in use or connected, a ring is available, a check is
current or saved, a small triangle opens something. `lan`, `bat` and
the clock have nothing to set: a click on one shows the address,
speed and gateway; the charge, the time left and the health; this
month.

- `layout`: a saved layout opens on Enter. Words at the prompt make a
  new one.
- `wifi`: disconnect the network in use; connect one around, strongest
  first, and a new network asks its password once; forget a saved one.
- `bt`: connect or disconnect your devices, look for new ones, pair a
  new one, turn Bluetooth off and on.
- `out` and `mic`: use another device, mute and unmute.
- `look`: a palette, the font bigger or smaller, a wallpaper, alpha. A
  pick applies now. New windows take a font change.
- `apps`: the allowed apps, in the same window.

Under the list, the question: what do you want? Type and the list
narrows across every section: `drac` finds the palette from a click
on `wifi`. Words that match no row are what you want: `mute everything
and dracula, I need some quiet`, `movie night`, `call mom on the
headset`, `warmer and bigger`. spark turns them into steps from that
same list, and nothing else: mute `out` and `mic`, the palette; the
HDMI output, a dark palette and a layout with mpv; connect the headset
and move the sound to it. spark-shell checks every step against the
list, plays it and says what it did, one line each. A layout step
opens its windows, and the panel follows them. The same words work
from a shell: `spark-shell panel "mute everything"`.

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
words, the list of what the bar can do and the names of your saved
layouts. Never a window title or a file. A new Wi-Fi network is saved
by the Wi-Fi tool itself.

Uninstall: `spark-shell off`, then delete `~/.spark-shell`.

## Contributing

    git config core.hooksPath .githooks
    sh tests/shell_test.sh

The suite runs in a throwaway HOME. It checks the docs and help too:

- Plain English: short sentences, common words, no made-up terms.
- ASCII only, at most 80 columns, no contractions.
- Capitals only for acronyms and placeholders (`NAME`, `PATH`).

MIT licence (LICENSE). Credits in CREDITS.md. Built with Claude.
