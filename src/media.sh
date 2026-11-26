# shellcheck extended-analysis=false
# --- media: what plays in any player that speaks MPRIS, and its controls
# sets: MEDIA_ACTIONS MEDIA_MPV_PLUGINS MEDIA_MPV_RECORD MEDIA_MPV_ROOT
# reads: MODE OS PANEL_DOT PANEL_SEP SCRUB_AWK STATE_DIR TAB
# playerctl asks the players. It acts on the first it finds, so the player is chosen here: the one that plays, else the
# first paused one. A title is a page's or a file's own words: every field is scrubbed before anything draws or says it
MEDIA_ACTIONS='play pause toggle next previous stop'   # what a key, a click, a row or a tool asks of the player
media_here() { [ -z "${SPARK_SHELL_NO_PLAYERCTL:-}" ] && command -v playerctl >/dev/null 2>&1; }   # SPARK_SHELL_NO_PLAYERCTL: for the tests
# media_list -> a line a player with a track, in playerctl's order: NAME<tab>STATUS<tab>TEXT. NAME is the instance where
# playerctl gives one (two windows of one browser are two players), STATUS is Playing, Paused or Stopped, TEXT the artist
# and the title, the one of the two there is, or the player's own name. Nothing with no player or no playerctl
media_list() {
    media_here || return 0
    bar_timeout playerctl --all-players --no-messages metadata --format "{{playerInstance}}$TAB{{playerName}}$TAB{{status}}$TAB{{artist}}$TAB{{title}}" 2>/dev/null \
        | LC_ALL=C awk -F '\t' "$SCRUB_AWK"'
            { n = $1; if (n == "") n = $2; a = clean($4); t = clean($5)
              if (n !~ /^[A-Za-z0-9_.-]+$/ || $3 !~ /^(Playing|Paused|Stopped)$/) next   # a bus name is these letters alone
              if (a != "" && t != "") t = a " - " t; else if (t == "") t = a
              if (t == "") t = clean($2)
              if (t != "") printf "%s\t%s\t%s\n", n, $3, t }' || :
}
media_now() {   # -> the player the bar shows and the keys reach, as media_list says it: the first that plays, else the first paused; nothing when none does either
    media_list | awk -F '\t' '$2 == "Playing" { print; f = 1; exit } $2 == "Paused" && p == "" { p = $0 } END { if (!f && p != "") print p }'
}
media_check() {   # the media row of check, on a desktop machine
    if ! media_here; then chk media warn "playerctl is not installed, so the bar shows nothing of what plays and the media keys do nothing" "spark-shell on desktop"
    elif [ -n "$(media_mpv_plugin)" ] && ! media_mpv_loads; then chk media warn "mpv does not load its MPRIS plugin, so the bar never shows what mpv plays" "spark-shell on desktop"
    else chk media ok "the bar shows what plays, and the media keys control it"; fi
}
# mpv is one of the players through its MPRIS plugin (mpv-mpris). Some families' packages link the plugin into mpv's
# system scripts folder; Void's and openSUSE's leave it in a library folder, where mpv never looks. On desktop links
# it into your own mpv scripts folder then, by a record, and off takes away the link the record names
MEDIA_MPV_PLUGINS='usr/lib/mpv-mpris/mpris.so usr/lib64/mpv-mpris/mpris.so usr/lib64/mpv/mpris.so usr/lib/mpv/mpris.so'
MEDIA_MPV_RECORD=$STATE_DIR/media.mpv   # the link on desktop made, a line: off removes that one and no other
MEDIA_MPV_ROOT=${SPARK_SHELL_MPV_ROOT:-}   # a package's files are read where they are, never under ROOT (the files spark-shell writes as root); SPARK_SHELL_MPV_ROOT=DIR (tests) prefixes them
media_mpv_plugin() {   # -> the plugin as the family's package installed it; nothing where it is not installed
    for _mpp in $MEDIA_MPV_PLUGINS; do [ ! -f "$MEDIA_MPV_ROOT/$_mpp" ] || { printf '%s\n' "$MEDIA_MPV_ROOT/$_mpp"; return 0; }; done
    for _mpp in "$MEDIA_MPV_ROOT"/usr/lib/*/mpv/mpris.so "$MEDIA_MPV_ROOT"/usr/lib/*/mpv-mpris/mpris.so; do [ ! -f "$_mpp" ] || { printf '%s\n' "$_mpp"; return 0; }; done   # under the architecture's own folder
}
media_mpv_link() { printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/mpv/scripts/mpris.so"; }
media_mpv_loads() { [ -e "$MEDIA_MPV_ROOT/etc/mpv/scripts/mpris.so" ] || [ -e "$(media_mpv_link)" ]; }   # mpv loads the plugin: by the system's link, or by a file or a link in your folder
media_apply() {   # on desktop's media row: nothing where mpv loads the plugin already, where it is not installed, or where a link of yours stands
    ! media_mpv_loads || return 0
    _mas=$(media_mpv_plugin); [ -n "$_mas" ] || return 0
    _mal=$(media_mpv_link); [ ! -L "$_mal" ] || return 0
    changes=$((changes + 1))
    if [ "$MODE" = dry ]; then row would media "$_mal: mpv loads its MPRIS plugin, so the bar shows what it plays"; return 0; fi
    mkdir -p "${_mal%/*}" && ln -s "$_mas" "$_mal" || return 0
    mkdir_private "$STATE_DIR"; printf '%s\n' "$_mal" > "$MEDIA_MPV_RECORD"
    row link media "$_mal: mpv loads its MPRIS plugin, so the bar shows what it plays"
}
media_off() {   # off, off desktop: the link on desktop made goes, by its record; one you made stays
    [ -s "$MEDIA_MPV_RECORD" ] || return 0
    _mol=''; read -r _mol < "$MEDIA_MPV_RECORD" || :
    if [ "$MODE" = dry ]; then row would media "$_mol removed"; return 0; fi
    [ ! -L "$_mol" ] || rm -f "$_mol"
    rm -f "$MEDIA_MPV_RECORD"; row ok media "$_mol removed"
}
media_why() { if media_here; then echo "nothing is playing"; else echo "playerctl is not installed (spark-shell on desktop)"; fi; }
# media_act ACTION -> one line, what the player was asked and its name; 1 when not done: no playerctl, no player, or a
# player that did not take it. The player is the one media_now names, else the first there is: a stopped one still plays
media_act() {
    case " $MEDIA_ACTIONS " in *" $1 "*) ;; *) echo "media takes $(printf '%s' "$MEDIA_ACTIONS" | sed 's/ /, /g')"; return 1 ;; esac
    media_here || { media_why; return 1; }
    _mal=$(media_now); _map=${_mal%%"$TAB"*}
    [ -n "$_map" ] || _map=$(bar_timeout playerctl --no-messages --list-all 2>/dev/null | sed -n '1p' | tr -cd 'A-Za-z0-9_.-')
    [ -n "$_map" ] || { echo "nothing to $1: no player is running"; return 1; }
    _mac=$1
    case $1 in
        play) _maw=playing ;; pause) _maw=paused ;; stop) _maw=stopped ;; next) _maw='next track' ;; previous) _maw='previous track' ;;
        toggle) _mac=play-pause; _maw=playing; case $_mal in *"${TAB}Playing${TAB}"*) _maw=paused ;; esac ;;
    esac
    bar_timeout playerctl --no-messages --player "$_map" "$_mac" >/dev/null 2>&1 || { echo "${_map%%.*} did not take $1"; return 1; }
    bar_redraw   # the player's own change follows: the bar's watcher draws it when it comes
    echo "$_maw $PANEL_SEP ${_map%%.*}"
}
# media_follow -> a line at each change of any player: a track, a pause, a player that came or went. It runs until
# its reader is gone and it writes again, so who starts it keeps its pid and ends it (bar_media_watch)
media_follow() { exec playerctl --all-players --no-messages --follow metadata --format '{{status}} {{artist}} {{title}}' 2>/dev/null; }
media_title() {   # the section's line: what plays, or why nothing shows
    _mtl=$(media_now); [ -n "$_mtl" ] || { echo "$(panel_col media)$(media_why)"; return 0; }
    _mts=playing; case $_mtl in *"${TAB}Paused${TAB}"*) _mts=paused ;; esac
    printf '%s\n' "$(panel_col media)$_mts $PANEL_SEP $(printf '%s' "$_mtl" | cut -f3 | cut_chars 44)"   # a title is a player's words: printed as they are, never read by echo
}
panel_rows_media() {   # what plays, a look-only row with its player a column, the dot while it plays; then the one of play and pause that changes it, next, previous, stop
    _mrl=$(media_now); [ -n "$_mrl" ] || { printf -- '-\t%s\tshow\n' "$(media_why)"; return 0; }
    _mrt=$(printf '%s' "$_mrl" | cut -f3 | cut_chars 44); _mrp=$(printf '%s' "$_mrl" | cut -f1 | cut -d. -f1 | cut_chars 14)
    case $_mrl in
        *"${TAB}Paused${TAB}"*) printf -- '-\t%s\tshow\t|%s\n-\tplay\tplay\n' "$_mrt" "$_mrp" ;;
        *) printf '%s\t%s\tshow\t|%s\n-\tpause\tpause\n' "$PANEL_DOT" "$_mrt" "$_mrp" ;;
    esac
    printf -- '-\tnext\tnext\n-\tprevious\tprevious\n-\tstop\tstop\n'
}
layout_media() {   # layout_media [ACTION] -- spark-shell desktop media: what plays, or a step of MEDIA_ACTIONS
    [ "$OS" != Darwin ] || refuse "not on macOS, which has its own media keys"
    if [ "$#" = 0 ]; then
        _lml=$(media_list); [ -n "$_lml" ] || { media_why; return 0; }
        printf '%s\n' "$_lml" | awk -F '\t' '{ n = $1; sub(/[.].*/, "", n); printf "%s: %s (%s)\n", n, $3, tolower($2) }'
        return 0
    fi
    [ "$#" = 1 ] || refuse "media takes one of $(printf '%s' "$MEDIA_ACTIONS" | sed 's/ /, /g')"
    media_act "$1" || exit 1
}
