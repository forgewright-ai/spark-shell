# Changelog

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
