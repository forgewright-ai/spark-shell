# spark-shell -- spark's own shell for a machine that is an AI box

A commercial box, a mac mini, an old laptop: a machine that serves a
local AI on the LAN, to run and to keep. spark gives it the AI;
spark-shell gives it the hands -- tmux, starship, fzf, zoxide, eza, bat,
btop, and one plain look on every surface (tmux, the prompt, btop):
ASCII and the 16 palette slots, right on
the Linux console and merely plain in an emulator. Discreet and light:
this machine's cycles belong to the model.

    spark-shell on          the tools, the look; the rc files
                            become spark-shell's (yours move to .bak)
    spark theme NAME        one palette everywhere (spark's verb)
    spark-shell apply       re-render the look from that palette
    spark-shell off         everything back from .bak, or gone
    spark-shell check       is this machine still what this repo says?
    spark-shell desktop     sway and one foot window on this console
                            (DESKTOP=sway in the config)

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

## The prompt

With spark-shell on, spark's prompt takes the palette's colour: `on`
and `apply` render `~/.config/spark-shell/sgr.sh`, three exports from
the accent and muted slots (`SPARK_ACCENT_SGR`, `SPARK_MUTED_SGR`,
`SPARK_WARN_SGR`), and spark 1.41 or newer draws its hint row, `spark
chat` and `spark do` with them at a tty. starship shows `spark MODEL`
on the prompt while spark answers and `spark down` when it stopped,
read from spark's own cache (`~/.local/state/spark/prompt`) by one sh
between keystrokes; the cycles stay the model's.

## A desktop

Put `DESKTOP=sway` in the config and `spark-shell on` adds a desktop to
the box: sway, a Wayland compositor that tiles windows, and foot, the
terminal window, with DejaVu Sans Mono from the distro. Both are
rendered from the same palette: foot takes the sixteen slots' own hex,
so it is the desktop's twin of the console palette, and sway's borders
and background take the accent, the muted tone and the background. tmux
stays the multiplexer inside a window (sessions, panes, the bar line),
so sway draws the borders only: the bar line is tmux's.

    spark-shell desktop     start it, from a console login (tty1)
    Super+Return            a window: foot, running your login shell
    Super+Shift+q           close it
    Super+Shift+c           reload sway (after spark-shell apply)
    Super+Shift+e           back to the console

The keys are i3's: `Super` and hjkl or the arrows to focus, with Shift
to move, `Super+1`..`0` the workspaces, `Super+r` resize. `spark theme
NAME` then `spark-shell apply` recolours the borders live and the next
window. Between keystrokes it idles: sway and foot draw on demand, the
cycles stay the model's. Start the desktop, then the model: they share
the memory. sway's log is `~/.local/state/spark-shell/sway.log`. If
`seatd.service` is ever enabled on the box, add your user to the `seat`
group (libseat prefers seatd over logind when both are there).

## Options

`~/.config/spark-shell/config` (KEY=value, every key optional):
`PROMPT` starship|plain, `PROMPT_STYLE` minimal|full, `GIT_NAME`,
`GIT_EMAIL` (set both and a
.gitconfig is rendered with that identity; one you already have stays
yours), `DESKTOP` none|sway, `FONT` (foot's spec, `DejaVu Sans
Mono:size=12`). `config.example` shows the defaults.

## What leaves this machine

Nothing, beyond the package manager and one pinned download verified
by sha256 (starship). No model, no network call, no
telemetry. The one file read from spark is `~/.config/spark/theme.env`;
nothing is ever sent to it.

## Contributing

    git config core.hooksPath .githooks
    sh tests/shell_test.sh

The pre-commit gate keeps the docs ASCII and the tree free of private
words; the test suite runs in a throwaway HOME and never touches yours.

MIT. Credits in CREDITS.md. Built with Claude.
