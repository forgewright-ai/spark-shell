# shellcheck extended-analysis=false
# --- the tools provider
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
    if desk_in_sway; then
        _tss=$(swaymsg -t get_version 2>/dev/null | jq -r '.human_readable // empty' | awk '{ print $1 }')
        _tso=$(swaymsg -t get_outputs 2>/dev/null | jq -r '[.[] | select(.active) | .name + " " + (.current_mode.width | tostring) + "x" + (.current_mode.height | tostring)] | join(", ")')
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
    ! desk_in_sway || swaymsg -t get_tree 2>/dev/null | jq -r '.. | objects | select((.type == "con" or .type == "floating_con") and (.pid // 0) > 0) | "\(.pid)\t\(.id)"' > "$TMP/running.windows" 2>/dev/null || :
    python3 -I "$REPO/lib/tools_running.py" list "$BAR_PROC" "$TMP/running.state" "$TMP/running.windows" > "$TMP/running.tsv" 2>/dev/null
}
tools_users() { awk -F: '{ printf "%s\t%s\n", $3, $1 }' /etc/passwd 2>/dev/null | jq -Rn '[inputs | split("\t") | {(.[0]): .[1]}] | add // {}'; }   # -> {"0": "root",...}
TOOLS_KEEP='sway swaybar swaybg swayidle swaylock spark-shell spark-dialog dbus-daemon pipewire pipewire-pulse wireplumber'   # never ended from here: the desktop's own parts and the dialog
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
    [ -z "$_tdd" ] || python3 -I "$REPO/lib/tools_running.py" tree "$BAR_PROC" "$_tdd" 2>/dev/null
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
            swaymsg "[con_id=$_tfc] focus" >/dev/null 2>&1 || { echo "$2 did not come to front"; return 1; }
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
        copy-details) command -v wl-copy >/dev/null 2>&1 || { echo "cannot copy: wl-copy is not installed (spark-shell on desktop)"; return 1; }
            tools_details_text | wl-copy 2>/dev/null || { echo "cannot copy: the clipboard did not take it"; return 1; }
            echo "details copied" ;;
        export) _tex=$("$REPO/spark-shell" sbom --json 2>&1) || { printf '%s
' "$_tex" | tail -1; return 1; }
            _tep=${SBOM_JSON#"$HOME"}; [ "$_tep" = "$SBOM_JSON" ] || _tep="~$_tep"; echo "saved $_tep" ;;
        *) echo "$1 is not something tools does"; return 1 ;;
    esac
}
tools_terminal() {   # tools_terminal LINE [THEN] -- LINE in a terminal window that waits for Enter; THEN a spark-shell command run after it
    desk_in_sway || { echo "a terminal window needs the desktop"; return 1; }
    mkdir_private "$STATE_DIR/tools"
    _tts=$(mktemp "$STATE_DIR/tools/run.XXXXXX") || { echo "could not open a terminal"; return 1; }
    case $1 in spark-shell|'spark-shell '*) _ttc="$REPO/$1" ;; *) _ttc=$1 ;; esac
    {
        printf '#!/bin/sh\nrm -f "$0"\nprintf %s\n%s\n' "'%s\\n\\n' '$1'" "$_ttc"
        case ${2:-} in spark-shell|'spark-shell '*) printf 'printf %s\n%s\n' "'\\n%s\\n\\n' '$2'" "$REPO/$2" ;; esac
        printf 'printf %s\nread _\n' "'\\npress Enter to close\\n'"
    } > "$_tts"
    _wr=0; win_exec "foot sh $_tts" || _wr=$?
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
    _am=$(python3 "$REPO/lib/home.py" map "$REPO/template/.config/sway/config" 2>/dev/null) || _am='{}'   # the keys as bound now, your overrides in
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

# the wire: only MCP reaches stdout, fd 3; fd 1 goes to stderr before any
# step runs. One process writes fd 3, the loop; the reader ("in LINE") and
# the watcher ("poke") feed it through one FIFO, a line under a lock
rpc_send() { ( printf '%s\n' "$1" >&3 ) 2>/dev/null || :; }   # from a subshell: a closed wire (the dialog gone) ends the subshell, never the provider mid-request
rpc_result() { printf '%s' "$2" | jq -c --argjson id "$1" '{jsonrpc: "2.0", id: $id, result: .}' >&3; }   # rpc_result ID JSON (the result on stdin to jq: no argument grows past a limit)
rpc_error() { rpc_send "$(jq -cn --argjson id "$1" --argjson c "$2" --arg m "$3" '{jsonrpc: "2.0", id: $id, error: {code: $c, message: $m}}')"; }   # rpc_error ID CODE MESSAGE
rpc_note() { rpc_send "$(jq -cn --arg m "$1" --argjson p "$2" '{jsonrpc: "2.0", method: $m, params: $p}')"; }   # rpc_note METHOD PARAMS -- a notification
fifo_put() {   # fifo_put LINE -- one line into the loop's FIFO (fd 5), under the lock, so a long line is never cut by a poke
    # a lock older than two seconds was left by a writer killed mid-line, and is taken
    _fpw=0; until lock_take "$PLOCK"; do _fpw=$((_fpw + 1)); [ "$_fpw" -lt 200 ] || { lock_drop "$PLOCK"; _fpw=0; }; sleep 0.01; done
    printf '%s\n' "$1" >&5 || :; lock_drop "$PLOCK"
}
PROVIDE_POLL=${SPARK_SHELL_PROVIDE_POLL:-}   # the watcher's seconds between looks; the tests set it
# the sections the desktop changes behind the dialog; every other changes only by a step, whose answer carries its rows
PROVIDE_WATCHED=${SPARK_SHELL_PROVIDE_WATCHED:-wifi bt out mic storage window notifications}
provide_seen() { cksum < "$TMP/rows.last" > "$TMP/rows.seen"; }   # the rows the host was last sent, as the watcher compares them
provide_watch() {   # provide_watch SECTION [PAGE] -- the rows, or a page, read again every few seconds; a change pokes the loop. Its own TMP
    _seen=$TMP/rows.seen; _wpage=${2:-}; TMP=$TMP/watch; mkdir -p "$TMP"
    _every=$PROVIDE_POLL; [ -n "$_every" ] || case $(panel_cost "$1") in slow) _every=15 ;; fast) _every=5 ;; *) _every=3 ;; esac
    if [ -n "$_wpage" ]; then   # a page: every change pokes
        _last=$(provide_tools_page "$_wpage" 2>/dev/null | cksum)
        while :; do
            sleep "$_every"
            _now=$(provide_tools_page "$_wpage" 2>/dev/null | cksum)
            [ "$_now" = "$_last" ] || { _last=$_now; fifo_put poke; }
        done
    fi
    _last=$(provide_rows "$1" 2>/dev/null | cksum)
    while :; do
        sleep "$_every"
        config_load; theme_load
        _now=$(provide_rows "$1" 2>/dev/null | cksum)
        # a change pokes once; rows the host already has (a call's answer carried them) poke nothing
        _had=''; [ ! -f "$_seen" ] || IFS= read -r _had < "$_seen" || :
        [ "$_now" = "$_last" ] || { _last=$_now; [ "$_now" = "$_had" ] || fifo_put poke; }
    done
}
provide_watch_check() {   # provide_watch_check SUM -- the check's record read again every few seconds; a change pokes the loop. SUM the record as it was before the answer, so a check that ends at once is not missed
    _every=${PROVIDE_POLL:-3}; _last=$1
    while :; do
        sleep "$_every"
        _now=$({ cksum < "$TOOLS_CHECK"; } 2>/dev/null)
        [ "$_now" = "$_last" ] || { _last=$_now; fifo_put poke; }
    done
}
provide_input() {   # stdin -> the loop's FIFO, a line each; a pairing agent's answers go to it directly
    while IFS= read -r _l || [ -n "$_l" ]; do
        if [ -S "$TMP/bt.sock" ] && [ "${#_l}" -le "$PROVIDE_LINE_MAX" ]; then
            if printf '%s' "$_l" | jq -e '(.id | type) == "string" and (.id | startswith("bt-pair-")) and (has("method") | not)' >/dev/null 2>&1; then
                printf '%s\n' "$_l" | python3 "$REPO/lib/bt_agent.py" --reply "$TMP" || :
                _l=''; continue
            fi
            if printf '%s' "$_l" | jq -e --slurpfile id "$TMP/bt.call-id" '.method == "notifications/cancelled" and .params.requestId == $id[0]' >/dev/null 2>&1; then
                : > "$TMP/bt.cancel"; _l=''; continue
            fi
        fi
        fifo_put "in $_l"; _l=''
    done
    [ ! -S "$TMP/bt.sock" ] || : > "$TMP/bt.cancel"
    fifo_put eof
}

provide_main() {   # provide_main SECTION -- serve it until stdin ends
    sec=$1
    case " $PROVIDE_SECTIONS " in *" $sec "*) ;; *) refuse_in provide "${sec:-a section} is not one: $(printf '%s' "$PROVIDE_SECTIONS" | sed 's/ /, /g')" >&2 ;; esac   # a refusal on stderr: stdout is the wire
    command -v jq >/dev/null 2>&1 || refuse_in provide "jq is not installed (spark-shell on)" >&2
    command -v mkfifo >/dev/null 2>&1 || refuse_in provide "mkfifo is not installed" >&2
    config_load; [ "$OS" = Darwin ] || pm_detect; theme_load; SND=''; [ "$OS" = Darwin ] || SND=$(snd_tool)
    PANEL_VERSION_NOW=$(panel_version); PANEL_VERSION_READ=1   # once a provider: the release does not change under it
    [ "$sec" != display ] || { if saver_can; then SAVER_CAN_NOW=1; else SAVER_CAN_NOW=0; fi; }   # python3 asked once a provider, not twice a read
    [ "$sec" != tools ] || tools_sbom_warm   # the installed list, ready before software opens
    exec 3>&1 1>&2 6<&0   # fd 3 the wire out, fd 6 the wire in; whatever a step prints goes to stderr
    WATCH=''; READER=''; SUBSCRIBED=''; PLOCK=$TMP/in.lock; PROOTS=$TMP/roots; CLIENT_ROOTS=''; CLIENT_PAIRING=''; : > "$PROOTS"
    REM_DELETED=$TMP/deleted   # a reminder deleted here is kept until the provider ends: its undo
    LAYOUT_DELETED=$TMP/deleted-layouts   # and a layout
    trap '{ [ -z "$WATCH" ] || kill "$WATCH"; [ -z "$READER" ] || kill "$READER"; files_stop; files_sound_stop; } 2>/dev/null || :; rm -rf "$TMP"' EXIT   # the reader has ended with stdin: a kill that finds nobody is no failure
    trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM   # a signal ends the provider through the EXIT trap
    mkfifo "$TMP/in"
    ( provide_input ) <&6 5>"$TMP/in" 3>&- & READER=$!
    exec 4<"$TMP/in" 6<&-
    while IFS= read -r _msg <&4; do
        case $_msg in
            eof) break ;;
            poke) [ -z "$SUBSCRIBED" ] || rpc_note notifications/resources/updated "$(jq -cn --arg u "spark-shell://$sec/rows" '{uri: $u}')" ;;
            "in "*) provide_one "${_msg#in }" || : ;;
        esac
    done
}
provide_one() {   # provide_one LINE -- one message: a request answered, a notification taken, anything else refused
    [ "${#1}" -le "$PROVIDE_LINE_MAX" ] || { rpc_error null -32600 "a message is $PROVIDE_LINE_MAX bytes at most"; return 0; }
    # one jq reads the message, a line each: compact JSON holds no newline, a method's control characters are spaces
    _parts=$(printf '%s' "$1" | jq -r 'if type != "object" or .jsonrpc != "2.0" then "bad", "null", "", "{}", "{}"
        else (if (has("method") | not) then "answer" elif has("id") then "request" else "note" end),
            (.id | tojson), (.method // "" | tostring | gsub("[\u0000-\u001f]"; " ")), (.params // {} | tojson), (.result // {} | tojson) end' 2>/dev/null) \
        || { rpc_error null -32700 "not JSON"; return 0; }
    { IFS= read -r _kind; IFS= read -r _id; IFS= read -r _method; IFS= read -r _params; IFS= read -r _result; } <<EOF
$_parts
EOF
    case $_kind in
        request) ;;
        answer)   # the one question this server asks: the host's roots
            [ "$_id" = '"roots"' ] && provide_roots "$_result"; return 0 ;;
        note)   # ask the host for its roots when it has them
            case $_method in notifications/initialized|notifications/roots/list_changed)
                [ -z "$CLIENT_ROOTS" ] || rpc_send "$(jq -cn '{jsonrpc: "2.0", id: "roots", method: "roots/list"}')" ;; esac
            return 0 ;;
        *) rpc_error null -32600 "one JSON-RPC 2.0 object a line"; return 0 ;;
    esac
    case $_id in '"'*|[0-9]*|-[0-9]*) ;; *) rpc_error null -32600 "an id is a string or a number"; return 0 ;; esac
    case $_method in
        initialize)
            PROVIDE_CLIENT=$(printf '%s' "$_params" | jq -r '.clientInfo.name // "" | tostring | gsub("[^A-Za-z0-9._-]"; "")')
            [ "$(printf '%s' "$_params" | jq -r '.capabilities.experimental["spark-shell/pairing"] == true')" != true ] || CLIENT_PAIRING=1
            [ "$(printf '%s' "$_params" | jq -r '.capabilities.roots != null')" != true ] || CLIENT_ROOTS=1
            rpc_result "$_id" "$(jq -cn --arg v "$PROVIDE_PROTOCOL" --arg n "$sec" --arg t "$(provide_title "$sec")" --arg ver "$(panel_version)" \
                '{protocolVersion: $v, capabilities: {tools: {listChanged: true}, resources: {subscribe: true, listChanged: true}, logging: {}}, serverInfo: {name: $n, title: $t, version: $ver}}')" ;;
        ping|logging/setLevel) rpc_result "$_id" '{}' ;;
        tools/list) rpc_result "$_id" "$(provide_tools "$sec" | jq -c '{tools: .}')" ;;
        tools/call) provide_call "$_id" "$_params" ;;
        resources/list) rpc_result "$_id" "$(jq -cn --arg u "spark-shell://$sec/rows" --arg s "$sec" '{resources: [{uri: $u, name: "rows", title: ($s + " rows"), mimeType: "application/json"}]}')" ;;
        resources/templates/list) if [ "$sec" = files ]; then rpc_result "$_id" '{"resourceTemplates":[{"uriTemplate":"spark-shell://files/rows/{folder}{?from}","name":"folder","title":"a folder under the roots, a page of it from an entry","mimeType":"application/json"},{"uriTemplate":"spark-shell://files/rows/match/{words}","name":"match","title":"the names under your home that hold the words","mimeType":"application/json"},{"uriTemplate":"spark-shell://files/preview/{file}{?page}","name":"preview","title":"a file shown as a page","mimeType":"application/json"}]}'
            else rpc_result "$_id" "$(jq -cn --arg s "$sec" '{resourceTemplates: ([{uriTemplate: ("spark-shell://" + $s + "/page/{row}"), name: "page", title: "a row shown as a page", mimeType: "application/json"}] + (if $s == "notes" then [{uriTemplate: "spark-shell://notes/rows/find/{words}", name: "find", title: "the notes whose text holds the words", mimeType: "application/json"}] else [] end))}')"; fi ;;
        resources/read|resources/subscribe|resources/unsubscribe)
            _uri=$(printf '%s' "$_params" | jq -r '.uri // "" | tostring')
            if [ "$sec" = files ] && [ "$_method" = resources/read ] && case $_uri in spark-shell://files/rows/?*) true ;; *) false ;; esac; then   # a folder under the roots, or the trash
                if provide_files_rows "$_uri" > "$TMP/folder.json"; then rpc_result "$_id" "$(jq -c --arg u "$_uri" '{contents: [{uri: $u, mimeType: "application/json", text: tojson}]}' "$TMP/folder.json")"
                else rpc_error "$_id" -32002 "no folder at that uri"; fi
                return 0
            fi
            if [ "$sec" = files ] && [ "$_method" = resources/read ] && case $_uri in spark-shell://files/preview/?*) true ;; *) false ;; esac; then   # a file shown as a page
                _pu=${_uri#spark-shell://files/preview/}; _ppg=1; _ppf=''
                case $_pu in *'?'*) _pq=${_pu#*'?'}; _pu=${_pu%%'?'*}
                    case "&$_pq&" in *'&page='*) _ppg=${_pq#*page=}; _ppg=${_ppg%%'&'*} ;; esac
                    case "&$_pq&" in *'&full=1&'*) _ppf=full ;; esac ;;
                esac
                if _pp=$(files_unb64 "$_pu") && files_page "$_pp" "$_ppg" "$_ppf" > "$TMP/page.out"; then rpc_result "$_id" "$(jq -c --arg u "$_uri" '{contents: [{uri: $u, mimeType: "application/json", text: tojson}]}' "$TMP/page.out")"
                else rpc_error "$_id" -32002 "no file at that uri"; fi
                return 0
            fi
            if [ "$sec" = theme ] && [ "$_uri" = "spark-shell://theme/rows/wallpapers" ] && [ "$_method" = resources/read ]; then   # the wallpaper list
                provide_wall_rows > "$TMP/wall.last"   # the rows the host has: the gate's
                rpc_result "$_id" "$(jq -c --arg u "$_uri" '{contents: [{uri: $u, mimeType: "application/json", text: tojson}]}' "$TMP/wall.last")"; return 0
            fi
            if [ "$sec" = theme ] && [ "$_uri" = "spark-shell://theme/rows/animations" ] && [ "$_method" = resources/read ]; then   # the animation list
                rpc_result "$_id" "$(provide_anim_rows | jq -c --arg u "$_uri" '{contents: [{uri: $u, mimeType: "application/json", text: tojson}]}')"; return 0
            fi
            if [ "$sec" = display ] && [ "$_method" = resources/read ] && case $_uri in spark-shell://display/rows/screen/?*) true ;; *) false ;; esac; then
                if provide_screen_rows "${_uri##*/}" > "$TMP/screen.json"; then rpc_result "$_id" "$(jq -c --arg u "$_uri" '{contents: [{uri: $u, mimeType: "application/json", text: tojson}]}' "$TMP/screen.json")"
                else rpc_error "$_id" -32002 "no screen at that uri"; fi
                return 0
            fi
            if { [ "$sec" = lan ] || [ "$sec" = wifi ]; } && [ "$_method" = resources/read ] && case $_uri in spark-shell://"$sec"/rows/network/?*) true ;; *) false ;; esac; then
                if provide_network_rows "$sec" "${_uri##*/}" > "$TMP/network.rows"; then rpc_result "$_id" "$(jq -c --arg u "$_uri" '{contents: [{uri: $u, mimeType: "application/json", text: tojson}]}' "$TMP/network.rows")"
                else rpc_error "$_id" -32002 "no network interface at that uri"; fi
                return 0
            fi
            if [ "$sec" = window ] && [ "$_method" = resources/read ] && case $_uri in spark-shell://window/rows/?*) true ;; *) false ;; esac; then   # a picker of the workspace place
                rpc_result "$_id" "$(provide_window_rows "$_uri" | jq -c --arg u "$_uri" '{contents: [{uri: $u, mimeType: "application/json", text: tojson}]}')"; return 0
            fi
            if [ "$sec" = tools ] && [ "$_method" = resources/read ] && case $_uri in spark-shell://tools/rows/?*) true ;; *) false ;; esac; then   # a tool's page
                if provide_tools_page "${_uri#spark-shell://tools/rows/}" > "$TMP/tools.page" 2>/dev/null && [ -s "$TMP/tools.page" ]; then rpc_result "$_id" "$(jq -c --arg u "$_uri" '{contents: [{uri: $u, mimeType: "application/json", text: tojson}]}' "$TMP/tools.page")"
                else rpc_error "$_id" -32002 "no tool page at that uri"; fi
                return 0
            fi
            if [ "$sec" = clock ] && [ "$_method" = resources/read ] && [ "$_uri" = "spark-shell://clock/rows/settings" ]; then
                rpc_result "$_id" "$(provide_rows clock settings | jq -c --arg u "$_uri" '{contents: [{uri: $u, mimeType: "application/json", text: tojson}]}')"; return 0
            fi
            if [ "$_method" = resources/read ] && case $_uri in "spark-shell://$sec/page/"?*) true ;; *) false ;; esac; then   # a row shown as a page, Space's
                if _pid=$(files_unb64 "${_uri#"spark-shell://$sec/page/"}") && provide_page "$sec" "$_pid" > "$TMP/rowpage.json" 2>/dev/null && [ -s "$TMP/rowpage.json" ]; then rpc_result "$_id" "$(jq -c --arg u "$_uri" '{contents: [{uri: $u, mimeType: "application/json", text: tojson}]}' "$TMP/rowpage.json")"
                else rpc_error "$_id" -32002 "no page at that uri"; fi
                return 0
            fi
            if [ "$sec" = notes ] && [ "$_method" = resources/read ] && case $_uri in spark-shell://notes/rows/find/?*) true ;; *) false ;; esac; then   # the notes whose text holds every word, for a search from Home
                if NOTES_WORDS=$(files_unb64 "${_uri##*/}") && [ -n "$NOTES_WORDS" ] && provide_rows notes > "$TMP/notes.found.json"; then
                    rpc_result "$_id" "$(jq -c --arg u "$_uri" '.rows |= map(select(.tool.name == "notes_open")) | .short = [] | {contents: [{uri: $u, mimeType: "application/json", text: tojson}]}' "$TMP/notes.found.json")"
                else rpc_error "$_id" -32002 "no search at that uri"; fi
                NOTES_WORDS=''
                return 0
            fi
            if [ "$sec" = tools ] && [ "$_uri" = "spark-shell://tools/rows/running" ]; then   # running, read again every 3 seconds while it is on screen
                case $_method in
                    resources/subscribe) SUBSCRIBED=1; [ -n "$WATCH" ] || { provide_watch tools running 5>"$TMP/in" 3>&- 4<&- & WATCH=$!; }; rpc_result "$_id" '{}' ;;
                    resources/unsubscribe) SUBSCRIBED=''; [ -z "$WATCH" ] || { kill "$WATCH" 2>/dev/null || :; wait "$WATCH" 2>/dev/null || :; WATCH=''; }; rpc_result "$_id" '{}' ;;
                esac
                return 0
            fi
            [ "$_uri" = "spark-shell://$sec/rows" ] || { rpc_error "$_id" -32002 "no resource at that uri"; return 0; }
            case $_method in
                resources/read) provide_rows "$sec" > "$TMP/rows.last"; provide_seen   # the rows the host has: the gate's, the watcher's
                    rpc_result "$_id" "$(jq -c --arg u "$_uri" '{contents: [{uri: $u, mimeType: "application/json", text: tojson}]}' "$TMP/rows.last")" ;;
                resources/subscribe) SUBSCRIBED=1
                    case " $PROVIDE_WATCHED " in *" $sec "*) [ -n "$WATCH" ] || { provide_watch "$sec" 5>"$TMP/in" 3>&- 4<&- & WATCH=$!; } ;; esac
                    [ "$sec" != tools ] || [ -n "$WATCH" ] || { _sum=$({ cksum < "$TOOLS_CHECK"; } 2>/dev/null); provide_watch_check "$_sum" 5>"$TMP/in" 3>&- 4<&- & WATCH=$!; }
                    rpc_result "$_id" '{}' ;;
                resources/unsubscribe) SUBSCRIBED=''; [ -z "$WATCH" ] || { kill "$WATCH" 2>/dev/null || :; wait "$WATCH" 2>/dev/null || :; WATCH=''; }; rpc_result "$_id" '{}' ;;
            esac ;;
        *) rpc_error "$_id" -32601 "no method $_method here" ;;
    esac
}
provide_notes_append() {   # two typed arguments; note contents never travel through the panel's token grammar
    printf '%s' "$2" | jq -e 'type == "object" and keys == ["name","text"]
        and (.name | type == "string" and length > 0 and length <= 255 and (test("[\u0000-\u001f\u007f-\u009f/]") | not))
        and (.text | type == "string" and length > 0 and length <= 16384 and (test("[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f-\u009f]") | not))' >/dev/null 2>&1 \
        || { rpc_error "$1" -32602 'notes_append takes an exact filename and text of 1 to 16384 characters; only tabs and line breaks are allowed controls'; return 0; }
    _pna_name=$(printf '%s' "$2" | jq -r .name)
    printf '%s' "$2" | jq -j .text > "$TMP/note.append" || { provide_refuse "$1" 'the text could not be prepared; nothing appended'; return 0; }
    rm -f "$TMP/action.effect"
    if _pna_out=$(PROVIDE_EFFECT=1 note_append "$_pna_name" "$TMP/note.append" 2>/dev/null); then
        rm -f "$TMP/note.append"
        [ -s "$TMP/action.effect" ] || { provide_refuse "$1" 'the text may have been appended, but the note could not be read back; check it before trying again'; return 0; }
        rpc_result "$1" "$(jq -cn --arg r "$_pna_out" --slurpfile e "$TMP/action.effect" '{receipt:$r,effect:$e[0]}' | jq -c '{content:[{type:"text",text:tojson}],structuredContent:.,isError:false}')"
        [ -z "$SUBSCRIBED" ] || rpc_note notifications/resources/updated '{"uri":"spark-shell://notes/rows"}'
    else
        rm -f "$TMP/note.append"
        provide_refuse "$1" "${_pna_out:-could not append the text; check the note before trying again}"
    fi
}
provide_notes_step() {   # provide_notes_step ID TOOL ARGS -- a note renamed, put in the trash or brought back: by its exact filename, the undo in its result
    printf '%s' "$3" | jq -e --arg t "$2" 'type == "object" and (.name | type == "string" and length <= 255 and test("^[^./\u0000-\u001f\u007f][^/\u0000-\u001f\u007f]*[.]md$"))
        and (if $t == "notes_rename" then keys == ["name","to"] and (.to | type == "string" and length > 0 and length <= 255 and (test("[\u0000-\u001f\u007f-\u009f]") | not)) else keys == ["name"] end)' >/dev/null 2>&1 \
        || { rpc_error "$1" -32602 "$2 takes a note's exact filename$([ "$2" != notes_rename ] || echo ', and a title of 1 to 255 characters')"; return 0; }
    _nsn=$(printf '%s' "$3" | jq -r .name)
    _nsd=$(realpath "$NOTES_DIR" 2>/dev/null) || { provide_refuse "$1" "notes: there is no ~/notes"; return 0; }
    _nsf=$_nsd/$_nsn
    case $2 in notes_rename|notes_trash) [ -f "$_nsf" ] && [ ! -L "$_nsf" ] || { provide_refuse "$1" "notes: no note is called $_nsn now"; return 0; } ;; esac
    _nsp=${PROOTS:-}; files_home_root > "$TMP/notes.roots"; PROOTS=$TMP/notes.roots   # the trash a note goes to is your home's, whatever roots the host gave
    case $2 in
        notes_rename)
            _nst=$(printf '%s' "$3" | jq -r .to)
            _nso=$(awk 'NF { sub(/^#+[ \t]*/, ""); print; exit }' "$_nsf"); [ -n "$_nso" ] || _nso=${_nsn%.md}   # the old title as written, for the undo
            _nsw=$(note_name "$_nsf")
            if note_retitle "$_nsf" "$_nst"; then files_result "$1" "$_nsw renamed to $(note_name "$_nsf")" notes_rename "$(jq -cn --arg n "$_nsn" --arg t "$_nso" '{name: $n, to: $t}')"
            else provide_refuse "$1" "notes: could not rename $_nsw"; fi ;;
        notes_trash)
            _nsw=$(note_name "$_nsf")
            if _nsx=$(files_trash "$_nsf"); then files_result "$1" "$_nsw is in the trash" notes_restore "$(jq -cn --arg n "$_nsn" '{name: $n}')"
            else provide_refuse "$1" "notes: $_nsx"; fi ;;
        notes_restore)
            if _nsx=$(files_restore "$_nsf"); then files_result "$1" "$(note_name "$_nsf") is back" notes_trash "$(jq -cn --arg n "$_nsn" '{name: $n}')"
            else provide_refuse "$1" "notes: $_nsx"; fi ;;
    esac
    PROOTS=$_nsp
}
note_retitle() {   # note_retitle FILE TITLE -- the first line that says something becomes TITLE, its hashes kept; none: TITLE as a heading
    _nrt=$(mktemp "${1%/*}/.retitle.XXXXXX") || return 1
    T=$2 awk 'BEGIN { t = ENVIRON["T"] } !done && NF { if (match($0, /^#+[ \t]*/)) print substr($0, 1, RLENGTH) t; else print t; done = 1; next } { print } END { if (!done) print "# " t }' "$1" > "$_nrt" \
        && mv "$_nrt" "$1" || { rm -f "$_nrt"; return 1; }
}
provide_ask() {   # provide_ask CALL-ID MESSAGE FIELD TITLE -> what the person typed for FIELD (MCP elicitation); false when declined, cancelled or unanswered in five minutes
    _aid="ask-$1"
    rpc_send "$(jq -cn --arg i "$_aid" --arg m "$2" --arg f "$3" --arg t "$4" '{jsonrpc: "2.0", id: $i, method: "elicitation/create", params: {message: $m, requestedSchema: {type: "object", properties: {($f): {type: "string", title: $t, maxLength: 256}}, required: [$f]}}}')"
    ( sleep 300; fifo_put "in $(jq -cn --arg i "$_aid" '{jsonrpc: "2.0", id: $i, result: {action: "cancel"}}')" ) >/dev/null 2>&1 3>&- 4<&- & _ag=$!   # its own fds: this function runs in a command substitution, and a child holding its stdout would hold the answer five minutes
    _ans=''; _ast=1
    while IFS= read -r _am <&4; do   # the loop's lines until the answer: a poke is dropped, another request is told to wait, eof ends the provider
        case $_am in
            eof) kill "$_ag" 2>/dev/null || :; exit 0 ;;   # the wire ended: the provider with it
            poke) continue ;;
            "in "*) _al=${_am#in }
                case $(printf '%s' "$_al" | jq -r --arg i "$_aid" 'if .id == $i and (has("method") | not) then "mine" elif has("method") and has("id") then "request" else "other" end' 2>/dev/null) in
                    mine) _ans=$(printf '%s' "$_al" | jq -r --arg f "$3" 'select(.result.action == "accept") | .result.content[$f] // "" | tostring' 2>/dev/null | scrub_text | tr -d '\n' | cut -c1-256)
                        [ -z "$_ans" ] || _ast=0
                        break ;;
                    request) rpc_error "$(printf '%s' "$_al" | jq -c '.id')" -32000 "a question is open: answer it, or Esc" ;;
                esac ;;
        esac
    done
    { ! command -v pgrep >/dev/null 2>&1 || kill $(pgrep -P "$_ag") 2>/dev/null; kill "$_ag" 2>/dev/null; } || :   # the sleeper and its sleep
    [ "$_ast" -eq 0 ] || return 1
    printf '%s' "$_ans"
}
provide_call() {   # provide_call ID PARAMS -- the step: the tool, its arguments checked, the row, the gate, then the step
    # the name, the arguments and the progress token in one jq: a line each, compact JSON holds no newline
    _parts=$(printf '%s' "$2" | jq -r '(.name // "" | tostring | gsub("[\u0000-\u001f]"; " ")), (.arguments // {} | tojson), (._meta.progressToken // "" | if . == "" then "" else tojson end)')
    { IFS= read -r _name; IFS= read -r _args; IFS= read -r _tok; } <<EOF
$_parts
EOF
    case $_name in *[!a-z0-9_]*|[!a-z]*|'') rpc_error "$1" -32602 "no tool by that name"; return 0 ;; esac
    WIN_LABELS_READ=''   # a call's own read of the windows is its alone
    { tool_spec "$_name" && [ "$_ts" = "$sec" ]; } || { rpc_error "$1" -32602 "no tool $_name in $sec"; return 0; }
    case $_th in *p*) provide_person_ok || { rpc_error "$1" -32602 "$_name runs from its row in the dialog, never from a plan"; return 0; } ;; esac
    _title=$_tt   # the call's own title: the undo's tool_spec below sets _tt to its own
    [ "$_name" != notes_append ] || { provide_notes_append "$1" "$_args"; return 0; }
    case $_name in notes_rename|notes_trash|notes_restore) provide_notes_step "$1" "$_name" "$_args"; return 0 ;; esac   # a note's file by its exact name, as the append
    _bad=$(printf '%s' "$_args" | jq -r --arg p "$_tp" --arg k "$_tk" --arg q "$_tq" --arg x "$_te" '
        def plain: test("^[^\u0000-\u001f\u007f-\u009f\u200b-\u200f\u202a-\u202e\u2060-\u2069\ufeff\u2028\u2029]{1,256}$");
        ($x | split(" ") | map(select(. != "") | split(":") | [(.[0] | rtrimstr("?")), .[1], (.[0] | endswith("?"))])) as $xs | ($xs | map(.[0])) as $xk | . as $a |
        [$xs[] | select(.[1] != "text" and .[1] != "seconds" and .[1] != "pixels" and (.[2] | not))] as $xr | [$xs[] | select(. as $e | $a | has($e[0]))] as $xp |   # the extras a call must give; the ones this call gave
        if type != "object" then "arguments are an object"
        elif (keys - [$p, $q] - $xk - [""]) != [] then "no argument " + ((keys - [$p, $q] - $xk)[0])
        elif $p != "" and (has($p) | not) then "missing " + $p
        elif ([$xr[] | select(. as $e | $a | has($e[0]) | not)] | length) > 0 then "missing " + ([$xr[] | select(. as $e | $a | has($e[0]) | not)][0][0])
        elif ([$xp[] | select(.[1] != "text" and .[1] != "name" and .[1] != "filename" and .[1] != "path" and .[1] != "coordinate" and .[1] != "scale" and .[1] != "mode" and .[1] != "port" and .[1] != "net" and .[1] != "seconds" and .[1] != "pixels") | . as $e | select((($e[1] | split("|")) | index([$a[$e[0]]])) | not)] | length) > 0 then ([$xp[] | select(.[1] != "text" and .[1] != "name" and .[1] != "filename" and .[1] != "path" and .[1] != "coordinate" and .[1] != "scale" and .[1] != "mode" and .[1] != "port" and .[1] != "net" and .[1] != "seconds" and .[1] != "pixels") | . as $e | select((($e[1] | split("|")) | index([$a[$e[0]]])) | not)][0] | .[0] + " is one of " + (.[1] | split("|") | join(", ")))
        elif any($xp[]; . as $e | .[1] == "filename" and (($a[$e[0]] | type) != "string" or ($a[$e[0]] | length) < 1 or ($a[$e[0]] | length) > 255 or ($a[$e[0]] | test("[\u0000-\u001f\u007f/]")))) then "name is one name, no slash, 255 characters at most"
        elif any($xp[]; . as $e | .[1] == "path" and (($a[$e[0]] | type) != "string" or ($a[$e[0]] | startswith("/") | not) or ($a[$e[0]] | length) > 4096 or ($a[$e[0]] | test("[\u0000-\u001f\u007f]")))) then "to is a whole path, plain text"
        elif ([$xs[] | select(.[1] == "text" or .[1] == "name") | . as $e | select(($a | has($e[0])) and ((($a[$e[0]] | type) != "string") or (($a[$e[0]] | length) > 40) or (($a[$e[0]]) | plain | not)))] | length) > 0 then ([$xs[] | select(.[1] == "text" or .[1] == "name") | .[0]][0]) + " is plain text, 40 characters at most"
        elif any($xs[]; . as $e | .[1] == "coordinate" and (($a[$e[0]] | type) != "number" or $a[$e[0]] < -65535 or $a[$e[0]] > 65535 or $a[$e[0]] != ($a[$e[0]] | floor))) then "coordinates are whole numbers, -65535 to 65535"
        elif any($xs[]; . as $e | .[1] == "scale" and (if ($a[$e[0]] | type) != "string" then true else ($a[$e[0]] | length) > 16 or ($a[$e[0]] | test("^[0-9]+([.][0-9]+)?$") | not) or (($a[$e[0]] | tonumber? // 0) <= 0) end)) then "scale is a positive decimal"
        elif any($xs[]; . as $e | .[1] == "mode" and (($a[$e[0]] | type) != "string" or ($a[$e[0]] | test("^[0-9]{2,5}x[0-9]{2,5}(@[0-9]{1,4}([.][0-9]{1,3})?Hz)?$") | not))) then "mode is WIDTHxHEIGHT or WIDTHxHEIGHT@REFRESHHz"
        elif any($xs[]; . as $e | .[1] == "net" and (($a[$e[0]] | type) != "string" or ($a[$e[0]] | test("^[A-Za-z0-9.,:/-]{1,80}$") | not))) then "network values are addresses, none or auto"
        elif any($xs[]; . as $e | .[1] == "seconds" and ($a | has($e[0])) and (($a[$e[0]] | type) != "number" or $a[$e[0]] < 0 or $a[$e[0]] > 86400)) then "at is a number of seconds, 0 to 86400"
        elif any($xs[]; . as $e | .[1] == "pixels" and ($a | has($e[0])) and (($a[$e[0]] | type) != "number" or $a[$e[0]] < 0 or $a[$e[0]] > 65535 or $a[$e[0]] != ($a[$e[0]] | floor))) then "x, y, w and h are whole numbers of pixels, 0 to 65535"
        elif any($xs[]; . as $e | .[1] == "port" and (($a[$e[0]] | type) != "string" or ($a[$e[0]] | test("^[A-Za-z0-9_.:-]{1,80}$") | not))) then "other is a connected screen port"
        elif $p == "" then ""
        elif $k == "level" then (if (.[$p] | type) == "number" and .[$p] == (.[$p] | floor) and .[$p] >= 0 and .[$p] <= 100 then "" else $p + " is a whole number, 0 to 100" end)
        elif $k == "delta" then (if (.[$p] | type) == "number" and .[$p] == (.[$p] | floor) and .[$p] >= -100 and .[$p] <= 100 then "" else $p + " is a whole number of percentage points, -100 to 100" end)
        elif $k == "bright" then (if ((.[$p] | type) == "number" and .[$p] == (.[$p] | floor) and .[$p] >= 1 and .[$p] <= 100) or ((.[$p] | type) == "string" and (.[$p] | test("^(up|down|[1-9][0-9]?|100)$"))) then "" else $p + " is up, down or a whole number, 1 to 100" end)
        elif $k == "minutes" then (if (.[$p] | type) == "number" and .[$p] == (.[$p] | floor) and .[$p] >= 0 and .[$p] <= 999 then "" else $p + " is a whole number of minutes, 0 to 999" end)
        elif $k == "speed" then (if (.[$p] | type) == "number" and .[$p] >= -1 and .[$p] <= 1 then "" else $p + " is a number, -1 to 1" end)
        elif $k == "delay" then (if (.[$p] | type) == "number" and .[$p] == (.[$p] | floor) and .[$p] >= 100 and .[$p] <= 2000 then "" else $p + " is a whole number, 100 to 2000" end)
        elif $k == "alpha" then (if (.[$p] | type) == "number" and .[$p] >= 0 and .[$p] <= 1 then "" else $p + " is a number, 0 to 1" end)
        elif $k == "path" then (if (.[$p] | type) == "string" and (.[$p] | startswith("/")) and (.[$p] | length) <= 4096 and (.[$p] | test("[\u0000-\u001f\u007f]") | not) then "" else $p + " is a whole path, plain text" end)
        elif (.[$p] | type) != "string" or ((.[$p]) | plain | not) then $p + " is plain text, 256 characters at most"
        elif ($k | contains("|")) and (.[$p] as $x | $k | split("|") | any(. == $x) | not) then $p + " is one of " + ($k | split("|") | join(", "))
        else "" end
        + (if $q != "" and has($q) and ((.[$q] | type) != "string" or (.[$q] | length) > 256) then "; " + $q + " is text, 256 characters at most" else "" end)')
    [ -z "$_bad" ] || { rpc_error "$1" -32602 "$_name: $_bad"; return 0; }
    [ "$sec" != files ] || { provide_files_call "$1" "$_name" "$_args"; return 0; }   # files: the four lines, not the panel's gate; a name whole, never its slug
    # the step's value (a text extra as its slug) and the arguments without the secret: one jq, a line each
    _parts=$(printf '%s' "$_args" | jq -r --arg p "$_tp" --arg x "$_te" --arg q "$_tq" '. as $a
        | (if $p == "" then "" else [$a[$p] | tostring] + [$x | split(" ")[] | select(. != "") | split(":") | [(.[0] | rtrimstr("?")), .[1]] | . as $e | select($a[$e[0]] != null) | $e[0] + "=" + (($a[$e[0]] | tostring) | if $e[1] == "text" or $e[1] == "name" then ascii_downcase | gsub("[^a-z0-9]+"; "-") | gsub("^-+|-+$"; "") | .[0:40] else . end)] | join(" ") end),
          (if $q == "" then . else del(.[$q]) end | tojson)')
    { IFS= read -r _v; IFS= read -r _plain; } <<EOF
$_parts
EOF
    PANEL_PASS=''; [ -z "$_tq" ] || PANEL_PASS=$(printf '%s' "$_args" | jq -r --arg q "$_tq" '.[$q] // ""')   # a password: a shell variable for the step, never a file, never a line out
    case $_name in
        notes_open) _resolved=$(note_file "$_v") || { provide_refuse "$1" 'select one note by its filename; that name is missing or ambiguous'; return 0; }; _v=${_resolved##*/} ;;
        reminders_done|reminders_snooze|reminders_delete) _resolved=$(rem_find "$_v") || { provide_refuse "$1" 'select one reminder by its UID; that name is missing or ambiguous'; return 0; }; _v=$(printf '%s' "$_resolved" | cut -f2) ;;
        window_focus|window_close) win_label > "$TMP/win.labels"; WIN_LABELS_READ=1   # the windows read once for the call: its check, its name, the step's
            _v=$(win_named "$_v") || { provide_refuse "$1" 'select one open window by its ID; that name is missing or ambiguous'; return 0; } ;;
    esac
    case $_name in notes_open|reminders_done|reminders_snooze|reminders_delete|window_focus|window_close) _plain=$(jq -cn --arg n "$_v" '{name:$n}') ;; esac
    _act=$_ta; _arg=$_v; [ "$_ta" != '=' ] || { _act=$_v; _arg=''; }   # a palette's step is its name alone
    if [ "$_name" = reminders_add ] && ! rem_parse "$_v" >/dev/null 2>&1; then   # no day and time in the words: one question, then the step with the answer in front
        case $(printf '%s' "$_v" | tr 'A-Z' 'a-z') in "remind me to "*) _v=$(printf '%s' "$_v" | cut -c14-) ;; "remind me "*) _v=$(printf '%s' "$_v" | cut -c11-) ;; esac   # the title is what follows
        _when=$(provide_ask "$1" "When" when "5pm, tomorrow 9:00, in 20 min") || { provide_refuse "$1" "not done: no time given"; return 0; }
        _v="$_when $_v"; _arg=$_v
    fi
    PANEL_ROW_MATCHED=''
    case $_th in *f*) ;; *)   # the rows are the allowlist: the ones the host was last sent, else read now
        provide_quick "$sec" "$_name" "$_v" && _quick=1 || _quick=''
        if [ -z "$_quick" ]; then
            [ -s "$TMP/rows.last" ] || provide_rows "$sec" > "$TMP/rows.last"
            cat "$TMP/rows.last" > "$TMP/rows.json"
            if [ "$sec" = theme ]; then   # the wallpaper list's rows are the theme's too
                [ -s "$TMP/wall.last" ] || provide_wall_rows > "$TMP/wall.last"
                cat "$TMP/wall.last" >> "$TMP/rows.json"
            fi
            jq -e -s --arg n "$_name" --argjson a "$_plain" 'any(.[] | ((.rows // [])[] | .tool, (.more // [])[], (.step // empty | . as $s | $s.values[] | . as $v | $s.set | .arguments[$s.key] = $v.sent), .switch.turn_on, .switch.turn_off, .look), .look_back | select(. != null); .name == $n and .arguments == $a)' "$TMP/rows.json" >/dev/null 2>&1 \
                && PANEL_ROW_MATCHED=1
        fi
        [ -n "$_quick$PANEL_ROW_MATCHED" ] || provide_in_use "$sec" "$_name" "${_arg:-$_act}" \
            || { provide_refuse "$1" "${_arg:-$_act} is not in the list now"; return 0; } ;;
    esac
    _g=$(panel_gate "$sec" "$_act" "$_arg") || { PANEL_ROW_MATCHED=''; provide_refuse "$1" "$(printf '%s' "$_g" | scrub_text)"; return 0; }
    PANEL_ROW_MATCHED=''
    # the inverse read once, before the step: the state now is what undo puts back; panel_step takes it as it is
    _undo='null'; PANEL_INV=$(panel_inverse "$sec" "$_act" "$_g"); PANEL_INV_READ=1; _inv=${PANEL_INV%%"$TAB"*}
    if [ -n "$_inv" ] && action_tool "$sec" "$_inv"; then _undo=$(tool_call_json "$_tool" "$_tv") || _undo='null'; fi
    BT_BRIDGE=''
    if [ "$_name" = bt_pair ]; then
        [ -n "$CLIENT_PAIRING" ] || { provide_refuse "$1" "pairing needs a client that supports native pairing questions"; return 0; }
        BT_BRIDGE=$TMP
        rm -f "$TMP/bt.cancel" "$TMP/bt.ask"
        printf '%s\n' "$1" > "$TMP/bt.call-id"
    fi
    export BT_BRIDGE
    rm -f "$TMP/opened" "$TMP/action.effect"
    : > "$TMP/step.mark"   # the settings read again after the step only when it wrote them
    PROVIDE_EFFECT=1; PANEL_JOURNAL=off   # the terminal panel's recent picks and undo journal are its own: a host's step writes neither
    ( set +e; panel_step "$sec" "$_act" "$_g" > "$TMP/call.out" 2>&1; echo $? > "$TMP/call.rc" ) 3>&- 4<&- 5>&- & _w=$!
    if [ -n "$_tok$BT_BRIDGE" ]; then
        _i=0
        while kill -0 "$_w" 2>/dev/null; do
            if [ -f "$TMP/bt.ask" ]; then rpc_send "$(cat "$TMP/bt.ask")"; rm -f "$TMP/bt.ask"; fi
            if [ -n "$_tok" ]; then _i=$((_i + 1)); rpc_note notifications/progress "$(jq -cn --argjson t "$_tok" --argjson p "$_i" --arg s "$sec" '{progressToken: $t, progress: $p, message: ($s + ": working")}')"; fi
            if [ -n "$BT_BRIDGE" ]; then sleep 0.1; else sleep 0.5; fi
        done
    fi
    wait "$_w" 2>/dev/null || :
    PANEL_PASS=''; BT_BRIDGE=''; PANEL_INV=''; PANEL_INV_READ=''; PANEL_JOURNAL=''; WIN_LABELS_READ=''; rm -f "$TMP/bt.call-id" "$TMP/bt.ask"
    _rc=$(cat "$TMP/call.rc" 2>/dev/null || echo 1); _out=$(scrub_text < "$TMP/call.out")
    if [ -n "$(find "$CONFIG" "$THEME_ENV" -newer "$TMP/step.mark" 2>/dev/null)" ]; then   # the step changed the settings: the rows read them anew
        for _k in $THEME_KEYS; do unset "$_k"; done; config_load; theme_load
    fi
    if [ "$_rc" -ne 0 ]; then provide_refuse "$1" "${_out:-$sec: $_title did not work}"; return 0; fi
    case $_name in notes_add|reminders_*|out_level|out_adjust|out_mute|out_unmute|mic_level|mic_adjust|mic_mute|mic_unmute|window_focus|window_close)
        [ -s "$TMP/action.effect" ] || { provide_refuse "$1" 'the action may have happened, but its result could not be read back; check the current state before trying again'; return 0; } ;;
    esac
    _pal='null'; _trn='null'   # a theme step: the palette now, so the dialog repaints itself
    [ "$sec" != theme ] || { _trn=$(dialog_transitions); _trn=$(jq -cn --arg t "$_trn" '$t'); }   # and its animation now, read again by an open dialog: "" plays none
    if [ "$_name" = theme_preview ]; then   # a look: the colors on the screen, no animation changed, nothing to undo
        _trn=null; _undo=null; _pal=$(cat "$TMP/preview.palette" 2>/dev/null || :); [ -n "$_pal" ] || _pal=null; rm -f "$TMP/preview.palette"
    fi
    [ "$sec" != theme ] || [ "$_name" = theme_preview ] || { panel_load; _pal=$(jq -cn --arg f "$HEX_FG" --arg a "$HEX_ACCENT" --arg m "$PANEL_MUTED" --arg b "$PANEL_BG" --arg h "$PANEL_HI" --arg r "${HEX_ANSI_1:-}" --arg g "${HEX_ANSI_2:-}" --arg y "$(bar_style GLYPH_FAMILY stone)" '{HEX_FG: $f, HEX_ACCENT: $a, PANEL_MUTED: $m, PANEL_BG: $b, PANEL_HI: $h, HEX_ANSI_1: $r, HEX_ANSI_2: $g, GLYPH_FAMILY: $y}
        + ($ENV | with_entries(select(.key | test("^HEX_ANSI_([0-9]|1[0-5])$"))))'); }   # and the glyph family and the 16 colors, for a piece the dialog draws
    if [ -s "$TMP/network.undo" ]; then _undo=$(tool_call_json "${sec}_restore" "$(cat "$TMP/network.undo")"); fi
    if [ -s "$TMP/sound.undo" ]; then _undo=$(tool_call_json "${sec}_level" "$(cat "$TMP/sound.undo")"); fi
    # the rows as the step left them go with the answer: the host reads nothing again, the gate and the watcher take them as seen
    [ -s "$TMP/action.effect" ] || printf 'null' > "$TMP/action.effect"
    if [ -f "$TMP/opened" ] || [ "$sec" = tools ]; then printf 'null' > "$TMP/rows.last.new"   # tools: the page on screen changed, not the six; with no rows the host reads both again
    else provide_rows "$sec" > "$TMP/rows.last.new" && cp "$TMP/rows.last.new" "$TMP/rows.last" && provide_seen; fi
    rpc_result "$1" "$(jq -cn --arg r "$_out" --argjson u "$_undo" --argjson p "$_pal" --argjson t "$_trn" --argjson o "$([ -f "$TMP/opened" ] && echo true || echo false)" \
        --slurpfile e "$TMP/action.effect" --slurpfile rows "$TMP/rows.last.new" '
        (if $o then {opened: true}
         else {receipt: $r} + (if $u == null then {} else {undo: $u} end) + (if $p == null then {} else {palette: $p} end)
            + (if $t == null then {} else {transitions: $t} end) + (if $rows[0] == null then {} else {rows: $rows[0]} end) end)
        + (if $e[0] == null then {} else {effect: $e[0]} end)
        | {content: [{type: "text", text: (del(.rows) | tojson)}], structuredContent: ., isError: false}')"
    rm -f "$TMP/action.effect" "$TMP/rows.last.new"
}
provide_quick() {   # provide_quick SECTION TOOL VALUE -> 0 for a pick the theme's rows always list, without drawing them
    [ "$1" = theme ] || return 1
    case $2 in
        theme_palette) case $(theme_kind "$3") in shipped|yours|saved|none) return 0 ;; look) [ "$3" = "${THEME:-}" ] ;; *) return 1 ;; esac ;;
        theme_wallpaper) [ "$OS" != Darwin ] && [ "$DESKTOP" = sway ] && { wall_shipped "$3" || [ "$3" = default ]; } ;;
        theme_text) case $3 in bigger|smaller|[6-9]|[1-3][0-9]|40) [ -n "$(look_font_size)" ] ;; *) return 1 ;; esac ;;   # a size as it is, the dialog's step
        theme_transparency) case ${3%\%} in more|less|[0-9]|[1-4][0-9]|50) return 0 ;; *) return 1 ;; esac ;;
        theme_preview) [ "$3" = off ] || case $(theme_kind "$3") in shipped|yours) return 0 ;; *) return 1 ;; esac ;;   # a palette's look, or the look in use again
        theme_animation) case " next back none $ANIMATION_NAMES " in *" $3 "*) return 0 ;; *) return 1 ;; esac ;;
        theme_glyphs) case $3 in signs|words) return 0 ;; *) return 1 ;; esac ;;
        theme_icons) case $3 in on|off) return 0 ;; *) return 1 ;; esac ;;
        theme_spacing) case $3 in none|groups|rows) return 0 ;; *) return 1 ;; esac ;;
        theme_family) case " $GLYPH_FAMILIES " in *" ${3:-none} "*) return 0 ;; *) return 1 ;; esac ;;
        theme_face) case " $FONT_FACES " in *" ${3:-none} "*) return 0 ;; *) return 1 ;; esac ;;
        theme_motion) case $3 in on|off) return 0 ;; *) return 1 ;; esac ;;
        *) return 1 ;;
    esac
}
provide_refuse() { rpc_result "$1" "$(jq -cn --arg t "$2" '{content: [{type: "text", text: $t}], isError: true}')"; }   # provide_refuse ID SENTENCE -- a tool's refusal, in the result
cmd_provide() {   # cmd_provide SECTION -- the verb
    [ $# -eq 1 ] || refuse_in provide "one section: $(printf '%s' "$PROVIDE_SECTIONS" | sed 's/ /, /g')" >&2
    provide_main "$1"
}

