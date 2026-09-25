# spark-shell -- the seat at an AI box

An AI box is a machine kept to serve a local AI: a small server, a
Mac mini, an old laptop. spark gives it the AI. spark-shell gives it
the seat: the tools and one plain look. The tools are tmux, starship,
fzf, zoxide, eza, bat, btop and fd. The look is ASCII and the 16
palette slots on every surface: tmux, the prompt, btop, foot, sway,
the login box. It is right on the Linux console and plain in an
emulator. This machine's cycles belong to the model.

    spark-shell on          the terminal seat: the tools, the prompt, the look
    spark-shell on desktop  the seat and a desktop: sway, foot, the login box
    spark-shell off desktop the desktop and the login box off at the next boot
    spark-shell off         everything handed back, the packages stay
    spark-shell on --dry-run
                            print what would change, touch nothing
    spark-shell off --dry-run
                            print what would be handed back, touch nothing
    spark-shell check       the machine row by row, exit 0 when no row fails
    spark-shell status      the state: rc files, tools, the look, the next step
    spark-shell bar on|off  the status line (tmux's, spark draws it)
    spark-shell sbom [apps|tools|parts|NAME] [--json]
                            the software bill of materials, one row per package
    spark-shell desktop     sway and one foot window on this console, now
    spark-shell desktop "WORDS" [--rooms|--windows]
                            a desk for that need: the model picks the windows
    spark-shell desktop keep [WORDS] | WORDS | forget WORDS
                            keep the last desk, open a kept one, drop one
    spark-shell desktop apps | tools
                            what a desk may open: a picker, one list of marks
    spark-shell desktop keys
                            the desktop's keys, one sentence each
    spark-shell desktop wallpaper PATH|default|none
                            the picture behind the windows
    spark theme NAME        one palette everywhere (spark's verb)

Three states: nothing, the terminal seat, the seat with a desktop.
`on` and `off` move between them, and `desktop` names the third.
`spark-shell status` ends with a `next` row while one thing is still
off. That is spark not installed, the desktop not on, a render
missing, the login box not at boot or a reboot pending. A complete
seat has none.

## Installing

    git clone https://github.com/forgewright-ai/spark-shell ~/.spark-shell
    ~/.spark-shell/spark-shell on

It runs on the Debian and Arch families (apt or pacman, sudo asked
once) and on macOS (Homebrew). To update, `git -C ~/.spark-shell pull`
and then `spark-shell on` again. spark itself is not required. With
it, the status line is spark's and the palette follows `spark theme
NAME` (a new login does it, or `spark-shell on`). The prompt is
starship's, from pacman on Arch and from Homebrew on macOS. Debian 13
has no starship package, so there the rc files draw the shell's own
prompt. `PROMPT=plain` in the config picks the shell's own prompt
anywhere.

## One plain look

This machine is often a bare Linux console: a 256-glyph font and 16
palette slots, nothing more. So every rendered file names colours by
slot (`colour0` to `colour15`, or starship's 16 colour words) and
draws with ASCII. The palette reaches every surface through the
console palette that `spark theme NAME` programs. The accent and the
muted tone become the nearest of the palette's 16 slots. One file,
right on the console, plain in an emulator.

The rule is for the look, not for content. What a program draws
inside a pane, a picture or text art, keeps the colours it has. tmux
passes RGB through under foot. The console has no RGB, so there the
same file draws in its nearest slots.

## The prompt

With spark-shell on, spark's prompt marks take the palette's colour.
`on` renders `~/.config/spark-shell/sgr.sh`, three exports from the
accent and muted slots (`SPARK_ACCENT_SGR`, `SPARK_MUTED_SGR`,
`SPARK_WARN_SGR`). spark 1.41 or newer draws its hint row, spark chat
and `spark do` with them at a tty.

## A desktop

`spark-shell on desktop` adds a desktop to this machine: sway, a
Wayland compositor that tiles windows, and foot, the terminal window,
with DejaVu Sans Mono from the distro. Both are rendered from the same
palette. foot takes the 16 slots' own hex, so it is the desktop's twin
of the console palette. sway's borders and background take the accent,
the muted tone and the background. tmux stays the multiplexer inside a
window (sessions, panes, the status line), so sway draws the borders
only.

`spark-shell desktop` starts it now, from a console login (tty1).
Started by hand, sway's log is `~/.local/state/spark-shell/sway.log`,
and from the login box it is the journal's. If `seatd.service` is
ever enabled on this machine, add your user to the `seat` group
(libseat prefers seatd over logind when both are there).

`Super+s` opens a small window with spark chat, floating on the
workspace you are on, and `Ctrl-D` closes it. It follows `spark theme`
like every other window. Without spark the window says so instead of
never appearing. Stacking, i3's `Super+s`, is `Super+Shift+s` here.

Between keystrokes the desktop idles: sway and foot draw on demand,
the login box waits on a tty, the cycles stay the model's. Start the
desktop, then the model: they share the memory.

## The keys

`spark-shell desktop keys` prints the desktop's keys any time, one
sentence each. The first window shows them once, as a short card,
then your shell. They are the `# key:` lines of the sway template.

    Super+Return opens a window, foot running your login shell.
    Super+d asks for a desk from your words at a small prompt.
    Super+s opens a small window with spark chat, and Ctrl-D closes it.
    Super+Shift+q closes the window.
    Super+Shift+c reloads sway after spark-shell on.
    Super+Shift+e leaves the desktop for the console or the login box.
    Super and h, j, k, l or an arrow move the focus, with Shift the window.
    Super+f fills the screen with a window, and Super+r resizes until Enter.
    Super+1 to 0 go to a workspace, and with Shift send the window there.
    exit in the first window leaves the desktop too.

## The login box

`on desktop` also puts the login box on tty1: greetd, with tuigreet
drawing it on the console. It shows the machine's name above, Login
and Password, and the clock, in the palette's slots like everything
else. Behind it tuigreet's DOOM fire burns in the same
slots where tuigreet knows it (0.11 and newer), and `F4` switches it
for one boot. It costs a few percent of one core while the login box
waits, nothing once you are in.

`Enter` starts the desktop. `F2` picks the console session instead, a
login shell on tty1 with no desktop, and `spark-shell desktop` starts
one from there. greetd takes tty1 in getty's place at the next boot,
never in the middle of a session. tty2 and up, and ssh, are as before.
Leaving the desktop shows the login box again.

`spark-shell off desktop` hands the renders back and puts getty on
tty1 again at the next boot. The packages and the terminal seat stay.
The login box's files are root's (`/etc/greetd`, a `greetd.service`
drop-in), so `on` asks for sudo once, at a terminal, whenever the
login box is on. Those files are only written when they differ.

## The wallpaper

The desktop opens on the forge wallpaper, the smith at work:
`wallpapers/forge-1920x1080.jpg`, shipped here in two sizes (a
2560x1664 twin for a bigger screen). sway fills the screen with it
and keeps gaps around the windows (8 px inside, 12 px at the edges).
The next foot window is a little translucent (`ALPHA` in the config,
0.85), so the wallpaper shows through the text.

`spark-shell desktop wallpaper PATH` puts a picture of yours there
instead. `default` brings the wallpaper back, and `none` leaves the
palette's background, edge to edge and opaque. Bare, it names the
current one. A running sway takes the change at once. A dark picture
keeps the text readable. A picture that goes missing leaves the
palette's colour and a row saying so, never a black screen.

## A desk from your words

    spark-shell desktop "focused news reading and music"
    spark-shell desktop "studio for content creation for Instagram and X"

Say what you are about to do and the desktop lays it out. The model
reads the app list: this machine's desktop entries, the packages you
chose, a tool the words name. It picks the windows for that work, a
main one and the ones beside it.

sway opens them on the next empty workspace, the main window at the
left at the width the model gave, the rest stacked at the right. One
line says why those windows.

Each app opens the way its own desktop entry says: mpv's idle player,
a browser on the page the model named, a terminal app inside foot. The
windows you already have are not touched.

`Super+d` asks the same at a small prompt: type, then `Enter`. The
arrows move over your kept desks, and `Esc` closes it. There the why
line stays until `Enter`, so you read it.

A desk is for that need and that moment. Close its windows and it is
gone, an empty workspace with the wallpaper on it. `Super+1` is your
first terminal again, and `Super+Return` opens a new one there. One
you would want again:

    spark-shell desktop keep            the last desk, under its own words
    spark-shell desktop keep writing    or under yours
    spark-shell desktop writing         opens it again, no model
    spark-shell desktop forget writing
    spark-shell desktop                 inside the desktop: the kept ones

## Two screens

With 2 screens the model is told both, left and right with their
sizes. It puts a window on one of them only when the need wants both
("the feed on the right screen"). Each screen gets its own workspace,
the main window's first, and the closing line names both. A desk kept
on 2 screens opens on one and says so in a line. Nothing pins a
window: dragging it to the other screen, floating it or closing it
stay yours. More than 2 are named as sway names them (`DP-1`,
`HDMI-A-1`), and a kept desk may name one that way too.

## The app list

What a desk may open is what this machine declares: every app with a
desktop entry, the way the OS's own launchers see it, plus any program
your words name. To choose for yourself, `spark-shell desktop apps`
opens a picker over this machine's apps, one row per package, and
`spark-shell desktop tools` one over its tools (each runs in a
terminal window). A marked row wears a `*`, `Tab` flips a mark, and
`Enter` saves to `~/.config/spark-shell/apps`. That file is yours:
one name per line, with your own words after a colon if you like
(`mpv: my radio`). Marked, the desk offers exactly those. tmux
declares itself when the desktop is on. A graphical app or a game is
as welcome as a terminal one, and can be the whole workspace.

## A kept desk

A kept desk is the model's answer, one JSON object in
`~/.config/spark-shell/desks/NAME`: the words, the why, the main
window with its width, the windows beside it. It is yours to edit, and
it is laid out again for the screens you have each time it opens. A
desk kept before v0.36 (sway lines) is refused with the words that
make it again.

Every rendered line, fresh or kept, passes one gate before sway sees
it: a desk verb, no shell syntax, and `exec` only of an app this
machine has. A shell or a way to root is not an app. A line that fails
is named and dropped, and the rest still opens. The model sees the
need's words, the screens (name and size) and the app list, never a
window's title or a file.

## Rooms

    spark-shell desktop "the feeds, the mail and a shell"
    spark-shell desktop studio --rooms      inside the desktop, as rooms
    spark-shell desktop "WORDS" --windows   from a console: sway first

Where there is no sway (a console login, ssh, a Mac) the same desk
plays as rooms. That is a tmux session named after the words, one
window per app, the status line naming them, joined at once. Inside
tmux the client switches to it, and on a pipe one line says how to
attach. The player is where you ask from, never a guess. Inside the
desktop it is windows, and `--rooms` there builds the session and
opens it in a foot window of its own. `--windows` from a console
starts sway and lays the desk out in it. A session with that name
already open is joined, not built again. `tmux kill-session -t NAME`
ends it.

Rooms are terminal windows, so the model is offered the terminal apps
only. A kept desk's graphical app (gimp, a browser) is one line,
"needs the desktop", and the rest opens. A kept desk runs any program
this machine has, as on the desktop. Two words are desks' own. `shell`
is a terminal with a prompt (foot alone on the desktop, tmux's own
window here). `editor` is `$EDITOR`'s name, else micro when it is
here, else one refusal telling you to set it in
`~/.config/spark-shell/rc`. The main window's `width` is the desktop's
and is not read here.

One desk ships with the repository, the studio: a shell, the editor,
the feeds (newsboat), the web (w3m on duckduckgo.com) and the mail
(aerc), one room each. Keeping it is a copy, then its name:

    cp desks/studio ~/.config/spark-shell/desks/
    spark-shell desktop studio

An app this machine lacks is one refused line, and the rest opens. A
music room is yours to add, one entry in the kept file's `side` list,
with your own playlist:

    {"app": "mpv", "args": "--no-video radio.m3u"}

## The bill of materials

`spark-shell sbom` is this machine's software bill of materials, in
the package manager's words. Each row is a package: its version,
licence, description, chosen or dependency, the commands it puts on
PATH and the desktop entries it ships. `sbom apps`, `sbom tools` and
`sbom parts` narrow it, and `sbom NAME` is one package. `sbom --json`
writes CycloneDX 1.5 to `~/.local/state/spark-shell/sbom.cdx.json`,
the format spark's own `spark ver --sbom` uses.

## The palette at login

`spark theme NAME` writes the palette. At your next login spark-shell
sees the change and re-renders its own files (tmux, starship, btop,
spark's prompt marks, foot and sway) before the greeting, one checksum
when nothing changed. `spark-shell on` does it now: a running sway
takes the borders at once, and the login box follows (root's files,
sudo).

## Yours

`~/.config/spark-shell/rc` is sourced last by both rc files and never
written by spark-shell: `export EDITOR=micro`, aliases, anything these
files do not say. The editor you use is yours.

## Options

`~/.config/spark-shell/config` is KEY=value, every key optional, and
`config.example` shows the defaults. `PROMPT` is starship or plain,
and `PROMPT_STYLE` minimal or full. `DESKTOP` is none or sway
(`spark-shell on|off desktop` writes it). `FONT` is foot's spec
(`DejaVu Sans Mono:size=12`). `WALLPAPER` is default, none or an
absolute path (`spark-shell desktop wallpaper` writes it), and `ALPHA`
is foot's opacity over a picture (0.85).

## What leaves this machine

The package manager's fetches. A desk is one call to `spark edit` on
this machine, where the model runs. It reads the need's words, the
screens' names and sizes (or the terminal's, for rooms) and the app
list. No telemetry. The files read from spark are `theme.env` (the
palette) and, at login, `site.env` and `banner` (the greeting).
Nothing is ever sent to it.

## Contributing

    git config core.hooksPath .githooks
    sh tests/shell_test.sh

The pre-commit gate keeps the docs ASCII and the tree free of private
words. The suite runs in a throwaway HOME, never touches yours, and
holds the docs to the voice.

The voice is spark's, in its `docs/CONTRIBUTING.md` under Voice, plus
spark-shell's own words:

- "an AI box" once, in the first sentence, as the idea. Everywhere
  else it is "this machine".
- "spark-shell" is the program. "the seat" is what it gives: the
  terminal seat, or the seat and a desktop.
- "the login box" in full: greetd and tuigreet on tty1.
- "the palette", "the model", "spark chat" (what `Super+s` opens),
  "the prompt" (the shell's), "spark's prompt marks" (the colour
  spark takes from `sgr.sh`), "the status line" (tmux's).
- "the forge wallpaper" the first time, then "the wallpaper".
- "a desk", "a room", "a window", "a workspace", "a screen", "the app
  list", "a mark".
- Keys in backticks, sway's names in a combination: `Super+Return`,
  `Super+d`. Alone: `Enter`, `Esc`, `Tab`, `Ctrl-D`.
- "licence", and numerals: 16 slots, 8 px, 0.85.

MIT licence (LICENSE). Credits in CREDITS.md. Built with Claude.
