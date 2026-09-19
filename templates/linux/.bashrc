# spark-shell ~/.bashrc -- bash 5 on Linux. Symlinked from the spark-shell repository:
# edit it there, and `git status` shows the change.
[[ $- == *i* ]] || return

# --- PATH first: everything below may depend on ~/.local/bin ---------------
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) PATH="$HOME/.local/bin:$PATH" ;; esac
export PATH
# micro is yours (spark-micro puts spark in it); the colorscheme rendered
# for it uses the 16 palette slots, so no truecolor flag
if command -v micro >/dev/null 2>&1; then export EDITOR=micro VISUAL=micro; fi

# --- history ---------------------------------------------------------------
HISTSIZE=20000 HISTFILESIZE=50000 HISTCONTROL=ignoreboth:erasedups
shopt -s histappend checkwinsize globstar autocd
bind 'set completion-ignore-case on' 2>/dev/null

# --- the daily tools, by their Debian names where those differ -------------
command -v fdfind >/dev/null && alias fd=fdfind
command -v batcat >/dev/null && alias bat=batcat
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

# --- fzf, zoxide -----------------------------------------------------------
for f in /usr/share/doc/fzf/examples/key-bindings.bash /usr/share/fzf/key-bindings.bash; do
    [ -r "$f" ] && { . "$f"; break; }
done

# --- prompt: starship when PROMPT=starship rendered a config ---------------
if [ -r ~/.config/starship.toml ] && command -v starship >/dev/null; then
    eval "$(starship init bash)"
else
    PS1='\n\u@\h:\w\$ '   # the blank row is where spark prints its hint
fi

# --- spark at the prompt: `? words` or `words?` + Enter; Esc a on any line -
# After fzf, so its Enter macro is the one that wins.
[ -r ~/.config/spark/widget.bash ] && . ~/.config/spark/widget.bash
[ -r ~/.config/spark/completion.bash ] && . ~/.config/spark/completion.bash

# zoxide last: its prompt hook has to be the final one, or it complains
command -v zoxide >/dev/null && eval "$(zoxide init bash)"
