# shellcheck extended-analysis=false
# ------------------------------------------------------------------- sbom
# sets: APPS SBOM_JSON
# reads: CONFIG_DIR DISTRO OS PM REPO ROOT TMP
# the machine's packages as the package manager says them: an app has a
# desktop entry, a tool a command without one, a part neither
SBOM_JSON=${XDG_STATE_HOME:-$HOME/.local/state}/spark-shell/sbom.cdx.json
APPS=$CONFIG_DIR/apps     # the allowed apps, one per line: `name[: your words]`
sbom_entries() {   # -> $TMP/entries: NAME<tab>FILE<tab>WHAT<tab>TERMINAL<tab>CATEGORIES<tab>LAUNCH, hidden ones out
    _sbd=''; for d in ${XDG_DATA_HOME:-$HOME/.local/share} $(printf '%s' "${XDG_DATA_DIRS:-/usr/local/share:/usr/share}" | tr ':' ' '); do _sbd="$_sbd $d/applications"; done
    dirs_cached apps.entries "$_sbd" 'sbom_entries_now; cat "$TMP/entries"' > "$TMP/entries.c" && mv "$TMP/entries.c" "$TMP/entries"
}
sbom_entries_now() {
    : > "$TMP/entries"
    for d in ${XDG_DATA_HOME:-$HOME/.local/share} $(printf '%s' "${XDG_DATA_DIRS:-/usr/local/share:/usr/share}" | tr ':' ' '); do
        [ -d "$d/applications" ] || continue
        for f in "$d"/applications/*.desktop; do
            [ -f "$f" ] || continue
            grep -qE '^(NoDisplay|Hidden)=true' "$f" && continue
            launch=$(sed -n 's/^Exec=//p' "$f" | head -1 | sed 's/^env [^ ]* //; s/ *%[ick]//g; s|^[^ ]*/||')
            name=${launch%% *}
            [ -n "$name" ] || continue
            grep -q "^$name	" "$TMP/entries" && continue
            what=''
            for key in Comment GenericName Name; do
                [ -n "$what" ] || what=$(sed -n "s/^$key=//p" "$f" | head -1)
            done
            term=no; grep -q '^Terminal=true' "$f" && term=yes
            cats=$(sed -n 's/^Categories=//p' "$f" | head -1 | sed 's/;$//')
            printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "$f" "$what" "$term" "$cats" "$launch" >> "$TMP/entries"
        done
    done
}
sbom_collect() {   # -> $TMP/sbom: NAME VERSION LICENSE REASON DESCRIPTION COMMANDS ENTRIES (tab-separated; KIND first)
    sbom_entries
    pm_detect 2>/dev/null || true
    : > "$TMP/files"   # PACKAGE<tab>PATH for every command and entry a package ships
    case $PM in
        pacman)
            pacman -Qi 2>/dev/null | awk -F' *: ' '
                /^Name/ {n=$2} /^Version/ {v=$2} /^Licenses/ {l=$2} /^Description/ {d=$2}
                /^Install Reason/ {r=($2 ~ /Explicitly/) ? "chosen" : "dependency"}
                /^$/ && n != "" {printf "%s\t%s\t%s\t%s\t%s\n", n, v, l, r, d; n=""}' > "$TMP/pkgs"
            pacman -Ql 2>/dev/null | awk '$2 ~ /^\/usr\/bin\/[^\/]+$/ || $2 ~ /\/applications\/[^\/]+\.desktop$/ {print $1 "\t" $2}' > "$TMP/files" ;;
        apt)
            dpkg-query -W -f='${Package}\t${Version}\t?\t?\t${binary:Summary}\n' 2>/dev/null > "$TMP/pkgs.raw"
            apt-mark showmanual 2>/dev/null | sort > "$TMP/manual"
            while IFS='	' read -r n v _ _ d; do
                lic=$(sed -n 's/^License: //p' "/usr/share/doc/$n/copyright" 2>/dev/null | head -1)
                if grep -qx "$n" "$TMP/manual"; then r=chosen; else r=dependency; fi
                printf '%s\t%s\t%s\t%s\t%s\n' "$n" "$v" "${lic:-?}" "$r" "$d"
                grep -E '^/usr/bin/[^/]+$|/applications/[^/]+\.desktop$' "/var/lib/dpkg/info/$n.list" 2>/dev/null | sed "s/^/$n\t/" >> "$TMP/files"
            done < "$TMP/pkgs.raw" > "$TMP/pkgs" ;;
        xbps)
            xbps-query -m 2>/dev/null | sort > "$TMP/manual"
            xbps-query -l 2>/dev/null | while read -r _ pv d; do
                n=${pv%-*}
                lic=$(xbps-query -p license "$n" 2>/dev/null | head -1)
                if grep -qx "$pv" "$TMP/manual"; then r=chosen; else r=dependency; fi
                printf '%s\t%s\t%s\t%s\t%s\n' "$n" "${pv##*-}" "${lic:-?}" "$r" "$d"
                grep -oE '/usr/bin/[^<]+|/usr/share/applications/[^<]+\.desktop' "$ROOT/var/db/xbps/.$n-files.plist" 2>/dev/null \
                    | awk -v n="$n" '{print n "\t" $0}' >> "$TMP/files"
            done > "$TMP/pkgs" ;;
        dnf|zypper)   # one rpm database under both; dnf keeps who asked for a package, zypper does not
            if [ "$PM" = dnf ]; then dnf -q repoquery --userinstalled --qf '%{name}\n' 2>/dev/null | sort > "$TMP/manual"; else : > "$TMP/manual"; fi
            rpm -qa --qf '%{NAME}\t%{VERSION}-%{RELEASE}\t%{LICENSE}\t?\t%{SUMMARY}\n' 2>/dev/null | while IFS='	' read -r n v l _ d; do
                if grep -qx "$n" "$TMP/manual"; then r=chosen; elif [ "$PM" = dnf ]; then r=dependency; else r='?'; fi
                printf '%s\t%s\t%s\t%s\t%s\n' "$n" "$v" "${l:-?}" "$r" "$d"
                rpm -ql "$n" 2>/dev/null | grep -E '^/usr/bin/[^/]+$|/applications/[^/]+\.desktop$' | sed "s/^/$n\t/" >> "$TMP/files"
            done > "$TMP/pkgs" ;;
        brew)
            brew info --json=v2 --installed 2>/dev/null | jq -r '
                (.formulae[] | [.name, (.installed[0].version // .versions.stable // "?"), (.license // "?"),
                    (if (.installed[0].installed_on_request // false) then "chosen" else "dependency" end), (.desc // "")] | @tsv),
                (.casks[] | [.token, (.installed // .version // "?"), "?", "chosen", (.desc // "")] | @tsv)' > "$TMP/pkgs" 2>/dev/null
            prefix=$(brew --prefix 2>/dev/null)
            while IFS='	' read -r n _ _ _ _; do
                for b in "$prefix/opt/$n/bin"/*; do [ -x "$b" ] && printf '%s\t/usr/bin/%s\n' "$n" "${b##*/}"; done
            done < "$TMP/pkgs" >> "$TMP/files" 2>/dev/null ;;
        *) : > "$TMP/pkgs" ;;
    esac
    # kind, commands and entries per package
    awk -F'\t' '
        FILENAME == ARGV[1] { ent[$2] = $1 "=" $5; next }                         # entries: file -> NAME=Categories
        FILENAME == files { if ($2 ~ /\.desktop$/) { if ($2 in ent) e[$1] = e[$1] " " ent[$2] }
                            else { sub(".*/", "", $2); c[$1] = c[$1] " " $2 } ; next }
        { n = $1; cmds = substr(c[n], 2); ents = substr(e[n], 2)
          k = (ents != "") ? "app" : (cmds != "") ? "tool" : "part"
          printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", k, n, $2, $3, $4, $5, cmds, ents }' \
        "$TMP/entries" files="$TMP/files" "$TMP/files" "$TMP/pkgs" | sort -t'	' -k2,2 > "$TMP/sbom"
}
sbom_json() {   # the CycloneDX 1.5 document, from $TMP/sbom, to stdout
    _pm=${PM:-none}; _os=${DISTRO:-$(printf '%s' "$OS" | tr 'A-Z' 'a-z')}
    jq -R -s --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg host "$(short_host)" --arg pm "$_pm" --arg os "$_os" --arg ver "$(sed -n 's/^## v//p' "$REPO/CHANGELOG.md" | head -1)" '
        split("\n") | map(select(length > 0) | split("\t")) |
        {bomFormat: "CycloneDX", specVersion: "1.5", version: 1,
         metadata: {timestamp: $ts, tools: [{name: "spark-shell", version: $ver}],
                    component: {type: "operating-system", name: $host, description: ("this machine, as " + $pm + " declares it")}},
         components: map({
            type: (if .[0] == "app" then "application" else "library" end),
            name: .[1], version: .[2], description: .[5],
            licenses: (if .[3] == "" or .[3] == "?" then [] else [{license: {name: .[3]}}] end),
            purl: ("pkg:" + $pm + "/" + $os + "/" + .[1] + "@" + .[2]),
            properties: ([{name: "spark-shell:kind", value: .[0]}, {name: "spark-shell:reason", value: .[4]}]
                         + (if .[6] != "" then [{name: "spark-shell:commands", value: .[6]}] else [] end)
                         + (if .[7] != "" then [{name: "spark-shell:entries", value: .[7]}] else [] end))})}' "$TMP/sbom"
}
cmd_sbom() {   # sbom [apps|tools|parts|NAME] [--json]
    config_load
    json=0; pick=''
    for a in "$@"; do case $a in --json) json=1 ;; -*) ;; *) pick=$a ;; esac; done
    command -v jq >/dev/null 2>&1 || { echo "spark-shell sbom: jq is not installed (spark-shell on)"; return 1; }
    sbom_collect
    [ -s "$TMP/sbom" ] || { echo "spark-shell sbom: no package manager here that this repo knows (pacman, apt, xbps, brew)"; return 1; }
    if [ "$json" = 1 ]; then
        mkdir_private "$(dirname "$SBOM_JSON")"
        sbom_json > "$SBOM_JSON"
        echo "$SBOM_JSON -- CycloneDX 1.5, $(wc -l < "$TMP/sbom" | tr -d ' ') components"
        return 0
    fi
    case $pick in
        ''|apps|tools|parts)
            k=${pick%s}
            awk -F'\t' -v k="$k" '$1 == k || k == "" {printf "%-5s %-24s %-14s %-22s %s\n", $1, $2, substr($3, 1, 14), substr($4, 1, 22), $6}' "$TMP/sbom"
            a=$(grep -c '^app	' "$TMP/sbom" || true); t=$(grep -c '^tool	' "$TMP/sbom" || true); p=$(grep -c '^part	' "$TMP/sbom" || true)
            echo "$a apps, $t tools, $p parts -- an app is a package with a desktop entry (spark-shell apps chooses the allowed apps)" ;;
        *)
            line=$(awk -F'\t' -v n="$pick" '$2 == n' "$TMP/sbom")
            [ -n "$line" ] || { echo "spark-shell sbom: no package named $pick"; return 1; }
            printf '%s\n' "$line" | awk -F'\t' '{printf "%s  %s %s\n  %s\n  licence   %s\n  reason    %s\n  commands  %s\n  entries   %s\n", $1, $2, $3, $6, $4, $5, ($7 == "" ? "-" : $7), ($8 == "" ? "-" : $8)}' ;;
    esac
}

