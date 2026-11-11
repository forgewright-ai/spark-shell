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
published yet moves nothing: run it again a few minutes later.

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
    Super+Space opens or focuses home, including its conversation view.
    Super+Alt+Space switches focus between floating and tiled windows.
    Super+Shift+q closes the window.
    Super+Shift+c reloads the desktop after spark-shell on.
    Super+Shift+e leaves the desktop.
    Super+h/j/k/l move the focus, and with Shift they move the window.
    Super+Shift+arrow moves the window too.
    Super+Alt+arrow moves the focus too, across the screens.
    Super+arrow snaps the window to a half, then a quarter of the screen.
    Super+Up twice maximizes the window, and Super+Down twice minimizes it.
    Super+minus puts the keyboard on the pad, where minimized windows wait.
    Super+Shift+space floats the window, or tiles it again.
    Super+f makes a window fill the screen.
    Super+r resizes the window, until Enter.
    The mouse resizes too: drag the strip between two windows.
    Super+right-drag resizes a window by its corner, Super+left-drag moves it.
    Super+w makes tabs, Super+Shift+s a stack, Super+e side by side again.
    Super+b puts the next window beside this one, and Super+v below it.
    Super+1..0 go to workspaces 1 to 10; with Shift the window goes there.
    Super+Ctrl+Left/Right go to the previous or next workspace.
    Super+Ctrl+Shift+Left/Right take the window there too.
    Super+Escape locks the screen; it locks by itself after idle minutes.
    Print captures the screen, Shift+Print an area, Super+Print the window.
    Super+Ctrl+space goes to the next keyboard layout.
    The volume and mute keys set the sound, and the mic mute key the mic.
    The brightness keys set the screen's brightness.
    Typing exit in the first window also leaves the desktop.

## Config

The settings live in `~/.config/spark-shell/config`. `config.example`
lists every key with its default, and the commands write them.

## Contributing

    git config core.hooksPath .githooks
    sh test/gate.sh

`sh test/gate.sh` runs every check CI runs, on this machine; the
pre-push hook runs `sh test/gate.sh --quick`. The suite,
`sh test/shell_test.sh`, runs in a throwaway HOME and never touches
yours. Report a problem at
https://github.com/forgewright-ai/spark-shell/issues.

## License

MIT, see `LICENSE`. `CREDITS.md` names the software spark-shell uses
and its licenses.
