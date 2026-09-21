#!/bin/sh
# spark-shell tests -- a throwaway HOME, no network, no packages: the
# package row is forced to `todo` by an unknown distro fixture, and the
# pinned rows are satisfied by stubs, so `on` exercises the render and
# link machinery only. Run: sh tests/shell_test.sh
# With SPARK=/path/to/spark's clone, section 11 renders its palettes too.
set -eu
REPO=$(cd "$(dirname "$0")/.." && pwd)
pass=0; fail=0
ok() { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s   %s\n' "$1" "${2:-}"; }
tab=$(printf '\t')
plain() {   # plain FILE -- no hex colour, no byte outside ASCII
    ! grep -Eq '#[0-9a-fA-F]{6}' "$1" && ! LC_ALL=C grep -q "[^ -~${tab}]" "$1"
}

fresh() {   # a new throwaway HOME with the stubs in place
    H=$(mktemp -d)
    export HOME=$H XDG_CONFIG_HOME=$H/.config XDG_STATE_HOME=$H/.local/state XDG_DATA_HOME=$H/.local/share
    mkdir -p "$H/.local/bin" "$H/.config/spark"
    printf '#!/bin/sh\necho starship 0.0-stub\n' > "$H/.local/bin/starship"
    chmod +x "$H/.local/bin/starship"
    printf 'ID=fixture\n' > "$H/os-release"
    export SPARK_OS_RELEASE=$H/os-release
    # the root renders (the login box) land under a throwaway root, never
    # in this machine's /etc; systemctl is whatever PATH has (a stub, 15)
    export SPARK_SHELL_ROOT=$H/root
    PATH=$H/.local/bin:$PATH
}

theme_fixture() {   # theme_fixture ACCENT [MUTED] -- a 21-key theme.env over the VGA sixteen
    {
        printf 'THEME_BG=#000000\nTHEME_FG=#aaaaaa\nTHEME_ACCENT=%s\nTHEME_MUTED=%s\nTHEME_BTOP=TTY\n' "$1" "${2:-#555555}"
        i=0
        for c in 000000 aa0000 00aa00 aa5500 0000aa aa00aa 00aaaa aaaaaa 555555 ff5555 55ff55 ffff55 5555ff ff55ff 55ffff ffffff; do
            printf 'THEME_ANSI_%d=#%s\n' "$i" "$c"; i=$((i + 1))
        done
    } > "$HOME/.config/spark/theme.env"
}
RENDERS=".tmux.conf .config/btop/btop.conf .config/starship.toml .config/spark-shell/sgr.sh"

SH=$REPO/spark-shell

# --- 1. dry-run: rows, nothing touched -----------------------------------
fresh
out=$(sh "$SH" on --dry-run)
printf '%s\n' "$out" | grep -q '^would  rc' && ok "dry-run: would link the rc files" || bad "dry-run rc rows" "$out"
printf '%s\n' "$out" | grep -q '^would  look' && ok "dry-run: would render the look" || bad "dry-run look rows" "$out"
printf '%s\n' "$out" | grep -q '^todo   packages' && ok "dry-run: an unknown family is a todo, not a guess" || bad "dry-run packages row" "$out"
printf '%s\n' "$out" | grep -q ' to do$' && ok "dry-run ends with the count" || bad "dry-run count" "$out"
printf '%s\n' "$out" | grep -q 'font' && bad "a font row survives" "$out" || ok "dry-run: no font row"
[ ! -e "$HOME/.tmux.conf" ] && ok "dry-run touched nothing" || bad "dry-run wrote files"

# --- 2. on: links, renders, idempotence, the plain look ------------------
theme_fixture '#ff5555'
printf 'yours\n' > "$HOME/.bashrc"     # a pre-existing rc file of the user's
out=$(sh "$SH" on)
case $(uname -s) in Darwin) rc1=.zshrc ;; *) rc1=.bashrc ;; esac
[ -L "$HOME/$rc1" ] && ok "on: $rc1 is spark-shell's link" || bad "rc link" "$(ls -la "$HOME")"
if [ "$rc1" = .bashrc ]; then
    [ -f "$HOME/.bashrc.bak" ] && grep -q yours "$HOME/.bashrc.bak" && ok "on: yours went to .bak" || bad "rc backup"
fi
[ -f "$HOME/.tmux.conf" ] && grep -q 'fg=colour9,bold' "$HOME/.tmux.conf" && ok "on: the accent is its palette slot (colour9)" || bad "tmux render" "$(grep -n colour "$HOME/.tmux.conf" 2>&1 | head -3)"
grep -q '@[A-Z_0-9]*@' "$HOME/.tmux.conf" && bad "unrendered placeholder left" || ok "on: no placeholder left"
for rel in $RENDERS; do
    [ -f "$HOME/$rel" ] || { bad "on: $rel not rendered"; continue; }
    plain "$HOME/$rel" && ok "on: $rel is plain (no hex, ASCII)" || bad "on: $rel not plain" "$(grep -nE '#[0-9a-fA-F]{6}' "$HOME/$rel" | head -2)"
done
grep -q 'SPARK_ASCII=1 spark bar line' "$HOME/.tmux.conf" && ok "on: the bar is asked in ASCII" || bad "bar ascii"
[ ! -e "$HOME/.gitconfig" ] && ok "on: no identity given, no .gitconfig written (never a guess)" || bad "gitconfig guessed" "$(cat "$HOME/.gitconfig")"
grep -q ':Tc' "$HOME/.tmux.conf" && bad "tmux advertises truecolor for the look" || ok "on: no Tc override (the look is slots)"
grep -q 'terminal-features ",foot\*:RGB"' "$HOME/.tmux.conf" && ok "on: content passes through in RGB under foot" || bad "foot RGB passthrough" "$(grep -n terminal- "$HOME/.tmux.conf")"
grep -q 'client-attached' "$HOME/.tmux.conf" && bad "the console hook survives" || ok "on: no console hook (the slots need none)"
grep -q '^force_tty = True' "$HOME/.config/btop/btop.conf" && grep -q '^graph_symbol = "tty"' "$HOME/.config/btop/btop.conf" \
    && ok "on: btop in tty mode, tty graphs" || bad "btop tty mode"
[ ! -e "$HOME/.config/micro" ] && ok "on: no editor configured (nothing under ~/.config/micro)" || bad "micro touched" "$(ls -R "$HOME/.config/micro")"
grep -q "EDITOR\|editor = " "$REPO/templates/linux/.bashrc" "$REPO/templates/macos/.zshrc" "$REPO/templates/.gitconfig" && bad "an editor is still configured" || ok "templates: no EDITOR, no git editor"
grep -q 'style = "bold bright-red"' "$HOME/.config/starship.toml" && ok "on: starship's accent is its colour word (bright-red)" || bad "starship accent"
sgr=$HOME/.config/spark-shell/sgr.sh
grep -q "SPARK_ACCENT_SGR='1;91'" "$sgr" && grep -q "SPARK_MUTED_SGR='90'" "$sgr" && grep -q "SPARK_WARN_SGR='1;31'" "$sgr" \
    && ok "on: sgr.sh exports the slots as SGR (accent 1;91, muted 90, warn 1;31)" || bad "sgr render" "$(cat "$sgr" 2>&1)"
grep -q '^# rendered by spark-shell' "$sgr" && ok "on: sgr.sh carries the marker" || bad "sgr marker"
# shellcheck disable=SC1090   # the render just written, on purpose
(. "$sgr" && [ "$SPARK_ACCENT_SGR" = '1;91' ] && [ "$SPARK_MUTED_SGR" = 90 ] && [ "$SPARK_WARN_SGR" = '1;31' ]) \
    && ok "on: sgr.sh sources in sh and sets the three" || bad "sgr source"
grep -q 'custom' "$HOME/.config/starship.toml" && bad "starship carries a segment of its own" || ok "on: starship's prompt is starship's alone (no spark segment)"
out=$(sh "$SH" on --dry-run)
printf '%s\n' "$out" | grep -q '^Nothing to do$' && ok "second run: Nothing to do" || bad "idempotence" "$out"

# --- 3. apply follows the palette ----------------------------------------
theme_fixture '#ee8800'
sh "$SH" apply >/dev/null
grep -q 'fg=colour3,bold' "$HOME/.tmux.conf" && ok "apply: a new accent lands as its nearest slot (colour3)" || bad "apply rerender" "$(grep -n colour "$HOME/.tmux.conf" | head -2)"
out=$(sh "$SH" check || true)
printf '%s\n' "$out" | grep -q '^ok     look' && ok "check: the look matches the palette" || bad "check look row" "$out"
printf '%s\n' "$out" | grep -q 'font' && bad "check: a font row survives" "$out" || ok "check: no font row"
grep -q "SPARK_ACCENT_SGR='1;33'" "$HOME/.config/spark-shell/sgr.sh" && ok "apply: the new accent lands in sgr.sh (1;33)" || bad "apply sgr" "$(cat "$HOME/.config/spark-shell/sgr.sh")"
st=$(sh "$SH" status); printf '%s\n' "$st" | grep -q 'accent colour3, muted colour8 (SGR 1;33 / 90)' && ok "status: the theme row names the slots and the SGR pair" || bad "status slots" "$(printf '%s\n' "$st" | grep theme)"

# --- 4. the prompt choices ------------------------------------------------
mkdir -p "$HOME/.config/spark-shell"
printf 'PROMPT=plain\n' > "$HOME/.config/spark-shell/config"
rm -f "$HOME/.config/starship.toml"
sh "$SH" apply >/dev/null
[ ! -e "$HOME/.config/starship.toml" ] && ok "PROMPT=plain renders no starship.toml" || bad "plain prompt"
printf 'PROMPT=starship\nPROMPT_STYLE=full\n' > "$HOME/.config/spark-shell/config"
sh "$SH" apply >/dev/null
[ -f "$HOME/.config/starship.toml" ] && grep -q 'style = "bold yellow"' "$HOME/.config/starship.toml" \
    && plain "$HOME/.config/starship.toml" && ok "PROMPT_STYLE=full renders the full style, plain" || bad "full style"

# --- 5. off hands back ----------------------------------------------------
out=$(sh "$SH" off)
if [ "$rc1" = .bashrc ]; then
    [ ! -L "$HOME/.bashrc" ] && grep -q yours "$HOME/.bashrc" && ok "off: the rc file came back from .bak" || bad "rc restore" "$(ls -la "$HOME")"
fi
[ ! -e "$HOME/.tmux.conf" ] && ok "off: a render with no .bak is removed, never a husk" || bad "render removal"
[ ! -e "$HOME/.config/spark-shell/sgr.sh" ] && ok "off: sgr.sh is gone (the prompt goes plain)" || bad "sgr removal"
printf '%s\n' "$out" | grep -q 'packages stay installed' && ok "off: packages stay, said so" || bad "off closing" "$out"

# --- 6. adoption: a file spark's old layer rendered is ours ---------------
fresh
theme_fixture '#5555ff'
printf '# rendered by spark install.sh from templates/.tmux.conf\nold\n' > "$HOME/.tmux.conf"
sh "$SH" on >/dev/null
grep -q 'fg=colour12,bold' "$HOME/.tmux.conf" && [ ! -e "$HOME/.tmux.conf.bak" ] && ok "adoption: an old spark render is re-rendered, no .bak" || bad "adoption"

# --- 7. config seeded from site.env once ----------------------------------
fresh
printf 'SITE_PROMPT=starship\nSITE_PROMPT_STYLE=full\nSITE_GIT_NAME=Test Person\n' > "$HOME/.config/spark/site.env"
sh "$SH" status >/dev/null
grep -q 'PROMPT_STYLE=full' "$HOME/.config/spark-shell/config" && grep -q 'GIT_NAME=Test Person' "$HOME/.config/spark-shell/config" \
    && ok "first run seeds the config from site.env" || bad "seeding" "$(cat "$HOME/.config/spark-shell/config" 2>/dev/null)"

# --- 8. invoked through a symlink (~/.local/bin): the repo still found --
fresh
theme_fixture '#ff55ff'
ln -s "$SH" "$H/.local/bin/spark-shell"
sh -c '"$0" on' "$H/.local/bin/spark-shell" >/dev/null 2>&1 || true
[ -f "$HOME/.tmux.conf" ] && grep -q 'fg=colour13,bold' "$HOME/.tmux.conf" \
    && ok "a symlinked spark-shell still finds its templates" || bad "symlink invocation" "$(ls -la "$HOME" | head -4)"
case $(uname -s) in Darwin) r8=.zshrc ;; *) r8=.bashrc ;; esac
[ -L "$HOME/$r8" ] && [ -e "$HOME/$r8" ] && ok "the rc link resolves (no dangling target)" || bad "rc link dangles" "$(readlink "$HOME/$r8" 2>&1)"

# --- 9. no theme.env: the colour words, each its own slot -----------------
fresh
sh "$SH" on >/dev/null
grep -q 'fg=colour4,bold' "$HOME/.tmux.conf" && grep -q 'pane-border-style "fg=colour7"' "$HOME/.tmux.conf" \
    && ok "no theme.env: accent blue (colour4), muted white (colour7)" || bad "name defaults" "$(grep -n colour "$HOME/.tmux.conf" | head -3)"
grep -q "SPARK_ACCENT_SGR='1;34'" "$HOME/.config/spark-shell/sgr.sh" && grep -q "SPARK_MUTED_SGR='37'" "$HOME/.config/spark-shell/sgr.sh" \
    && ok "no theme.env: sgr.sh says blue (1;34) and white (37)" || bad "sgr defaults" "$(cat "$HOME/.config/spark-shell/sgr.sh")"
st=$(sh "$SH" status); printf '%s\n' "$st" | grep -q "none: the terminal's own sixteen; accent colour4, muted colour7 (SGR 1;34 / 37)" && ok "status: no theme.env, the slots still named" || bad "status none" "$(printf '%s\n' "$st" | grep theme)"

# --- 10. the templates themselves: no truecolor flag, ASCII fzf ----------
grep -q MICRO_TRUECOLOR "$REPO/templates/linux/.bashrc" "$REPO/templates/macos/.zshrc" && bad "MICRO_TRUECOLOR still exported" || ok "rc files: no MICRO_TRUECOLOR"
grep -q -- '--no-unicode' "$REPO/templates/linux/.bashrc" && grep -q -- '--no-unicode' "$REPO/templates/macos/.zshrc" && ok "rc files: fzf asked for ASCII" || bad "fzf opts"
grep -rEq '#[0-9a-fA-F]{6}' "$REPO/templates" && bad "a template names a hex colour" "$(grep -rnE '#[0-9a-fA-F]{6}' "$REPO/templates" | head -2)" || ok "templates: no hex colour anywhere"
for rc in linux/.bashrc macos/.zshrc; do
    grep -q 'spark-shell/sgr.sh' "$REPO/templates/$rc" && ok "rc files: $rc sources spark-shell/sgr.sh" || bad "$rc: no sgr.sh"
    # the order: starship's init, then sgr.sh, then spark's hook line, then zoxide
    l_st=$(grep -n 'starship init' "$REPO/templates/$rc" | head -1 | cut -d: -f1)
    l_sgr=$(grep -n '^[^#]*spark-shell/sgr.sh' "$REPO/templates/$rc" | head -1 | cut -d: -f1)
    l_hook=$(grep -n '^[^#]*config/spark/hook\.' "$REPO/templates/$rc" | head -1 | cut -d: -f1)
    l_zo=$(grep -n 'zoxide init' "$REPO/templates/$rc" | head -1 | cut -d: -f1)
    [ "$l_st" -lt "$l_sgr" ] && [ "$l_sgr" -lt "$l_hook" ] && [ "$l_hook" -lt "$l_zo" ] \
        && ok "rc files: $rc keeps the order (starship, sgr.sh, spark's hook, zoxide)" || bad "$rc order" "starship $l_st sgr $l_sgr hook $l_hook zoxide $l_zo"
done
for t in minimal full; do
    st_t=$REPO/templates/.config/starship.toml.$t
    grep -q 'custom' "$st_t" && bad "starship $t: a segment of spark's" || ok "starship $t: no spark segment on the prompt"
done

# --- 11. the git identity: yours to give, never guessed, never overwritten
fresh
mkdir -p "$HOME/.config/spark-shell"
printf 'GIT_NAME=Test Person\nGIT_EMAIL=you@example.com\n' > "$HOME/.config/spark-shell/config"
sh "$SH" on >/dev/null
grep -q 'name = Test Person' "$HOME/.gitconfig" && grep -q 'email = you@example.com' "$HOME/.gitconfig" && plain "$HOME/.gitconfig" \
    && ok "identity given: .gitconfig rendered with it" || bad "gitconfig render" "$(cat "$HOME/.gitconfig" 2>&1)"
st=$(sh "$SH" status); printf '%s\n' "$st" | grep -q 'rendered: Test Person <you@example.com>' && ok "status: the git row names the identity" || bad "status git row" "$(printf '%s\n' "$st" | grep git)"
out=$(sh "$SH" check || true)
printf '%s\n' "$out" | grep -q '^ok     look' && ok "check: a rendered .gitconfig is part of the look" || bad "check gitconfig" "$out"
sh "$SH" off >/dev/null
[ ! -e "$HOME/.gitconfig" ] && ok "off: the rendered .gitconfig is gone (no .bak: there was none before)" || bad "gitconfig off"
fresh
mkdir -p "$HOME/.config/spark-shell"
printf 'GIT_NAME=Test Person\nGIT_EMAIL=you@example.com\n' > "$HOME/.config/spark-shell/config"
printf '[user]\n\tname = Someone Else\n' > "$HOME/.gitconfig"
sh "$SH" on >/dev/null
grep -q 'Someone Else' "$HOME/.gitconfig" && [ ! -e "$HOME/.gitconfig.bak" ] && ok "a .gitconfig of yours is never touched, even with an identity in the config" || bad "gitconfig yours" "$(ls -la "$HOME")"
st=$(sh "$SH" status); printf '%s\n' "$st" | grep -q 'yours, left alone' && ok "status: the git row says yours" || bad "status yours" "$(printf '%s\n' "$st" | grep git)"
out=$(sh "$SH" check || true)
printf '%s\n' "$out" | grep -q '^ok     look' && ok "check: your .gitconfig is not stale look" || bad "check yours" "$out"

# --- 12. v0.2's micro look is handed back once ---------------------------
fresh
mkdir -p "$HOME/.config/micro/colorschemes"
printf '# spark.micro -- rendered by spark-shell\ncolor-link default "default,default"\n' > "$HOME/.config/micro/colorschemes/spark.micro"
printf '{\n    "colorscheme": "spark",\n    "softwrap": true\n}\n' > "$HOME/.config/micro/settings.json"
sh "$SH" on >/dev/null
[ ! -e "$HOME/.config/micro/colorschemes/spark.micro" ] && ok "migration: the v0.2 spark.micro is removed" || bad "spark.micro stays"
grep -q softwrap "$HOME/.config/micro/settings.json" && ! grep -q colorscheme "$HOME/.config/micro/settings.json" \
    && ok "migration: the colorscheme key is dropped, the rest of settings.json is micro's" || bad "settings.json" "$(cat "$HOME/.config/micro/settings.json")"
printf 'mine\n' > "$HOME/.config/micro/colorschemes/spark.micro"
sh "$SH" apply >/dev/null
grep -q mine "$HOME/.config/micro/colorschemes/spark.micro" && ok "a spark.micro of yours is never touched" || bad "yours removed"

# --- 13. spark's own palettes, when its clone is at hand -------------------
if [ -n "${SPARK:-}" ] && ls "$SPARK"/themes/*.env >/dev/null 2>&1; then
    for env in "$SPARK"/themes/*.env; do
        name=${env##*/}; name=${name%.env}
        fresh
        cp "$env" "$HOME/.config/spark/theme.env"
        sh "$SH" on >/dev/null
        st=$(sh "$SH" status)
        allplain=1
        for rel in $RENDERS; do plain "$HOME/$rel" || allplain=0; done
        [ "$allplain" = 1 ] && grep -Eq 'fg=colour(1[0-5]|[0-9]),bold' "$HOME/.tmux.conf" \
            && ok "$name: renders plain, $(printf '%s\n' "$st" | sed -n 's/.*read: \(accent colour[0-9]*, muted colour[0-9]*\).*/\1/p')" \
            || bad "$name: not plain or no accent slot" "$(grep -rnE '#[0-9a-fA-F]{6}' "$HOME/.tmux.conf" "$HOME/.config" | head -2)"
    done
else
    printf '  NOTICE: SPARK unset -- spark'"'"'s palettes not exercised (SPARK=/path/to/spark sh tests/shell_test.sh)\n'
fi

# --- 14. the desktop: sway and foot, asked for by DESKTOP=sway ---------
# stubs stand in for sway, swaymsg and foot; the Linux half is guarded by
# uname (macOS has its own desktop) and runs in CI's linux and arch jobs
desktop_stubs() {
    for t in sway swaymsg foot; do
        printf '#!/bin/sh\necho "%s-stub $*" >&2\n' "$t" > "$H/.local/bin/$t"; chmod +x "$H/.local/bin/$t"
    done
}
fresh
desktop_stubs
theme_fixture '#ff5555'
out=$(sh "$SH" on --dry-run)
[ ! -e "$HOME/.config/foot" ] && [ ! -e "$HOME/.config/sway" ] && ok "default: DESKTOP=none renders no foot.ini, no sway config" || bad "desktop rendered by default" "$(ls -R "$HOME/.config")"
printf '%s\n' "$out" | grep -q 'font' && bad "default dry-run names a font" "$out" || ok "default dry-run: no font word"
sh "$SH" on >/dev/null
st=$(sh "$SH" status); printf '%s\n' "$st" | grep -q '^  desk  none' && ok "status: the desk row says none" || bad "status desk none" "$(printf '%s\n' "$st" | grep desk)"
out=$(sh "$SH" check || true)
printf '%s\n' "$out" | grep -q '^ok     desktop      na (' && ok "check: desktop is na by default" || bad "check desktop na" "$out"
printf '%s\n' "$out" | grep -q 'font' && bad "check names a font" "$out" || ok "check: no font word"
out=$(DESKTOP=none sh "$SH" desktop 2>&1 || true)
printf '%s\n' "$out" | grep -q '^spark-shell desktop: ' && ok "desktop: refused with DESKTOP=none, one line" || bad "desktop none" "$out"
printf 'DESKTOP=gnome\n' > "$HOME/.config/spark-shell/config"
sh "$SH" status >/dev/null 2>&1 && bad "DESKTOP=gnome accepted" || ok "config: DESKTOP=gnome is refused"
printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"
if [ "$(uname -s)" = Darwin ]; then
    out=$(sh "$SH" on --dry-run)
    printf '%s\n' "$out" | grep -q '^skip   desktop      na: macOS' && ok "macOS: DESKTOP=sway is na, said in a row" || bad "macOS na row" "$out"
    sh "$SH" apply >/dev/null
    [ ! -e "$HOME/.config/sway" ] && ok "macOS: nothing rendered for the desktop" || bad "macOS rendered sway"
    out=$(sh "$SH" desktop 2>&1 || true)
    printf '%s\n' "$out" | grep -q '^spark-shell desktop: na' && ok "macOS: desktop refuses, na" || bad "macOS desktop" "$out"
    out=$(sh "$SH" check || true)
    printf '%s\n' "$out" | grep -q '^ok     desktop      na (macOS)' && ok "macOS: check says na" || bad "macOS check" "$out"
else
    out=$(sh "$SH" on --dry-run)
    printf '%s\n' "$out" | grep -q '^would  look .*foot/foot.ini' && printf '%s\n' "$out" | grep -q '^would  look .*sway/config' \
        && ok "DESKTOP=sway: dry-run would render foot.ini and sway/config" || bad "sway dry-run" "$out"
    sh "$SH" on >/dev/null
    foot=$HOME/.config/foot/foot.ini; sway=$HOME/.config/sway/config
    [ -f "$foot" ] && [ -f "$sway" ] && ok "DESKTOP=sway: both rendered" || bad "sway renders missing" "$(ls -R "$HOME/.config")"
    grep -q '^background=000000$' "$foot" && grep -q '^foreground=aaaaaa$' "$foot" && grep -q '^regular1=aa0000$' "$foot" && grep -q '^bright1=ff5555$' "$foot" \
        && ok "foot.ini: the palette's own hex (background 000000, regular1 aa0000, bright1 ff5555)" || bad "foot colours" "$(grep -n '=' "$foot" | head -8)"
    grep -q '^font=DejaVu Sans Mono:size=12$' "$foot" && ok "foot.ini: the default FONT line" || bad "foot font line" "$(grep -n '^font' "$foot")"
    grep -q '^\[colors-dark\]$' "$foot" && ! grep -q '^\[colors\]$' "$foot" && ok "foot.ini: one colour section, [colors-dark] (a foot with no version = 1.26+)" || bad "foot sections" "$(grep -n '^\[' "$foot")"
    printf '#!/bin/sh\n[ "$1" = --version ] && echo "foot version: 1.21.0 (Debian)"\n' > "$HOME/.local/bin/foot"
    sh "$SH" apply >/dev/null
    grep -q '^\[colors\]$' "$foot" && ! grep -q '^\[colors-dark\]$' "$foot" && ok "foot.ini: foot 1.21 gets [colors] alone" || bad "foot 1.21 section" "$(grep -n '^\[' "$foot")"
    printf '#!/bin/sh\n[ "$1" = --version ] && echo "foot version: 1.28.0 (Arch)"\n' > "$HOME/.local/bin/foot"
    sh "$SH" apply >/dev/null
    grep -q '^\[colors-dark\]$' "$foot" && ! grep -q '^\[colors\]$' "$foot" && ok "foot.ini: foot 1.28 gets [colors-dark] alone" || bad "foot 1.28 section" "$(grep -n '^\[' "$foot")"
    grep -q '^client.focused *#ff5555 ' "$sway" && ok "sway: client.focused takes the accent's hex (#ff5555)" || bad "sway focused" "$(grep -n client "$sway")"
    grep -q '^output \* bg #000000 solid_color$' "$sway" && ok "sway: the background is the palette's bg (#000000)" || bad "sway bg" "$(grep -n output "$sway")"
    grep -q '@[A-Z_0-9]*@' "$foot" "$sway" && bad "a desktop render keeps a placeholder" "$(grep -n '@[A-Z_0-9]*@' "$foot" "$sway" | head -2)" || ok "desktop renders: no placeholder left"
    head -1 "$foot" | grep -q '^# rendered by spark-shell' && head -1 "$sway" | grep -q '^# rendered by spark-shell' && ok "desktop renders: both marked" || bad "desktop markers"
    LC_ALL=C grep -q "[^ -~${tab}]" "$foot" "$sway" && bad "a desktop render is not ASCII" || ok "desktop renders: ASCII"
    printf 'DESKTOP=sway\nFONT=Test Mono:size=14\n' > "$HOME/.config/spark-shell/config"
    sh "$SH" apply >/dev/null
    grep -q '^font=Test Mono:size=14$' "$foot" && ok "FONT in the config lands in foot.ini verbatim" || bad "FONT override" "$(grep -n '^font' "$foot")"
    printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"
    sh "$SH" apply >/dev/null
    st=$(sh "$SH" status); printf '%s\n' "$st" | grep -q '^  desk  sway .*sway: rendered' && ok "status: the desk row says sway, rendered" || bad "status desk sway" "$(printf '%s\n' "$st" | grep desk)"
    out=$(sh "$SH" check || true)
    printf '%s\n' "$out" | grep -q '^ok     desktop      sway and foot' && ok "check: desktop ok with the stubs and fresh renders" || bad "check desktop ok" "$out"
    printf '%s\n' "$out" | grep -q 'font' && bad "check names a font" "$out" || ok "check: no font word with DESKTOP=sway"
    out=$(env -u XDG_VTNR -u WAYLAND_DISPLAY sh "$SH" desktop 2>&1 || true)
    printf '%s\n' "$out" | grep -q 'needs a console login: ssh has no seat' && ok "desktop: refused without XDG_VTNR (ssh has no seat)" || bad "desktop no seat" "$out"
    out=$(env -u XDG_VTNR XDG_VTNR=1 WAYLAND_DISPLAY=wayland-1 sh "$SH" desktop 2>&1 || true)
    printf '%s\n' "$out" | grep -q 'already inside' && ok "desktop: refused inside a desktop (WAYLAND_DISPLAY set)" || bad "desktop inside" "$out"
    out=$(env -u WAYLAND_DISPLAY XDG_VTNR=1 TERM=linux sh "$SH" desktop 2>&1); st=$?
    [ "$st" -eq 0 ] && grep -q 'sway-stub' "$HOME/.local/state/spark-shell/sway.log" && printf '%s' "$out" | od -c | grep -q '033   \[   ?   2   5   h' \
        && ok "desktop: runs sway as a child, its stderr in sway.log, the cursor back on TERM=linux" || bad "desktop run" "st=$st out=$out log=$(cat "$HOME/.local/state/spark-shell/sway.log" 2>&1)"
    out=$(SWAYSOCK=/nonexistent sh "$SH" apply)
    printf '%s\n' "$out" | grep -q '^ok     sway         reloaded' && ok "apply: swaymsg reload when SWAYSOCK is set" || bad "sway reload" "$out"
    rm -f "$H/.local/bin/sway"
    out=$(sh "$SH" check || true)
    printf '%s\n' "$out" | grep -q '^FAIL   desktop      missing: sway -- spark-shell on' && ok "check: FAIL without sway, the remedy is spark-shell on" || bad "check no sway" "$out"
    out=$(env -u WAYLAND_DISPLAY XDG_VTNR=1 sh "$SH" desktop 2>&1 || true)
    printf '%s\n' "$out" | grep -q 'not installed: sway' && ok "desktop: refused without sway" || bad "desktop no sway" "$out"
    desktop_stubs
    sh "$SH" off >/dev/null
    [ ! -e "$foot" ] && [ ! -e "$sway" ] && ok "off: both desktop renders are gone" || bad "desktop off" "$(ls -R "$HOME/.config")"
    mkdir -p "$HOME/.config/sway"; printf 'mine\n' > "$sway"
    sh "$SH" off >/dev/null
    grep -q mine "$sway" && ok "off: a sway config of yours (no marker) is left alone" || bad "yours removed"
    sh "$SH" on >/dev/null
    [ -f "$sway.bak" ] && grep -q mine "$sway.bak" && grep -q '^# rendered by spark-shell' "$sway" && ok "on: yours moves to .bak, the render takes its place" || bad "sway backup" "$(ls "$HOME/.config/sway")"
    rm -f "$foot"
    out=$(env -u WAYLAND_DISPLAY XDG_VTNR=1 sh "$SH" desktop 2>&1 || true)
    printf '%s\n' "$out" | grep -q 'not rendered (spark-shell apply)' && ok "desktop: refused when a render is missing" || bad "desktop not rendered" "$out"
    # no theme.env: the VGA sixteen, what spark theme none programs
    fresh
    desktop_stubs
    mkdir -p "$HOME/.config/spark-shell"; printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"
    sh "$SH" on >/dev/null
    grep -q '^regular4=0000aa$' "$HOME/.config/foot/foot.ini" && grep -q '^background=000000$' "$HOME/.config/foot/foot.ini" && grep -q '^foreground=aaaaaa$' "$HOME/.config/foot/foot.ini" \
        && ok "no theme.env: foot.ini takes the VGA sixteen (regular4 0000aa, bg 000000, fg aaaaaa)" || bad "vga foot" "$(grep -n '=' "$HOME/.config/foot/foot.ini" | head -6)"
    grep -q '^client.focused *#0000aa ' "$HOME/.config/sway/config" && ok "no theme.env: the accent's hex is its VGA slot (blue, #0000aa)" || bad "vga accent" "$(grep -n client "$HOME/.config/sway/config")"
fi
grep -q '@FONT@' "$REPO/templates/.config/foot/foot.ini" && grep -q 'output \* bg #@HEX_BG@ solid_color' "$REPO/templates/.config/sway/config" \
    && ok "templates: foot.ini and sway/config carry placeholders, the hex lands at render time" || bad "desktop template placeholders"
grep -q '^bar ' "$REPO/templates/.config/sway/config" && bad "sway: a bar block (the tmux line is the bar)" || ok "sway template: no bar, tmux's line is the bar"
grep -q '^xwayland disable$' "$REPO/templates/.config/sway/config" && ok "sway template: xwayland disabled" || bad "sway xwayland"
grep -v '^#' "$REPO/templates/.config/sway/config" | grep -q 'tmux' && bad "sway: a window starts tmux (it runs the login shell)" || ok "sway template: a new foot runs the login shell, never tmux"
grep -q "^exec sh -c '\$term; swaymsg exit'$" "$REPO/templates/.config/sway/config" && ok "sway template: the desktop ends with its first terminal" || bad "sway template: exec line" "$(grep -n '^exec' "$REPO/templates/.config/sway/config")"

# --- 15. the login box: desktop on|off, greetd on tty1 --------------------
# stubs for greetd and tuigreet beside the desktop's; systemctl is a stub
# that logs its arguments and keeps enable/disable state in files. Every
# root path is under SPARK_SHELL_ROOT (fresh), so nothing reaches /etc.
greeter_stubs() {
    for t in greetd tuigreet; do
        printf '#!/bin/sh\necho "%s-stub $*" >&2\n' "$t" > "$H/.local/bin/$t"; chmod +x "$H/.local/bin/$t"
    done
    cat > "$H/.local/bin/systemctl" <<'EOF'
#!/bin/sh
st=${SPARK_SHELL_ROOT:-$HOME/root}/units
mkdir -p "$st"
echo "$*" >> "$st/log"
case $1 in
    enable) touch "$st/$2" ;;
    disable) rm -f "$st/$2" ;;
    is-enabled) if [ -e "$st/$2" ]; then echo enabled; else echo disabled; exit 1; fi ;;
esac
EOF
    chmod +x "$H/.local/bin/systemctl"
    systemctl enable getty@tty1.service     # a box as it comes
}
ROOT_RENDERS="etc/greetd/config.toml etc/greetd/spark-shell/desktop.desktop etc/greetd/spark-shell/console.desktop etc/systemd/system/greetd.service.d/spark-shell.conf"
fresh
desktop_stubs
greeter_stubs
theme_fixture '#ff5555'
mkdir -p "$HOME/.config/spark-shell"
printf 'PROMPT_STYLE=full\nDESKTOP=none\n' > "$HOME/.config/spark-shell/config"
if [ "$(uname -s)" = Darwin ]; then
    st=0; out=$(sh "$SH" desktop on 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$(printf '%s\n' "$out" | wc -l)" -eq 1 ] && printf '%s\n' "$out" | grep -q '^spark-shell desktop: na' \
        && ok "macOS: desktop on refuses, na, one line, exit 1" || bad "macOS desktop on" "st=$st $out"
    grep -q 'DESKTOP=none' "$HOME/.config/spark-shell/config" && [ ! -e "$H/root/etc" ] && ok "macOS: desktop on wrote nothing" || bad "macOS desktop on wrote" "$(cat "$HOME/.config/spark-shell/config")"
else
    out=$(sh "$SH" desktop on --dry-run)
    printf '%s\n' "$out" | grep -q '^would  greeter .*etc/greetd/config.toml' && printf '%s\n' "$out" | grep -q '^would  greeter      enable greetd.service, disable getty@tty1.service' \
        && ok "desktop on --dry-run: would render the root files and switch the units" || bad "greeter dry-run rows" "$out"
    grep -q 'DESKTOP=none' "$HOME/.config/spark-shell/config" && [ ! -e "$H/root/etc" ] && [ ! -e "$H/.config/sway" ] && ok "desktop on --dry-run: wrote nothing (the config kept)" || bad "greeter dry-run wrote" "$(find "$H/root" "$H/.config")"
    printf '%s\n' "$out" | grep -q 'font' && bad "desktop on --dry-run names a font" "$out" || ok "desktop on --dry-run: no font word"
    out=$(sh "$SH" desktop on 2>&1); st=$?
    [ "$st" -eq 0 ] && grep -q '^DESKTOP=sway$' "$HOME/.config/spark-shell/config" && grep -q '^PROMPT_STYLE=full$' "$HOME/.config/spark-shell/config" \
        && [ "$(grep -c '^DESKTOP=' "$HOME/.config/spark-shell/config")" -eq 1 ] \
        && ok "desktop on: DESKTOP=sway written into the config, the other line kept" || bad "desktop on config" "st=$st $(cat "$HOME/.config/spark-shell/config")"
    [ -f "$HOME/.config/foot/foot.ini" ] && [ -f "$HOME/.config/sway/config" ] && ok "desktop on: foot.ini and sway/config rendered" || bad "desktop on user renders" "$out"
    allthere=1; for rel in $ROOT_RENDERS; do [ -f "$H/root/$rel" ] || allthere=0; done
    [ "$allthere" = 1 ] && ok "desktop on: the four root files rendered under the root" || bad "root renders" "$(find "$H/root" -type f)"
    conf=$H/root/etc/greetd/config.toml
    head -1 "$conf" | grep -q '^# rendered by spark-shell' && ok "config.toml: the marker is line 1" || bad "config.toml marker" "$(head -1 "$conf")"
    grep -q '^vt = 1$' "$conf" && grep -q '^user = "greeter"$' "$conf" && grep -q -- '--cmd sway ' "$conf" && grep -q -- '--sessions /etc/greetd/spark-shell ' "$conf" \
        && ok "config.toml: vt 1, the greeter user, tuigreet --cmd sway --sessions" || bad "config.toml shape" "$(cat "$conf")"
    grep -q -- "--theme 'border=lightred;" "$conf" && grep -q 'container=black' "$conf" && grep -q 'text=gray' "$conf" && grep -q 'greet=darkgray' "$conf" \
        && ok "config.toml: the palette as ratatui words (border lightred, container black, text gray, greet darkgray)" || bad "config.toml theme" "$(grep -o -- "--theme '[^']*'" "$conf")"
    name=$(hostname -s 2>/dev/null || uname -n | cut -d. -f1)
    grep -q -- "--greeting '$name' " "$conf" && ok "config.toml: the greeting is the machine's short name" || bad "config.toml greeting" "$(grep -o -- "--greeting '[^']*'" "$conf") vs $name"
    grep -q '^Name=desktop$' "$H/root/etc/greetd/spark-shell/desktop.desktop" && grep -q '^Exec=sway$' "$H/root/etc/greetd/spark-shell/desktop.desktop" \
        && grep -q '^Name=console$' "$H/root/etc/greetd/spark-shell/console.desktop" && grep -q '^Exec=bash -l$' "$H/root/etc/greetd/spark-shell/console.desktop" \
        && ok "the two sessions: desktop = sway, console = bash -l" || bad "session files" "$(cat "$H"/root/etc/greetd/spark-shell/*.desktop)"
    grep -q '^After=spark-console.service$' "$H/root/etc/systemd/system/greetd.service.d/spark-shell.conf" && ok "the drop-in orders greetd after spark-console.service" || bad "drop-in" "$(cat "$H/root/etc/systemd/system/greetd.service.d/spark-shell.conf")"
    for rel in $ROOT_RENDERS; do
        if grep -q '@[A-Z_0-9]*@' "$H/root/$rel"; then bad "$rel keeps a placeholder" "$(grep -o '@[A-Z_0-9]*@' "$H/root/$rel" | head -1)"
        elif plain "$H/root/$rel"; then ok "$rel: no placeholder, no hex, ASCII"
        else bad "$rel not plain"; fi
    done
    grep -q '^disable getty@tty1.service$' "$H/root/units/log" && grep -q '^enable greetd.service$' "$H/root/units/log" \
        && ok "desktop on: getty@tty1 disabled, greetd enabled (never started or stopped)" || bad "unit switches" "$(cat "$H/root/units/log")"
    grep -Eq '^(start|stop|restart) ' "$H/root/units/log" && bad "a unit was started or stopped live" "$(cat "$H/root/units/log")" || ok "desktop on: no unit started or stopped live"
    printf '%s\n' "$out" | grep -q '^ok     greeter      greetd on tty1 at the next boot (getty@tty1 until then)' && ok "desktop on: the greeter row says the next boot" || bad "greeter row" "$out"
    st=$(sh "$SH" status); printf '%s\n' "$st" | grep -q '^  desk  sway .*login box: greetd at boot' && ok "status: the desk row names the login box" || bad "status login box" "$(printf '%s\n' "$st" | grep desk)"
    out=$(sh "$SH" check || true)
    printf '%s\n' "$out" | grep -q '^ok     greeter      greetd on tty1 at boot' && ok "check: ok greeter" || bad "check greeter" "$out"
    out=$(sh "$SH" on --dry-run)
    printf '%s\n' "$out" | grep -q '^Nothing to do$' && ok "on --dry-run after desktop on: Nothing to do (the root files match, the units are set)" || bad "greeter idempotence" "$out"
    # a palette change reaches the box through apply
    theme_fixture '#5555ff'
    out=$(sh "$SH" apply)
    printf '%s\n' "$out" | grep -q '^render greeter .*config.toml' && grep -q -- "--theme 'border=lightblue;" "$conf" && ok "apply: a new accent re-renders config.toml (border lightblue)" || bad "apply greeter" "$out"
    printf '%s\n' "$out" | grep -q '^render greeter .*desktop.desktop' && bad "apply re-wrote an unchanged root file" "$out" || ok "apply: an unchanged root file is left alone"
    # the config set by hand + on = desktop on, one path
    rm -rf "$H/root/etc"; rm -f "$H/root/units/greetd.service"; : > "$H/root/units/log"
    sh "$SH" on >/dev/null
    [ -f "$conf" ] && grep -q '^enable greetd.service$' "$H/root/units/log" && ok "DESKTOP=sway by hand + on: the same path (root files, greetd enabled)" || bad "on = desktop on" "$(cat "$H/root/units/log")"
    # check fails when a unit is off or a file is stale, the remedy is desktop on
    rm -f "$H/root/units/greetd.service"
    out=$(sh "$SH" check || true)
    printf '%s\n' "$out" | grep -q '^FAIL   greeter      greetd.service is not enabled -- spark-shell desktop on' && ok "check: FAIL greeter when greetd is not enabled, the remedy is desktop on" || bad "check greetd off" "$out"
    systemctl enable greetd.service
    printf 'edited\n' >> "$conf"
    out=$(sh "$SH" check || true)
    printf '%s\n' "$out" | grep -q '^FAIL   greeter      stale: /etc/greetd/config.toml -- spark-shell desktop on' && ok "check: FAIL greeter when config.toml is stale" || bad "check stale" "$out"
    # desktop off: DESKTOP=none, the renders gone, getty back
    : > "$H/root/units/log"
    out=$(sh "$SH" desktop off)
    grep -q '^DESKTOP=none$' "$HOME/.config/spark-shell/config" && grep -q '^PROMPT_STYLE=full$' "$HOME/.config/spark-shell/config" && ok "desktop off: DESKTOP=none written, the other line kept" || bad "desktop off config" "$(cat "$HOME/.config/spark-shell/config")"
    [ ! -e "$HOME/.config/foot/foot.ini" ] && [ ! -e "$HOME/.config/sway/config" ] && ok "desktop off: the two user renders are gone" || bad "desktop off user renders" "$(ls -R "$HOME/.config")"
    [ ! -e "$conf" ] && [ ! -e "$H/root/etc/greetd/spark-shell" ] && [ ! -e "$H/root/etc/systemd/system/greetd.service.d" ] \
        && ok "desktop off: the root files and the two dirs of ours are gone (/etc/greetd is the package's)" || bad "desktop off root" "$(find "$H/root/etc")"
    grep -q '^disable greetd.service$' "$H/root/units/log" && grep -q '^enable getty@tty1.service$' "$H/root/units/log" && ok "desktop off: greetd disabled, getty@tty1 enabled" || bad "desktop off units" "$(cat "$H/root/units/log")"
    printf '%s\n' "$out" | grep -q '^ok     greeter      getty on tty1 at the next boot' && ok "desktop off: the greeter row says getty at the next boot" || bad "desktop off row" "$out"
    printf '%s\n' "$out" | grep -q 'packages stay installed' && ok "desktop off: packages stay, said so" || bad "desktop off closing" "$out"
    out=$(sh "$SH" desktop off)
    printf '%s\n' "$out" | grep -q '^ok     greeter' && bad "desktop off twice acts twice" "$out" || ok "desktop off twice: nothing to undo, nothing said"
    # a foreign config.toml is kept as .spark-orig and comes back on off
    mkdir -p "$H/root/etc/greetd"; printf '[terminal]\nvt = 1\n[default_session]\ncommand = "agreety --cmd /bin/sh"\nuser = "greeter"\n' > "$conf"
    sh "$SH" desktop on >/dev/null
    [ -f "$conf.spark-orig" ] && grep -q agreety "$conf.spark-orig" && grep -q '^# rendered by spark-shell' "$conf" && ok "desktop on: a config.toml of the package's goes to .spark-orig once" || bad "spark-orig" "$(ls "$H/root/etc/greetd")"
    sh "$SH" apply >/dev/null
    [ -f "$conf.spark-orig" ] && grep -q agreety "$conf.spark-orig" && ok "apply: .spark-orig is never overwritten" || bad "spark-orig twice"
    sh "$SH" off >/dev/null
    [ -f "$conf" ] && grep -q agreety "$conf" && [ ! -e "$conf.spark-orig" ] && ok "off: config.toml is back from .spark-orig" || bad "spark-orig restore" "$(ls "$H/root/etc/greetd"; cat "$conf" 2>&1)"
    [ ! -e "$H/root/etc/greetd/spark-shell" ] && [ ! -e "$H/root/units/greetd.service" ] && [ -e "$H/root/units/getty@tty1.service" ] && ok "off: the whole layer undoes the login box too" || bad "off greeter" "$(find "$H/root")"
    # no theme.env: the colour words -- accent blue, muted white = gray in ratatui's words
    fresh; desktop_stubs; greeter_stubs
    sh "$SH" desktop on >/dev/null
    grep -q -- "--theme 'border=blue;" "$H/root/etc/greetd/config.toml" && grep -q 'greet=gray' "$H/root/etc/greetd/config.toml" && grep -q 'container=black' "$H/root/etc/greetd/config.toml" \
        && ok "no theme.env: border blue, greet gray, container black" || bad "no theme.env greeter" "$(grep -o -- "--theme '[^']*'" "$H/root/etc/greetd/config.toml")"
    out=$(env -u WAYLAND_DISPLAY XDG_VTNR=1 sh "$SH" desktop 2>&1); st=$?
    [ "$st" -eq 0 ] && ok "desktop (start now) still starts sway with the box in place" || bad "desktop start" "$out"
    out=$(sh "$SH" desktop sideways 2>&1 || true)
    printf '%s\n' "$out" | grep -q '^spark-shell desktop: sideways' && ok "desktop: an unknown word is refused in one line" || bad "desktop unknown word" "$out"
    # no sudo to be had (not root, sudo refuses, no tty): a todo row, nothing written
    if [ "$(id -u)" -ne 0 ]; then
        printf '#!/bin/sh\nexit 1\n' > "$H/.local/bin/sudo"; chmod +x "$H/.local/bin/sudo"
        out=$(env -u SPARK_SHELL_ROOT sh "$SH" apply </dev/null 2>&1 || true)
        printf '%s\n' "$out" | grep -q '^todo   greeter .*spark-shell desktop on at a terminal (sudo once)' && ok "no sudo: the root render is a todo row, the shape of the packages row" || bad "no sudo todo" "$out"
        rm -f "$H/.local/bin/sudo"
    fi
fi
grep -q '@ACCENT_TUI@' "$REPO/templates/etc/greetd/config.toml" && grep -q '@NAME@' "$REPO/templates/etc/greetd/config.toml" && ok "templates: config.toml carries the tui and name placeholders" || bad "config.toml template"
grep -rq 'font' "$REPO/templates/etc" && bad "a root template names a font" || ok "templates/etc: no font word"

printf '%s\n' "shell_test: $pass ok, $fail failed"
[ "$fail" -eq 0 ]
