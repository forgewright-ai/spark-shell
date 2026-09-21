# Changelog

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
