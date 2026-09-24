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
    printf '#!/bin/sh\necho "Yazi 0.0-stub"\n' > "$H/.local/bin/yazi"   # the pin never downloads in a test
    chmod +x "$H/.local/bin/starship" "$H/.local/bin/yazi"
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
RENDERS=".tmux.conf .config/btop/btop.conf .config/starship.toml .config/spark-shell/sgr.sh .config/yazi/theme.toml"

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
grep -q '^cwd = { fg = "bright-red" }$' "$HOME/.config/yazi/theme.toml" && grep -q '^globs = \[\]$' "$HOME/.config/yazi/theme.toml" \
    && ok "on: yazi's look -- the accent word for cwd, no icon glyphs" || bad "yazi look" "$(cat "$HOME/.config/yazi/theme.toml")"
st=$(sh "$SH" status); printf '%s\n' "$st" | grep -q '^  tool  yazi *yes' && ok "status: yazi is a tool" || bad "status yazi" "$st"
ck=$(sh "$SH" check || true); tr_=$(printf '%s\n' "$ck" | grep tools)
case $tr_ in *"btop, yazi"*) ok "check: the tools row names yazi" ;; *missing:*yazi*) bad "check tools: yazi missing with its stub on PATH" "$tr_" ;; *) ok "check: yazi is not among the missing tools (CI has few of them)" ;; esac
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
    l_you=$(grep -n 'config/spark-shell/rc' "$REPO/templates/$rc" | grep -v '^[0-9]*:#' | head -1 | cut -d: -f1)
    [ -n "$l_you" ] && [ "$l_you" -gt "$l_zo" ] && ok "rc files: $rc sources ~/.config/spark-shell/rc (yours) last" || bad "$rc yours" "line $l_you vs zoxide $l_zo"
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
    grep -q "^output \* bg \"$REPO/wallpapers/forge-1920x1080.jpg\" fill\$" "$sway" && grep -q '^gaps inner 8$' "$sway" && grep -q '^alpha=0.85$' "$foot" \
        && ok "sway: the default background is the forge (wallpapers/forge-1920x1080.jpg), gaps, foot translucent" || bad "sway default bg" "$(grep -n 'output\|gaps' "$sway")"
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
    printf '%s\n' "$out" | grep -q '^no kept desks yet' && ok "desktop: inside a desktop (WAYLAND_DISPLAY set) it lists the kept desks, none yet" || bad "desktop inside" "$out"
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

# --- follow: the login hook re-renders the look when theme.env changed
fresh
theme_fixture '#ff5555'
sh "$SH" on >/dev/null
out=$(sh "$SH" follow)
[ -z "$out" ] && ok "follow: nothing to say right after on (the palette was seen)" || bad "follow after on" "$out"
theme_fixture '#ee8800'
out=$(sh "$SH" follow)
printf '%s\n' "$out" | grep -q '^spark-shell: the look followed the palette' && grep -q 'fg=colour3,bold' "$HOME/.tmux.conf" && grep -q "SPARK_ACCENT_SGR='1;33'" "$HOME/.config/spark-shell/sgr.sh" \
    && ok "follow: a changed palette re-renders the look, one line says so" || bad "follow changed" "$out"
out=$(sh "$SH" follow)
[ -z "$out" ] && ok "follow: quiet when the palette did not change since" || bad "follow quiet" "$out"
rm -f "$HOME/.config/spark/theme.env"
out=$(sh "$SH" follow)
printf '%s\n' "$out" | grep -q 'followed' && grep -q 'fg=colour4,bold' "$HOME/.tmux.conf" && ok "follow: theme none (no theme.env) is a change too" || bad "follow none" "$out"
grep -q 'spark-shell follow' "$REPO/templates/linux/.bash_profile" && grep -q 'spark-shell follow' "$REPO/templates/macos/.zprofile" && ok "the login profiles run spark-shell follow" || bad "profiles follow"

# --- the wallpaper: a verb that sets and applies; gaps and a translucent foot
if [ "$(uname -s)" != Darwin ]; then
    fresh; desktop_stubs
    mkdir -p "$HOME/.config/spark-shell"; printf 'DESKTOP=sway\nPROMPT_STYLE=full\n' > "$HOME/.config/spark-shell/config"
    theme_fixture '#ff5555'
    sh "$SH" on >/dev/null
    sway=$HOME/.config/sway/config; foot=$HOME/.config/foot/foot.ini
    out=$(sh "$SH" desktop wallpaper)
    printf '%s\n' "$out" | grep -q "^wallpaper default -- the forge, $REPO/wallpapers/forge-1920x1080.jpg\$" && ok "desktop wallpaper (bare): the default is the forge" || bad "wallpaper bare default" "$out"
    [ -s "$REPO/wallpapers/forge-1920x1080.jpg" ] && [ -s "$REPO/wallpapers/forge-2560x1664.jpg" ] && ok "wallpapers/: the forge in two sizes ships with the repo" || bad "wallpapers missing"
    sh "$SH" desktop wallpaper none >/dev/null
    grep -q '^output \* bg #000000 solid_color$' "$sway" && grep -q '^gaps inner 0$' "$sway" && grep -q '^gaps outer 0$' "$sway" && grep -q '^alpha=1.0$' "$foot" \
        && ok "wallpaper none: the palette's colour, no gaps, foot opaque" || bad "wallpaper none render" "$(grep -n 'bg\|gaps' "$sway"; grep -n alpha "$foot")"
    out=$(sh "$SH" desktop wallpaper)
    printf '%s\n' "$out" | grep -q '^wallpaper none' && ok "desktop wallpaper (bare): says none" || bad "wallpaper bare" "$out"
    sh "$SH" desktop wallpaper default >/dev/null
    grep -q '^WALLPAPER=default$' "$HOME/.config/spark-shell/config" && grep -q "forge-1920x1080.jpg\" fill\$" "$sway" && ok "desktop wallpaper default: the forge again" || bad "wallpaper default" "$(grep -n output "$sway")"
    pic="$HOME/pictures/one two.jpg"; mkdir -p "$HOME/pictures"; printf x > "$pic"
    out=$(sh "$SH" desktop wallpaper "$pic")
    grep -q "^WALLPAPER=$pic\$" "$HOME/.config/spark-shell/config" && grep -q '^PROMPT_STYLE=full$' "$HOME/.config/spark-shell/config" \
        && ok "desktop wallpaper PATH: WALLPAPER in the config, the other lines kept" || bad "wallpaper config" "$(cat "$HOME/.config/spark-shell/config")"
    grep -q "^output \* bg \"$pic\" fill\$" "$sway" && grep -q '^gaps inner 8$' "$sway" && grep -q '^gaps outer 12$' "$sway" && grep -q '^alpha=0.85$' "$foot" \
        && ok "wallpaper PATH: sway fills it (quoted: a space in the path), gaps 8/12, foot alpha 0.85" || bad "wallpaper render" "$(grep -n 'bg\|gaps' "$sway"; grep -n alpha "$foot")"
    printf '%s\n' "$out" | grep -q 'a running sway shows it now' && ok "desktop wallpaper PATH: says what happens" || bad "wallpaper words" "$out"
    sh "$SH" desktop wallpaper | grep -q "^wallpaper $pic\$" && ok "desktop wallpaper (bare): names the picture" || bad "wallpaper bare after"
    st=$(sh "$SH" status); printf '%s\n' "$st" | grep -q "^  wall  picture *$pic\$" && ok "status: the wall row names the picture" || bad "status wall" "$(sh "$SH" status | grep wall)"
    ck=$(sh "$SH" check || true); printf '%s\n' "$ck" | grep -q '^ok     desktop' && ok "check: the desktop renders match with a wallpaper" || bad "check with wallpaper" "$(sh "$SH" check)"
    rm -f "$pic"
    out=$(sh "$SH" apply)
    printf '%s\n' "$out" | grep -q '^todo   wallpaper .*is not there' && grep -q '^output \* bg #000000 solid_color$' "$sway" && grep -q '^alpha=1.0$' "$foot" \
        && ok "a picture that went missing: a todo row, the palette's colour, never a black screen" || bad "missing wallpaper" "$out"
    st=$(sh "$SH" status); printf '%s\n' "$st" | grep -q '^  wall  missing' && ok "status: wall missing" || bad "status wall missing" "$(sh "$SH" status | grep wall)"
    rc=0; out=$(sh "$SH" desktop wallpaper /nowhere/at/all.jpg 2>&1) || rc=$?
    [ $rc = 1 ] && printf '%s\n' "$out" | grep -q 'not a readable file' && ok "desktop wallpaper: a path that is not there is refused" || bad "wallpaper refuse missing" "$out"
    rc=0; out=$(sh "$SH" desktop wallpaper pictures/x.jpg 2>&1) || rc=$?
    [ $rc = 1 ] && printf '%s\n' "$out" | grep -q 'an absolute path' && ok "desktop wallpaper: a relative path is refused" || bad "wallpaper refuse relative" "$out"
    out=$(sh "$SH" desktop wallpaper none)
    grep -q '^WALLPAPER=none$' "$HOME/.config/spark-shell/config" && grep -q '^output \* bg #000000 solid_color$' "$sway" && grep -q '^gaps inner 0$' "$sway" && grep -q '^alpha=1.0$' "$foot" \
        && ok "desktop wallpaper none: the palette's background is back" || bad "wallpaper none" "$out"
    printf 'DESKTOP=none\n' > "$HOME/.config/spark-shell/config"
    rc=0; out=$(sh "$SH" desktop wallpaper "$HOME/.config/spark-shell/config" 2>&1) || rc=$?
    [ $rc = 1 ] && printf '%s\n' "$out" | grep -q 'spark-shell desktop on first' && ok "desktop wallpaper: refused without the desktop" || bad "wallpaper without desktop" "$out"
    printf 'DESKTOP=sway\nALPHA=0.7\n' > "$HOME/.config/spark-shell/config"; sh "$SH" apply >/dev/null
    grep -q '^alpha=0.7$' "$foot" && ok "ALPHA in the config lands in foot.ini" || bad "alpha key" "$(grep -n alpha "$foot")"
    sed 's/^ALPHA=.*/ALPHA=2/' "$HOME/.config/spark-shell/config" > "$HOME/c.tmp"; mv "$HOME/c.tmp" "$HOME/.config/spark-shell/config"
    rc=0; out=$(sh "$SH" apply 2>&1) || rc=$?
    [ $rc = 1 ] && printf '%s\n' "$out" | grep -q 'ALPHA=2' && ok "ALPHA outside 0..1 is refused in one line" || bad "alpha refuse" "$out"
fi
grep -q '@FONT@' "$REPO/templates/.config/foot/foot.ini" && grep -q '@FOOT_ALPHA@' "$REPO/templates/.config/foot/foot.ini" \
    && grep -q 'output \* bg @WALL_BG@' "$REPO/templates/.config/sway/config" && grep -q '^gaps inner @GAPS_INNER@' "$REPO/templates/.config/sway/config" \
    && ok "templates: foot.ini and sway/config carry placeholders, the hex and the wallpaper land at render time" || bad "desktop template placeholders"
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
    grep -q '^vt = 1$' "$conf" && grep -q '^user = "greeter"$' "$conf" && grep -q -- "--cmd '$REPO/spark-shell desktop' " "$conf" && grep -q -- '--sessions /etc/greetd/spark-shell ' "$conf" \
        && ok "config.toml: vt 1, the greeter user, tuigreet --cmd spark-shell desktop, --sessions" || bad "config.toml shape" "$(cat "$conf")"
    grep '^command' "$conf" | grep -q -- '--background' && bad "config.toml: --background for a tuigreet that lacks it" || ok "config.toml: no --background for a tuigreet without it (0.9)"
    printf '#!/bin/sh\n[ "$1" = --help ] && echo "        --background NAME background animation"\n' > "$H/.local/bin/tuigreet"
    sh "$SH" apply >/dev/null
    grep -q -- "--greeting '$(hostname -s 2>/dev/null || uname -n | cut -d. -f1)' --background doom --theme" "$conf" && ok "config.toml: the DOOM fire for a tuigreet that knows --background (0.11)" || bad "config.toml doom" "$(grep -o -- '--greeting.*--theme' "$conf")"
    grep -q -- "--theme 'border=lightred;" "$conf" && grep -q 'container=black' "$conf" && grep -q 'text=gray' "$conf" && grep -q 'greet=darkgray' "$conf" \
        && ok "config.toml: the palette as ratatui words (border lightred, container black, text gray, greet darkgray)" || bad "config.toml theme" "$(grep -o -- "--theme '[^']*'" "$conf")"
    name=$(hostname -s 2>/dev/null || uname -n | cut -d. -f1)
    grep -q -- "--greeting '$name' " "$conf" && ok "config.toml: the greeting is the machine's short name" || bad "config.toml greeting" "$(grep -o -- "--greeting '[^']*'" "$conf") vs $name"
    grep -q '^Name=desktop$' "$H/root/etc/greetd/spark-shell/desktop.desktop" && grep -q "^Exec=$REPO/spark-shell desktop\$" "$H/root/etc/greetd/spark-shell/desktop.desktop" \
        && grep -q '^Name=console$' "$H/root/etc/greetd/spark-shell/console.desktop" && grep -q '^Exec=bash -l$' "$H/root/etc/greetd/spark-shell/console.desktop" \
        && ok "the two sessions: desktop = spark-shell desktop (the clone), console = bash -l" || bad "session files" "$(cat "$H"/root/etc/greetd/spark-shell/*.desktop)"
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
    out=$(env -u XDG_VTNR -u SWAYSOCK sh "$SH" desktop sideways 2>&1 || true)
    printf '%s\n' "$out" | grep -q '^spark-shell desktop: needs a console login' && [ ! -e "$HOME/.local/state/spark-shell/desk.pending" ] \
        && ok "desktop: a word with no desktop and no seat is refused in one line, nothing left pending" || bad "desktop word no seat" "$out"
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

# --- 16. desks: a desk from your words -----------------------------------
# stubs: spark logs its argv and answers one fixed desk (main gimp-3.0 at
# 70, two firefox pages, micro in a terminal, and toad, which this machine
# lacks); swaymsg logs every line it is sent and answers the queries --
# its tree holds one window per exec line already sent, so the wait after
# an exec returns at once. jq is the real one. The inventory is a fixture
# of desktop entries under XDG_DATA_HOME; XDG_DATA_DIRS points at an empty
# dir so the machine's own entries stay out. The Linux half is guarded by
# uname like 14 and 15.
desk_stubs() {   # after desktop_stubs: its swaymsg is replaced
    cat > "$H/.local/bin/spark" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" > "${XDG_STATE_HOME:-$HOME/.local/state}/spark.argv"
cat <<'JSON'
{"why": "photo work in gimp with the two feeds beside it and a notes file",
 "main": {"app": "gimp-3.0", "args": "", "width": 70},
 "side": [{"app": "firefox", "args": "https://instagram.com"}, {"app": "firefox", "args": "https://x.com"},
          {"app": "micro", "args": ""}, {"app": "player", "args": ""}, {"app": "toad", "args": ""}]}
JSON
EOF
    cat > "$H/.local/bin/swaymsg" <<'EOF'
#!/bin/sh
log=${XDG_STATE_HOME:-$HOME/.local/state}/swaymsg.log; mkdir -p "$(dirname "$log")"
case ${1:-} in
    -t) case $2 in
            get_outputs) echo '[{"current_mode":{"width":2560,"height":1440}}]' ;;
            get_workspaces) echo '[{"num":1},{"num":2}]' ;;
            get_tree) n=$(grep '^exec' "$log" 2>/dev/null | grep -vc 'exec gone' || :); [ -n "$n" ] || n=0; i=0
                printf '{"type":"root","nodes":[{"type":"workspace","num":3,"nodes":['
                while [ "$i" -lt "$n" ]; do [ "$i" -eq 0 ] || printf ','; printf '{"type":"con","pid":%d}' $((100 + i)); i=$((i + 1)); done
                echo ']}]}' ;;
        esac ;;
    --) shift; echo "$*" >> "$log" ;;
esac
EOF
    for t in gimp-3.0 firefox micro gone player; do printf '#!/bin/sh\n:\n' > "$H/.local/bin/$t"; done   # gone: an app that opens no window
    chmod +x "$H/.local/bin/spark" "$H/.local/bin/swaymsg" "$H/.local/bin/gimp-3.0" "$H/.local/bin/firefox" "$H/.local/bin/micro" "$H/.local/bin/gone" "$H/.local/bin/player"
    apps=$XDG_DATA_HOME/applications; mkdir -p "$apps" "$H/share"
    export XDG_DATA_DIRS=$H/share
    printf '[Desktop Entry]\nName=GNU Image Manipulation Program\nComment=Create images and edit photographs\nExec=gimp-3.0 %%U\nTerminal=false\nType=Application\n' > "$apps/gimp.desktop"
    printf '[Desktop Entry]\nName=Firefox\nGenericName=Web Browser\nExec=firefox %%u\nType=Application\n' > "$apps/firefox.desktop"
    printf '[Desktop Entry]\nName=Micro\nExec=micro %%F\nTerminal=true\nType=Application\n' > "$apps/micro.desktop"
    printf '[Desktop Entry]\nName=Hidden\nExec=hidden\nNoDisplay=true\nType=Application\n' > "$apps/hidden.desktop"
    printf '[Desktop Entry]\nName=Gone\nComment=Ends at once, no window\nExec=gone\nType=Application\n' > "$apps/gone.desktop"
    # an entry with its own flags and a file field (mpv's shape): opened as the entry says, the field dropped without args
    printf '[Desktop Entry]\nName=Player\nComment=Play music\nExec=/usr/bin/player --idle -- %%U\nType=Application\n' > "$apps/player.desktop"
}
fresh
desktop_stubs
desk_stubs
need='photo editing for instagram and x'
argv=$H/.local/state/spark.argv; swlog=$H/.local/state/swaymsg.log
desk_last=$H/.local/state/spark-shell/desk.last; desk_pending=$H/.local/state/spark-shell/desk.pending
desks=$H/.config/spark-shell/desks
theme_fixture '#ff5555'
mkdir -p "$HOME/.config/spark-shell"; printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"
sh "$SH" on >/dev/null
if [ "$(uname -s)" = Darwin ]; then
    na_form() {   # na_form WORDS... -> one line, na, exit 1
        st=0; out=$(sh "$SH" desktop "$@" 2>&1) || st=$?
        [ "$st" -eq 1 ] && [ "$(printf '%s\n' "$out" | wc -l)" -eq 1 ] && printf '%s\n' "$out" | grep -q '^spark-shell desktop: na: macOS has its own desktop$' \
            && ok "macOS: desktop $1 refuses, na, one line, exit 1" || bad "macOS desktop $*" "st=$st $out"
    }
    na_form "$need"; na_form keep x; na_form forget x; na_form x
    [ ! -e "$desk_last" ] && [ ! -e "$desk_pending" ] && [ ! -e "$desks" ] && [ ! -e "$argv" ] && [ ! -e "$swlog" ] \
        && ok "macOS: no desk form wrote anything (no desk.last, no pending, no desks dir, spark and swaymsg never called)" || bad "macOS desk wrote" "$(find "$H/.local/state" "$H/.config/spark-shell")"
else
    export SWAYSOCK=$H/sway.sock WAYLAND_DISPLAY=wayland-1    # inside the desktop
    st=$(sh "$SH" status); printf '%s\n' "$st" | grep -q '^  desks none .*spark-shell desktop "WORDS" makes one' && ok "status: the desks row says none before any" || bad "status desks none" "$(printf '%s\n' "$st" | grep desks)"
    out=$(sh "$SH" desktop)
    printf '%s\n' "$out" | grep -q '^no kept desks yet -- try: spark-shell desktop "' && ok "desktop (bare, inside): no kept desks yet, a try line" || bad "desk list empty" "$out"
    # the need: spark asked once, the lines played, the missing app named
    st=0; out=$(sh "$SH" desktop "$need" 2>&1) || st=$?
    [ "$st" -eq 0 ] && printf '%s\n' "$out" | grep -q "^desk> $need\$" && printf '%s\n' "$out" | grep -q '^  photo work in gimp with the two feeds' \
        && ok "desktop WORDS: exit 0, the desk> line, the why line" || bad "desk need" "st=$st $out"
    printf '%s\n' "$out" | grep -q '^  toad is not on this machine -- laid out without it$' && ok "desktop WORDS: an app the model named that is not here is said" || bad "toad line" "$out"
    printf '%s\n' "$out" | grep -q '^  refused  exec toad  (toad is not on this machine)$' && ok "desktop WORDS: its exec line is refused with the reason" || bad "toad refused" "$out"
    printf '%s\n' "$out" | grep -q '^on workspace 3 -- spark-shell desktop keep NAME keeps it$' && ok "desktop WORDS: on workspace 3 (1 and 2 are in use), keep named" || bad "on workspace" "$out"
    printf '%s\n' "$out" | grep -q 'no window after\|sway refused' && bad "desktop WORDS: a wait ran out or sway refused" "$out" || ok "desktop WORDS: every window came up, sway took every line"
    [ -f "$argv" ] && [ "$(sed -n '1,3p' "$argv" | paste -sd ' ' -)" = 'edit --type json' ] && grep -qx -- '--name' "$argv" && grep -qx desk.json "$argv" && grep -qx -- '--about' "$argv" \
        && ok "spark: asked as spark edit --type json --name desk.json --about" || bad "spark argv" "$(cat "$argv" 2>&1)"
    [ "$(tail -1 "$argv")" = "write the desk for this need: $need" ] && ok "spark: the prompt ends with the need's words" || bad "spark prompt" "$(tail -1 "$argv")"
    grep -q 'on a 2560x1440 screen' "$argv" && ok "spark: the about names the screen (from swaymsg get_outputs)" || bad "about screen" "$(grep -o 'on a [^ ]* screen' "$argv")"
    grep -q 'gimp-3.0: Create images and edit photographs' "$argv" && ok "inventory: a desktop entry's Comment (gimp-3.0)" || bad "inventory gimp" "$(grep -o 'gimp-3.0: [^;]*' "$argv")"
    grep -q 'firefox: Web Browser' "$argv" && ok "inventory: GenericName when there is no Comment (firefox)" || bad "inventory firefox" "$(grep -o 'firefox: [^;]*' "$argv")"
    grep -q 'micro: Micro' "$argv" && ok "inventory: Name when there is nothing else (micro)" || bad "inventory micro" "$(grep -o 'micro: [^;]*' "$argv")"
    grep -q ', terminal' "$argv" && bad "inventory: the terminal mark reached the model" "$(grep -o '[^;]*, terminal[^;]*' "$argv")" || ok "inventory: the terminal mark is kept from the model (sway's business)"
    grep -qi 'hidden' "$argv" && bad "inventory: a NoDisplay entry is in" "$(grep -oi '[^;]*hidden[^;]*' "$argv")" || ok "inventory: a NoDisplay entry is dropped"
    grep -q 'for:' "$argv" && bad "inventory: the keyword for counts as a program" "$(grep -o 'for: [^;]*' "$argv")" || ok "inventory: a need word that is a keyword (for) is not a program"
    grep -q 'foot:\|footclient:\|xdg-open:' "$argv" && bad "inventory: foot or xdg-open is in" || ok "inventory: no foot, footclient or xdg-open"
    printf '%s\n' 'workspace number 3' 'exec gimp-3.0' splith 'exec firefox https://instagram.com' splitv 'exec firefox https://x.com' 'exec foot -e micro' 'exec player --idle --' 'focus left' 'resize set width 70 ppt' > "$H/expected.lines"
    cmp -s "$swlog" "$H/expected.lines" && ok "sway got exactly the nine lines in order (main, splith, side, splitv, micro in foot, focus left, resize 70 ppt; toad never)" || bad "swaymsg lines" "$(cat "$swlog" 2>&1)"
    head -1 "$desk_last" | grep -q "^# desk: $need -- rendered by spark-shell" && grep -q '^# why: photo work in gimp' "$desk_last" && grep -q '^exec foot -e micro$' "$desk_last" \
        && ok "desk.last: the header (the words, the marker), the why, the lines" || bad "desk.last" "$(cat "$desk_last" 2>&1)"
    # the prompt form: the words typed at desk> are not printed again
    : > "$swlog"
    st=0; out=$(printf '%s\n' "$need" | SWAYSOCK=/tmp/x sh "$SH" desktop --ask 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$(printf '%s\n' "$out" | grep -c 'desk> ')" -eq 1 ] && grep -q '^exec gimp-3.0$' "$swlog" \
        && ok "desktop --ask: one desk> line, the desk laid out" || bad "ask form" "st=$st $out"
    # keep, list, replay, status, forget
    out=$(sh "$SH" desktop keep studio)
    printf '%s\n' "$out" | grep -q "^kept studio -- spark-shell desktop studio opens it ($desks/studio)\$" && cmp -s "$desk_last" "$desks/studio" \
        && ok "desktop keep NAME: desk.last copied to desks/NAME, said in one line" || bad "keep" "$out"
    out=$(sh "$SH" desktop)
    printf '%s\n' "$out" | grep -q "^  studio  *$need\$" && printf '%s\n' "$out" | grep -q '^spark-shell desktop NAME opens one; keep NAME, forget NAME$' \
        && ok "desktop (bare, inside): lists the kept desk with its words" || bad "desk list" "$out"
    rm -f "$argv" "$swlog"
    st=0; out=$(sh "$SH" desktop studio 2>&1) || st=$?
    [ "$st" -eq 0 ] && printf '%s\n' "$out" | grep -q "^desk> $need\$" && cmp -s "$swlog" "$H/expected.lines" \
        && ok "desktop NAME: replays the same nine lines on the next free workspace (3)" || bad "replay" "st=$st $out $(cat "$swlog" 2>&1)"
    [ ! -e "$argv" ] && ok "desktop NAME: no model call" || bad "replay called spark" "$(cat "$argv")"
    st=$(sh "$SH" status); printf '%s\n' "$st" | grep -q '^  desks 1 kept  *studio (spark-shell desktop NAME)$' && ok "status: the desks row counts and names the kept ones" || bad "status desks" "$(printf '%s\n' "$st" | grep desks)"
    out=$(sh "$SH" desktop forget studio)
    [ "$out" = "forgot studio" ] && [ ! -e "$desks/studio" ] && ok "desktop forget NAME: gone, one line" || bad "forget" "$out"
    st=0; out=$(sh "$SH" desktop forget studio 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = "spark-shell desktop: no kept desk named studio" ] && ok "desktop forget NAME twice: refused in one line" || bad "forget twice" "st=$st $out"
    printf 'workspace number 1\nexec firefox\n' > "$desks/mine"
    st=0; out=$(sh "$SH" desktop forget mine 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$(printf '%s\n' "$out" | wc -l)" -eq 1 ] && printf '%s\n' "$out" | grep -q 'is not a desk of ours -- left alone' && [ -f "$desks/mine" ] \
        && ok "desktop forget NAME: a file without the marker is refused and left in place" || bad "forget yours" "st=$st $out"
    st=0; out=$(sh "$SH" desktop keep 'a b' 2>&1) || st=$?
    [ "$st" -eq 1 ] && printf '%s\n' "$out" | grep -q '^spark-shell desktop: keep NAME -- letters, digits, - and _$' && ok "desktop keep: a name with a space is refused" || bad "keep name" "st=$st $out"
    # the gate on a kept desk edited by hand: every line read, the bad ones named, the rest runs
    printf '# desk: the gate -- rendered by spark-shell\nworkspace number 1\nexec foot -e rm x\nexec gimp-3.0 $(id)\nexec sudo ls\noutput * bg x\nexec firefox a|b\nexec foot -e micro notes.txt\n' > "$desks/gate"
    rm -f "$swlog"
    st=0; out=$(sh "$SH" desktop gate 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$(printf '%s\n' "$out" | grep -c '^  refused  ')" -eq 5 ] && ok "gate: five lines refused, the desk still runs (exit 0)" || bad "gate count" "st=$st $out"
    printf '%s\n' "$out" | grep -qF '  refused  exec foot -e rm x  (rm is not on this machine)' && ok "gate: exec foot -e of an app not in the inventory (rm)" || bad "gate rm" "$out"
    printf '%s\n' "$out" | grep -qF '  refused  exec gimp-3.0 $(id)  (shell syntax' && printf '%s\n' "$out" | grep -qF '  refused  exec firefox a|b  (shell syntax' \
        && ok "gate: shell syntax (\$(id), a pipe) never reaches sh -c" || bad "gate syntax" "$out"
    printf '%s\n' "$out" | grep -qF '  refused  exec sudo ls  (sudo is not an app)' && ok "gate: sudo is not an app" || bad "gate sudo" "$out"
    printf '%s\n' "$out" | grep -qF '  refused  output * bg x  (output is not a desk verb)' && ok "gate: output is not a desk verb" || bad "gate verb" "$out"
    printf '%s\n' 'workspace number 3' 'exec foot -e micro notes.txt' > "$H/expected.gate"
    cmp -s "$swlog" "$H/expected.gate" && ok "gate: sway got the workspace line and the one good exec, nothing else" || bad "gate lines" "$(cat "$swlog" 2>&1)"
    # a window that never comes (mpv with nothing to play): the split meant for it is skipped,
    # so the next window lands beside the main one instead of cutting it
    printf '# desk: gone -- rendered by spark-shell\nworkspace number 1\nexec foot -e micro\nsplith\nexec gone\nsplitv\nexec firefox\nfocus left\nresize set width 70 ppt\n' > "$desks/gone"
    : > "$swlog"
    st=0; out=$(sh "$SH" desktop gone 2>&1) || st=$?
    printf '%s\n' "$out" | grep -q '^  no window from gone -- going on$' && printf '%s\n' "$out" | grep -q '^  skipped  splitv  (no window to split)$' \
        && ok "a window that never comes: said, and the split meant for it skipped" || bad "gone window" "st=$st $out"
    printf '%s\n' 'workspace number 3' 'exec foot -e micro' 'splith' 'exec gone' 'exec firefox' 'focus left' 'resize set width 70 ppt' > "$H/expected.gone"
    cmp -s "$swlog" "$H/expected.gone" && ok "a window that never comes: sway never got the splitv" || bad "gone lines" "$(cat "$swlog" 2>&1)"
    # from a console: the words wait, sway starts, --pending lays them out once
    rm -f "$argv" "$swlog"
    st=0; out=$(env -u SWAYSOCK -u WAYLAND_DISPLAY XDG_VTNR=1 sh "$SH" desktop "news and music" 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$(cat "$desk_pending" 2>&1)" = 'news and music' ] && grep -q 'sway-stub' "$H/.local/state/spark-shell/sway.log" && [ ! -e "$argv" ] \
        && ok "desktop WORDS from a console: the words wait in desk.pending, sway starts, no model call yet" || bad "pending write" "st=$st $out $(cat "$desk_pending" 2>&1)"
    st=0; out=$(sh "$SH" desktop --pending 2>&1) || st=$?
    [ "$st" -eq 0 ] && printf '%s\n' "$out" | grep -q '^desk> news and music$' && printf '%s\n' "$out" | grep -q '^on workspace 3' && [ ! -e "$desk_pending" ] \
        && [ "$(tail -1 "$argv")" = 'write the desk for this need: news and music' ] \
        && ok "desktop --pending: lays the waiting words out, the file is gone" || bad "pending play" "st=$st $out"
    st=0; out=$(sh "$SH" desktop --pending 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ -z "$out" ] && ok "desktop --pending twice: a quiet no-op" || bad "pending twice" "st=$st $out"
    # no jq: check says so, a desk is refused
    mkdir -p "$H/nojq"
    for d in $(printf '%s' "$PATH" | tr ':' ' '); do
        [ -d "$d" ] || continue
        for f in "$d"/*; do
            n=${f##*/}
            if [ "$n" != jq ] && [ -x "$f" ] && [ ! -e "$H/nojq/$n" ]; then ln -s "$f" "$H/nojq/$n"; fi
        done
    done
    out=$(PATH=$H/nojq sh "$SH" check 2>&1 || true)
    printf '%s\n' "$out" | grep -q '^FAIL   desktop      jq is missing (.*) -- spark-shell on$' && ok "check: FAIL desktop without jq, the remedy is spark-shell on" || bad "check no jq" "$out"
    st=0; out=$(PATH=$H/nojq sh "$SH" desktop "$need" 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = "spark-shell desktop: jq is not installed (spark-shell on)" ] && ok "desktop WORDS without jq: refused in one line" || bad "desk no jq" "st=$st $out"
    out=$(sh "$SH" check || true)
    printf '%s\n' "$out" | grep -q '^ok     desktop      sway and foot, the renders match the palette; a desk from your words$' && ok "check: the desktop row says a desk from your words" || bad "check desk row" "$out"
    # the rendered sway config: Super+d, the floating prompt, --pending before the first terminal
    sway=$HOME/.config/sway/config
    grep -qF "bindsym \$mod+d exec \$term --app-id spark-desk -e $REPO/spark-shell desktop --ask" "$sway" && ok "sway render: Super+d asks at a prompt (the clone's spark-shell)" || bad "sway render bind" "$(grep -n 'mod+d' "$sway")"
    grep -qF 'for_window [app_id="spark-desk"] floating enable' "$sway" && ok "sway render: the prompt floats" || bad "sway render for_window" "$(grep -n spark-desk "$sway")"
    l_p=$(grep -nF "exec $REPO/spark-shell desktop --pending" "$sway" | head -1 | cut -d: -f1); l_t=$(grep -n "^exec sh -c '" "$sway" | tail -1 | cut -d: -f1)
    [ -n "$l_p" ] && [ -n "$l_t" ] && [ "$l_p" -lt "$l_t" ] && ok "sway render: desktop --pending runs before the first terminal" || bad "sway render pending" "pending $l_p terminal $l_t"
    unset SWAYSOCK WAYLAND_DISPLAY
fi
grep -q '^bindsym \$mod+d exec \$term --app-id spark-desk -e @REPO@/spark-shell desktop --ask$' "$REPO/templates/.config/sway/config" && ok "sway template: Super+d is spark-shell desktop --ask in a spark-desk foot" || bad "sway template bind" "$(grep -n 'mod+d' "$REPO/templates/.config/sway/config")"
grep -q '^for_window \[app_id="spark-desk"\] floating enable' "$REPO/templates/.config/sway/config" && ok "sway template: the spark-desk window floats" || bad "sway template for_window"
l_p=$(grep -n '^exec @REPO@/spark-shell desktop --pending$' "$REPO/templates/.config/sway/config" | head -1 | cut -d: -f1); l_t=$(grep -n "^exec sh -c '" "$REPO/templates/.config/sway/config" | tail -1 | cut -d: -f1)
[ -n "$l_p" ] && [ -n "$l_t" ] && [ "$l_p" -lt "$l_t" ] && ok "sway template: desktop --pending is the exec before the last exec sh -c" || bad "sway template pending" "pending $l_p terminal $l_t"
grep -q '^## A desk from your words$' "$REPO/README.md" && ok "README: A desk from your words" || bad "README desk section"
grep -q '^## v0.23$' "$REPO/CHANGELOG.md" && ok "CHANGELOG: v0.23" || bad "CHANGELOG v0.23"

printf '%s\n' "shell_test: $pass ok, $fail failed"
[ "$fail" -eq 0 ]
