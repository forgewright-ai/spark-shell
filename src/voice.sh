# shellcheck extended-analysis=false
# --- voice: the ear hears, the words go in the terminal's line, the band shows it
# sets: EAR_BIN VOICE_DIR VOICE_MODEL_SHA256 VOICE_MODEL_URL VOICE_PUNCT_SHA256 VOICE_PUNCT_URL VOICE_REWRITE_SHA256 VOICE_REWRITE_URL VOICE_RUNTIME_SHA256 VOICE_RUNTIME_URL
# reads: DIALOG_URL OS REPO STATE_DIR TMP
EAR_BIN=${XDG_DATA_HOME:-$HOME/.local/share}/spark-shell/spark-ear
VOICE_DIR=${XDG_DATA_HOME:-$HOME/.local/share}/spark-shell/ear   # the engine: lib/ and model/
VOICE_RUNTIME_URL=${SPARK_SHELL_VOICE_RUNTIME_URL:-https://github.com/k2-fsa/sherpa-onnx/releases/download/v2.0.1/sherpa-onnx-v2.0.1-linux-x64-shared-lib.tar.bz2}   # sherpa-onnx; file:// or none in the tests
VOICE_RUNTIME_SHA256=532c45bbd41036d83cd70606797529aa8086c2053395a58967736c727625b120
VOICE_MODEL_URL=${SPARK_SHELL_VOICE_MODEL_URL:-https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-nemo-streaming-fast-conformer-transducer-en-80ms-int8.tar.bz2}   # NVIDIA's streaming FastConformer, English
VOICE_MODEL_SHA256=7bd33a914e93370a1ba9c2066d9e841bdcad8613fa2a00537c1ae15d851a14d8
VOICE_PUNCT_URL=${SPARK_SHELL_VOICE_PUNCT_URL:-https://github.com/k2-fsa/sherpa-onnx/releases/download/punctuation-models/sherpa-onnx-online-punct-en-2024-08-06.tar.bz2}   # the marks the words wear while they are spoken
VOICE_PUNCT_SHA256=9f5e5a72c7d2829635bd074fce92b6bbd5b78da8a52e7ad8ed1be933f366b99d
VOICE_REWRITE_URL=${SPARK_SHELL_VOICE_REWRITE_URL:-https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-nemo-parakeet-unified-en-0.6b-int8-non-streaming.tar.bz2}   # the line read again when the speaking stops
VOICE_REWRITE_SHA256=99f63605b3a85a54c250c0869670a687b7d6598a47bf2421515e1f839a76e150

# the ear, pinned like the pad
ear_release_tag() {   # -> clone_tag when it pins an ear and component/ear/ is unchanged since; false otherwise
    _ert=$(clone_tag) || return 1
    git -C "$REPO" cat-file -e "$_ert:component/ear/ear.env" 2>/dev/null || return 1
    git -C "$REPO" diff --quiet "$_ert" -- component/ear 2>/dev/null || return 1
    printf '%s\n' "$_ert"
}
ear_want_sha() {   # -> the sha256 the release tag's tree pins for this machine, or nothing
    _erk=EAR_SHA256_$(wallpaper_target | tr 'a-z-' 'A-Z_'); _ert=$(ear_release_tag) || return 0
    git -C "$REPO" show "$_ert:component/ear/ear.env" 2>/dev/null | sed -n "s/^$_erk=\([0-9a-f]\{64\}\)$/\1/p"
}
ear_ok() { [ -x "$EAR_BIN" ] && _erw=$(ear_want_sha) && [ -n "$_erw" ] && [ "$(sha256_of "$EAR_BIN")" = "$_erw" ]; }   # the binary in place is the one the tree pins
ear_cmd() { if [ -n "${SPARK_SHELL_EAR:-}" ]; then [ -x "$SPARK_SHELL_EAR" ] && printf '%s' "$SPARK_SHELL_EAR"; elif ear_ok; then printf '%s' "$EAR_BIN"; else return 1; fi; }   # -> SPARK_SHELL_EAR (another build, as it is), else the pinned ear; false when none

# the engine behind the ear
voice_lib() { printf '%s' "$VOICE_DIR/lib/libsherpa-onnx-c-api.so"; }
voice_model() { printf '%s' "$VOICE_DIR/model"; }
voice_punct() { printf '%s' "$VOICE_DIR/punct"; }   # the punctuation while speaking
voice_rewrite() { printf '%s' "$VOICE_DIR/rewrite"; }   # the line read again at the end
voice_punct_here() { [ -f "$(voice_punct)/model.onnx" ] && [ -f "$(voice_punct)/bpe.vocab" ]; }
voice_rewrite_here() { [ -f "$(voice_rewrite)/encoder.int8.onnx" ] && [ -f "$(voice_rewrite)/tokens.txt" ]; }
voice_engine_here() { [ -f "$(voice_lib)" ] && [ -f "$VOICE_DIR/lib/libonnxruntime.so" ] && [ -f "$(voice_model)/encoder.int8.onnx" ] && [ -f "$(voice_model)/tokens.txt" ]; }
voice_engine() {   # -> the command that hears here: your own, else the ear; false when neither can
    if [ -n "${VOICE_ENGINE:-}" ]; then printf '%s' "$VOICE_ENGINE"; return 0; fi
    voice_engine_here || return 1
    ear_cmd
}
voice_engine_env() {   # what the ear reads; your own engine is left as it is
    [ -z "${VOICE_ENGINE:-}" ] || return 0
    EAR_LIB=$(voice_lib) EAR_MODEL=$(voice_model); export EAR_LIB EAR_MODEL
    ! voice_punct_here || { EAR_PUNCT=$(voice_punct); export EAR_PUNCT; }
    ! voice_rewrite_here || { EAR_REWRITE=$(voice_rewrite); export EAR_REWRITE; }
}
voice_here() { [ "$VOICE" != no ] && wm_type_here && voice_engine >/dev/null 2>&1; }   # the mic on the band and the key only where something hears and the words can be typed

# the files of a session, in the runtime folder: want (the key is held or the mic is on), pid, the pipes; the state for the band
voice_run_dir() { printf '%s' "${XDG_RUNTIME_DIR:-$STATE_DIR}/spark-shell-voice"; }
voice_want() { printf '%s' "$(voice_run_dir)/want"; }
voice_state() { printf '%s' "${XDG_RUNTIME_DIR:-$STATE_DIR}/spark-shell-voice.state"; }   # listening 0|1, level 0..7: the band reads it
voice_pid() {   # -> the running session's pid; false when none runs, or when what ran is a husk nothing reaped
    _vp=$(cat "$(voice_run_dir)/pid" 2>/dev/null) || return 1
    case $_vp in ''|*[!0-9]*) return 1 ;; esac
    kill -0 "$_vp" 2>/dev/null || return 1
    [ ! -r "/proc/$_vp/cmdline" ] || tr '\0' ' ' < "/proc/$_vp/cmdline" | grep -q spark-shell || return 1
    printf '%s\n' "$_vp"
}
voice_set_state() { _vss=$(voice_state).$$; printf 'listening %s\nlevel %s\n' "$1" "$2" > "$_vss" 2>/dev/null && mv "$_vss" "$(voice_state)" 2>/dev/null || rm -f "$_vss" 2>/dev/null || :; }
voice_wanted() { mkdir_private "$(voice_run_dir)"; printf '%s %s.%s %s\n' "$1" "$$" "$(voice_now_ms)" "${2:-plain}" > "$(voice_want)"; }   # voice_wanted STAMP [plain|marks] -- the press's time in ms, or 0, a token of its own, and what the words wear
voice_want_kind() { cut -d' ' -f3 "$(voice_want)" 2>/dev/null; }
voice_want_stamp() { cut -d' ' -f1 "$(voice_want)" 2>/dev/null; }
voice_want_token() { cut -d' ' -f2 "$(voice_want)" 2>/dev/null; }

voice_stop() {   # the session told to end: the engine first, so its last words are typed; then the session itself
    _vsp=$(voice_pid) || return 1
    rm -f "$(voice_want)"
    _vse=$(cat "$(voice_run_dir)/engine" 2>/dev/null) || _vse=''
    case $_vse in ''|*[!0-9]*) ;; *) kill -TERM "$_vse" 2>/dev/null || : ;; esac
    _vsi=0; while [ "$_vsi" -lt 15 ] && kill -0 "$_vsp" 2>/dev/null; do sleep 0.1; _vsi=$((_vsi + 1)); done
    kill -0 "$_vsp" 2>/dev/null || return 0
    # it is still there: a shell runs no trap while its read waits, so the session goes with its own group
    kill -TERM "-$_vsp" 2>/dev/null || kill -TERM "$_vsp" 2>/dev/null || :
    voice_set_state 0 0
    rm -f "$(voice_run_dir)/pid" "$(voice_run_dir)/engine"
}
voice_press() {   # voice_press [wrap] -- the key down: a tap opens home on the release; held, it listens until the release
    ! voice_stop || return 0   # a press while listening ends it
    voice_wanted "$(voice_now_ms)" "${1:-plain}"
    voice_session hold
}
voice_release() {   # voice_release [wrap] -- the key up
    _vr=$(voice_want_stamp) && [ -n "$_vr" ] || { voice_stop || :; return 0; }   # the press is listening already
    _vk=$(voice_want_kind)
    rm -f "$(voice_want)"
    [ "$_vr" != 0 ] && [ $(( $(voice_now_ms) - _vr )) -lt 300 ] || { voice_stop || :; return 0; }   # held: the words stay
    [ "$_vk" = wrap ] || home_open   # a tap of the plain key opens home; the wrapping key is for holding
}
voice_toggle() {   # the mic clicked
    if voice_stop; then echo "voice: off"; return 0; fi
    voice_wanted 0 plain
    voice_session now
    echo "voice: listening"
}
voice_now_ms() {   # -> the time in milliseconds; where date has no nanoseconds (BSD), whole seconds
    _vnm=$(date +%s%N 2>/dev/null)
    case $_vnm in ''|*[!0-9]*) printf '%s\n' "$(( $(date +%s) * 1000 ))" ;; *) printf '%s\n' "$(( _vnm / 1000000 ))" ;; esac
}
voice_session() { ( setsid sh "$REPO/spark-shell" desktop voice --listen "$1" </dev/null >/dev/null 2>>"$(voice_run_dir)/log" & ); }   # voice_session hold|now -- voice_listen, apart
voice_no() {   # voice_no WHY [DETAIL] -- nothing is heard, said where each is read: a notification, and the session's log
    voice_drop_want
    mkdir_private "$(voice_run_dir)"
    printf 'voice: %s%s\n' "$1" "${2:+ -- $2}" >> "$(voice_run_dir)/log"
    notify_send voice "Voice: $1"
}
voice_drop_want() { [ "$(voice_want_token)" = "${_vlw:-}" ] || return 0; rm -f "$(voice_want)"; }   # only the file this session was started for
voice_listen() {   # voice_listen hold|now -- the session: the engine's words into the focused terminal's line while its own want stands
    [ "$1" = now ] || { sleep 0.3; [ -f "$(voice_want)" ] || return 0; }   # a tap: the release took the file
    _vlw=$(voice_want_token) || _vlw=''   # the session answers for this want alone; a newer one takes over
    _vlk=$(voice_want_kind) || _vlk=plain   # plain words, or your prefix and suffix around them
    _vlc=$(voice_engine) || { voice_no "nothing can hear here (spark-shell on desktop)"; return 0; }
    voice_engine_env
    wm_type_here || { voice_no "$(wm_missing type)"; return 0; }
    _vlt=$(wm_focused_id) || { voice_no "no window has the focus"; return 0; }   # the words go where the keys would
    _vld=$(voice_run_dir); mkdir_private "$_vld"; echo $$ > "$_vld/pid"
    rm -f "$_vld/leash" "$_vld/words"; mkfifo "$_vld/leash" "$_vld/words"
    voice_set_state 1 0
    # shellcheck disable=SC2086   # the engine's words are a command line
    $_vlc --max 60 < "$_vld/leash" > "$_vld/words" 2>>"$_vld/log" & _vlp=$!
    echo "$_vlp" > "$_vld/engine"
    exec 3> "$_vld/leash"; _vlo=1   # the leash: closed, the engine says its last words and ends
    trap '[ "$_vlo" = 0 ] || { exec 3>&-; _vlo=0; }' TERM INT HUP   # told to stop: the leash goes now, not at the next level
    _vln=0; _vlt1=''
    while IFS= read -r _vll; do
        case $_vll in
            level\ *) voice_set_state 1 "${_vll#level }"
                _vln=$((_vln + 1))
                if [ "$_vlo" = 1 ] && [ "$(voice_want_token)" != "$_vlw" ]; then exec 3>&-; _vlo=0   # the key is up, the mic was clicked again, or a newer session has the word
                # the focus every second: no word goes to another window. A tree that does not answer is not a move.
                elif [ "$_vlo" = 1 ] && [ $((_vln % 10)) = 0 ] && _vlf=$(wm_focused_id) && [ "$_vlf" != "$_vlt" ]; then
                    printf 'voice: the focus moved to %s\n' "$_vlf" >> "$_vld/log"
                    exec 3>&-; _vlo=0
                fi ;;
            type\ *) [ -n "$_vlt1" ] || { _vlt1=1; [ "$_vlk" != wrap ] || [ -z "${VOICE_PREFIX:-}" ] || wm_type "$VOICE_PREFIX"; }   # the prefix before the first words
                wm_type "${_vll#type }" ;;
            erase\ *) wm_erase "${_vll#erase }" ;;
        esac
    done < "$_vld/words"
    [ "$_vlo" = 0 ] || exec 3>&-
    [ -z "$_vlt1" ] || [ "$_vlk" != wrap ] || [ -z "${VOICE_SUFFIX:-}" ] || wm_type "$VOICE_SUFFIX"   # and the suffix after them
    _vlr=0; wait "$_vlp" || _vlr=$?
    printf 'voice: the session ended, the engine said %s, the leash was %s\n' "$_vlr" "$([ "$_vlo" = 1 ] && echo open || echo closed)" >> "$_vld/log"
    [ "$_vlr" != 2 ] || notify_send voice "Voice: $(grep -v '^voice: ' "$_vld/log" 2>/dev/null | tail -1 | sed 's/^spark-ear: //')"
    voice_set_state 0 0
    voice_drop_want
    rm -f "$_vld/pid" "$_vld/engine" "$_vld/leash" "$_vld/words"
}
voice_off() { voice_stop || rm -f "$(voice_want)"; }   # off desktop: no session is left listening; the ear and its engine stay
voice_status() {
    if voice_pid >/dev/null; then echo 'voice: listening'
    elif voice_here; then echo 'voice: ready (hold Super+Space, or click the mic on a window)'
    else echo 'voice: nothing can hear here (spark-shell on desktop)'; fi
}
voice_cmd() {   # voice_cmd [press|release|toggle|off|status|--listen hold|now]
    [ "$OS" != Darwin ] || refuse "not on macOS, which has its own dictation"
    case ${1:-status} in
        press) shift; voice_press "${1:-plain}" ;;
        release) shift; voice_release "${1:-plain}" ;;
        toggle) voice_toggle ;;
        off) voice_off ;;
        status) voice_status ;;
        --listen) voice_listen "${2:-now}" ;;
        *) refuse "voice takes press, release, toggle, off or status; press and release take wrap" ;;
    esac
}

# the install
voice_fetch() {   # voice_fetch WHAT URL SHA256 FILE -- the archive at FILE, its sha256 checked; a todo row and false otherwise
    curl -fsSL --proto '=https,file' --proto-redir '=https' -o "$4" --connect-timeout 30 --speed-limit 1024 --speed-time 60 "$2" 2>/dev/null || { rm -f "$4"; row todo voice "could not fetch the $1 -- spark-shell on desktop again"; return 1; }
    [ "$(sha256_of "$4")" = "$3" ] || { rm -f "$4"; row todo voice "the $1 fetched is not the one spark-shell pins: not installed"; return 1; }
}
voice_unpack() {   # voice_unpack ARCHIVE DIR MEMBER... -- the named files of a tar.bz2 into DIR, flat; false when one is missing
    python3 -I -c 'import os, sys, tarfile
archive, out, names = sys.argv[1], sys.argv[2], sys.argv[3:]
os.makedirs(out, exist_ok=True)
with tarfile.open(archive, "r:bz2") as t:
    for m in t.getmembers():
        base = os.path.basename(m.name)
        if base in names and m.isfile():
            with t.extractfile(m) as src, open(os.path.join(out, base + ".new"), "wb") as dst:
                dst.write(src.read())
            os.replace(os.path.join(out, base + ".new"), os.path.join(out, base))
            names.remove(base)
sys.exit(1 if names else 0)' "$@"
}
voice_install() {   # the voice row of on desktop: the ear and its engine in place as pinned, or fetched and checked
    [ "$VOICE" != no ] || { skip voice "VOICE=no"; return 0; }
    [ -z "${VOICE_ENGINE:-}" ] || { ok voice "your engine: $VOICE_ENGINE"; return 0; }
    _vit=$(wallpaper_target) || { skip voice "no spark-ear built for $(uname -m) yet"; return 0; }
    _vir=$(ear_release_tag) || { row todo voice "this clone is past its release: the ear comes with the next tag"; return 0; }
    _viw=$(ear_want_sha); [ -n "$_viw" ] || { skip voice "$_vir pins no spark-ear"; return 0; }
    if ear_ok && voice_engine_here && voice_punct_here && voice_rewrite_here; then ok voice "spark-ear and its models, as pinned ($VOICE_DIR)"; return 0; fi
    [ "$DIALOG_URL" != none ] && [ "$VOICE_RUNTIME_URL" != none ] || { skip voice "no release to fetch from (SPARK_SHELL_DIALOG_URL=none)"; return 0; }
    command -v curl >/dev/null 2>&1 || { row todo voice "curl is not installed: the ear cannot be fetched (spark-shell on installs it)"; return 0; }
    need voice "fetch spark-ear for $_vir and its models (sherpa-onnx 2.0.1, English, 620 MB: the words as you speak, their punctuation, and the line read again at the end), the sha256 of each checked" || return 0
    if ! ear_ok; then
        tag_signed "$_vir" || { row todo voice "$_vir is not signed by a key in allowed-signers: spark-ear not installed"; return 0; }
        voice_fetch ear "$DIALOG_URL/$_vir/spark-ear-$_vit" "$_viw" "$TMP/spark-ear" || return 0
        mkdir -p "$(dirname "$EAR_BIN")" && chmod 755 "$TMP/spark-ear" && mv "$TMP/spark-ear" "$EAR_BIN"
    fi
    if [ ! -f "$(voice_lib)" ] || [ ! -f "$VOICE_DIR/lib/libonnxruntime.so" ]; then
        voice_fetch "engine's library" "$VOICE_RUNTIME_URL" "$VOICE_RUNTIME_SHA256" "$TMP/runtime.tar.bz2" || return 0
        voice_unpack "$TMP/runtime.tar.bz2" "$VOICE_DIR/lib" libsherpa-onnx-c-api.so libonnxruntime.so || { row todo voice "the engine's library did not unpack"; return 0; }
    fi
    if ! voice_engine_here; then
        voice_fetch model "$VOICE_MODEL_URL" "$VOICE_MODEL_SHA256" "$TMP/model.tar.bz2" || return 0
        voice_unpack "$TMP/model.tar.bz2" "$(voice_model)" encoder.int8.onnx decoder.int8.onnx joiner.int8.onnx tokens.txt || { row todo voice "the model did not unpack"; return 0; }
    fi
    if ! voice_punct_here; then
        voice_fetch "punctuation model" "$VOICE_PUNCT_URL" "$VOICE_PUNCT_SHA256" "$TMP/punct.tar.bz2" || return 0
        voice_unpack "$TMP/punct.tar.bz2" "$(voice_punct)" model.onnx bpe.vocab || { row todo voice "the punctuation model did not unpack"; return 0; }
    fi
    if ! voice_rewrite_here; then
        voice_fetch "rewriting model" "$VOICE_REWRITE_URL" "$VOICE_REWRITE_SHA256" "$TMP/rewrite.tar.bz2" || return 0
        voice_unpack "$TMP/rewrite.tar.bz2" "$(voice_rewrite)" encoder.int8.onnx decoder.int8.onnx joiner.int8.onnx tokens.txt || { row todo voice "the rewriting model did not unpack"; return 0; }
    fi
    row ok voice "spark-ear and its models installed ($VOICE_DIR), sha256 checked"
}
check_voice() {
    if [ "$OS" = Darwin ] || [ "$DESKTOP" = none ]; then chk voice ok "na (no desktop)"
    elif [ "$VOICE" = no ]; then chk voice ok "na (VOICE=no)"
    elif [ -n "${VOICE_ENGINE:-}" ]; then chk voice ok "your engine: $VOICE_ENGINE"
    elif ! _cvt=$(wallpaper_target); then chk voice ok "na (no spark-ear built for $(uname -m) yet)"
    elif ! _cvr=$(ear_release_tag); then chk voice ok "na (this clone is past its release)"
    elif [ -z "$(ear_want_sha)" ]; then chk voice ok "na ($_cvr pins no spark-ear)"
    elif ! ear_ok; then chk voice fail "not the spark-ear $_cvr pins" "spark-shell on desktop"
    elif ! voice_engine_here; then chk voice fail "the engine is missing" "spark-shell on desktop"
    elif ! voice_punct_here; then chk voice fail "the punctuation model is missing" "spark-shell on desktop"
    elif ! voice_rewrite_here; then chk voice fail "the rewriting model is missing" "spark-shell on desktop"
    elif ! wm_type_here; then chk voice fail "$(wm_missing type)" "spark-shell on desktop"
    else chk voice ok "spark-ear and its models ($VOICE_DIR)"; fi
}
