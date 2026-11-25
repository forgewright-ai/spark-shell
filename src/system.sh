# shellcheck extended-analysis=false
# --- the system provider: the machine as the system place shows it (named tools through v0.152)
# sets: SYSTEM_CHECK SYSTEM_CHECK_FRESH SYSTEM_KEEP SYSTEM_SBOM SYSTEM_SPACE SYSTEM_SPACE_FRESH SYSTEM_SPACE_SHOWN SYSTEM_SPACE_WAIT
# reads: BAR_PROC BAR_SYS PANEL_SEP PM REPO SBOM_JSON STATE_DIR TAB TMP WM_OWN
system_state_names() {   # the section opens (provide, panel): what it kept under tools, its name through v0.152, moves to its name, once; its kept package count goes, a new one is read
    [ ! -d "$STATE_DIR/tools" ] || [ -e "$STATE_DIR/system" ] || mv "$STATE_DIR/tools" "$STATE_DIR/system" 2>/dev/null || :
    [ ! -e "$STATE_DIR/panel/tools.packages" ] || rm -f "$STATE_DIR/panel/tools.packages" 2>/dev/null || :
}
SYSTEM_CHECK=$STATE_DIR/check.last   # the epoch, then spark-shell check's own lines
SYSTEM_CHECK_FRESH=10                # a check younger than this many seconds is read, not run again
system_label() {   # system_label NAME -> the plain name of a check row
    case $1 in
        rc) echo 'shell startup' ;; tools) echo programs ;; terminfo) echo terminal ;; look) echo 'config files' ;;
        font) echo 'console font' ;; quiet) echo 'boot messages' ;; saver) echo 'screen saver' ;; mcp) echo 'spark tools' ;;
        login) echo 'login screen' ;; bar) echo 'status line' ;; top) echo bar ;; storage) echo drives ;; notify) echo notifications ;;
        semantic) echo 'semantic search' ;;
        *) printf '%s\n' "$1" ;;
    esac
}
system_check_keep() {   # system_check_keep FILE -- a check's lines kept with the time it ran
    mkdir_private "$STATE_DIR"
    { date +%s; cat "$1"; } > "$SYSTEM_CHECK.$$" 2>/dev/null && mv "$SYSTEM_CHECK.$$" "$SYSTEM_CHECK" || rm -f "$SYSTEM_CHECK.$$"
}
system_check_run() {   # the check run now, unless the kept one is fresh
    _tct=$(sed -n 1p "$SYSTEM_CHECK" 2>/dev/null)
    case $_tct in ''|*[!0-9]*) _tct=0 ;; esac
    [ $(( $(date +%s) - _tct )) -lt "$SYSTEM_CHECK_FRESH" ] && return 0
    "$REPO/spark-shell" check > /dev/null 2>&1 || :
}
system_check_rows() {   # -> STATUS<tab>NAME<tab>LABEL<tab>DETAIL<tab>FIX, a row each of the kept check
    sed 1d "$SYSTEM_CHECK" 2>/dev/null | awk '
        /^(ok|warn|FAIL) / { st = $1; nm = $2; d = $0; sub(/^[^ ]+ +[^ ]+ +/, "", d); fx = ""
            if (st != "ok") { i = index(d, " -- "); if (i > 0) { fx = substr(d, i + 4); d = substr(d, 1, i - 1) } }
            printf "%s\t%s\t%s\t%s\n", st, nm, d, fx }' | while IFS="$TAB" read -r _tst _tnm _tdt _tfx; do
        printf '%s\t%s\t%s\t%s\t%s\n' "$_tst" "$_tnm" "$(system_label "$_tnm")" "$_tdt" "$_tfx"
    done
}
system_fix_command() {   # system_fix_command FIX -> the spark-shell command a remedy names, its words in parentheses left out; false for an instruction
    _tfc=$(printf '%s' "$1" | sed 's/ *([^)]*)$//')
    printf '%s' "$_tfc" | grep -qE '^spark-shell( [a-z0-9][a-z0-9-]*)+$' || return 1
    printf '%s\n' "$_tfc"
}
system_check_state() {   # -> "2 problems", "1 problem", "no problems", "not checked yet"
    [ -s "$SYSTEM_CHECK" ] || { echo 'not checked yet'; return; }
    _tcn=$(sed 1d "$SYSTEM_CHECK" | grep -cE '^(warn|FAIL) ' || :)
    case $_tcn in 0) echo 'no problems' ;; 1) echo '1 problem' ;; *) echo "$_tcn problems" ;; esac
}
system_menu() {   # -> NAME<tab>STATE<tab>LINE, the six in their order
    printf 'check\t%s\ttest the setup and fix problems\n' "$(system_check_state)"
    printf 'space\t%s\tsee what uses the disk\n' "$(system_space_state)"
    printf 'running\t%s\tsee what uses the cpu and memory\n' "$(system_running_state)"
    printf 'details\t%s\thardware and software details\n' "$(system_details_state)"
    printf 'updates\tspark-shell v%s\tupdate spark-shell and the system\n' "$(panel_version)"
    printf 'software\t%s\tinstalled packages and their licenses\n' "$(system_software_state)"
}
system_os() { sed -n "s/^$1=//p" "${SPARK_OS_RELEASE:-/etc/os-release}" 2>/dev/null | head -1 | tr -d '"'; }   # system_os KEY -> os-release's value
system_space_state() { _tsh=$(storage_here); case $_tsh in *', '*) printf '%s\n' "${_tsh#*, }" ;; *) echo 'the system disk' ;; esac; }   # -> "120.3 GB free"
system_running_state() { _trn=0; for _trp in "$BAR_PROC"/[0-9]*; do [ ! -d "$_trp" ] || _trn=$((_trn + 1)); done; echo "$_trn processes"; }   # -> "412 processes"
system_mem_kb() { awk -v k="$1" '$1 == k ":" { print $2; exit }' "$BAR_PROC/meminfo" 2>/dev/null || :; }   # system_mem_kb MemTotal -> kB
system_details_state() {   # -> "Void Linux, 16 GB"
    _tsn=$(system_os NAME); _tsm=$(system_mem_kb MemTotal)
    _tsg=''; [ -z "$_tsm" ] || _tsg=$(awk -v k="$_tsm" 'BEGIN { printf "%d GB", k / 1048576 + 0.5 }')
    printf '%s\n' "${_tsn:-Linux}${_tsg:+, $_tsg}"
}
system_package_count() {   # -> how many packages the package manager has installed, or nothing
    case $PM in
        xbps) xbps-query -l 2>/dev/null | grep -c . ;; apt) dpkg-query -f '.\n' -W 2>/dev/null | grep -c . ;;
        pacman) pacman -Qq 2>/dev/null | grep -c . ;; dnf|zypper) rpm -qa 2>/dev/null | grep -c . ;;
    esac
}
system_software_state() { _tpc=$(panel_cache system.packages 3600 system_package_count); case $_tpc in ''|0|*[!0-9]*) echo 'no package list' ;; *) echo "$_tpc packages" ;; esac; }
provide_system_rows() {   # -> the system section's rows resource: the six, each with its page as children, then about, whose page is the about section's own
    { system_menu; printf 'about\tlicense and credits\tthe project, the license, the credits\n'; } | jq -Rn --arg sep "$PANEL_SEP" '
        [inputs | split("\t") | {id: ("system:" + .[0]), sign: "blank", text: .[0], tool: null, more: [], columns: [.[1]],
            children: (if .[0] == "about" then "spark-shell://about/rows" else "spark-shell://system/rows/" + .[0] end), group: null, line: (.[0] + " " + $sep + " " + .[2])}]
        | {title: "system", state: "", rows: ., short: [.[].id]}'
}
provide_system_page() {   # provide_system_page PATH -> a row's page, a rows resource: check, check/passed
    case $1 in
        check) system_check_run; system_check_page ;;
        check/passed) system_check_passed ;;
        running) system_running_page ;;
        space) system_space_run; system_space_page ;;
        details) system_details_page ;;
        updates) system_updates_page ;;
        software) system_software_page ;;
        software/apps|software/tools|software/parts) system_software_list "${1#software/}" ;;
        *) return 1 ;;
    esac
}
system_check_page() {   # -> the check's page: problems, fixes, passed, check again
    system_check_rows > "$TMP/check.rows"
    _tca=$(sed -n 1p "$SYSTEM_CHECK" 2>/dev/null); _tcw=''
    case $_tca in ''|*[!0-9]*) ;; *) _tcw=$(date -d "@$_tca" '+%H:%M' 2>/dev/null || date -r "$_tca" '+%H:%M' 2>/dev/null || :) ;; esac
    while IFS="$TAB" read -r _tst _tnm _tlb _tdt _tfx; do
        [ "$_tst" != ok ] || continue
        _tfcm=''; _tfcm=$(system_fix_command "$_tfx") || _tfcm=''
        printf '%s\t%s\t%s\t%s\t%s\n' "$_tnm" "$_tlb" "$_tdt" "$_tfx" "$_tfcm"
    done < "$TMP/check.rows" > "$TMP/check.problems"
    _tcp=$(awk -F '\t' '$1 == "ok" && $4 !~ /^na( |$)/' "$TMP/check.rows" | grep -c . || :)
    _tcna=$(awk -F '\t' '$1 == "ok" && $4 ~ /^na( |$)/' "$TMP/check.rows" | grep -c . || :)
    jq -Rn --arg sep "$PANEL_SEP" --arg passed "$_tcp" --arg na "$_tcna" --arg when "$_tcw" --arg state "$(system_check_state)" '
        def row($id; $text): {id: $id, sign: "blank", text: $text, tool: null, more: [], columns: [], children: null, group: null};
        def gap($n): row("system:gap:" + $n; "") | .muted = true;
        [inputs | split("\t") | {name: .[0], label: .[1], detail: .[2], fix: .[3], command: .[4]}] as $p
        | [$p[] | . as $x | row("system:problem:" + $x.name; $x.label) | .group = "problems"
            | .columns = [$x.detail + (if $x.command == "" and $x.fix != "" then ": " + $x.fix else "" end)]] as $problems
        | ($p | map(select(.command != "") | .command) | reduce .[] as $c ([]; if index([$c]) then . else . + [$c] end)) as $order
        | [$order[] as $c
            | row("system:fix:" + $c; "fix") | .columns = [$c] | .tool = {name: "system_fix", arguments: {command: $c}}
            | .line = ("fix " + $sep + " in a terminal: " + $c)] as $fixes
        | ($problems
           + (if ($fixes | length) > 0 then [gap("1")] + $fixes else [] end)
           + (if ($problems | length) > 0 then [gap("2")] else [] end)
           + (if $passed != "0" then [row("system:passed"; "\($passed) passed") | .children = "spark-shell://system/rows/check/passed"
                | .line = ("\($passed) passed " + $sep + " the checks with no problem")] else [] end)
           + (if $na != "0" then [row("system:na"; "\($na) not applicable") | .muted = true] else [] end)
           + [gap("3"), (row("system:check-again"; "check again") | .columns = (if $when == "" then [] else ["checked at " + $when] end)
                | .tool = {name: "system_check", arguments: {}} | .line = ("check again " + $sep + " runs every test again"))]) as $rows
        | {title: "check", state: $state, rows: $rows, short: []}' < "$TMP/check.problems"
}
system_check_passed() {   # -> the passed checks as a rows resource
    system_check_rows | awk -F '\t' '$1 == "ok" && $4 !~ /^na( |$)/ { printf "%s\t%s\t%s\n", $2, $3, $4 }' | jq -Rn '
        [inputs | split("\t") | {id: ("system:ok:" + .[0]), sign: "blank", text: .[1], tool: null, more: [], columns: [.[2]], children: null, group: null}]
        | {title: "passed", state: "", rows: ., short: []}'
}
system_rows_of() {   # stdin GROUP<tab>LABEL<tab>VALUE -> rows; an empty VALUE is left out
    jq -Rn '[inputs | split("\t") | select(.[2] != "") | {id: ("system:fact:" + .[1]), sign: "blank", text: .[1], tool: null, more: [],
        columns: [.[2]], children: null, group: (if .[0] == "" then null else .[0] end)}]'
}
system_details_facts() {   # -> GROUP<tab>LABEL<tab>VALUE: the machine, the operating system, the desktop
    _tsd=$BAR_SYS/class/dmi/id; _tsv=$(cat "$_tsd/sys_vendor" 2>/dev/null); _tsp=$(cat "$_tsd/product_name" 2>/dev/null)
    case $_tsv in LENOVO) _tsp=$(cat "$_tsd/product_version" 2>/dev/null) ;; ''|'System manufacturer'|'To Be Filled By O.E.M.') ;; *) _tsp="$_tsv $_tsp" ;; esac
    _tsc=$(awk -F ': *' '$1 ~ /^model name/ { print $2; exit }' "$BAR_PROC/cpuinfo" 2>/dev/null | sed 's/([RTMrtm]*)//g; s/ CPU//; s/ @ .*//; s/ with .*//; s/  */ /g; s/ *$//')
    _tsco=$(awk -F ': *' '$1 ~ /^cpu cores/ { print $2; exit }' "$BAR_PROC/cpuinfo" 2>/dev/null || :); _tsth=$(grep -c '^processor' "$BAR_PROC/cpuinfo" 2>/dev/null || :)   # cores where the processor says them, else its threads
    [ -n "$_tsc" ] || _tsc=$(uname -m)
    [ -n "$_tsco" ] || _tsco=$_tsth; [ -z "$_tsco" ] || [ "$_tsco" = 0 ] || _tsc="$_tsc, $_tsco cores"
    _tst=$(system_mem_kb MemTotal); _tsa=$(system_mem_kb MemAvailable); _tsm=''
    [ -z "$_tst" ] || _tsm="$(storage_kb "$_tst")${_tsa:+, $(storage_kb $((_tst - _tsa))) used}"
    _tsg=$(for _d in "$BAR_SYS"/class/drm/card[0-9]*; do [ -L "$_d/device/driver" ] && basename "$(readlink "$_d/device/driver")"; done 2>/dev/null | sort -u | paste -sd, - | sed 's/,/, /g')
    _tsb=''; for _b in "$BAR_SYS"/class/power_supply/BAT*; do
        [ -r "$_b/capacity" ] || continue; _tsb="$(cat "$_b/capacity")%"
        _tsf=$(cat "$_b/energy_full" 2>/dev/null || cat "$_b/charge_full" 2>/dev/null); _tsfd=$(cat "$_b/energy_full_design" 2>/dev/null || cat "$_b/charge_full_design" 2>/dev/null)
        [ -z "$_tsf" ] || [ -z "$_tsfd" ] || [ "$_tsfd" -le 0 ] 2>/dev/null || _tsb="$_tsb, health $(( _tsf * 100 / _tsfd ))%"
        break
    done
    printf 'hardware\tmodel\t%s\nhardware\tprocessor\t%s\nhardware\tmemory\t%s\nhardware\tdisk\t%s\nhardware\tgraphics\t%s\nhardware\tbattery\t%s\n' \
        "$_tsp" "$_tsc" "$_tsm" "$(storage_here)" "$_tsg" "$_tsb"
    _tsu=$(power_up); printf 'operating system\tsystem\t%s\noperating system\tkernel\t%s\noperating system\tinit\t%s\noperating system\tpackages\t%s\noperating system\tuptime\t%s\n' \
        "$(system_os PRETTY_NAME)" "$(uname -r)" "$(init_shape)" "$PM" "${_tsu#up }"
    _tss=''; _tso=''
    if wm_up; then
        _tss=$(wm_version | jq -r '.human_readable // empty' | awk '{ print $1 }')
        _tso=$(wm_outputs | jq -r '[.[] | select(.active) | .name + " " + (.current_mode.width | tostring) + "x" + (.current_mode.height | tostring)] | join(", ")')
    fi
    _tsk=$(spark_bin); _tskv=''; [ -z "$_tsk" ] || _tskv=$("$_tsk" --version 2>/dev/null | sed -n 's/.*spark \([0-9][0-9.]*\).*/\1/p' | head -1)
    printf 'desktop\tsway\t%s\ndesktop\tscreens\t%s\ndesktop\tspark-shell\t%s\ndesktop\tspark-dialog\t%s\ndesktop\tspark\t%s\n' \
        "$_tss" "$_tso" "v$(panel_version)" "$(system_dialog_version)" "$_tskv"
}
system_dialog_version() { _tdv=$(sed -n 's/^version = "\(.*\)"$/v\1/p' "$REPO/component/dialog/Cargo.toml" 2>/dev/null | head -1); printf '%s\n' "$_tdv"; }   # -> the dialog's version as Cargo.toml pins it
system_details_page() {   # -> the details' page: the machine's facts in three groups, then copy details
    system_details_facts | scrub_text | system_rows_of | jq -c --arg sep "$PANEL_SEP" '
        . + [{id: "system:gap:1", sign: "blank", text: "", tool: null, more: [], columns: [], children: null, group: null, muted: true},
             {id: "system:copy-details", sign: "blank", text: "copy details", tool: {name: "system_copy_details", arguments: {}}, more: [], columns: [], children: null, group: null,
              line: ("copy details " + $sep + " to the clipboard, for bug reports")}]
        | {title: "details", state: "", rows: ., short: []}'
}
system_details_text() {   # -> the system's facts as text, a group under its heading, for a bug report
    system_details_facts | scrub_text | awk -F '\t' '$3 != "" { if ($1 != g) { if (g != "") print ""; print $1; g = $1 } printf "  %-12s %s\n", $2, $3 }'
}
system_updates_page() {   # -> the updates page: the releases, update spark-shell, update system
    _tuv=$(panel_version); _tud=''
    [ -z "$_tuv" ] || _tud=$(release_day "$_tuv")
    jq -n --arg sep "$PANEL_SEP" --arg v "v$_tuv${_tud:+, released $_tud}" --arg dv "$(system_dialog_version)" \
        --arg sys "$(system_os PRETTY_NAME | scrub_text)${PM:+, $PM}" --arg up "$(pkg_upgrade_said)" '
        def row($id; $text): {id: $id, sign: "blank", text: $text, tool: null, more: [], columns: [], children: null, group: null};
        [(row("system:fact:spark-shell"; "spark-shell") | .columns = [$v]),
         (if $dv == "" then empty else (row("system:fact:spark-dialog"; "spark-dialog") | .columns = [$dv]) end),
         (row("system:update"; "update spark-shell") | .tool = {name: "system_update", arguments: {}} | .line = ("update spark-shell " + $sep + " in a terminal: spark-shell update")),
         (row("system:gap:1"; "") | .muted = true),
         (row("system:fact:system"; "system") | .columns = [if $up == "" then $sys + " " + $sep + " no supported package manager here" else $sys end]),
         (if $up == "" then empty else (row("system:update-system"; "update system") | .tool = {name: "system_update_system", arguments: {}}
             | .line = ("update system " + $sep + " in a terminal: " + $up)) end)]
        | {title: "updates", state: "", rows: ., short: []}'
}
SYSTEM_SBOM=$STATE_DIR/system/sbom   # the installed list, kept for an hour: reading every license takes seconds
system_sbom_fresh() { _tsbt=$(stat -c %Y "$SYSTEM_SBOM" 2>/dev/null || echo 0); [ -s "$SYSTEM_SBOM" ] && [ $(( $(date +%s) - _tsbt )) -lt 3600 ]; }
system_sbom_warm() {   # the list built ahead in the background when the kept one is old; its own TMP
    system_sbom_fresh && return 0
    mkdir_private "$STATE_DIR/system"; lock_take "$SYSTEM_SBOM.lock" || return 0
    ( TMP=$(mktemp -d) && { sbom_collect >/dev/null 2>&1 || :; [ ! -s "$TMP/sbom" ] || mv "$TMP/sbom" "$SYSTEM_SBOM"; rm -rf "$TMP"; }; lock_drop "$SYSTEM_SBOM.lock" ) </dev/null >/dev/null 2>&1 3>&- 4<&- 5>&- &
}
system_sbom() {   # -> $TMP/sbom, the kept list; one being built ahead is waited for, 9 seconds at most, else built now
    _tsbw=0; while [ -e "$SYSTEM_SBOM.lock" ] && [ "$_tsbw" -lt 45 ]; do sleep 0.2; _tsbw=$((_tsbw + 1)); done
    if system_sbom_fresh; then cp "$SYSTEM_SBOM" "$TMP/sbom"; return 0; fi
    sbom_collect 2>/dev/null || :
    [ -s "$TMP/sbom" ] || return 1
    mkdir_private "$STATE_DIR/system"; cp "$TMP/sbom" "$SYSTEM_SBOM"
}
system_software_page() {   # -> apps, tools and parts, each its count and its list; export
    system_sbom || { jq -n '{title: "software", state: "", rows: [{id: "system:fact:none", sign: "blank", text: "no supported package manager here", tool: null, more: [], columns: [], children: null, group: null, muted: true}], short: []}'; return 0; }
    jq -n --arg sep "$PANEL_SEP" --arg a "$(grep -c '^app	' "$TMP/sbom" || :)" --arg t "$(grep -c '^tool	' "$TMP/sbom" || :)" --arg p "$(grep -c '^part	' "$TMP/sbom" || :)" '
        def row($id; $text): {id: $id, sign: "blank", text: $text, tool: null, more: [], columns: [], children: null, group: null};
        def kind($k; $n; $what): row("system:software:" + $k; $k) | .columns = [$n] | .children = ("spark-shell://system/rows/software/" + $k) | .line = ($k + " " + $sep + " " + $what);
        [kind("apps"; $a; "packages with a desktop entry"), kind("tools"; $t; "packages with commands"), kind("parts"; $p; "libraries and data"),
         (row("system:gap:1"; "") | .muted = true),
         (row("system:export"; "export") | .columns = ["CycloneDX 1.5"] | .tool = {name: "system_export", arguments: {}} | .line = ("export " + $sep + " save the list as a CycloneDX file"))]
        | {title: "software", state: "", rows: ., short: []}'
}
system_software_list() {   # system_software_list apps|tools|parts -> the packages of that kind, a row each
    system_sbom || return 1
    _tsk=${1%s}
    awk -F '\t' -v k="$_tsk" '$1 == k { printf "%s\t%s\t%s\n", $2, $3, $4 }' "$TMP/sbom" | scrub_text | jq -Rn --arg k "$_tsk" --arg l "$1" --arg sep "$PANEL_SEP" '
        def b64: @base64 | gsub("="; "") | gsub("[+]"; "-") | gsub("/"; "_");
        [inputs | split("\t") | ("system:package:" + $k + ":" + .[0]) as $id
            | {id: $id, sign: "blank", text: .[0], tool: null, more: [], columns: [.[1]], children: null, group: null,
               line: ([.[0], .[1], .[2]] | map(select(. != "" and . != "?")) | join(" " + $sep + " ")), page: ("spark-shell://system/page/" + ($id | b64))}]
        | {title: $l, state: "", rows: ., short: []}'
}
system_package_page() {   # system_package_page KIND:NAME -> a package's page
    system_sbom || return 1
    _tpk=${1%%:*}; _tpn=${1#*:}
    awk -F '\t' -v k="$_tpk" -v n="$_tpn" '$1 == k && $2 == n { print; exit }' "$TMP/sbom" > "$TMP/package.one"
    [ -s "$TMP/package.one" ] || return 1
    IFS="$TAB" read -r _ _ _tpv _tpl _ _tpd _tpc _ < "$TMP/package.one"
    case $_tpk in app) _tpt=app ;; tool) _tpt=tool ;; *) _tpt=part ;; esac
    printf 'description\t%s\nversion\t%s\nlicense\t%s\ncommands\t%s\ntype\t%s\nsource\t%s\n' "$_tpd" "$_tpv" "$(printf '%s' "$_tpl" | sed 's/^?$//')" "$(printf '%s' "$_tpc" | tr ' ' '\n' | sed 's|.*/||' | paste -sd' ' -)" "$_tpt" "$PM" \
        | page_of "$_tpn" ''
}
SYSTEM_SPACE=$STATE_DIR/system/space   # the last measure: at (the epoch, then done or part), home, cache (du's KB<tab>PATH lines), trash, packages (KB)
SYSTEM_SPACE_FRESH=60                 # a measure younger than this many seconds is read, not made again
SYSTEM_SPACE_WAIT=8                   # seconds a measure may take: the page's read is answered within the dialog's 10
system_package_cache() {   # -> the package manager's download cache, or nothing
    case $PM in
        xbps) echo /var/cache/xbps ;; apt) echo /var/cache/apt/archives ;; pacman) echo /var/cache/pacman/pkg ;;
        dnf) if [ -d /var/cache/libdnf5 ]; then echo /var/cache/libdnf5; else echo /var/cache/dnf; fi ;; zypper) echo /var/cache/zypp/packages ;;
    esac
}
system_cache_dir() { printf '%s\n' "${XDG_CACHE_HOME:-$HOME/.cache}"; }
system_trash_dir() { printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}/Trash"; }
system_tilde() {   # system_tilde PATH -> the path with your home as ~
    _ttr=$(files_home_root)
    case $1 in "$HOME"|"$_ttr") echo '~' ;; "$HOME"/*) printf '%s/%s\n' '~' "${1#"$HOME"/}" ;; "$_ttr"/*) printf '%s/%s\n' '~' "${1#"$_ttr"/}" ;; *) printf '%s\n' "$1" ;; esac
}
system_space_measure() {   # the measure made now, SYSTEM_SPACE_WAIT seconds at most, the four du side by side
    mkdir -p "$SYSTEM_SPACE"
    _tsk=$(system_package_cache)
    { timeout "$SYSTEM_SPACE_WAIT" du -x -d1 -k "$(files_home_root)" > "$SYSTEM_SPACE/home.new" 2>/dev/null; echo $? > "$SYSTEM_SPACE/home.rc"; } & _tm1=$!
    { timeout "$SYSTEM_SPACE_WAIT" du -x -d1 -k "$(system_cache_dir)" > "$SYSTEM_SPACE/cache.new" 2>/dev/null || :; } & _tm2=$!
    { timeout "$SYSTEM_SPACE_WAIT" du -sk "$(system_trash_dir)" 2>/dev/null | cut -f1 > "$SYSTEM_SPACE/trash.new" || :; } & _tm3=$!
    { [ -z "$_tsk" ] || timeout "$SYSTEM_SPACE_WAIT" du -sk "$_tsk" 2>/dev/null | cut -f1 > "$SYSTEM_SPACE/packages.new" || :; } & _tm4=$!
    wait "$_tm1" "$_tm2" "$_tm3" "$_tm4" 2>/dev/null || :   # these four alone: a provider may have a watcher in the background
    for _f in home cache trash packages; do
        if [ -f "$SYSTEM_SPACE/$_f.new" ]; then mv -f "$SYSTEM_SPACE/$_f.new" "$SYSTEM_SPACE/$_f"; else : > "$SYSTEM_SPACE/$_f"; fi
    done
    _tmd='done'; [ "$(cat "$SYSTEM_SPACE/home.rc" 2>/dev/null)" != 124 ] || _tmd='part'   # 124 is timeout's own exit: du was stopped
    printf '%s %s\n' "$(date +%s)" "$_tmd" > "$SYSTEM_SPACE/at"
}
system_space_run() {   # the measure made now, unless the kept one is fresh
    _tsa=$(cut -d' ' -f1 "$SYSTEM_SPACE/at" 2>/dev/null)
    case $_tsa in ''|*[!0-9]*) _tsa=0 ;; esac
    [ $(( $(date +%s) - _tsa )) -lt "$SYSTEM_SPACE_FRESH" ] || system_space_measure
}
system_space_folders() {   # -> KB<tab>NAME<tab>PATH, home's folders, the largest first; the app caches left out, the trash taken out of its folder
    _tfr=$(files_home_root); _tfc=$(realpath "$(system_cache_dir)" 2>/dev/null || system_cache_dir); _tft=$(realpath "$(system_trash_dir)" 2>/dev/null || system_trash_dir)
    awk -F '\t' -v root="$_tfr" -v cache="$_tfc" -v trash="$_tft" -v tk="$(cat "$SYSTEM_SPACE/trash" 2>/dev/null)" '
        $2 == root || $2 == cache { next }
        { k = $1; if (tk != "" && index(trash "/", $2 "/") == 1) k -= tk; if (k < 0) k = 0; n = $2; sub(/.*\//, "", n); printf "%d\t%s\t%s\n", k, n, $2 }' "$SYSTEM_SPACE/home" 2>/dev/null | sort -t "$TAB" -k1,1nr
}
system_space_loose() {   # -> the KB of the files directly in home: the whole, less its folders; nothing when the measure did not end
    [ "$(cut -d' ' -f2 "$SYSTEM_SPACE/at" 2>/dev/null)" = 'done' ] || return 0
    awk -F '\t' -v root="$(files_home_root)" '$2 == root { t = $1; next } { s += $1 } END { if (t != "") { d = t - s; print (d < 0 ? 0 : d) } }' "$SYSTEM_SPACE/home" 2>/dev/null
}
SYSTEM_SPACE_SHOWN=6   # home's folders listed by name; the rest are one row
system_space_page() {   # -> the space page: the disk, cleanup, home's folders, measure again
    _tsp=$(cut -d' ' -f2 "$SYSTEM_SPACE/at" 2>/dev/null); _tsw=$(cut -d' ' -f1 "$SYSTEM_SPACE/at" 2>/dev/null)
    system_space_folders > "$TMP/space.folders"
    _tsc=$(awk -F '\t' -v c="$(realpath "$(system_cache_dir)" 2>/dev/null || system_cache_dir)" '$2 == c { print $1 }' "$SYSTEM_SPACE/cache" 2>/dev/null)
    while IFS="$TAB" read -r _k _n _p; do
        _h=''; case $_n in .*) _h=1 ;; esac
        printf '%s\t%s\t%s\t%s\t%s\n' "$_n" "$(files_size $((_k * 1024)))" "$_h" "$(files_uri "$_p")" "$(system_tilde "$_p")"
    done < "$TMP/space.folders" > "$TMP/space.rows"
    _tsl=$(system_space_loose)
    jq -Rn --arg sep "$PANEL_SEP" --arg disk "$(storage_here)" --arg shown "$SYSTEM_SPACE_SHOWN" \
        --arg trash "$(_k=$(cat "$SYSTEM_SPACE/trash" 2>/dev/null); [ -z "$_k" ] || files_size $((_k * 1024)))" \
        --arg pkg "$(_k=$(cat "$SYSTEM_SPACE/packages" 2>/dev/null); [ -z "$_k" ] || files_size $((_k * 1024)))" --arg clean "$(pkg_clean_said)" \
        --arg cache "$([ -z "$_tsc" ] || files_size $((_tsc * 1024)))" --arg cached "$(system_tilde "$(system_cache_dir)")" \
        --arg loose "$([ -z "$_tsl" ] || files_size $((_tsl * 1024)))" --arg home "$(files_uri "$(files_home_root)")" \
        --arg rest "$(awk -F '\t' -v n="$SYSTEM_SPACE_SHOWN" 'NR > n { c++; k += $1 } END { if (c) printf "%d\t%d\n", c, k }' "$TMP/space.folders")" \
        --arg restsize "$(awk -F '\t' -v n="$SYSTEM_SPACE_SHOWN" 'NR > n { k += $1 } END { print k * 1024 }' "$TMP/space.folders" | { read -r _b; files_size "${_b:-0}"; })" \
        --arg part "$_tsp" --arg at "$([ -z "$_tsw" ] || date -d "@$_tsw" +%H:%M 2>/dev/null || date -r "$_tsw" +%H:%M 2>/dev/null)" '
        def b64: @base64 | gsub("="; "") | gsub("[+]"; "-") | gsub("/"; "_");
        def row($id; $text): {id: $id, sign: "blank", text: $text, tool: null, more: [], columns: [], children: null, group: null};
        [inputs | split("\t") | {name: .[0], size: .[1], hidden: (.[2] == "1"), uri: .[3], path: .[4]}] as $f
        | ($shown | tonumber) as $n
        | [(row("system:fact:system disk"; "system disk") | .columns = [if $disk == "" then "?" else $disk end]),
           (row("system:trash"; "trash") | .group = "cleanup" | .columns = [$trash] | .children = "spark-shell://files/rows/trash"
               | .line = ("trash " + $sep + " open in files to restore or empty")),
           (if $clean == "" then empty else (row("system:clean-packages"; "package cache") | .group = "cleanup" | .columns = [$pkg]
               | .tool = {name: "system_clean_packages", arguments: {}} | .line = ("package cache " + $sep + " clean: " + $clean)) end),
           (row("system:caches"; "app caches") | .group = "cleanup" | .columns = [$cache] | .page = ("spark-shell://system/page/" + ("system:space:caches" | b64))
               | .line = ("app caches " + $sep + " " + $cached + " by folder")),
           ($f[:$n][] | . as $d | ("system:folder:" + $d.name) as $id
               | row($id; $d.name) | .group = "home" | .columns = [$d.size]
               | .line = ([$d.name, $d.size, (if $d.hidden then "hidden folder" else "folder" end)] | join(" " + $sep + " "))
               | .page = ("spark-shell://system/page/" + ($id | b64))
               | (if $d.hidden then . else .children = $d.uri end)),
           (if $loose == "" then empty else (row("system:folder:~"; "files in home") | .group = "home" | .columns = [$loose] | .children = $home
               | .line = ("files in home " + $sep + " " + $loose + " " + $sep + " files directly in ~")) end),
           (if $rest == "" then empty else ($rest | split("\t")) as $r | (row("system:space:more"; (if $r[0] == "1" then "1 more folder" else $r[0] + " more folders" end)) | .group = "home" | .columns = [$restsize]) end),
           (if $part == "part" then (row("system:space:part"; "some folders took too long to measure") | .group = "home" | .muted = true) else empty end),
           (row("system:gap:1"; "") | .muted = true),
           (row("system:measure"; "measure again") | .columns = [if $at == "" then "not measured yet" else "measured at " + $at end]
               | .tool = {name: "system_measure", arguments: {}} | .line = ("measure again " + $sep + " what uses the disk now"))]
        | {title: "space", state: (if $disk == "" then "" else ($disk | sub("^[^,]*, "; "")) end), rows: ., short: []}' < "$TMP/space.rows"
}
system_space_view() {   # system_space_view caches|folder:NAME -> a page of its largest folders; a home folder is measured now
    case $1 in
        caches) _tvp=$(realpath "$(system_cache_dir)" 2>/dev/null || system_cache_dir); cp "$SYSTEM_SPACE/cache" "$TMP/view.du" 2>/dev/null || : > "$TMP/view.du"; _tvt='app caches' ;;
        folder:?*) _tvn=${1#folder:}; case $_tvn in */*|.|..) return 1 ;; esac
            _tvp=$(files_home_root)/$_tvn; [ -d "$_tvp" ] || return 1; _tvt=$_tvn
            timeout 5 du -x -d1 -k "$_tvp" > "$TMP/view.du" 2>/dev/null || : ;;   # stopped at 5 seconds, the folder's own total is missing: said below
        *) return 1 ;;
    esac
    _tvk=$(awk -F '\t' -v p="$_tvp" '$2 == p { print $1 }' "$TMP/view.du")
    _tvw="$([ -z "$_tvk" ] || files_size $((_tvk * 1024))) in $(system_tilde "$_tvp")"; [ -n "$_tvk" ] || _tvw="$(system_tilde "$_tvp"), measured in part"
    awk -F '\t' -v p="$_tvp" '$2 != p { n = $2; sub(/.*\//, "", n); printf "%d\t%s\n", $1, n }' "$TMP/view.du" | sort -t "$TAB" -k1,1nr | head -12 \
        | while IFS="$TAB" read -r _k _n; do printf '%s\t%s\n' "$_n" "$(files_size $((_k * 1024)))"; done | page_of "$_tvt" "$_tvw"
}
system_running_read() {   # -> $TMP/running.tsv, the programs now, sway's windows by process id
    : > "$TMP/running.windows"
    ! wm_up || wm_tree | jq -r '.. | objects | select((.type == "con" or .type == "floating_con") and (.pid // 0) > 0) | "\(.pid)\t\(.id)"' > "$TMP/running.windows" 2>/dev/null || :
    python3 -I "$REPO/lib/running.py" list "$BAR_PROC" "$TMP/running.state" "$TMP/running.windows" > "$TMP/running.tsv" 2>/dev/null
}
system_users() { awk -F: '{ printf "%s\t%s\n", $3, $1 }' /etc/passwd 2>/dev/null | jq -Rn '[inputs | split("\t") | {(.[0]): .[1]}] | add // {}'; }   # -> {"0": "root",...}
SYSTEM_KEEP="$WM_OWN spark-shell spark-dialog spark-bar spark-winpad spark-wallpaper dbus-daemon pipewire pipewire-pulse wireplumber"   # never ended from here: the desktop's own parts and the dialog
system_running_page() {   # -> every program, the busiest first, with put in front and end
    system_running_read
    jq -Rn --arg sep "$PANEL_SEP" --arg me "$(id -u)" --argjson users "$(system_users)" --arg keep " $SYSTEM_KEEP " --arg state "$(system_running_state)" '
        def b64: @base64 | gsub("="; "") | gsub("[+]"; "-") | gsub("/"; "_");
        def one: (. * 10 | round) as $t | "\($t / 10 | floor).\($t % 10)";
        def size: if . < 1024 then "\(.) B" elif . < 1048576 then "\(. / 1024 | floor) KB" elif . < 1073741824 then "\(. / 1048576 | one) MB" else "\(. / 1073741824 | one) GB" end;
        [inputs | split("\t") | {name: .[0], cpu: (.[1] | tonumber), private: (.[2] | tonumber), count: .[4], uids: (.[5] | split(",")), window: .[9]}
            | . as $g | ($g.uids == [$me]) as $mine | ("system:program:" + $g.name) as $id
            | ($g.uids | map($users[.] // .) | join(", ")) as $who
            | {id: $id, sign: "blank", text: $g.name, more: [], children: null, group: null,
               columns: ["\($g.cpu)%", ($g.private | size)],
               wide: ["\($g.cpu)% cpu", ($g.private | size), (if $g.count == "1" then "1 process" else $g.count + " processes" end)],
               line: ([$g.name, "\($g.cpu)% cpu", ($g.private | size), (if $g.count == "1" then "1 process" else $g.count + " processes" end)]
                   + (if $mine then [] else ["user " + $who] end) | join(" " + $sep + " ")),
               page: ("spark-shell://system/page/" + ($id | b64)),
               tool: (if $g.window != "" then {name: "system_front", arguments: {name: $g.name}, said: "put in front"} else null end)}
            | .more = (if $mine and ($keep | contains(" " + $g.name + " ") | not) then [{name: "system_end", arguments: {name: $g.name}, said: "end"}] else [] end)]
        | {title: "running", state: $state, rows: ., short: []}' < "$TMP/running.tsv"
}
system_program() {   # system_program NAME -> its line of the last read (read now when there is none)
    [ -s "$TMP/running.tsv" ] || system_running_read
    awk -F '\t' -v n="$1" '$1 == n { print; exit }' "$TMP/running.tsv"
}
system_program_page() {   # system_program_page NAME -> a program's page
    _tpl=$(system_program "$1"); [ -n "$_tpl" ] || return 1
    printf '%s\n' "$_tpl" > "$TMP/program.one"
    IFS="$TAB" read -r _tpn _tpc _tpp _tpr _tpk _tpu _tps _tpi _tpm _ < "$TMP/program.one"
    _tpw=$(printf '%s\n' "$_tpu" | tr ',' '\n' | while read -r _u; do if [ "$_u" = "$(id -u)" ]; then echo you; else awk -F: -v u="$_u" '$3 == u { print $1; f = 1 } END { if (!f) print "user " u }' /etc/passwd; fi; done | paste -sd, - | sed 's/,/, /g')
    _tpd=$(printf '%s' "$_tpi" | awk '{ s = ""; for (i = 1; i <= NF && i <= 4; i++) s = s (i > 1 ? ", " : "") $i; if (NF > 4) s = s " and " (NF - 4) " more"; print s }')
    _tpt=$(date -d "@$_tps" '+%H:%M' 2>/dev/null || date -r "$_tps" '+%H:%M' 2>/dev/null || :)
    [ "$(date -d "@$_tps" +%F 2>/dev/null)" = "$(date +%F)" ] || _tpt=$(date -d "@$_tps" '+%e %b %H:%M' 2>/dev/null | sed 's/^ *//' || :)
    printf 'processes\t%s\nids\t%s\nuser\t%s\nstarted\t%s\ncpu\t%s%%\nmemory\t%s private, %s resident\ncommand\t%s\n' \
        "$_tpk" "$_tpd" "$_tpw" "$_tpt" "$_tpc" "$(files_size "$_tpp")" "$(files_size "$_tpr")" "$_tpm" | page_of "$_tpn" ''
}
system_dialog_tree() {   # -> the pids never ended from here: this provider's ancestors, and everything under the dialog
    _tdp=$$; _tdd=''
    while [ -n "$_tdp" ] && [ "$_tdp" != 0 ] && [ "$_tdp" != 1 ]; do
        echo "$_tdp"
        [ "$(cat "$BAR_PROC/$_tdp/comm" 2>/dev/null)" != spark-dialog ] || _tdd=$_tdp
        _tdp=$(awk '{ sub(/^.*\) /, ""); print $2 }' "$BAR_PROC/$_tdp/stat" 2>/dev/null)
    done
    [ -z "$_tdd" ] || python3 -I "$REPO/lib/running.py" tree "$BAR_PROC" "$_tdd" 2>/dev/null
}
system_gate() {   # system_gate ACTION [ARG] -> ARG as the step takes it (exit 0), or why not (exit 1)
    case $1 in
        check|copy-details|update|export|measure) echo ''; return 0 ;;
        clean-packages) [ -n "$(pkg_clean_said)" ] || { echo "no supported package manager here"; return 1; }; echo ''; return 0 ;;
        update-system) [ -n "$(pkg_upgrade_said)" ] || { echo "no supported package manager here"; return 1; }; echo ''; return 0 ;;
        front) _tgl=$(system_program "$2"); [ -n "$_tgl" ] || { echo "$2 is not running"; return 1; }
            [ -n "$(printf '%s' "$_tgl" | cut -f10)" ] || { echo "$2 has no window"; return 1; }
            printf '%s\n' "$2"; return 0 ;;
        end) case " $SYSTEM_KEEP " in *" $2 "*) case $2 in sway) echo "sway is the desktop: use logout in power" ;; spark-dialog) echo "the dialog closes with Esc" ;; *) echo "$2 is part of the desktop: use logout in power" ;; esac; return 1 ;; esac
            system_running_read; _tgl=$(system_program "$2"); [ -n "$_tgl" ] || { echo "$2 is not running"; return 1; }
            _tgu=$(printf '%s' "$_tgl" | cut -f6)
            [ "$_tgu" = "$(id -u)" ] || { echo "$2 belongs to $(printf '%s\n' "$_tgu" | tr ',' '\n' | grep -vx "$(id -u)" | head -1 | while read -r _u; do awk -F: -v u="$_u" '$3 == u { print $1; f = 1 } END { if (!f) print "user " u }' /etc/passwd; done) and cannot be ended here"; return 1; }
            printf '%s\n' "$2"; return 0 ;;
        fix) _tgc=$(system_fix_command "$2") || { echo "$2 is not a fix the last check gave"; return 1; }
            system_check_rows | while IFS="$TAB" read -r _tst _tnm _tlb _tdt _tfx; do [ "$_tst" = ok ] || system_fix_command "$_tfx" 2>/dev/null || :; done | grep -qxF -- "$_tgc" \
                || { echo "$2 is not a fix the last check gave"; return 1; }
            printf '%s\n' "$_tgc"; return 0 ;;
    esac
    echo "$1 is not something system does"; return 1
}
system_act() {   # system_act ACTION [ARG] -> one line; exit 1 when it was not done
    case $1 in
        check) "$REPO/spark-shell" check > /dev/null 2>&1 || :
            [ -s "$SYSTEM_CHECK" ] || { echo "the check printed nothing"; return 1; }
            echo "checked: $(system_check_state)" ;;
        fix) system_terminal "$2" 'spark-shell check' ;;   # the check runs again when the fix ends: the menu's count is the fix's result
        update) system_terminal 'spark-shell update' ;;
        measure) system_space_measure; echo "measured: $(system_space_state)" ;;
        clean-packages) system_terminal "$(pkg_clean_said)" ;;
        front) _tfc=$(system_program "$2" | cut -f10)
            wm_act "con_id=$_tfc" "focus" >/dev/null 2>&1 || { echo "$2 did not come to front"; return 1; }
            : > "$TMP/opened"; echo "$2 in front" ;;
        end) system_dialog_tree | sort -u > "$TMP/end.keep"
            system_program "$2" | cut -f8 | tr ' ' '\n' | grep -vxFf "$TMP/end.keep" | grep . > "$TMP/end.pids" || { echo "$2 is part of the dialog: Esc closes it"; return 1; }
            while read -r _p; do kill -TERM "$_p" 2>/dev/null || :; done < "$TMP/end.pids"   # the shell's own kill: an external one is procps', not on every machine
            _tew=0; while [ "$_tew" -lt 25 ]; do
                # a zombie has ended: its parent has yet to reap it
                _tel=''; while read -r _p; do [ ! -d "$BAR_PROC/$_p" ] || grep -qs '^State:[[:space:]]*Z' "$BAR_PROC/$_p/status" || { _tel=1; break; }; done < "$TMP/end.pids"
                [ -n "$_tel" ] || break; sleep 0.2; _tew=$((_tew + 1))
            done
            [ -z "$_tel" ] || { echo "$2 is still running after 5 seconds"; return 1; }
            echo "$2 ended" ;;
        update-system) system_terminal "$(pkg_upgrade_said)" ;;
        copy-details) wm_copy_here || { echo "$(wm_missing copy)"; return 1; }
            system_details_text | wm_copy 2>/dev/null || { echo "cannot copy: the clipboard did not take it"; return 1; }
            echo "details copied" ;;
        export) _tex=$("$REPO/spark-shell" sbom --json 2>&1) || { printf '%s
' "$_tex" | tail -1; return 1; }
            _tep=${SBOM_JSON#"$HOME"}; [ "$_tep" = "$SBOM_JSON" ] || _tep="~$_tep"; echo "saved $_tep" ;;
        *) echo "$1 is not something system does"; return 1 ;;
    esac
}
system_terminal() {   # system_terminal LINE [THEN] -- LINE in a terminal window that waits for Enter; THEN a spark-shell command run after it
    wm_up || { echo "a terminal window needs the desktop"; return 1; }
    mkdir_private "$STATE_DIR/system"
    _tts=$(mktemp "$STATE_DIR/system/run.XXXXXX") || { echo "could not open a terminal"; return 1; }
    case $1 in spark-shell|'spark-shell '*) _ttc="$REPO/$1" ;; *) _ttc=$1 ;; esac
    {
        printf '#!/bin/sh\nrm -f "$0"\nprintf %s\n%s\n' "'%s\\n\\n' '$1'" "$_ttc"
        case ${2:-} in spark-shell|'spark-shell '*) printf 'printf %s\n%s\n' "'\\n%s\\n\\n' '$2'" "$REPO/$2" ;; esac
        printf 'printf %s\nread _\n' "'\\npress Enter to close\\n'"
    } > "$_tts"
    _wr=0; win_exec "$(term_run_bare "sh $_tts")" || _wr=$?
    [ "$_wr" -ne 2 ] || { rm -f "$_tts"; echo "could not open a terminal"; return 1; }
    [ "$_wr" -eq 0 ] || { echo "the terminal opened no window"; return 1; }
    : > "$TMP/opened"; echo "opened a terminal: $1"
}
help_keys() {   # -> SUBJECT<tab>WHAT<tab>BINDING<tab>KEY, a desktop key a row; BINDING may be empty
    printf '%s\n' \
        "windows	open a terminal	terminal.open	Super+Return" \
        "windows	close the window	window.close	Super+Shift+q" \
        "windows	move focus		Super+h j k l" \
        "windows	snap the window to a half or a quarter		Super+arrow" \
        "windows	maximize the window		Super+Up Up" \
        "windows	minimize the window		Super+Down Down" \
        "windows	bring back a window from the pad	desktop.desktop-pad-keys	Super+minus" \
        "windows	float or tile the window	desktop.desktop-window-float	Super+Shift+space" \
        "windows	make the window full screen	window.fullscreen	Super+f" \
        "windows	tabbed layout	layout.tabs	Super+w" \
        "windows	stacked layout	layout.stack	Super+Shift+s" \
        "windows	side-by-side layout	layout.toggle-split	Super+e" \
        "workspaces	go to a workspace		Super+1..0" \
        "workspaces	move the window to a workspace		Super+Shift+1..0" \
        "workspaces	previous or next workspace		Super+Ctrl+Left  Right" \
        "desktop	open home	home.open	Super+space" \
        "desktop	lock the screen	desktop.desktop-lock	Super+Escape" \
        "desktop	capture the screen	desktop.desktop-capture-screen	Print" \
        "desktop	capture an area	desktop.desktop-capture-area	Shift+Print" \
        "desktop	capture the window	desktop.desktop-capture-window	Super+Print" \
        "desktop	next keyboard layout	desktop.desktop-keyboard-next	Super+Ctrl+space" \
        "desktop	put the keyboard on the bar	desktop.bar-keys	Super+equal"
}
provide_about_rows() {   # -> the about section's rows resource: the facts, project, license, credits, then help's keys
    _av=$(panel_version); _ad=''
    [ -z "$_av" ] || _ad=$(release_day "$_av")
    _ap=$REPO; case $_ap in "$HOME"/*) _ap="~${_ap#"$HOME"}" ;; esac
    _an=$(grep -c '^- ' "$REPO/CREDITS.md" 2>/dev/null || echo 0)
    _am=$(python3 "$REPO/lib/home.py" map "$(wm_config_template)" 2>/dev/null) || _am='{}'   # the keys as bound now, your overrides in
    help_keys | scrub_text | jq -Rn --arg v "$_av" --arg d "$_ad" --arg p "$_ap" --arg n "$_an" --argjson m "$_am" '
        def b64: @base64 | gsub("="; "") | gsub("[+]"; "-") | gsub("/"; "_");
        def row(id; text; tool; cols): {id: id, sign: "blank", text: text, tool: tool, more: [], columns: cols, children: null, group: null};
        [inputs | split("\t")] | to_entries | map(.key as $i | .value as $r
            | row("about:key:" + ($i | tostring); $r[1]; null; []) | .group = $r[0]
            | .key = (if $r[2] != "" and ($m[$r[2]] // "") != "" then $m[$r[2]] else $r[3] end)) as $keys
        | (if $d == "" then [] else [row("about:released"; "released " + $d; null; [])] end)
          + [(row("about:project"; "project"; {name: "about_site", arguments: {}}; ["github.com/forgewright-ai/spark-shell"]) | .sign = "opens" | .wide = ["opens in the browser"]),
             (row("about:license"; "license"; null; ["MIT"]) | .wide = ["MIT", "LICENSE in " + $p] | .page = ("spark-shell://about/page/" + ("about:license" | b64))),
             (row("about:credits"; "credits"; null; [$n + " projects and their licenses"]) | .wide = [$n + " projects and their licenses", "CREDITS.md in " + $p] | .page = ("spark-shell://about/page/" + ("about:credits" | b64))),
             row("about:installed"; "installed at " + $p; null; []),
             (row("about:open"; "spark-shell " + $v; {name: "about_open", arguments: {}}; []) | .sign = "opens")]
          + $keys
        | {title: "about", rows: ., short: ["about:open"]}'
}
