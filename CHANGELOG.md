# Changelog

## v0.32

- `spark-shell sbom [apps|tools|parts|NAME] [--json]`: the box's
  software bill of materials in the package manager's words (pacman,
  dpkg, brew): version, licence, description, chosen or dependency,
  commands, desktop entries with their XDG categories; kind follows
  (an app declares itself with an entry, a tool is a command, a part
  is neither). `--json` writes CycloneDX 1.5, spark's own format.
- The desk's inventory is what the box declares: every app with a
  desktop entry, plus a program your words name. The list of chosen
  packages is gone (it had offered mkinitcpio, greetd and fzf as apps).
- `spark-shell desktop apps`: a picker (fzf, Tab marks, Enter saves)
  over the box's apps and tools; the marks live in
  ~/.config/spark-shell/apps, yours, `name[: your words]`. Marked, the
  desk offers exactly those, with your words beside the machine's.
- tmux declares itself as an app of the desktop (a rendered entry).
- `status` has an `apps` row; `check` an `apps` row (a marked app that
  is gone is a FAIL with the remedy).

## v0.31

- The pulse also runs while a window is awaited, not only while the
  model writes: the seconds between the why line and the first window
  had shown nothing.

## v0.30

- The prompt takes the focus back before "Enter closes": Enter had
  been going to the app opened last. What it shows is what a person
  reads: the why, one line per window with its outcome (`w3m
  duckduckgo.com`, `mpv radio.m3u -- no window`), any refusal; the
  sway lines come with `-v` and live in the kept file. `-v` and
  `--dry-run` after the words are flags, not words.

## v0.29

- The prompt's header in whole sentences: "Say what you are about to
  do and press Enter. Up and Down pick a desk you kept. Esc closes."
  The window is taller (40 ppt), so the why line stays in view.

## v0.28

- The packages you chose reach the model in the package's own words
  (pacman's, dpkg's or brew's one-line description): "internet
  browsing" had opened avahi's SSH-server browser because w3m's line
  said only "a tool you chose". A shell or a way to root is not in the
  list at all.

## v0.27

- The `Super+d` prompt window follows the desk to its workspace and
  stays, on top, until Enter: the model's why line and any refusal are
  read, not lost with the window when the workspace switched.
- The `desk>` prompt is an fzf line when fzf is there (the tools row
  installs it): the arrows move over the kept desks, Enter takes the
  words or the desk under the cursor, Esc closes, a header says so.
  A bare `read` had thrown escape codes at the arrows and ignored Esc.
- While the model writes, the prompt shows the pulse every spark prompt
  shows (`*` in the accent, `.` `..` `...` muted, 0.35 s), at a tty only.

## v0.26

- The `desk>` prompt (Super+d) no longer repeats your words on a
  second line; the command-line form still names the need first.

## v0.25

- An app opens the way its own desktop entry says: the Exec line with
  its file/URL field taking the model's args, or dropped. mpv's entry
  is `mpv --player-operation-mode=pseudo-gui -- %U`, so a music desk
  gets an idle player window instead of nothing (bare `mpv` ends at
  once with nothing to play).

## v0.24

- A desk whose window never came (mpv with nothing to play) no longer
  cuts the window before it: the split meant for it is skipped, and
  the next window lands where that one would have. The model's brief
  asks for as few windows as the work takes, never an app the need
  does not call for (aerc had been padding "writing and music").

## v0.23

- A desk from your words: `spark-shell desktop "focused news reading
  and music"` asks the model (spark edit, from nothing, one JSON
  answer: why, a main window and its width, the side windows) for the
  windows the need calls for, from the apps this machine has -- its
  desktop entries, the packages you chose, a tool the words name --
  and sway opens them on the next empty workspace, main at the left,
  the rest stacked at the right. `Super+d` asks at a small floating
  prompt. `keep NAME`, `NAME`, `forget NAME`: a kept desk is a text
  file of sway commands, replayed with no model call; bare `desktop`
  inside the desktop lists them. Every line passes one gate before
  sway sees it (a desk verb, no shell syntax -- sway hands exec to
  sh -c -- and exec only of an app in the inventory, never a shell or
  a way to root). From a console with no desktop, the words wait for
  the one it starts. The `check` desktop row wants jq; `status` has a
  `desks` row.

## v0.22

- `ALPHA` in the config: foot over a picture, 0 to 1, default 0.85
  (0.95 hid the forge; 0.9 had let a bright car through -- the number
  depends on the picture, so it is yours).

## v0.21

- The forge is the desktop's default wallpaper: `wallpapers/` ships the
  smith at work in 1920x1080 and 2560x1664 (JPEG, the maintainer's
  own, CC BY-NC-ND 4.0); `WALLPAPER` defaults to `default` = the 1080
  one from the clone, `spark-shell desktop wallpaper default` returns to
  it, `none` and a PATH as before.

## v0.20

- The look follows the palette by itself: the login profiles run
  `spark-shell follow`, which re-renders the user's files when
  theme.env changed since the last render (a cksum stamp in
  ~/.local/state/spark-shell/theme.seen) and says so in one line;
  quiet otherwise. `spark theme nord` had left sway's border and
  foot's background in gruvbox through a reboot, waiting for an apply
  nobody had been told to run. The login box (root's files) still
  follows at `spark-shell apply`.

## v0.19

- `vi` as a safety net (`ex-vi-compat` on Arch, `vim-tiny` on Debian,
  in `PKG_SHELL`): what falls back to vi when EDITOR is unset (yazi,
  git, crontab, visudo) opened nothing on a minimal Arch. The editor
  you use stays yours (`~/.config/spark-shell/rc`).

## v0.18

- `~/.config/spark-shell/rc`: yours, sourced last by both rc files,
  never written here. The rc files are spark-shell's symlinks, so a
  line of your own (`export EDITOR=micro`; yazi's Enter on a file was
  exit 127 without one) had nowhere to live.

## v0.17

- The login box's Enter runs `spark-shell desktop` too (tuigreet's
  `--cmd`), not bare sway: v0.12 wrapped only the F3 session, so the
  default still spilled sway's stderr onto tty1 at every reboot.

## v0.16

- yazi, the file manager, joins the tools: a package on Arch
  (`PKG_CLI`) and Homebrew; on Debian, which has none, a pinned
  release (26.9.1, sha256, `yazi` and `ya` into ~/.local/bin, unzipped
  -- `unzip` joins `PKG_CLI` on both distros). A rendered
  `~/.config/yazi/theme.toml`: no icon glyphs (they want a Nerd Font),
  the accent word on the current directory. The `tools` rows name it.
- The login box's fire was not lit: tuigreet prints its help on stderr,
  so the flag check saw nothing. Read.

## v0.15

- The login box burns: tuigreet's DOOM fire (`--background doom`) in
  the palette, where the installed tuigreet knows the flag (0.11 and
  newer; Debian 13's 0.9 gets the plain box). About six percent of one
  core while the box waits, nothing once you are in; F4 switches it for
  one boot.

## v0.14

- foot over a wallpaper is `alpha=0.95` (was 0.9): a bright picture
  read through the text more than the number suggested.

## v0.13

- `spark-shell desktop wallpaper PATH|none`: a picture behind the
  windows. `WALLPAPER` in the config; sway `output * bg "PATH" fill`
  with gaps 8/12, foot `alpha=0.9` (opaque and edge to edge with
  `none`, as before); a live sway reloads; the verb bare names the
  current one; a missing file falls back to the palette's colour with a
  `todo` row, and a path is refused unless absolute and readable. A
  `wall` status row.

## v0.12

- The login box's desktop session is `spark-shell desktop` (the clone's
  path), not bare `sway`: sway's and foot's stderr go to
  `~/.local/state/spark-shell/sway.log` and the cursor comes back, the
  same as starting it by hand. A reboot from inside the desktop had
  printed foot's broken-pipe lines on tty1.

## v0.11

- `spark-shell desktop on|off`: the desktop and the login box together.
  `on` writes `DESKTOP=sway` into the config (the file made if missing,
  the one line replaced, every other kept) and takes the path `on` takes
  with it (`desktop_apply`, one code path for `on`, `apply` and this
  verb): the packages, foot.ini and sway/config, and now the login box.
  `off` writes `DESKTOP=none`, hands the two renders back and undoes the
  box; packages stay. `spark-shell desktop` alone still starts sway now.
- The login box: greetd with tuigreet on tty1 (`PKG_GREETER` in
  `distro/*.env`: greetd + greetd-tuigreet on Arch, greetd + tuigreet on
  Debian 13; names verified 2026-09-20; none on Ubuntu LTS). A small box
  on the themed console -- the machine's short name, Login, Password,
  the clock -- drawn in the palette's slots as ratatui's colour words
  (`tui_name`, the placeholders `@ACCENT_TUI@ @MUTED_TUI@ @BG_TUI@
  @FG_TUI@`; BG and FG by their nearest slot, `default` = black and
  gray). Enter is the desktop (sway), F2 the console session (a login
  shell on tty1); `--remember`, `--remember-session`.
- Root renders, a new class: `/etc/greetd/config.toml`, the two session
  files in `/etc/greetd/spark-shell/`, and a `greetd.service` drop-in
  (`After=spark-console.service`, so the first frame is already in the
  palette). Written through sudo only when the render differs from the
  disk; `--dry-run` says `would`; no sudo to be had is a `todo` row. A
  config.toml that is not ours goes to `config.toml.spark-orig` once and
  comes back on off. Then `systemctl enable greetd.service` and
  `disable getty@tty1.service` (greetd first, so tty1 never loses its
  login), and the reverse on off -- never a start or stop: greetd takes
  tty1 at the next boot, the session this runs in is not touched.
- `apply` re-renders the root files too: a palette change reaches the
  login box. `status`'s desk row adds `login box: greetd at boot` or
  `getty`; `check` gains a `greeter` row (`na` with DESKTOP=none and on
  macOS; the files, the render and the two unit states, remedy
  `spark-shell desktop on`). `off` undoes the box as well.
- `SPARK_SHELL_ROOT=DIR` (tests only): every root path under DIR, plain
  writes, systemctl from PATH. The suite runs in a throwaway root as it
  does in a throwaway HOME; a stub systemctl logs its calls. CI gains a
  `debian:13` job, where distro/debian.env's names are looked up (the
  apt-cache step leaves the Ubuntu job: no tuigreet there); the Arch
  job looks up PKG_GREETER too. The e-mail gate (hook and CI) no longer
  reads a systemd instance name (`getty@tty1.service`) as an address.

## v0.10

- The plain look is for the look, not for content. tmux is told foot can
  take RGB (`terminal-features ",foot*:RGB"`), so a picture or text art
  drawn in a pane keeps its colours under the desktop instead of being
  approximated to 256. Every rendered file still names slots only; on
  the console nothing changes, there is no RGB to take.

## v0.9

- foot: `pad=4x4 center`. A grid never fills a window exactly; foot put
  the pixels left over at the bottom, and with 8 px of padding that read
  as a blank line under the last row (23 px at 1920x1080, cell 10x19).
  Four pixels and `center` split what is left evenly, one more row.

## v0.8

- The desktop ends with its first terminal: `exit` in the foot it opened
  is the console again (sway's `exec` runs `foot; swaymsg exit`). An
  empty sway was a black screen with nothing to type into; Super+Shift+e
  still works, Super+Return still opens more windows.
- foot.ini names ONE colour section, for the foot installed: `[colors]`
  before foot 1.26 (Debian 13 has 1.21), `[colors-dark]` from 1.26 on
  (Arch has 1.28) -- v0.6 rendered both, and foot 1.28 shows an
  "invalid section name: colors" error in the window for the one it
  dropped (`foot_colors`, from `foot --version`; 1.26+ when foot is not
  there yet, as in a dry run).

## v0.7

- The starship prompt is starship's again: the `spark MODEL` /
  `spark down` segment of v0.5 is gone from both styles (too much on
  the prompt line). The three colour exports stay; spark's prompt cache
  is still written by spark, read by nothing here.

## v0.6

- A desktop. `DESKTOP=sway` in the config and `on` installs sway, foot
  and DejaVu Sans Mono from the distro (`PKG_DESKTOP` in
  `distro/*.env`; names verified on Debian 13 and Arch, 2026-09-20) and
  renders `~/.config/foot/foot.ini` and `~/.config/sway/config`;
  `apply` re-renders them (and `swaymsg reload`s a running sway); `off`
  hands both back, marker-guarded like every render. `spark-shell
  desktop` starts sway on this console, as a child: its stderr goes to
  `~/.local/state/spark-shell/sway.log`, the cursor is put back on the
  console after it exits, its exit status is ours. It refuses, one line
  each, on macOS, with `DESKTOP=none`, without sway, without the
  renders, inside a desktop already (`WAYLAND_DISPLAY`), and without a
  seat (`XDG_VTNR` unset: ssh has no seat, a console login does).
  `status` gains a `desk` row, `check` a `desktop` row (`na` with
  `DESKTOP=none` and on macOS). Default `none`: nothing changes for a
  box that has not asked.
- The HEX class. foot is the desktop's twin of the console palette: the
  one surface that gives the sixteen slots their colours, so it, and
  sway's borders beside it, take the palette's own rrggbb
  (`HEX_BG`, `HEX_FG`, `HEX_ACCENT`, `HEX_MUTED`, `HEX_ANSI_0..15`,
  filled at the end of `theme_load`: a `#rrggbb` stripped, a colour
  word the VGA sixteen that `spark theme none` programs). The templates
  carry `@HEX_*@` placeholders and the hex lands at render time, so the
  gate's rule stays: no hex in a template, every other render still
  names slots. foot's colours sit in `[colors]` (foot 1.21, Debian 13)
  and `[colors-dark]` (foot 1.26 and newer; Arch ships 1.28, which
  dropped `[colors]`): each foot reads the section it knows and logs
  the other to stderr once, nothing in the window.
- `FONT` in the config (foot's own spec; default `DejaVu Sans
  Mono:size=12`). On Arch, sway depends on the virtual `ttf-font`:
  `ttf-dejavu` provides it, `ttf-jetbrains-mono` does not (pacman would
  add a second family on its own), which is why the desktop's face is
  DejaVu.
- sway stays bare, since tmux owns the terminal: no bar (the tmux line
  is the bar), no titlebars (`default_border pixel 2`), no xwayland; a
  new window is foot running the login shell, never tmux itself. The
  keys are i3's. Every directive used is in sway 1.10 (Debian 13) and
  1.12 (Arch).

## v0.5

- The prompt's colour. `on` and `apply` render
  `~/.config/spark-shell/sgr.sh`, three exports from the palette slots
  (`SPARK_ACCENT_SGR='1;<code>'`, `SPARK_MUTED_SGR='<code>'`,
  `SPARK_WARN_SGR='1;31'`; a slot below 8 is 30+n, above is 82+n, so
  console-safe 30-37 and 90-97 only, bold at most), and the rc files
  source it right before spark's hook line. spark 1.41 or newer reads
  them at a tty and paints its hint row, `spark chat` and `spark do`
  with them; a pipe never sees them, and without the file the prompt
  stays plain. `off` removes the render; `spark-shell status` names the
  pair beside the slots (`SGR 1;91 / 90`). The interface stays one file
  each way: spark writes `theme.env`, spark-shell writes `sgr.sh`.
- A spark segment in starship, both styles, right before the `>`:
  `spark MODEL` in the accent while spark answers, `spark down` in red
  when it stopped, nothing when spark is not there. It reads spark's own
  prompt cache (`~/.local/state/spark/prompt`, KEY=value) with sh
  builtins -- one `sh` per module, no python on a prompt -- and draws
  its space only when it has something to say. The blank hint row above
  stays.

## v0.4

- No editor. spark-shell installs no editor (it never did) and now
  configures none either: no `EDITOR=micro` in the rc files, no
  `editor = micro` in the rendered .gitconfig, no micro colorscheme and
  no seed in micro's settings.json. An editor's look is its own plugin's
  business (spark-micro), and which editor you use is yours. What v0.2
  rendered is handed back once: a `spark.micro` it wrote is removed and
  the `colorscheme` key it seeded is dropped, so micro never points at a
  scheme that is gone.

## v0.3

- No guessed git identity. A `.gitconfig` is rendered only when both
  `GIT_NAME` and `GIT_EMAIL` are in the config (typed, or seeded from an
  old site.env); unset, none is written and git's identity is yours to
  set. A `.gitconfig` you already have is never touched, even with an
  identity in the config. v0.2 wrote `<user> <user@host>` on a machine
  with neither, which is nobody's identity.
- No projects folder. `on` no longer makes `~/projects`, the `WORKSPACE`
  key is gone (an old one in the config is ignored), and `check` has no
  backup row scanning it: where your work lives is not the look's
  business.

## v0.2

- The Nerd Font is gone: `on` no longer downloads it, `check` has no
  font row, the Brewfile has no cask, and `unzip` and `fontconfig` left
  the package lists (they served only the font). A machine that is a
  bare Linux console cannot draw a `.ttf`, and the look below no longer
  needs one anywhere. A font directory an earlier `on` left at
  `~/.local/share/fonts/JetBrainsMonoNerdFont` is not touched -- nothing
  spark-shell did not render is ever removed; `rm -r` it and `fc-cache
  -f` if you want it gone.
- One plain look: every render draws with ASCII and names colours by
  palette slot, never by hex -- tmux without the truecolor override and
  without the console hook (`colour0`..`colour15` need none), starship
  with ASCII git marks and its colour words, btop in `force_tty` with
  tty graphs, micro's colorscheme in its sixteen colour words, bat on
  its `ansi` theme with numbers only, fzf with `--no-unicode
  --color=16`. The accent and the muted tone become the nearest of the
  palette's sixteen at render time (`spark-shell status` names the
  pair); spark's `theme.env` is read as before. `MICRO_TRUECOLOR` is no
  longer exported, and the status line asks `spark bar line` with
  `SPARK_ASCII=1`.
- `apply` and `on` also unset, in a running tmux, what the v0.1 render
  had set and a reload cannot undo (the console hook, the appended
  truecolor override), so the new look lands without a restart.
- The rc files carry spark's one marked hook line (`config/spark/hook.`)
  instead of sourcing its widget and completion themselves: spark's rc
  row sees the marker and never appends a second line -- which, with
  `~/.bashrc` a symlink into this clone, used to land in the tracked
  template and dirty the checkout.

## v0.1

- The shell layer, out of spark and on its own: everything spark
  v1.19's `spark shell on` did lives here now -- the tools (tmux,
  starship, fzf, zoxide, eza, bat, btop), the JetBrainsMono Nerd Font,
  the terminfo entry, the rc files, and the rendered look (tmux,
  starship, btop, micro's colorscheme) painted from spark's
  `theme.env`.
- One command: `spark-shell on|off|status|apply|check|bar`. `apply` is
  the second half of `spark theme NAME`; `off` hands everything back
  from `.bak`, or removes what had no before -- never an empty husk.
- Choices in `~/.config/spark-shell/config` (PROMPT, PROMPT_STYLE,
  WORKSPACE, GIT_NAME, GIT_EMAIL), seeded once from spark's site.env
  on a machine that ran the old layer; files the old layer rendered
  are adopted in place.
