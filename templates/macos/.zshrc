# spark-shell ~/.zshrc -- zsh on macOS. Symlinked from the spark-shell repository:
# edit it there, and `git status` shows the change.
[[ -o interactive ]] || return

# --- PATH first (Terminal.app opens login shells, so .zprofile ran; a plain
#     `zsh` did not) -------------------------------------------------------
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) PATH="$HOME/.local/bin:$PATH" ;; esac
export PATH

# --- history and completion ---------------------------------------------
HISTFILE=~/.zsh_history HISTSIZE=20000 SAVEHIST=50000
setopt hist_ignore_all_dups hist_ignore_space share_history
setopt auto_cd extended_glob
autoload -Uz compinit && compinit -d ~/.cache/zcompdump
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
bindkey -e

# --- the daily tools ------------------------------------------------------
if command -v eza >/dev/null; then
    alias ls='eza --group-directories-first'
    alias ll='eza -la --group-directories-first --git'
    alias lt='eza --tree -L 2'
else
    alias ll='ls -la'
fi
alias g=git
alias ..='cd ..'
alias check='spark check'

# --- one plain look: ASCII and the 16 palette slots, console or emulator -
export BAT_THEME=ansi BAT_STYLE=numbers              # 16-colour theme, no grid
export FZF_DEFAULT_OPTS='--no-unicode --color=16'    # fzf >= 0.38

# --- fzf, zoxide ----------------------------------------------------------
command -v fzf >/dev/null && source <(fzf --zsh)

# --- prompt: starship when PROMPT=starship rendered a config --------------
if [[ -r ~/.config/starship.toml ]] && command -v starship >/dev/null; then
    eval "$(starship init zsh)"
else
    PROMPT=$'\n%n@%m:%~%# '   # the blank row is where spark prints its hint
fi

# --- spark at the prompt: the colour it draws with (three exports from
#     the palette slots, rendered by spark-shell on), then its one
#     marked hook line (the widget, completion, the console palette). After
#     fzf, so its accept-line wrapper is the one spark wraps; spark's rc
#     row sees the marker and never appends a second.
[[ -r ~/.config/spark-shell/sgr.sh ]] && source ~/.config/spark-shell/sgr.sh   # spark-shell: the prompt's colour
[[ -r ~/.config/spark/hook.zsh ]] && source ~/.config/spark/hook.zsh   # spark: the AI at the prompt

# zoxide last: its prompt hook has to be the final one, or it complains
command -v zoxide >/dev/null && eval "$(zoxide init zsh)"

# --- yours: ~/.config/spark-shell/rc, sourced last, never written by
#     spark-shell (your editor, aliases, anything these files do not say)
[[ -r ~/.config/spark-shell/rc ]] && source ~/.config/spark-shell/rc
