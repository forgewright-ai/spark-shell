# shellcheck extended-analysis=false
# --- setup: on, off, status and check
# sets: LAYOUT_SEEN SEEN
# reads: APPS CONFIG DESKTOP_RENDERED DIALOG_BIN DIALOG_URL DISTRO FAMILIES_SAID LAYOUTS_DIR LOGIN_ETC MODE NEON NEON_OLD NEON_VERSION OS PM PROVIDE_SECTIONS RENDERED REPO SEMANTIC_MODEL SPARK_CONFIG_DIR TERM_NAME THEME_ENV TMP WM_NAME YES
# `on` is the terminal seat, `on desktop` the seat and the desktop; `off
# desktop` takes the desktop back, `off` everything. The nouns are desktop
# and login; any other word is refused before a thing is touched.
noun_ok() {   # noun_ok on|off [WORD...]
    [ $# -gt 1 ] || return 0
    [ "$*" != "$1 desktop" ] && [ "$*" != "$1 login" ] || return 0
    _v=$1; shift; _w=$*
    case $_w in *[!\ ]*) ;; *) _w="an empty word" ;; esac
    echo "spark-shell $_v: $_w is not known here (only desktop and login are)"; exit 1
}
# on, on desktop and quiet boot on say what they change and ask first;
# --yes skips the question, --dry-run never asks. With no terminal and no
# --yes: one line and exit 1. The suite answers through stdin with
# SPARK_SHELL_TEST_TTY set.
asks() { [ "$MODE" = apply ] && [ "$YES" = 0 ]; }   # will this run ask?
ask_terminal() {   # before a word is printed: no terminal, one line and exit 1
    [ -t 0 ] || [ -n "${SPARK_SHELL_TEST_TTY:-}" ] || { echo "spark-shell: no terminal to ask on -- add --yes to go ahead"; exit 1; }
}
ask_continue() {   # the question; anything but y or yes stops here, nothing changed
    printf '\nContinue? [y/N] '
    if ! IFS= read -r _ans; then echo; _ans=''; fi
    case $_ans in y|Y|yes|Yes|YES) return 0 ;; esac
    echo "spark-shell: nothing was changed."; exit 1
}
warn_wrap() {   # warn_wrap LABEL WORDS... -- one row of the desktop list, wrapped within 80 columns
    _l=$1; shift
    printf '%s\n' "$*" | awk -v l="$_l" '{
        line = sprintf("  %-13s", l); n = length(line); first = 1
        for (i = 1; i <= NF; i++) {
            if (!first && n + 1 + length($i) > 79) { print line; line = sprintf("%15s", ""); n = 15; first = 1 }
            if (first) { line = line $i; n += length($i); first = 0 } else { line = line " " $i; n += 1 + length($i) }
        }
        print line }'
}
on_warning() {   # on_warning [desktop|login] -- at the very start of on: what it changes, then the question
    noun_ok on "$@"
    asks || return 0
    pm_detect
    if [ "${1:-}" = login ]; then
        [ -z "$(desktop_na)" ] || return 0   # refused next, before anything
        ask_terminal
        printf '%s\n' 'spark-shell on login changes how this machine starts:' ''
        # shellcheck disable=SC2086
        [ -z "$PKG_LOGIN$PKG_DESKTOP" ] || warn_wrap packages $PKG_LOGIN $PKG_DESKTOP '(sudo)'
        [ "$PM" != pacman ] || warn_wrap upgrade 'missing packages require a full system upgrade; pacman asks before applying it'
        warn_wrap login 'tty1 shows the login screen from the next boot'
        warn_wrap '' 'tty2 keeps the console login (Alt+F2)'
        warn_wrap files "/$LOGIN_ETC, greetd's config.toml (sudo)"
        if [ "$DISTRO" = void ]; then
            warn_wrap groups "adds $LOGIN_ACCOUNT to _seatd (sudo)"
            warn_wrap power "lets $LOGIN_ACCOUNT run reboot and poweroff, nothing else (sudo)"
        fi
        printf '\n%s\n%s\n' 'spark-shell off login puts the console login back.' 'Packages stay.'
        ask_continue
        return 0
    fi
    if [ "${1:-}" = desktop ]; then
        [ -z "$(desktop_na)" ] || return 0   # refused next, before anything
    fi
    ask_terminal
    if [ "$OS" = Darwin ]; then
        printf '%s\n' 'spark-shell replaces your shell files, installs packages and' \
            'a font, and changes the Terminal.app colors and font.' 'spark-shell on --dry-run shows every change.'
    elif [ "${1:-}" = desktop ]; then
        printf '%s\n' 'spark-shell replaces your shell files, installs packages' \
            'and changes the console colors.' 'spark-shell on desktop --dry-run shows every change.'
    else
        printf '%s\n' 'spark-shell replaces your shell files, installs packages' \
            'and changes the console colors. spark-shell on --dry-run' 'shows every change.'
    fi
    if [ "${1:-}" = desktop ]; then
        printf '\nspark-shell changes how this machine works:\n\n'
        # shellcheck disable=SC2086
        [ -z "$PKG_DESKTOP$PKG_SOUND" ] || warn_wrap packages $PKG_DESKTOP $PKG_SOUND '(sudo)'
        neon_pkg >/dev/null || warn_wrap font "Monaspace Neon $NEON_VERSION from GitHub to your fonts, sha256 checked"
        ! ( config_load; semantic_fetches ) >/dev/null 2>&1 || warn_wrap search "EmbeddingGemma 2 from Hugging Face, 310 MB, sha256 checked, for the dialog's search by meaning"
        warn_wrap login 'logging in on tty1 starts the desktop'
        warn_wrap '' 'Alt+F2 is a plain shell'
        if [ "$DISTRO" = void ]; then
            warn_wrap groups 'adds you to _seatd and audio (sudo)'
            warn_wrap services 'turns on seatd at boot (sudo)'
            if [ -d "$SPARK_CONFIG_DIR/sv" ]; then warn_wrap sound "PipeWire runs from boot, under spark's supervisor, and ALSA programs play through it (sudo)"
            else warn_wrap sound 'PipeWire starts with the desktop, and ALSA programs play through it (sudo)'; fi
            warn_wrap power 'lets you suspend, restart and shut down, nothing else (sudo)'
            warn_wrap drives 'lets you mount and eject USB drives (polkit, sudo)'
        fi
        printf '\n%s\n%s\n' 'spark-shell off desktop puts the login back.' 'Packages stay.'
    fi
    [ "$PM" != pacman ] || printf '\n%s\n' 'On Arch, missing packages require a full system upgrade; pacman asks first.'
    ask_continue
}
boot_warning() {   # boot_warning SHAPE -- before quiet boot on: what it changes, then the question
    asks || return 0
    ask_terminal
    printf '%s\n' 'spark-shell quiet boot on changes how this machine starts:' \
        'the boot menu is hidden, and the kernel and init are silent.'
    case $1 in
        grub) echo 'It adds a GRUB settings file and runs update-grub (sudo).' ;;
        uki) echo 'It edits the kernel command line and runs mkinitcpio -P (sudo).' ;;
        void) echo 'It edits the GRUB settings and the runit boot files (sudo).' ;;
    esac
    echo 'spark-shell quiet boot off puts it back.'
    ask_continue
}
cmd_on() {   # cmd_on [desktop|login]
    on_warning "$@"
    noun_ok on "$@"
    [ "${1:-}" != desktop ] || [ -z "$(desktop_na)" ] || refuse "$(desktop_na)"
    [ "${1:-}" != login ] || [ -z "$(login_na)" ] || refuse_in login "$(login_na)"
    config_load
    on_config "$@"
    sudo_upfront
    loud && printf '== packages\n'
    on_packages "$@"
    if [ "$MODE" != dry ]; then
        case ${1:-} in login) config_set LOGIN yes ;; desktop) config_set DESKTOP sway ;; esac
    fi
    # why the desktop's packages are not in the row above
    if _dna=$(desktop_na) && [ -n "$_dna" ]; then
        [ "$DESKTOP" != sway ] || skip desktop "$_dna"
    elif ! desktop_wanted; then
        skip desktop "DESKTOP=none (the config)"
    fi
    # the font after the packages, before anything renders FONT
    neon_install
    neon_move
    faces_install
    private_dirs
    loud && printf '\n== prompt\n'
    on_prompt
    on_terminfo
    loud && printf '\n== files\n'
    tree=$(rc_tree)
    for f in $(rc_files); do
        link_one "$tree/$f" "$HOME/$f"
    done
    theme_files   # the palette first: every render reads theme.env
    render_all
    old_greetd_off   # the login screen, handed back to getty
    if login_wanted; then login_screen_apply; else login_screen_off; fi
    # spark-shell on PATH, so the prompt and tmux can call it
    link_one "$REPO/spark-shell" "$HOME/.local/bin/spark-shell"
    tmux_reload
    loud && printf '\n== console\n'
    if [ "$THEME" = none ]; then palette_off all; fi
    console_apply
    if [ "$MODE" = dry ]; then
        dry_close
    else
        theme_seen
        console_now
        if [ "$changes" -eq 0 ] && [ "$todo" -eq 0 ]; then echo "Nothing to do"; else echo "open a new shell (exec \$SHELL)"; fi
    fi
}
on_config() {   # on_config [desktop|login] -- LOGIN=yes or DESKTOP=sway for this run; the config is written after the packages install
    if [ "${1:-}" = login ]; then
        if [ "$LOGIN" != yes ]; then
            if [ "$MODE" = dry ]; then row would config "LOGIN=yes ($CONFIG)"; else changes=$((changes + 1)); fi
        fi
        LOGIN=yes; export LOGIN
    fi
    if [ "${1:-}" = desktop ]; then
        if [ "$DESKTOP" != sway ]; then
            if [ "$MODE" = dry ]; then row would config "DESKTOP=sway ($CONFIG)"; else changes=$((changes + 1)); fi
        fi
        DESKTOP=sway; export DESKTOP
    fi
}
on_packages() {   # on_packages [desktop|login] -- the packages row: the lists installed, or a todo; a return of 1 ends the run (set -e) before any file changes
    pm_detect
    if [ "$PM" = brew ]; then
        if ! command -v brew >/dev/null 2>&1; then
            row todo packages "Homebrew is not installed: https://brew.sh (then run again)"
        elif brew bundle check --file "$REPO/distro/brewfile" --no-upgrade >/dev/null 2>&1; then
            ok packages "distro/brewfile satisfied"
        elif need packages "brew bundle --file distro/brewfile"; then
            brew bundle --file "$REPO/distro/brewfile" --no-upgrade
            ok packages "distro/brewfile satisfied"
        fi
    elif [ -z "$PM" ]; then
        row todo packages "no package list for this Linux: spark-shell knows $FAMILIES_SAID"
    else
        missing=''
        pkgs="$PKG_SHELL $PKG_CLI $PKG_CONSOLE"
        if desktop_wanted || login_wanted; then pkgs="$pkgs $PKG_DESKTOP"; fi
        if desktop_wanted; then pkgs="$pkgs $PKG_SOUND"; fi
        # pulseaudio stays until its replacement is chosen
        if [ "$PM" = pacman ] && desktop_wanted && pkg_installed pulseaudio; then
            pkgs=$(printf '%s\n' $pkgs | grep -vx pipewire-pulse | paste -sd ' ' -)
            row todo sound "pulseaudio is installed, and pipewire-pulse takes its place -- sudo pacman -S pipewire-pulse (it asks before removing pulseaudio)"
        fi
        if login_wanted; then pkgs="$pkgs $PKG_LOGIN"; fi
        # shellcheck disable=SC2086
        for p in $pkgs; do pkg_installed "$p" || missing="$missing $p"; done
        _again="spark-shell on${*:+ $*}"
        if [ -z "$missing" ]; then ok packages "installed"
        elif pkg_nobody; then
            # nobody to type a password: a desktop or a login asked for waits
            # for its packages; anything else goes on, as update must
            _why='sudo once'; [ "$PM" != pacman ] || _why='pacman asks before it upgrades'
            case ${1:-} in desktop|login) if [ "$MODE" != dry ]; then
                row todo packages "still to install:$missing -- $_again at a terminal ($_why)"
                echo 'spark-shell: the packages are not in; setup stopped before changing shell or desktop files.' >&2
                return 1
            fi ;; esac
            row todo packages "still to install:$missing -- $_again at a terminal ($_why); the links and renders need no root, so they go on"
        else
            _install="install$missing ($PM, sudo)"
            [ "$PM" != pacman ] || _install="full system upgrade and install$missing (pacman -Syu --needed, sudo; pacman asks first)"
            if need packages "$_install"; then
                # shellcheck disable=SC2086
                if pkg_install_on $missing; then ok packages "installed"
                else
                    if _up=$(pkg_update_said) && [ -n "$_up" ]; then row todo packages "$PM could not install:$missing -- $_up, then $_again"
                    else row todo packages "$PM failed (see above) -- run $_again again"; fi
                    echo 'spark-shell: package installation failed; setup stopped before changing shell or desktop files.' >&2
                    return 1
                fi
            fi
        fi
    fi
}
on_prompt() {   # the prompt row: starship from the package manager alone, nothing downloaded. A skip, not a todo: Debian's dry-run still ends in Nothing to do
    if [ "$PROMPT" != starship ]; then skip prompt "PROMPT=$PROMPT (the config): the shell's own"
    elif command -v starship >/dev/null 2>&1 || [ -x "$HOME/.local/bin/starship" ]; then
        v=$(PATH=$HOME/.local/bin:$PATH starship --version 2>/dev/null | head -1)
        ok prompt "${v:-starship} draws the prompt"
    elif starship_listed; then skip prompt "starship comes with the packages above"
    else skip prompt "no starship package here: the shell's own prompt (the rc files draw it)"
    fi
}
on_terminfo() {   # the terminfo row: tmux-256color must know modified arrow keys
    if infocmp -1x tmux-256color 2>/dev/null | grep -q 'kUP='; then
        ok terminfo "tmux-256color knows modified arrow keys"
    elif [ "$OS" = Darwin ]; then
        nc=$(brew --prefix ncurses 2>/dev/null || true)
        if [ ! -x "$nc/bin/infocmp" ]; then skip terminfo "Homebrew ncurses not installed yet"
        elif need terminfo "compile tmux-256color from Homebrew ncurses into ~/.terminfo"; then
            "$nc/bin/infocmp" -x tmux-256color > "$TMP/tmux.ti"
            tic -x -o "$HOME/.terminfo" "$TMP/tmux.ti"
            ok terminfo "compiled into ~/.terminfo"
        fi
    else
        skip terminfo "tmux-256color lacks kUP here -- a newer ncurses-term has it"
    fi
}

cmd_off() {   # cmd_off [desktop|login]
    noun_ok off "$@"
    [ "${1:-}" != desktop ] || [ -z "$(desktop_na)" ] || refuse "$(desktop_na)"
    [ "${1:-}" != login ] || [ -z "$(login_na)" ] || refuse_in login "$(login_na)"
    config_load
    [ "$OS" = Darwin ] || pm_detect
    if [ "$MODE" = dry ]; then off_would "${1:-}"; return 0; fi
    if [ "${1:-}" = login ]; then
        config_set LOGIN no
        LOGIN=no; export LOGIN
        login_screen_off
        echo "packages stay installed -- the package manager removes them if you want"
        return 0
    fi
    if [ "${1:-}" = desktop ]; then
        config_set DESKTOP none
        DESKTOP=none; export DESKTOP
        hand_back $DESKTOP_RENDERED .config/starship-foot.toml .config/alsa/asoundrc
        user_dirs_off
        portal_off
        pointer_off
        old_greetd_off
        seat_off
        sound_off
        light_off
        storage_off
        power_off
        mcp_off
        semantic_off
        machine_off
        echo "packages stay installed -- the package manager removes them if you want"
        return 0
    fi
    for f in $(rc_files); do
        p=$HOME/$f
        # only spark-shell's own symlink is handed back
        if [ -L "$p" ]; then
            case $(readlink "$p") in "$REPO"/*) restore_one "$p" ;; esac
        fi
    done
    hand_back $RENDERED .config/starship.toml .config/starship-foot.toml .config/yazi/theme.toml $DESKTOP_RENDERED .config/alsa/asoundrc   # alsa: the bar's default card; yazi: a render no longer made, its.bak yours
    [ "$OS" = Darwin ] || user_dirs_off
    portal_off
    [ "$OS" = Darwin ] || pointer_off
    old_greetd_off
    login_screen_off
    seat_off
    sound_off
    light_off
    storage_off
    power_off
    mcp_off
    semantic_off
    machine_off
    pm_detect
    console_off   # the palette, the font, the login screen and the boot, as they were
    # spark's hook line survives the hand-back when spark is installed here
    hook_line=''
    case $OS in
        Darwin) [ -r "$SPARK_CONFIG_DIR/hook.zsh" ] && hook_line='[[ -r ~/.config/spark/hook.zsh ]] && source ~/.config/spark/hook.zsh   # spark: the AI at the prompt' ;;
        *) [ -r "$SPARK_CONFIG_DIR/hook.bash" ] && hook_line='[ -r ~/.config/spark/hook.bash ] && . ~/.config/spark/hook.bash   # spark: the AI at the prompt' ;;
    esac
    if [ -n "$hook_line" ]; then
        case $OS in Darwin) rcf=$HOME/.zshrc ;; *) rcf=$HOME/.bashrc ;; esac
        if ! grep -q 'config/spark/hook\.' "$rcf" 2>/dev/null; then
            printf '%s\n' "$hook_line" >> "$rcf"
            row ok rc "$rcf -- spark's hook line kept"
        fi
    fi
    tmux_reload
    console_now
    echo "packages stay installed -- the package manager removes them if you want"
    echo "open a new shell (exec \$SHELL)"
}

# The dry run of off: would rows, nothing touched, by the same gates as
# the real run.
off_would() {   # off_would [desktop|login]
    if [ "${1:-}" = login ]; then
        [ "$LOGIN" = no ] || row would config "LOGIN=no ($CONFIG)"
        login_screen_off
        dry_close
        return 0
    fi
    _mo=$(mcp_mine); [ -z "$_mo" ] || row would mcp "take$_mo off spark's MCP list"
    semantic_off
    ! machine_there || row would machine "remove what the desktop told spark's prompt line ($(files_home "$(machine_dir)"))"
    if [ "${1:-}" = desktop ]; then
        [ "$DESKTOP" = none ] || row would config "DESKTOP=none ($CONFIG)"
        list=$DESKTOP_RENDERED
    else
        for f in $(rc_files); do
            p=$HOME/$f
            [ -L "$p" ] || continue
            case $(readlink "$p") in "$REPO"/*) row would rc "$p" ;; esac
        done
        # the one write off may do: spark's hook line into the rc file it leaves
        case $OS in Darwin) hook=hook.zsh; rcf=$HOME/.zshrc ;; *) hook=hook.bash; rcf=$HOME/.bashrc ;; esac
        if [ -r "$SPARK_CONFIG_DIR/$hook" ]; then
            after=$rcf; if [ -L "$rcf" ]; then case $(readlink "$rcf") in "$REPO"/*) after=$rcf.bak ;; esac; fi
            grep -q 'config/spark/hook\.' "$after" 2>/dev/null || row would rc "$rcf -- spark's hook line kept"
        fi
        list="$RENDERED .config/starship.toml .config/yazi/theme.toml $DESKTOP_RENDERED"
    fi
    for rel in $list; do
        p=$HOME/$rel
        [ -f "$p" ] && [ ! -L "$p" ] || continue
        grep -q 'rendered by spark-shell' "$p" 2>/dev/null || [ -e "$p.bak" ] || continue
        if [ -e "$p.bak" ]; then row would restore "$p -- back from ${p##*/}.bak"
        else row would restore "$p -- removed (no ${p##*/}.bak: there was no file before)"; fi
    done
    old_greetd_off
    [ "${1:-}" = desktop ] || login_screen_off
    seat_off
    sound_off
    light_off
    storage_off
    power_off
    if [ "${1:-}" != desktop ]; then pm_detect; console_off; fi
    dry_close
}

# `spark-shell follow`, run by the login profile, re-renders the user's
# files when theme.env changed since the last render (one cksum when not).
SEEN=${XDG_STATE_HOME:-$HOME/.local/state}/spark-shell/theme.seen
theme_sum() { if [ -f "$THEME_ENV" ]; then cksum < "$THEME_ENV" | cut -d' ' -f1; else echo none; fi; }
theme_seen() { mkdir_private "$(dirname "$SEEN")"; theme_sum > "$SEEN"; }
cmd_follow() {
    config_load
    [ "$(theme_sum)" != "$(cat "$SEEN" 2>/dev/null)" ] || return 0
    theme_load
    EXPR=$(render_expr)
    for rel in $RENDERED; do render_one "$REPO/template/$rel" "$HOME/$rel" >/dev/null; done
    prompt_render >/dev/null
    if desktop_wanted; then
        for rel in $DESKTOP_RENDERED; do render_one "$REPO/template/$rel" "$HOME/$rel" >/dev/null; done
        desktop_reload >/dev/null
    fi
    n=$changes
    tmux_reload >/dev/null 2>&1 || true
    theme_seen
    [ "$n" -eq 0 ] || echo "spark-shell: $n files updated for the new palette."
}

# The desktop's keys are the `# key: ` sentences in the sway template, one
# source (the README carries them verbatim and the suite holds it to them).
LAYOUT_SEEN=${XDG_STATE_HOME:-$HOME/.local/state}/spark-shell/desktop.seen
layout_keys() { python3 "$REPO/lib/home.py" keys "$(wm_config_template)"; }
status_next() {   # the first sentence that applies, as a next row; nothing off, no row
    if [ -z "$(spark_bin)" ]; then n=spark; s="Install spark, the local AI: github.com/forgewright-ai/spark."
    elif [ -n "$(desktop_na)" ]; then return 0
    elif [ "$DESKTOP" = none ]; then [ -d /dev/dri ] || return 0; n=desktop; s="spark-shell on desktop adds the desktop."
    elif [ -n "$(desktop_tools)" ]; then n=desktop; s="spark-shell on installs $WM_NAME and $TERM_NAME."
    elif [ ! -f "$(wm_config_file)" ] || [ ! -f "$(term_config_file)" ]; then n=desktop; s="spark-shell on writes the $WM_NAME and $TERM_NAME settings."
    elif seat_needed && ! seat_ready; then n=desktop; s="spark-shell on desktop at a terminal sets up seatd (sudo once)."
    elif seat_needed && ! id -Gn | tr ' ' '\n' | grep -qx _seatd; then n=desktop; s="Log out and in again: the _seatd group takes effect at the next login."
    else return 0; fi
    printf '  next  %-16s %s\n' "$n" "$s"
}

cmd_status() {
    config_load
    tree=$(rc_tree)
    printf 'spark-shell status\n'
    for f in $(rc_files); do
        p=$HOME/$f
        if [ -L "$p" ] && [ "$(readlink "$p")" = "$tree/$f" ]; then s="spark-shell's"
        elif [ -L "$p" ]; then s="a symlink elsewhere"
        elif [ -f "$p" ]; then grep -q 'config/spark/hook\.' "$p" 2>/dev/null && s="yours, with spark's hook" || s="yours"
        else s="absent"; fi
        # shellcheck disable=SC2088   # the tilde is display, not a path
        printf '  rc    %-16s %s\n' "~/$f" "$s"
    done
    pm_detect
    for t in tmux starship fzf zoxide eza bat btop fd; do
        tool_here "$t" && s=yes || s=no
        printf '  tool  %-16s %s\n' "$t" "$s"
    done
    theme_load || true   # the wall row below names the ground's hex
    if s=$(desktop_na) && [ -n "$s" ]; then :
    elif [ "$DESKTOP" = none ]; then s="none (spark-shell on desktop)"
    elif [ -n "$(desktop_tools)" ]; then s="$WM_NAME: not installed --$(desktop_tools) (spark-shell on desktop)"
    elif [ ! -f "$(wm_config_file)" ] || [ ! -f "$(term_config_file)" ]; then s="$WM_NAME: settings not written (spark-shell on)"
    else _fs=$(font_spec); s="$WM_NAME: ready, $TERM_NAME uses $(fc-match -f '%{family}' "$_fs" 2>/dev/null || printf '%s' "${_fs%%:*}") (log in on tty1 to start it)"; fi
    printf '  desktop %-14s %s\n' "$DESKTOP" "$s"
    status_login
    n=$(ls -A "$LAYOUTS_DIR" 2>/dev/null | wc -l | tr -d ' ')   # a saved layout opens as tmux windows anywhere
    if [ "$n" -gt 0 ]; then printf '  layouts %-14s %s\n' "$n saved" "$(ls -A "$LAYOUTS_DIR" | paste -sd ',' - | sed 's/,/, /g') (spark-shell layout NAME)"
    else printf '  layouts %-14s %s\n' none 'spark-shell layout "WORDS" makes one'; fi
    if [ "$OS" != Darwin ] && [ "$DESKTOP" = sway ]; then
        if apps_marked; then printf '  apps  %-16s %s\n' "$(grep -c '^[A-Za-z0-9]' "$APPS") allowed" "$(grep '^[A-Za-z0-9]' "$APPS" | sed 's/[: ].*//' | paste -sd',' - | sed 's/,/, /g') (spark-shell apps)"
        else printf '  apps  %-16s %s\n' all "every app with a desktop entry (spark-shell apps picks the allowed apps)"; fi
        if [ "$WALLPAPER" = none ]; then printf '  wall  %-16s %s\n' none "the palette's background (spark-shell theme wallpaper PATH|default)"
        elif wall_color; then printf '  wall  %-16s %s\n' color "$WALLPAPER, a plain color; a palette with a drawing of its own replaces it"
        elif [ "$WALLPAPER" = default ]; then printf '  wall  %-16s %s\n' default "the ground, the palette's background a shade darker ($(wall_ground)); it follows the palette"
        elif wall_there; then printf '  wall  %-16s %s\n' picture "$WALLPAPER"
        else printf '  wall  %-16s %s\n' missing "$(wall_path) is missing -- the palette's background color instead"; fi
        if [ "$DESKTOP_BAR" = yes ]; then printf '  bar   %-16s %s\n' shown "$(bar_place_words "$BAR_POSITION"): $(bar_names) (spark-shell bar off --desktop hides it)"
        else printf '  bar   %-16s %s\n' hidden "spark-shell bar on --desktop shows it"; fi
    fi
    theme_load || true
    slots="accent slot ${ACCENT_SLOT:-?}, muted slot ${MUTED_SLOT:-?} (SGR 1;${ACCENT_SGR:-?} / ${MUTED_SGR:-?})"
    [ -f "$THEME_ENV" ] && printf '  theme %-16s %s\n' "${THEME:-theme.env}" "in use: $slots (spark-shell theme NAME changes it)" \
                        || printf '  theme %-16s %s\n' "${THEME:-theme.env}" "none: the terminal's own 16 colors -- $slots"
    status_console
    status_next
}

cmd_check() {   # the setup's tests, a line each, kept for tools' check
    { cmd_check_lines; echo $? > "$TMP/check.rc"; } | tee "$TMP/check.out"
    [ ! -s "$TMP/check.out" ] || tools_check_keep "$TMP/check.out"
    return "$(cat "$TMP/check.rc" 2>/dev/null || echo 1)"
}
chk() {   # chk NAME ok|warn|fail DETAIL [REMEDY] -- a check's row; a warn names its remedy and does not fail
    case $2 in
        ok) printf 'ok     %-12s %s\n' "$1" "$3" ;;
        warn) printf 'warn   %-12s %s -- %s\n' "$1" "$3" "${4:-}" ;;
        *) printf 'FAIL   %-12s %s -- %s\n' "$1" "$3" "${4:-}"; fails=$((fails + 1)) ;;
    esac
}
cmd_check_lines() {   # the checks, a row each; false when one fails
    config_load
    fails=0
    check_rc
    check_tools
    check_terminfo
    check_look
    check_theme
    check_font
    check_quiet
    check_desktop
    check_compositor
    check_terminal
    check_pointer
    check_saver
    check_mcp
    check_login
    check_dialog
    check_semantic
    check_apps
    check_bar
    check_top
    if [ "$OS" != Darwin ] && [ "$DESKTOP" = sway ]; then sound_check; notify_check; portal_check; bt_check; storage_check; power_check; fi
    [ "$fails" = 0 ]
}
check_rc() {   # the rc files are spark-shell's links
    tree=$(rc_tree)
    rc_ok=1
    for f in $(rc_files); do
        [ -L "$HOME/$f" ] && [ "$(readlink "$HOME/$f")" = "$tree/$f" ] || rc_ok=0
    done
    [ "$rc_ok" = 1 ] && chk rc ok "the rc files are spark-shell's" || chk rc fail "an rc file is not spark-shell's" "spark-shell on"
}
check_tools() {   # the tools are on PATH; starship only where a package manager has it and the config asks; ~/.local/bin too: a non-login ssh shell has no such PATH
    miss=''
    pm_detect
    tools="tmux fzf zoxide eza bat btop fd"
    if [ "$PROMPT" = starship ] && starship_listed; then tools="$tools starship"; fi
    for t in $tools; do
        tool_here "$t" || miss="$miss $t"
    done
    [ -z "$miss" ] && chk tools ok "$(printf '%s' "$tools" | sed 's/ /, /g')" || chk tools fail "missing:$miss" "spark-shell on"
}
check_terminfo() {   # tmux-256color knows modified arrow keys
    infocmp -1x tmux-256color 2>/dev/null | grep -q 'kUP=' && chk terminfo ok "tmux-256color knows modified arrows" \
        || chk terminfo fail "tmux-256color lacks kUP" "spark-shell on"
}
check_look() {   # render freshness: what on would write vs what is on disk
    theme_load
    EXPR=$(render_expr)
    stale=''
    for rel in $RENDERED; do
        [ -f "$HOME/$rel" ] || { stale="$stale $rel"; continue; }
        render_sed "$EXPR" "$REPO/template/$rel" > "$TMP/chk"
        cmp -s "$TMP/chk" "$HOME/$rel" || stale="$stale $rel"
    done
    [ -z "$stale" ] && chk look ok "the settings files match the palette" || chk look fail "out of date:$stale" "spark-shell on"
}
check_desktop() {   # the desktop's tools and rendered files, the seat, the font
    if [ "$OS" = Darwin ]; then chk desktop ok "na (macOS)"
    elif is_wsl; then chk desktop ok "na (WSL)"
    elif [ "$DESKTOP" = none ]; then chk desktop ok "na (DESKTOP=none)"
    elif [ -n "$(desktop_tools)" ]; then chk desktop fail "missing:$(desktop_tools)" "spark-shell on"
    else
        stale=''; render_failed=''
        for rel in $DESKTOP_RENDERED; do
            [ -f "$HOME/$rel" ] || { stale="$stale $rel"; continue; }
            # a broken renderer is a check result, not a stop
            if ! (render_tmp "$REPO/template/$rel" "$TMP/chk"); then
                render_failed="$render_failed $rel"
                continue
            fi
            cmp -s "$TMP/chk" "$HOME/$rel" || stale="$stale $rel"
        done
        if [ -n "$render_failed" ]; then chk desktop fail "cannot render:$render_failed" "check python3 and desktop-keys.json"
        elif [ -n "$stale" ]; then chk desktop fail "out of date:$stale" "spark-shell on"
        elif ! command -v jq >/dev/null 2>&1; then chk desktop fail "jq is missing (a layout reads the model's answer with it)" "spark-shell on"
        elif seat_needed && ! seatd_on; then chk desktop fail "seatd does not start at boot (Void has no logind)" "spark-shell on desktop"
        elif seat_needed && ! in_group _seatd "$(id -un)"; then chk desktop fail "$(id -un) is not in the _seatd group" "spark-shell on desktop"
        elif [ "$(font_spec)" != "$FONT" ]; then chk desktop warn "$NEON is not installed, so $TERM_NAME draws $NEON_OLD" "spark-shell on"
        else chk desktop ok "$WM_NAME and $TERM_NAME are installed and up to date"; fi
    fi
}
check_compositor() {   # the compositor answers
    if [ "$OS" = Darwin ] || [ "$DESKTOP" = none ]; then chk compositor ok "na (no desktop)"
    elif ! wm_here; then chk compositor fail "$WM_NAME is not installed" "spark-shell on desktop"
    elif ! wm_session; then chk compositor ok "$WM_NAME: no session here (log in on tty1)"
    elif _wv=$(wm_version | jq -r '.human_readable // empty' 2>/dev/null) && [ -n "$_wv" ]; then chk compositor ok "$WM_NAME $_wv answers"
    else chk compositor warn "$WM_NAME does not answer" "log in again"; fi
}
check_terminal() {   # the terminal is here
    if [ "$OS" = Darwin ] || [ "$DESKTOP" = none ]; then chk terminal ok "na (no desktop)"
    elif ! term_here; then chk terminal fail "$TERM_NAME is not installed" "spark-shell on desktop"
    else _tv=$(term_version); chk terminal ok "$TERM_NAME${_tv:+ $_tv}, pictures over sixel"; fi
}
check_pointer() {   # the spark pointer is drawn
    if [ -n "$(desktop_na)" ] || [ "$DESKTOP" = none ]; then chk pointer ok "na (no desktop)"
    elif pointer_drawn; then chk pointer ok "spark-white and spark-black are drawn; sway shows $POINTER_NAME at $POINTER_SIZE"
    elif ! pointer_can; then chk pointer warn "python3 cannot draw the spark pointer here" "install python3, then spark-shell on desktop"
    else chk pointer fail "the spark pointer is not drawn" "spark-shell on desktop"; fi
}
check_saver() {   # the idle screen's saver can run
    if [ "$OS" = Darwin ] || [ "$DESKTOP" = none ]; then chk saver ok "na (no desktop)"
    elif [ "$DISPLAY_SAVER" = clock ]; then chk saver ok "the idle screen shows the clock alone"
    elif saver_can; then chk saver ok "the idle screen shows the $DISPLAY_SAVER saver"
    else chk saver warn "python3 cannot run the $DISPLAY_SAVER saver: the idle screen shows the clock" "install python3, or spark-shell desktop display saver clock"; fi
}
check_mcp() {   # the providers are on spark's MCP list
    if [ "$OS" = Darwin ] || [ "$DESKTOP" = none ]; then chk mcp ok "na (no desktop)"
    elif ! mcp_spark >/dev/null; then chk mcp ok "na (spark has no MCP list before 1.90)"
    else _mn=$(mcp_mine | wc -w | tr -d ' '); _mt=$(printf '%s' "$PROVIDE_SECTIONS" | wc -w | tr -d ' ')
        if [ "$_mn" = "$_mt" ]; then chk mcp ok "the $_mt providers are on spark's MCP list"; else chk mcp warn "$_mn of $_mt providers on spark's MCP list" "spark-shell on desktop"; fi
    fi
}
check_login() {   # the login screen takes tty1 at boot
    if [ -n "$(login_na)" ] || [ "$LOGIN" != yes ]; then chk login ok "na (the console login, LOGIN=no)"
    elif ! greetd_here; then chk login fail "greetd is not installed" "spark-shell on login"
    else
        login_render; _f=$(login_files_differ)
        if [ -n "$_f" ]; then chk login fail "out of date:$_f" "spark-shell on login"
        elif ! login_switched; then chk login fail "the login screen does not take tty1 at boot" "spark-shell on login"
        elif [ "$DISTRO" = void ] && ! in_group _seatd "$LOGIN_ACCOUNT"; then chk login fail "$LOGIN_ACCOUNT is not in the _seatd group" "spark-shell on login"
        else chk login ok "the login screen takes tty1 at boot, tty2 keeps the console login"; fi
    fi
}
check_dialog() {   # home runs only the build the release pins: said here, not at the key
    if [ "$OS" = Darwin ] || [ "$DESKTOP" = none ] || [ "$DIALOG_URL" = none ] || [ -n "${SPARK_SHELL_DIALOG:-}" ] || ! dialog_target >/dev/null; then chk dialog ok "na (no release build here)"
    elif ! _crt=$(release_tag); then chk dialog ok "na (this clone is past its release)"
    elif dialog_ok; then chk dialog ok "$DIALOG_BIN, the sha256 $_crt pins"
    else chk dialog fail "not the build $_crt pins, so home will not open" "spark-shell on"; fi
}
check_semantic() {   # the model is the one spark-shell pins: read whole for its sha256 here, never as home opens
    if [ "$OS" = Darwin ] || [ "$DESKTOP" = none ]; then chk semantic ok "na (no desktop)"
    elif [ -z "$(spark_bin)" ]; then chk semantic ok "na (spark is not installed)"
    elif [ "$DIALOG_SEMANTIC" = no ]; then chk semantic ok "na (DIALOG_SEMANTIC=no)"
    elif ! semantic_engine >/dev/null; then chk semantic ok "na (spark's engine is not installed)"
    elif [ ! -f "$SEMANTIC_MODEL" ]; then chk semantic fail "the model is missing" "spark-shell on"
    elif ! semantic_model_ok; then chk semantic fail "the model is not the one spark-shell pins" "spark-shell on"
    else semantic_where; _cst='not running'; ! semantic_up || _cst="running at $SEMANTIC_SOCK"; chk semantic ok "$SEMANTIC_MODEL, the sha256 spark-shell pins, $_cst"; fi
}
check_apps() {   # the allowed apps are here
    if [ "$OS" = Darwin ] || [ "$DESKTOP" = none ]; then chk apps ok "na (no desktop)"
    else
        sbom_entries; ne=$(wc -l < "$TMP/entries" | tr -d ' ')
        if apps_marked; then
            gone=''
            for n in $(grep '^[A-Za-z0-9]' "$APPS" | sed 's/[: ].*//'); do layout_on_path "$n" || grep -q "^$n	" "$TMP/entries" || gone="$gone $n"; done
            [ -z "$gone" ] && chk apps ok "$(grep -c '^[A-Za-z0-9]' "$APPS") allowed apps, $ne apps installed" || chk apps fail "allowed but not here:$gone" "spark-shell apps"
        else chk apps ok "$ne apps installed, all allowed (spark-shell apps chooses)"; fi
    fi
}
check_bar() {   # spark draws the status line
    spark=$(spark_bin)
    if [ -z "$spark" ]; then chk bar ok "na (spark not found -- the status line stays empty)"
    elif "$spark" bar line >/dev/null 2>&1; then chk bar ok "spark bar line works"
    else chk bar fail "spark bar line failed" "spark check"; fi
}
check_top() {   # the bar draws its blocks
    if [ "$OS" = Darwin ] || [ "$DESKTOP" = none ]; then chk top ok "na (no desktop)"
    elif [ "$DESKTOP_BAR" != yes ]; then chk top ok "hidden (spark-shell bar on --desktop shows it)"
    elif ! command -v jq >/dev/null 2>&1; then chk top warn "jq is not installed: the bar takes no clicks" "spark-shell on"
    elif line=$(REM_LOOK=1 bar_status --once 2>/dev/null) && printf '%s' "$line" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1; then
        chk top ok "the bar draws $(printf '%s' "$line" | jq -r '[.[] | select(.name != "div" and .name != "logo") | .name] | unique | join(", ")')"
    else chk top fail "spark-shell bar status draws nothing" "spark-shell on"; fi
}

