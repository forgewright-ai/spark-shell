# Credits

spark-shell stands on other people's work. Every program here comes
from a package manager's own repositories, unpinned. The palettes are
color values, credited below.

## The logo

The S in `assets/` is spark's own block letter, from
https://github.com/forgewright-ai/spark -- MIT. spark-shell adds the
prompt sign and the cursor cell.

## The prompt

- starship -- https://github.com/starship/starship -- ISC, (c) Starship
  Contributors. From Arch's extra repository (pacman), from Void's
  (xbps) and from Homebrew.

## The tools

Installed from apt's, pacman's, xbps's or Homebrew's own
repositories, unpinned. The editor you use is yours, and its spark
plugin is its own repository with its own credits.

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
- kbd -- https://kbd-project.org/ -- GPL-2.0-or-later. `setvtrgb` for
  the console palette, and `setfont` and the console fonts, on Linux.

## The desktop

With DESKTOP=sway, from apt, pacman or xbps.

- sway -- https://github.com/swaywm/sway -- MIT.
- wlroots -- https://gitlab.freedesktop.org/wlroots/wlroots -- MIT.
  sway's library, pulled by the package.
- swaybg -- https://github.com/swaywm/swaybg -- MIT. The background:
  its own package on Arch and Void, pulled by sway on Debian.
- foot, foot-terminfo -- https://codeberg.org/dnkl/foot -- MIT.
- DejaVu fonts -- https://dejavu-fonts.github.io -- Bitstream Vera
  licence (ttf-dejavu on Arch, fonts-dejavu-core on Debian,
  dejavu-fonts-ttf on Void).
- seatd -- https://git.sr.ht/~kennylevinsen/seatd -- MIT. On Void,
  which has no logind, it gives sway the screen and keyboard.
- greetd -- https://git.sr.ht/~kennylevinsen/greetd -- GPL-3.0. With
  LOGIN=yes (spark-shell on login), it runs the login screen on tty1
  and starts your session after it. spark-shell talks to it over its
  socket and ships none of its code.
- curl -- https://curl.se -- curl licence (MIT-style). Fetches the
  dialog's release file.
- OpenSSH (openssh, openssh-client on Debian) -- https://www.openssh.com --
  BSD-style. ssh-keygen checks a release tag's signature.
- Mesa -- https://mesa3d.org -- MIT. mesa-dri on Void, the graphics
  drivers sway draws with.

## The dialog

`spark-dialog`, built from `dialog/` with crates from crates.io, each
pinned by `dialog/Cargo.lock`. The release's `spark-dialog.cdx.json`
lists every one with its licence (93 today: MIT, Apache-2.0, Zlib and
Unicode-3.0). The ones it is made of:

- ratatui -- https://github.com/ratatui/ratatui -- MIT. The drawing.
- crossterm -- https://github.com/crossterm-rs/crossterm -- MIT. The
  terminal.
- serde_json -- https://github.com/serde-rs/json -- MIT or Apache-2.0.
  The protocol's JSON.
- png -- https://github.com/image-rs/image-png -- MIT or Apache-2.0.
  The favicon, read for the logo in the about.
- unicode-width -- https://github.com/unicode-rs/unicode-width -- MIT or
  Apache-2.0. A character's cells.
- libc -- https://github.com/rust-lang/libc -- MIT or Apache-2.0. The
  clock and a signal.

## The palettes

The 16 palettes in `themes/`, written to `theme.env` by `spark-shell
theme NAME`. Color values only, no code copied, each file's first
line naming its upstream. The licence is the upstream's:

- Catppuccin -- https://github.com/catppuccin/catppuccin -- MIT.
- Dracula -- https://github.com/dracula/dracula-theme -- MIT.
- Everforest -- https://github.com/sainnhe/everforest -- MIT.
- Gruvbox -- https://github.com/morhetz/gruvbox -- MIT.
- Nord -- https://www.nordtheme.com -- MIT.
- One Light -- https://github.com/atom/atom, its One Light syntax -- MIT.
- Rose Pine -- https://github.com/rose-pine/rose-pine-theme -- MIT.
- Selenized -- https://github.com/jan-warchol/selenized -- MIT.
- Solarized -- https://ethanschoonover.com/solarized -- MIT.
- Tokyo Night -- https://github.com/folke/tokyonight.nvim -- Apache-2.0.

## The Terminal.app profile

`lib/terminal_profile.py` builds it with the Python 3 standard library
(macOS ships it) and hands it to Terminal.app with macOS's own
`defaults`, `plutil`, `osascript` and `mdfind`. Nothing is installed.

Built with Claude (Anthropic).
