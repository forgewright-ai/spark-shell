# spark-shell -- spark's own shell for a machine that is an AI box

A commercial box, a mac mini, an old laptop: a machine that serves a
local AI on the LAN, to run and to keep. spark gives it the AI;
spark-shell gives it the hands -- tmux, starship, fzf, zoxide, eza, bat,
btop, yazi, and one plain look on every surface (tmux, the prompt, btop,
yazi):
ASCII and the 16 palette slots, right on
the Linux console and merely plain in an emulator. Discreet and light:
this machine's cycles belong to the model.

    spark-shell on          the tools, the look; the rc files
                            become spark-shell's (yours move to .bak)
    spark theme NAME        one palette everywhere (spark's verb)
    spark-shell apply       re-render the look from that palette
    spark-shell off         everything back from .bak, or gone
    spark-shell check       is this machine still what this repo says?
    spark-shell desktop on  a desktop and a login box: sway, foot, and
                            greetd's box on tty1 at the next boot
    spark-shell desktop off both back: getty on tty1 again
    spark-shell desktop     sway and one foot window on this console, now
    spark-shell desktop wallpaper PATH|default|none
                            the picture behind the windows (default: the forge)

## Install

    git clone https://github.com/forgewright-ai/spark-shell ~/.spark-shell
    ~/.spark-shell/spark-shell on

Debian and Arch families (apt or pacman, sudo asked once), macOS
(Homebrew). To update: `git -C ~/.spark-shell pull`, then
`spark-shell apply`. spark itself is not required; with it, the tmux
status line shows `spark bar line` and the palette follows
`spark theme NAME` (then `spark-shell apply`). Machines that ran
spark's old shell layer are adopted: the first `on` reads your old
choices out of spark's site.env once, and rendered files spark left
behind are re-rendered in place, never backed up against you.

## One plain look

The machine this is for is often a bare Linux console: a 256-glyph
font and 16 palette slots, nothing more. So every rendered file names
colours by slot (`colour0`..`colour15`, or starship's sixteen colour
words) and draws with ASCII. The palette reaches every surface through
the console palette `spark theme NAME` programs; the accent and the
muted tone become the nearest of the palette's sixteen. One file, right
on the console, plain in an emulator.

The rule is for the look, not for content. What a program draws inside
a pane, a picture or text art, keeps the colours it has: tmux passes
RGB through under foot, and on the console, which has no RGB, the same
file draws in its nearest slots.

## The prompt

With spark-shell on, spark's prompt takes the palette's colour: `on`
and `apply` render `~/.config/spark-shell/sgr.sh`, three exports from
the accent and muted slots (`SPARK_ACCENT_SGR`, `SPARK_MUTED_SGR`,
`SPARK_WARN_SGR`), and spark 1.41 or newer draws its hint row, `spark
chat` and `spark do` with them at a tty. The prompt line itself stays
starship's.

## A desktop

`spark-shell desktop on` adds a desktop to the box: sway, a Wayland
compositor that tiles windows, and foot, the terminal window, with
DejaVu Sans Mono from the distro. Both are rendered from the same
palette: foot takes the sixteen slots' own hex, so it is the desktop's
twin of the console palette, and sway's borders and background take the
accent, the muted tone and the background. tmux stays the multiplexer
inside a window (sessions, panes, the bar line), so sway draws the
borders only: the bar line is tmux's. (`DESKTOP=sway` in the config and
`spark-shell on` is the same thing; `desktop on` writes that line.)

With it comes a login box on tty1: greetd, with tuigreet drawing a small
box on the themed console -- the machine's name above, Login and
Password, the clock -- in the palette's slots, like everything else,
and behind it tuigreet's DOOM fire in the same slots where tuigreet
knows it (0.11 and newer; F4 switches it for one boot). It costs a few
percent of one core while the box waits, nothing once you are in.
Enter starts the desktop; F2 picks the console session instead, a login
shell on tty1 with no desktop (`spark-shell desktop` starts one from
there). greetd takes tty1 in getty's place at the next boot, never in
the middle of a session; tty2 and up, and ssh, are as before. Leaving
the desktop shows the box again. `spark-shell desktop off` writes
`DESKTOP=none`, hands the renders back and puts getty on tty1 again at
the next boot; the packages stay. The box's files are root's
(`/etc/greetd`, a `greetd.service` drop-in), so `desktop on` and `apply`
ask for sudo when they differ.

    spark-shell desktop     start it now, from a console login (tty1)
    Super+Return            a window: foot, running your login shell
    Super+d                 a desk from your words (below)
    Super+Shift+q           close it
    Super+Shift+c           reload sway (after spark-shell apply)
    Super+Shift+e           back to the console (or the login box)
    exit                    in the first window: back there too

The desktop opens on the forge: `wallpapers/forge-1920x1080.jpg`, the
smith at work, shipped here in two sizes (a 2560x1664 twin for a
bigger display). sway fills the screen with it, keeps gaps around the
windows (8 inside, 12 at the edges) and the next foot window is a
little translucent (`ALPHA` in the config, 0.85), so it shows through
the text.
`spark-shell desktop wallpaper PATH` puts a picture of yours there
instead, `default` the forge again, `none` the palette's background,
edge to edge and opaque; bare, it names the current one. A running
sway takes the change at once. A dark picture keeps the text readable.
A picture that goes missing leaves the palette's colour and a row
saying so, never a black screen.

The keys are i3's: `Super` and hjkl or the arrows to focus, with Shift
to move, `Super+1`..`0` the workspaces, `Super+r` resize. `spark theme
NAME` then `spark-shell apply` recolours the borders live, the next
window and the login box. Between keystrokes it idles: sway and foot
draw on demand, the login box waits on a tty, the cycles stay the
model's. Start the desktop, then the model: they share the memory.
Started by hand, sway's log is `~/.local/state/spark-shell/sway.log`;
from the login box it is the journal's. If `seatd.service` is ever
enabled on the box, add your user to the `seat` group (libseat prefers
seatd over logind when both are there).

## A desk from your words

    spark-shell desktop "focused news reading and music"
    spark-shell desktop "studio for content creation for Instagram and X"

Say what you are about to do and the desktop lays it out: the model
reads the apps this machine has (its desktop entries, the packages you
chose, a tool the words name) and picks the windows for that work, a
main one and the ones beside it; sway opens them on the next empty
workspace, the main at the left at the width the model gave, the rest
stacked at the right, and says in one line why those (at the `Super+d`
prompt the window follows the desk and stays until Enter, so you read
it; "writing" alone once meant mail to the model). Each app opens
the way its own desktop entry says (mpv's idle player, a browser on
the page the model named), a terminal app inside foot. The windows you
already have are not touched. `Super+d` asks the same at a small
prompt: type, Enter; the arrows move over your kept desks; Esc closes. A desk is for that need and that moment: close its windows and
it is gone, an empty workspace with the forge on it; `Super+1` is your
first terminal again, `Super+Return` a new one there. One you would
want again:

    spark-shell desktop keep            the last desk, under its own words
    spark-shell desktop keep writing    or under yours
    spark-shell desktop writing         opens it again, no model
    spark-shell desktop forget writing
    spark-shell desktop                 inside the desktop: the kept ones

What a desk may open is what the box declares: every app with a
desktop entry, the way the OS's own launchers see it, plus any program
your words name. To choose for yourself, `spark-shell desktop apps`
opens a picker over the box's apps, `spark-shell desktop tools` one
over its tools (each runs in a terminal window), one row per package:
a marked row wears a `*`, Tab flips a mark, Enter saves
to `~/.config/spark-shell/apps`, yours, one name per line with your
own words after a colon if you like (`mpv: my radio`). Marked, the
desk offers exactly those. tmux declares itself when the desktop is
on. A graphical app or a game is as welcome as a terminal one: it
opens the way its entry says, and can be the whole workspace.

`spark-shell sbom` is the box's software bill of materials, in the
package manager's words: every package, its version, licence,
description, chosen or dependency, the commands it puts on PATH and
the desktop entries it ships. `sbom apps`, `sbom tools`, `sbom parts`
narrow it, `sbom NAME` is one package, `sbom --json` writes CycloneDX
1.5 to `~/.local/state/spark-shell/sbom.cdx.json`, the format spark's
own `spark ver --sbom` uses.

A kept desk is a text file of sway commands
(`~/.config/spark-shell/desks/NAME`), yours to edit. Every line, fresh
or kept, passes one gate before sway sees it: a desk verb, no shell
syntax, and `exec` only of an app this machine has -- a shell or a way
to root is not an app. A line that fails is named and dropped, the rest
still opens. The model sees the need's words, the screen's size and
the app list, never a window's title or a file. From a console with no
desktop running, `spark-shell desktop "WORDS"` starts one and lays the
desk out in it.

## The palette follows you

`spark theme NAME` writes the palette; at your next login spark-shell
sees the change and re-renders its own files (tmux, starship, btop,
yazi, the prompt's colours, foot and sway) before the greeting -- one
checksum when nothing changed. `spark-shell apply` does it now, and is
the one that reaches the login box (root's files, sudo).

## Yours

`~/.config/spark-shell/rc` is sourced last by both rc files and never
written by spark-shell: `export EDITOR=micro`, aliases, anything these
files do not say. yazi, git and the rest read `EDITOR` from there; with
it unset they fall back to `vi`, which the tools bring as a safety net
(a minimal Arch has none). The editor you use is yours.

## Options

`~/.config/spark-shell/config` (KEY=value, every key optional):
`PROMPT` starship|plain, `PROMPT_STYLE` minimal|full, `GIT_NAME`,
`GIT_EMAIL` (set both and a
.gitconfig is rendered with that identity; one you already have stays
yours), `DESKTOP` none|sway (`spark-shell desktop on|off` writes it),
`FONT` (foot's spec, `DejaVu Sans Mono:size=12`), `WALLPAPER` default,
none or an absolute path (`spark-shell desktop wallpaper` writes it),
`ALPHA` for foot over a picture (0.85).
`config.example` shows the defaults.

## What leaves this machine

Nothing, beyond the package manager and two pinned downloads verified
by sha256 (starship; yazi on Debian). No model, no network call, no
telemetry. The one file read from spark is `~/.config/spark/theme.env`;
nothing is ever sent to it.

## Contributing

    git config core.hooksPath .githooks
    sh tests/shell_test.sh

The pre-commit gate keeps the docs ASCII and the tree free of private
words; the test suite runs in a throwaway HOME and never touches yours.

MIT. Credits in CREDITS.md. Built with Claude.
