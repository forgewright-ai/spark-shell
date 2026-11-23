# spark-shell

A minimal desktop for Linux, and a terminal setup for Linux, macOS and
Windows under WSL 2. One command sets up either. The desktop has home
(Super+Space) for apps, files, windows, notes, the calendar and the
settings, a pad for minimized windows, a bar, a lock screen and a login
screen. The terminal gets the everyday tools, a prompt and a color
theme. With a local AI installed, you can ask for things in words;
everything else works without one.

## Before you install

spark-shell changes your machine. `spark-shell on` replaces your shell
files and the settings of the tools it sets up (yours are saved as
`.bak` files), installs packages (sudo) and sets the console colors,
also at boot. On a Mac it sets a terminal profile instead.
`spark-shell on desktop` makes a login on tty1 start the desktop.
`spark-shell on login` puts a login screen on tty1 from the next boot.
`spark-shell quiet boot on` changes how the machine boots.

Each of these says what it will change and asks first. `--dry-run`
shows every change and changes nothing. `spark-shell off` undoes it
all; the packages stay installed. On Arch, installing the missing
packages upgrades the whole system in the same transaction, and it
asks first.

## Install

    git clone https://github.com/forgewright-ai/spark-shell ~/.spark-shell
    ~/.spark-shell/spark-shell on

To update, run `spark-shell update`: the clone moves to the newest
release signed by a key in its `allowed-signers`, never to a commit
nobody signed, and `on` runs again from it. A tag whose release is not
published yet moves nothing: run it again a few minutes later. Two
kinds of key sign: the release key any release, and a patch key, on a
machine that tags fixes by the rule in `test/tag.sh`, a patch (vX.Y.Z)
alone.

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

"Proven headless" means CI ran the desktop in a container of that
family and no more: a screen, a keyboard and sound are a machine's
proof. The desktop's own programs are built for x86_64 alone today.

## Commands

`spark-shell -h` lists every command. `spark-shell status` says what is
set up, and `spark-shell check` tests it.

## Keys

`spark-shell desktop keys` lists the desktop's keys as bound, and home's
help lists them by subject. The bindings are named actions in
`~/.config/spark-shell/desktop-keys.json` and, for home,
`~/.config/spark-shell/home-keys.json`. The defaults:

    Super+Return opens a terminal window.
    Super+Space opens home; held, it listens and types what you say.
    Super+period held listens too, with your prefix and suffix around the words.
    Super+Alt+Space switches focus between floating and tiled windows.
    Super+q closes the window.
    Super+Shift+c reloads the desktop after spark-shell on.
    Super+Shift+e leaves the desktop.
    Super+arrow moves the focus, and Super+h/j/k/l too.
    Super+Tab goes back to the window before, and again to the one before that.
    Super+Ctrl+arrow places the window at a half, then a quarter of the screen.
    Super+Ctrl+Up past the top fills the screen, and past the bottom minimizes.
    Super+m minimizes the window; Super+minus puts the keyboard on the pad.
    Super+Shift+space floats the window, or tiles it again.
    Super+Shift+arrow moves the window: in the tiling, or to the next screen.
    Super+Shift+h/j/k/l move the window in the tiling too.
    The buttons at a title's left end close, minimize, and fill the screen.
    The mic on a title's band listens until clicked again.
    Super+f makes a window fill the screen.
    Super+r resizes the window, until Enter.
    The mouse resizes too: drag the strip between two windows.
    Super+right-drag resizes a window by its corner, Super+left-drag moves it.
    Super+w makes tabs, Super+Shift+s a stack, Super+e side by side again.
    Super+b puts the next window beside this one, and Super+v below it.
    Super+1..0 go to workspaces 1 to 10; with Shift the window goes there.
    Super+PageUp/PageDown go to the previous or next workspace.
    Super+Shift+PageUp/PageDown take the window there too.
    Super+Escape locks the screen; it locks by itself after idle minutes.
    Print captures the screen, Shift+Print an area, Super+Print the window.
    Super+Ctrl+space goes to the next keyboard layout.
    The volume and mute keys set the sound, and the mic mute key the mic.
    The brightness keys set the screen's brightness.
    Super+equal puts the keyboard on the bar: arrows move and set, Enter acts.
    Typing exit in the first window also leaves the desktop.

## Config

The settings live in `~/.config/spark-shell/config`. `config.example`
lists every key with its default, and the commands write them.

## Theme settings

Open **settings > theme > The Gallery**. The 34 bundled themes hang in
the six sections of **The Permanent Collection**. Open a section to browse
its works. Moving through the list shows each wallpaper and changes nothing.
F3 opens the larger picture and Esc goes back. Enter on a work opens its
details; choose **apply theme** there to use it.

Each work identifies its source palette. Press F4 on a work to inspect the
**Terminal palette**; select a color to copy its hex value, or choose
**Export palette** to save its colors in the downloads folder.
The same palette is available from the command line:

```sh
spark-shell theme export amber-drizzle kitty > amber-drizzle.conf
```

Formats are `env` (all 20 colors), `foot`, `kitty`, `ghostty`, and
`alacritty`. With no format, the command prints `env`.

The sections are listed in `gallery/core/curation.json` and the theme
names in `gallery/core/themes.tsv`. Both ship with spark-shell and work
offline. Every theme keeps its name, settings and command. Wallpaper and
motion, type and glyphs, and interface settings can also be changed on
their own.

`spark-shell theme variant dark|light` switches a theme that has both.
`spark-shell theme screens` says what each screen shows.

Saved themes have their own entry. Personal themes take precedence when
names match; they live in `$XDG_CONFIG_HOME/spark-shell/themes/` (default
`~/.config/spark-shell/themes/`). To add a collection of your own, put its
theme names, one per line, in the adjacent `galleries/` directory, for
example `studio.list`.

**Your themes** lists the themes you made or installed, each with rename,
duplicate and delete, and the ways to make one: from the look in use, a
picture, a theme file, or a copy of the theme in use. **Colors** and
**Screens and art** change the theme in use: its 20 colors, the pointer,
the clock on the idle screen, its other variant, the pictures for a
turned, second and third screen, a loop for each picture, and the
dialog's own opening and closing. A bundled theme changes as a look of
its own until you save it.

To share a theme, `spark-shell theme export NAME spark-theme` writes
`NAME.spark-theme` to the downloads folder: its colors, look, pictures,
loops and dialog animation. Pictures lose their metadata, and the pointer
and text size stay yours. `spark-shell theme install FILE` reads one as
data, checks it as the gallery's themes are, and uses it.

## Contributing

The dialog, bar and winpad share the Rust library in `component/theme`.
It defines native palette colors, terminal slots and glyph families.
The shell reads the palette files in `gallery/theme`, manages saved looks
and applies them through `spark-shell theme`. From `component/theme`,
`cargo test --locked` compares every shipped palette with the shell.

    git config core.hooksPath .githooks
    sh test/gate.sh

`sh test/gate.sh` runs every check CI runs, on this machine; the
pre-push hook runs `sh test/gate.sh --quick`. `sh test/prove.sh` adds
the suite as CI's containers run it and the desktop's proofs, each in
a home of its own with sudo refused. `sh test/lane.sh` names the jobs
CI runs for a change. The suite,
`sh test/shell_test.sh`, runs in a throwaway HOME and never touches
yours. Report a problem at
https://github.com/forgewright-ai/spark-shell/issues.

## License

MIT, see `LICENSE`. `CREDITS.md` names the software spark-shell uses
and its licenses.
