# shellcheck extended-analysis=false
# the sound on the desktop: PipeWire, WirePlumber and its PulseAudio
# sets: BAR_ASOUNDRC LIGHT_GROUPS SOUND_ALSA SOUND_CONF SOUND_FILES SOUND_PW SOUND_PW_CONF SOUND_SHARE SOUND_SV
# reads: MODE NL OS REPO ROOT SPARK_CONFIG_DIR STATE_DIR TMP
BAR_ASOUNDRC=$HOME/.config/alsa/asoundrc   # ALSA reads it after ~/.asoundrc; ours only with the marker line
# server. Under systemd the packages' user units start them; on runit
# they run from boot under spark's supervisor, else beside sway. Void
# leaves the two ALSA files out of /etc/alsa/conf.d, so on desktop links
# them, and without logind adds you to the audio group; each root step
# is recorded and off desktop undoes only those
SOUND_ALSA='50-pipewire.conf 99-pipewire-default.conf'
SOUND_SHARE=usr/share/alsa/alsa.conf.d
SOUND_CONF=etc/alsa/conf.d
SOUND_SV=$SPARK_CONFIG_DIR/sv/spark-shell-sound   # the service, in the directory spark's runsvdir-USER runs from boot
SOUND_FILES='run finish log/run'                  # its files, from template/.config/spark/sv/spark-shell-sound
SOUND_PW='wireplumber=usr/share/examples/wireplumber/10-wireplumber.conf pipewire-pulse=usr/share/examples/pipewire/20-pipewire-pulse.conf'   # PROGRAM=the package's own example that has PipeWire start it
SOUND_PW_CONF=${XDG_CONFIG_HOME:-$HOME/.config}/pipewire/pipewire.conf.d   # the per-user place for their links
sound_links_missing() { for f in $SOUND_ALSA; do [ -f "$ROOT/$SOUND_SHARE/$f" ] && [ ! -e "$ROOT/$SOUND_CONF/$f" ] && [ ! -L "$ROOT/$SOUND_CONF/$f" ] && printf ' %s' "$f"; done; return 0; }   # -> the files PipeWire's package left out of /etc/alsa/conf.d
sound_group_needed() { [ "$(init_shape)" != systemd ] && grep -q '^audio:' "$ROOT/etc/group" 2>/dev/null; }   # no logind: the audio group opens the sound devices
sound_apply() {
    [ "$OS" != Darwin ] || return 0
    _miss=$(sound_links_missing)
    if [ -n "$_miss" ] && need sound "ALSA programs play through PipeWire: link$_miss into /$SOUND_CONF (sudo)" && seat_root on "the sound"; then
        _ok=1; mkdir_private "$STATE_DIR"
        root_do mkdir -p "$ROOT/$SOUND_CONF" || _ok=0
        for f in $_miss; do   # the record names each link made, and only those
            if root_do ln -s "/$SOUND_SHARE/$f" "$ROOT/$SOUND_CONF/$f"; then echo "$f" >> "$STATE_DIR/sound.alsa"; else _ok=0; fi
        done
        if [ "$_ok" = 1 ]; then
            ok sound "ALSA programs play through PipeWire (/$SOUND_CONF)"
        else row todo sound "the links in /$SOUND_CONF failed -- spark-shell on desktop again"; acting=0; fi
    fi
    _me=$(id -un)
    if sound_group_needed && ! in_group audio "$_me" && need sound "add $_me to the audio group: the sound devices open to you (sudo)" && seat_root on "the sound"; then
        if root_do usermod -aG audio "$_me"; then
            mkdir_private "$STATE_DIR"; : > "$STATE_DIR/sound.group"
            ok sound "$_me is in the audio group now: it takes effect at your next login"
        else row todo sound "usermod could not add $_me to audio -- spark-shell on desktop again"; acting=0; fi
    fi
    if [ -f "$BAR_ASOUNDRC" ] && grep -q 'rendered by spark-shell' "$BAR_ASOUNDRC" && command -v pipewire >/dev/null 2>&1; then
        changes=$((changes + 1))
        if [ "$MODE" = dry ]; then row would sound "remove $BAR_ASOUNDRC: PipeWire picks the output now"
        else rm -f "$BAR_ASOUNDRC"; row ok sound "$BAR_ASOUNDRC removed: PipeWire picks the output now"; fi
    fi
    sound_svc_apply
}
sound_off() {   # by the records alone, as seat_off: the service and PipeWire's own links first (yours, no root), then the root steps
    sound_svc_off
    sound_pw_off
    [ -e "$STATE_DIR/sound.alsa" ] || [ -e "$STATE_DIR/sound.group" ] || return 0
    need sound "PipeWire's ALSA links and your audio membership removed, as spark-shell made them (sudo)" || return 0
    seat_root off "the sound" || return 0
    if [ -e "$STATE_DIR/sound.alsa" ]; then
        _ok=1
        for f in $(cat "$STATE_DIR/sound.alsa"); do
            case " $SOUND_ALSA " in *" $f "*) ;; *) continue ;; esac   # a name of ours, never a path read back
            [ "$(readlink "$ROOT/$SOUND_CONF/$f" 2>/dev/null)" = "/$SOUND_SHARE/$f" ] || continue
            root_do rm -f "$ROOT/$SOUND_CONF/$f" || _ok=0
        done
        if [ "$_ok" = 1 ]; then rm -f "$STATE_DIR/sound.alsa"; row ok sound "ALSA programs no longer play through PipeWire (the links spark-shell made are gone)"
        else row todo sound "the links in /$SOUND_CONF stay -- spark-shell off desktop again"; fi
    fi
    if [ -e "$STATE_DIR/sound.group" ]; then
        _me=$(id -un)
        if ! in_group audio "$_me" || root_do gpasswd -d "$_me" audio >/dev/null 2>&1; then
            rm -f "$STATE_DIR/sound.group"
            row ok sound "$_me is out of the audio group spark-shell added: it takes effect at your next login"
        else row todo sound "gpasswd could not take $_me out of audio -- spark-shell off desktop again"; fi
    fi
}
# the sound from boot (runit): spark-shell-sound, a service in the
# directory spark's runsvdir-USER runs. Its run takes the desktop's
# private runtime dir and runs PipeWire in its own process group; finish
# stops what it started. It is written whole under a dot name runsvdir
# skips, then renamed into place; off takes it down through its runsv
sound_rd() { _r=${TMPDIR:-/tmp}; printf '%s/%s-runtime-dir' "${_r%/}" "$(id -u)"; }   # -> the private runtime dir runtime_dir makes, the service's too
sound_svc_ours() { [ -d "$SOUND_SV" ] && [ ! -L "$SOUND_SV" ] && grep -qs 'rendered by spark-shell' "$SOUND_SV/run"; }   # the service is spark-shell's: the marker in its run
sound_svc_why() {   # -> why PipeWire does not run from boot on this runit machine, or nothing
    if [ ! -d "$SPARK_CONFIG_DIR/sv" ]; then echo "spark's supervisor is not here ($SPARK_CONFIG_DIR/sv)"
    elif [ -n "${XDG_RUNTIME_DIR:-}" ] && [ "$XDG_RUNTIME_DIR" != "$(sound_rd)" ]; then echo "a login manager set the runtime dir ($XDG_RUNTIME_DIR)"; fi
}
sound_svc_render() {   # -> the service's files in $TMP/sound, from its templates
    _se="s|@SND_DIR@|$(esc "$ROOT/dev/snd")|g${NL}s|@SOUND_LOG@|$(esc "$STATE_DIR/log/sound")|g"
    mkdir -p "$TMP/sound/log"
    for f in $SOUND_FILES; do
        render_sed "$_se" "$REPO/template/.config/spark/sv/spark-shell-sound/$f" > "$TMP/sound/$f"
        ! grep -q '@[A-Z_0-9]*@' "$TMP/sound/$f" || { printf 'spark-shell: the sound service %s: unrendered placeholder\n' "$f" >&2; exit 1; }
    done
}
sound_svc_differ() { for f in $SOUND_FILES; do cmp -s "$TMP/sound/$f" "$SOUND_SV/$f" || printf ' %s' "$f"; done; }   # -> the service's files that differ from the render, by name
sound_svc_put() {   # sound_svc_put DIR -- the rendered files into DIR, 0755, each through a rename: a run that runs keeps its own file
    mkdir -p "$1/log" || return 1
    for f in $SOUND_FILES; do cp "$TMP/sound/$f" "$1/$f.new" && chmod 0755 "$1/$f.new" && mv -f "$1/$f.new" "$1/$f" || return 1; done
}
sound_svc_status() { sound_svc_ours && sv status "$SOUND_SV" 2>/dev/null; }   # -> runsv's own line for the service (run: DIR: (pid N) Ts;...), nothing when nothing supervises it
sound_svc_up() { case $(sound_svc_status || :) in run:*|finish:*) return 0 ;; esac; return 1; }   # its runsv keeps it up: running, or between two starts
sound_from() {   # -> boot | login | the desktop: where the PipeWire that answers runs from
    if [ "$(init_shape)" = systemd ]; then echo login; return 0; fi
    _p=$(sound_svc_status | sed -n 's/^run: [^(]*(pid \([0-9][0-9]*\)).*/\1/p')   # the service's pid is PipeWire's once it runs it, the run script's while it waits
    if [ -n "$_p" ] && [ "$(cat "$ROOT/proc/$_p/comm" 2>/dev/null)" = pipewire ]; then echo boot; else echo 'the desktop'; fi
}
sound_pw_links() {   # PipeWire starts WirePlumber and its PulseAudio server itself: its per-user links, recorded; false when it cannot
    _want=''; _who=''
    for _w in $SOUND_PW; do
        _p=${_w%%=*}; _e=${_w#*=}
        [ "$_p" != pipewire-pulse ] || command -v pipewire-pulse >/dev/null 2>&1 || continue
        ! sound_by_pipewire "$_p" || continue
        [ -f "$ROOT/$_e" ] || { skip sound "PipeWire cannot start $_p itself here (no /$_e): PipeWire starts with the desktop"; return 1; }
        _want="$_want ${_e##*/}"
        if [ "$_p" = wireplumber ]; then _who="${_who:+$_who and }WirePlumber"; else _who="${_who:+$_who and }its PulseAudio server"; fi
    done
    [ -n "$_want" ] || return 0
    need sound "PipeWire starts $_who itself: link$_want into $SOUND_PW_CONF" || return 0
    mkdir -p "$SOUND_PW_CONF" "$STATE_DIR" 2>/dev/null || :
    for _w in $SOUND_PW; do
        _e=${_w#*=}
        case "$_want " in *" ${_e##*/} "*) ;; *) continue ;; esac
        if ln -s "$ROOT/$_e" "$SOUND_PW_CONF/${_e##*/}"; then grep -qsx "${_e##*/}" "$STATE_DIR/sound.pipewire" || echo "${_e##*/}" >> "$STATE_DIR/sound.pipewire"
        else row todo sound "the link $SOUND_PW_CONF/${_e##*/} failed -- spark-shell on desktop again"; acting=0; return 1; fi
    done
    ok sound "PipeWire starts $_who itself ($SOUND_PW_CONF)"
}
sound_svc_apply() {   # the boot row of on desktop (runit): the service, after PipeWire's own links
    [ "$(init_shape)" = runit ] && command -v pipewire >/dev/null 2>&1 || return 0
    _why=$(sound_svc_why)
    if [ -n "$_why" ]; then skip sound "$_why: PipeWire starts with the desktop"; return 0; fi
    if { [ -e "$SOUND_SV" ] || [ -L "$SOUND_SV" ]; } && ! sound_svc_ours; then
        row todo sound "$SOUND_SV is not spark-shell's: left as it is, and PipeWire starts with the desktop"; acting=0; return 0
    fi
    sound_pw_links || return 0
    sound_svc_render
    if sound_svc_ours; then
        _f=$(sound_svc_differ)
        if [ -z "$_f" ]; then ok sound "PipeWire runs from boot ($SOUND_SV)"; return 0; fi
        need sound "PipeWire from boot: write$_f in $SOUND_SV" || return 0
        if sound_svc_put "$SOUND_SV"; then ok sound "PipeWire from boot: $SOUND_SV updated, in effect from its next start"
        else row todo sound "$SOUND_SV could not be written -- spark-shell on desktop again"; acting=0; fi
        return 0
    fi
    need sound "PipeWire from boot: $SOUND_SV, a service under spark's supervisor" || return 0
    _new=$SPARK_CONFIG_DIR/sv/.spark-shell-sound.new   # a dot name: runsvdir skips it until it is whole
    rm -rf "$_new"
    if sound_svc_put "$_new" && mv "$_new" "$SOUND_SV"; then
        if XDG_RUNTIME_DIR=$(sound_rd) wpctl status >/dev/null 2>&1; then ok sound "PipeWire runs from boot ($SOUND_SV); the one running now stays until it ends"
        else ok sound "PipeWire runs from boot ($SOUND_SV)"; fi
    else rm -rf "$_new"; row todo sound "$SOUND_SV could not be written -- spark-shell on desktop again"; acting=0; fi
}
sound_svc_off() {   # off: the service down through its runsv, then its directory gone
    sound_svc_ours || return 0
    if [ "$MODE" = dry ]; then row would sound "PipeWire no longer runs from boot: $SOUND_SV stopped and removed"; return 0; fi
    touch "$SOUND_SV/down" 2>/dev/null || :   # a runsv started for it again never starts PipeWire
    sv -w 10 force-stop "$SOUND_SV" >/dev/null 2>&1 || :
    _gone=$SPARK_CONFIG_DIR/sv/.spark-shell-sound.off   # a dot name: runsvdir lets go of it, and never starts a runsv for it again
    rm -rf "$_gone"
    if mv "$SOUND_SV" "$_gone"; then
        sv exit "$_gone" >/dev/null 2>&1 || :
        _i=0; while [ "$_i" -lt 10 ] && sv status "$_gone" >/dev/null 2>&1; do sleep 1; _i=$((_i + 1)); done   # its runsv gone first, then its files
        rm -rf "$_gone"
        row ok sound "PipeWire no longer runs from boot ($SOUND_SV is gone)"
    else row todo sound "$SOUND_SV stays -- spark-shell off desktop again"; fi
}
sound_pw_off() {   # off: PipeWire's own links, by the record alone
    [ -s "$STATE_DIR/sound.pipewire" ] || return 0
    if [ "$MODE" = dry ]; then row would sound "PipeWire's links in $SOUND_PW_CONF removed, as spark-shell made them"; return 0; fi
    for _n in $(cat "$STATE_DIR/sound.pipewire"); do
        for _w in $SOUND_PW; do
            _e=${_w#*=}; [ "${_e##*/}" = "$_n" ] || continue   # a name of ours, never a path read back
            [ "$(readlink "$SOUND_PW_CONF/$_n" 2>/dev/null)" != "$ROOT/$_e" ] || rm -f "$SOUND_PW_CONF/$_n"
        done
    done
    rm -f "$STATE_DIR/sound.pipewire"
    rmdir "$SOUND_PW_CONF" "${SOUND_PW_CONF%/*}" 2>/dev/null || :   # only when nothing else is in them
    row ok sound "PipeWire no longer starts WirePlumber or its PulseAudio server itself (the links spark-shell made are gone)"
}
# the brightness: brightnessctl needs the video group, ddcutil the i2c
# group and the i2c-dev module; on desktop adds you to each group that
# exists, recorded, and off desktop takes back only those
LIGHT_GROUPS='video i2c'
light_apply() {
    [ "$OS" != Darwin ] || return 0
    _me=$(id -un)
    for _g in $LIGHT_GROUPS; do
        grep -q "^$_g:" "$ROOT/etc/group" 2>/dev/null && ! in_group "$_g" "$_me" || continue
        need light "add $_me to the $_g group: the screen's brightness opens to you (sudo)" && seat_root on "the brightness" || continue
        if root_do usermod -aG "$_g" "$_me"; then
            mkdir_private "$STATE_DIR"; echo "$_g" >> "$STATE_DIR/light.groups"
            ok light "$_me is in the $_g group now: it takes effect at your next login"
        else row todo light "usermod could not add $_me to $_g -- spark-shell on desktop again"; acting=0; fi
    done
    if command -v ddcutil >/dev/null 2>&1 && ! ls "$ROOT"/dev/i2c-* >/dev/null 2>&1 && [ -z "$ROOT" ]; then   # the module now; the package loads it at every boot
        need light "load i2c-dev now, for a screen's brightness over DDC/CI (sudo)" && seat_root on "the brightness" && { root_do modprobe i2c-dev 2>/dev/null && ok light "i2c-dev loaded"; } || :
    fi
}
light_off() {   # by the record alone
    [ -s "$STATE_DIR/light.groups" ] || return 0
    need light "your video and i2c memberships removed, as spark-shell added them (sudo)" || return 0
    seat_root off "the brightness" || return 0
    _me=$(id -un)
    for _g in $(cat "$STATE_DIR/light.groups"); do
        case " $LIGHT_GROUPS " in *" $_g "*) ;; *) continue ;; esac
        if ! in_group "$_g" "$_me" || root_do gpasswd -d "$_me" "$_g" >/dev/null 2>&1; then row ok light "$_me is out of the $_g group spark-shell added: it takes effect at your next login"
        else row todo light "gpasswd could not take $_me out of $_g -- spark-shell off desktop again"; fi
    done
    rm -f "$STATE_DIR/light.groups"
}
sound_start() {   # PipeWire, WirePlumber and the PulseAudio server for the desktop about to start, where nothing else runs them; their pids in SOUND_PIDS
    SOUND_PIDS=''
    [ "$(init_shape)" != systemd ] || return 0   # the packages' user units
    command -v pipewire >/dev/null 2>&1 && command -v wireplumber >/dev/null 2>&1 || return 0
    ! wpctl status >/dev/null 2>&1 || return 0   # one answers already: yours
    pipewire >"$1" 2>&1 </dev/null & SOUND_PIDS=$!
    for _i in 1 2 3 4 5; do [ ! -S "$XDG_RUNTIME_DIR/pipewire-0" ] || break; sleep 1; done
    sound_by_pipewire wireplumber || { wireplumber >>"$1" 2>&1 </dev/null & SOUND_PIDS="$SOUND_PIDS $!"; }
    if command -v pipewire-pulse >/dev/null 2>&1 && ! sound_by_pipewire pipewire-pulse; then pipewire-pulse >>"$1" 2>&1 </dev/null & SOUND_PIDS="$SOUND_PIDS $!"; fi
}
sound_by_pipewire() {   # sound_by_pipewire NAME -- PipeWire starts NAME itself: a pipewire.conf.d file runs it
    for _d in "$ROOT/etc/pipewire/pipewire.conf.d" "${XDG_CONFIG_HOME:-$HOME/.config}/pipewire/pipewire.conf.d"; do
        grep -qs "$1" "$_d"/*.conf && return 0
    done
    return 1
}
# shellcheck disable=SC2086   # the pids, split on purpose
sound_stop() { [ -z "${SOUND_PIDS:-}" ] || { kill $SOUND_PIDS 2>/dev/null; wait $SOUND_PIDS 2>/dev/null; } || :; }   # wait: gone before the next desktop asks wpctl
