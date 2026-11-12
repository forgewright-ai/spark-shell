# shellcheck extended-analysis=false
# --- the tools provider
# sets: TOOLS_CHECK TOOLS_CHECK_FRESH TOOLS_KEEP TOOLS_SBOM TOOLS_SPACE TOOLS_SPACE_FRESH TOOLS_SPACE_SHOWN TOOLS_SPACE_WAIT
# reads: BAR_PROC BAR_SYS PANEL_SEP PM REPO SBOM_JSON STATE_DIR TAB TMP WM_OWN
TOOLS_CHECK=$STATE_DIR/check.last   # the epoch, then spark-shell check's own lines
TOOLS_CHECK_FRESH=10                # a check younger than this many seconds is read, not run again
tools_label() {   # tools_label NAME -> the plain name of a check row
    case $1 in
        rc) echo 'shell startup' ;; tools) echo programs ;; terminfo) echo terminal ;; look) echo 'config files' ;;
        font) echo 'console font' ;; quiet) echo 'boot messages' ;; saver) echo 'screen saver' ;; mcp) echo 'spark tools' ;;
        login) echo 'login screen' ;; bar) echo 'status line' ;; top) echo bar ;; storage) echo drives ;; notify) echo notifications ;;
        semantic) echo 'semantic search' ;;
        *) printf '%s\n' "$1" ;;
    esac
}
tools_check_keep() {   # tools_check_keep FILE -- a check's lines kept with the time it ran
    mkdir_private "$STATE_DIR"
    { date +%s; cat "$1"; } > "$TOOLS_CHECK.$$" 2>/dev/null && mv "$TOOLS_CHECK.$$" "$TOOLS_CHECK" || rm -f "$TOOLS_CHECK.$$"
}
tools_check_run() {   # the check run now, unless the kept one is fresh
    _tct=$(sed -n 1p "$TOOLS_CHECK" 2>/dev/null)
    case $_tct in ''|*[!0-9]*) _tct=0 ;; esac
    [ $(( $(date +%s) - _tct )) -lt "$TOOLS_CHECK_FRESH" ] && return 0
    "$REPO/spark-shell" check > /dev/null 2>&1 || :
}
tools_check_rows() {   # -> STATUS<tab>NAME<tab>LABEL<tab>DETAIL<tab>FIX, a row each of the kept check
    sed 1d "$TOOLS_CHECK" 2>/dev/null | awk '
        /^(ok|warn|FAIL) / { st = $1; nm = $2; d = $0; sub(/^[^ ]+ +[^ ]+ +/, "", d); fx = ""
            if (st != "ok") { i = index(d, " -- "); if (i > 0) { fx = substr(d, i + 4); d = substr(d, 1, i - 1) } }
            printf "%s\t%s\t%s\t%s\n", st, nm, d, fx }' | while IFS="$TAB" read -r _tst _tnm _tdt _tfx; do
        printf '%s\t%s\t%s\t%s\t%s\n' "$_tst" "$_tnm" "$(tools_label "$_tnm")" "$_tdt" "$_tfx"
    done
}
tools_fix_command() {   # tools_fix_command FIX -> the spark-shell command a remedy names, its words in parentheses left out; false for an instruction
    _tfc=$(printf '%s' "$1" | sed 's/ *([^)]*)$//')
    printf '%s' "$_tfc" | grep -qE '^spark-shell( [a-z0-9][a-z0-9-]*)+$' || return 1
    printf '%s\n' "$_tfc"
}
tools_check_state() {   # -> "2 problems", "1 problem", "no problems", "not checked yet"
    [ -s "$TOOLS_CHECK" ] || { echo 'not checked yet'; return; }
    _tcn=$(sed 1d "$TOOLS_CHECK" | grep -cE '^(warn|FAIL) ' || :)
    case $_tcn in 0) echo 'no problems' ;; 1) echo '1 problem' ;; *) echo "$_tcn problems" ;; esac
}
tools_menu() {   # -> NAME<tab>STATE<tab>LINE, the six in their order
    printf 'check\t%s\ttest the setup and fix problems\n' "$(tools_check_state)"
    printf 'space\t%s\tsee what uses the disk\n' "$(tools_space_state)"
    printf 'running\t%s\tsee what uses the cpu and memory\n' "$(tools_running_state)"
    printf 'system\t%s\thardware and software details\n' "$(tools_system_state)"
    printf 'updates\tspark-shell v%s\tupdate spark-shell and the system\n' "$(panel_version)"
    printf 'software\t%s\tinstalled packages and their licenses\n' "$(tools_software_state)"
}
tools_os() { sed -n "s/^$1=//p" "${SPARK_OS_RELEASE:-/etc/os-release}" 2>/dev/null | head -1 | tr -d '"'; }   # tools_os KEY -> os-release's value
tools_space_state() { _tsh=$(storage_here); case $_tsh in *', '*) printf '%s\n' "${_tsh#*, }" ;; *) echo 'the system disk' ;; esac; }   # -> "120.3 GB free"
tools_running_state() { _trn=0; for _trp in "$BAR_PROC"/[0-9]*; do [ ! -d "$_trp" ] || _trn=$((_trn + 1)); done; echo "$_trn processes"; }   # -> "412 processes"
tools_mem_kb() { awk -v k="$1" '$1 == k ":" { print $2; exit }' "$BAR_PROC/meminfo" 2>/dev/null || :; }   # tools_mem_kb MemTotal -> kB
tools_system_state() {   # -> "Void Linux, 16 GB"
    _tsn=$(tools_os NAME); _tsm=$(tools_mem_kb MemTotal)
    _tsg=''; [ -z "$_tsm" ] || _tsg=$(awk -v k="$_tsm" 'BEGIN { printf "%d GB", k / 1048576 + 0.5 }')
    printf '%s\n' "${_tsn:-Linux}${_tsg:+, $_tsg}"
}
tools_package_count() {   # -> how many packages the package manager has installed, or nothing
    case $PM in
        xbps) xbps-query -l 2>/dev/null | grep -c . ;; apt) dpkg-query -f '.\n' -W 2>/dev/null | grep -c . ;;
        pacman) pacman -Qq 2>/dev/null | grep -c . ;; dnf|zypper) rpm -qa 2>/dev/null | grep -c . ;;
    esac
}
tools_software_state() { _tpc=$(panel_cache tools.packages 3600 tools_package_count); case $_tpc in ''|0|*[!0-9]*) echo 'no package list' ;; *) echo "$_tpc packages" ;; esac; }
provide_tools_rows() {   # -> the tools section's rows resource: the six, each with its page as children
    tools_menu | jq -Rn --arg sep "$PANEL_SEP" '
        [inputs | split("\t") | {id: ("tools:" + .[0]), sign: "blank", text: .[0], tool: null, more: [], columns: [.[1]],
            children: ("spark-shell://tools/rows/" + .[0]), group: null, line: (.[0] + " " + $sep + " " + .[2])}]
        | {title: "tools", state: "", rows: ., short: [.[].id]}'
}
provide_tools_page() {   # provide_tools_page PATH -> a tool's page, a rows resource: check, check/passed
    case $1 in
        check) tools_check_run; tools_check_page ;;
        check/passed) tools_check_passed ;;
        running) tools_running_page ;;
        space) tools_space_run; tools_space_page ;;
        system) tools_system_page ;;
        updates) tools_updates_page ;;
        software) tools_software_page ;;
        software/apps|software/tools|software/parts) tools_software_list "${1#software/}" ;;
        *) return 1 ;;
    esac
}
tools_check_page() {   # -> the check's page: problems, fixes, passed, check again
    tools_check_rows > "$TMP/check.rows"
    _tca=$(sed -n 1p "$TOOLS_CHECK" 2>/dev/null); _tcw=''
    case $_tca in ''|*[!0-9]*) ;; *) _tcw=$(date -d "@$_tca" '+%H:%M' 2>/dev/null || date -r "$_tca" '+%H:%M' 2>/dev/null || :) ;; esac
    while IFS="$TAB" read -r _tst _tnm _tlb _tdt _tfx; do
        [ "$_tst" != ok ] || continue
        _tfcm=''; _tfcm=$(tools_fix_command "$_tfx") || _tfcm=''
        printf '%s\t%s\t%s\t%s\t%s\n' "$_tnm" "$_tlb" "$_tdt" "$_tfx" "$_tfcm"
    done < "$TMP/check.rows" > "$TMP/check.problems"
    _tcp=$(awk -F '\t' '$1 == "ok" && $4 !~ /^na( |$)/' "$TMP/check.rows" | grep -c . || :)
    _tcna=$(awk -F '\t' '$1 == "ok" && $4 ~ /^na( |$)/' "$TMP/check.rows" | grep -c . || :)
    jq -Rn --arg sep "$PANEL_SEP" --arg passed "$_tcp" --arg na "$_tcna" --arg when "$_tcw" --arg state "$(tools_check_state)" '
        def row($id; $text): {id: $id, sign: "blank", text: $text, tool: null, more: [], columns: [], children: null, group: null};
        def gap($n): row("tools:gap:" + $n; "") | .muted = true;
        [inputs | split("\t") | {name: .[0], label: .[1], detail: .[2], fix: .[3], command: .[4]}] as $p
        | [$p[] | . as $x | row("tools:problem:" + $x.name; $x.label) | .group = "problems"
            | .columns = [$x.detail + (if $x.command == "" and $x.fix != "" then ": " + $x.fix else "" end)]] as $problems
        | ($p | map(select(.command != "") | .command) | reduce .[] as $c ([]; if index([$c]) then . else . + [$c] end)) as $order
        | [$order[] as $c
            | row("tools:fix:" + $c; "fix") | .columns = [$c] | .tool = {name: "tools_fix", arguments: {command: $c}}
            | .line = ("fix " + $sep + " in a terminal: " + $c)] as $fixes
        | ($problems
           + (if ($fixes | length) > 0 then [gap("1")] + $fixes else [] end)
           + (if ($problems | length) > 0 then [gap("2")] else [] end)
           + (if $passed != "0" then [row("tools:passed"; "\($passed) passed") | .children = "spark-shell://tools/rows/check/passed"
                | .line = ("\($passed) passed " + $sep + " the checks with no problem")] else [] end)
           + (if $na != "0" then [row("tools:na"; "\($na) not applicable") | .muted = true] else [] end)
           + [gap("3"), (row("tools:check-again"; "check again") | .columns = (if $when == "" then [] else ["checked at " + $when] end)
                | .tool = {name: "tools_check", arguments: {}} | .line = ("check again " + $sep + " runs every test again"))]) as $rows
        | {title: "check", state: $state, rows: $rows, short: []}' < "$TMP/check.problems"
}
tools_check_passed() {   # -> the passed checks as a rows resource
    tools_check_rows | awk -F '\t' '$1 == "ok" && $4 !~ /^na( |$)/ { printf "%s\t%s\t%s\n", $2, $3, $4 }' | jq -Rn '
        [inputs | split("\t") | {id: ("tools:ok:" + .[0]), sign: "blank", text: .[1], tool: null, more: [], columns: [.[2]], children: null, group: null}]
        | {title: "passed", state: "", rows: ., short: []}'
}
tools_rows_of() {   # stdin GROUP<tab>LABEL<tab>VALUE -> rows; an empty VALUE is left out
    jq -Rn '[inputs | split("\t") | select(.[2] != "") | {id: ("tools:fact:" + .[1]), sign: "blank", text: .[1], tool: null, more: [],
        columns: [.[2]], children: null, group: (if .[0] == "" then null else .[0] end)}]'
}
tools_system_facts() {   # -> GROUP<tab>LABEL<tab>VALUE: the machine, the operating system, the desktop
    _tsd=$BAR_SYS/class/dmi/id; _tsv=$(cat "$_tsd/sys_vendor" 2>/dev/null); _tsp=$(cat "$_tsd/product_name" 2>/dev/null)
    case $_tsv in LENOVO) _tsp=$(cat "$_tsd/product_version" 2>/dev/null) ;; ''|'System manufacturer'|'To Be Filled By O.E.M.') ;; *) _tsp="$_tsv $_tsp" ;; esac
    _tsc=$(awk -F ': *' '$1 ~ /^model name/ { print $2; exit }' "$BAR_PROC/cpuinfo" 2>/dev/null | sed 's/([RTMrtm]*)//g; s/ CPU//; s/ @ .*//; s/ with .*//; s/  */ /g; s/ *$//')
    _tsco=$(awk -F ': *' '$1 ~ /^cpu cores/ { print $2; exit }' "$BAR_PROC/cpuinfo" 2>/dev/null || :); _tsth=$(grep -c '^processor' "$BAR_PROC/cpuinfo" 2>/dev/null || :)   # cores where the processor says them, else its threads
    [ -n "$_tsc" ] || _tsc=$(uname -m)
    [ -n "$_tsco" ] || _tsco=$_tsth; [ -z "$_tsco" ] || [ "$_tsco" = 0 ] || _tsc="$_tsc, $_tsco cores"
    _tst=$(tools_mem_kb MemTotal); _tsa=$(tools_mem_kb MemAvailable); _tsm=''
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
        "$(tools_os PRETTY_NAME)" "$(uname -r)" "$(init_shape)" "$PM" "${_tsu#up }"
    _tss=''; _tso=''
    if wm_up; then
        _tss=$(wm_version | jq -r '.human_readable // empty' | awk '{ print $1 }')
        _tso=$(wm_outputs | jq -r '[.[] | select(.active) | .name + " " + (.current_mode.width | tostring) + "x" + (.current_mode.height | tostring)] | join(", ")')
    fi
    _tsk=$(spark_bin); _tskv=''; [ -z "$_tsk" ] || _tskv=$("$_tsk" --version 2>/dev/null | sed -n 's/.*spark \([0-9][0-9.]*\).*/\1/p' | head -1)
    printf 'desktop\tsway\t%s\ndesktop\tscreens\t%s\ndesktop\tspark-shell\t%s\ndesktop\tspark-dialog\t%s\ndesktop\tspark\t%s\n' \
        "$_tss" "$_tso" "v$(panel_version)" "$(tools_dialog_version)" "$_tskv"
}
tools_dialog_version() { _tdv=$(sed -n 's/^version = "\(.*\)"$/v\1/p' "$REPO/component/dialog/Cargo.toml" 2>/dev/null | head -1); printf '%s\n' "$_tdv"; }   # -> the dialog's version as Cargo.toml pins it
tools_system_page() {   # -> the system's page: its facts in three groups, then copy details
    tools_system_facts | scrub_text | tools_rows_of | jq -c --arg sep "$PANEL_SEP" '
        . + [{id: "tools:gap:1", sign: "blank", text: "", tool: null, more: [], columns: [], children: null, group: null, muted: true},
             {id: "tools:copy-details", sign: "blank", text: "copy details", tool: {name: "tools_copy_details", arguments: {}}, more: [], columns: [], children: null, group: null,
              line: ("copy details " + $sep + " to the clipboard, for bug reports")}]
        | {title: "system", state: "", rows: ., short: []}'
}
tools_details_text() {   # -> the system's facts as text, a group under its heading, for a bug report
    tools_system_facts | scrub_text | awk -F '\t' '$3 != "" { if ($1 != g) { if (g != "") print ""; print $1; g = $1 } printf "  %-12s %s\n", $2, $3 }'
}
tools_upgrade_command() {   # -> the family's own upgrade, or nothing
    case $PM in apt) echo 'sudo apt-get update && sudo apt-get upgrade' ;; pacman) echo 'sudo pacman -Syu' ;; *) pkg_update_said ;; esac
}
tools_updates_page() {   # -> the updates page: the releases, update spark-shell, update system
    _tuv=$(panel_version); _tud=''
    [ -z "$_tuv" ] || _tud=$(cd "$REPO" 2>/dev/null && LC_ALL=C git log -1 --format=%cd --date=format:'%e %b %Y' "v$_tuv" 2>/dev/null | sed 's/^ *//')
    jq -n --arg sep "$PANEL_SEP" --arg v "v$_tuv${_tud:+, released $_tud}" --arg dv "$(tools_dialog_version)" \
        --arg sys "$(tools_os PRETTY_NAME | scrub_text)${PM:+, $PM}" --arg up "$(tools_upgrade_command)" '
        def row($id; $text): {id: $id, sign: "blank", text: $text, tool: null, more: [], columns: [], children: null, group: null};
        [(row("tools:fact:spark-shell"; "spark-shell") | .columns = [$v]),
         (if $dv == "" then empty else (row("tools:fact:spark-dialog"; "spark-dialog") | .columns = [$dv]) end),
         (row("tools:update"; "update spark-shell") | .tool = {name: "tools_update", arguments: {}} | .line = ("update spark-shell " + $sep + " in a terminal: spark-shell update")),
         (row("tools:gap:1"; "") | .muted = true),
         (row("tools:fact:system"; "system") | .columns = [if $up == "" then $sys + " " + $sep + " no supported package manager here" else $sys end]),
         (if $up == "" then empty else (row("tools:update-system"; "update system") | .tool = {name: "tools_update_system", arguments: {}}
             | .line = ("update system " + $sep + " in a terminal: " + $up)) end)]
        | {title: "updates", state: "", rows: ., short: []}'
}
TOOLS_SBOM=$STATE_DIR/tools/sbom   # the installed list, kept for an hour: reading every license takes seconds
tools_sbom_fresh() { _tsbt=$(stat -c %Y "$TOOLS_SBOM" 2>/dev/null || echo 0); [ -s "$TOOLS_SBOM" ] && [ $(( $(date +%s) - _tsbt )) -lt 3600 ]; }
tools_sbom_warm() {   # the list built ahead in the background when the kept one is old; its own TMP
    tools_sbom_fresh && return 0
    mkdir_private "$STATE_DIR/tools"; lock_take "$TOOLS_SBOM.lock" || return 0
    ( TMP=$(mktemp -d) && { sbom_collect >/dev/null 2>&1 || :; [ ! -s "$TMP/sbom" ] || mv "$TMP/sbom" "$TOOLS_SBOM"; rm -rf "$TMP"; }; lock_drop "$TOOLS_SBOM.lock" ) </dev/null >/dev/null 2>&1 3>&- 4<&- 5>&- &
}
tools_sbom() {   # -> $TMP/sbom, the kept list; one being built ahead is waited for, 9 seconds at most, else built now
    _tsbw=0; while [ -e "$TOOLS_SBOM.lock" ] && [ "$_tsbw" -lt 45 ]; do sleep 0.2; _tsbw=$((_tsbw + 1)); done
    if tools_sbom_fresh; then cp "$TOOLS_SBOM" "$TMP/sbom"; return 0; fi
    sbom_collect 2>/dev/null || :
    [ -s "$TMP/sbom" ] || return 1
    mkdir_private "$STATE_DIR/tools"; cp "$TMP/sbom" "$TOOLS_SBOM"
}
tools_software_page() {   # -> apps, tools and parts, each its count and its list; export
    tools_sbom || { jq -n '{title: "software", state: "", rows: [{id: "tools:fact:none", sign: "blank", text: "no supported package manager here", tool: null, more: [], columns: [], children: null, group: null, muted: true}], short: []}'; return 0; }
    jq -n --arg sep "$PANEL_SEP" --arg a "$(grep -c '^app	' "$TMP/sbom" || :)" --arg t "$(grep -c '^tool	' "$TMP/sbom" || :)" --arg p "$(grep -c '^part	' "$TMP/sbom" || :)" '
        def row($id; $text): {id: $id, sign: "blank", text: $text, tool: null, more: [], columns: [], children: null, group: null};
        def kind($k; $n; $what): row("tools:software:" + $k; $k) | .columns = [$n] | .children = ("spark-shell://tools/rows/software/" + $k) | .line = ($k + " " + $sep + " " + $what);
        [kind("apps"; $a; "packages with a desktop entry"), kind("tools"; $t; "packages with commands"), kind("parts"; $p; "libraries and data"),
         (row("tools:gap:1"; "") | .muted = true),
         (row("tools:export"; "export") | .columns = ["CycloneDX 1.5"] | .tool = {name: "tools_export", arguments: {}} | .line = ("export " + $sep + " save the list as a CycloneDX file"))]
        | {title: "software", state: "", rows: ., short: []}'
}
tools_software_list() {   # tools_software_list apps|tools|parts -> the packages of that kind, a row each
    tools_sbom || return 1
    _tsk=${1%s}
    awk -F '\t' -v k="$_tsk" '$1 == k { printf "%s\t%s\t%s\n", $2, $3, $4 }' "$TMP/sbom" | scrub_text | jq -Rn --arg k "$_tsk" --arg l "$1" --arg sep "$PANEL_SEP" '
        def b64: @base64 | gsub("="; "") | gsub("[+]"; "-") | gsub("/"; "_");
        [inputs | split("\t") | ("tools:package:" + $k + ":" + .[0]) as $id
            | {id: $id, sign: "blank", text: .[0], tool: null, more: [], columns: [.[1]], children: null, group: null,
               line: ([.[0], .[1], .[2]] | map(select(. != "" and . != "?")) | join(" " + $sep + " ")), page: ("spark-shell://tools/page/" + ($id | b64))}]
        | {title: $l, state: "", rows: ., short: []}'
}
tools_package_page() {   # tools_package_page KIND:NAME -> a package's page
    tools_sbom || return 1
    _tpk=${1%%:*}; _tpn=${1#*:}
    awk -F '\t' -v k="$_tpk" -v n="$_tpn" '$1 == k && $2 == n { print; exit }' "$TMP/sbom" > "$TMP/package.one"
    [ -s "$TMP/package.one" ] || return 1
    IFS="$TAB" read -r _ _ _tpv _tpl _ _tpd _tpc _ < "$TMP/package.one"
    case $_tpk in app) _tpt=app ;; tool) _tpt=tool ;; *) _tpt=part ;; esac
    printf 'description\t%s\nversion\t%s\nlicense\t%s\ncommands\t%s\ntype\t%s\nsource\t%s\n' "$_tpd" "$_tpv" "$(printf '%s' "$_tpl" | sed 's/^?$//')" "$(printf '%s' "$_tpc" | tr ' ' '\n' | sed 's|.*/||' | paste -sd' ' -)" "$_tpt" "$PM" \
        | page_of "$_tpn" ''
}
TOOLS_SPACE=$STATE_DIR/tools/space   # the last measure: at (the epoch, then done or part), home, cache (du's KB<tab>PATH lines), trash, packages (KB)
TOOLS_SPACE_FRESH=60                 # a measure younger than this many seconds is read, not made again
TOOLS_SPACE_WAIT=8                   # seconds a measure may take: the page's read is answered within the dialog's 10
tools_package_cache() {   # -> the package manager's download cache, or nothing
    case $PM in
        xbps) echo /var/cache/xbps ;; apt) echo /var/cache/apt/archives ;; pacman) echo /var/cache/pacman/pkg ;;
        dnf) if [ -d /var/cache/libdnf5 ]; then echo /var/cache/libdnf5; else echo /var/cache/dnf; fi ;; zypper) echo /var/cache/zypp/packages ;;
    esac
}
tools_clean_command() {   # -> the family's own clean of that cache, or nothing
    case $PM in xbps) echo 'sudo xbps-remove -O' ;; apt) echo 'sudo apt-get clean' ;; pacman) echo 'sudo pacman -Sc' ;; dnf) echo 'sudo dnf clean packages' ;; zypper) echo 'sudo zypper clean --all' ;; esac
}
tools_cache_dir() { printf '%s\n' "${XDG_CACHE_HOME:-$HOME/.cache}"; }
tools_trash_dir() { printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}/Trash"; }
tools_tilde() {   # tools_tilde PATH -> the path with your home as ~
    _ttr=$(files_home_root)
    case $1 in "$HOME"|"$_ttr") echo '~' ;; "$HOME"/*) printf '%s/%s\n' '~' "${1#"$HOME"/}" ;; "$_ttr"/*) printf '%s/%s\n' '~' "${1#"$_ttr"/}" ;; *) printf '%s\n' "$1" ;; esac
}
tools_space_measure() {   # the measure made now, TOOLS_SPACE_WAIT seconds at most, the four du side by side
    mkdir -p "$TOOLS_SPACE"
    _tsk=$(tools_package_cache)
    { timeout "$TOOLS_SPACE_WAIT" du -x -d1 -k "$(files_home_root)" > "$TOOLS_SPACE/home.new" 2>/dev/null; echo $? > "$TOOLS_SPACE/home.rc"; } & _tm1=$!
    { timeout "$TOOLS_SPACE_WAIT" du -x -d1 -k "$(tools_cache_dir)" > "$TOOLS_SPACE/cache.new" 2>/dev/null || :; } & _tm2=$!
    { timeout "$TOOLS_SPACE_WAIT" du -sk "$(tools_trash_dir)" 2>/dev/null | cut -f1 > "$TOOLS_SPACE/trash.new" || :; } & _tm3=$!
    { [ -z "$_tsk" ] || timeout "$TOOLS_SPACE_WAIT" du -sk "$_tsk" 2>/dev/null | cut -f1 > "$TOOLS_SPACE/packages.new" || :; } & _tm4=$!
    wait "$_tm1" "$_tm2" "$_tm3" "$_tm4" 2>/dev/null || :   # these four alone: a provider may have a watcher in the background
    for _f in home cache trash packages; do
        if [ -f "$TOOLS_SPACE/$_f.new" ]; then mv -f "$TOOLS_SPACE/$_f.new" "$TOOLS_SPACE/$_f"; else : > "$TOOLS_SPACE/$_f"; fi
    done
    _tmd='done'; [ "$(cat "$TOOLS_SPACE/home.rc" 2>/dev/null)" != 124 ] || _tmd='part'   # 124 is timeout's own exit: du was stopped
    printf '%s %s\n' "$(date +%s)" "$_tmd" > "$TOOLS_SPACE/at"
}
tools_space_run() {   # the measure made now, unless the kept one is fresh
    _tsa=$(cut -d' ' -f1 "$TOOLS_SPACE/at" 2>/dev/null)
    case $_tsa in ''|*[!0-9]*) _tsa=0 ;; esac
    [ $(( $(date +%s) - _tsa )) -lt "$TOOLS_SPACE_FRESH" ] || tools_space_measure
}
tools_space_folders() {   # -> KB<tab>NAME<tab>PATH, home's folders, the largest first; the app caches left out, the trash taken out of its folder
    _tfr=$(files_home_root); _tfc=$(realpath "$(tools_cache_dir)" 2>/dev/null || tools_cache_dir); _tft=$(realpath "$(tools_trash_dir)" 2>/dev/null || tools_trash_dir)
    awk -F '\t' -v root="$_tfr" -v cache="$_tfc" -v trash="$_tft" -v tk="$(cat "$TOOLS_SPACE/trash" 2>/dev/null)" '
        $2 == root || $2 == cache { next }
        { k = $1; if (tk != "" && index(trash "/", $2 "/") == 1) k -= tk; if (k < 0) k = 0; n = $2; sub(/.*\//, "", n); printf "%d\t%s\t%s\n", k, n, $2 }' "$TOOLS_SPACE/home" 2>/dev/null | sort -t "$TAB" -k1,1nr
}
tools_space_loose() {   # -> the KB of the files directly in home: the whole, less its folders; nothing when the measure did not end
    [ "$(cut -d' ' -f2 "$TOOLS_SPACE/at" 2>/dev/null)" = 'done' ] || return 0
    awk -F '\t' -v root="$(files_home_root)" '$2 == root { t = $1; next } { s += $1 } END { if (t != "") { d = t - s; print (d < 0 ? 0 : d) } }' "$TOOLS_SPACE/home" 2>/dev/null
}
TOOLS_SPACE_SHOWN=6   # home's folders listed by name; the rest are one row
tools_space_page() {   # -> the space page: the disk, cleanup, home's folders, measure again
    _tsp=$(cut -d' ' -f2 "$TOOLS_SPACE/at" 2>/dev/null); _tsw=$(cut -d' ' -f1 "$TOOLS_SPACE/at" 2>/dev/null)
    tools_space_folders > "$TMP/space.folders"
    _tsc=$(awk -F '\t' -v c="$(realpath "$(tools_cache_dir)" 2>/dev/null || tools_cache_dir)" '$2 == c { print $1 }' "$TOOLS_SPACE/cache" 2>/dev/null)
    while IFS="$TAB" read -r _k _n _p; do
        _h=''; case $_n in .*) _h=1 ;; esac
        printf '%s\t%s\t%s\t%s\t%s\n' "$_n" "$(files_size $((_k * 1024)))" "$_h" "$(files_uri "$_p")" "$(tools_tilde "$_p")"
    done < "$TMP/space.folders" > "$TMP/space.rows"
    _tsl=$(tools_space_loose)
    jq -Rn --arg sep "$PANEL_SEP" --arg disk "$(storage_here)" --arg shown "$TOOLS_SPACE_SHOWN" \
        --arg trash "$(_k=$(cat "$TOOLS_SPACE/trash" 2>/dev/null); [ -z "$_k" ] || files_size $((_k * 1024)))" \
        --arg pkg "$(_k=$(cat "$TOOLS_SPACE/packages" 2>/dev/null); [ -z "$_k" ] || files_size $((_k * 1024)))" --arg clean "$(tools_clean_command)" \
        --arg cache "$([ -z "$_tsc" ] || files_size $((_tsc * 1024)))" --arg cached "$(tools_tilde "$(tools_cache_dir)")" \
        --arg loose "$([ -z "$_tsl" ] || files_size $((_tsl * 1024)))" --arg home "$(files_uri "$(files_home_root)")" \
        --arg rest "$(awk -F '\t' -v n="$TOOLS_SPACE_SHOWN" 'NR > n { c++; k += $1 } END { if (c) printf "%d\t%d\n", c, k }' "$TMP/space.folders")" \
        --arg restsize "$(awk -F '\t' -v n="$TOOLS_SPACE_SHOWN" 'NR > n { k += $1 } END { print k * 1024 }' "$TMP/space.folders" | { read -r _b; files_size "${_b:-0}"; })" \
        --arg part "$_tsp" --arg at "$([ -z "$_tsw" ] || date -d "@$_tsw" +%H:%M 2>/dev/null || date -r "$_tsw" +%H:%M 2>/dev/null)" '
        def b64: @base64 | gsub("="; "") | gsub("[+]"; "-") | gsub("/"; "_");
        def row($id; $text): {id: $id, sign: "blank", text: $text, tool: null, more: [], columns: [], children: null, group: null};
        [inputs | split("\t") | {name: .[0], size: .[1], hidden: (.[2] == "1"), uri: .[3], path: .[4]}] as $f
        | ($shown | tonumber) as $n
        | [(row("tools:fact:system disk"; "system disk") | .columns = [if $disk == "" then "?" else $disk end]),
           (row("tools:trash"; "trash") | .group = "cleanup" | .columns = [$trash] | .children = "spark-shell://files/rows/trash"
               | .line = ("trash " + $sep + " open in files to restore or empty")),
           (if $clean == "" then empty else (row("tools:clean-packages"; "package cache") | .group = "cleanup" | .columns = [$pkg]
               | .tool = {name: "tools_clean_packages", arguments: {}} | .line = ("package cache " + $sep + " clean: " + $clean)) end),
           (row("tools:caches"; "app caches") | .group = "cleanup" | .columns = [$cache] | .page = ("spark-shell://tools/page/" + ("tools:space:caches" | b64))
               | .line = ("app caches " + $sep + " " + $cached + " by folder")),
           ($f[:$n][] | . as $d | ("tools:folder:" + $d.name) as $id
               | row($id; $d.name) | .group = "home" | .columns = [$d.size]
               | .line = ([$d.name, $d.size, (if $d.hidden then "hidden folder" else "folder" end)] | join(" " + $sep + " "))
               | .page = ("spark-shell://tools/page/" + ($id | b64))
               | (if $d.hidden then . else .children = $d.uri end)),
           (if $loose == "" then empty else (row("tools:folder:~"; "files in home") | .group = "home" | .columns = [$loose] | .children = $home
               | .line = ("files in home " + $sep + " " + $loose + " " + $sep + " files directly in ~")) end),
           (if $rest == "" then empty else ($rest | split("\t")) as $r | (row("tools:space:more"; (if $r[0] == "1" then "1 more folder" else $r[0] + " more folders" end)) | .group = "home" | .columns = [$restsize]) end),
           (if $part == "part" then (row("tools:space:part"; "some folders took too long to measure") | .group = "home" | .muted = true) else empty end),
           (row("tools:gap:1"; "") | .muted = true),
           (row("tools:measure"; "measure again") | .columns = [if $at == "" then "not measured yet" else "measured at " + $at end]
               | .tool = {name: "tools_measure", arguments: {}} | .line = ("measure again " + $sep + " what uses the disk now"))]
        | {title: "space", state: (if $disk == "" then "" else ($disk | sub("^[^,]*, "; "")) end), rows: ., short: []}' < "$TMP/space.rows"
}
tools_space_view() {   # tools_space_view caches|folder:NAME -> a page of its largest folders; a home folder is measured now
    case $1 in
        caches) _tvp=$(realpath "$(tools_cache_dir)" 2>/dev/null || tools_cache_dir); cp "$TOOLS_SPACE/cache" "$TMP/view.du" 2>/dev/null || : > "$TMP/view.du"; _tvt='app caches' ;;
        folder:?*) _tvn=${1#folder:}; case $_tvn in */*|.|..) return 1 ;; esac
            _tvp=$(files_home_root)/$_tvn; [ -d "$_tvp" ] || return 1; _tvt=$_tvn
            timeout 5 du -x -d1 -k "$_tvp" > "$TMP/view.du" 2>/dev/null || : ;;   # stopped at 5 seconds, the folder's own total is missing: said below
        *) return 1 ;;
    esac
    _tvk=$(awk -F '\t' -v p="$_tvp" '$2 == p { print $1 }' "$TMP/view.du")
    _tvw="$([ -z "$_tvk" ] || files_size $((_tvk * 1024))) in $(tools_tilde "$_tvp")"; [ -n "$_tvk" ] || _tvw="$(tools_tilde "$_tvp"), measured in part"
    awk -F '\t' -v p="$_tvp" '$2 != p { n = $2; sub(/.*\//, "", n); printf "%d\t%s\n", $1, n }' "$TMP/view.du" | sort -t "$TAB" -k1,1nr | head -12 \
        | while IFS="$TAB" read -r _k _n; do printf '%s\t%s\n' "$_n" "$(files_size $((_k * 1024)))"; done | page_of "$_tvt" "$_tvw"
}
tools_running_read() {   # -> $TMP/running.tsv, the programs now, sway's windows by process id
    : > "$TMP/running.windows"
    ! wm_up || wm_tree | jq -r '.. | objects | select((.type == "con" or .type == "floating_con") and (.pid // 0) > 0) | "\(.pid)\t\(.id)"' > "$TMP/running.windows" 2>/dev/null || :
    python3 -I "$REPO/lib/running.py" list "$BAR_PROC" "$TMP/running.state" "$TMP/running.windows" > "$TMP/running.tsv" 2>/dev/null
}
tools_users() { awk -F: '{ printf "%s\t%s\n", $3, $1 }' /etc/passwd 2>/dev/null | jq -Rn '[inputs | split("\t") | {(.[0]): .[1]}] | add // {}'; }   # -> {"0": "root",...}
TOOLS_KEEP="$WM_OWN spark-shell spark-dialog dbus-daemon pipewire pipewire-pulse wireplumber"   # never ended from here: the desktop's own parts and the dialog
tools_running_page() {   # -> every program, the busiest first, with put in front and end
    tools_running_read
    jq -Rn --arg sep "$PANEL_SEP" --arg me "$(id -u)" --argjson users "$(tools_users)" --arg keep " $TOOLS_KEEP " --arg state "$(tools_running_state)" '
        def b64: @base64 | gsub("="; "") | gsub("[+]"; "-") | gsub("/"; "_");
        def one: (. * 10 | round) as $t | "\($t / 10 | floor).\($t % 10)";
        def size: if . < 1024 then "\(.) B" elif . < 1048576 then "\(. / 1024 | floor) KB" elif . < 1073741824 then "\(. / 1048576 | one) MB" else "\(. / 1073741824 | one) GB" end;
        [inputs | split("\t") | {name: .[0], cpu: (.[1] | tonumber), private: (.[2] | tonumber), count: .[4], uids: (.[5] | split(",")), window: .[9]}
            | . as $g | ($g.uids == [$me]) as $mine | ("tools:program:" + $g.name) as $id
            | ($g.uids | map($users[.] // .) | join(", ")) as $who
            | {id: $id, sign: "blank", text: $g.name, more: [], children: null, group: null,
               columns: ["\($g.cpu)%", ($g.private | size)],
               wide: ["\($g.cpu)% cpu", ($g.private | size), (if $g.count == "1" then "1 process" else $g.count + " processes" end)],
               line: ([$g.name, "\($g.cpu)% cpu", ($g.private | size), (if $g.count == "1" then "1 process" else $g.count + " processes" end)]
                   + (if $mine then [] else ["user " + $who] end) | join(" " + $sep + " ")),
               page: ("spark-shell://tools/page/" + ($id | b64)),
               tool: (if $g.window != "" then {name: "tools_front", arguments: {name: $g.name}, said: "put in front"} else null end)}
            | .more = (if $mine and ($keep | contains(" " + $g.name + " ") | not) then [{name: "tools_end", arguments: {name: $g.name}, said: "end"}] else [] end)]
        | {title: "running", state: $state, rows: ., short: []}' < "$TMP/running.tsv"
}
tools_program() {   # tools_program NAME -> its line of the last read (read now when there is none)
    [ -s "$TMP/running.tsv" ] || tools_running_read
    awk -F '\t' -v n="$1" '$1 == n { print; exit }' "$TMP/running.tsv"
}
tools_program_page() {   # tools_program_page NAME -> a program's page
    _tpl=$(tools_program "$1"); [ -n "$_tpl" ] || return 1
    printf '%s\n' "$_tpl" > "$TMP/program.one"
    IFS="$TAB" read -r _tpn _tpc _tpp _tpr _tpk _tpu _tps _tpi _tpm _ < "$TMP/program.one"
    _tpw=$(printf '%s\n' "$_tpu" | tr ',' '\n' | while read -r _u; do if [ "$_u" = "$(id -u)" ]; then echo you; else awk -F: -v u="$_u" '$3 == u { print $1; f = 1 } END { if (!f) print "user " u }' /etc/passwd; fi; done | paste -sd, - | sed 's/,/, /g')
    _tpd=$(printf '%s' "$_tpi" | awk '{ s = ""; for (i = 1; i <= NF && i <= 4; i++) s = s (i > 1 ? ", " : "") $i; if (NF > 4) s = s " and " (NF - 4) " more"; print s }')
    _tpt=$(date -d "@$_tps" '+%H:%M' 2>/dev/null || date -r "$_tps" '+%H:%M' 2>/dev/null || :)
    [ "$(date -d "@$_tps" +%F 2>/dev/null)" = "$(date +%F)" ] || _tpt=$(date -d "@$_tps" '+%e %b %H:%M' 2>/dev/null | sed 's/^ *//' || :)
    printf 'processes\t%s\nids\t%s\nuser\t%s\nstarted\t%s\ncpu\t%s%%\nmemory\t%s private, %s resident\ncommand\t%s\n' \
        "$_tpk" "$_tpd" "$_tpw" "$_tpt" "$_tpc" "$(files_size "$_tpp")" "$(files_size "$_tpr")" "$_tpm" | page_of "$_tpn" ''
}
tools_dialog_tree() {   # -> the pids never ended from here: this provider's ancestors, and everything under the dialog
    _tdp=$$; _tdd=''
    while [ -n "$_tdp" ] && [ "$_tdp" != 0 ] && [ "$_tdp" != 1 ]; do
        echo "$_tdp"
        [ "$(cat "$BAR_PROC/$_tdp/comm" 2>/dev/null)" != spark-dialog ] || _tdd=$_tdp
        _tdp=$(awk '{ sub(/^.*\) /, ""); print $2 }' "$BAR_PROC/$_tdp/stat" 2>/dev/null)
    done
    [ -z "$_tdd" ] || python3 -I "$REPO/lib/running.py" tree "$BAR_PROC" "$_tdd" 2>/dev/null
}
tools_gate() {   # tools_gate ACTION [ARG] -> ARG as the step takes it (exit 0), or why not (exit 1)
    case $1 in
        check|copy-details|update|export|measure) echo ''; return 0 ;;
        clean-packages) [ -n "$(tools_clean_command)" ] || { echo "no supported package manager here"; return 1; }; echo ''; return 0 ;;
        update-system) [ -n "$(tools_upgrade_command)" ] || { echo "no supported package manager here"; return 1; }; echo ''; return 0 ;;
        front) _tgl=$(tools_program "$2"); [ -n "$_tgl" ] || { echo "$2 is not running"; return 1; }
            [ -n "$(printf '%s' "$_tgl" | cut -f10)" ] || { echo "$2 has no window"; return 1; }
            printf '%s\n' "$2"; return 0 ;;
        end) case " $TOOLS_KEEP " in *" $2 "*) case $2 in sway) echo "sway is the desktop: use logout in power" ;; spark-dialog) echo "the dialog closes with Esc" ;; *) echo "$2 is part of the desktop: use logout in power" ;; esac; return 1 ;; esac
            tools_running_read; _tgl=$(tools_program "$2"); [ -n "$_tgl" ] || { echo "$2 is not running"; return 1; }
            _tgu=$(printf '%s' "$_tgl" | cut -f6)
            [ "$_tgu" = "$(id -u)" ] || { echo "$2 belongs to $(printf '%s\n' "$_tgu" | tr ',' '\n' | grep -vx "$(id -u)" | head -1 | while read -r _u; do awk -F: -v u="$_u" '$3 == u { print $1; f = 1 } END { if (!f) print "user " u }' /etc/passwd; done) and cannot be ended here"; return 1; }
            printf '%s\n' "$2"; return 0 ;;
        fix) _tgc=$(tools_fix_command "$2") || { echo "$2 is not a fix the last check gave"; return 1; }
            tools_check_rows | while IFS="$TAB" read -r _tst _tnm _tlb _tdt _tfx; do [ "$_tst" = ok ] || tools_fix_command "$_tfx" 2>/dev/null || :; done | grep -qxF -- "$_tgc" \
                || { echo "$2 is not a fix the last check gave"; return 1; }
            printf '%s\n' "$_tgc"; return 0 ;;
    esac
    echo "$1 is not something tools does"; return 1
}
tools_act() {   # tools_act ACTION [ARG] -> one line; exit 1 when it was not done
    case $1 in
        check) "$REPO/spark-shell" check > /dev/null 2>&1 || :
            [ -s "$TOOLS_CHECK" ] || { echo "the check printed nothing"; return 1; }
            echo "checked: $(tools_check_state)" ;;
        fix) tools_terminal "$2" 'spark-shell check' ;;   # the check runs again when the fix ends: the menu's count is the fix's result
        update) tools_terminal 'spark-shell update' ;;
        measure) tools_space_measure; echo "measured: $(tools_space_state)" ;;
        clean-packages) tools_terminal "$(tools_clean_command)" ;;
        front) _tfc=$(tools_program "$2" | cut -f10)
            wm_act "con_id=$_tfc" "focus" >/dev/null 2>&1 || { echo "$2 did not come to front"; return 1; }
            : > "$TMP/opened"; echo "$2 in front" ;;
        end) tools_dialog_tree | sort -u > "$TMP/end.keep"
            tools_program "$2" | cut -f8 | tr ' ' '\n' | grep -vxFf "$TMP/end.keep" | grep . > "$TMP/end.pids" || { echo "$2 is part of the dialog: Esc closes it"; return 1; }
            while read -r _p; do kill -TERM "$_p" 2>/dev/null || :; done < "$TMP/end.pids"   # the shell's own kill: an external one is procps', not on every machine
            _tew=0; while [ "$_tew" -lt 25 ]; do
                # a zombie has ended: its parent has yet to reap it
                _tel=''; while read -r _p; do [ ! -d "$BAR_PROC/$_p" ] || grep -qs '^State:[[:space:]]*Z' "$BAR_PROC/$_p/status" || { _tel=1; break; }; done < "$TMP/end.pids"
                [ -n "$_tel" ] || break; sleep 0.2; _tew=$((_tew + 1))
            done
            [ -z "$_tel" ] || { echo "$2 is still running after 5 seconds"; return 1; }
            echo "$2 ended" ;;
        update-system) tools_terminal "$(tools_upgrade_command)" ;;
        copy-details) wm_copy_here || { echo "$(wm_missing copy)"; return 1; }
            tools_details_text | wm_copy 2>/dev/null || { echo "cannot copy: the clipboard did not take it"; return 1; }
            echo "details copied" ;;
        export) _tex=$("$REPO/spark-shell" sbom --json 2>&1) || { printf '%s
' "$_tex" | tail -1; return 1; }
            _tep=${SBOM_JSON#"$HOME"}; [ "$_tep" = "$SBOM_JSON" ] || _tep="~$_tep"; echo "saved $_tep" ;;
        *) echo "$1 is not something tools does"; return 1 ;;
    esac
}
tools_terminal() {   # tools_terminal LINE [THEN] -- LINE in a terminal window that waits for Enter; THEN a spark-shell command run after it
    wm_up || { echo "a terminal window needs the desktop"; return 1; }
    mkdir_private "$STATE_DIR/tools"
    _tts=$(mktemp "$STATE_DIR/tools/run.XXXXXX") || { echo "could not open a terminal"; return 1; }
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
        "desktop	next keyboard layout	desktop.desktop-keyboard-next	Super+Ctrl+space"
}
provide_about_rows() {   # -> the about section's rows resource: the facts, project, license, credits, then help's keys
    _av=$(panel_version); _ad=''
    [ -z "$_av" ] || _ad=$(cd "$REPO" 2>/dev/null && LC_ALL=C git log -1 --format=%cd --date=format:'%e %b %Y' "v$_av" 2>/dev/null | sed 's/^ *//')   # the day of the tag this copy is at
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
