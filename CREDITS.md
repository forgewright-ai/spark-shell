# Credits

spark-shell stands on other people's work. Everything here is fetched
from its own home, pinned by sha256 where a version is pinned at all.

## The prompt

starship -- https://github.com/starship/starship -- ISC
(c) Starship Contributors

Version 1.26.0 (`STARSHIP_VERSION` in `spark-shell`), pinned by sha256
on Linux; Homebrew installs the same tool on macOS with no version pin.

## The file manager

yazi -- https://github.com/sxyazi/yazi -- MIT
(c) sxyazi and contributors

A package on Arch and Homebrew; on Debian, which has none, version
26.9.1 (`YAZI_VERSION` in `spark-shell`), pinned by sha256, unzipped
into ~/.local/bin (yazi and ya).

## The tools (apt or pacman / Homebrew)

Installed from apt's, pacman's or Homebrew's own repositories,
unpinned. No editor is among them: an editor's spark plugin is its own
repository with its own credits.

- bash -- GPL-3.0-or-later
- tmux -- ISC
- ncurses-bin -- MIT-style (ncurses)
- ncurses -- MIT-style (ncurses-bin, on Arch)
- pacman-contrib -- GPL-2.0-or-later (`checkupdates`, on Arch)
- bat -- MIT/Apache-2.0
- eza -- MIT
- fzf -- MIT
- zoxide -- MIT
- ripgrep -- MIT/Unlicense
- fd-find -- MIT/Apache-2.0 (fd)
- fd -- MIT/Apache-2.0 (fd-find, on Arch)
- jq -- MIT
- btop -- Apache-2.0
- unzip -- Info-ZIP license (yazi's zip on Debian; archives in yazi)

## The desktop (apt or pacman, with DESKTOP=sway)

- sway -- https://github.com/swaywm/sway -- MIT
- wlroots -- https://gitlab.freedesktop.org/wlroots/wlroots -- MIT
  (sway's library; pulled by the package)
- swaybg -- https://github.com/swaywm/swaybg -- MIT (the background;
  its own package on Arch, pulled by sway on Debian)
- foot, foot-terminfo -- https://codeberg.org/dnkl/foot -- MIT
- DejaVu fonts -- https://dejavu-fonts.github.io -- Bitstream Vera
  license (ttf-dejavu on Arch, fonts-dejavu-core on Debian)

## The login box (apt or pacman, with DESKTOP=sway)

- greetd -- https://git.sr.ht/~kennylevinsen/greetd -- GPL-3.0-only
  (the login daemon on tty1; 0.10.3 on Arch and Debian 13)
- tuigreet -- https://github.com/apognu/tuigreet -- GPL-3.0-only (the
  box it draws; greetd-tuigreet 0.11.1 on Arch, tuigreet 0.9.1 on
  Debian 13; not packaged on Ubuntu LTS)

## The palettes

The colours the look is rendered with come from
`~/.config/spark/theme.env`, written by `spark theme NAME`; the
palettes themselves live in spark's repository with their own credits
(github.com/forgewright-ai/spark, CREDITS.md).

Built with Claude (Anthropic).
