# shellcheck extended-analysis=false
# --- the preview: a page for each kind of file, a sound and a video played
# sets: FILES_FULL_PX FILES_KINDS FILES_PAGE_PX FILES_SOUND_T FILES_TEXT_MAX FILES_TOOL_T FILES_WAVE_PX MPV_SAFE
# reads: NOTES_DIR REPO TMP US WM_NAME
FILES_TEXT_MAX=131072    # a text preview's bytes at most
FILES_PAGE_PX=1600       # a picture's long side at most
FILES_FULL_PX=4096       # a zoom's; the dialog decodes 4096 at most
FILES_TOOL_T=10          # a tool's seconds: the file is untrusted
FILES_SOUND_T=300        # seconds the waveform drawing gets
# a line each: the kind, its extensions
FILES_KINDS='markdown md markdown
json json
code sh bash zsh fish py rb pl lua js mjs cjs ts tsx jsx c h cc cpp hpp cs java kt go rs swift sql html htm css scss xml yaml yml toml ini cfg conf env diff patch
text txt text log csv tsv jsonl ndjson rst org tex srt vtt
picture png jpg jpeg webp gif svg bmp tif tiff
pdf pdf
sound mp3 wav flac ogg oga opus m4a aac aif aiff aifc ac3 eac3 dts caf mka wv
video mp4 m4v mov webm mkv avi mpg mpeg mts m2ts wmv ogv mxf 3gp
office docx pptx xlsx odt odp ods'
FILES_WAVE_PX=160        # the waveform's height over the spectrogram (512)
MPV_SAFE='--no-config --no-ytdl --load-scripts=no --demuxer-lavf-o=protocol_whitelist=file'   # the file is untrusted: no config, scripts, network
files_kind() {   # files_kind PATH -> its kind, text or other
    _fke=$(printf '%s' "${1##*/}" | sed -n 's/.*\.\([A-Za-z0-9]*\)$/\1/p' | tr 'A-Z' 'a-z')
    _fkk=$(printf '%s\n' "$FILES_KINDS" | awk -v e="$_fke" 'e != "" { for (i = 2; i <= NF; i++) if ($i == e) { print $1; exit } }')
    if [ -n "$_fkk" ]; then echo "$_fkk"
    elif command -v file >/dev/null 2>&1 && file -b --mime-type -- "$1" 2>/dev/null | grep -q '^text/'; then echo text
    else echo other; fi
}
files_tool() {   # files_tool CMD... -- CMD timed out, idle under FILES_IDLE
    if [ -n "${FILES_IDLE:-}" ]; then set -- nice -n 19 "$@"; ! command -v ionice >/dev/null 2>&1 || set -- ionice -c 3 "$@"; fi
    if command -v timeout >/dev/null 2>&1; then timeout "$FILES_TOOL_T" "$@"; else "$@"; fi
}
files_say() { jq -cn --arg s "$1" '{say: $s}' > "$TMP/page.json"; }   # files_say WHY -- page.json: no preview
provide_page() {   # provide_page SECTION ROW-ID -> the row's page
    case $1:$2 in
        apps:'apps:open '?*) app_page "${2#apps:open }" ;;
        notes:'notes:open '?*)
            _ppn=${2#notes:open }; case $_ppn in */*|.*) return 1 ;; esac
            _ppd=$(realpath "$NOTES_DIR" 2>/dev/null) || return 1
            _ppr=${PROOTS:-}; files_home_root > "$TMP/notes.roots"; PROOTS=$TMP/notes.roots   # under your home, whatever roots the host gave
            files_page "$_ppd/$_ppn" 1 ''; _ppc=$?; PROOTS=$_ppr; return "$_ppc" ;;
        reminders:reminders:*) rem_page "$(printf '%s' "$2" | sed -n 's/.*:[0-9]\{4\}-[0-9][0-9]-[0-9][0-9]://p')" ;;   # the uid, after the date
        window:'window:focus '?*) win_page "${2#window:focus }" ;;
        layout:'layout:open '?*) layout_page "${2#layout:open }" ;;
        wifi:wifi:*) wifi_page "$2" ;;
        bt:'bt:'*' '?*) bt_page "${2#bt:* }" ;;
        storage:'storage:'*' '?*) storage_page "${2#storage:* }" ;;
        tools:tools:package:?*) tools_package_page "${2#tools:package:}" ;;
        tools:tools:program:?*) tools_program_page "${2#tools:program:}" ;;
        tools:tools:space:caches) tools_space_view caches ;;
        tools:tools:folder:?*) tools_space_view "folder:${2#tools:folder:}" ;;
        about:about:license) scrub_text < "$REPO/LICENSE" | jq -Rn '{title: "license", lines: [inputs], bold: []}' ;;
        about:about:credits) scrub_text < "$REPO/CREDITS.md" | jq -Rn '[inputs] as $l | {title: "credits", lines: ($l | map(sub("^#+ *"; ""))), bold: [range($l | length) | select($l[.] | startswith("#"))]}' ;;
        *) return 1 ;;
    esac
}
page_of() {   # page_of TITLE WHAT -- stdin LABEL<tab>VALUE -> a page
    scrub_text | awk -F '\t' '$2 != "" { n++; l[n] = $1; v[n] = $2; if (length($1) > w) w = length($1) } END { for (i = 1; i <= n; i++) printf "%-" (w + 3) "s%s\n", l[i], v[i] }' > "$TMP/page.pairs"
    jq -n --arg t "$(printf '%s' "$1" | scrub_text)" --arg w "$(printf '%s' "$2" | scrub_text)" --rawfile p "$TMP/page.pairs" \
        '{title: $t, lines: ([$t] + (if $w == "" or $w == $t then [] else [$w] end) + [""] + ($p | split("\n") | map(select(. != "")))), bold: [0]}'
}
app_page() {   # app_page NAME -> an app's page
    sbom_entries
    _apl=$(awk -F '\t' -v n="$1" '$1 == n { print; exit }' "$TMP/entries")
    if [ -z "$_apl" ]; then
        command -v "$1" >/dev/null 2>&1 || return 1
        printf 'runs in\ta terminal\ncommand\t%s\n' "$1" | page_of "$1" "a command on this computer"; return
    fi
    _apf=$(printf '%s' "$_apl" | cut -f2); _apw=$(printf '%s' "$_apl" | cut -f3); _apx=$(printf '%s' "$_apl" | cut -f6 | sed 's/ *%[a-zA-Z]//g')   # field codes out
    _apn=$(sed -n 's/^Name=//p' "$_apf" | head -1); [ -n "$_apn" ] || _apn=$1
    case $_apf in */flatpak/*) _api='as a Flatpak' ;; */snapd/*) _api='as a Snap' ;; "${XDG_DATA_HOME:-$HOME/.local/share}"/*) _api='in your own apps folder' ;; /usr/local/*) _api='by hand, in /usr/local' ;; *) _api="with the system's packages" ;; esac
    _apr='its own window'; [ "$(printf '%s' "$_apl" | cut -f4)" != yes ] || _apr='a terminal'
    printf 'group\t%s\nruns in\t%s\ncommand\t%s\ninstalled\t%s\n' "$(app_group "$(printf '%s' "$_apl" | cut -f5)")" "$_apr" "$_apx" "$_api" | page_of "$_apn" "$_apw"
}
rem_page() {   # rem_page UID -> a reminder's page
    [ -n "$1" ] || return 1
    _rpl=$(rem_list | awk -F '\t' -v u="$1" '$2 == u { print; exit }'); [ -n "$_rpl" ] || return 1
    _rps=$(printf '%s' "$_rpl" | cut -f1); _rpf=$(printf '%s' "$_rpl" | cut -f4)
    if rem_ours "$_rpl"; then _rpc='spark-shell'; else _rpc=${_rpf%/*}; _rpc=${_rpc##*/}; fi
    _rpw=$(rem_said "$_rps"); [ "$(rem_group "$_rps" "$(date +%Y%m%d%H%M)")" != due ] || _rpw="$_rpw, due now"
    printf 'when\t%s\ncalendar\t%s\n' "$_rpw" "$_rpc" | page_of "$(printf '%s' "$_rpl" | cut -f3)" 'a reminder'
}
win_page() {   # win_page ID -> a window's page
    case $1 in ''|*[!0-9]*) return 1 ;; esac
    wm_tree | jq -r --argjson i "$1" --arg aside "$(win_aside)" '
        [.nodes[] | select(.type == "output") as $o | $o.nodes[] | select(.type == "workspace") as $w | $w | .. | objects | select(.id? == $i and (.type == "con" or .type == "floating_con")) | {o: $o.name, w: $w.name, n: .}] | .[0] // empty
        | (.n.app_id // .n.window_properties.class // "a window"), (.n.name // ""),
          "workspace\t" + (.w | split(":") | .[0] + (if (.[1] // "") != "" and .[1] != .[0] then " " + .[1] else "" end)), "screen\t" + .o, "size\t" + (.n.rect.width | tostring) + " by " + (.n.rect.height | tostring) + " pixels",
          "placed\t" + (if .n.fullscreen_mode == 1 or (.n.id | tostring) == $aside then "full screen" elif .n.type == "floating_con" then "floating" else "tiled" end)' > "$TMP/win.page" 2>/dev/null
    [ -s "$TMP/win.page" ] || return 1
    sed -n '3,$p' "$TMP/win.page" | page_of "$(sed -n 1p "$TMP/win.page")" "$(sed -n 2p "$TMP/win.page")"
}
layout_page() {   # layout_page NAME -> a layout's page
    _lpf=$(layout_kept_file "$1") || return 1
    layout_json_ok "$_lpf" || return 1
    jq -r '"in front\t" + .main.app + (if .main.fullscreen == true then ", full screen" elif (.main.width | type) == "number" then ", " + (.main.width | tostring) + "% wide" else "" end),
        (if ((.side // []) | length) > 0 then "beside\t" + ([.side[] | .app // empty] | join(", ")) else empty end),
        (if (.main.screen // "") != "" then "screen\t" + .main.screen else empty end)' "$_lpf" 2>/dev/null | page_of "$(layout_label "$_lpf")" "$(layout_why "$_lpf")"
}
wifi_page() {   # wifi_page ROW-ID -> a network's page
    case $1 in wifi:disconnect) _wpn=$(wifi_connected); _wpu=yes ;; 'wifi:connect '?*) _wpn=${1#wifi:connect }; _wpu='' ;; 'wifi:saved '?*) _wpn=${1#wifi:saved }; _wpu='' ;; *) return 1 ;; esac
    [ -n "$_wpn" ] || return 1
    _wps=$(wifi_scan | awk -F '\t' -v n="$_wpn" '$1 == n { print; exit }')
    _wpk=no; ! wifi_known | cut -f2 | grep -qxF -- "$_wpn" || _wpk=yes
    _wpa=''; [ -z "$_wpu" ] || ! command -v ip >/dev/null 2>&1 || _wpa=$(ip -4 -o addr show dev "$(wifi_if)" 2>/dev/null | awk '{ print $4; exit }')
    {   [ -z "$_wpu" ] || printf 'in use\tyes\n'
        if [ -n "$_wps" ]; then
            printf 'signal\t%s%%\n' "$(printf '%s' "$_wps" | cut -f2)"
            if [ "$(printf '%s' "$_wps" | cut -f3)" = 1 ]; then printf 'security\ta password\n'; else printf 'security\topen, no password\n'; fi
        elif [ -z "$_wpu" ]; then printf 'signal\tnot around now\n'; fi
        printf 'saved\t%s\naddress\t%s\n' "$_wpk" "$_wpa"
    } | page_of "$_wpn" 'a Wi-Fi network'
}
bt_page() {   # bt_page NAME -> a device's page
    _bpl=$(bt_list | awk -F '\t' -v n="$1" '$2 == n { print; exit }'); [ -n "$_bpl" ] || return 1
    _bpm=$(printf '%s' "$_bpl" | cut -f1)
    _bpb=''; ! command -v timeout >/dev/null 2>&1 || _bpb=$(timeout 3 bluetoothctl info "$_bpm" 2>/dev/null | sed -n 's/.*Battery Percentage: *0x[0-9a-fA-F]* *(\([0-9]*\)).*/\1/p' | head -1)
    _bpc=no; [ "$(printf '%s' "$_bpl" | cut -f4)" != 1 ] || _bpc=yes
    _bpp=no; [ "$(printf '%s' "$_bpl" | cut -f3)" != 1 ] || _bpp=yes
    printf 'connected\t%s\npaired\t%s\nbattery\t%s\naddress\t%s\n' "$_bpc" "$_bpp" "${_bpb:+$_bpb%}" "$_bpm" | page_of "$1" 'a Bluetooth device'
}
storage_page() {   # storage_page NAME -> a drive's page
    storage_list > "$TMP/storage.p"
    _spl=$(awk -F "$US" -v n="$1" '$1 == "fs" && $2 == n { print; exit }' "$TMP/storage.p"); [ -n "$_spl" ] || return 1
    _spm=$(printf '%s' "$_spl" | cut -d "$US" -f5)
    _spf=''; [ -z "$_spm" ] || _spf=$(storage_kb "$(storage_free "$_spm")")
    _spo='not mounted'; [ -z "$_spm" ] || _spo=$(files_home "$_spm")
    printf 'drive\t%s\nsize\t%s\nfree\t%s\nmounted at\t%s\nformat\t%s\n' "$(printf '%s' "$_spl" | cut -d "$US" -f6)" "$(files_size "$(printf '%s' "$_spl" | cut -d "$US" -f4)")" "$_spf" "$_spo" "$(printf '%s' "$_spl" | cut -d "$US" -f7)" | page_of "$1" 'a drive'
}
files_folder_page() {   # files_folder_page PATH -> a folder's page
    find "$1" -mindepth 1 -maxdepth 1 ! -name '.*' -type d 2>/dev/null | wc -l | tr -d ' ' > "$TMP/fold.d"
    find "$1" -mindepth 1 -maxdepth 1 ! -name '.*' ! -type d 2>/dev/null | wc -l | tr -d ' ' > "$TMP/fold.f"
    read -r _fpd < "$TMP/fold.d"; read -r _fpf < "$TMP/fold.f"
    _fph=''; [ "$_fpd" -eq 0 ] || { _fph="$(files_num "$_fpd") folder"; [ "$_fpd" = 1 ] || _fph="${_fph}s"; }
    [ "$_fpf" -eq 0 ] || { _fpx="$(files_num "$_fpf") file"; [ "$_fpf" = 1 ] || _fpx="${_fpx}s"; _fph="${_fph:+$_fph, }$_fpx"; }
    find "$1" -mindepth 1 -maxdepth 1 ! -name '.*' -print0 2>/dev/null | files_nul | files_stats | sort -t "$US" -k3,3nr | head -n 8 \
        | awk -F "$US" '{ p = substr($0, length($1 $2 $3 $4 $5) + 6); sub(/.*\//, "", p); print p }' | scrub_text > "$TMP/fold.new"
    jq -n --arg t "$(printf '%s' "${1##*/}" | scrub_text)" --arg h "${_fph:-empty}" --arg w "$(files_home "$1" | scrub_text)" --rawfile n "$TMP/fold.new" '
        ($n | split("\n") | map(select(. != ""))) as $new
        | {title: $t, lines: ([$t, $h] + (if ($new | length) > 0 then ["", "newest"] + ($new | map("   " + .)) else [] end)), bold: [0, 3], facts: [$w]}'
}
files_page() {   # files_page PATH PAGE [full] -> its page
    if _fp=$(files_ok "$1" dir); then files_folder_page "$_fp"; return; fi
    _fp=$(files_ok "$1" file) || return 1
    _fpg=${2:-1}; case $_fpg in ''|*[!0-9]*) _fpg=1 ;; esac; [ "$_fpg" -ge 1 ] || _fpg=1
    _fpx=$FILES_PAGE_PX; [ "${3:-}" != full ] || _fpx=$FILES_FULL_PX
    # shellcheck disable=SC2046   # two numbers, split on purpose
    set -- "$_fp" "$_fpg" $(files_stat "$_fp")
    mkdir -p "$TMP/pages" || return 1
    _fpb=$TMP/pages/$(printf '%s %s' "$1" "$4" | cksum | cut -d' ' -f1)   # cached by path and time
    : > "$TMP/page.lead"; : > "$TMP/page.json"
    case $(files_kind "$1") in
        markdown) files_page_text "$1" markdown "$3" "$_fpb" ;;
        json) files_page_text "$1" json "$3" "$_fpb" ;;
        code) files_page_text "$1" code "$3" "$_fpb" ;;
        text) files_page_text "$1" text "$3" "$_fpb" ;;
        picture) files_page_picture "$1" "$_fpb-$_fpx" "$_fpx" ;;
        pdf) files_page_pdf "$1" "$2" "$_fpb-$_fpx" "$_fpx" ;;
        sound) files_page_media "$1" sound "$_fpb" ;;
        video) files_page_media "$1" video "$_fpb-$_fpx" "$_fpx" ;;
        office) files_page_office "$1" "$_fpb" ;;
        *) file -b -- "$1" 2>/dev/null | cut -d, -f1 | scrub_text | cut -c1-40 >> "$TMP/page.lead"
           files_say "this kind of file cannot be viewed: Enter opens it" ;;
    esac
    printf '%s\n%s\n' "$(files_size "$3")" "$(files_when "$4")" >> "$TMP/page.lead"
    jq -n --arg t "$(printf '%s' "${1##*/}" | scrub_text)" --rawfile f "$TMP/page.lead" --slurpfile k "$TMP/page.json" \
        '{title: $t, facts: ($f | split("\n") | map(select(. != "")))} + ($k[0] // {})'
}
files_page_text() {   # files_page_text PATH KIND SIZE BASE -- page.json; BASE.txt for spark
    head -c "$FILES_TEXT_MAX" "$1" > "$TMP/page.raw" 2>/dev/null || :
    [ "$(LC_ALL=C tr -d '\000' < "$TMP/page.raw" | wc -c | tr -d ' ')" = "$(wc -c < "$TMP/page.raw" | tr -d ' ')" ] || { files_say "cannot view: this file is not text, Enter opens it"; return 0; }
    if [ "$2" = json ] && [ "$3" -le "$FILES_TEXT_MAX" ] && jq . "$1" > "$TMP/page.pretty" 2>/dev/null; then mv "$TMP/page.pretty" "$TMP/page.raw"; fi
    cp "$TMP/page.raw" "$4.txt"
    expand -t 4 < "$TMP/page.raw" > "$TMP/page.txt" 2>/dev/null || cp "$TMP/page.raw" "$TMP/page.txt"
    [ "$3" -le "$FILES_TEXT_MAX" ] || printf '\n\nthe view ends here, at %s of %s: Enter opens the whole file\n' "$(files_size "$FILES_TEXT_MAX")" "$(files_size "$3")" >> "$TMP/page.txt"
    jq -Rn --arg k "$2" --arg a "$4.txt" '[inputs] as $l
        | (if $k == "markdown" then {lines: ($l | map(sub("^#{1,6}[ \t]+"; ""))), bold: [range(0; $l | length) as $i | select($l[$i] | test("^#{1,6}[ \t]")) | $i]}
           else {lines: $l, numbered: ($k == "code")} end) + {attach: $a}' < "$TMP/page.txt" > "$TMP/page.json"
}
files_page_picture() {   # files_page_picture PATH BASE PX -- page.json, BASE.png
    _fpd=$(png_size "$1")
    [ -n "$_fpd" ] || _fpd=$(file -b -- "$1" 2>/dev/null | sed -n 's/.*[ ,]\([0-9][0-9]*\) *x *\([0-9][0-9]*\).*/\1 \2/p' | head -1)
    case $1 in *.svg|*.SVG) ;; *) if [ -z "$_fpd" ] && command -v mpv >/dev/null 2>&1; then   # file(1) gives a TIFF no size
        # shellcheck disable=SC2086   # MPV_SAFE is options, split on purpose
        _fpd=$(files_tool mpv $MPV_SAFE --untimed --vo=null --ao=null --length=0.05 --msg-level=all=no,term-msg=info --term-playing-msg='${width:} ${height:}' -- "$1" </dev/null 2>/dev/null | head -1 | grep -x '[0-9][0-9]* [0-9][0-9]*' || :)
    fi ;; esac
    _fps=$3; _fpz=null; _fpw=false; [ "$3" != "$FILES_FULL_PX" ] || _fpw=true
    if [ -n "$_fpd" ]; then
        # shellcheck disable=SC2086   # two numbers, split on purpose
        set -- "$1" "$2" "$3" $_fpd
        printf '%s \303\227 %s\n' "$4" "$5" >> "$TMP/page.lead"; _fpz="[$4,$5]"
        [ "$4" -ge "$5" ] && _fpl=$4 || _fpl=$5; [ "$_fpl" -gt "$_fps" ] || { _fps=$_fpl; _fpw=true; }
    fi
    case $1 in
        *.svg|*.SVG) command -v rsvg-convert >/dev/null 2>&1 && files_tool rsvg-convert -a -w "$_fps" -h "$_fps" -o "$2.png" "$1" 2>/dev/null ;;
        *) pic_png "$1" "$2.png" "$_fps" ;;
    esac || { files_say "cannot view: nothing here draws this picture, Enter opens it"; return 0; }
    if [ "$_fpz" != null ]; then   # EXIF orientation turns the size
        # shellcheck disable=SC2046   # four numbers, split on purpose
        set -- "$1" "$2" "$3" $_fpd $(png_size "$2.png")
        if [ $# -eq 7 ] && { { [ "$4" -gt "$5" ] && [ "$7" -gt "$6" ]; } || { [ "$5" -gt "$4" ] && [ "$6" -gt "$7" ]; }; }; then
            printf '%s \303\227 %s\n' "$5" "$4" > "$TMP/page.lead"; _fpz="[$5,$4]"
        fi
    fi
    jq -cn --arg p "$2.png" --argjson z "$_fpz" --argjson f "$_fpw" '{picture: $p, full: $f} + (if $z == null then {} else {size: $z} end)' > "$TMP/page.json"
}
files_page_pdf() {   # files_page_pdf PATH PAGE BASE PX -- page.json, BASE-PAGE.png
    command -v pdftoppm >/dev/null 2>&1 || { files_say "cannot view: pdftoppm (poppler) is not installed, Enter opens it"; return 0; }
    _fpn=$(files_tool pdfinfo "$1" 2>"$TMP/pdf.err" | sed -n 's/^Pages: *\([0-9][0-9]*\).*/\1/p')
    if [ -z "$_fpn" ] && grep -qi 'password' "$TMP/pdf.err"; then files_say "cannot view: this PDF is locked by a password, Enter opens it"; return 0; fi
    [ -n "$_fpn" ] && [ "$_fpn" -gt 0 ] || { files_say "cannot view: this PDF could not be read, Enter opens it"; return 0; }
    [ "$2" -le "$_fpn" ] || set -- "$1" "$_fpn" "$3" "$4"
    _fpz=$(files_tool pdfinfo -f "$2" -l "$2" "$1" 2>/dev/null | awk '/^Page +[0-9]+ size:/ { printf "[%d,%d]", $4 * 96 / 72 + 0.5, $6 * 96 / 72 + 0.5; exit }')
    [ -f "$3-$2.png" ] || files_tool pdftoppm -f "$2" -l "$2" -png -scale-to "$4" -singlefile "$1" "$3-$2" >/dev/null 2>&1 \
        || { files_say "cannot view: this page could not be drawn, Enter opens it"; return 0; }
    [ -f "$3-$2.txt" ] || files_tool pdftotext -f "$2" -l "$2" -enc UTF-8 "$1" "$3-$2.txt" >/dev/null 2>&1 || rm -f "$3-$2.txt"
    _fpa=''; [ ! -s "$3-$2.txt" ] || _fpa=$3-$2.txt
    jq -cn --arg p "$3-$2.png" --argjson n "$2" --argjson m "$_fpn" --arg a "$_fpa" --argjson z "${_fpz:-null}" --argjson f "$([ "$4" = "$FILES_FULL_PX" ] && echo true || echo false)" \
        '{picture: $p, page: $n, pages: $m, full: $f} + (if $a == "" then {} else {attach: $a} end) + (if $z == null then {} else {size: $z} end)' > "$TMP/page.json"
}
audio_bits() {   # audio_bits FILE -> the header's sample bits; mpv says 32 for 24
    od -An -v -tu1 -N 65536 < "$1" 2>/dev/null | awk '
        { for (i = 1; i <= NF; i++) b[n++] = $i }
        function id(o,   r, j) { r = ""; for (j = 0; j < 4; j++) r = r sprintf("%c", b[o + j]); return r }
        function le(o, k,   r, j) { r = 0; for (j = k - 1; j >= 0; j--) r = r * 256 + b[o + j]; return r }
        function be(o, k,   r, j) { r = 0; for (j = 0; j < k; j++) r = r * 256 + b[o + j]; return r }
        END {
            if (id(0) == "fLaC") { print (b[20] % 2) * 16 + int(b[21] / 16) + 1; exit }
            if (id(0) == "RIFF" && id(8) == "WAVE")
                for (o = 12; o + 28 <= n; o += 8 + z + z % 2) { z = le(o + 4, 4)
                    if (id(o) == "fmt ") { f = le(o + 8, 2); v = le(o + 22, 2); if (f == 65534 && z >= 40) { f = le(o + 32, 2); if (le(o + 26, 2) > 0) v = le(o + 26, 2) } if (f == 1) print v; exit } }
            if (id(0) == "FORM" && (id(8) == "AIFF" || id(8) == "AIFC"))
                for (o = 12; o + 16 <= n; o += 8 + z + z % 2) { z = be(o + 4, 4)
                    if (id(o) == "COMM") { print be(o + 14, 2); exit } }
        }'
}
files_sound_draw() {   # files_sound_draw PATH BASE -- BASE-sound.png, drawn aside
    if [ -f "$TMP/sound.job" ]; then
        read -r _fsj _fsb < "$TMP/sound.job"
        if [ "$_fsb" = "$2" ] && kill -0 "$_fsj" 2>/dev/null; then files_sound_wait "$2"; return 0; fi
        files_sound_stop
    fi
    (
        FILES_IDLE=1; FILES_TOOL_T=$FILES_SOUND_T; _fsd=$(mktemp -d) || exit 0; _fsp=$2-sound.pid
        trap 'rm -rf "$_fsd" "$_fsp"' EXIT; trap 'exit 143' TERM
        # shellcheck disable=SC2086   # MPV_SAFE is options, split on purpose
        files_tool mpv $MPV_SAFE --untimed --really-quiet --ao=null --vo=image --vo-image-format=png --vo-image-outdir="$_fsd" \
            --lavfi-complex="[aid1]asplit[a][b];[a]showwavespic=s=1600x${FILES_WAVE_PX}:split_channels=0:colors=white:scale=sqrt[w];[b]showspectrumpic=s=1600x512:legend=0:fscale=log:scale=log[s];[w][s]vstack=inputs=2[vo]" \
            -- "$1" </dev/null >/dev/null 2>&1 &
        echo "$!" > "$2-sound.pid"; wait "$!"
        mv "$_fsd/00000001.png" "$2-sound.png.new" 2>/dev/null && mv "$2-sound.png.new" "$2-sound.png"   # whole or not there
    ) </dev/null >/dev/null 2>&1 &
    echo "$! $2" > "$TMP/sound.job"
    files_sound_wait "$2"
}
files_sound_wait() { _fsw=0; while [ "$_fsw" -lt 15 ] && [ ! -f "$1-sound.png" ]; do sleep 0.1; _fsw=$((_fsw + 1)); done; }   # files_sound_wait BASE -- 1.5 s at most
files_sound_stop() {
    [ -f "$TMP/sound.job" ] || return 0
    read -r _fsj _fsb < "$TMP/sound.job"
    [ ! -f "$_fsb-sound.pid" ] || kill "$(cat "$_fsb-sound.pid")" 2>/dev/null || :
    kill "$_fsj" 2>/dev/null || :; rm -f "$TMP/sound.job"
}
files_time() { awk -v s="$1" 'BEGIN { s = int(s + 0.5); h = int(s / 3600); m = int(s % 3600 / 60); if (h > 0) printf "%d:%02d:%02d", h, m, s % 60; else printf "%d:%02d", m, s % 60 }'; }   # files_time SECONDS -> 3:45, 1:02:03
files_page_media() {   # files_page_media PATH sound|video BASE [PX] -- page.json
    command -v mpv >/dev/null 2>&1 || { files_say "cannot view: mpv is not installed, Enter opens it"; return 0; }
    # shellcheck disable=SC2086   # MPV_SAFE is options, split on purpose
    _fmf=$(files_tool mpv $MPV_SAFE --untimed --vo=null --ao=null --length=0.05 --msg-level=all=no,term-msg=info \
        --term-playing-msg="\${=duration:0}$US\${width:}$US\${height:}$US\${audio-params/samplerate:}$US\${audio-params/channel-count:}$US\${audio-params/format:}$US\${audio-codec-name:}$US\${metadata/by-key/title:}$US\${metadata/by-key/artist:}$US\${metadata/by-key/album:}$US\${video-params/rotate:}" -- "$1" </dev/null 2>/dev/null | head -1)
    [ -n "$_fmf" ] || { files_say "cannot view: mpv could not read this file, Enter opens it"; return 0; }
    printf '%s\n' "$_fmf" | tr "$US" '\n' > "$TMP/page.media"
    { read -r _fms; read -r _fmw; read -r _fmh; read -r _fmr; read -r _fmc; read -r _fmb; read -r _fmk; } < "$TMP/page.media"
    _fma=$(jq -cn --arg p "$1" '{path: $p}')
    if [ "$2" = video ]; then
        files_time "${_fms:-0}" >> "$TMP/page.lead"; echo >> "$TMP/page.lead"
        _fmx=${4:-$FILES_PAGE_PX}; _fmz=null; _fmu=true
        # the size shown, turned by rotation
        _fmv=''; _fmo=$(sed -n 11p "$TMP/page.media")
        if [ -n "$_fmw" ] && [ -n "$_fmh" ]; then
            if [ "$_fmw" -ge "$_fmh" ]; then _fml=$_fmw; [ "$_fmw" -le "$_fmx" ] || _fmv=--vf=scale=w=$_fmx:h=-2
            else _fml=$_fmh; [ "$_fmh" -le "$_fmx" ] || _fmv=--vf=scale=w=-2:h=$_fmx; fi
            case $_fmo in 90|270) set -- "$1" "$2" "$3" "${4:-}" "$_fmh" "$_fmw" ;; *) set -- "$1" "$2" "$3" "${4:-}" "$_fmw" "$_fmh" ;; esac
            printf '%s \303\227 %s\n' "$5" "$6" >> "$TMP/page.lead"; _fmz="[$5,$6]"
            [ "$_fml" -le "$_fmx" ] || _fmu=false; [ "$_fmx" != "$FILES_FULL_PX" ] || _fmu=true
        fi
        rm -rf "$TMP/frame"; mkdir -p "$TMP/frame"
        [ -f "$3.png" ] || {
            # shellcheck disable=SC2086
            files_tool mpv $MPV_SAFE --untimed --really-quiet --no-audio --vo=image --vo-image-format=png --vo-image-outdir="$TMP/frame" \
                --start=10% --frames=1 $_fmv -- "$1" </dev/null >/dev/null 2>&1
            mv "$TMP/frame/00000001.png" "$3.png" 2>/dev/null
        } || { files_say "cannot view: no frame of this video could be drawn, Enter opens it"; return 0; }
        _fmh=''; ! files_video_here || _fmh=1
        jq -cn --arg p "$3.png" --argjson a "$_fma" --argjson z "$_fmz" --argjson f "$_fmu" --arg h "$_fmh" --argjson n "${_fms:-0}" \
            '{picture: $p, full: $f} + (if $h != "" then {play: {name: "files_play", arguments: $a, said: "play"}, stop: {name: "files_stop", arguments: {}, said: "stop"}, seconds: $n}
               else {play: {name: "files_open", arguments: $a, said: "play"}} end) + (if $z == null then {} else {size: $z} end)' > "$TMP/page.json"
        return 0
    fi
    [ -z "$_fmr" ] || awk -v r="$_fmr" 'BEGIN { k = r / 1000; if (k == int(k)) printf "%d kHz\n", k; else printf "%.1f kHz\n", k }' >> "$TMP/page.lead"
    case $_fmk in mp3|mp2|aac|opus|vorbis|wmav2|ac3|eac3|dca) _fml=lossy ;; *) _fml='' ;; esac
    [ -n "$_fml" ] || case $_fmb in u8*) echo '8 bit' ;; s16*) echo '16 bit' ;; s24*) echo '24 bit' ;;
        s32*) _fmn=$(audio_bits "$1"); if [ -n "$_fmn" ]; then echo "$_fmn bit"; elif [ "$_fmk" != alac ]; then echo '32 bit'; fi ;; float*) echo '32-bit float' ;; double*) echo '64-bit float' ;; esac >> "$TMP/page.lead"
    case $_fmc in 1) echo mono ;; 2) echo stereo ;; ''|0) ;; *) echo "$_fmc channels" ;; esac >> "$TMP/page.lead"
    case $_fmk in pcm_*) echo PCM ;; '') ;; *) printf '%s\n' "$_fmk" | tr 'a-z' 'A-Z' ;; esac >> "$TMP/page.lead"
    [ -z "$_fml" ] || awk -v b="$(wc -c < "$1")" -v s="${_fms:-0}" 'BEGIN { if (s > 0) printf "%d kbps\n", b * 8 / s / 1000 + 0.5 }' >> "$TMP/page.lead"
    # the dialog polls for it
    [ -f "$3-sound.png" ] || files_sound_draw "$1" "$3"
    _fmp=$3-sound.png
    sed -n '8p' "$TMP/page.media" > "$TMP/page.tags"; sed -n '9,10p' "$TMP/page.media" | awk 'NF { s = s (s == "" ? "" : " \302\267 ") $0 } END { if (s != "") print s }' >> "$TMP/page.tags"
    jq -Rn --argjson a "$_fma" --argjson n "${_fms:-0}" --arg p "$_fmp" --argjson h "$FILES_WAVE_PX" '[inputs | select(. != "")] as $l
        | {lines: $l, bold: (if ($l | length) > 0 then [0] else [] end), seconds: $n,
           play: {name: "files_play", arguments: $a, said: "play"}, stop: {name: "files_stop", arguments: {}, said: "stop"}}
          + (if $p == "" then {} else {sound: {picture: $p, wave: $h}} end)' < "$TMP/page.tags" > "$TMP/page.json"
}
files_page_office() {   # files_page_office PATH BASE -- page.json; BASE.txt for spark
    command -v python3 >/dev/null 2>&1 || { files_say "cannot view: python3 is not installed, Enter opens it"; return 0; }
    files_tool python3 -I "$REPO/lib/office.py" "$1" > "$TMP/page.office" 2>/dev/null && jq -e '.lines | length > 0' "$TMP/page.office" >/dev/null 2>&1 \
        || { files_say "cannot view: this document could not be read, Enter opens it"; return 0; }
    jq -r '.lines[]' "$TMP/page.office" > "$2.txt"
    jq -c --arg a "$2.txt" '. + {attach: $a}' "$TMP/page.office" > "$TMP/page.json"
}
files_play() {   # files_play PATH [AT] -- a sound from AT seconds
    files_stop
    # shellcheck disable=SC2086
    mpv $MPV_SAFE --no-video --no-terminal --really-quiet --start="+${2:-0}" -- "$1" </dev/null >/dev/null 2>&1 &
    echo "$!" > "$TMP/play.pid"
}
files_video_here() { wm_session && wm_here && wm_version >/dev/null; }   # files_video_here -- sway answers
files_play_video() {   # files_play_video PATH AT X Y W H -- X Y W H in terminal pixels
    _fvt=$(wm_tree) || { echo "$WM_NAME does not answer"; return 1; }
    _fvd=$(printf '%s' "$_fvt" | jq -r 'first(.. | objects | select(.app_id? == "spark-dialog" and .focused? == true) | "\(.rect.x + .window_rect.x) \(.rect.y + .window_rect.y) \(.fullscreen_mode // 0)") // empty')
    [ -n "$_fvd" ] || { echo "the dialog's window is not found"; return 1; }
    _fvo=$(printf '%s' "$_fvt" | jq -r 'first(.nodes[] | select(.type == "output") | select(any(.. | objects; .app_id? == "spark-dialog" and .focused? == true)) | .name) // empty')
    _fvs=$(wm_outputs | jq -r --arg o "$_fvo" 'first(.[] | select(.name == $o) | .scale) // 1')
    # sway stacks full screen over floating: the dialog goes floating for the play
    _fvsw=''
    if [ -f "$TMP/play.swap" ]; then _fvsw=$(cat "$TMP/play.swap")
    else
        case $_fvd in *' 0') ;; *)
            _fvsw=$(printf '%s' "$_fvt" | jq -r 'first(.. | objects | select(.app_id? == "spark-dialog" and .focused? == true) | "\(.id) \(.geometry.width // 0) \(.geometry.height // 0)") // empty')
            _fvr=$(wm_outputs | jq -r --arg o "$_fvo" 'first(.[] | select(.name == $o) | "\(.rect.width) \(.rect.height) \(.rect.x) \(.rect.y)") // empty')
            [ -n "$_fvsw" ] && [ -n "$_fvr" ] || { echo "the dialog's window is not found"; return 1; }
            # shellcheck disable=SC2086   # four numbers
            set -- "$1" "$2" "$3" "$4" "$5" "$6" $_fvr
            # the bar apart: a sway with no bar refuses it
            wm_cmd "bar mode invisible" >/dev/null 2>&1 || :
            wm_act "con_id=${_fvsw%% *}" "fullscreen disable, resize set $7 $8, move absolute position $9 ${10}" >/dev/null 2>&1 \
                || { wm_cmd "bar mode $(bar_mode)" >/dev/null 2>&1 || :; echo "full screen could not make room for the video"; return 1; }
            printf '%s\n' "$_fvsw" > "$TMP/play.swap" ;;
        esac
    fi
    _fvp=$(sed -n 's/^pad=\([0-9]*\)x\([0-9]*\).*/\1 \2/p' "$HOME/.config/foot/dialog.ini" 2>/dev/null | head -1)
    # sway's units: the corner, foot's padding, the frame scaled
    # shellcheck disable=SC2086   # numbers, split on purpose
    _fvg=$(printf '%s %s %s %s %s %s\n' "$3 $4 $5 $6" ${_fvd% *} ${_fvp:-0 0} | awk -v s="${_fvs:-1}" '{ if (s <= 0) s = 1; printf "%d %d %d %d", $5 + $7 + $1 / s, $6 + $8 + $2 / s, $3 / s, $4 / s }')
    files_stop
    # shellcheck disable=SC2086   # MPV_SAFE is options, split on purpose
    # mpv left to itself fits the screen's width
    mpv $MPV_SAFE --wayland-app-id=spark-preview --no-border --osc=no --osd-level=0 --no-terminal --really-quiet --keep-open=no \
        --geometry="$(printf '%s' "$_fvg" | awk '{ printf "%dx%d", $3, $4 }')" --start="+$2" -- "$1" </dev/null >/dev/null 2>&1 &
    _fvm=$!; echo "$_fvm" > "$TMP/play.pid"
    # never a background and-or list: bash holds the step's answer pipe open
    if [ -n "$_fvsw" ]; then
        ( while pid_running "$_fvm"; do sleep 0.2; done; sleep 0.3
          if [ -f "$TMP/play.pid" ] && pid_running "$(cat "$TMP/play.pid")"; then exit 0; fi
          rm -f "$TMP/play.swap"; files_full_back "$_fvsw" ) </dev/null >/dev/null 2>&1 3>&- 4<&- &
    fi
    # shellcheck disable=SC2086   # four numbers
    set -- $_fvg
    _fvi=0; while [ "$_fvi" -lt 30 ] && ! wm_tree | jq -e 'any(.. | objects; .app_id? == "spark-preview")' >/dev/null 2>&1; do sleep 0.1; _fvi=$((_fvi + 1)); done
    # mapped unseen; placed and shown in one command
    wm_act "app_id=\"spark-preview\"" "floating enable, border none, resize set $3 $4, move absolute position $1 $2, opacity 1" >/dev/null 2>&1 || :
}
pid_running() { kill -0 "$1" 2>/dev/null && ! grep -qs '^State:[[:space:]]*Z' "/proc/$1/status"; }   # pid_running PID -- a zombie is ended; a container may never reap
files_full_back() {   # files_full_back "ID W H" -- full screen again, sized first for leaving
    # shellcheck disable=SC2086   # three numbers
    set -- $1
    _ffb=''; [ "${2:-0}" -gt 0 ] && [ "${3:-0}" -gt 0 ] && _ffb="resize set $2 $3, move position center, "
    wm_act "con_id=$1" "${_ffb}fullscreen enable" >/dev/null 2>&1 || :
    wm_cmd "bar mode $(bar_mode)" >/dev/null 2>&1 || :
}
files_stop() { [ ! -f "$TMP/play.pid" ] || { kill "$(cat "$TMP/play.pid")" 2>/dev/null || :; rm -f "$TMP/play.pid"; }; }
