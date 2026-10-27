# spark-shell

<picture>
<source media="(prefers-color-scheme: dark)" srcset="assets/logo.svg">
<img src="assets/logo-light.svg" alt="spark-shell" width="150">
</picture>

spark-shell sets up your terminal on Debian, Ubuntu, Arch, Void,
Fedora, openSUSE or macOS, and on Windows inside Ubuntu under WSL 2.
It adds tmux, a prompt, everyday tools and a color theme. On Linux, it
can also set up a sway desktop and an optional login screen. With
[spark](https://github.com/forgewright-ai/spark), the local AI, you can
ask it to open apps for a task. The terminal, desktop, notes and
reminders also work without spark. [Where it runs](#where-it-runs)
says what each system gets.

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

To update, run `spark-shell update`: the clone moves to the newest
release signed by a key in its `allowed-signers`, never to a commit
nobody signed, and `on` runs again from it.
spark is optional.
Without it, layouts and spark chat are unavailable. The tmux
status line still shows the machine and your reminders.

## Where it runs

| system                   | terminal | desktop              | login screen    |
| ------------------------ | -------- | -------------------- | --------------- |
| Debian 13                | yes      | yes                  | yes             |
| Ubuntu 24.04 or newer    | yes      | yes, proven headless | yes, not proven |
| Arch                     | yes      | yes                  | yes             |
| Void (glibc)             | yes      | yes                  | yes             |
| Fedora                   | yes      | yes, proven headless | yes, not proven |
| openSUSE Tumbleweed      | yes      | yes, proven headless | yes, not proven |
| macOS                    | yes      | no, its own          | no, its own     |
| Windows, Ubuntu on WSL 2 | yes      | no                   | no              |

The terminal is `spark-shell on`: the tools, the prompt, the colors.
The desktop is `spark-shell on desktop`, sway and foot in your palette,
and the login screen `spark-shell on login`, greetd on tty1. Each
family has a file of package names in `distro/`, and CI looks every
name up on that family and installs the desktop's in a container of
it, where `spark-shell on` renders the settings and a headless sway
runs them. "Proven headless" means that and no more: a screen, a
keyboard and sound are a machine's proof, and Debian, Arch and Void
have had theirs. On WSL 2 there is no console and no tty1, so `on
desktop` and `on login` say so in one line, the console font, palette
and quiet steps skip, and Windows Terminal draws the terminal. Fedora
and openSUSE boot quiet already, and spark-shell does not edit their
GRUB 2 entries, so `quiet boot on` says so there.

## First task

After setup, run `spark-shell check`. It lists any part that needs
attention. Then add a note:

    spark-shell notes add groceries: buy oat milk
    spark-shell notes

The second command lists your notes. `spark-shell notes groceries`
opens the note in your editor. Notes work without spark or the desktop.
See [Notes and reminders](#notes-and-reminders) for where they are kept.

For a desktop, read [Desktop](#desktop). On Linux, run
`spark-shell on desktop`. It asks before making changes. You can see
them first with `spark-shell on desktop --dry-run`.

## Help

Run `spark-shell -h` for commands, or `spark-shell status` to see what
is set up. [Commands](#commands) is the short list; the sections below
explain each part. If something fails, run `spark-shell check` and
[report the problem](https://github.com/forgewright-ai/spark-shell/issues).

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
    spark-shell update                move to the newest signed release, then on
    spark-shell theme NAME|none       set the colors and the look, or none
    spark-shell theme [list]          show the look in use, or list them all
    spark-shell theme save [NAME]     keep the look in use as a saved theme
    spark-shell theme delete NAME     delete a saved theme
    spark-shell theme back            the look before this one, again
    spark-shell theme wallpaper X     a drawing, a picture, a color or default
    spark-shell theme text N          the text size everywhere; bigger, smaller
    spark-shell theme transparency N  the windows' transparency; more, less
    spark-shell theme picture PATH    a theme from a picture of yours
    spark-shell theme "WORDS"         a theme from words, read by spark
    spark-shell font FACE SIZE|none   set the console font, or use its own
    spark-shell font list             list the fonts you can use
    spark-shell quiet login on|off    hide the notice before the login (Linux)
    spark-shell quiet boot on|off     hide the boot menu and messages (Linux)
    spark-shell quiet                 show both settings
    spark-shell layout "WORDS"        open apps for that task, picked by spark
    spark-shell layout save [NAME]    save the last layout
    spark-shell layout [NAME]         list the saved layouts, or open one
    spark-shell layout delete NAME    delete a saved layout
    spark-shell layout rename NAME NEW
                                      give a saved layout a new name
    spark-shell layout back           the layout before this one, again
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
    spark-shell desktop lock          lock the screen now (Super+Escape)
    spark-shell desktop idle [off]    the idle screen now, or down
    spark-shell desktop capture screen|area|window
                                      a PNG in ~/pictures/screenshots (Print)
    spark-shell desktop display       the idle and lock minutes, the brightness
    spark-shell desktop display idle|lock N
                                      idle screen or lock after N idle minutes
    spark-shell desktop display saver [NAME]
                                      list the idle screen's savers, or pick one
    spark-shell desktop display brightness N|up|down
                                      the screen's brightness, 1 to 100
    spark-shell desktop keyboard [us br|next]
                                      the keyboard's layouts, or the next one
    spark-shell desktop keyboard repeat-delay N|repeat-rate N|caps KEY
                                     key repeat and caps, control or escape
    spark-shell desktop pointer [tap on|off|scroll on|off|speed N]
                                     tap to click, natural scroll and speed
    spark-shell desktop screen [NAME scale N|mode WxH|on|off|left-of NAME]
                                      list the screens, or set one
    spark-shell desktop notifications [do-not-disturb on|off|dismiss|restore]
                                      do not disturb, and the last few
    spark-shell desktop storage [mount|unmount|open|eject NAME]
                                      the drives plugged in, the free space
    spark-shell desktop power [lock|suspend|logout|restart|shutdown]
                                      lock, log out, suspend, restart, shut down
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
btop, fd and jq, and shell files that use them. Debian, Ubuntu and
Fedora have no starship package, so there the prompt is the shell's
own. Your own settings go in `~/.config/spark-shell/rc`, which
spark-shell reads last and never writes.

## Colors (theme)

The desktop shares a native dark or light preference with apps that follow
it. The palette does not replace an app's own theme. Native desktop portals
provide file pickers and screen sharing under sway. `off desktop` restores
the previous preference if no other program has changed it.

Type `spark-shell theme gruvbox-dark`. You get one palette in tmux, the
prompt, btop, the desktop and the Linux console, also at boot. On a Mac
it is a Terminal.app profile named `spark-shell`. `theme list` shows
the 16 palettes, eight dark and eight light, and your own go in
`~/.config/spark-shell/themes/`.
On Linux the terminals you have open change color at once. On the
desktop a theme change is one moment: the terminals, the dialog, the
bar, the window edges, the pointer and the wallpaper change together,
nothing reloads, and the new wallpaper is drawn over the old before the
old one goes, so the screen never goes dark. The prompt and spark's
line draw their accent in a slot of the terminal that the change sets,
so text already on the screen changes too: no `exec $SHELL`, no
`clear`. A program that is already running, such as btop, changes when
it starts again.

On the desktop a theme is the whole look, and one choice brings the
rest: the palette brings the wallpaper drawn for it (`theme nord` puts
fjord behind the windows, over a drawing, a color or the ground; only
a picture of your own stays), the pointer in white or black, and the
login, the lock and the idle screen in its colors. `theme wallpaper
skyline` picks a drawing for the palette in use, drawn again in that
palette's colors. `theme text 14` is the one text size, on foot, the
bar, the dialog, the login, the lock and the idle screen; the pointer
grows with it (24, 32 or 48 pixels). `theme transparency 15` is the
windows' transparency, 0 to 50; the open windows take it at once.

`theme save winter` keeps the look in use as a theme: a folder
`~/.config/spark-shell/themes/winter/` with the palette, the
wallpaper's files, the text size, the transparency and the pointer. It
copies to another machine, and a folder from elsewhere is read the way
the config is: each value is held to its shape, and a folder with one
that is not is refused in a line that names it, with nothing changed.
The themes folder is yours alone (0700). `theme winter` brings it
back, `theme list` shows the saved themes, `theme delete winter`
removes one. The last ten
looks you chose are kept, with the time: `theme back` steps through
them. Layouts are kept the same way, so `layout back` opens the one
before.

`theme picture ~/pictures/beach.jpg` makes a theme from a picture of
yours: its colors become the palette, with the text at 7 to 1 on the
background and every other color at 3 to 1, dark or light as the
picture is, and the picture is the wallpaper. `theme "warm dark
winter"` asks spark for five words and a name, the hue of the ground,
the hue of the accent, how warm, how much contrast, dark or light, and
makes the palette from them; a flag or a brand is one look with two
hues, never two. The drawing you have is drawn again in it. Both apply
at once and sit in the last ten under the picture's or the words' name
until you save them. `theme none` leaves the terminal its own colors:
foot's own sixteen on the desktop, the console's own at the console.

## Font

The terminal's font is Monaspace Neon, by GitHub Next, the same type as
spark's page. `spark-shell on` installs it for foot on the desktop and
for Terminal.app on a Mac: from the distro's package where there is one
(Arch), else the release file from GitHub, installed only when its
sha256 is the one spark-shell pins. Without a network nothing is
installed, and the terminal keeps DejaVu Sans Mono (Menlo on a Mac)
until the next `spark-shell on`. A font you chose in `FONT` or
`CONSOLE_FONT` stays yours. DejaVu Sans Mono and Menlo-Regular, the
defaults before, move to Monaspace Neon once, at the same size. foot
draws the lines, blocks and braille of tmux and btop itself, and takes
a glyph the font lacks from DejaVu Sans Mono.

Type `spark-shell font Terminus 16x32`. You get that console font, now
and at every boot (sudo). The Linux console takes only such a bitmap
font. On a Mac it sets the Terminal.app font instead: `spark-shell font
Monaco 14`.

## Quiet

Type `spark-shell quiet login on`. You get only the login prompt, with
no notice before it. Type `spark-shell quiet boot on`. You get a boot
with no menu and no kernel messages (hold Shift or Space for the menu).
It edits boot files, so it asks first. Linux only. Fedora and openSUSE
boot quiet already, and spark-shell does not edit their GRUB 2 entries:
`quiet boot on` says so there.

## Desktop

Type `spark-shell on desktop`. You get sway (a window manager that
tiles windows) and foot (a terminal), in your palette, and the sound:
PipeWire with WirePlumber, for every program and Bluetooth too. Linux
only, every family in [Where it runs](#where-it-runs). Where systemd
runs, PipeWire's own user services run it from login. On Void it runs
from boot, desktop or not, so a
console login has sound too: a service of yours under spark's
supervisor, `~/.config/spark/sv/spark-shell-sound`. PipeWire starts
WirePlumber and its PulseAudio server itself, from two links in
`~/.config/pipewire/pipewire.conf.d`. If the desktop already runs its
own PipeWire when the service comes, that one keeps running until you
leave the desktop, and then the service takes over. Without spark,
PipeWire starts with the desktop and stops when you leave it.
`on desktop` also turns on the seatd service, adds you to the `_seatd`
and `audio` groups, and links PipeWire's two ALSA files into
`/etc/alsa/conf.d`, so ALSA programs play through it (sudo). The
notifications, the drives and the power come with it: mako, notify-send
and udisks2, and on Void two rules (sudo), one that lets you mount and
eject a USB drive and one that lets you suspend, restart and shut down
([Notifications, drives and power](#notifications-drives-and-power)).
`spark-shell check` says where PipeWire runs from: boot, login or the
desktop. `off desktop` stops the service and removes it, with the links.

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
(sudo; on Fedora, dnf brings greetd's SELinux policy with it). tty2
keeps the
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
choose. spark-shell checks each proposed window against your words
before opening it. For `notes and firefox`, it opens
your editor and Firefox. An unmatched suggestion stays closed; the
dialog offers it as `layout  also open btop`; press Enter to open it.
Each app you name opens once. Say `fullscreen` and the main
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
desktop start shows the keys in the about dialog, one line each, and
the dialog's `about` row shows them again.

    Super+Return opens a terminal window.
    Super+d opens the dialog: a place to go, or say what you would like.
    Super+s opens the dialog in spark chat, and Ctrl-D closes it.
    Super+Shift+q closes the window.
    Super+Shift+c reloads sway after spark-shell on.
    Super+Shift+e leaves the desktop.
    Super+arrow moves the focus, as h, j, k, l do; Shift moves the window.
    Super+f makes a window fill the screen.
    Super+r resizes the window, until Enter.
    The mouse resizes too: drag the strip between two windows.
    Super+right-drag resizes a window by its corner, Super+left-drag moves it.
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
brightness. `display idle 10` brings the idle screen after 10 idle
minutes, `display lock 15` locks the screen and turns the display off
after 15, and 0 means never; a running desktop takes the change at
once. `display saver NAME` picks what the idle screen shows behind its
clock (Lock and capture says what). `display
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

A note is a Markdown file in `~/notes`. Its first line is its name.
The folder is yours alone (0700), and so is each note spark-shell
writes (0600).
You can edit or sync it with other tools. [First task](#first-task)
shows how to add one. A reminder is an iCalendar event with an alarm.
Each has an `.ics` file in `~/calendar`. khal and calendar apps on a
Mac or phone can read them, including through CalDAV sync. Apple's
Reminders no longer accepts to-dos over CalDAV, so spark-shell uses
events.

Reminders work in a terminal, on the desktop and on a Mac:

    spark-shell reminders add tomorrow 9:00 call the dentist
    spark-shell reminders

The day can be today, tomorrow, a weekday (fri or friday) or a date
(2026-11-03); the time is 18:30, 9am or 6:30pm; the rest is the words.
A note opens in your editor right in the terminal you typed in, and in
a terminal window from the dialog. A new note you leave empty is not
kept.

When a reminder comes due, the bar shows a `due` block with its words,
a click opens the reminders, and a short sound plays once (PipeWire,
else ALSA; afplay on a Mac). On the desktop it comes as a notification
too, once, and a click on it opens the reminders in the dialog. The
tmux status line shows it too, in the accent, so a terminal outside the
desktop and a Mac hear and see it.
Both lines check the time every 15 seconds, so nothing more runs for
it. Done takes the reminder away; again in 10 minutes moves it on.

## Lock and capture

After the idle minutes (10) the idle screen: the wallpaper dims to the
ground and the time sits at the lower left in large figures, in the
accent, as the Calendar draws it, the date under it; a key or a mouse
move takes it down, and so does Ctrl-C, whether it came by itself or by
`spark-shell desktop idle`. However it goes, the workspace you were on
and the bar come back.

Type `spark-shell desktop display saver spark`. You get an animation
behind the clock on the idle screen, in your palette: spark (bursts and
rising embers), starfield, or drift (the clock bounces). `desktop
display saver` lists them with the one in use ticked, and `saver clock`
brings back the clock alone, which is what you have until you pick one.
The clock, its place, the date and the way out do not change, and
`spark-shell desktop idle` shows the screen now. A saver needs python3:
without it, or if the saver fails, the idle screen shows the clock. It
comes in over its first second or two, with the clock whole from the
start, writes only the cells that change, ten times a second, and goes
when the lock comes: nothing runs behind the lock or a dark screen. The
dialog's display section has a row for it. The savers are
`lib/saver.py`, and `python3 lib/saver.py NAME` plays one in any
terminal; `--ascii` keeps it to plain characters.

After the lock minutes (15) the screen locks and the display turns off.
Where logind runs (every family but Void), it locks before the machine
sleeps too; Void has no logind to say so. Super+Escape, or `spark-shell
desktop lock`, locks it now; `spark-shell desktop idle` shows the idle
screen now. The lock is swaylock over your wallpaper, in the palette:
at rest the picture alone, and a ring comes up with the first key you
type. With more than one keyboard layout, the one in use shows under
the ring, in the ring's own colors.

Print takes a picture of the screen, Shift+Print of an area you drag,
and Super+Print of the window in front; `spark-shell desktop capture
screen|area|window` does the same, and the dialog's `window` section
has the screen and an area. Each picture is a PNG named by the time in
`~/pictures/screenshots`, and it is on the clipboard too (grim, slurp
and wl-clipboard).

## Notifications, drives and power

A notification comes in the top right corner, under the bar, in your
palette and text face: the app's name muted, what it says in bold, the
words under it. The newest is on top, three at most, and each goes
after eight seconds into the history, which keeps the last ten. A
critical one stays until you dismiss it and has a red edge. A click
does what its app offers; a right click dismisses it. mako draws them,
from `~/.config/mako/config`, and a new look reaches the next one at
once. Type `spark-shell desktop notifications do-not-disturb on`. They
stay out of sight, a critical one still shows, the bar says `do not
disturb`, and it holds until you turn it off, logins included.
`desktop notifications` lists the last few, `dismiss` clears the
screen, and `restore` shows the last one again; the dialog's
Notifications has the same. A program reaches mako through the
session's D-Bus. Where logind makes none (Void), the desktop starts
inside `dbus-run-session`, so the notifications start at the login
after `on desktop`.

A drive you plug in (a USB stick, a card) comes as a notification, and
a click on it opens the dialog's Storage, where Enter mounts it and,
once mounted, opens it in your file manager (or a terminal in it when
there is none). Nothing mounts by itself. `spark-shell desktop storage`
lists the drives with their parts and this computer's free space;
`mount NAME`, `unmount NAME`, `open NAME` and `eject NAME` do the rest,
eject unmounting every part first and powering the drive off. udisks2
mounts with no root where logind says you sit at the screen. On Void,
with no logind, `on desktop` writes a polkit rule that lets you mount,
eject and power off a removable drive, nothing more (sudo). An
encrypted drive is unlocked in a terminal (`udisksctl unlock -b DEV`).
The disk the system runs from, and a disk the system mounts itself, is
never listed.

Type `spark-shell desktop power suspend`. The screen locks first, then
the machine sleeps, from the dialog's Power too, where lock, log out,
restart and shut down sit beside it; log out, restart and shut down ask
for a typed yes there. Where logind runs, it does them for you; logind
refuses a restart while another login is open, and spark-shell says
so. On Void `on desktop` writes a sudo rule that lets you run zzz,
reboot and poweroff, each with no argument, and nothing else (sudo).
What the power button and the lid do is logind's or acpid's: the
section says it, and changes nothing.

## Wallpaper

By default there is no picture. Behind the windows is the ground: the
palette's background a shade darker than the windows, so the
transparent terminals sit on something quieter than themselves. It
follows the palette. Type `spark-shell theme wallpaper
/path/to/picture.jpg` for a picture of yours. A path from where you
are, or one that starts with `~`, works too. `default` is the ground
again, and so is `none`: no wallpaper changes the transparency.

Type `spark-shell theme wallpaper skyline`. You get one of the 17
wallpapers spark-shell ships in `wallpaper/`, each drawn for a palette.
For the dark ones: skyline (tokyonight-night), fjord (nord), forest
(everforest-dark), sunset (gruvbox-dark), hills (catppuccin-mocha),
dunes (dracula), ripples (rose-pine), contours (selenized-dark) and
embers (any dark palette). For the light ones: morning
(solarized-light), meadow (catppuccin-latte), kites (tokyonight-day),
fields (gruvbox-light), grove (everforest-light), arches
(rose-pine-dawn), shore (selenized-light) and flight (one-light).
Each is its SVG source and a 3840 by 2160 PNG, and the config keeps its
name, so it follows the clone. A drawing follows the palette: the second
line of each SVG names the role of every color it uses (the background,
the accent, a terminal color, a mix of two), so a drawing picked for
another palette, or for a palette made from a picture or from words, is
drawn again in that palette's colors (rsvg-convert draws it; the PNG
lands under `~/.local/state/spark-shell/wallpapers/`), and a palette
with a drawing of its own brings that one.

Type `spark-shell theme wallpaper navy`. You get a plain color, until
a palette with a drawing of its own replaces it. Give `#rrggbb`, or one
of these names: black, white, gray (or grey), silver, navy, blue, teal,
green, olive, maroon, red, purple, brown, orange. The ground, a
drawing, a picture and a color are drawn the same way: the windows
stand apart, with a transparent edge the mouse can grab, and the
terminals as transparent as `theme transparency` says. No window is
outlined in the accent; tabs and stacks show the focused title in the
surface shade.

## Pointer

The desktop draws its own pointer, the spark pointer: an arrow with no
stem, a hand, the I-beam, the resize arrows, an hourglass, in white on
a dark palette and in black on a light one. `spark-shell on desktop`
writes the two cursor themes, `spark-white` and `spark-black`, under
`~/.local/share/icons`, and the login screen gets a copy. sway shows
the one the palette picks and hands its name and size to every program
it starts, so one pointer shows everywhere. Its size follows the text
size: 24 pixels up to 13 points, 32 up to 19, 48 above. To use another
theme, or another size, set `POINTER` in the config: `POINTER=spark-black 32`,
or `POINTER=Adwaita` for a theme installed on the machine.

The edge of a window is where the mouse resizes it. Every window has a
four-pixel edge, so two windows are parted by an eight-pixel strip: the
pointer shows the resize arrows over it, and a drag resizes. The edge
is transparent, so the wallpaper shows there. A window alone on its
workspace has no edge. Super+right-drag shows the corner arrow it
pulls; Super+left-drag shows the closed hand, and where a tiled window
would land shows as a soft tint of the accent, a quarter of it, so the
text under it stays readable. The same tint draws a quiet line on the
side of a window left alone in a split, where the next one opens.

## Bar

On the desktop, a bar sits at the top of the screen. The workspaces are
on the left. A workspace a layout opened carries the layout's words, so
`2 news` reads from a distance. On the right, in groups parted by a thin
line: `lan`, `wifi` and `bt`; `out` and `mic`, each with its gauge;
`due`, a reminder due; `do not disturb`, while it is on; `light`, the
brightness with its gauge, and `kb`,
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
state; a long one is cut at a word), then the date and the time as your
locale writes them, and a small bar while work runs. The bar is one of
the five animations spark draws at its prompt, and it says what is
going on: a light bouncing while spark thinks, an arrow crossing while
the rows of a place are read, arrows moving right while a step runs,
one step after another when more steps wait behind it, and a bar
growing and shrinking while a model loads. Under it is
the prompt, two rows tall:
type a request, Enter sends it, and Shift+Enter starts a new line (Alt+Enter
where a terminal cannot tell the two apart). A longer draft scrolls
inside the two rows, and a paste keeps its lines and never sends. The
row under the prompt says what Enter does to the lit row and what Esc
does now; with nothing typed it says only what Esc does. A key is drawn
as a key, and nothing else is.

The home lists six places, each with what it holds now: Apps (the
apps by name), Files (your home folder), Workspace (the windows open
and the layouts saved), Notes (how many, and the newest), Calendar (the
next reminder, or none ahead) and Settings (the network and the theme;
inside, sound, microphone, Wi-Fi, Bluetooth, storage, display,
keyboard, notifications, theme, the bar, power, Talk, Connections and
About). A place shows only where this
machine has it. The down arrow moves from the prompt into the
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
- `notifications`: turn do not disturb on or off, dismiss what is on
  the screen, show the last one again; under them the last few.
- `storage`: each drive plugged in, with its parts: Enter mounts one,
  and on one that is mounted opens it in your file manager; unmount
  one, eject the drive; then this computer's free space.
- `power`: lock the screen, suspend, log out, restart, shut down; the
  last three ask for a typed yes. What the power button does is said
  under them, never changed.
- `theme`: first the wallpaper, the text size and the transparency, a
  row each; on the text size and the transparency, left and right
  change the value in place. Then the palettes, dark and light, each
  with a chip of its colors (its ground, its accent and six hues) and
  the drawing it brings. Then yours: your saved themes, `save this look
  as`, which asks a name, `a theme from a picture`, which opens your
  home folder, and the terminal's own colors (palette none). Enter on a
  palette applies it, and Undo takes it back; `theme back` on the
  command line steps through the last ten. The wallpaper row opens the
  wallpaper list: the drawings, each with the palette it was drawn for,
  the lit one shown as a picture in your palette at the top right; `a
  picture of yours` (jpg, jpeg, png, webp); `a color`, which asks for a
  name or `#rrggbb`; and the ground. The header names the palette. At
  the home, Esc clears what the last request left on the screen, its
  receipts and refusals; the next Esc closes the dialog.
- Calendar: the time in large figures, then this month and the next
  side by side, today lit and a day with a reminder in the accent; the
  left and right arrows move the months while nothing is typed. Under
  them, the reminders.
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
- `about`: the version, the licence and the address, then each key on
  one line, its sentence up to the first comma; `spark-shell desktop
  keys` has every sentence whole. It opens by itself the first time the
  desktop starts, and Esc gives the list back.
- `files`: your home folder. Enter on a folder opens it, `..` goes back
  up, and Esc walks back the way you came; a folder lists its folders,
  then its files with the size and the date. Enter on a file opens it
  with the app for its kind. A hidden file, a link and anything outside
  your home are never read.

Above the list, what was said and done, the newest first, a blank row
between one turn and the next. A turn is the command as it ran, then
what came of it in plain words: a check for a step done, a cross and
the reason for one refused. Undo at the end of a result takes that step
back while it can be: pick it, or type undo. At the bottom, under a
rule, the controls in plain text: Attach, the model, and the mic at the
right. Tab moves through them and the one in focus is lit; Shift+Tab
goes back.

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
the dialog can take, shown or not. The row your words name is lit, and
Enter runs it with no model call: `nord` and Enter is the palette nord
(`drac` lights dracula). Words that name no row light `Ask spark`, the
first row while you type. A place's name alone, as `settings` or
`calendar`, opens it. A command in the dialog's own words, as `display
brightness 30` or `theme dracula`, runs at once, with no model. Other
words start a task in spark with the current view and available tools.
Spark proposes one action, shown in the prompt for you to read. Enter
runs it; Esc stops the task. Changing the proposal starts a new request.
After execution, the actual result goes back to spark before it chooses
another action. A clarification keeps the same goal and earlier results.
An action such as closing a window or forgetting a network still waits
for a typed yes, checked again against what is offered then. A timeout
or lost provider stops the task: its outcome is unknown and it is not
retried. A reported error can lead to inspection or a different proposal,
which again waits for Enter. The Providers section describes the adapter.

The dialog is a terminal program: keyboard, focus and contrast are its
own, but a screen reader sees text, not controls with names.

The dialog is a program of its own, `spark-dialog`, built from
`dialog/` in this repository. `spark-shell on` installs it for the
desktop from the release of the tag this copy is on, and only when a
key in `allowed-signers` signed the tag and the file has the sha256
that `dialog/dialog.env` pins (x86_64 machines for now). It starts each
section as a provider, `spark-shell provide SECTION`, with no shell
and a short list of settings from your environment. They start
quietly: the progress bar shows only for work you asked for, a section
checks its rows only while they are on screen, and a provider leaves
nothing behind in `/tmp`, whatever stops it. It keeps one line
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

Mouse and touchpad preferences live in the Pointer section. Tap to click
starts on for touchpads; natural scroll starts off. Speed is -1 to 1, with
0 the default. Keyboard also sets repeat delay (100 to 2000 milliseconds),
repeat rate (0 to 100 per second, 0 disables repeat), and Caps Lock as itself,
Control or Escape. The settings apply live and remain for the next login.
The command line and the dialog use the same native controls, with no AI.

The dialog's key chips are clickable. A click takes the same action as the
key; each half of the Calendar's arrow chip moves in that direction.
Destructive operations still require a typed yes.

## Providers

The dialog's language prompt uses the tool adapter of `spark do`. It sends
the current view, selected row, local clock and visible state with that
view's capabilities. Dates, columns and exact row actions are retained,
including the selected row's action arguments. Existing-item arguments
are narrowed to their actual row values when one name identifies the item.
Other providers are listed by name; spark can request their current state
when the task needs it. Hidden rows are not volunteered.
Tool descriptions and typed arguments retain their meaning across the
interface. The protocol is owned by spark's `CLAUDE.md`, contract 16.

One proposed action waits for Enter. The dialog checks the current tools,
arguments and rows again, and consequential actions still require `yes`.
The actual MCP result goes back to spark before another action is proposed.
A question continues the same task. Esc drops the continuation; an action
already sent may still finish. Late model replies cannot restart it.
A lost provider or timeout stops the task without retrying the action.
Declared structured output schemas are checked before a result is accepted.
Model completion prose is separate from the native success receipt.

The continuation lives only in this window. The adapter adds no service,
model download or runtime dependency. A current spark build with
`spark do --tools` is required for this prompt; unsupported builds report
an error. The client's existing spark connection can supply inference from
another machine; no model needs to run on the desktop client. Execution
stays with the provider that owns the capability. Direct controls and
explicit commands remain usable without AI.
The terminal `want --json` interface and attachment reader below retain
their existing one-shot behavior during migration.

A tool can advertise `_meta["spark-shell/prepare"]: true`. Before showing
its proposal, the dialog calls the read-only `spark/prepare` method with
the same name and arguments. `{ready:true, arguments:{...}}` supplies
canonical arguments; these are checked and shown before execution.
`{ready:false, question:"..."}` requests clarification without execution
or another model call. Preparation failure, timeout or cancellation
never falls through to execution. This extension is optional; providers
without the flag keep their existing path. It grants no permission.

`reminders_add` uses preparation to resolve relative times to an explicit
local date and time. A past or unreadable time asks for clarification.
Preparation writes no calendar event. The reviewed explicit date survives
midnight; execution still checks that the time has not passed meanwhile.

Every section of the dialog is a provider: `spark-shell provide wifi`
serves the section as an MCP server on stdin and stdout (the Model
Context Protocol, 2025-06-18), for the dialog and for spark itself
later. A step is a tool, as `wifi_connect`
with its title `wifi connect NAME`; the rows are the resource
`spark-shell://wifi/rows`, and a host that subscribes is told when they
change. A tool runs only a step the section offers now, with a row's
own argument, checked as the dialog checks a pick. A tool that cannot be
taken back says so, and a result carries the step that takes it back
when there is one. A password is the tool's own argument, and it
reaches the Wi-Fi tool on its standard input, never on a command line,
which any user of the machine can read while it runs. It is never
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
none or a path), `POINTER` (a cursor theme's name and size, empty for
the spark pointer), `ALPHA` (how solid foot is, 0.85: 15% transparency),
`DESKTOP_BAR` (yes or no), `THEME`, `CONSOLE_FONT`, `QUIET_LOGIN`, `QUIET_BOOT`,
`DIALOG_ATTACH` (yes or no), `DIALOG_ATTACH_TYPES` (txt md),
`DIALOG_MODEL` and `DIALOG_TALK` (yes or no), `DISPLAY_IDLE` and
`DISPLAY_LOCK` (minutes, 0 never), `DISPLAY_SAVER` (clock, or a saver's
name), `KEYBOARD` (layouts), `DO_NOT_DISTURB` (yes or no). The commands
write them.

Files it writes: the shell files, `~/.tmux.conf`, `~/.config/btop/`,
`~/.config/starship.toml`, `~/.config/spark-shell/` (a saved theme a
folder under its `themes/`), `~/.config/spark/theme.env`,
`~/.local/state/spark-shell/` (yours alone, 0700: the last ten looks
and layouts, a drawing rendered in another palette, the drawings' small
pictures for the wallpaper list),
`~/.local/bin/spark-shell`, and for the desktop `~/.config/sway/`,
`~/.config/foot/` (foot.ini and the dialog's own dialog.ini),
`~/.config/starship-foot.toml`, `~/.config/mako/config`, a rule that
draws the bar's wifi bars without hinting in
`~/.config/fontconfig/conf.d/50-spark-shell.conf`,
the two cursor themes in
`~/.local/share/icons/`, on Void with spark the sound's service in
`~/.config/spark/sv/spark-shell-sound` and two links in
`~/.config/pipewire/pipewire.conf.d`, and, after a change of output on
plain ALSA, `~/.config/alsa/asoundrc`, and
`~/.config/spark-shell/screens.conf`. As
root: the console colors at boot (a systemd unit or a line in
`/etc/rc.local`), the console font, the login notice and boot files for
quiet, and on Void PipeWire's two links in `/etc/alsa/conf.d` and your
place in the `audio` group, the polkit rule for your drives in
`/etc/polkit-1/rules.d/50-spark-shell-storage.rules` and the sudo rule
for the power in `/etc/sudoers.d/spark-shell-power`, and your place in
`video` and `i2c` for the brightness. `off` restores or removes each
one. The font stays, as the packages do: four files in
`~/.local/share/fonts/monaspace-neon/`, or `MonaspaceNeon-*.otf` in
`~/Library/Fonts` on a Mac. `off login` removes the login screen's
copy, in `/usr/share/fonts/spark-shell/`.

What leaves the machine: only what the package manager downloads and,
for the desktop, the dialog's release file from GitHub, checked against
the sha256 the signed tree pins, and Monaspace Neon's release file from
GitHub, checked against the sha256 spark-shell pins. A
layout asks spark, which runs on this machine, with your words, the
screen sizes and the app list; a want at the dialog asks it with your
words, what the bar shows, the list of what it can do (an open window
by its name among it) and the names of your saved layouts. A theme from
words asks spark, on this machine, with the words alone; a theme from
a picture is color math here, and the picture goes nowhere. A file only
when you attach one, its text and its name, never its path.
A new Wi-Fi network is saved by the Wi-Fi tool itself.

The settings live in `~/.config/spark-shell/config`, and every run
reads that file. A setting in the environment never stands in for it.

The logo, in `assets/`: spark's block-letter S, then the prompt sign and
a cursor cell. `logo.svg` is for a dark ground and `logo-light.svg` for
a light one; `favicon.svg` and `favicon-light.svg` are the same with no
ground of their own, and `favicon-16.png` to `favicon-26.png`, with
their `-light` twins, are those at the height of a terminal row.
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

Display rows open the connected screen's scales, resolutions and arrangement.
Each change has undo. A screen kept off stays off at login; the last active
screen cannot be switched off. If the connected screens change and all are
off, the desktop enables the first connected screen.

`spark-shell desktop time format 12` selects a 12 hour clock everywhere;
`format 24` selects 24 hours. `time week monday` starts the week on Monday;
`sunday` restores Sunday. `time zone America/Chicago` changes the native
time zone after confirmation and system permission. The clock section
reports sync status without changing the time service.

Bluetooth uses the native BlueZ service. Pairing asks for the device's code
or confirmation in the dialog; only the chosen device can use that agent.
A paired device can be removed after typed confirmation. The shared native
services stay enabled when the desktop is off. On Void, a new bluetooth
group membership takes effect at the next login.

The native pairing wire uses the experimental `spark-shell/pairing`
capability and method. The dialog accepts it only while its configured
spark-shell provider runs `bt_pair`. PINs are masked and excluded from the
exchange, task context and audit. Generic elicitation still refuses secrets.

The printers section reads the configured native CUPS queues and your pending
jobs. It can select a default printer, pause or resume a queue, and cancel a
chosen job after confirmation. Queue state changes offer undo, as does a
default change when the prior default is known. Cancelled jobs stay cancelled.
CUPS owns permission and configuration.
No printer, server or service is added by opening the section.
