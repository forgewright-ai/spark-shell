# Credits

spark-shell stands on other people's work. Everything here comes from
a package manager's own repositories, unpinned.

## The prompt

- starship -- https://github.com/starship/starship -- ISC, (c) Starship
  Contributors. From Arch's extra repository (pacman) and from Homebrew.

## The tools

Installed from apt's, pacman's or Homebrew's own repositories,
unpinned. The editor you use is yours, and its spark plugin is its own
repository with its own credits.

- bash -- GPL-3.0-or-later.
- tmux -- ISC.
- ncurses-bin -- MIT-style (ncurses).
- ncurses -- MIT-style (ncurses-bin, on Arch and Homebrew).
- diffutils -- GPL-3.0-or-later (on Arch).
- bat -- MIT/Apache-2.0.
- eza -- MIT.
- fzf -- MIT.
- zoxide -- MIT.
- fd-find -- MIT/Apache-2.0 (fd).
- fd -- MIT/Apache-2.0 (fd-find, on Arch and Homebrew).
- jq -- MIT.
- btop -- Apache-2.0.

## The desktop

With DESKTOP=sway, from apt or pacman.

- sway -- https://github.com/swaywm/sway -- MIT.
- wlroots -- https://gitlab.freedesktop.org/wlroots/wlroots -- MIT.
  sway's library, pulled by the package.
- swaybg -- https://github.com/swaywm/swaybg -- MIT. The background:
  its own package on Arch, pulled by sway on Debian.
- foot, foot-terminfo -- https://codeberg.org/dnkl/foot -- MIT.
- DejaVu fonts -- https://dejavu-fonts.github.io -- Bitstream Vera
  licence (ttf-dejavu on Arch, fonts-dejavu-core on Debian).

## The login box

With DESKTOP=sway, from apt or pacman.

- greetd -- https://git.sr.ht/~kennylevinsen/greetd -- GPL-3.0-only.
  The login daemon on tty1: 0.10.3 on Arch and Debian 13.
- tuigreet -- https://github.com/apognu/tuigreet -- GPL-3.0-only. The
  login box it draws: greetd-tuigreet 0.11.1 on Arch, tuigreet 0.9.1
  on Debian 13, not packaged on Ubuntu LTS.

## The palettes

The colours the look is rendered with come from
`~/.config/spark/theme.env`, written by `spark theme NAME`. The
palettes themselves live in spark's repository with their own credits
(github.com/forgewright-ai/spark, CREDITS.md).

## The wallpapers

`wallpapers/forge-1920x1080.jpg` and `forge-2560x1664.jpg`, the forge
wallpaper in two sizes, are the maintainer's own, CC BY-NC-ND 4.0
(https://creativecommons.org/licenses/by-nc-nd/4.0/).

Built with Claude (Anthropic).
