# Credits

spark-shell stands on other people's work. Everything here is fetched
from its own home, pinned by sha256 where a version is pinned at all.

## The prompt

starship -- https://github.com/starship/starship -- ISC
(c) Starship Contributors

Version 1.26.0 (`STARSHIP_VERSION` in `spark-shell`), pinned by sha256
on Linux; Homebrew installs the same tool on macOS with no version pin.

## Fonts

JetBrains Mono -- https://github.com/JetBrains/JetBrainsMono -- SIL Open
Font License 1.1, Reserved Font Name "JetBrains Mono"

Nerd Fonts -- https://github.com/ryanoasis/nerd-fonts -- MIT (the
patcher)

Nerd Fonts patches JetBrains Mono and renames the result "JetBrainsMono
Nerd Font" -- version 3.5.1 (`NERDFONT_VERSION` in `spark-shell`),
pinned by sha256 on Linux; Homebrew's font-jetbrains-mono-nerd-font cask
installs the same family on macOS with no version pin.

## The tools (apt or pacman / Homebrew)

Installed from apt's, pacman's or Homebrew's own repositories,
unpinned. No editor is among them: an editor's spark plugin is its own
repository with its own credits.

- bash -- GPL-3.0-or-later
- tmux -- ISC
- unzip -- Info-ZIP (the Nerd Font's archive)
- fontconfig -- MIT-style
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

## The palettes

The colours the look is rendered with come from
`~/.config/spark/theme.env`, written by `spark theme NAME`; the
palettes themselves live in spark's repository with their own credits
(github.com/forgewright-ai/spark, CREDITS.md).

Built with Claude (Anthropic).
