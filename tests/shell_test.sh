#!/bin/sh
# spark-shell tests -- a throwaway HOME, no network, no packages: the
# package row is forced to `todo` by an unknown distro fixture, and the
# prompt row is satisfied by a stub, so `on` exercises the render and
# link machinery only. Run: sh tests/shell_test.sh
# With SPARK=/path/to/spark's clone, section 13 renders its palettes too.
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
    printf '#!/bin/sh\necho starship 0.0-stub\n' > "$H/.local/bin/starship"   # the prompt row finds it
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
rc=0; out=$(sh "$SH" on nonsense 2>&1) || rc=$?
[ "$rc" -eq 1 ] && [ "$out" = "spark-shell on: nonsense is not a thing to switch on (desktop is)" ] && [ ! -e "$HOME/.tmux.conf" ] && [ ! -e "$HOME/.config/spark-shell/config" ] \
    && ok "on NOUN: an unknown noun is refused in one sentence before anything runs (exit 1)" || bad "on nonsense" "rc=$rc $out"
rc=0; out=$(sh "$SH" off nonsense 2>&1) || rc=$?
[ "$rc" -eq 1 ] && [ "$out" = "spark-shell off: nonsense is not a thing to switch off (desktop is)" ] && ok "off NOUN: the same refusal" || bad "off nonsense" "rc=$rc $out"

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
[ ! -e "$HOME/.gitconfig" ] && ok "on: no .gitconfig written (git's identity is git's)" || bad "gitconfig written" "$(cat "$HOME/.gitconfig")"
grep -q ':Tc' "$HOME/.tmux.conf" && bad "tmux advertises truecolor for the look" || ok "on: no Tc override (the look is slots)"
grep -q 'terminal-features ",foot\*:RGB"' "$HOME/.tmux.conf" && ok "on: content passes through in RGB under foot" || bad "foot RGB passthrough" "$(grep -n terminal- "$HOME/.tmux.conf")"
grep -q 'client-attached' "$HOME/.tmux.conf" && bad "the console hook survives" || ok "on: no console hook (the slots need none)"
grep -q '^force_tty = True' "$HOME/.config/btop/btop.conf" && grep -q '^graph_symbol = "tty"' "$HOME/.config/btop/btop.conf" \
    && ok "on: btop in tty mode, tty graphs" || bad "btop tty mode"
[ ! -e "$HOME/.config/micro" ] && ok "on: no editor configured (nothing under ~/.config/micro)" || bad "micro touched" "$(ls -R "$HOME/.config/micro")"
grep -q "EDITOR\|editor = " "$REPO/templates/linux/.bashrc" "$REPO/templates/macos/.zshrc" && bad "an editor is still configured" || ok "templates: no EDITOR, no git editor"
grep -q 'style = "bold bright-red"' "$HOME/.config/starship.toml" && ok "on: starship's accent is its colour word (bright-red)" || bad "starship accent"
sgr=$HOME/.config/spark-shell/sgr.sh
grep -q "SPARK_ACCENT_SGR='1;91'" "$sgr" && grep -q "SPARK_MUTED_SGR='90'" "$sgr" && grep -q "SPARK_WARN_SGR='1;31'" "$sgr" \
    && ok "on: sgr.sh exports the slots as SGR (accent 1;91, muted 90, warn 1;31)" || bad "sgr render" "$(cat "$sgr" 2>&1)"
grep -q '^# rendered by spark-shell' "$sgr" && ok "on: sgr.sh carries the marker" || bad "sgr marker"
# shellcheck disable=SC1090   # the render just written, on purpose
(. "$sgr" && [ "$SPARK_ACCENT_SGR" = '1;91' ] && [ "$SPARK_MUTED_SGR" = 90 ] && [ "$SPARK_WARN_SGR" = '1;31' ]) \
    && ok "on: sgr.sh sources in sh and sets the three" || bad "sgr source"
grep -q 'custom' "$HOME/.config/starship.toml" && bad "starship carries a segment of its own" || ok "on: starship's prompt is starship's alone (no spark segment)"
# the bar row asks spark itself: a stub that answers, one that fails, none at all
printf '#!/bin/sh\nexit 0\n' > "$H/.local/bin/spark"; chmod +x "$H/.local/bin/spark"
ck=$(sh "$SH" check || true)
printf '%s\n' "$ck" | grep -q '^ok     bar          spark bar line answers the status line$' && ok "check: ok bar when spark bar line answers" || bad "check bar ok" "$(printf '%s\n' "$ck" | grep bar)"
printf '#!/bin/sh\nexit 1\n' > "$H/.local/bin/spark"
ck=$(sh "$SH" check || true)
printf '%s\n' "$ck" | grep -q '^FAIL   bar          spark bar line failed -- spark check$' && ok "check: FAIL bar when spark bar line fails, the remedy is spark check" || bad "check bar fail" "$(printf '%s\n' "$ck" | grep bar)"
rm -f "$H/.local/bin/spark"
ck=$(PATH=$H/.local/bin:/usr/bin:/bin sh "$SH" check || true)
printf '%s\n' "$ck" | grep -q '^ok     bar          na (spark not found -- the status line stays empty)$' && ok "check: bar is na without spark, still ok" || bad "check bar na" "$(printf '%s\n' "$ck" | grep bar)"
out=$(sh "$SH" on --dry-run)
printf '%s\n' "$out" | grep -q '^Nothing to do$' && ok "second run: Nothing to do" || bad "idempotence" "$out"
# Debian's names: apt ships fd as fdfind and bat as batcat; check and status find them so
mkdir -p "$H/apt-bin"
for t in tmux fzf zoxide eza btop fdfind batcat; do printf '#!/bin/sh\n:\n' > "$H/apt-bin/$t"; chmod +x "$H/apt-bin/$t"; done
printf 'ID=debian\n' > "$H/os-debian"
ck=$(SPARK_OS_RELEASE=$H/os-debian PATH=$H/apt-bin:/usr/bin:/bin sh "$SH" check || true)
printf '%s\n' "$ck" | grep -q '^ok     tools        tmux, fzf, zoxide, eza, bat, btop, fd$' && ok "check under apt: fdfind and batcat count as fd and bat" || bad "check apt tools" "$(printf '%s\n' "$ck" | grep tools)"
st=$(SPARK_OS_RELEASE=$H/os-debian PATH=$H/apt-bin:/usr/bin:/bin sh "$SH" status)
printf '%s\n' "$st" | grep -q '^  tool  fd  *yes$' && printf '%s\n' "$st" | grep -q '^  tool  bat  *yes$' && ok "status under apt: the fd and bat rows say yes" || bad "status apt tools" "$(printf '%s\n' "$st" | grep tool)"

# --- 3. on again follows the palette --------------------------------------
theme_fixture '#ee8800'
sh "$SH" on >/dev/null
grep -q 'fg=colour3,bold' "$HOME/.tmux.conf" && ok "on again: a new accent lands as its nearest slot (colour3)" || bad "on rerender" "$(grep -n colour "$HOME/.tmux.conf" | head -2)"
out=$(sh "$SH" check || true)
printf '%s\n' "$out" | grep -q '^ok     look' && ok "check: the look matches the palette" || bad "check look row" "$out"
printf '%s\n' "$out" | grep -q 'font' && bad "check: a font row survives" "$out" || ok "check: no font row"
grep -q "SPARK_ACCENT_SGR='1;33'" "$HOME/.config/spark-shell/sgr.sh" && ok "on again: the new accent lands in sgr.sh (1;33)" || bad "on again sgr" "$(cat "$HOME/.config/spark-shell/sgr.sh")"
st=$(sh "$SH" status); printf '%s\n' "$st" | grep -q 'accent colour3, muted colour8 (SGR 1;33 / 90)' && ok "status: the theme row names the slots and the SGR pair" || bad "status slots" "$(printf '%s\n' "$st" | grep theme)"
out=$(sh "$SH" on)
printf '%s\n' "$out" | grep -q '^Nothing to do$' && ok "on again with nothing changed: ends in Nothing to do" || bad "on nothing to do" "$out"
out=$(sh "$SH" apply)
printf '%s\n' "$out" | grep -q '^Nothing to do$' && ok "apply is on: the same path, the same closing" || bad "apply alias" "$out"

# --- 4. the prompt choices ------------------------------------------------
mkdir -p "$HOME/.config/spark-shell"
printf 'PROMPT=plain\n' > "$HOME/.config/spark-shell/config"
rm -f "$HOME/.config/starship.toml"
sh "$SH" on >/dev/null
[ ! -e "$HOME/.config/starship.toml" ] && ok "PROMPT=plain renders no starship.toml" || bad "plain prompt"
printf 'PROMPT=starship\nPROMPT_STYLE=full\n' > "$HOME/.config/spark-shell/config"
sh "$SH" on >/dev/null
[ -f "$HOME/.config/starship.toml" ] && grep -q 'style = "bold yellow"' "$HOME/.config/starship.toml" \
    && plain "$HOME/.config/starship.toml" && ok "PROMPT_STYLE=full renders the full style, plain" || bad "full style"
# no starship and no package for it (the fixture family): the shell's own prompt, a skip, never a download
mv "$H/.local/bin/starship" "$H/starship.aside"
out=$(PATH=$H/.local/bin:/usr/bin:/bin sh "$SH" on --dry-run)
printf '%s\n' "$out" | grep -q 'would  starship' && bad "a starship download survives" "$out" || ok "on: no starship row would fetch anything"
printf '%s\n' "$out" | grep -q '^skip   prompt       no starship package here' && ok "on: no starship package here is a skip (the shell's own prompt)" || bad "prompt skip" "$out"
printf '%s\n' "$out" | grep -q '^Nothing to do$' && ok "on: a prompt skip still ends in Nothing to do" || bad "prompt skip count" "$out"
mv "$H/starship.aside" "$H/.local/bin/starship"
out=$(sh "$SH" on --dry-run)
printf '%s\n' "$out" | grep -q '^ok     prompt       starship 0.0-stub draws the prompt$' && ok "on: the prompt row names the starship it found" || bad "prompt ok" "$out"
! grep -q 'STARSHIP_VERSION\|sha256\|curl ' "$SH" && ok "spark-shell: no pinned version, no sha256, no curl (nothing is downloaded)" || bad "a download survives" "$(grep -n 'STARSHIP_VERSION\|sha256\|curl ' "$SH")"

# --- 5. off hands back ----------------------------------------------------
# a yazi theme v0.35 rendered over one of yours (.bak): off hands yours back
mkdir -p "$HOME/.config/yazi"; printf '# rendered by spark-shell\n' > "$HOME/.config/yazi/theme.toml"; printf 'mine\n' > "$HOME/.config/yazi/theme.toml.bak"
out=$(sh "$SH" off --dry-run)
printf '%s\n' "$out" | grep -q '^would  rc ' && printf '%s\n' "$out" | grep -q '^would  restore .*\.tmux\.conf' && printf '%s\n' "$out" | grep -q '^would  restore .*yazi/theme\.toml -- back from theme\.toml\.bak' && printf '%s\n' "$out" | grep -q ' to do$' \
    && ok "off --dry-run: would rows for the rc link, the renders and the .bak, then the count" || bad "off dry-run rows" "$out"
[ -L "$HOME/$rc1" ] && [ -f "$HOME/.tmux.conf" ] && [ -f "$HOME/.config/yazi/theme.toml.bak" ] && [ -f "$HOME/.config/spark-shell/sgr.sh" ] \
    && ok "off --dry-run: touched nothing (the rc link, the renders and the .bak still there)" || bad "off dry-run wrote" "$(ls -la "$HOME" "$HOME/.config/yazi")"
out=$(sh "$SH" off)
[ ! -e "$HOME/.config/yazi/theme.toml.bak" ] && [ "$(cat "$HOME/.config/yazi/theme.toml")" = mine ] && ok "off: a yazi theme of yours comes back from .bak (v0.35's render gone)" || bad "yazi hand-back" "$(ls -la "$HOME/.config/yazi")"
if [ "$rc1" = .bashrc ]; then
    [ ! -L "$HOME/.bashrc" ] && grep -q yours "$HOME/.bashrc" && ok "off: the rc file came back from .bak" || bad "rc restore" "$(ls -la "$HOME")"
fi
[ ! -e "$HOME/.tmux.conf" ] && ok "off: a render with no .bak is removed, never a husk" || bad "render removal"
[ ! -e "$HOME/.config/spark-shell/sgr.sh" ] && ok "off: sgr.sh is gone (the prompt goes plain)" || bad "sgr removal"
printf '%s\n' "$out" | grep -q 'packages stay installed' && ok "off: packages stay, said so" || bad "off closing" "$out"

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
    sh "$SH" on >/dev/null
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
    sh "$SH" on >/dev/null
    grep -q '^\[colors\]$' "$foot" && ! grep -q '^\[colors-dark\]$' "$foot" && ok "foot.ini: foot 1.21 gets [colors] alone" || bad "foot 1.21 section" "$(grep -n '^\[' "$foot")"
    printf '#!/bin/sh\n[ "$1" = --version ] && echo "foot version: 1.28.0 (Arch)"\n' > "$HOME/.local/bin/foot"
    sh "$SH" on >/dev/null
    grep -q '^\[colors-dark\]$' "$foot" && ! grep -q '^\[colors\]$' "$foot" && ok "foot.ini: foot 1.28 gets [colors-dark] alone" || bad "foot 1.28 section" "$(grep -n '^\[' "$foot")"
    grep -q '^client.focused *#ff5555 ' "$sway" && ok "sway: client.focused takes the accent's hex (#ff5555)" || bad "sway focused" "$(grep -n client "$sway")"
    grep -q "^bindsym \$mod+s exec \$term --app-id spark-chat -e $REPO/spark-shell desktop --chat\$" "$sway" && ok "sway: the Super+s line names the clone's spark-shell" || bad "sway Super+s render" "$(grep -n 'mod+s ' "$sway")"
    grep -q "^exec sh -c '\$term -e $REPO/spark-shell desktop --first; swaymsg exit'\$" "$sway" && ok "sway: the first window's line names the clone's spark-shell" || bad "sway --first render" "$(grep -n '^exec sh' "$sway")"
    grep -q "^output \* bg \"$REPO/wallpapers/forge-1920x1080.jpg\" fill\$" "$sway" && grep -q '^gaps inner 8$' "$sway" && grep -q '^alpha=0.85$' "$foot" \
        && ok "sway: the default background is the forge (wallpapers/forge-1920x1080.jpg), gaps, foot translucent" || bad "sway default bg" "$(grep -n 'output\|gaps' "$sway")"
    grep -q '@[A-Z_0-9]*@' "$foot" "$sway" && bad "a desktop render keeps a placeholder" "$(grep -n '@[A-Z_0-9]*@' "$foot" "$sway" | head -2)" || ok "desktop renders: no placeholder left"
    head -1 "$foot" | grep -q '^# rendered by spark-shell' && head -1 "$sway" | grep -q '^# rendered by spark-shell' && ok "desktop renders: both marked" || bad "desktop markers"
    LC_ALL=C grep -q "[^ -~${tab}]" "$foot" "$sway" && bad "a desktop render is not ASCII" || ok "desktop renders: ASCII"
    printf 'DESKTOP=sway\nFONT=Test Mono:size=14\n' > "$HOME/.config/spark-shell/config"
    sh "$SH" on >/dev/null
    grep -q '^font=Test Mono:size=14$' "$foot" && ok "FONT in the config lands in foot.ini verbatim" || bad "FONT override" "$(grep -n '^font' "$foot")"
    printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"
    sh "$SH" on >/dev/null
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
    out=$(SWAYSOCK=/nonexistent sh "$SH" on)
    printf '%s\n' "$out" | grep -q '^ok     sway         reloaded' && ok "on: swaymsg reload when SWAYSOCK is set" || bad "sway reload" "$out"
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
    printf '%s\n' "$out" | grep -q 'not rendered (spark-shell on)' && ok "desktop: refused when a render is missing" || bad "desktop not rendered" "$out"
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
    out=$(sh "$SH" on)
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
    [ $rc = 1 ] && printf '%s\n' "$out" | grep -q 'spark-shell on desktop first' && ok "desktop wallpaper: refused without the desktop" || bad "wallpaper without desktop" "$out"
    printf 'DESKTOP=sway\nALPHA=0.7\n' > "$HOME/.config/spark-shell/config"; sh "$SH" on >/dev/null
    grep -q '^alpha=0.7$' "$foot" && ok "ALPHA in the config lands in foot.ini" || bad "alpha key" "$(grep -n alpha "$foot")"
    sed 's/^ALPHA=.*/ALPHA=2/' "$HOME/.config/spark-shell/config" > "$HOME/c.tmp"; mv "$HOME/c.tmp" "$HOME/.config/spark-shell/config"
    rc=0; out=$(sh "$SH" on 2>&1) || rc=$?
    [ $rc = 1 ] && printf '%s\n' "$out" | grep -q 'ALPHA=2' && ok "ALPHA outside 0..1 is refused in one line" || bad "alpha refuse" "$out"
fi
grep -q '@FONT@' "$REPO/templates/.config/foot/foot.ini" && grep -q '@FOOT_ALPHA@' "$REPO/templates/.config/foot/foot.ini" \
    && grep -q 'output \* bg @WALL_BG@' "$REPO/templates/.config/sway/config" && grep -q '^gaps inner @GAPS_INNER@' "$REPO/templates/.config/sway/config" \
    && ok "templates: foot.ini and sway/config carry placeholders, the hex and the wallpaper land at render time" || bad "desktop template placeholders"
grep -q '^bar ' "$REPO/templates/.config/sway/config" && bad "sway: a bar block (the tmux line is the bar)" || ok "sway template: no bar, tmux's line is the bar"
grep -q '^xwayland disable$' "$REPO/templates/.config/sway/config" && ok "sway template: xwayland disabled" || bad "sway xwayland"
grep -v '^#' "$REPO/templates/.config/sway/config" | grep -q 'tmux' && bad "sway: a window starts tmux (it runs the login shell)" || ok "sway template: a new foot runs the login shell, never tmux"
grep -q "^exec sh -c '\$term -e @REPO@/spark-shell desktop --first; swaymsg exit'$" "$REPO/templates/.config/sway/config" && ok "sway template: the desktop ends with its first terminal (desktop --first: the keys once, then your shell)" || bad "sway template: exec line" "$(grep -n '^exec' "$REPO/templates/.config/sway/config")"
sway_t=$REPO/templates/.config/sway/config
grep -q '^bindsym \$mod+s exec \$term --app-id spark-chat -e @REPO@/spark-shell desktop --chat$' "$sway_t" && ok "sway template: Super+s opens a foot on spark-shell desktop --chat (the AI one key away)" || bad "sway template: Super+s" "$(grep -n 'mod+s ' "$sway_t")"
grep -q '^for_window \[app_id="spark-chat"\] floating enable, resize set width 60 ppt height 40 ppt$' "$sway_t" && ok "sway template: the chat window floats, small" || bad "sway template: spark-chat for_window" "$(grep -n spark-chat "$sway_t")"
grep -q '^bindsym \$mod+Shift+s layout stacking$' "$sway_t" && ! grep -q '^bindsym \$mod+s layout' "$sway_t" && ok "sway template: stacking moved to Super+Shift+s, Super+s is spark's" || bad "sway template: stacking key" "$(grep -n 'layout stacking' "$sway_t")"

# --- the AI one key away: desktop --chat execs spark chat with the palette's exports (all OSes)
fresh
cat > "$H/.local/bin/spark" <<'EOF'
#!/bin/sh
{ printf '%s\n' "$@"; echo "SPARK_ACCENT_SGR=${SPARK_ACCENT_SGR:-unset}"; } > "$HOME/spark.argv"
EOF
chmod +x "$H/.local/bin/spark"
theme_fixture '#ff5555'
sh "$SH" on >/dev/null
st=0; out=$(sh "$SH" desktop --chat 2>&1) || st=$?
[ "$st" -eq 0 ] && [ "$(head -1 "$H/spark.argv")" = chat ] && grep -q "^SPARK_ACCENT_SGR=1;91$" "$H/spark.argv" \
    && ok "desktop --chat: execs spark chat, sgr.sh sourced first (the accent's SGR 1;91 reaches it)" || bad "desktop --chat" "st=$st $out $(cat "$H/spark.argv" 2>&1)"
mv "$H/.local/bin/spark" "$H/spark.away"
st=0; out=$(PATH=$H/.local/bin:/usr/bin:/bin sh "$SH" desktop --chat 2>&1 </dev/null) || st=$?
[ "$st" -eq 0 ] && printf '%s\n' "$out" | grep -q '^spark is not installed -- the AI is spark' && printf '%s\n' "$out" | grep -q 'Enter closes' \
    && ok "desktop --chat without spark: the window says so and waits for Enter, exit 0" || bad "desktop --chat no spark" "st=$st $out"

# --- the first hour: desktop keys any time, the card once in the first window (all OSes)
keys=$(sh "$SH" desktop keys)
[ "$(printf '%s\n' "$keys" | wc -l | tr -d ' ')" -ge 8 ] && ok "desktop keys: the template's key sentences, eight or more" || bad "desktop keys count" "$keys"
printf '%s\n' "$keys" | grep -vq '\.$' && bad "desktop keys: a line that is not a whole sentence" "$(printf '%s\n' "$keys" | grep -v '\.$')" || ok "desktop keys: every line is a sentence ending with a period"
printf '%s\n' "$keys" | grep -q '^Super+s ' && ok "desktop keys: Super+s is among them" || bad "desktop keys Super+s" "$keys"
printf '%s\n' "$keys" | while IFS= read -r line; do grep -qF -- "$line" "$REPO/README.md" || printf '%s\n' "$line"; done > "$H/keys.missing"
[ ! -s "$H/keys.missing" ] && ok "README: every key sentence, verbatim" || bad "README keys" "$(cat "$H/keys.missing")"
[ ! -e "$H/.local/state/spark-shell/desktop.seen" ] && ok "desktop keys: no stamp written" || bad "desktop keys wrote the stamp"
printf '#!/bin/sh\necho shell-stub\n' > "$H/.local/bin/shellstub"; chmod +x "$H/.local/bin/shellstub"
out=$(SHELL=$H/.local/bin/shellstub sh "$SH" desktop --first)
printf '%s\n' "$out" | head -1 | grep -q "^These are the desktop's keys; spark-shell desktop keys shows them again any time\.$" && [ -f "$H/.local/state/spark-shell/desktop.seen" ] && [ "$(printf '%s\n' "$out" | tail -1)" = shell-stub ] \
    && ok "desktop --first: the card once (the stamp written first), then the shell" || bad "desktop --first" "$out"
out=$(SHELL=$H/.local/bin/shellstub sh "$SH" desktop --first)
[ "$out" = shell-stub ] && ok "desktop --first again: the shell alone, no card" || bad "desktop --first twice" "$out"
printf '#!/bin/sh\necho "${PROMPT-unset} ${DESKTOP-unset} ${FONT-unset}"\n' > "$H/.local/bin/envstub"; chmod +x "$H/.local/bin/envstub"
out=$(SHELL=$H/.local/bin/envstub sh "$SH" desktop --first)
[ "$out" = 'unset unset unset' ] && ok "desktop --first: the config's exports (PROMPT, DESKTOP, FONT) never reach your shell" || bad "desktop --first env" "$out"

# --- 15. the login box: on desktop | off desktop, greetd on tty1 ----------
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
    is-active) [ -e "$st/active-$2" ] ;;
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
st=$(PATH=$H/.local/bin:/usr/bin:/bin sh "$SH" status); printf '%s\n' "$st" | grep -q '^  next  spark .*Install spark, the AI this seat is for: github.com/forgewright-ai/spark\.$' && ok "status: next says install spark first, without spark on PATH" || bad "status next spark" "$(printf '%s\n' "$st" | grep next)"
if [ "$(uname -s)" = Darwin ]; then
    st=0; out=$(sh "$SH" on desktop 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$(printf '%s\n' "$out" | wc -l)" -eq 1 ] && printf '%s\n' "$out" | grep -q '^spark-shell desktop: na' \
        && ok "macOS: on desktop refuses, na, one line, exit 1" || bad "macOS on desktop" "st=$st $out"
    grep -q 'DESKTOP=none' "$HOME/.config/spark-shell/config" && [ ! -e "$H/root/etc" ] && ok "macOS: on desktop wrote nothing" || bad "macOS on desktop wrote" "$(cat "$HOME/.config/spark-shell/config")"
else
    out=$(sh "$SH" on desktop --dry-run)
    printf '%s\n' "$out" | grep -q '^would  greeter .*etc/greetd/config.toml' && printf '%s\n' "$out" | grep -q '^would  greeter      enable greetd.service, disable getty@tty1.service' \
        && ok "on desktop --dry-run: would render the root files and switch the units" || bad "greeter dry-run rows" "$out"
    grep -q 'DESKTOP=none' "$HOME/.config/spark-shell/config" && [ ! -e "$H/root/etc" ] && [ ! -e "$H/.config/sway" ] && ok "on desktop --dry-run: wrote nothing (the config kept)" || bad "greeter dry-run wrote" "$(find "$H/root" "$H/.config")"
    printf '%s\n' "$out" | grep -q 'font' && bad "on desktop --dry-run names a font" "$out" || ok "on desktop --dry-run: no font word"
    out2=$(sh "$SH" desktop on --dry-run)
    [ "$out2" = "$out" ] && ok "desktop on is on desktop: the same dry run, row for row" || bad "desktop on alias" "$out2"
    out=$(sh "$SH" on desktop 2>&1); st=$?
    [ "$st" -eq 0 ] && grep -q '^DESKTOP=sway$' "$HOME/.config/spark-shell/config" && grep -q '^PROMPT_STYLE=full$' "$HOME/.config/spark-shell/config" \
        && [ "$(grep -c '^DESKTOP=' "$HOME/.config/spark-shell/config")" -eq 1 ] \
        && ok "on desktop: DESKTOP=sway written into the config, the other line kept" || bad "on desktop config" "st=$st $(cat "$HOME/.config/spark-shell/config")"
    [ -f "$HOME/.config/foot/foot.ini" ] && [ -f "$HOME/.config/sway/config" ] && ok "on desktop: foot.ini and sway/config rendered" || bad "on desktop user renders" "$out"
    allthere=1; for rel in $ROOT_RENDERS; do [ -f "$H/root/$rel" ] || allthere=0; done
    [ "$allthere" = 1 ] && ok "on desktop: the four root files rendered under the root" || bad "root renders" "$(find "$H/root" -type f)"
    conf=$H/root/etc/greetd/config.toml
    head -1 "$conf" | grep -q '^# rendered by spark-shell' && ok "config.toml: the marker is line 1" || bad "config.toml marker" "$(head -1 "$conf")"
    grep -q '^vt = 1$' "$conf" && grep -q '^user = "greeter"$' "$conf" && grep -q -- "--cmd '$REPO/spark-shell desktop' " "$conf" && grep -q -- '--sessions /etc/greetd/spark-shell ' "$conf" \
        && ok "config.toml: vt 1, the greeter user, tuigreet --cmd spark-shell desktop, --sessions" || bad "config.toml shape" "$(cat "$conf")"
    grep '^command' "$conf" | grep -q -- '--background' && bad "config.toml: --background for a tuigreet that lacks it" || ok "config.toml: no --background for a tuigreet without it (0.9)"
    printf '#!/bin/sh\n[ "$1" = --help ] && echo "        --background NAME background animation"\n' > "$H/.local/bin/tuigreet"
    sh "$SH" on >/dev/null
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
        && ok "on desktop: getty@tty1 disabled, greetd enabled (never started or stopped)" || bad "unit switches" "$(cat "$H/root/units/log")"
    grep -Eq '^(start|stop|restart) ' "$H/root/units/log" && bad "a unit was started or stopped live" "$(cat "$H/root/units/log")" || ok "on desktop: no unit started or stopped live"
    printf '%s\n' "$out" | grep -q '^ok     greeter      greetd on tty1 at the next boot (getty@tty1 until then)' && ok "on desktop: the greeter row says the next boot" || bad "greeter row" "$out"
    st=$(sh "$SH" status); printf '%s\n' "$st" | grep -q '^  desk  sway .*login box: greetd at boot' && ok "status: the desk row names the login box" || bad "status login box" "$(printf '%s\n' "$st" | grep desk)"
    # the next row: the first sentence that applies, none when nothing is off
    printf '#!/bin/sh\n:\n' > "$H/.local/bin/spark"; chmod +x "$H/.local/bin/spark"
    st=$(env -u WAYLAND_DISPLAY sh "$SH" status); printf '%s\n' "$st" | grep -q '^  next  login box .*Reboot: the login box takes tty1 at the next boot\.$' && ok "status: next says reboot when greetd is set for boot but not active" || bad "status next reboot" "$(printf '%s\n' "$st" | grep next)"
    touch "$H/root/units/active-greetd.service"
    st=$(env -u WAYLAND_DISPLAY sh "$SH" status); printf '%s\n' "$st" | grep -q '^  next' && bad "status: a next row with nothing off" "$(printf '%s\n' "$st" | grep next)" || ok "status: no next row when nothing is off (greetd active)"
    rm -f "$H/root/units/greetd.service"
    st=$(env -u WAYLAND_DISPLAY sh "$SH" status); printf '%s\n' "$st" | grep -q '^  next  login box .*spark-shell on desktop at a terminal puts greetd on tty1 (sudo once)\.$' && ok "status: next says on desktop when greetd is not at boot" || bad "status next greetd" "$(printf '%s\n' "$st" | grep next)"
    systemctl enable greetd.service; rm -f "$H/.local/bin/spark"
    out=$(sh "$SH" check || true)
    printf '%s\n' "$out" | grep -q '^ok     greeter      greetd on tty1 at boot' && ok "check: ok greeter" || bad "check greeter" "$out"
    out=$(sh "$SH" on --dry-run)
    printf '%s\n' "$out" | grep -q '^Nothing to do$' && ok "on --dry-run after on desktop: Nothing to do (the root files match, the units are set)" || bad "greeter idempotence" "$out"
    # a palette change reaches the box through on
    theme_fixture '#5555ff'
    out=$(sh "$SH" on)
    printf '%s\n' "$out" | grep -q '^render greeter .*config.toml' && grep -q -- "--theme 'border=lightblue;" "$conf" && ok "on: a new accent re-renders config.toml (border lightblue)" || bad "on greeter" "$out"
    printf '%s\n' "$out" | grep -q '^render greeter .*desktop.desktop' && bad "on re-wrote an unchanged root file" "$out" || ok "on: an unchanged root file is left alone"
    # the config set by hand + on = on desktop, one path
    rm -rf "$H/root/etc"; rm -f "$H/root/units/greetd.service"; : > "$H/root/units/log"
    sh "$SH" on >/dev/null
    [ -f "$conf" ] && grep -q '^enable greetd.service$' "$H/root/units/log" && ok "DESKTOP=sway by hand + on: the same path (root files, greetd enabled)" || bad "on = on desktop" "$(cat "$H/root/units/log")"
    # check fails when a unit is off or a file is stale, the remedy is on desktop
    rm -f "$H/root/units/greetd.service"
    out=$(sh "$SH" check || true)
    printf '%s\n' "$out" | grep -q '^FAIL   greeter      greetd.service is not enabled -- spark-shell on desktop' && ok "check: FAIL greeter when greetd is not enabled, the remedy is on desktop" || bad "check greetd off" "$out"
    systemctl enable greetd.service
    printf 'edited\n' >> "$conf"
    out=$(sh "$SH" check || true)
    printf '%s\n' "$out" | grep -q '^FAIL   greeter      stale: /etc/greetd/config.toml -- spark-shell on desktop' && ok "check: FAIL greeter when config.toml is stale" || bad "check stale" "$out"
    # off desktop: first the dry run (nothing touched), then DESKTOP=none, the renders gone, getty back
    : > "$H/root/units/log"
    out=$(sh "$SH" off desktop --dry-run)
    printf '%s\n' "$out" | grep -q '^would  config       DESKTOP=none' && printf '%s\n' "$out" | grep -q '^would  restore .*sway/config' && printf '%s\n' "$out" | grep -q '^would  restore .*foot/foot\.ini' && printf '%s\n' "$out" | grep -q '^would  greeter      getty on tty1 at the next boot' \
        && ok "off desktop --dry-run: would rows for the config, the two renders and the login box" || bad "off desktop dry-run rows" "$out"
    grep -q '^DESKTOP=sway$' "$HOME/.config/spark-shell/config" && [ -f "$HOME/.config/sway/config" ] && [ -f "$conf" ] && ! grep -Eq '^(enable|disable) ' "$H/root/units/log" \
        && ok "off desktop --dry-run: touched nothing (DESKTOP=sway kept, the renders and the root files there, no unit switched)" || bad "off desktop dry-run wrote" "$(cat "$HOME/.config/spark-shell/config"; cat "$H/root/units/log")"
    out=$(sh "$SH" off desktop)
    grep -q '^DESKTOP=none$' "$HOME/.config/spark-shell/config" && grep -q '^PROMPT_STYLE=full$' "$HOME/.config/spark-shell/config" && ok "off desktop: DESKTOP=none written, the other line kept" || bad "off desktop config" "$(cat "$HOME/.config/spark-shell/config")"
    [ ! -e "$HOME/.config/foot/foot.ini" ] && [ ! -e "$HOME/.config/sway/config" ] && ok "off desktop: the two user renders are gone" || bad "off desktop user renders" "$(ls -R "$HOME/.config")"
    [ ! -e "$conf" ] && [ ! -e "$H/root/etc/greetd/spark-shell" ] && [ ! -e "$H/root/etc/systemd/system/greetd.service.d" ] \
        && ok "off desktop: the root files and the two dirs of ours are gone (/etc/greetd is the package's)" || bad "off desktop root" "$(find "$H/root/etc")"
    grep -q '^disable greetd.service$' "$H/root/units/log" && grep -q '^enable getty@tty1.service$' "$H/root/units/log" && ok "off desktop: greetd disabled, getty@tty1 enabled" || bad "off desktop units" "$(cat "$H/root/units/log")"
    printf '%s\n' "$out" | grep -q '^ok     greeter      getty on tty1 at the next boot' && ok "off desktop: the greeter row says getty at the next boot" || bad "off desktop row" "$out"
    printf '%s\n' "$out" | grep -q 'packages stay installed' && ok "off desktop: packages stay, said so" || bad "off desktop closing" "$out"
    out=$(sh "$SH" desktop off)
    printf '%s\n' "$out" | grep -q '^ok     greeter' && bad "desktop off (a spelling of off desktop) twice acts twice" "$out" || ok "desktop off, the spelling, twice: nothing to undo, nothing said"
    # the login box still running after off: its Enter runs `desktop`, which lands in your shell
    printf '#!/bin/sh\necho "shell-stub $* ${DESKTOP-unset}"\n' > "$H/.local/bin/offshell"; chmod +x "$H/.local/bin/offshell"
    st=0; out=$(XDG_VTNR=1 SHELL=$H/.local/bin/offshell env -u WAYLAND_DISPLAY sh "$SH" desktop 2>&1) || st=$?
    [ "$st" -eq 0 ] && printf '%s\n' "$out" | grep -q '^The desktop is off (spark-shell on desktop brings it back); this is your shell\.$' && [ "$(printf '%s\n' "$out" | tail -1)" = 'shell-stub -l unset' ] \
        && ok "desktop with the desktop off, from a console: one line, then your login shell (never a dead end at the greeter)" || bad "desktop off console landing" "st=$st $out"
    # a foreign config.toml is kept as .spark-orig and comes back on off
    mkdir -p "$H/root/etc/greetd"; printf '[terminal]\nvt = 1\n[default_session]\ncommand = "agreety --cmd /bin/sh"\nuser = "greeter"\n' > "$conf"
    sh "$SH" on desktop >/dev/null
    [ -f "$conf.spark-orig" ] && grep -q agreety "$conf.spark-orig" && grep -q '^# rendered by spark-shell' "$conf" && ok "on desktop: a config.toml of the package's goes to .spark-orig once" || bad "spark-orig" "$(ls "$H/root/etc/greetd")"
    sh "$SH" on >/dev/null
    [ -f "$conf.spark-orig" ] && grep -q agreety "$conf.spark-orig" && ok "on again: .spark-orig is never overwritten" || bad "spark-orig twice"
    sh "$SH" off >/dev/null
    [ -f "$conf" ] && grep -q agreety "$conf" && [ ! -e "$conf.spark-orig" ] && ok "off: config.toml is back from .spark-orig" || bad "spark-orig restore" "$(ls "$H/root/etc/greetd"; cat "$conf" 2>&1)"
    [ ! -e "$H/root/etc/greetd/spark-shell" ] && [ ! -e "$H/root/units/greetd.service" ] && [ -e "$H/root/units/getty@tty1.service" ] && ok "off: the whole layer undoes the login box too" || bad "off greeter" "$(find "$H/root")"
    # no theme.env: the colour words -- accent blue, muted white = gray in ratatui's words
    fresh; desktop_stubs; greeter_stubs
    sh "$SH" on desktop >/dev/null
    grep -q -- "--theme 'border=blue;" "$H/root/etc/greetd/config.toml" && grep -q 'greet=gray' "$H/root/etc/greetd/config.toml" && grep -q 'container=black' "$H/root/etc/greetd/config.toml" \
        && ok "no theme.env: border blue, greet gray, container black" || bad "no theme.env greeter" "$(grep -o -- "--theme '[^']*'" "$H/root/etc/greetd/config.toml")"
    out=$(env -u WAYLAND_DISPLAY XDG_VTNR=1 sh "$SH" desktop 2>&1); st=$?
    [ "$st" -eq 0 ] && ok "desktop (start now) still starts sway with the box in place" || bad "desktop start" "$out"
    out=$(env -u XDG_VTNR -u SWAYSOCK sh "$SH" desktop sideways --windows 2>&1 || true)
    printf '%s\n' "$out" | grep -q '^spark-shell desktop: needs a console login' && [ ! -e "$HOME/.local/state/spark-shell/desk.pending" ] \
        && ok "desktop --windows: a word with no desktop and no seat is refused in one line, nothing left pending" || bad "desktop word no seat" "$out"
    # no sudo to be had (not root, sudo refuses, no tty): a todo row, nothing written
    if [ "$(id -u)" -ne 0 ]; then
        printf '#!/bin/sh\nexit 1\n' > "$H/.local/bin/sudo"; chmod +x "$H/.local/bin/sudo"
        out=$(env -u SPARK_SHELL_ROOT sh "$SH" on </dev/null 2>&1 || true)
        printf '%s\n' "$out" | grep -q '^todo   greeter .*spark-shell on desktop at a terminal (sudo once)' && ok "no sudo: the root render is a todo row, the shape of the packages row" || bad "no sudo todo" "$out"
        rm -f "$H/.local/bin/sudo"
    fi
fi
grep -q '@ACCENT_TUI@' "$REPO/templates/etc/greetd/config.toml" && grep -q '@NAME@' "$REPO/templates/etc/greetd/config.toml" && ok "templates: config.toml carries the tui and name placeholders" || bad "config.toml template"
grep -rq 'font' "$REPO/templates/etc" && bad "a root template names a font" || ok "templates/etc: no font word"

# --- 16. desks: a desk from your words -----------------------------------
# stubs: spark logs its argv and answers one fixed desk (main gimp-3.0 at
# 70, two firefox pages, micro in a terminal, and ghostapp, which this machine
# lacks); swaymsg logs every line it is sent and answers the queries --
# its tree holds one window per exec line already sent, so the wait after
# an exec returns at once. jq is the real one. The inventory is a fixture
# of desktop entries under XDG_DATA_HOME; XDG_DATA_DIRS points at an empty
# dir so the machine's own entries stay out. The Linux half is guarded by
# uname like 14 and 15.
desk_stubs() {   # after desktop_stubs: its swaymsg is replaced
    cat > "$H/.local/bin/spark" <<'EOF'
#!/bin/sh
mkdir -p "${XDG_STATE_HOME:-$HOME/.local/state}"; printf '%s\n' "$@" > "${XDG_STATE_HOME:-$HOME/.local/state}/spark.argv"
if [ -e "$HOME/two-screens" ]; then cat <<'JSON'
{"why": "photo work in gimp at the left, the feed at the right, notes beside the photo",
 "main": {"app": "gimp-3.0", "args": "", "width": 70, "screen": "left"},
 "side": [{"app": "firefox", "args": "https://instagram.com", "screen": "right"}, {"app": "micro", "args": ""}]}
JSON
else cat <<'JSON'
{"why": "photo work in gimp with the two feeds beside it and a notes file",
 "main": {"app": "gimp-3.0", "args": "", "width": 70},
 "side": [{"app": "firefox", "args": "https://instagram.com"}, {"app": "firefox", "args": "https://x.com"},
          {"app": "micro", "args": ""}, {"app": "player", "args": ""}, {"app": "ghostapp", "args": ""}]}
JSON
fi
EOF
    # the outputs carry make, model and serial like sway's (never to reach the model); two when $HOME/two-screens exists
    cat > "$H/.local/bin/swaymsg" <<'EOF'
#!/bin/sh
log=${XDG_STATE_HOME:-$HOME/.local/state}/swaymsg.log; mkdir -p "$(dirname "$log")"
case ${1:-} in
    -t) case $2 in
            get_version) echo '{"human_readable":"sway-stub"}' ;;
            get_outputs) o1='{"name":"DP-1","active":true,"make":"Fakemake","model":"Fakemodel","serial":"SN0001","rect":{"x":0,"y":0},"current_mode":{"width":2560,"height":1440}}'
                o2='{"name":"HDMI-A-1","active":true,"make":"Fakemake","model":"Fakemodel","serial":"SN0002","rect":{"x":2560,"y":0},"current_mode":{"width":1920,"height":1080}}'
                if [ -e "$HOME/two-screens" ]; then echo "[$o2,$o1]"; else echo "[$o1]"; fi ;;
            get_workspaces) echo '[{"num":1},{"num":2}]' ;;
            get_tree) ws=$(grep -n '^workspace number' "$log" 2>/dev/null | tail -1); from=${ws%%:*}; num=${ws##* }; [ -n "$from" ] || { from=0; num=3; }
                n=$({ if [ "$from" -gt 0 ]; then sed "1,${from}d" "$log"; else cat "$log"; fi; } 2>/dev/null | grep '^exec' | grep -vc 'exec gone' || :); [ -n "$n" ] || n=0; i=0
                printf '{"type":"root","nodes":[{"type":"workspace","num":%s,"nodes":[' "$num"
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
    na_form apps   # a desk itself plays as rooms here (18)
    [ ! -e "$desk_last" ] && [ ! -e "$desk_pending" ] && [ ! -e "$desks" ] && [ ! -e "$argv" ] && [ ! -e "$swlog" ] \
        && ok "macOS: the picker wrote nothing (no desk.last, no pending, no desks dir, spark and swaymsg never called)" || bad "macOS desk wrote" "$(find "$H/.local/state" "$H/.config/spark-shell")"
else
    export SWAYSOCK=$H/sway.sock WAYLAND_DISPLAY=wayland-1    # inside the desktop
    st=$(sh "$SH" status); printf '%s\n' "$st" | grep -q '^  desks none .*spark-shell desktop "WORDS" makes one' && ok "status: the desks row says none before any" || bad "status desks none" "$(printf '%s\n' "$st" | grep desks)"
    out=$(sh "$SH" desktop)
    printf '%s\n' "$out" | grep -q '^no kept desks yet -- try: spark-shell desktop "' && ok "desktop (bare, inside): no kept desks yet, a try line" || bad "desk list empty" "$out"
    # the need: spark asked once, the lines played, the missing app named
    st=0; out=$(sh "$SH" desktop "$need" 2>&1) || st=$?
    [ "$st" -eq 0 ] && printf '%s\n' "$out" | grep -q "^desk> $need\$" && printf '%s\n' "$out" | grep -q '^  photo work in gimp with the two feeds' \
        && ok "desktop WORDS: exit 0, the desk> line, the why line" || bad "desk need" "st=$st $out"
    printf '%s\n' "$out" | grep -q '^  ghostapp is not on this machine -- laid out without it$' && ok "desktop WORDS: an app the model named that is not here is said" || bad "ghostapp line" "$out"
    printf '%s\n' "$out" | grep -q '^  refused  exec ghostapp  (ghostapp is not on this machine)$' && ok "desktop WORDS: its exec line is refused with the reason" || bad "ghostapp refused" "$out"
    printf '%s\n' "$out" | grep -q '^on workspace 3 -- spark-shell desktop keep NAME keeps it$' && ok "desktop WORDS: on workspace 3 (1 and 2 are in use), keep named" || bad "on workspace" "$out"
    printf '%s\n' "$out" | grep -q 'no window after\|sway refused' && bad "desktop WORDS: a wait ran out or sway refused" "$out" || ok "desktop WORDS: every window came up, sway took every line"
    [ -f "$argv" ] && [ "$(sed -n '1,3p' "$argv" | paste -sd ' ' -)" = 'edit --type json' ] && grep -qx -- '--name' "$argv" && grep -qx desk.json "$argv" && grep -qx -- '--about' "$argv" \
        && ok "spark: asked as spark edit --type json --name desk.json --about" || bad "spark argv" "$(cat "$argv" 2>&1)"
    [ "$(tail -1 "$argv")" = "write the desk for this need: $need" ] && ok "spark: the prompt ends with the need's words" || bad "spark prompt" "$(tail -1 "$argv")"
    grep -q 'on one screen, 2560x1440\. ' "$argv" && ok "spark: the about says one screen and its size (from swaymsg get_outputs)" || bad "about screen" "$(grep -o 'on one screen[^.]*' "$argv")"
    grep -q 'screen is left\|"screen"' "$argv" && bad "about: the screen rule or field reached the model with one screen" "$(grep -o 'A window is on one screen[^.]*' "$argv")" || ok "spark: one screen, no screen field and no screen rule in the about"
    grep -q 'gimp-3.0: Create images and edit photographs' "$argv" && ok "inventory: a desktop entry's Comment (gimp-3.0)" || bad "inventory gimp" "$(grep -o 'gimp-3.0: [^;]*' "$argv")"
    grep -q 'firefox: Web Browser' "$argv" && ok "inventory: GenericName when there is no Comment (firefox)" || bad "inventory firefox" "$(grep -o 'firefox: [^;]*' "$argv")"
    grep -q 'micro: Micro' "$argv" && ok "inventory: Name when there is nothing else (micro)" || bad "inventory micro" "$(grep -o 'micro: [^;]*' "$argv")"
    grep -q ', terminal' "$argv" && bad "inventory: the terminal mark reached the model" "$(grep -o '[^;]*, terminal[^;]*' "$argv")" || ok "inventory: the terminal mark is kept from the model (sway's business)"
    grep -qi 'hidden' "$argv" && bad "inventory: a NoDisplay entry is in" "$(grep -oi '[^;]*hidden[^;]*' "$argv")" || ok "inventory: a NoDisplay entry is dropped"
    grep -q 'for:' "$argv" && bad "inventory: the keyword for counts as a program" "$(grep -o 'for: [^;]*' "$argv")" || ok "inventory: a need word that is a keyword (for) is not a program"
    grep -q 'foot:\|footclient:\|xdg-open:' "$argv" && bad "inventory: foot or xdg-open is in" || ok "inventory: no foot, footclient or xdg-open"
    printf '%s\n' 'workspace number 3' 'exec gimp-3.0' splith 'exec firefox https://instagram.com' splitv 'exec firefox https://x.com' 'exec foot -e micro' 'exec player --idle --' 'focus left' 'resize set width 70 ppt' > "$H/expected.lines"
    cmp -s "$swlog" "$H/expected.lines" && ok "sway got exactly the nine lines in order (main, splith, side, splitv, micro in foot, focus left, resize 70 ppt; ghostapp never)" || bad "swaymsg lines" "$(cat "$swlog" 2>&1)"
    jq -e --arg w "$need" '(keys_unsorted[0] == "words") and .words == $w and (.why | startswith("photo work in gimp")) and .main.app == "gimp-3.0" and .main.width == 70 and (.side | length) == 5 and .side[0].args == "https://instagram.com"' "$desk_last" >/dev/null 2>&1 \
        && ok "desk.last: the model's answer as JSON, the words first, then why, main and side as answered" || bad "desk.last" "$(cat "$desk_last" 2>&1)"
    grep -q '^exec\|^workspace\|^#' "$desk_last" && bad "desk.last holds sway lines or a header" "$(head -3 "$desk_last")" || ok "desk.last: no sway line, no header (rendered when it opens)"
    # the inventory: unmarked, every app with a desktop entry and never a package
    # (the fake pacman answers -Qi and -Ql, as sbom_collect asks); marked (the
    # apps file), exactly those names -- an entry's words, a package's words or
    # yours; a shell never, a name that is nowhere silently left out
    cat > "$H/.local/bin/pacman" <<'EOF'
#!/bin/sh
case ${1:-} in
    -Qi) printf 'Name            : reader\nVersion         : 1.0-1\nLicenses        : GPL2\nDescription     : Text-based Web browser\nInstall Reason  : Explicitly installed\n\n'
         printf 'Name            : bash\nVersion         : 5.2-1\nLicenses        : GPL3\nDescription     : The GNU Bourne Again shell\nInstall Reason  : Explicitly installed\n\n'
         printf 'Name            : linux\nVersion         : 6.1-1\nLicenses        : GPL2\nDescription     : The Linux kernel\nInstall Reason  : Explicitly installed\n\n' ;;
    -Ql) printf 'reader /usr/bin/reader\nbash /usr/bin/bash\nlinux /boot/vmlinuz-linux\n' ;;
esac
EOF
    printf '#!/bin/sh\n:\n' > "$H/.local/bin/reader"; chmod +x "$H/.local/bin/pacman" "$H/.local/bin/reader"
    printf 'ID=arch\n' > "$H/os-arch"
    SPARK_OS_RELEASE=$H/os-arch SWAYSOCK=/tmp/x sh "$SH" desktop "$need" >/dev/null 2>&1 || true
    grep -q 'micro: Micro' "$argv" && ! grep -q 'reader:' "$argv" && ! grep -q 'bash:' "$argv" \
        && ok "inventory unmarked: the entries (micro), never a package (reader, bash)" || bad "inventory unmarked" "$(grep -o 'micro: [^;]*\|reader:[^;]*\|bash:[^;]*' "$argv")"
    apps_file=$HOME/.config/spark-shell/apps
    printf '# the apps a desk may open\nreader: my browser\nmicro\nbash\nghost\n' > "$apps_file"
    SPARK_OS_RELEASE=$H/os-arch SWAYSOCK=/tmp/x sh "$SH" desktop "$need" >/dev/null 2>&1 || true
    grep -q 'reader: my browser' "$argv" && ok "inventory marked: a package with your note, in your words" || bad "inventory marked note" "$(grep -o 'reader[^;]*' "$argv")"
    grep -q 'micro: Micro' "$argv" && ok "inventory marked: a marked entry in the entry's words" || bad "inventory marked entry" "$(grep -o 'micro[^;]*' "$argv")"
    grep -q 'firefox' "$argv" && bad "inventory marked: an unmarked entry is in" "$(grep -o 'firefox[^;]*' "$argv")" || ok "inventory marked: an unmarked entry (firefox) is out"
    grep -q 'bash:' "$argv" && bad "inventory marked: a shell is offered to the model" "$(grep -o 'bash:[^;]*' "$argv")" || ok "inventory marked: a shell is never offered"
    grep -q 'ghost' "$argv" && bad "inventory marked: a name that is nowhere is in" "$(grep -o 'ghost[^;]*' "$argv")" || ok "inventory marked: a name that is nowhere is silently left out"
    rm -f "$apps_file" "$H/.local/bin/pacman" "$H/.local/bin/reader"
    # the prompt form: the words typed at desk> are not printed again
    : > "$swlog"
    st=0; out=$(printf '%s\n\n' "$need" | SWAYSOCK=/tmp/x sh "$SH" desktop --ask 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$(printf '%s\n' "$out" | grep -c 'desk> ')" -eq 1 ] && grep -q '^exec gimp-3.0$' "$swlog" \
        && printf '%s\n' "$out" | grep -q 'Enter closes' && head -1 "$swlog" | grep -q '^\[app_id=spark-desk\] move container to workspace number 3$' \
        && tail -1 "$swlog" | grep -q '^\[app_id=spark-desk\] focus$' \
        && ok "desktop --ask: one desk> line, the prompt window follows the desk, Enter closes it" || bad "ask form" "st=$st $out $(head -2 "$swlog")"
    printf '%s' "$out" | od -c | grep -q '033' && bad "the pulse reached a pipe" "$(printf '%s' "$out" | od -c | grep 033 | head -1)" || ok "no pulse on a pipe (a tty only, like spark's)"
    # keep, list, replay, status, forget
    out=$(sh "$SH" desktop keep studio)
    printf '%s\n' "$out" | grep -q "^kept studio -- spark-shell desktop studio opens it ($desks/studio)\$" && cmp -s "$desk_last" "$desks/studio" \
        && ok "desktop keep NAME: desk.last copied to desks/NAME, said in one line" || bad "keep" "$out"
    # keep takes all the words; bare keep names the desk after its own words
    out=$(sh "$SH" desktop keep Photo Work, please)
    printf '%s\n' "$out" | grep -q "^kept photo-work-please -- " && [ -f "$desks/photo-work-please" ] && ok "desktop keep WORDS: every word, lowercased, joined by -" || bad "keep words" "$out $(ls "$desks")"
    out=$(sh "$SH" desktop keep)
    printf '%s\n' "$out" | grep -q "^kept photo-editing-for-instagram-and-x -- " && [ -f "$desks/photo-editing-for-instagram-and-x" ] && ok "desktop keep (bare): named after the desk's own words" || bad "keep bare" "$out $(ls "$desks")"
    rm -f "$desks/photo-work-please" "$desks/photo-editing-for-instagram-and-x"
    out=$(sh "$SH" desktop)
    printf '%s\n' "$out" | grep -q "^  studio  *$need\$" && printf '%s\n' "$out" | grep -q '^spark-shell desktop NAME opens one; keep \[WORDS\], forget NAME$' \
        && ok "desktop (bare, inside): lists the kept desk with its words" || bad "desk list" "$out"
    rm -f "$argv" "$swlog"
    st=0; out=$(sh "$SH" desktop studio 2>&1) || st=$?
    [ "$st" -eq 0 ] && printf '%s\n' "$out" | grep -q "^desk> $need\$" && printf '%s\n' "$out" | grep -q '^  photo work in gimp' && printf '%s\n' "$out" | grep -q '^on workspace 3 -- the kept desk studio$' && cmp -s "$swlog" "$H/expected.lines" \
        && ok "desktop NAME: replays the same nine lines on the next free workspace (3), with its why" || bad "replay" "st=$st $out $(cat "$swlog" 2>&1)"
    : > "$swlog"
    st=0; out=$(sh "$SH" desktop Studio 2>&1) || st=$?
    [ "$st" -eq 0 ] && head -1 "$swlog" | grep -q '^workspace number 3$' && [ ! -e "$argv" ] && ok "desktop WORDS that name a kept desk (any case): a replay, no model" || bad "replay by words" "st=$st $out"
    : > "$swlog"
    st=0; out=$(printf 'studio\n\n' | SWAYSOCK=/tmp/x sh "$SH" desktop --ask 2>&1) || st=$?
    [ "$st" -eq 0 ] && head -1 "$swlog" | grep -q '^\[app_id=spark-desk\] move container to workspace number 3$' && tail -1 "$swlog" | grep -q '^\[app_id=spark-desk\] focus$' \
        && printf '%s\n' "$out" | grep -q 'photo work in gimp' && printf '%s\n' "$out" | grep -q 'Enter closes' \
        && ok "a kept desk from the prompt: the window follows it, the why is read, Enter closes" || bad "replay ask" "st=$st $out $(cat "$swlog")"
    st=0; out=$(printf 'keep Second Try\n\n' | SWAYSOCK=/tmp/x sh "$SH" desktop --ask 2>&1) || st=$?
    [ "$st" -eq 0 ] && printf '%s\n' "$out" | grep -q 'kept second-try -- ' && [ -f "$desks/second-try" ] && ok "keep at the desk> prompt" || bad "keep at prompt" "st=$st $out"
    rm -f "$desks/second-try"
    [ ! -e "$argv" ] && ok "desktop NAME: no model call" || bad "replay called spark" "$(cat "$argv")"
    st=$(sh "$SH" status); printf '%s\n' "$st" | grep -q '^  desks 1 kept  *studio (spark-shell desktop NAME)$' && ok "status: the desks row counts and names the kept ones" || bad "status desks" "$(printf '%s\n' "$st" | grep desks)"
    out=$(sh "$SH" desktop forget studio)
    [ "$out" = "forgot studio" ] && [ ! -e "$desks/studio" ] && ok "desktop forget NAME: gone, one line" || bad "forget" "$out"
    st=0; out=$(sh "$SH" desktop forget studio 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = "spark-shell desktop: no kept desk named studio" ] && ok "desktop forget NAME twice: refused in one line" || bad "forget twice" "st=$st $out"
    printf 'workspace number 1\nexec firefox\n' > "$desks/mine"
    st=0; out=$(sh "$SH" desktop forget mine 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$(printf '%s\n' "$out" | wc -l)" -eq 1 ] && [ "$out" = "spark-shell desktop: $desks/mine is not a desk of ours (one JSON object: words, why, main, side) -- left alone." ] && [ -f "$desks/mine" ] \
        && ok "desktop forget NAME: a file that is not one JSON object is refused, named, and left in place" || bad "forget yours" "st=$st $out"
    st=0; out=$(sh "$SH" desktop mine 2>&1) || st=$?
    [ "$st" -eq 1 ] && printf '%s\n' "$out" | grep -q 'left alone\.$' && ok "desktop NAME on a file that is not a desk: refused, left alone" || bad "open yours" "st=$st $out"
    # a desk kept before v0.36 (sway lines under a header): refused on open and on forget, the file named, the words to make it again
    printf '# desk: news and mail -- rendered by spark-shell (spark-shell desktop keep NAME keeps it)\nworkspace number 1\nexec firefox\n' > "$desks/old"
    old_why="spark-shell desktop: $desks/old is a desk of the old shape, sway lines; spark-shell desktop \"news and mail\" makes it again, then keep."
    st=0; out=$(sh "$SH" desktop old 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = "$old_why" ] && ok "desktop NAME on a desk of the old shape: one sentence names the file and the words that make it again" || bad "open old" "st=$st $out"
    st=0; out=$(sh "$SH" desktop forget old 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = "$old_why" ] && [ -f "$desks/old" ] && ok "desktop forget NAME on a desk of the old shape: the same sentence, the file left" || bad "forget old" "st=$st $out"
    rm -f "$desks/old"
    cp "$desk_last" "$H/desk.last.json"; printf '# desk: old -- rendered by spark-shell\nworkspace number 1\n' > "$desk_last"
    st=0; out=$(sh "$SH" desktop keep 2>&1) || st=$?
    [ "$st" -eq 1 ] && printf '%s\n' "$out" | grep -q "^spark-shell desktop: $desk_last is a desk of the old shape" && ok "desktop keep with a desk.last of the old shape: refused, the file named" || bad "keep old" "st=$st $out"
    cp "$H/desk.last.json" "$desk_last"
    st=0; out=$(sh "$SH" desktop keep a b 2>&1) || st=$?
    [ "$st" -eq 0 ] && printf '%s\n' "$out" | grep -q '^kept a-b -- ' && [ -f "$desks/a-b" ] && ok "desktop keep: words with a space become one name (a-b)" || bad "keep name" "st=$st $out"
    rm -f "$desks/a-b"
    # the gate on a kept desk edited by hand: every rendered line read, the bad ones named, the rest runs
    cat > "$desks/gate" <<'EOF'
{"words": "the gate", "main": {"app": "rm", "args": "x"},
 "side": [{"app": "gimp-3.0", "args": "$(id)"}, {"app": "sudo", "args": "ls"}, {"app": "firefox", "args": "a|b"}, {"app": "micro", "args": "notes.txt"}]}
EOF
    rm -f "$swlog"
    st=0; out=$(sh "$SH" desktop gate 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$(printf '%s\n' "$out" | grep -c '^  refused  ')" -eq 3 ] && ok "gate: three lines refused, the desk still runs (exit 0)" || bad "gate count" "st=$st $out"
    printf '%s\n' "$out" | grep -q '^  rm x$' && ok "gate: a kept desk you edited may open a program the machine has (rm x ran; it is yours)" || bad "gate rm" "$out"
    printf '%s\n' "$out" | grep -qF '  refused  exec gimp-3.0 $(id)  (shell syntax' && printf '%s\n' "$out" | grep -qF '  refused  exec firefox a|b  (shell syntax' \
        && ok "gate: shell syntax (\$(id), a pipe) never reaches sh -c" || bad "gate syntax" "$out"
    printf '%s\n' "$out" | grep -qE '^  refused  exec (foot -e )?sudo ls  \(sudo is not an app\)$' && ok "gate: sudo is not an app (in foot when this machine has a sudo, plain when not)" || bad "gate sudo" "$out"
    printf '%s\n' 'workspace number 3' 'exec foot -e rm x' 'splith' 'exec foot -e micro notes.txt' 'focus left' 'resize set width 70 ppt' > "$H/expected.gate"
    cmp -s "$swlog" "$H/expected.gate" && ok "gate: sway got the workspace line, the two good execs and their layout, nothing else" || bad "gate lines" "$(cat "$swlog" 2>&1)"
    # a kept desk may open any program the machine has (you kept it); the model's answer may not
    printf '#!/bin/sh\n:\n' > "$H/.local/bin/reader"; chmod +x "$H/.local/bin/reader"
    printf '{"words": "a reader you kept", "main": {"app": "reader"}, "side": [{"app": "sudo", "args": "ls"}]}\n' > "$desks/kept-reader"
    : > "$swlog"
    st=0; out=$(sh "$SH" desktop kept-reader 2>&1) || st=$?
    [ "$st" -eq 0 ] && grep -q '^exec foot -e reader$' "$swlog" && printf '%s\n' "$out" | grep -qE '^  refused  exec (foot -e )?sudo ls  \(sudo is not an app\)$' \
        && ok "a kept desk: a program on the machine but not in the inventory opens; sudo never" || bad "kept gate" "st=$st $out $(cat "$swlog")"
    rm -f "$desks/kept-reader" "$H/.local/bin/reader"
    # a window that never comes (mpv with nothing to play): the split meant for it is skipped,
    # so the next window lands beside the main one instead of cutting it
    printf '{"words": "gone", "main": {"app": "micro", "width": 70}, "side": [{"app": "gone"}, {"app": "firefox"}]}\n' > "$desks/gone"
    : > "$swlog"
    st=0; out=$(sh "$SH" desktop gone 2>&1) || st=$?
    printf '%s\n' "$out" | grep -q '^  gone -- no window$' && printf '%s\n' "$out" | grep -q '^  micro$' && printf '%s\n' "$out" | grep -q '^  firefox$' \
        && ! printf '%s\n' "$out" | grep -q 'splitv\|focus left\|resize set' \
        && ok "a window that never comes: said in the app's own words; no sway grammar on the screen" || bad "gone window" "st=$st $out"
    : > "$swlog"
    st=0; out=$(sh "$SH" desktop gone -v 2>&1) || st=$?
    printf '%s\n' "$out" | grep -q '^  skipped  splitv  (no window to split)$' && printf '%s\n' "$out" | grep -q '^  exec foot -e micro$' \
        && ok "-v after the words is a flag, not a word: the sway lines and the skipped split shown" || bad "gone verbose" "st=$st $out"
    printf '%s\n' 'workspace number 3' 'exec foot -e micro' 'splith' 'exec gone' 'exec firefox' 'focus left' 'resize set width 70 ppt' > "$H/expected.gone"
    cmp -s "$swlog" "$H/expected.gone" && ok "a window that never comes: sway never got the splitv" || bad "gone lines" "$(cat "$swlog" 2>&1)"
    # two screens: the brief says them and the rule; each screen its own workspace, the main's first,
    # focus output before each; the outputs' make, model and serial never leave the machine
    touch "$H/two-screens"; rm -f "$argv" "$swlog"
    st=0; out=$(sh "$SH" desktop "$need" 2>&1) || st=$?
    [ "$st" -eq 0 ] && grep -q 'on screens: left 2560x1440, right 1920x1080\. ' "$argv" && grep -q ' A window is on one screen; screen is left or right; one screen unless the need names two or the work needs two\. ' "$argv" \
        && grep -q '"screen": "left"' "$argv" && ok "two screens: the brief names them left to right with their sizes, the rule, the screen field" || bad "two screens brief" "st=$st $(grep -o 'on screens[^.]*' "$argv") $out"
    grep -q 'Fakemake\|Fakemodel\|SN000' "$argv" && bad "two screens: an output's make, model or serial reached the model" "$(grep -o '[^ ]*Fake[^ ]*\|SN000[0-9]' "$argv" | head -3)" || ok "two screens: the outputs' make, model and serial never reach the model"
    printf '%s\n' 'focus output DP-1' 'workspace number 3' 'exec gimp-3.0' splith 'exec foot -e micro' 'focus left' 'resize set width 70 ppt' 'focus output HDMI-A-1' 'workspace number 4' 'exec firefox https://instagram.com' > "$H/expected.two"
    cmp -s "$swlog" "$H/expected.two" && ok "two screens: the main's group first (focus output, workspace 3, main, micro beside it, sized), then the right screen's (focus output, workspace 4, firefox)" || bad "two screens lines" "$(cat "$swlog" 2>&1)"
    printf '%s\n' "$out" | grep -q '^on workspace 3 and 4 -- spark-shell desktop keep NAME keeps it$' && ok "two screens: the closing line says both workspaces" || bad "two screens closing" "$out"
    printf '%s\n' "$out" | grep -q 'is not here' && bad "two screens: a screen that is here was said to be missing" "$(printf '%s\n' "$out" | grep 'is not here')" || ok "two screens: both named screens are here, no line says one is missing"
    grep -q 'workspace .* output\|floating\|sticky' "$swlog" && bad "two screens: a line that pins (workspace N output, floating, sticky)" "$(grep 'output\|floating\|sticky' "$swlog")" || ok "two screens: nothing pins a window (no workspace N output, no floating, no sticky)"
    sh "$SH" desktop keep two >/dev/null
    jq -e '.main.screen == "left" and .side[0].screen == "right" and (.side[1] | has("screen") | not)' "$desks/two" >/dev/null 2>&1 && ok "two screens: the kept desk carries screen on main and one side entry, as answered" || bad "two kept" "$(cat "$desks/two")"
    rm -f "$H/two-screens"; : > "$swlog"
    st=0; out=$(sh "$SH" desktop two 2>&1) || st=$?
    [ "$st" -eq 0 ] && printf '%s\n' "$out" | grep -q '^  the right screen is not here -- all on DP-1$' && ! printf '%s\n' "$out" | grep -q 'all on *$' && [ "$(grep -c '^workspace number' "$swlog")" -eq 1 ] && ! grep -q '^focus output' "$swlog" \
        && printf '%s\n' "$out" | grep -q '^on workspace 3 -- the kept desk two$' && ok "a desk kept on two screens opens on one: said in one line, one workspace, no focus output" || bad "two on one" "st=$st $out $(cat "$swlog")"
    printf '{"words": "nine", "main": {"app": "micro", "screen": "DP-9"}, "side": [{"app": "firefox", "screen": "right"}]}\n' > "$desks/nine"
    touch "$H/two-screens"; : > "$swlog"
    st=0; out=$(sh "$SH" desktop nine 2>&1) || st=$?
    printf '%s\n' 'focus output DP-1' 'workspace number 3' 'exec foot -e micro' 'focus output HDMI-A-1' 'workspace number 4' 'exec firefox' > "$H/expected.nine"
    [ "$st" -eq 0 ] && printf '%s\n' "$out" | grep -q '^  the DP-9 screen is not here -- all on DP-1$' && cmp -s "$swlog" "$H/expected.nine" \
        && ok "a kept screen name that is not here (DP-9) maps to the first screen; a side on the right keeps its own" || bad "nine" "st=$st $out $(cat "$swlog")"
    st=0; out=$(sh "$SH" desktop nine -v 2>&1) || st=$?
    printf '%s\n' "$out" | grep -q '^  focus output HDMI-A-1$' && ok "-v shows the focus output lines" || bad "nine verbose" "$out"
    rm -f "$H/two-screens" "$desks/nine" "$desks/two"
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
grep -q '^## v0.38$' "$REPO/CHANGELOG.md" && ok "CHANGELOG: v0.38" || bad "CHANGELOG v0.38"

# --- 17. sbom and the apps a desk may open --------------------------------
# a fake pacman answers -Qi (three packages) and -Ql (their files); the
# entries are the fixture's (desk_stubs) plus the tmux entry that `on`
# renders with DESKTOP=sway; fzf is a stub (the picker is asked with no
# terminal, so it never runs); jq is the real one. ID=arch is pinned per
# call, so `on` keeps the fixture's todo packages row. Linux-guarded like
# 14-16. The fake -Ql maps gimp's entry to the fixture's applications dir,
# so gimp is the one app, reader the tool, libfoo the part.
sbom_stubs() {
    cat > "$H/.local/bin/pacman" <<'EOF'
#!/bin/sh
case ${1:-} in
    -Qi) printf 'Name            : gimp\nVersion         : 3.0.4-1\nLicenses        : GPL3\nDescription     : GNU Image Manipulation Program\nInstall Reason  : Explicitly installed\n\n'
         printf 'Name            : reader\nVersion         : 1.0-1\nLicenses        : MIT\nDescription     : Text-based Web browser\nInstall Reason  : Explicitly installed\n\n'
         printf 'Name            : libfoo\nVersion         : 2.1-3\nLicenses        : LGPL2.1\nDescription     : A library other packages need\nInstall Reason  : Installed as a dependency for another package\n\n' ;;
    -Ql) printf 'gimp %s/applications/gimp.desktop\ngimp /usr/bin/gimp-3.0\nreader /usr/bin/reader\nlibfoo /usr/lib/libfoo.so\n' "${XDG_DATA_HOME:-$HOME/.local/share}" ;;
esac
EOF
    printf '#!/bin/sh\n:\n' > "$H/.local/bin/reader"
    printf '#!/bin/sh\necho fzf-stub >&2\n' > "$H/.local/bin/fzf"
    chmod +x "$H/.local/bin/pacman" "$H/.local/bin/reader" "$H/.local/bin/fzf"
    printf 'ID=arch\n' > "$H/os-arch"
}
fresh
desktop_stubs
desk_stubs
sbom_stubs
mkdir -p "$HOME/.config/spark-shell"; printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"
apps_file=$HOME/.config/spark-shell/apps; argv=$H/.local/state/spark.argv
if [ "$(uname -s)" = Darwin ]; then
    sh "$SH" on >/dev/null
    st=0; out=$(sh "$SH" desktop apps </dev/null 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$(printf '%s\n' "$out" | wc -l)" -eq 1 ] && printf '%s\n' "$out" | grep -q '^spark-shell desktop: na: macOS has its own desktop$' \
        && ok "macOS: desktop apps refuses, na, one line, exit 1" || bad "macOS desktop apps" "st=$st $out"
    ck=$(sh "$SH" check || true)
    printf '%s\n' "$ck" | grep -q '^ok     apps         na (' && ok "macOS: the check apps row says na" || bad "macOS check apps" "$(printf '%s\n' "$ck" | grep apps)"
else
    sh "$SH" on >/dev/null
    tmuxd=$HOME/.local/share/applications/spark-shell-tmux.desktop
    [ -f "$tmuxd" ] && head -1 "$tmuxd" | grep -q '^# rendered by spark-shell' && grep -q '^Exec=tmux$' "$tmuxd" && grep -q '^Terminal=true$' "$tmuxd" \
        && ok "on with DESKTOP=sway: tmux declares itself (spark-shell-tmux.desktop, marked, Exec=tmux, Terminal=true)" || bad "tmux entry" "$(cat "$tmuxd" 2>&1)"
    plain "$tmuxd" && ok "tmux entry: plain (no hex, ASCII)" || bad "tmux entry not plain"
    # the table and the kinds: the counts line, exit 0, one row per package
    st=0; out=$(SPARK_OS_RELEASE=$H/os-arch sh "$SH" sbom 2>&1) || st=$?
    [ "$st" -eq 0 ] && printf '%s\n' "$out" | grep -q '^1 apps, 1 tools, 1 parts -- an app declares itself with a desktop entry; spark-shell desktop apps marks the desk'"'"'s$' \
        && ok "sbom: exit 0 and the counts line (one of each kind)" || bad "sbom counts" "st=$st $out"
    printf '%s\n' "$out" | grep -q '^tool  reader  *1.0-1  *MIT  *Text-based Web browser$' \
        && ok "sbom: a command without an entry is a tool (reader, its version, licence and words)" || bad "sbom tool row" "$out"
    printf '%s\n' "$out" | grep -q '^part  libfoo  *2.1-3  *LGPL2.1  *A library other packages need$' && ok "sbom: a package with neither is a part (libfoo)" || bad "sbom part row" "$out"
    printf '%s\n' "$out" | grep -q '^app   gimp  *3.0.4-1  *GPL3  *GNU Image Manipulation Program$' && ok "sbom: a package that ships an entry is an app (gimp)" || bad "sbom gimp row" "$out"
    [ "$(printf '%s\n' "$out" | grep -c '^[a-z]*  ')" -eq 3 ] && ok "sbom: three packages, three rows" || bad "sbom row count" "$out"
    out=$(SPARK_OS_RELEASE=$H/os-arch sh "$SH" sbom tools 2>&1 || true)
    printf '%s\n' "$out" | grep -q '^tool  reader ' && ! printf '%s\n' "$out" | grep -q '^part ' && ok "sbom tools: the tools alone" || bad "sbom tools" "$out"
    out=$(SPARK_OS_RELEASE=$H/os-arch sh "$SH" sbom parts 2>&1 || true)
    printf '%s\n' "$out" | grep -q '^part  libfoo ' && ! printf '%s\n' "$out" | grep -q '^tool ' && ok "sbom parts: the parts alone" || bad "sbom parts" "$out"
    out=$(SPARK_OS_RELEASE=$H/os-arch sh "$SH" sbom apps 2>&1 || true)
    printf '%s\n' "$out" | grep -q '^tool \|^part ' && bad "sbom apps: a tool or a part in the apps" "$out" || ok "sbom apps: no tool, no part"
    # one name: the detail block; an unknown name: one line, exit 1
    st=0; out=$(SPARK_OS_RELEASE=$H/os-arch sh "$SH" sbom reader 2>&1) || st=$?
    [ "$st" -eq 0 ] && printf '%s\n' "$out" | grep -q '^tool  reader 1.0-1$' && printf '%s\n' "$out" | grep -q '^  licence   MIT$' \
        && printf '%s\n' "$out" | grep -q '^  reason    chosen$' && printf '%s\n' "$out" | grep -q '^  commands  reader$' && printf '%s\n' "$out" | grep -q '^  entries   -$' \
        && ok "sbom NAME: the detail block (licence, reason, commands, entries)" || bad "sbom detail" "st=$st $out"
    out=$(SPARK_OS_RELEASE=$H/os-arch sh "$SH" sbom libfoo 2>&1 || true)
    printf '%s\n' "$out" | grep -q '^  reason    dependency$' && printf '%s\n' "$out" | grep -q '^  commands  -$' && ok "sbom NAME: a dependency with no command says so" || bad "sbom libfoo detail" "$out"
    st=0; out=$(SPARK_OS_RELEASE=$H/os-arch sh "$SH" sbom nosuch 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = "spark-shell sbom: no package named nosuch" ] && ok "sbom NAME: an unknown name is refused in one line, exit 1" || bad "sbom unknown" "st=$st $out"
    # --json: CycloneDX 1.5 under the state dir, one line names it
    cdx=$H/.local/state/spark-shell/sbom.cdx.json
    st=0; out=$(SPARK_OS_RELEASE=$H/os-arch sh "$SH" sbom --json 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$out" = "$cdx -- CycloneDX 1.5, 3 components" ] && [ -s "$cdx" ] \
        && ok "sbom --json: writes sbom.cdx.json under the state dir, one line names it and the count" || bad "sbom json line" "st=$st $out"
    jq -e '.bomFormat == "CycloneDX" and .specVersion == "1.5" and .metadata.tools[0].name == "spark-shell" and (.components | length) == 3' "$cdx" >/dev/null 2>&1 \
        && ok "sbom.cdx.json: CycloneDX 1.5, the tool named, three components" || bad "cdx shape" "$(head -c 400 "$cdx" 2>&1)"
    jq -e '.components[] | select(.name == "reader") | .type == "library" and .version == "1.0-1" and .purl == "pkg:pacman/arch/reader@1.0-1" and .licenses[0].license.name == "MIT" and .description == "Text-based Web browser"' "$cdx" >/dev/null 2>&1 \
        && ok "cdx: a tool is a library component with its purl (pkg:pacman/arch/reader@1.0-1), licence and words" || bad "cdx reader" "$(jq -c '.components[] | select(.name == "reader")' "$cdx" 2>&1)"
    jq -e '.components[] | select(.name == "reader") | .properties | (map(select(.name == "spark-shell:kind"))[0].value == "tool") and (map(select(.name == "spark-shell:reason"))[0].value == "chosen") and (map(select(.name == "spark-shell:commands"))[0].value == "reader")' "$cdx" >/dev/null 2>&1 \
        && ok "cdx: the properties carry spark-shell:kind, :reason and :commands" || bad "cdx properties" "$(jq -c '.components[] | select(.name == "reader") | .properties' "$cdx" 2>&1)"
    jq -e '.components[] | select(.name == "libfoo") | .type == "library" and (.properties | map(select(.name == "spark-shell:kind"))[0].value == "part") and (.properties | map(select(.name == "spark-shell:reason"))[0].value == "dependency") and (.properties | map(select(.name == "spark-shell:commands")) | length == 0)' "$cdx" >/dev/null 2>&1 \
        && ok "cdx: a part is a library with kind part, reason dependency, no commands property" || bad "cdx libfoo" "$(jq -c '.components[] | select(.name == "libfoo")' "$cdx" 2>&1)"
    jq -e '.components[] | select(.name == "gimp") | .type == "application" and (.properties | map(select(.name == "spark-shell:entries"))[0].value == "gimp-3.0=")' "$cdx" >/dev/null 2>&1 \
        && ok "cdx: an app is an application component with its entries property (gimp-3.0)" || bad "cdx application" "$(jq -c '.components[] | select(.name == "gimp")' "$cdx" 2>&1)"
    plain "$cdx" && ok "sbom.cdx.json: plain (no hex, ASCII)" || bad "cdx not plain"
    # no package manager this repo knows: one line, exit 1
    st=0; out=$(sh "$SH" sbom 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = "spark-shell sbom: no package manager here that this repo knows (pacman, apt, brew)" ] && ok "sbom with ID=fixture: no known package manager, one line, exit 1" || bad "sbom fixture" "st=$st $out"
    # the picker with no terminal: refused in one line naming the file (apps and tools alike)
    st=0; out=$(sh "$SH" desktop tools </dev/null 2>&1) || st=$?
    [ "$st" -eq 1 ] && printf '%s\n' "$out" | grep -q '^spark-shell desktop: the picker needs a terminal' && ok "desktop tools: the same picker, the same refusal without a terminal" || bad "tools refusal" "st=$st $out"
    st=0; out=$(sh "$SH" desktop apps </dev/null 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = "spark-shell desktop: the picker needs a terminal; the file is $apps_file (name[: your words], one per line)" ] \
        && ok "desktop apps without a terminal: refused in one line naming the file, exit 1" || bad "desktop apps no tty" "st=$st $out"
    [ ! -e "$apps_file" ] && ok "desktop apps without a terminal: wrote nothing" || bad "desktop apps wrote" "$(cat "$apps_file")"
    # status and check, unmarked: every entry (the five fixtures and tmux)
    st=$(sh "$SH" status); printf '%s\n' "$st" | grep -q '^  apps  unmarked  *every app with a desktop entry (spark-shell desktop apps picks)$' && ok "status: the apps row says unmarked, every app with a desktop entry" || bad "status apps unmarked" "$(printf '%s\n' "$st" | grep apps)"
    ck=$(sh "$SH" check || true); printf '%s\n' "$ck" | grep -q '^ok     apps         6 apps declare themselves, none marked (spark-shell desktop apps picks)$' \
        && ok "check: the apps row counts the entries (five fixtures and tmux), none marked" || bad "check apps unmarked" "$(printf '%s\n' "$ck" | grep apps)"
    # the unmarked inventory: tmux in its entry's words, a terminal app
    rm -f "$argv"
    SWAYSOCK=/tmp/x WAYLAND_DISPLAY=wayland-1 sh "$SH" desktop "$need" >/dev/null 2>&1 || true
    if command -v tmux >/dev/null 2>&1; then
        grep -q 'tmux: A shell with panes, sessions and the status line' "$argv" && ok "inventory unmarked: tmux in its entry's words" || bad "inventory tmux" "$(grep -o 'tmux[^;]*' "$argv" 2>&1)"
    fi
    grep -q 'gimp-3.0: Create images and edit photographs' "$argv" && ! grep -q 'gimp:' "$argv" && ok "inventory unmarked: an entry's Exec name, never the package name (gimp-3.0, not gimp)" || bad "inventory gimp" "$(grep -o 'gimp[^;]*' "$argv" 2>&1)"
    # marked: the names, the rows; a name that is gone is a FAIL with the remedy
    printf '# mine\nreader: my browser\nmicro\n' > "$apps_file"
    st=$(sh "$SH" status); printf '%s\n' "$st" | grep -q '^  apps  2 marked  *reader, micro (spark-shell desktop apps)$' && ok "status: the apps row counts and names the marked" || bad "status apps marked" "$(printf '%s\n' "$st" | grep apps)"
    ck=$(sh "$SH" check || true); printf '%s\n' "$ck" | grep -q '^ok     apps         2 marked for the desk, 6 apps declare themselves$' && ok "check: ok apps when every marked name is here" || bad "check apps marked" "$(printf '%s\n' "$ck" | grep apps)"
    printf 'reader: my browser\nmicro\nghost\n' > "$apps_file"
    ck=$(sh "$SH" check || true); printf '%s\n' "$ck" | grep -q '^FAIL   apps         marked but not here: ghost -- spark-shell desktop apps$' && ok "check: FAIL apps naming the marked name that is gone, the remedy is desktop apps" || bad "check apps gone" "$(printf '%s\n' "$ck" | grep apps)"
    rm -f "$apps_file"
    # off hands the tmux entry back
    sh "$SH" off >/dev/null
    [ ! -e "$tmuxd" ] && ok "off: the tmux entry is gone (no .bak: there was none before)" || bad "tmux entry off" "$(ls "$HOME/.local/share/applications")"
    ck=$(sh "$SH" check || true); printf '%s\n' "$ck" | grep -q '^ok     apps         5 apps declare themselves, none marked' && ok "check after off: tmux is out of the count (five entries)" || bad "check apps after off" "$(printf '%s\n' "$ck" | grep apps)"
    printf 'DESKTOP=none\n' > "$HOME/.config/spark-shell/config"
    ck=$(sh "$SH" check || true); printf '%s\n' "$ck" | grep -q '^ok     apps         na (no desktop)$' && ok "check: apps na with DESKTOP=none" || bad "check apps none" "$(printf '%s\n' "$ck" | grep apps)"
fi
grep -q '^Exec=tmux$' "$REPO/templates/.local/share/applications/spark-shell-tmux.desktop" && grep -q '^Terminal=true$' "$REPO/templates/.local/share/applications/spark-shell-tmux.desktop" \
    && ok "template: spark-shell-tmux.desktop runs tmux in a terminal" || bad "tmux template"

# --- 18. rooms: the same desk as a tmux session --------------------------
# No sway here (SWAYSOCK unset): a desk plays as rooms through a fake
# tmux that logs each call as one line; has-session finds a session
# only while $H/tmux.has exists. newsboat, w3m and aerc are stubs, mpv
# is absent on purpose, the spark and swaymsg stubs are 16's. Not
# uname-guarded: rooms run on macOS too; only the two forms that start
# or address sway are Linux's.
rooms_stubs() {
    cat > "$H/.local/bin/tmux" <<'EOF'
#!/bin/sh
log=${XDG_STATE_HOME:-$HOME/.local/state}/tmux.log; mkdir -p "$(dirname "$log")"
printf '%s\n' "$*" >> "$log"
case ${1:-} in has-session) [ -e "$HOME/tmux.has" ] ;; esac
EOF
    for t in newsboat w3m aerc; do printf '#!/bin/sh\n:\n' > "$H/.local/bin/$t"; done
    chmod +x "$H/.local/bin/tmux" "$H/.local/bin/newsboat" "$H/.local/bin/w3m" "$H/.local/bin/aerc"
}
fresh
desktop_stubs
desk_stubs
rooms_stubs
unset SWAYSOCK WAYLAND_DISPLAY TMUX EDITOR
need='photo editing for instagram and x'; sname=photo-editing-for-instagram-and-x
argv=$H/.local/state/spark.argv; swlog=$H/.local/state/swaymsg.log; tlog=$H/.local/state/tmux.log
desk_last=$H/.local/state/spark-shell/desk.last; desks=$H/.config/spark-shell/desks
# a need with no sway: the rooms player, the terminal apps offered, one room per app that is one
st=0; out=$(sh "$SH" desktop "$need" 2>&1) || st=$?
[ "$st" -eq 0 ] && printf '%s\n' "$out" | grep -q "^desk> $need\$" && printf '%s\n' "$out" | grep -q '^  photo work in gimp with the two feeds' \
    && ok "rooms: a need with no sway plays as rooms: exit 0, the desk> line, the why" || bad "rooms need" "st=$st $out"
printf '%s\n' "has-session -t =$sname" "new-session -d -s $sname -n micro micro" > "$H/expected.rooms"
cmp -s "$tlog" "$H/expected.rooms" && ok "rooms: tmux got has-session, then one new-session with micro as its first window, nothing else" || bad "rooms tmux log" "$(cat "$tlog" 2>&1)"
printf '%s\n' "$out" | grep -q '^  gimp-3.0 -- needs the desktop$' && printf '%s\n' "$out" | grep -q '^  firefox https://instagram.com -- needs the desktop$' && printf '%s\n' "$out" | grep -q '^  micro$' \
    && ok "rooms: a graphical app is one line (needs the desktop), a terminal app runs" || bad "rooms outcome lines" "$out"
printf '%s\n' "$out" | grep -q '^  refused  room ghostapp ghostapp  (ghostapp is not on this machine)$' && ok "rooms: the gate reads a room line like an exec" || bad "rooms gate" "$out"
printf '%s\n' "$out" | grep -q "^rooms $sname -- spark-shell desktop keep NAME keeps it\$" && printf '%s\n' "$out" | grep -q "^rooms $sname -- tmux attach-session -t $sname joins them\$" \
    && ok "rooms: the closing line names the session and keep; on a pipe, the line that joins them" || bad "rooms closing" "$out"
grep -q 'attach-session\|switch-client' "$tlog" && bad "rooms: attached on a pipe" "$(cat "$tlog")" || ok "rooms: no attach on a pipe"
grep -q '^A desk of rooms: the windows for one need, each a terminal window (tmux), on a [0-9]*x[0-9]* terminal\. ' "$argv" && ok "rooms brief: rooms, a terminal, its columns and lines" || bad "rooms brief" "$(grep -o 'A desk[^.]*' "$argv")"
grep -q 'micro: Micro' "$argv" && grep -q 'shell: a terminal with a prompt' "$argv" && ! grep -q 'gimp-3.0\|firefox\|"screen"\|on one screen\|on screens' "$argv" \
    && ok "rooms brief: the terminal apps and shell only; no graphical app, no screen field, no screens" || bad "rooms brief apps" "$(grep -o 'Apps on this machine[^.]*' "$argv")"
jq -e --arg w "$need" '.words == $w and .main.app == "gimp-3.0"' "$desk_last" >/dev/null 2>&1 && ok "rooms: desk.last is the same JSON shape (keep works the same)" || bad "rooms desk.last" "$(cat "$desk_last" 2>&1)"
[ ! -e "$swlog" ] && ok "rooms: swaymsg never sent a line" || bad "rooms swaymsg" "$(cat "$swlog")"
# a need of * from a directory with files: the word, never the file names
rm -f "$argv"
(cd "$H/.local/bin" && sh "$SH" desktop '*' >/dev/null 2>&1) || true
[ "$(tail -1 "$argv")" = 'write the desk for this need: *' ] && ok "a need of * reaches the model as *, not as the cwd's file names" || bad "glob need" "$(tail -1 "$argv" 2>&1)"
# inside tmux: switch-client; a session already open is joined, not built again
: > "$tlog"
st=0; out=$(TMUX=/x sh "$SH" desktop "$need" --rooms 2>&1) || st=$?
[ "$st" -eq 0 ] && [ "$(tail -1 "$tlog")" = "switch-client -t =$sname" ] && ok "rooms inside tmux (TMUX set, --rooms): switch-client to the session" || bad "rooms switch" "st=$st $(cat "$tlog")"
touch "$H/tmux.has"; : > "$tlog"
st=0; out=$(sh "$SH" desktop "$need" 2>&1) || st=$?
[ "$st" -eq 0 ] && printf '%s\n' "$out" | grep -q "^  the rooms $sname are open already\$" && ! grep -q 'new-session' "$tlog" \
    && ok "rooms open already: said in one line, no session built, joined" || bad "rooms has-session" "st=$st $out $(cat "$tlog")"
rm -f "$H/tmux.has"
# the studio shipped with the repo: copied, it is a kept desk; shell and editor are desk words
mkdir -p "$desks"; cp "$REPO/desks/studio" "$desks/"
jq -e '.words == "studio" and .main.app == "shell" and (.side | map(.app)) == ["editor", "newsboat", "w3m", "aerc"]' "$REPO/desks/studio" >/dev/null 2>&1 \
    && ok "desks/studio: words studio, main shell, then editor, newsboat, w3m, aerc (no music room)" || bad "studio shape" "$(cat "$REPO/desks/studio")"
: > "$tlog"; rm -f "$argv"
st=0; out=$(sh "$SH" desktop studio 2>&1) || st=$?
printf '%s\n' 'has-session -t =studio' 'new-session -d -s studio -n shell' 'new-window -t =studio -n editor micro' 'new-window -t =studio -n newsboat newsboat' 'new-window -t =studio -n w3m w3m duckduckgo.com' 'new-window -t =studio -n aerc aerc' > "$H/expected.studio"
[ "$st" -eq 0 ] && cmp -s "$tlog" "$H/expected.studio" && [ ! -e "$argv" ] \
    && ok "desktop studio: the session with a bare shell window, then one window per room, the editor micro with EDITOR unset; no model call" || bad "studio play" "st=$st $out $(cat "$tlog")"
printf '%s\n' "$out" | grep -q '^desk> studio$' && printf '%s\n' "$out" | grep -q '^  a shell, the editor, the feeds' && printf '%s\n' "$out" | grep -q '^  editor micro$' && printf '%s\n' "$out" | grep -q '^  w3m duckduckgo.com$' \
    && printf '%s\n' "$out" | grep -q '^rooms studio -- the kept desk studio$' && ok "desktop studio: the desk> line, the why, one line per room, the closing line" || bad "studio lines" "$out"
printf '#!/bin/sh\n:\n' > "$H/.local/bin/nano"; chmod +x "$H/.local/bin/nano"   # the containers have no nano; a kept desk runs what is on PATH
: > "$tlog"
st=0; out=$(EDITOR=/usr/bin/nano sh "$SH" desktop studio 2>&1) || st=$?
grep -q '^new-window -t =studio -n editor nano$' "$tlog" && ok "editor is EDITOR's basename (nano)" || bad "editor nano" "$(cat "$tlog")"
rm -f "$H/.local/bin/nano"; : > "$tlog"
st=0; out=$(EDITOR=/usr/bin/nosucheditor sh "$SH" desktop studio 2>&1) || st=$?
[ "$st" -eq 0 ] && printf '%s\n' "$out" | grep -q '^  refused  room editor nosucheditor  (nosucheditor is not on this machine)$' && grep -q '^new-window -t =studio -n newsboat newsboat$' "$tlog" \
    && ok "EDITOR naming a program that is not here: its room is refused, the rest opens" || bad "editor absent" "st=$st $out"
mkdir -p "$H/nomicro"   # a PATH with everything but micro (this machine may have the real one)
for d in $(printf '%s' "$PATH" | tr ':' ' '); do
    [ -d "$d" ] || continue
    for f in "$d"/*; do n=${f##*/}; if [ "$n" != micro ] && [ -x "$f" ] && [ ! -e "$H/nomicro/$n" ]; then ln -s "$f" "$H/nomicro/$n"; fi; done
done
: > "$tlog"
st=0; out=$(PATH=$H/nomicro sh "$SH" desktop studio 2>&1) || st=$?
[ "$st" -eq 1 ] && [ "$(printf '%s\n' "$out" | tail -1)" = 'spark-shell desktop: no editor: set EDITOR in ~/.config/spark-shell/rc' ] && ! grep -q 'new-session' "$tlog" \
    && ok "no EDITOR and no micro: refused in one sentence before any room is built" || bad "no editor" "st=$st $out $(cat "$tlog")"
st=0; out=$(sh "$SH" desktop studio -v 2>&1) || st=$?
printf '%s\n' "$out" | grep -q '^  room shell$' && printf '%s\n' "$out" | grep -q '^  room editor micro$' && printf '%s\n' "$out" | grep -q '^  room w3m w3m duckduckgo.com$' \
    && ok "-v shows the rooms grammar (room NAME [CMD ARGS])" || bad "rooms verbose" "$out"
printf '%s\n' "$out" | grep -q '^  session studio$' && ok "-v: the session line" || bad "rooms verbose session" "$out"
printf '{"words": "pipe", "main": {"app": "w3m", "args": "a|b"}}\n' > "$desks/pipe"; : > "$tlog"
st=0; out=$(sh "$SH" desktop pipe 2>&1) || st=$?
[ "$st" -eq 1 ] && printf '%s\n' "$out" | grep -qF '  refused  room w3m w3m a|b  (shell syntax' && ! grep -q 'new-session' "$tlog" && printf '%s\n' "$out" | grep -q 'nothing ran$' \
    && ok "a kept desk edited by hand: shell syntax in a room is refused; with no room left, nothing ran" || bad "rooms pipe" "st=$st $out"
# --rooms inside sway: the session is built, then a foot window of its own on a fresh workspace
export SWAYSOCK=$H/sway.sock; : > "$tlog"; rm -f "$swlog"
st=0; out=$(sh "$SH" desktop studio --rooms 2>&1) || st=$?
[ "$st" -eq 0 ] && grep -q '^new-session -d -s studio -n shell$' "$tlog" && [ "$(head -1 "$swlog")" = 'workspace number 3' ] && [ "$(tail -1 "$swlog")" = 'exec foot -e tmux attach-session -t =studio' ] \
    && ! grep -q 'attach-session\|switch-client' "$tlog" && ok "--rooms inside sway: the rooms built, then workspace 3 and one foot that attaches to them" || bad "rooms in sway" "st=$st $out $(cat "$swlog" "$tlog" 2>&1)"
unset SWAYSOCK
if [ "$(uname -s)" != Darwin ]; then
    # --windows from a console: the words wait, sway starts, --pending lays them out once
    theme_fixture '#ff5555'; mkdir -p "$HOME/.config/spark-shell"; printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"
    sh "$SH" on >/dev/null
    desk_pending=$H/.local/state/spark-shell/desk.pending; rm -f "$argv" "$swlog"
    st=0; out=$(XDG_VTNR=1 sh "$SH" desktop "news and music" --windows 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$(cat "$desk_pending" 2>&1)" = 'news and music' ] && grep -q 'sway-stub' "$H/.local/state/spark-shell/sway.log" && [ ! -e "$argv" ] \
        && ok "desktop WORDS --windows from a console: the words wait in desk.pending, sway starts, no model call yet" || bad "pending write" "st=$st $out $(cat "$desk_pending" 2>&1)"
    st=0; out=$(SWAYSOCK=$H/sway.sock sh "$SH" desktop --pending 2>&1) || st=$?
    [ "$st" -eq 0 ] && printf '%s\n' "$out" | grep -q '^desk> news and music$' && printf '%s\n' "$out" | grep -q '^on workspace 3' && [ ! -e "$desk_pending" ] \
        && [ "$(tail -1 "$argv")" = 'write the desk for this need: news and music' ] \
        && ok "desktop --pending: lays the waiting words out as windows, the file is gone" || bad "pending play" "st=$st $out"
    st=0; out=$(SWAYSOCK=$H/sway.sock sh "$SH" desktop --pending 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ -z "$out" ] && ok "desktop --pending twice: a quiet no-op" || bad "pending twice" "st=$st $out"
fi
grep -q '^## Rooms$' "$REPO/README.md" && ok "README: Rooms" || bad "README rooms section"

printf '%s\n' "shell_test: $pass ok, $fail failed"
[ "$fail" -eq 0 ]
