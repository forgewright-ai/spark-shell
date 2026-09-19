# Changelog

## v0.2

- The Nerd Font is gone: `on` no longer downloads it, `check` has no
  font row, the Brewfile has no cask, and `unzip` and `fontconfig` left
  the package lists (they served only the font). A machine that is a
  bare Linux console cannot draw a `.ttf`, and the look below no longer
  needs one anywhere. A font directory an earlier `on` left at
  `~/.local/share/fonts/JetBrainsMonoNerdFont` is not touched -- nothing
  spark-shell did not render is ever removed; `rm -r` it and `fc-cache
  -f` if you want it gone.

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
