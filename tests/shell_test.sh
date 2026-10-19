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
plain() {   # plain FILE -- no hex color, no byte outside ASCII
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
    # the root files land under a throwaway root, never in this
    # machine's /etc; systemctl is whatever PATH has (a stub)
    export SPARK_SHELL_ROOT=$H/root
    # the open terminals theme repaints: plain files under $H/pts, never
    # this machine's /dev/pts (a test must not repaint the terminal it runs in)
    export SPARK_SHELL_PTS_DIR=$H/pts
    # the tty is a stub: TEST_TTY=/dev/ttyN is a console, unset is ssh;
    # sway's runtime dir is a login manager's (the desktop tests unset it)
    printf '#!/bin/sh\n[ -n "${TEST_TTY:-}" ] || { echo "not a tty"; exit 1; }\necho "$TEST_TTY"\n' > "$H/.local/bin/tty"
    chmod +x "$H/.local/bin/tty"
    export XDG_RUNTIME_DIR=$H/run
    PATH=$H/.local/bin:$PATH
}

theme_fixture() {   # theme_fixture ACCENT [MUTED] -- a theme.env as today's spark writes it (THEME_BTOP too) over the VGA sixteen
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
sys=$(dirname "$(command -v uname)"):/usr/bin:/bin   # the system's tools alone; a uname put first on PATH (the Linux halves on a Mac) stays

# --- 1. dry-run: rows, nothing touched -----------------------------------
fresh
out=$(sh "$SH" on --dry-run)
printf '%s\n' "$out" | grep -q '^would  rc' && ok "dry-run: would link the rc files" || bad "dry-run rc rows" "$out"
printf '%s\n' "$out" | grep -q '^would  look' && ok "dry-run: would render the look" || bad "dry-run look rows" "$out"
printf '%s\n' "$out" | grep -q '^todo   packages' && ok "dry-run: an unknown family is a todo, not a guess" || bad "dry-run packages row" "$out"
printf '%s\n' "$out" | grep -Eq '^[0-9]+ to do$' && ok "dry-run ends with the count of its would rows" || bad "dry-run count" "$out"
[ "$(printf '%s\n' "$out" | grep -c '^would ')" = "$(printf '%s\n' "$out" | sed -n 's/^\([0-9]*\) to do$/\1/p')" ] && ok "dry-run: the count is the number of would rows" || bad "dry-run count exact" "$out"
printf '%s\n' "$out" | grep -Eq '^(would|todo|FAIL|warn) +font' && bad "a font row acts with CONSOLE_FONT unset" "$out" || ok "dry-run: no font row acts (CONSOLE_FONT unset)"
[ ! -e "$HOME/.tmux.conf" ] && ok "dry-run touched nothing" || bad "dry-run wrote files"
rc=0; out=$(sh "$SH" on nonsense 2>&1) || rc=$?
[ "$rc" -eq 1 ] && [ "$out" = "spark-shell on: nonsense is not known here (only desktop and login are)" ] && [ ! -e "$HOME/.tmux.conf" ] && [ ! -e "$HOME/.config/spark-shell/config" ] \
    && ok "on NOUN: an unknown noun is refused in one sentence before anything runs (exit 1)" || bad "on nonsense" "rc=$rc $out"
rc=0; out=$(sh "$SH" off nonsense 2>&1) || rc=$?
[ "$rc" -eq 1 ] && [ "$out" = "spark-shell off: nonsense is not known here (only desktop and login are)" ] && ok "off NOUN: the same refusal" || bad "off nonsense" "rc=$rc $out"
rc=0; out=$(sh "$SH" apply nonsense 2>&1) || rc=$?
[ "$rc" -eq 1 ] && [ "$out" = "spark-shell on: nonsense is not known here (only desktop and login are)" ] && ok "apply NOUN: the spelling refuses like on" || bad "apply nonsense" "rc=$rc $out"
rc=0; out=$(sh "$SH" desktop on extra 2>&1) || rc=$?
[ "$rc" -eq 1 ] && [ "$out" = "spark-shell on: desktop extra is not known here (only desktop and login are)" ] && [ ! -e "$HOME/.tmux.conf" ] && [ ! -e "$HOME/.config/spark-shell/config" ] \
    && ok "desktop on EXTRA: the spelling refuses an extra word, nothing written" || bad "desktop on extra" "rc=$rc $out"
rc=0; out=$(sh "$SH" on "" 2>&1) || rc=$?
[ "$rc" -eq 1 ] && [ "$out" = "spark-shell on: an empty word is not known here (only desktop and login are)" ] && [ ! -e "$HOME/.tmux.conf" ] && ok "on '': an empty word is refused (every word byte-exact)" || bad "on empty" "rc=$rc $out"

# --- 2. on: links, renders, idempotence, the plain look ------------------
theme_fixture '#ff5555'
printf 'yours\n' > "$HOME/.bashrc"     # a pre-existing rc file of the user's
out=$(sh "$SH" on --yes)
case $(uname -s) in Darwin) rc1=.zshrc ;; *) rc1=.bashrc ;; esac
[ -L "$HOME/$rc1" ] && ok "on: $rc1 is spark-shell's link" || bad "rc link" "$(ls -la "$HOME")"
if [ "$rc1" = .bashrc ]; then
    [ -f "$HOME/.bashrc.bak" ] && grep -q yours "$HOME/.bashrc.bak" && ok "on: yours went to .bak" || bad "rc backup"
fi
[ -f "$HOME/.tmux.conf" ] && grep -q 'fg=colour9,bold' "$HOME/.tmux.conf" && ok "on: the accent is its palette slot (colour9)" || bad "tmux render" "$(grep -n color "$HOME/.tmux.conf" 2>&1 | head -3)"
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
grep -q 'style = "bold bright-red"' "$HOME/.config/starship.toml" && ok "on: starship's accent is its color word (bright-red)" || bad "starship accent"
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
printf '%s\n' "$ck" | grep -q '^ok     bar          spark bar line works$' && ok "check: ok bar when spark bar line answers" || bad "check bar ok" "$(printf '%s\n' "$ck" | grep bar)"
printf '#!/bin/sh\nexit 1\n' > "$H/.local/bin/spark"
ck=$(sh "$SH" check || true)
printf '%s\n' "$ck" | grep -q '^FAIL   bar          spark bar line failed -- spark check$' && ok "check: FAIL bar when spark bar line fails, the remedy is spark check" || bad "check bar fail" "$(printf '%s\n' "$ck" | grep bar)"
rm -f "$H/.local/bin/spark"
ck=$(PATH=$H/.local/bin:$sys sh "$SH" check || true)
printf '%s\n' "$ck" | grep -q '^ok     bar          na (spark not found -- the status line stays empty)$' && ok "check: bar is na without spark, still ok" || bad "check bar na" "$(printf '%s\n' "$ck" | grep bar)"
out=$(sh "$SH" on --dry-run)
printf '%s\n' "$out" | grep -q '^Nothing to do$' && ok "second run: Nothing to do" || bad "idempotence" "$out"
# Debian's names: apt ships fd as fdfind and bat as batcat; check and status find them so
mkdir -p "$H/apt-bin"
for t in tmux fzf zoxide eza btop fdfind batcat; do printf '#!/bin/sh\n:\n' > "$H/apt-bin/$t"; chmod +x "$H/apt-bin/$t"; done
printf 'ID=debian\n' > "$H/os-debian"
ck=$(SPARK_OS_RELEASE=$H/os-debian PATH=$H/apt-bin:$sys sh "$SH" check || true)
printf '%s\n' "$ck" | grep -q '^ok     tools        tmux, fzf, zoxide, eza, bat, btop, fd$' && ok "check under apt: fdfind and batcat count as fd and bat" || bad "check apt tools" "$(printf '%s\n' "$ck" | grep tools)"
st=$(SPARK_OS_RELEASE=$H/os-debian PATH=$H/apt-bin:$sys sh "$SH" status)
printf '%s\n' "$st" | grep -q '^  tool  fd  *yes$' && printf '%s\n' "$st" | grep -q '^  tool  bat  *yes$' && ok "status under apt: the fd and bat rows say yes" || bad "status apt tools" "$(printf '%s\n' "$st" | grep tool)"

# --- 3. on again follows the palette --------------------------------------
theme_fixture '#ee8800'
sh "$SH" on --yes >/dev/null
grep -q 'fg=colour3,bold' "$HOME/.tmux.conf" && ok "on again: a new accent lands as its nearest slot (colour3)" || bad "on rerender" "$(grep -n color "$HOME/.tmux.conf" | head -2)"
out=$(sh "$SH" check || true)
printf '%s\n' "$out" | grep -q '^ok     look' && ok "check: the look matches the palette" || bad "check look row" "$out"
printf '%s\n' "$out" | grep -q '^ok     font         na (CONSOLE_FONT unset: the console keeps its font)$' && ok "check: the font row is na with CONSOLE_FONT unset" || bad "check: font row" "$out"
grep -q "SPARK_ACCENT_SGR='1;33'" "$HOME/.config/spark-shell/sgr.sh" && ok "on again: the new accent lands in sgr.sh (1;33)" || bad "on again sgr" "$(cat "$HOME/.config/spark-shell/sgr.sh")"
st=$(sh "$SH" status); printf '%s\n' "$st" | grep -q 'accent slot 3, muted slot 8 (SGR 1;33 / 90)' && ok "status: the theme row names the slots and the SGR pair" || bad "status slots" "$(printf '%s\n' "$st" | grep theme)"
out=$(sh "$SH" on --yes)
printf '%s\n' "$out" | grep -q '^Nothing to do$' && ok "on again with nothing changed: ends in Nothing to do" || bad "on nothing to do" "$out"
theme_fixture '#5555ff'
out=$(sh "$SH" on --dry-run); out2=$(sh "$SH" apply --dry-run)
[ "$out2" = "$out" ] && printf '%s\n' "$out" | grep -q '^would  look' && ok "apply is on: the same dry run, row for row (the new accent would render)" || bad "apply alias" "$out2"
sh "$SH" apply --yes >/dev/null
grep -q "SPARK_ACCENT_SGR='1;94'" "$HOME/.config/spark-shell/sgr.sh" && ok "apply: the accent lands in sgr.sh (1;94)" || bad "apply sgr" "$(cat "$HOME/.config/spark-shell/sgr.sh")"
theme_fixture '#ee8800'; sh "$SH" on --yes >/dev/null   # the palette section 4 reads

# --- 4. the prompt choices ------------------------------------------------
mkdir -p "$HOME/.config/spark-shell"
printf 'PROMPT=plain\n' > "$HOME/.config/spark-shell/config"
rm -f "$HOME/.config/starship.toml"
sh "$SH" on --yes >/dev/null
[ ! -e "$HOME/.config/starship.toml" ] && ok "PROMPT=plain renders no starship.toml" || bad "plain prompt"
printf 'PROMPT=starship\nPROMPT_STYLE=full\n' > "$HOME/.config/spark-shell/config"
sh "$SH" on --yes >/dev/null
[ -f "$HOME/.config/starship.toml" ] && grep -q 'style = "bold yellow"' "$HOME/.config/starship.toml" \
    && plain "$HOME/.config/starship.toml" && ok "PROMPT_STYLE=full renders the full style, plain" || bad "full style"
# no starship and no package for it (the fixture family): the shell's own prompt, a skip, never a download
mv "$H/.local/bin/starship" "$H/starship.aside"
out=$(PATH=$H/.local/bin:$sys sh "$SH" on --dry-run)
printf '%s\n' "$out" | grep -q 'would  starship' && bad "a starship download survives" "$out" || ok "on: no starship row would fetch anything"
printf '%s\n' "$out" | grep -q '^skip   prompt       no starship package here' && ok "on: no starship package here is a skip (the shell's own prompt)" || bad "prompt skip" "$out"
printf '%s\n' "$out" | grep -q '^Nothing to do$' && ok "on: a prompt skip still ends in Nothing to do" || bad "prompt skip count" "$out"
mv "$H/starship.aside" "$H/.local/bin/starship"
out=$(sh "$SH" on --dry-run)
printf '%s\n' "$out" | grep -q '^ok     prompt       starship 0.0-stub draws the prompt$' && ok "on: the prompt row names the starship it found" || bad "prompt ok" "$out"
! grep -q 'STARSHIP_VERSION' "$SH" && [ "$(grep -c 'curl -' "$SH")" = 1 ] && grep -q '^    curl -fsSL --proto .=https,file. -o "$_df" "$DIALOG_URL/$_rt/spark-dialog-$_dt"' "$SH" \
    && ok "spark-shell: one download, the dialog's release file, checked against the sha256 the tree pins; no pinned version of anything else" || bad "a download survives" "$(grep -n 'STARSHIP_VERSION\|curl ' "$SH")"

# --- 5. off hands back ----------------------------------------------------
# a yazi theme v0.35 rendered over one of yours (.bak): off hands yours back
mkdir -p "$HOME/.config/yazi"; printf '# rendered by spark-shell\n' > "$HOME/.config/yazi/theme.toml"; printf 'mine\n' > "$HOME/.config/yazi/theme.toml.bak"
: > "$HOME/.config/spark/hook.bash"; : > "$HOME/.config/spark/hook.zsh"   # spark installed here: off keeps its hook line
out=$(sh "$SH" off --dry-run)
printf '%s\n' "$out" | grep -q '^would  rc ' && printf '%s\n' "$out" | grep -q '^would  restore .*\.tmux\.conf' && printf '%s\n' "$out" | grep -q '^would  restore .*yazi/theme\.toml -- back from theme\.toml\.bak' && printf '%s\n' "$out" | grep -Eq '^[0-9]+ to do$' \
    && ok "off --dry-run: would rows for the rc link, the renders and the .bak, then the count" || bad "off dry-run rows" "$out"
printf '%s\n' "$out" | grep -q "^would  rc .*/$rc1 -- spark's hook line kept\$" && ok "off --dry-run: the hook line off would append is a would row" || bad "off dry-run hook row" "$out"
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
sh -c '"$0" on --yes' "$H/.local/bin/spark-shell" >/dev/null 2>&1 || true
[ -f "$HOME/.tmux.conf" ] && grep -q 'fg=colour13,bold' "$HOME/.tmux.conf" \
    && ok "a symlinked spark-shell still finds its templates" || bad "symlink invocation" "$(ls -la "$HOME" | head -4)"
case $(uname -s) in Darwin) r8=.zshrc ;; *) r8=.bashrc ;; esac
[ -L "$HOME/$r8" ] && [ -e "$HOME/$r8" ] && ok "the rc link resolves (no dangling target)" || bad "rc link dangles" "$(readlink "$HOME/$r8" 2>&1)"

# --- 9. no theme.env: the color words, each its own slot -----------------
fresh
sh "$SH" on --yes >/dev/null
grep -q 'fg=colour4,bold' "$HOME/.tmux.conf" && grep -q 'pane-border-style "fg=colour7"' "$HOME/.tmux.conf" \
    && ok "no theme.env: accent blue (colour4), muted white (colour7)" || bad "name defaults" "$(grep -n color "$HOME/.tmux.conf" | head -3)"
grep -q "SPARK_ACCENT_SGR='1;34'" "$HOME/.config/spark-shell/sgr.sh" && grep -q "SPARK_MUTED_SGR='37'" "$HOME/.config/spark-shell/sgr.sh" \
    && ok "no theme.env: sgr.sh says blue (1;34) and white (37)" || bad "sgr defaults" "$(cat "$HOME/.config/spark-shell/sgr.sh")"
st=$(sh "$SH" status); printf '%s\n' "$st" | grep -q "none: the terminal's own 16 colors -- accent slot 4, muted slot 7 (SGR 1;34 / 37)" && ok "status: no theme.env, the slots still named" || bad "status none" "$(printf '%s\n' "$st" | grep theme)"

# --- 10. the templates themselves: no truecolor flag, ASCII fzf ----------
grep -q MICRO_TRUECOLOR "$REPO/templates/linux/.bashrc" "$REPO/templates/macos/.zshrc" && bad "MICRO_TRUECOLOR still exported" || ok "rc files: no MICRO_TRUECOLOR"
grep -q -- '--no-unicode' "$REPO/templates/linux/.bashrc" && grep -q -- '--no-unicode' "$REPO/templates/macos/.zshrc" && ok "rc files: fzf asked for ASCII" || bad "fzf opts"
grep -rEq '#[0-9a-fA-F]{6}' "$REPO/templates" && bad "a template names a hex color" "$(grep -rnE '#[0-9a-fA-F]{6}' "$REPO/templates" | head -2)" || ok "templates: no hex color anywhere"
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
        sh "$SH" on --yes >/dev/null
        st=$(sh "$SH" status)
        allplain=1
        for rel in $RENDERS; do plain "$HOME/$rel" || allplain=0; done
        [ "$allplain" = 1 ] && grep -Eq 'fg=color(1[0-5]|[0-9]),bold' "$HOME/.tmux.conf" \
            && ok "$name: renders plain, $(printf '%s\n' "$st" | sed -n 's/.*read: \(accent color[0-9]*, muted color[0-9]*\).*/\1/p')" \
            || bad "$name: not plain or no accent slot" "$(grep -rnE '#[0-9a-fA-F]{6}' "$HOME/.tmux.conf" "$HOME/.config" | head -2)"
    done
else
    printf '  NOTICE: SPARK unset -- spark'"'"'s palettes not exercised (SPARK=/path/to/spark sh tests/shell_test.sh)\n'
fi
# the key spark's next release stops writing: a theme.env without
# THEME_BTOP renders the same look, so both orders work meanwhile
fresh
theme_fixture '#aa0000'
sh "$SH" on --yes >/dev/null
with=$(sed "s|$H|HOME|g" "$HOME/.tmux.conf")
fresh
theme_fixture '#aa0000'
grep -v '^THEME_BTOP=' "$HOME/.config/spark/theme.env" > "$H/theme.env" && mv "$H/theme.env" "$HOME/.config/spark/theme.env"
st=0; out=$(sh "$SH" on --yes 2>&1) || st=$?
[ "$st" -eq 0 ] && [ "$(sed "s|$H|HOME|g" "$HOME/.tmux.conf")" = "$with" ] \
    && ! grep -q 'color_theme\|THEME_BTOP' "$HOME/.config/btop/btop.conf" \
    && sh "$SH" status | grep 'in use: accent slot 1, muted slot 8' >/dev/null \
    && ok "theme.env without THEME_BTOP: the same render, no color_theme line in btop.conf" || bad "theme.env without THEME_BTOP" "st=$st $out"

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
printf '%s\n' "$out" | grep -Eq '^(would|todo|FAIL|warn) +font' && bad "default dry-run acts on a font" "$out" || ok "default dry-run: no font row acts"
sh "$SH" on --yes >/dev/null
st=$(sh "$SH" status); printf '%s\n' "$st" | grep -q '^  desktop none' && ok "status: the desktop row says none" || bad "status desktop none" "$(printf '%s\n' "$st" | grep desktop)"
out=$(sh "$SH" check || true)
printf '%s\n' "$out" | grep -q '^ok     desktop      na (' && ok "check: desktop is na by default" || bad "check desktop na" "$out"
printf '%s\n' "$out" | grep -Eq '^(would|todo|FAIL|warn) +font' && bad "check: a font row fails" "$out" || ok "check: the font row does not fail"
out=$(sh "$SH" desktop 2>&1 || true)
printf '%s\n' "$out" | grep -q '^spark-shell desktop: ' && ok "desktop: refused with DESKTOP=none (the default), one line" || bad "desktop none" "$out"
printf 'THEME=nord\n' > "$HOME/.config/spark-shell/config"
[ "$(THEME=dracula sh "$SH" theme | sed -n 1p | cut -d' ' -f1-3)" = 'theme  nord' ] && ok "config: the file wins over a key in the environment (a window started at login carries the old one)" || bad "file wins" "$(THEME=dracula sh "$SH" theme | sed -n 1p)"
printf 'DESKTOP=gnome\n' > "$HOME/.config/spark-shell/config"
sh "$SH" status >/dev/null 2>&1 && bad "DESKTOP=gnome accepted" || ok "config: DESKTOP=gnome is refused"
printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"
if [ "$(uname -s)" = Darwin ]; then
    out=$(sh "$SH" on --dry-run)
    printf '%s\n' "$out" | grep -q '^skip   desktop      not on macOS' && ok "macOS: DESKTOP=sway is na, said in a row" || bad "macOS na row" "$out"
    sh "$SH" on --yes >/dev/null
    [ ! -e "$HOME/.config/sway" ] && ok "macOS: nothing rendered for the desktop" || bad "macOS rendered sway"
    out=$(sh "$SH" desktop 2>&1 || true)
    printf '%s\n' "$out" | grep -q '^spark-shell desktop: not on macOS' && ok "macOS: desktop refuses, not on macOS" || bad "macOS desktop" "$out"
    out=$(sh "$SH" check || true)
    printf '%s\n' "$out" | grep -q '^ok     desktop      na (macOS)' && ok "macOS: check says na" || bad "macOS check" "$out"
else
    out=$(sh "$SH" on --dry-run)
    printf '%s\n' "$out" | grep -q '^would  look .*foot/foot.ini' && printf '%s\n' "$out" | grep -q '^would  look .*sway/config' \
        && ok "DESKTOP=sway: dry-run would render foot.ini and sway/config" || bad "sway dry-run" "$out"
    sh "$SH" on --yes >/dev/null
    foot=$HOME/.config/foot/foot.ini; sway=$HOME/.config/sway/config
    [ -f "$foot" ] && [ -f "$sway" ] && ok "DESKTOP=sway: both rendered" || bad "sway renders missing" "$(ls -R "$HOME/.config")"
    grep -q '^background=000000$' "$foot" && grep -q '^foreground=aaaaaa$' "$foot" && grep -q '^regular1=aa0000$' "$foot" && grep -q '^bright1=ff5555$' "$foot" && grep -q '^title=terminal$' "$foot" \
        && ok "foot.ini: the palette's own hex (background 000000, regular1 aa0000, bright1 ff5555)" || bad "foot colors" "$(grep -n '=' "$foot" | head -8)"
    grep -q '^font=DejaVu Sans Mono:size=12$' "$foot" && ok "foot.ini: the default FONT line" || bad "foot font line" "$(grep -n '^font' "$foot")"
    grep -q '^\[colors-dark\]$' "$foot" && ! grep -q '^\[colors\]$' "$foot" && ok "foot.ini: one color section, [colors-dark] (a foot with no version = 1.26+)" || bad "foot sections" "$(grep -n '^\[' "$foot")"
    printf '#!/bin/sh\n[ "$1" = --version ] && echo "foot version: 1.21.0 (Debian)"\n' > "$HOME/.local/bin/foot"
    sh "$SH" on --yes >/dev/null
    grep -q '^\[colors\]$' "$foot" && ! grep -q '^\[colors-dark\]$' "$foot" && ok "foot.ini: foot 1.21 gets [colors] alone" || bad "foot 1.21 section" "$(grep -n '^\[' "$foot")"
    printf '#!/bin/sh\n[ "$1" = --version ] && echo "foot version: 1.28.0 (Arch)"\n' > "$HOME/.local/bin/foot"
    sh "$SH" on --yes >/dev/null
    grep -q '^\[colors-dark\]$' "$foot" && ! grep -q '^\[colors\]$' "$foot" && ok "foot.ini: foot 1.28 gets [colors-dark] alone" || bad "foot 1.28 section" "$(grep -n '^\[' "$foot")"
    grep -q '^client.focused *#ff5555 ' "$sway" && ok "sway: client.focused takes the accent's hex (#ff5555)" || bad "sway focused" "$(grep -n client "$sway")"
    grep -q "^bindsym \$mod+s exec \$term --app-id spark-dialog -W 60x44 -o pad=24x19 -o colors-dark.background=0f0f0f -o colors-dark.alpha=1.0 -e $REPO/spark-shell dialog chat\$" "$sway" && ok "sway: the Super+s line names the clone's spark-shell" || bad "sway Super+s render" "$(grep -n 'mod+s ' "$sway")"
    grep -q "^exec sh -c '\$term -e $REPO/spark-shell desktop --first; swaymsg exit'\$" "$sway" && ok "sway: the first window's line names the clone's spark-shell" || bad "sway --first render" "$(grep -n '^exec sh' "$sway")"
    grep -q '^output \* bg #000000 solid_color$' "$sway" && grep -q '^gaps inner 8$' "$sway" && grep -q '^gaps outer 12$' "$sway" && grep -q '^alpha=0.85$' "$foot" \
        && ok "sway: the default background is the ground (the palette's background a shade darker), gaps, foot translucent" || bad "sway default bg" "$(grep -n 'output\|gaps' "$sway")"
    grep -q '@[A-Z_0-9]*@' "$foot" "$sway" && bad "a desktop render keeps a placeholder" "$(grep -n '@[A-Z_0-9]*@' "$foot" "$sway" | head -2)" || ok "desktop renders: no placeholder left"
    head -1 "$foot" | grep -q '^# rendered by spark-shell' && head -1 "$sway" | grep -q '^# rendered by spark-shell' && ok "desktop renders: both marked" || bad "desktop markers"
    LC_ALL=C grep -q "[^ -~${tab}]" "$foot" "$sway" && bad "a desktop render is not ASCII" || ok "desktop renders: ASCII"
    printf 'DESKTOP=sway\nFONT=Test Mono:size=14\n' > "$HOME/.config/spark-shell/config"
    sh "$SH" on --yes >/dev/null
    grep -q '^font=Test Mono:size=14$' "$foot" && ok "FONT in the config lands in foot.ini verbatim" || bad "FONT override" "$(grep -n '^font' "$foot")"
    printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"
    sh "$SH" on --yes >/dev/null
    st=$(sh "$SH" status); printf '%s\n' "$st" | grep -q '^  desktop sway .*sway: ready' && ok "status: the desktop row says sway, ready" || bad "status desktop sway" "$(printf '%s\n' "$st" | grep desktop)"
    out=$(sh "$SH" check || true)
    printf '%s\n' "$out" | grep -q '^ok     desktop      sway and foot' && ok "check: desktop ok with the stubs and fresh renders" || bad "check desktop ok" "$out"
    printf '%s\n' "$out" | grep -Eq '^(would|todo|FAIL|warn) +font' && bad "check: a font row fails with DESKTOP=sway" "$out" || ok "check: the font row does not fail with DESKTOP=sway"
    out=$(env -u TEST_TTY -u WAYLAND_DISPLAY sh "$SH" desktop 2>&1 || true)
    printf '%s\n' "$out" | grep -q 'needs a console login (tty1 to tty9): ssh and terminal windows cannot start sway' && ok "desktop: refused with no console tty (ssh)" || bad "desktop no console" "$out"
    out=$(TEST_TTY=/dev/tty1 WAYLAND_DISPLAY=wayland-1 sh "$SH" desktop 2>&1 || true)
    printf '%s\n' "$out" | grep -q '^no saved layouts yet' && ok "desktop: inside a desktop (WAYLAND_DISPLAY set) it lists the saved layouts, none yet" || bad "desktop inside" "$out"
    out=$(env -u WAYLAND_DISPLAY TEST_TTY=/dev/tty1 TERM=linux sh "$SH" desktop 2>&1); st=$?
    [ "$st" -eq 0 ] && grep -q 'sway-stub' "$HOME/.local/state/spark-shell/sway.log" && printf '%s' "$out" | od -c | grep -q '033   \[   ?   2   5   h' \
        && ok "desktop: runs sway as a child, its stderr in sway.log, the cursor back on TERM=linux" || bad "desktop run" "st=$st out=$out log=$(cat "$HOME/.local/state/spark-shell/sway.log" 2>&1)"
    out=$(SWAYSOCK=/nonexistent sh "$SH" on --yes)
    printf '%s\n' "$out" | grep -q '^ok     sway         reloaded' && ok "on: swaymsg reload when SWAYSOCK is set" || bad "sway reload" "$out"
    rm -f "$H/.local/bin/sway"
    out=$(sh "$SH" check || true)
    printf '%s\n' "$out" | grep -q '^FAIL   desktop      missing: sway -- spark-shell on' && ok "check: FAIL without sway, the remedy is spark-shell on" || bad "check no sway" "$out"
    out=$(env -u WAYLAND_DISPLAY TEST_TTY=/dev/tty1 sh "$SH" desktop 2>&1 || true)
    printf '%s\n' "$out" | grep -q 'not installed: sway' && ok "desktop: refused without sway" || bad "desktop no sway" "$out"
    desktop_stubs
    sh "$SH" off >/dev/null
    [ ! -e "$foot" ] && [ ! -e "$sway" ] && ok "off: both desktop renders are gone" || bad "desktop off" "$(ls -R "$HOME/.config")"
    mkdir -p "$HOME/.config/sway"; printf 'mine\n' > "$sway"
    sh "$SH" off >/dev/null
    grep -q mine "$sway" && ok "off: a sway config of yours (no marker) is left alone" || bad "yours removed"
    sh "$SH" on --yes >/dev/null
    [ -f "$sway.bak" ] && grep -q mine "$sway.bak" && grep -q '^# rendered by spark-shell' "$sway" && ok "on: yours moves to .bak, the render takes its place" || bad "sway backup" "$(ls "$HOME/.config/sway")"
    rm -f "$foot"
    out=$(env -u WAYLAND_DISPLAY TEST_TTY=/dev/tty1 sh "$SH" desktop 2>&1 || true)
    printf '%s\n' "$out" | grep -q 'the sway and foot settings are missing (spark-shell on)' && ok "desktop: refused when a render is missing" || bad "desktop not rendered" "$out"
    # no theme.env: the VGA sixteen, what spark-shell theme none programs
    fresh
    desktop_stubs
    mkdir -p "$HOME/.config/spark-shell"; printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"
    sh "$SH" on --yes >/dev/null
    grep -q '^regular4=0000aa$' "$HOME/.config/foot/foot.ini" && grep -q '^background=000000$' "$HOME/.config/foot/foot.ini" && grep -q '^foreground=aaaaaa$' "$HOME/.config/foot/foot.ini" \
        && ok "no theme.env: foot.ini takes the VGA sixteen (regular4 0000aa, bg 000000, fg aaaaaa)" || bad "vga foot" "$(grep -n '=' "$HOME/.config/foot/foot.ini" | head -6)"
    grep -q '^client.focused *#0000aa ' "$HOME/.config/sway/config" && ok "no theme.env: the accent's hex is its VGA slot (blue, #0000aa)" || bad "vga accent" "$(grep -n client "$HOME/.config/sway/config")"
fi

# --- follow: the login hook re-renders the look when theme.env changed
fresh
theme_fixture '#ff5555'
sh "$SH" on --yes >/dev/null
out=$(sh "$SH" follow)
[ -z "$out" ] && ok "follow: nothing to say right after on (the palette was seen)" || bad "follow after on" "$out"
theme_fixture '#ee8800'
out=$(sh "$SH" follow)
printf '%s\n' "$out" | grep -q '^spark-shell: [0-9]* files updated for the new palette\.$' && grep -q 'fg=colour3,bold' "$HOME/.tmux.conf" && grep -q "SPARK_ACCENT_SGR='1;33'" "$HOME/.config/spark-shell/sgr.sh" \
    && ok "follow: a changed palette re-renders the look, one line says so" || bad "follow changed" "$out"
out=$(sh "$SH" follow)
[ -z "$out" ] && ok "follow: quiet when the palette did not change since" || bad "follow quiet" "$out"
rm -f "$HOME/.config/spark/theme.env"
out=$(sh "$SH" follow)
printf '%s\n' "$out" | grep -q 'updated for the new palette' && grep -q 'fg=colour4,bold' "$HOME/.tmux.conf" && ok "follow: theme none (no theme.env) is a change too" || bad "follow none" "$out"
grep -q 'spark-shell follow' "$REPO/templates/linux/.bash_profile" && grep -q 'spark-shell follow' "$REPO/templates/macos/.zprofile" && ok "the login profiles run spark-shell follow" || bad "profiles follow"

# --- the wallpaper: a verb that sets and applies; gaps and a translucent foot
if [ "$(uname -s)" != Darwin ]; then
    fresh; desktop_stubs
    mkdir -p "$HOME/.config/spark-shell"; printf 'DESKTOP=sway\nPROMPT_STYLE=full\n' > "$HOME/.config/spark-shell/config"
    theme_fixture '#ff5555'
    sh "$SH" on --yes >/dev/null
    sway=$HOME/.config/sway/config; foot=$HOME/.config/foot/foot.ini
    out=$(sh "$SH" desktop wallpaper)
    printf '%s\n' "$out" | grep -q "^wallpaper default -- the ground, the palette's background a shade darker (#000000); it follows the palette\$" && ok "desktop wallpaper (bare): the default is the forge" || bad "wallpaper bare default" "$out"
    [ ! -e "$REPO/wallpapers" ] && ok "wallpapers/: no picture ships with the repo; the ground is the default" || bad "wallpapers dir" "$(ls "$REPO/wallpapers")"
    sh "$SH" desktop wallpaper none >/dev/null
    grep -q '^output \* bg #000000 solid_color$' "$sway" && grep -q '^gaps inner 0$' "$sway" && grep -q '^gaps outer 0$' "$sway" && grep -q '^alpha=1.0$' "$foot" \
        && ok "wallpaper none: the palette's color, no gaps, foot opaque" || bad "wallpaper none render" "$(grep -n 'bg\|gaps' "$sway"; grep -n alpha "$foot")"
    out=$(sh "$SH" desktop wallpaper)
    printf '%s\n' "$out" | grep -q '^wallpaper none' && ok "desktop wallpaper (bare): says none" || bad "wallpaper bare" "$out"
    sh "$SH" desktop wallpaper default >/dev/null
    grep -q '^WALLPAPER=default$' "$HOME/.config/spark-shell/config" && grep -q '^output \* bg #000000 solid_color$' "$sway" && grep -q '^gaps inner 8$' "$sway" && ok "desktop wallpaper default: the ground again" || bad "wallpaper default" "$(grep -n 'bg\|gaps' "$sway")"
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
    out=$(sh "$SH" on --yes)
    printf '%s\n' "$out" | grep -q '^todo   wallpaper .*is missing' && grep -q '^output \* bg #000000 solid_color$' "$sway" && grep -q '^alpha=1.0$' "$foot" \
        && ok "a picture that went missing: a todo row, the palette's color, never a black screen" || bad "missing wallpaper" "$out"
    st=$(sh "$SH" status); printf '%s\n' "$st" | grep -q '^  wall  missing' && ok "status: wall missing" || bad "status wall missing" "$(sh "$SH" status | grep wall)"
    rc=0; out=$(sh "$SH" desktop wallpaper /nowhere/at/all.jpg 2>&1) || rc=$?
    [ $rc = 1 ] && printf '%s\n' "$out" | grep -q 'not a readable file' && ok "desktop wallpaper: a path that is not there is refused" || bad "wallpaper refuse missing" "$out"
    [ $rc = 1 ] && printf '%s\n' "$out" | grep -q '^spark-shell desktop: /nowhere/at/all.jpg is not a readable file or a color\. Give a picture.s path, default, none, one of the wallpapers (skyline, fjord, forest, sunset, hills, dunes, ripples, contours, morning, embers), #rrggbb or one of these colors: black, white, gray, silver, navy, blue, teal, green, olive, maroon, red, purple, brown, orange$' \
        && [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 1 ] && ok "desktop wallpaper: the refusal is one line that lists what is accepted" || bad "wallpaper refusal words" "$out"
    # a path from where you are, and a quoted ~: saved as the full path
    printf x > "$pic"; printf x > "$HOME/pictures/two.png"
    rc=0; out=$(cd "$HOME/pictures" && sh "$SH" desktop wallpaper two.png 2>&1) || rc=$?
    full=$(cd "$HOME/pictures" && pwd)/two.png
    [ $rc = 0 ] && grep -qxF "WALLPAPER=$full" "$HOME/.config/spark-shell/config" && grep -qxF "output * bg \"$full\" fill" "$sway" \
        && ok "desktop wallpaper x.png: a path from where you are is saved as the full path" || bad "wallpaper relative" "rc=$rc $out $(grep WALLPAPER "$HOME/.config/spark-shell/config")"
    rc=0; out=$(cd "$HOME" && sh "$SH" desktop wallpaper ./pictures/../pictures/two.png 2>&1) || rc=$?
    [ $rc = 0 ] && grep -qxF "WALLPAPER=$full" "$HOME/.config/spark-shell/config" && ok "desktop wallpaper ./a/../a/x.png: the dots are resolved" || bad "wallpaper dots" "rc=$rc $out $(grep WALLPAPER "$HOME/.config/spark-shell/config")"
    tl='~'   # a literal ~, on purpose: what a quoted one gives spark-shell
    rc=0; out=$(sh "$SH" desktop wallpaper "$tl/pictures/one two.jpg" 2>&1) || rc=$?
    [ $rc = 0 ] && grep -qxF "WALLPAPER=$HOME/pictures/one two.jpg" "$HOME/.config/spark-shell/config" && ok "desktop wallpaper '~/x.jpg': a quoted ~ is your home" || bad "wallpaper tilde" "rc=$rc $out $(grep WALLPAPER "$HOME/.config/spark-shell/config")"
    rc=0; out=$(sh "$SH" desktop wallpaper '~' 2>&1) || rc=$?
    rc2=0; out2=$(sh "$SH" desktop wallpaper "$HOME/pictures" 2>&1) || rc2=$?
    [ $rc = 1 ] && [ $rc2 = 1 ] && printf '%s\n' "$out" "$out2" | grep -c 'is not a readable file' | grep -qx 2 && ok "desktop wallpaper: a directory is not a picture (~ alone too)" || bad "wallpaper dir" "$out $out2"
    rm -f "$pic"
    # a plain color: #rrggbb or a name, saved as #rrggbb; it never follows the palette
    out=$(sh "$SH" desktop wallpaper navy)
    grep -qx 'WALLPAPER=#000080' "$HOME/.config/spark-shell/config" && grep -q '^output \* bg #000080 solid_color$' "$sway" && grep -q '^gaps inner 8$' "$sway" && grep -q '^gaps outer 12$' "$sway" && grep -q '^alpha=0.85$' "$foot" && grep -q '^        background #000000d9$' "$sway" \
        && ok "desktop wallpaper navy: #000080 in the config, sway paints it solid, with the gaps and the translucent foot and bar a picture has" || bad "wallpaper navy" "$out $(grep -n 'bg\|gaps\|background' "$sway"; grep -n alpha "$foot")"
    [ "$(printf '%s\n' "$out" | tail -1)" = "a running sway shows #000080 now, and it stays when the palette changes -- a new foot window is translucent over it, as over a picture" ] && ok "desktop wallpaper navy: says what happens" || bad "wallpaper navy words" "$out"
    [ "$(sh "$SH" desktop wallpaper)" = "wallpaper #000080 -- a plain color, it stays when the palette changes" ] && ok "desktop wallpaper (bare): names the color" || bad "wallpaper bare color" "$(sh "$SH" desktop wallpaper)"
    st=$(sh "$SH" status); printf '%s\n' "$st" | grep -q '^  wall  color  *#000080, a plain color that stays when the palette changes$' && ok "status: the wall row names the color" || bad "status wall color" "$(printf '%s\n' "$st" | grep wall)"
    printf '%s\n' "$(sh "$SH" on --yes)" | grep -q '^todo   wallpaper' && bad "a color is reported missing" || ok "on: a color is never a missing picture"
    sh "$SH" theme dracula >/dev/null
    grep -q '^output \* bg #000080 solid_color$' "$sway" && grep -q '^background=282a36$' "$foot" && ok "a color stays when the palette changes (foot takes dracula, sway keeps #000080)" || bad "color follows the palette" "$(grep -n 'output' "$sway"; grep -n '^background' "$foot")"
    sh "$SH" desktop wallpaper default >/dev/null
    grep -q '^output \* bg #1c1e26 solid_color$' "$sway" && grep -q '^gaps inner 8$' "$sway" && grep -q '^alpha=0.85$' "$foot" && ok "desktop wallpaper default: the ground follows the palette (dracula's background a shade darker, #1c1e26)" || bad "ground dracula" "$(grep -n 'bg\|gaps' "$sway")"
    [ "$(sh "$SH" desktop wallpaper)" = "wallpaper default -- the ground, the palette's background a shade darker (#1c1e26); it follows the palette" ] && ok "desktop wallpaper (bare): names the ground and its hex" || bad "wallpaper bare ground" "$(sh "$SH" desktop wallpaper)"
    theme_fixture '#ff5555'   # the fixture's palette again, for the rows below
    for c in black:000000 white:ffffff gray:808080 grey:808080 silver:c0c0c0 navy:000080 blue:0000ff teal:008080 green:008000 olive:808000 maroon:800000 red:ff0000 purple:800080 brown:a52a2a orange:ffa500 Teal:008080; do
        sh "$SH" desktop wallpaper "${c%%:*}" >/dev/null && grep -qx "WALLPAPER=#${c#*:}" "$HOME/.config/spark-shell/config" || printf '%s\n' "$c"
    done > "$H/names.bad"
    [ ! -s "$H/names.bad" ] && ok "desktop wallpaper NAME: the 15 names are the CSS colors" || bad "wallpaper names" "$(cat "$H/names.bad")"
    # the wallpapers spark-shell ships (issue 10): stored by name, drawn from the clone's own file
    sh "$SH" desktop wallpaper skyline >/dev/null
    grep -qx 'WALLPAPER=skyline' "$HOME/.config/spark-shell/config" && grep -qF "output * bg \"$REPO/wallpaper/skyline.png\" fill" "$sway" && grep -q '^gaps inner 8$' "$sway" \
        && [ "$(sh "$SH" desktop wallpaper)" = "wallpaper skyline" ] \
        && ok "desktop wallpaper skyline: the name in the config, sway draws the clone's own picture with the gaps a picture has" || bad "wallpaper shipped" "$(grep WALLPAPER "$HOME/.config/spark-shell/config"); $(grep -n ' bg ' "$sway")"
    sh "$SH" desktop wallpaper default >/dev/null
    sh "$SH" desktop wallpaper '#ABCdef' >/dev/null
    grep -qx 'WALLPAPER=#abcdef' "$HOME/.config/spark-shell/config" && grep -q '^output \* bg #abcdef solid_color$' "$sway" && ok "desktop wallpaper #ABCdef: saved and drawn as #abcdef" || bad "wallpaper hex" "$(grep WALLPAPER "$HOME/.config/spark-shell/config")"
    for w in chartreuse '#12345' '#1234567' 'abcdef' '#ggg000'; do
        rc=0; out=$(sh "$SH" desktop wallpaper "$w" 2>&1) || rc=$?
        [ $rc = 1 ] && printf '%s\n' "$out" | grep -q 'is not a readable file or a color' || printf '%s\n' "$w"
    done > "$H/words.bad"
    [ ! -s "$H/words.bad" ] && grep -qx 'WALLPAPER=#abcdef' "$HOME/.config/spark-shell/config" && ok "desktop wallpaper: a word that is no color is refused, the config untouched" || bad "wallpaper bad colors" "$(cat "$H/words.bad")"
    out=$(sh "$SH" desktop wallpaper none)
    grep -q '^WALLPAPER=none$' "$HOME/.config/spark-shell/config" && grep -q '^output \* bg #000000 solid_color$' "$sway" && grep -q '^gaps inner 0$' "$sway" && grep -q '^alpha=1.0$' "$foot" \
        && ok "desktop wallpaper none: the palette's background is back" || bad "wallpaper none" "$out"
    printf 'DESKTOP=none\n' > "$HOME/.config/spark-shell/config"
    rc=0; out=$(sh "$SH" desktop wallpaper "$HOME/.config/spark-shell/config" 2>&1) || rc=$?
    [ $rc = 1 ] && printf '%s\n' "$out" | grep -q 'spark-shell on desktop first' && ok "desktop wallpaper: refused without the desktop" || bad "wallpaper without desktop" "$out"
    printf 'DESKTOP=sway\nALPHA=0.7\n' > "$HOME/.config/spark-shell/config"; sh "$SH" on --yes >/dev/null
    grep -q '^alpha=0.7$' "$foot" && ok "ALPHA in the config lands in foot.ini" || bad "alpha key" "$(grep -n alpha "$foot")"
    sed 's/^ALPHA=.*/ALPHA=2/' "$HOME/.config/spark-shell/config" > "$HOME/c.tmp"; mv "$HOME/c.tmp" "$HOME/.config/spark-shell/config"
    rc=0; out=$(sh "$SH" on --yes 2>&1) || rc=$?
    [ $rc = 1 ] && printf '%s\n' "$out" | grep -q 'ALPHA=2' && ok "ALPHA outside 0..1 is refused in one line" || bad "alpha refuse" "$out"
fi
grep -q '@FONT@' "$REPO/templates/.config/foot/foot.ini" && grep -q '@FOOT_ALPHA@' "$REPO/templates/.config/foot/foot.ini" \
    && grep -q 'output \* bg @WALL_BG@' "$REPO/templates/.config/sway/config" && grep -q '^gaps inner @GAPS_INNER@' "$REPO/templates/.config/sway/config" \
    && ok "templates: foot.ini and sway/config carry placeholders, the hex and the wallpaper land at render time" || bad "desktop template placeholders"
grep -q '^bar {' "$REPO/templates/.config/sway/config" && grep -q '^    position top' "$REPO/templates/.config/sway/config" && grep -q '^    status_command @REPO@/spark-shell bar status' "$REPO/templates/.config/sway/config" && ok "sway template: a bar at the top, drawn by spark-shell bar status" || bad "sway template: the bar block" "$(grep -n '^bar\|position\|status_command' "$REPO/templates/.config/sway/config")"
grep -q '^xwayland disable$' "$REPO/templates/.config/sway/config" && ok "sway template: xwayland disabled" || bad "sway xwayland"
grep -v '^#' "$REPO/templates/.config/sway/config" | grep -q 'tmux' && bad "sway: a window starts tmux (it runs the login shell)" || ok "sway template: a new foot runs the login shell, never tmux"
grep -q "^exec sh -c '\$term -e @REPO@/spark-shell desktop --first; swaymsg exit'$" "$REPO/templates/.config/sway/config" && ok "sway template: the desktop ends with its first terminal (desktop --first: the keys once, then your shell)" || bad "sway template: exec line" "$(grep -n '^exec' "$REPO/templates/.config/sway/config")"
sway_t=$REPO/templates/.config/sway/config
grep -q '^bindsym \$mod+s exec \$term --app-id spark-dialog -W @PANEL_SIZE@ -o pad=@PANEL_PAD@ -o @FOOT_COLORS@.background=@PANEL_BG@ -o @FOOT_COLORS@.alpha=1.0 -e @REPO@/spark-shell dialog chat$' "$sway_t" && ok "sway template: Super+s opens spark chat in the panel's window (the AI one key away)" || bad "sway template: Super+s" "$(grep -n 'mod+s ' "$sway_t")"
! grep -q 'spark-chat\|mod+p ' "$sway_t" && ok "sway template: no chat window of its own and no Super+p: one window, two keys" || bad "sway template: old keys" "$(grep -n 'spark-chat\|mod+p ' "$sway_t")"
grep -q '^bindsym \$mod+Shift+s layout stacking$' "$sway_t" && ! grep -q '^bindsym \$mod+s layout' "$sway_t" && ok "sway template: stacking moved to Super+Shift+s, Super+s is spark's" || bad "sway template: stacking key" "$(grep -n 'layout stacking' "$sway_t")"

# --- the AI one key away: desktop --chat execs spark chat with the palette's exports (all OSes)
fresh
cat > "$H/.local/bin/spark" <<'EOF'
#!/bin/sh
{ printf '%s\n' "$@"; echo "SPARK_ACCENT_SGR=${SPARK_ACCENT_SGR:-unset}"; } > "$HOME/spark.argv"
EOF
chmod +x "$H/.local/bin/spark"
theme_fixture '#ff5555'
sh "$SH" on --yes >/dev/null
st=0; out=$(sh "$SH" desktop --chat 2>&1) || st=$?
[ "$st" -eq 0 ] && [ "$(head -1 "$H/spark.argv")" = chat ] && grep -q "^SPARK_ACCENT_SGR=1;91$" "$H/spark.argv" \
    && ok "desktop --chat (the old Super+s): execs spark chat, sgr.sh sourced first (the accent's SGR 1;91 reaches it)" || bad "desktop --chat" "st=$st $out $(cat "$H/spark.argv" 2>&1)"
rm -f "$H/spark.argv"; st=0; out=$(sh "$SH" panel spark chat 2>&1) || st=$?
[ "$st" -eq 0 ] && [ "$(head -1 "$H/spark.argv")" = chat ] && ok "panel spark chat: the row's step execs spark chat the same way" || bad "panel spark chat" "st=$st $out $(cat "$H/spark.argv" 2>&1)"
mv "$H/.local/bin/spark" "$H/spark.away"
st=0; out=$(PATH=$H/.local/bin:$sys sh "$SH" desktop --chat 2>&1 </dev/null) || st=$?
[ "$st" -eq 0 ] && printf '%s\n' "$out" | grep -q '^spark is not installed, so there is no chat' && printf '%s\n' "$out" | grep -q 'Enter closes' \
    && ok "desktop --chat without spark: the window says so and waits for Enter, exit 0" || bad "desktop --chat no spark" "st=$st $out"
st=0; out=$(PATH=$H/.local/bin:$sys sh "$SH" panel chat 2>&1 </dev/null) || st=$?
[ "$st" -eq 0 ] && printf '%s\n' "$out" | grep -q '^spark is not installed, so there is no chat' && ok "panel chat without spark: the same line, exit 0" || bad "panel chat no spark" "st=$st $out"

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
[ "$out" = shell-stub ] && [ -f "$H/.local/state/spark-shell/desktop.seen" ] && [ "$(printf '%s\n' "$out" | tail -1)" = shell-stub ] \
    && ok "desktop --first: the stamp written, no card in the shell (the splash is a window, when there is one), then the shell" || bad "desktop --first" "$out"
out=$(SHELL=$H/.local/bin/shellstub sh "$SH" desktop --first)
[ "$out" = shell-stub ] && [ ! -f "$H/first.splash" ] && ok "desktop --first again: the shell alone" || bad "desktop --first twice" "$out"
printf '#!/bin/sh\necho "${PROMPT-unset} ${DESKTOP-unset} ${FONT-unset}"\n' > "$H/.local/bin/envstub"; chmod +x "$H/.local/bin/envstub"
out=$(SHELL=$H/.local/bin/envstub sh "$SH" desktop --first)
[ "$out" = 'unset unset unset' ] && ok "desktop --first: the config's exports (PROMPT, DESKTOP, FONT) never reach your shell" || bad "desktop --first env" "$out"

# --- 15. the login screen: getty's own, a login on tty1 starts the desktop
# No root file and no unit for the desktop on Debian or Arch: on desktop
# writes DESKTOP=sway and renders sway and foot, and the rc file starts
# the desktop at a login on tty1. systemctl is a stub that logs (it must
# never be asked for greetd). The tty is the stub fresh puts on PATH.
fresh
desktop_stubs
theme_fixture '#ff5555'
mkdir -p "$HOME/.config/spark-shell"
printf 'PROMPT_STYLE=full\nDESKTOP=none\n' > "$HOME/.config/spark-shell/config"
st=$(PATH=$H/.local/bin:$sys sh "$SH" status); printf '%s\n' "$st" | grep -q '^  next  spark .*Install spark, the local AI: github.com/forgewright-ai/spark\.$' && ok "status: next says install spark first, without spark on PATH" || bad "status next spark" "$(printf '%s\n' "$st" | grep next)"
if [ "$(uname -s)" = Darwin ]; then
    st=0; out=$(sh "$SH" on desktop --yes 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$(printf '%s\n' "$out" | wc -l)" -eq 1 ] && printf '%s\n' "$out" | grep -q '^spark-shell desktop: not on macOS' \
        && ok "macOS: on desktop refuses, one line, exit 1" || bad "macOS on desktop" "st=$st $out"
    grep -q 'DESKTOP=none' "$HOME/.config/spark-shell/config" && [ ! -e "$H/root/etc" ] && ok "macOS: on desktop wrote nothing" || bad "macOS on desktop wrote" "$(cat "$HOME/.config/spark-shell/config")"
else
    printf '#!/bin/sh\necho "$*" >> "%s/units.log"\n[ "$1" != is-enabled ] || exit 1\n' "$H" > "$H/.local/bin/systemctl"; chmod +x "$H/.local/bin/systemctl"
    out=$(sh "$SH" on desktop --dry-run)
    printf '%s\n' "$out" | grep -q '^would  config       DESKTOP=sway' && printf '%s\n' "$out" | grep -q '^would  look .*sway/config' \
        && ok "on desktop --dry-run: would write DESKTOP=sway and render sway" || bad "on desktop dry-run rows" "$out"
    grep -q 'DESKTOP=none' "$HOME/.config/spark-shell/config" && [ ! -e "$H/root/etc" ] && [ ! -e "$H/.config/sway" ] && ok "on desktop --dry-run: wrote nothing (the config kept)" || bad "on desktop dry-run wrote" "$(find "$H/root" "$H/.config")"
    printf '%s\n' "$out" | grep -Eq '^(would|todo|FAIL|warn) +font' && bad "on desktop --dry-run acts on a font" "$out" || ok "on desktop --dry-run: no font row acts"
    out2=$(sh "$SH" desktop on --dry-run)
    [ "$out2" = "$out" ] && ok "desktop on is on desktop: the same dry run, row for row" || bad "desktop on alias" "$out2"
    out=$(sh "$SH" on desktop --yes 2>&1); st=$?
    [ "$st" -eq 0 ] && grep -q '^DESKTOP=sway$' "$HOME/.config/spark-shell/config" && grep -q '^PROMPT_STYLE=full$' "$HOME/.config/spark-shell/config" \
        && [ "$(grep -c '^DESKTOP=' "$HOME/.config/spark-shell/config")" -eq 1 ] \
        && ok "on desktop: DESKTOP=sway written into the config, the other line kept" || bad "on desktop config" "st=$st $(cat "$HOME/.config/spark-shell/config")"
    [ -f "$HOME/.config/foot/foot.ini" ] && [ -f "$HOME/.config/sway/config" ] && ok "on desktop: foot.ini and sway/config rendered" || bad "on desktop user renders" "$out"
    [ ! -e "$H/root/etc/greetd" ] && [ ! -e "$H/root/etc/systemd" ] && ! grep -q 'greetd\|getty' "$H/units.log" 2>/dev/null \
        && ok "on desktop: no root file, no greetd, getty left alone" || bad "on desktop root" "$(find "$H/root" 2>&1; cat "$H/units.log" 2>&1)"
    printf '%s\n' "$out" | grep -qi 'greet\|login box' && bad "on desktop names greetd or a login box" "$out" || ok "on desktop: no word of greetd or a login box"
    st=$(sh "$SH" status); printf '%s\n' "$st" | grep -q '^  desktop sway .*(log in on tty1 to start it)$' && ok "status: the desktop row says log in on tty1 to start it" || bad "status desktop row" "$(printf '%s\n' "$st" | grep desktop)"
    printf '#!/bin/sh\n:\n' > "$H/.local/bin/spark"; chmod +x "$H/.local/bin/spark"
    st=$(env -u WAYLAND_DISPLAY sh "$SH" status); printf '%s\n' "$st" | grep -q '^  next' && bad "status: a next row with nothing off" "$(printf '%s\n' "$st" | grep next)" || ok "status: no next row when the desktop is ready (Debian, Arch: no reboot, no root)"
    rm -f "$H/.local/bin/spark"
    out=$(sh "$SH" check || true)
    printf '%s\n' "$out" | grep -q '^ok     desktop      sway and foot' && ! printf '%s\n' "$out" | grep -q 'greeter' && ok "check: ok desktop, no greeter row" || bad "check desktop" "$out"
    out=$(sh "$SH" on --dry-run)
    printf '%s\n' "$out" | grep -q '^Nothing to do$' && ok "on --dry-run after on desktop: Nothing to do" || bad "on desktop idempotence" "$out"
    out=$(sh "$SH" off desktop --dry-run)
    printf '%s\n' "$out" | grep -q '^would  config       DESKTOP=none' && printf '%s\n' "$out" | grep -q '^would  restore .*sway/config' && printf '%s\n' "$out" | grep -q '^would  restore .*foot/foot\.ini' \
        && ok "off desktop --dry-run: would rows for the config and the two renders" || bad "off desktop dry-run rows" "$out"
    grep -q '^DESKTOP=sway$' "$HOME/.config/spark-shell/config" && [ -f "$HOME/.config/sway/config" ] && ok "off desktop --dry-run: touched nothing" || bad "off desktop dry-run wrote" "$(cat "$HOME/.config/spark-shell/config")"
    out=$(sh "$SH" off desktop)
    grep -q '^DESKTOP=none$' "$HOME/.config/spark-shell/config" && grep -q '^PROMPT_STYLE=full$' "$HOME/.config/spark-shell/config" && ok "off desktop: DESKTOP=none written, the other line kept" || bad "off desktop config" "$(cat "$HOME/.config/spark-shell/config")"
    [ ! -e "$HOME/.config/foot/foot.ini" ] && [ ! -e "$HOME/.config/sway/config" ] && ok "off desktop: the two user renders are gone" || bad "off desktop user renders" "$(ls -R "$HOME/.config")"
    printf '%s\n' "$out" | grep -q 'packages stay installed' && ok "off desktop: packages stay, said so" || bad "off desktop closing" "$out"
    out=$(sh "$SH" desktop off)
    printf '%s\n' "$out" | grep -Eq '^ok +(login|desktop|restore) ' && bad "desktop off (a spelling of off desktop) twice acts twice" "$out" || ok "desktop off, the spelling, twice: nothing to undo, nothing said"
    # the old login screen, still running until the next boot, runs `desktop` on Enter: your shell
    printf '#!/bin/sh\necho "shell-stub $* ${DESKTOP-unset}"\n' > "$H/.local/bin/offshell"; chmod +x "$H/.local/bin/offshell"
    st=0; out=$(TEST_TTY=/dev/tty1 SHELL=$H/.local/bin/offshell env -u WAYLAND_DISPLAY sh "$SH" desktop 2>&1) || st=$?
    [ "$st" -eq 0 ] && printf '%s\n' "$out" | grep -q '^The desktop is off (spark-shell on desktop brings it back)\. This is your shell\.$' && [ "$(printf '%s\n' "$out" | tail -1)" = 'shell-stub -l unset' ] \
        && ok "desktop with the desktop off, from a console: one line, then your login shell (never a dead end)" || bad "desktop off console landing" "st=$st $out"
    # no theme.env: the desktop still starts from a console, and a word with no console is refused
    fresh; desktop_stubs
    sh "$SH" on desktop --yes >/dev/null
    out=$(TEST_TTY=/dev/tty1 env -u WAYLAND_DISPLAY sh "$SH" desktop 2>&1); st=$?
    [ "$st" -eq 0 ] && ok "desktop (start now) starts sway from a console" || bad "desktop start" "$out"
    out=$(env -u TEST_TTY -u SWAYSOCK sh "$SH" desktop sideways --windows 2>&1 || true)
    printf '%s\n' "$out" | grep -q '^spark-shell desktop: needs a console login' && [ ! -e "$HOME/.local/state/spark-shell/desk.pending" ] \
        && ok "desktop --windows: a word with no desktop and no console is refused in one line, nothing left pending" || bad "desktop word no console" "$out"
fi
[ ! -e "$REPO/templates/etc/greetd" ] && [ ! -e "$REPO/templates/etc/systemd/system/greetd.service.d" ] && [ -f "$REPO/templates/etc/systemd/system/spark-shell-console.service" ] \
    && ok "templates/etc: no greetd file, the console palette's unit stays" || bad "templates/etc greetd" "$(find "$REPO/templates/etc" -type f)"
grep -q 'PKG_GREETER' "$REPO"/distro/*.env && bad "distro/*.env: a PKG_GREETER line" || ok "distro/*.env: no greeter packages"
grep -rq 'font' "$REPO/templates/etc" && bad "a root template names a font" || ok "templates/etc: no font word"
grep -v '^ *#' "$SH" | grep -q 'XDG_VTNR\|tuigreet\|greet_background' && bad "spark-shell reads XDG_VTNR or draws tuigreet" "$(grep -n 'XDG_VTNR\|tuigreet' "$SH" | grep -v ':[ ]*#' | head -3)" || ok "spark-shell: no XDG_VTNR, no tuigreet in the code (the tty says console)"

# the rc file: a login on tty1 starts the desktop, nothing else does.
# The block is run alone in an interactive bash, with stubs for tty and
# spark-shell; `exit` after a desktop that ran ends that login.
bp=$REPO/templates/linux/.bash_profile
awk '/^# The desktop at a login on tty1/ {on = 1} on {print} on && /^fi$/ {exit}' "$bp" > "$H/autostart.sh"
grep -q '"\$(tty 2>/dev/null)" = /dev/tty1' "$H/autostart.sh" && grep -q 'spark-shell desktop && exit' "$H/autostart.sh" && grep -q 'WAYLAND_DISPLAY' "$H/autostart.sh" \
    && ok ".bash_profile: one block, tty1 exactly, no WAYLAND_DISPLAY, then spark-shell desktop" || bad ".bash_profile block" "$(cat "$H/autostart.sh")"
l_pal=$(grep -n 'console-colors' "$bp" | head -1 | cut -d: -f1); l_auto=$(grep -n '^# The desktop at a login on tty1' "$bp" | cut -d: -f1)
[ -n "$l_pal" ] && [ -n "$l_auto" ] && [ "$l_auto" -gt "$l_pal" ] && ok ".bash_profile: the desktop starts after the palette lines" || bad ".bash_profile order" "palette $l_pal desktop $l_auto"
if command -v bash >/dev/null 2>&1; then
    ab=$H/ab; mkdir -p "$ab/bin" "$ab/.config/spark-shell"
    printf '#!/bin/sh\necho "${TEST_TTY:-not a tty}"\n[ -n "${TEST_TTY:-}" ]\n' > "$ab/bin/tty"
    printf '#!/bin/sh\necho "spark-shell $*" >> "%s/ran"\n[ ! -e "%s/fails" ]\n' "$ab" "$ab" > "$ab/bin/spark-shell"
    chmod +x "$ab/bin/tty" "$ab/bin/spark-shell"
    autostart() {   # autostart TTY DESKTOP [VAR=VALUE] -> what ran, then "after" when the shell went on
        rm -f "$ab/ran"; printf 'DESKTOP=%s\n' "$2" > "$ab/.config/spark-shell/config"
        env -u WAYLAND_DISPLAY HOME="$ab" XDG_CONFIG_HOME="$ab/.config" TEST_TTY="$1" PATH="$ab/bin:$PATH" ${3:+"$3"} \
            bash --norc --noprofile -i -c ". '$H/autostart.sh'; echo after" 2>/dev/null </dev/null
        cat "$ab/ran" 2>/dev/null || true
    }
    [ "$(autostart /dev/tty1 sway)" = 'spark-shell desktop' ] && ok ".bash_profile: a login on tty1 with DESKTOP=sway starts the desktop, and leaving it ends the login" || bad "autostart tty1" "$(autostart /dev/tty1 sway)"
    [ "$(autostart /dev/tty2 sway)" = after ] && ok ".bash_profile: tty2 (Alt+F2) stays a plain shell" || bad "autostart tty2" "$(autostart /dev/tty2 sway)"
    [ "$(autostart /dev/tty10 sway)" = after ] && ok ".bash_profile: tty10 is not tty1" || bad "autostart tty10" "$(autostart /dev/tty10 sway)"
    [ "$(autostart /dev/pts/0 sway)" = after ] && ok ".bash_profile: ssh and terminal windows (/dev/pts) never start it" || bad "autostart pts" "$(autostart /dev/pts/0 sway)"
    [ "$(autostart /dev/tty1 none)" = after ] && ok ".bash_profile: DESKTOP=none on tty1 is a plain shell" || bad "autostart none" "$(autostart /dev/tty1 none)"
    [ "$(autostart /dev/tty1 sway WAYLAND_DISPLAY=wayland-1)" = after ] && ok ".bash_profile: inside a desktop it never starts another" || bad "autostart wayland" "$(autostart /dev/tty1 sway WAYLAND_DISPLAY=wayland-1)"
    : > "$ab/fails"
    [ "$(autostart /dev/tty1 sway | paste -sd' ' -)" = 'after spark-shell desktop' ] && ok ".bash_profile: a desktop that cannot start leaves its reason and the shell goes on" || bad "autostart fails" "$(autostart /dev/tty1 sway)"
fi

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
if [ -e "$HOME/answer.json" ]; then cat "$HOME/answer.json"   # a test's own answer
elif [ -e "$HOME/two-screens" ]; then cat <<'JSON'
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
                printf '{"type":"root","nodes":[{"type":"workspace","num":%s,"fullscreen_mode":0,"nodes":[' "$num"
                # with $HOME/fullscreen: a fullscreen window (77) on the workspace, and the panel floating under it with the pid the test wrote
                [ ! -e "$HOME/aerc" ] || { printf '{"type":"con","id":79,"pid":300,"app_id":"foot","name":"aerc"}'; { [ -e "$HOME/fullscreen" ] || [ "$n" -gt 0 ]; } && printf ','; }   # a terminal running aerc
                [ ! -e "$HOME/fullscreen" ] || { printf '{"type":"con","id":77,"pid":200,"app_id":"firefox","fullscreen_mode":1}'; [ "$n" -eq 0 ] || printf ','; }
                while [ "$i" -lt "$n" ]; do [ "$i" -eq 0 ] || printf ','; printf '{"type":"con","pid":%d}' $((100 + i)); i=$((i + 1)); done
                printf ']'
                [ ! -e "$HOME/fullscreen" ] || printf ',"floating_nodes":[{"type":"floating_con","id":78,"app_id":"spark-dialog","pid":%s,"fullscreen_mode":0}]' "$(cat "$HOME/panel.ppid" 2>/dev/null || echo 1)"
                echo '}]}' ;;
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
desks=$H/.config/spark-shell/layouts
theme_fixture '#ff5555'
mkdir -p "$HOME/.config/spark-shell"; printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"
sh "$SH" on --yes >/dev/null
if [ "$(uname -s)" = Darwin ]; then
    na_form() {   # na_form WORDS... -> one line, na, exit 1
        st=0; out=$(sh "$SH" desktop "$@" 2>&1) || st=$?
        [ "$st" -eq 1 ] && [ "$(printf '%s\n' "$out" | wc -l)" -eq 1 ] && printf '%s\n' "$out" | grep -q '^spark-shell desktop: not on macOS, which has its own desktop$' \
            && ok "macOS: desktop $1 refuses, na, one line, exit 1" || bad "macOS desktop $*" "st=$st $out"
    }
    na_form apps   # a desk itself plays as rooms here (18)
    [ ! -e "$desk_last" ] && [ ! -e "$desk_pending" ] && [ ! -e "$desks" ] && [ ! -e "$argv" ] && [ ! -e "$swlog" ] \
        && ok "macOS: the picker wrote nothing (no desk.last, no pending, no desks dir, spark and swaymsg never called)" || bad "macOS desk wrote" "$(find "$H/.local/state" "$H/.config/spark-shell")"
else
    export SWAYSOCK=$H/sway.sock WAYLAND_DISPLAY=wayland-1    # inside the desktop
    st=$(sh "$SH" status); printf '%s\n' "$st" | grep -q '^  layouts none .*spark-shell layout "WORDS" makes one' && ok "status: the layouts row says none before any" || bad "status layouts none" "$(printf '%s\n' "$st" | grep layouts)"
    out=$(sh "$SH" layout)
    printf '%s\n' "$out" | grep -q '^no saved layouts yet -- try: spark-shell layout "' && ok "layout (bare): no saved layouts yet, a try line" || bad "layout list empty" "$out"
    # the need: spark asked once, the lines played, the missing app named
    st=0; out=$(sh "$SH" layout "$need" 2>&1) || st=$?
    [ "$st" -eq 0 ] && printf '%s\n' "$out" | grep -q "^layout> $need\$" && printf '%s\n' "$out" | grep -q '^  photo work in gimp with the two feeds' \
        && ok "layout WORDS: exit 0, the layout> line, the why line" || bad "desk need" "st=$st $out"
    printf '%s\n' "$out" | grep -q '^  ghostapp is not on this machine -- laid out without it$' && ok "desktop WORDS: an app the model named that is not here is said" || bad "ghostapp line" "$out"
    printf '%s\n' "$out" | grep -q '^  refused  exec ghostapp  (ghostapp is not on this machine)$' && ok "desktop WORDS: its exec line is refused with the reason" || bad "ghostapp refused" "$out"
    printf '%s\n' "$out" | grep -q '^on workspace 3 -- spark-shell layout save NAME saves it$' && ok "layout WORDS: on workspace 3 (1 and 2 are in use), save named" || bad "on workspace" "$out"
    printf '%s\n' "$out" | grep -q 'no window after\|sway refused' && bad "desktop WORDS: a wait ran out or sway refused" "$out" || ok "desktop WORDS: every window came up, sway took every line"
    [ -f "$argv" ] && [ "$(sed -n '1,3p' "$argv" | paste -sd ' ' -)" = 'edit --type json' ] && grep -qx -- '--name' "$argv" && grep -qx layout.json "$argv" && grep -qx -- '--about' "$argv" \
        && ok "spark: asked as spark edit --type json --name layout.json --about" || bad "spark argv" "$(cat "$argv" 2>&1)"
    [ "$(tail -1 "$argv")" = "write the layout for this need: $need" ] && ok "spark: the prompt ends with the need's words" || bad "spark prompt" "$(tail -1 "$argv")"
    grep -q 'on one screen, 2560x1440\. ' "$argv" && ok "spark: the about says one screen and its size (from swaymsg get_outputs)" || bad "about screen" "$(grep -o 'on one screen[^.]*' "$argv")"
    grep -q 'screen is left\|"screen"' "$argv" && bad "about: the screen rule or field reached the model with one screen" "$(grep -o 'A window is on one screen[^.]*' "$argv")" || ok "spark: one screen, no screen field and no screen rule in the about"
    grep -q 'gimp-3.0: Create images and edit photographs' "$argv" && ok "inventory: a desktop entry's Comment (gimp-3.0)" || bad "inventory gimp" "$(grep -o 'gimp-3.0: [^;]*' "$argv")"
    grep -q 'firefox: Web Browser' "$argv" && ok "inventory: GenericName when there is no Comment (firefox)" || bad "inventory firefox" "$(grep -o 'firefox: [^;]*' "$argv")"
    grep -q 'micro: Micro' "$argv" && ok "inventory: Name when there is nothing else (micro)" || bad "inventory micro" "$(grep -o 'micro: [^;]*' "$argv")"
    grep -q ', terminal' "$argv" && bad "inventory: the terminal mark reached the model" "$(grep -o '[^;]*, terminal[^;]*' "$argv")" || ok "inventory: the terminal mark is kept from the model (sway's business)"
    grep -qi 'hidden' "$argv" && bad "inventory: a NoDisplay entry is in" "$(grep -oi '[^;]*hidden[^;]*' "$argv")" || ok "inventory: a NoDisplay entry is dropped"
    grep -q 'for:' "$argv" && bad "inventory: the keyword for counts as a program" "$(grep -o 'for: [^;]*' "$argv")" || ok "inventory: a need word that is a keyword (for) is not a program"
    grep -q 'foot:\|footclient:\|xdg-open:' "$argv" && bad "inventory: foot or xdg-open is in" || ok "inventory: no foot, footclient or xdg-open"
    printf '%s\n' 'workspace number 3' 'rename workspace to "3 photo editing for"' 'exec gimp-3.0' splith 'exec firefox https://instagram.com' splitv 'exec firefox https://x.com' 'exec foot -e micro' 'exec player --idle --' 'focus left' 'resize set width 70 ppt' > "$H/expected.lines"
    sed 's/^rename workspace to .*/rename workspace to "3 studio"/' "$H/expected.lines" > "$H/expected.studio"   # a saved layout names its workspace after itself
    cmp -s "$swlog" "$H/expected.lines" && ok "sway got exactly the ten lines in order (main, the workspace named after the words, splith, side, splitv, micro in foot, focus left, resize 70 ppt; ghostapp never)" || bad "swaymsg lines" "$(cat "$swlog" 2>&1)"
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
    SPARK_OS_RELEASE=$H/os-arch SWAYSOCK=/tmp/x sh "$SH" layout "$need" >/dev/null 2>&1 || true
    grep -q 'micro: Micro' "$argv" && ! grep -q 'reader:' "$argv" && ! grep -q 'bash:' "$argv" \
        && ok "inventory unmarked: the entries (micro), never a package (reader, bash)" || bad "inventory unmarked" "$(grep -o 'micro: [^;]*\|reader:[^;]*\|bash:[^;]*' "$argv")"
    apps_file=$HOME/.config/spark-shell/apps
    printf '# the apps a desk may open\nreader: my browser\nmicro\nbash\nghost\n' > "$apps_file"
    SPARK_OS_RELEASE=$H/os-arch SWAYSOCK=/tmp/x sh "$SH" layout "$need" >/dev/null 2>&1 || true
    grep -q 'reader: my browser' "$argv" && ok "inventory marked: a package with your note, in your words" || bad "inventory marked note" "$(grep -o 'reader[^;]*' "$argv")"
    grep -q 'micro: Micro' "$argv" && ok "inventory marked: a marked entry in the entry's words" || bad "inventory marked entry" "$(grep -o 'micro[^;]*' "$argv")"
    grep -q 'firefox' "$argv" && bad "inventory marked: an unmarked entry is in" "$(grep -o 'firefox[^;]*' "$argv")" || ok "inventory marked: an unmarked entry (firefox) is out"
    grep -q 'bash:' "$argv" && bad "inventory marked: a shell is offered to the model" "$(grep -o 'bash:[^;]*' "$argv")" || ok "inventory marked: a shell is never offered"
    grep -q 'ghost' "$argv" && bad "inventory marked: a name that is nowhere is in" "$(grep -o 'ghost[^;]*' "$argv")" || ok "inventory marked: a name that is nowhere is silently left out"
    rm -f "$apps_file" "$H/.local/bin/pacman" "$H/.local/bin/reader"
    # the old Super+d spelling: the panel with the layouts first; no terminal, so the list as text
    : > "$swlog"; SEP=$(printf '\302\267'); GO=$(printf '\342\226\270')
    st=0; out=$(SWAYSOCK=/tmp/x sh "$SH" layout --ask </dev/null 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$(printf '%s\n' "$out" | sed -n 1p)" = "layout     none saved yet" ] && [ "$(printf '%s\n' "$out" | sed -n 2p)" = "  layout     none saved yet: say what you want to do at the prompt	layout show" ] && [ ! -s "$swlog" ] \
        && ok "layout --ask: the panel with the layouts first, as text without a terminal; nothing played" || bad "ask form" "st=$st $out $(head -2 "$swlog")"
    printf '%s' "$out" | od -c | grep -q '033' && bad "the pulse reached a pipe" "$(printf '%s' "$out" | od -c | grep 033 | head -1)" || ok "no pulse on a pipe (a tty only, like spark's)"
    # keep, list, replay, status, forget
    out=$(sh "$SH" layout save studio)
    printf '%s\n' "$out" | grep -q "^saved studio -- spark-shell layout studio opens it ($desks/studio)\$" && [ "$(jq -S 'del(.suggested)' "$desk_last")" = "$(jq -S . "$desks/studio")" ] && ! jq -e 'has("suggested")' "$desks/studio" >/dev/null \
        && ok "layout save NAME: desk.last saved as layouts/NAME without what was only suggested, said in one line" || bad "keep" "$out"
    # keep takes all the words; bare keep names the desk after its own words
    out=$(sh "$SH" layout save Photo Work, please)
    printf '%s\n' "$out" | grep -q "^saved photo-work-please -- " && [ -f "$desks/photo-work-please" ] && ok "layout save WORDS: every word, lowercased, joined by -" || bad "keep words" "$out $(ls "$desks")"
    out=$(sh "$SH" layout save)
    printf '%s\n' "$out" | grep -q "^saved photo-editing-for-instagram-and-x -- " && [ -f "$desks/photo-editing-for-instagram-and-x" ] && ok "layout save (bare): named after the layout's own words" || bad "keep bare" "$out $(ls "$desks")"
    rm -f "$desks/photo-work-please" "$desks/photo-editing-for-instagram-and-x"
    out=$(sh "$SH" layout)
    printf '%s\n' "$out" | grep -q "^  studio  *$need\$" && printf '%s\n' "$out" | grep -q '^spark-shell layout NAME opens one -- layout save \[NAME\] saves the last layout, layout delete NAME deletes one$' \
        && ok "layout (bare): lists the saved layout with its words" || bad "desk list" "$out"
    rm -f "$argv" "$swlog"
    st=0; out=$(sh "$SH" layout studio 2>&1) || st=$?
    [ "$st" -eq 0 ] && printf '%s\n' "$out" | grep -q "^layout> $need\$" && printf '%s\n' "$out" | grep -q '^  photo work in gimp' && printf '%s\n' "$out" | grep -q '^on workspace 3 -- the saved layout studio$' && cmp -s "$swlog" "$H/expected.studio" \
        && ok "layout NAME: replays the same lines on the next free workspace (3), named studio, with its why" || bad "replay" "st=$st $out $(cat "$swlog" 2>&1)"
    : > "$swlog"
    st=0; out=$(sh "$SH" layout Studio 2>&1) || st=$?
    [ "$st" -eq 0 ] && head -1 "$swlog" | grep -q '^workspace number 3$' && [ ! -e "$argv" ] && ok "layout WORDS that name a saved layout (any case): a replay, no model" || bad "replay by words" "st=$st $out"
    : > "$swlog"
    st=0; out=$(ASKED=1 SWAYSOCK=/tmp/x sh "$SH" panel layout open studio 2>&1) || st=$?
    [ "$st" -eq 0 ] && head -1 "$swlog" | grep -q '^\[app_id=spark-dialog\] move container to workspace number 3$' && tail -1 "$swlog" | grep -q '^\[app_id=spark-dialog\] focus$' \
        && printf '%s\n' "$out" | grep -q 'photo work in gimp' && ! printf '%s\n' "$out" | grep -q 'layout> ' \
        && ok "a saved layout as a panel step (asked): the panel window follows it and is focused again, the why said, no layout> line" || bad "replay ask" "st=$st $out $(cat "$swlog")"
    st=0; out=$(ASKED=1 SWAYSOCK=/tmp/x sh "$SH" layout "$need" 2>&1) || st=$?
    [ "$st" -eq 0 ] && printf '%s\n' "$out" | grep -q '^on workspace [0-9]*$' && ok "a fresh layout asked from the panel: the closing line names the workspace alone (the panel has its save row)" || bad "asked closing" "st=$st $out"
    rm -f "$argv"   # that one asked spark; the replay tests below must see no call
    out=$(SWAYSOCK=/tmp/x sh "$SH" panel layout --list)
    [ "$(printf '%s\n' "$out" | sed -n 1p)" = "layout     1 saved $SEP last: $need" ] && [ "$(printf '%s\n' "$out" | sed -n 2p)" = "$GO layout     $need	layout open studio" ] \
        && ok "panel layout --list: the count and the last one on the title, a saved layout as a row that opens it by name" || bad "panel layout list" "$out"
    st=0; out=$(SWAYSOCK=/tmp/x sh "$SH" panel layout open nowhere 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = 'spark-shell panel: layout: no saved layout named nowhere' ] && ok "panel layout open NAME: a name that is not saved is refused in one line" || bad "layout open gate" "st=$st $out"
    st=0; out=$(SWAYSOCK=/tmp/x sh "$SH" panel layout new 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = 'spark-shell panel: layout: new takes the words for it' ] && ok "panel layout new: without words, refused in one line" || bad "layout new gate" "st=$st $out"
    [ ! -e "$argv" ] && ok "layout NAME: no model call" || bad "replay called spark" "$(cat "$argv")"
    st=$(sh "$SH" status); printf '%s\n' "$st" | grep -q '^  layouts 1 saved  *studio (spark-shell layout NAME)$' && ok "status: the layouts row counts and names the saved ones" || bad "status layouts" "$(printf '%s\n' "$st" | grep layouts)"
    out=$(sh "$SH" layout delete studio)
    [ "$out" = "deleted studio" ] && [ ! -e "$desks/studio" ] && ok "layout delete NAME: gone, one line" || bad "delete" "$out"
    # a named app twice with the same args is the model's padding: once; main fullscreen fills the screen once the window is there
    mv "$H/.local/bin/spark" "$H/spark.keep"
    printf '#!/bin/sh\nprintf "{\\"why\\": \\"the browser, full\\", \\"main\\": {\\"app\\": \\"firefox\\", \\"args\\": \\"\\", \\"fullscreen\\": true}, \\"side\\": [{\\"app\\": \\"firefox\\", \\"args\\": \\"\\"}]}\\n"\n' > "$H/.local/bin/spark"; chmod +x "$H/.local/bin/spark"
    : > "$swlog"; st=0; out=$(sh "$SH" layout "firefox fullscreen" 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$(grep -c '^exec firefox' "$swlog")" = 1 ] && [ "$(grep -A1 '^exec firefox' "$swlog" | sed -n 2p)" = 'fullscreen enable' ] && ! grep -q '^splith' "$swlog" \
        && ok "layout: firefox named twice opens once; fullscreen true on main sends fullscreen enable right after its window" || bad "layout once full" "st=$st $out $(cat "$swlog")"
    # the words decide what the machine can read in them: fullscreen when they say so (the model said false), and workspace N
    printf '#!/bin/sh\nprintf "{\\"why\\": \\"the editor\\", \\"main\\": {\\"app\\": \\"micro\\", \\"args\\": \\"\\", \\"fullscreen\\": false}, \\"side\\": []}\\n"\n' > "$H/.local/bin/spark"; chmod +x "$H/.local/bin/spark"
    : > "$swlog"; st=0; out=$(sh "$SH" layout "micro workspace 7 fullscreen" 2>&1) || st=$?
    [ "$st" -eq 0 ] && head -1 "$swlog" | grep -q '^workspace number 7$' && grep -q '^fullscreen enable$' "$swlog" && [ "$(jq -r .main.fullscreen "$desk_last")" = true ] \
        && ok "layout WORDS with workspace 7 and fullscreen: that workspace, and fullscreen, by the words themselves (the model had said false)" || bad "words decide" "st=$st $out $(cat "$swlog")"
    # every window tied to words of the need (its quote): notes -> micro stays, firefox stays, a shell for "fullscreen" or for nothing is padding and only suggested
    printf '#!/bin/sh\nprintf "{\\"why\\": \\"notes beside the browser\\", \\"main\\": {\\"app\\": \\"firefox\\", \\"quote\\": \\"Firefox\\", \\"args\\": \\"\\"}, \\"side\\": [{\\"app\\": \\"micro\\", \\"quote\\": \\"notes\\", \\"args\\": \\"\\"}, {\\"app\\": \\"shell\\", \\"quote\\": \\"fullscreen\\", \\"args\\": \\"\\"}, {\\"app\\": \\"btop\\", \\"quote\\": \\"\\", \\"args\\": \\"\\"}, {\\"app\\": \\"player\\", \\"quote\\": \\"some music\\", \\"args\\": \\"\\"}]}\\n"\n' > "$H/.local/bin/spark"; chmod +x "$H/.local/bin/spark"
    : > "$swlog"; st=0; out=$(sh "$SH" layout "notes and Firefox fullscreen" 2>&1) || st=$?
    [ "$st" -eq 0 ] && grep -q '^exec firefox' "$swlog" && grep -q '^exec foot -e micro' "$swlog" && ! grep -q 'btop\|player\|exec foot$' "$swlog" && printf '%s\n' "$out" | grep -q 'also suggested: shell and player' \
        && ok "layout: a window tied to words of the need opens (micro for notes); one tied to the layout's own word, to nothing, or to words the need lacks is padding, only suggested (btop is not even on this list)" || bad "grounded" "st=$st $out $(cat "$swlog")"
    # what spark also suggested is one Enter away: a row per app, opening it on this workspace, gone once taken
    printf '#!/bin/sh\nprintf "{\\"why\\": \\"notes beside the browser\\", \\"main\\": {\\"app\\": \\"firefox\\", \\"args\\": \\"\\"}, \\"side\\": [{\\"app\\": \\"micro\\", \\"args\\": \\"\\"}]}\\n"\n' > "$H/.local/bin/spark"; chmod +x "$H/.local/bin/spark"
    : > "$swlog"; st=0; out=$(sh "$SH" layout "notes and firefox" 2>&1) || st=$?
    [ "$st" -eq 0 ] && printf '%s\n' "$out" | grep -q 'also suggested: micro' && [ "$(jq -r '.suggested | join(",")' "$desk_last")" = micro ] && sh "$SH" panel layout --list | grep -q "also open micro	layout add micro$" \
        && ok "layout: what spark also suggested is kept with the last layout and offered as a panel row" || bad "suggested row" "st=$st $out $(jq -c . "$desk_last")"
    : > "$swlog"; st=0; out=$(SWAYSOCK=/tmp/x sh "$SH" panel layout add micro 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$out" = 'opened micro' ] && grep -q '^exec foot -e micro' "$swlog" && ! sh "$SH" panel layout --list | grep -q 'also open micro' \
        && ok "panel layout add NAME: the suggested app opens on this workspace, and its row is gone" || bad "suggested add" "st=$st $out $(cat "$swlog")"
    st=0; out=$(SWAYSOCK=/tmp/x sh "$SH" panel layout add gimp 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = 'spark-shell panel: layout: gimp was not suggested for the last layout' ] && ok "panel layout add: an app that was not suggested is refused in one line" || bad "suggested gate" "st=$st $out"
    mv "$H/spark.keep" "$H/.local/bin/spark"; : > "$swlog"
    st=0; out=$(sh "$SH" layout delete studio 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = "spark-shell layout: no saved layout named studio" ] && ok "layout delete NAME twice: refused in one line" || bad "delete twice" "st=$st $out"
    printf 'workspace number 1\nexec firefox\n' > "$desks/mine"
    st=0; out=$(sh "$SH" layout delete mine 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$(printf '%s\n' "$out" | wc -l)" -eq 1 ] && [ "$out" = "spark-shell layout: $desks/mine is not a layout spark-shell made (one JSON object: words, why, main, side) -- left alone." ] && [ -f "$desks/mine" ] \
        && ok "layout delete NAME: a file that is not one JSON object is refused, named, and left in place" || bad "forget yours" "st=$st $out"
    st=0; out=$(sh "$SH" layout mine 2>&1) || st=$?
    [ "$st" -eq 1 ] && printf '%s\n' "$out" | grep -q 'left alone\.$' && ok "layout NAME on a file that is not a layout: refused, left alone" || bad "open yours" "st=$st $out"
    # a desk kept before v0.36 (sway lines under a header): refused on open and on forget, the file named, the words to make it again
    printf '# desk: news and mail -- rendered by spark-shell (spark-shell desktop keep NAME keeps it)\nworkspace number 1\nexec firefox\n' > "$desks/old"
    old_why="spark-shell layout: $desks/old is a layout of the old shape (sway lines). spark-shell layout \"news and mail\" makes it again, then spark-shell layout save saves it."
    st=0; out=$(sh "$SH" layout old 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = "$old_why" ] && ok "layout NAME on a file of the old shape: one sentence names the file and the words that make it again" || bad "open old" "st=$st $out"
    st=0; out=$(sh "$SH" layout delete old 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = "$old_why" ] && [ -f "$desks/old" ] && ok "layout delete NAME on a file of the old shape: the same sentence, the file left" || bad "forget old" "st=$st $out"
    rm -f "$desks/old"
    cp "$desk_last" "$H/desk.last.json"; printf '# desk: old -- rendered by spark-shell\nworkspace number 1\n' > "$desk_last"
    st=0; out=$(sh "$SH" layout save 2>&1) || st=$?
    [ "$st" -eq 1 ] && printf '%s\n' "$out" | grep -q "^spark-shell layout: $desk_last is a layout of the old shape" && ok "layout save with a desk.last of the old shape: refused, the file named" || bad "save old" "st=$st $out"
    cp "$H/desk.last.json" "$desk_last"
    st=0; out=$(sh "$SH" layout save a b 2>&1) || st=$?
    [ "$st" -eq 0 ] && printf '%s\n' "$out" | grep -q '^saved a-b -- ' && [ -f "$desks/a-b" ] && ok "layout save: words with a space become one name (a-b)" || bad "save name" "st=$st $out"
    rm -f "$desks/a-b"
    # the gate on a kept desk edited by hand: every rendered line read, the bad ones named, the rest runs
    cat > "$desks/gate" <<'EOF'
{"words": "the gate", "main": {"app": "rm", "args": "x"},
 "side": [{"app": "gimp-3.0", "args": "$(id)"}, {"app": "sudo", "args": "ls"}, {"app": "firefox", "args": "a|b"}, {"app": "firefox", "args": "https://x, exec rm y"}, {"app": "micro", "args": "notes.txt"}]}
EOF
    rm -f "$swlog"
    st=0; out=$(sh "$SH" layout gate 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$(printf '%s\n' "$out" | grep -c '^  refused  ')" -eq 4 ] && ok "gate: four lines refused, the desk still runs (exit 0)" || bad "gate count" "st=$st $out"
    printf '%s\n' "$out" | grep -q '^  rm x$' && ok "gate: a kept desk you edited may open a program the machine has (rm x ran; it is yours)" || bad "gate rm" "$out"
    printf '%s\n' "$out" | grep -qF '  refused  exec gimp-3.0 $(id)  (shell syntax' && printf '%s\n' "$out" | grep -qF '  refused  exec firefox a|b  (shell syntax' \
        && ok "gate: shell syntax (\$(id), a pipe) never reaches sh -c" || bad "gate syntax" "$out"
    printf '%s\n' "$out" | grep -qF '  refused  exec firefox https://x, exec rm y  (a comma starts a second sway command)' \
        && ok "gate: a comma in an exec is refused (sway would run the rest as its own command)" || bad "gate comma" "$out"
    printf '%s\n' "$out" | grep -qE '^  refused  exec (foot -e )?sudo ls  \(sudo is not an app\)$' && ok "gate: sudo is not an app (in foot when this machine has a sudo, plain when not)" || bad "gate sudo" "$out"
    printf '%s\n' 'workspace number 3' 'rename workspace to "3 gate"' 'exec foot -e rm x' 'splith' 'exec foot -e micro notes.txt' 'focus left' 'resize set width 70 ppt' > "$H/expected.gate"
    cmp -s "$swlog" "$H/expected.gate" && ok "gate: sway got the workspace line, the two good execs and their layout, nothing else" || bad "gate lines" "$(cat "$swlog" 2>&1)"
    # a kept desk may open any program the machine has (you kept it); the model's answer may not
    printf '#!/bin/sh\n:\n' > "$H/.local/bin/reader"; chmod +x "$H/.local/bin/reader"
    printf '{"words": "a reader you kept", "main": {"app": "reader"}, "side": [{"app": "sudo", "args": "ls"}]}\n' > "$desks/kept-reader"
    : > "$swlog"
    st=0; out=$(sh "$SH" layout kept-reader 2>&1) || st=$?
    [ "$st" -eq 0 ] && grep -q '^exec foot -e reader$' "$swlog" && printf '%s\n' "$out" | grep -qE '^  refused  exec (foot -e )?sudo ls  \(sudo is not an app\)$' \
        && ok "a kept desk: a program on the machine but not in the inventory opens; sudo never" || bad "kept gate" "st=$st $out $(cat "$swlog")"
    rm -f "$desks/kept-reader" "$H/.local/bin/reader"
    # a window that never comes (mpv with nothing to play): the split meant for it is skipped,
    # so the next window lands beside the main one instead of cutting it
    printf '{"words": "gone", "main": {"app": "micro", "width": 70}, "side": [{"app": "gone"}, {"app": "firefox"}]}\n' > "$desks/gone"
    : > "$swlog"
    st=0; out=$(sh "$SH" layout gone 2>&1) || st=$?
    printf '%s\n' "$out" | grep -q '^  gone -- no window$' && printf '%s\n' "$out" | grep -q '^  micro$' && printf '%s\n' "$out" | grep -q '^  firefox$' \
        && ! printf '%s\n' "$out" | grep -q 'splitv\|focus left\|resize set' \
        && ok "a window that never comes: said in the app's own words; no sway grammar on the screen" || bad "gone window" "st=$st $out"
    : > "$swlog"
    st=0; out=$(sh "$SH" layout gone -v 2>&1) || st=$?
    printf '%s\n' "$out" | grep -q '^  skipped  splitv  (no window to split)$' && printf '%s\n' "$out" | grep -q '^  exec foot -e micro$' \
        && ok "-v after the words is a flag, not a word: the sway lines and the skipped split shown" || bad "gone verbose" "st=$st $out"
    printf '%s\n' 'workspace number 3' 'rename workspace to "3 gone"' 'exec foot -e micro' 'splith' 'exec gone' 'exec firefox' 'focus left' 'resize set width 70 ppt' > "$H/expected.gone"
    cmp -s "$swlog" "$H/expected.gone" && ok "a window that never comes: sway never got the splitv" || bad "gone lines" "$(cat "$swlog" 2>&1)"
    # two screens: the brief says them and the rule; each screen its own workspace, the main's first,
    # focus output before each; the outputs' make, model and serial never leave the machine
    touch "$H/two-screens"; rm -f "$argv" "$swlog"
    st=0; out=$(sh "$SH" layout "$need" 2>&1) || st=$?
    [ "$st" -eq 0 ] && grep -q 'on screens: left 2560x1440, right 1920x1080\. ' "$argv" && grep -q ' A window is on one screen; screen is left or right; one screen unless the need names two or the work needs two\. ' "$argv" \
        && grep -q '"screen": "left"' "$argv" && ok "two screens: the brief names them left to right with their sizes, the rule, the screen field" || bad "two screens brief" "st=$st $(grep -o 'on screens[^.]*' "$argv") $out"
    grep -q 'Fakemake\|Fakemodel\|SN000' "$argv" && bad "two screens: an output's make, model or serial reached the model" "$(grep -o '[^ ]*Fake[^ ]*\|SN000[0-9]' "$argv" | head -3)" || ok "two screens: the outputs' make, model and serial never reach the model"
    printf '%s\n' 'focus output DP-1' 'workspace number 3' 'rename workspace to "3 photo editing for"' 'exec gimp-3.0' splith 'exec foot -e micro' 'focus left' 'resize set width 70 ppt' 'focus output HDMI-A-1' 'workspace number 4' 'rename workspace to "4 photo editing for"' 'exec firefox https://instagram.com' > "$H/expected.two"
    cmp -s "$swlog" "$H/expected.two" && ok "two screens: the main's group first (focus output, workspace 3, main, micro beside it, sized), then the right screen's (focus output, workspace 4, firefox)" || bad "two screens lines" "$(cat "$swlog" 2>&1)"
    printf '%s\n' "$out" | grep -q '^on workspace 3 and 4 -- spark-shell layout save NAME saves it$' && ok "two screens: the closing line says both workspaces" || bad "two screens closing" "$out"
    printf '%s\n' "$out" | grep -q 'is not here' && bad "two screens: a screen that is here was said to be missing" "$(printf '%s\n' "$out" | grep 'is not here')" || ok "two screens: both named screens are here, no line says one is missing"
    grep -q 'workspace .* output\|floating\|sticky' "$swlog" && bad "two screens: a line that pins (workspace N output, floating, sticky)" "$(grep 'output\|floating\|sticky' "$swlog")" || ok "two screens: nothing pins a window (no workspace N output, no floating, no sticky)"
    sh "$SH" layout save two >/dev/null
    jq -e '.main.screen == "left" and .side[0].screen == "right" and (.side[1] | has("screen") | not)' "$desks/two" >/dev/null 2>&1 && ok "two screens: the kept desk carries screen on main and one side entry, as answered" || bad "two kept" "$(cat "$desks/two")"
    rm -f "$H/two-screens"; : > "$swlog"
    st=0; out=$(sh "$SH" layout two 2>&1) || st=$?
    [ "$st" -eq 0 ] && printf '%s\n' "$out" | grep -q '^  the right screen is not here -- all on DP-1$' && ! printf '%s\n' "$out" | grep -q 'all on *$' && [ "$(grep -c '^workspace number' "$swlog")" -eq 1 ] && ! grep -q '^focus output' "$swlog" \
        && printf '%s\n' "$out" | grep -q '^on workspace 3 -- the saved layout two$' && ok "a desk kept on two screens opens on one: said in one line, one workspace, no focus output" || bad "two on one" "st=$st $out $(cat "$swlog")"
    printf '{"words": "nine", "main": {"app": "micro", "screen": "DP-9"}, "side": [{"app": "firefox", "screen": "right"}]}\n' > "$desks/nine"
    touch "$H/two-screens"; : > "$swlog"
    st=0; out=$(sh "$SH" layout nine 2>&1) || st=$?
    printf '%s\n' 'focus output DP-1' 'workspace number 3' 'rename workspace to "3 nine"' 'exec foot -e micro' 'focus output HDMI-A-1' 'workspace number 4' 'rename workspace to "4 nine"' 'exec firefox' > "$H/expected.nine"
    [ "$st" -eq 0 ] && printf '%s\n' "$out" | grep -q '^  the DP-9 screen is not here -- all on DP-1$' && cmp -s "$swlog" "$H/expected.nine" \
        && ok "a kept screen name that is not here (DP-9) maps to the first screen; a side on the right keeps its own" || bad "nine" "st=$st $out $(cat "$swlog")"
    st=0; out=$(sh "$SH" layout nine -v 2>&1) || st=$?
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
    st=0; out=$(PATH=$H/nojq sh "$SH" layout "$need" 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = "spark-shell layout: jq is not installed (spark-shell on)" ] && ok "layout WORDS without jq: refused in one line" || bad "desk no jq" "st=$st $out"
    out=$(sh "$SH" check || true)
    printf '%s\n' "$out" | grep -q '^ok     desktop      sway and foot are installed and up to date$' && ok "check: the desktop row says installed and up to date" || bad "check desk row" "$out"
    # the rendered sway config: Super+d, the floating prompt, --pending before the first terminal
    sway=$HOME/.config/sway/config
    grep -qF "bindsym \$mod+d exec \$term --app-id spark-dialog -W 60x44 -o pad=24x19 -o colors-dark.background=0f0f0f -o colors-dark.alpha=1.0 -e $REPO/spark-shell dialog" "$sway" && ok "sway render: Super+d opens the panel (the clone's spark-shell), 76x36 with air and the surface a shade of black towards the text (no theme: 0f0f0f)" || bad "sway render bind" "$(grep -n 'mod+d' "$sway")"
    grep -qF 'for_window [app_id="spark-dialog"] floating enable, border none, move position center' "$sway" && ok "sway render: the panel floats in the middle, no frame" || bad "sway render for_window" "$(grep -n spark-dialog "$sway")"
    l_p=$(grep -nF "exec $REPO/spark-shell desktop --pending" "$sway" | head -1 | cut -d: -f1); l_t=$(grep -n "^exec sh -c '" "$sway" | tail -1 | cut -d: -f1)
    [ -n "$l_p" ] && [ -n "$l_t" ] && [ "$l_p" -lt "$l_t" ] && ok "sway render: desktop --pending runs before the first terminal" || bad "sway render pending" "pending $l_p terminal $l_t"
    unset SWAYSOCK WAYLAND_DISPLAY
fi
grep -q '^bindsym \$mod+d exec \$term --app-id spark-dialog -W @PANEL_SIZE@ -o pad=@PANEL_PAD@ -o @FOOT_COLORS@.background=@PANEL_BG@ -o @FOOT_COLORS@.alpha=1.0 -e @REPO@/spark-shell dialog$' "$REPO/templates/.config/sway/config" && ok "sway template: Super+d is spark-shell panel in a spark-dialog foot" || bad "sway template bind" "$(grep -n 'mod+d' "$REPO/templates/.config/sway/config")"
! grep -q 'spark-desk' "$REPO/templates/.config/sway/config" && ok "sway template: no spark-desk window any more, the panel is the one window" || bad "sway template spark-desk"
l_p=$(grep -n '^exec @REPO@/spark-shell desktop --pending$' "$REPO/templates/.config/sway/config" | head -1 | cut -d: -f1); l_t=$(grep -n "^exec sh -c '" "$REPO/templates/.config/sway/config" | tail -1 | cut -d: -f1)
[ -n "$l_p" ] && [ -n "$l_t" ] && [ "$l_p" -lt "$l_t" ] && ok "sway template: desktop --pending is the exec before the last exec sh -c" || bad "sway template pending" "pending $l_p terminal $l_t"
grep -q '^## Layouts$' "$REPO/README.md" && ok "README: Layouts" || bad "README layouts section"
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
    # fzf: its rows and its arguments logged; it answers the rows in $HOME/fzf.pick, or leaves (Esc, 130)
    printf '#!/bin/sh\ncat > "$HOME/fzf.rows"; printf "%%s\\n" "$@" > "$HOME/fzf.args"\n[ -f "$HOME/fzf.pick" ] || exit 130\ncat "$HOME/fzf.pick"\n' > "$H/.local/bin/fzf"
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
    sh "$SH" on --yes >/dev/null
    st=0; out=$(sh "$SH" desktop apps </dev/null 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$(printf '%s\n' "$out" | wc -l)" -eq 1 ] && printf '%s\n' "$out" | grep -q '^spark-shell desktop: not on macOS, which has its own desktop$' \
        && ok "macOS: desktop apps refuses, na, one line, exit 1" || bad "macOS desktop apps" "st=$st $out"
    st=0; out=$(sh "$SH" apps </dev/null 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = "spark-shell apps: not on macOS, which has its own desktop" ] && ok "macOS: apps refuses, na, one line, exit 1" || bad "macOS apps" "st=$st $out"
    ck=$(sh "$SH" check || true)
    printf '%s\n' "$ck" | grep -q '^ok     apps         na (' && ok "macOS: the check apps row says na" || bad "macOS check apps" "$(printf '%s\n' "$ck" | grep apps)"
else
    sh "$SH" on --yes >/dev/null
    tmuxd=$HOME/.local/share/applications/spark-shell-tmux.desktop
    [ -f "$tmuxd" ] && head -1 "$tmuxd" | grep -q '^# rendered by spark-shell' && grep -q '^Exec=tmux$' "$tmuxd" && grep -q '^Terminal=true$' "$tmuxd" \
        && ok "on with DESKTOP=sway: tmux declares itself (spark-shell-tmux.desktop, marked, Exec=tmux, Terminal=true)" || bad "tmux entry" "$(cat "$tmuxd" 2>&1)"
    plain "$tmuxd" && ok "tmux entry: plain (no hex, ASCII)" || bad "tmux entry not plain"
    # the table and the kinds: the counts line, exit 0, one row per package
    st=0; out=$(SPARK_OS_RELEASE=$H/os-arch sh "$SH" sbom 2>&1) || st=$?
    [ "$st" -eq 0 ] && printf '%s\n' "$out" | grep -q '^1 apps, 1 tools, 1 parts -- an app is a package with a desktop entry (spark-shell apps chooses the allowed apps)$' \
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
    [ "$st" -eq 1 ] && [ "$out" = "spark-shell sbom: no package manager here that this repo knows (pacman, apt, xbps, brew)" ] && ok "sbom with ID=fixture: no known package manager, one line, exit 1" || bad "sbom fixture" "st=$st $out"
    # the picker with no terminal: refused in one line naming the file (apps, and the old desktop apps|tools)
    st=0; out=$(sh "$SH" apps </dev/null 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = "spark-shell apps: the picker needs a terminal -- the file is $apps_file (name[: your words], one per line)" ] \
        && ok "apps without a terminal: refused in one line naming the file, exit 1" || bad "apps no tty" "st=$st $out"
    st=0; out=$(sh "$SH" desktop tools </dev/null 2>&1) || st=$?
    [ "$st" -eq 1 ] && printf '%s\n' "$out" | grep -q '^spark-shell desktop: the picker needs a terminal' && ok "old spellings: desktop tools is the same picker, the same refusal" || bad "tools refusal" "st=$st $out"
    st=0; out=$(sh "$SH" desktop apps </dev/null 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = "spark-shell desktop: the picker needs a terminal -- the file is $apps_file (name[: your words], one per line)" ] \
        && ok "old spellings: desktop apps without a terminal, refused in one line naming the file" || bad "desktop apps no tty" "st=$st $out"
    [ ! -e "$apps_file" ] && ok "apps without a terminal: wrote nothing" || bad "apps wrote" "$(cat "$apps_file")"
    # the one picker at a terminal (script lends it one): the apps first, then the tools, in
    # one list; Enter saves the allowed apps, a second pick flips one off, Esc leaves the file
    if command -v script >/dev/null 2>&1; then
        on_tty() { if script --version >/dev/null 2>&1; then script -qec "$*" /dev/null; else script -q /dev/null "$@"; fi; }
        printf '  gimp-3.0: Create images and edit photographs  [app]\n  reader: Text-based Web browser  [tool]\n' > "$HOME/fzf.pick"
        st=0; out=$(on_tty env SPARK_OS_RELEASE="$H/os-arch" sh "$SH" apps </dev/null 2>&1) || st=$?
        printf '%s\n' '  gimp-3.0: Create images and edit photographs  [app]' '  reader: Text-based Web browser  [tool]' > "$H/expected.rows"
        [ "$st" -eq 0 ] && cmp -s "$HOME/fzf.rows" "$H/expected.rows" && ok "apps: one picker, the app row first, then the tool row" || bad "apps rows" "st=$st $out $(cat "$HOME/fzf.rows" 2>&1)"
        grep -qx 'gimp-3.0' "$apps_file" && grep -qx reader "$apps_file" && printf '%s\n' "$out" | grep -qF "allowed apps: gimp-3.0 reader ($apps_file)" \
            && ok "apps: Enter saves the picked rows as the allowed apps, said in one line" || bad "apps save" "$out $(cat "$apps_file" 2>&1)"
        grep -qx 'apps> ' "$HOME/fzf.args" && grep -q '^The allowed apps: what a layout may open' "$HOME/fzf.args" && ! grep -qi 'mark' "$HOME/fzf.args" \
            && ok "apps: the prompt is apps>, the header says allowed apps" || bad "apps header" "$(cat "$HOME/fzf.args")"
        printf '* reader: Text-based Web browser  [tool]\n' > "$HOME/fzf.pick"
        st=0; out=$(on_tty env SPARK_OS_RELEASE="$H/os-arch" sh "$SH" desktop tools </dev/null 2>&1) || st=$?
        [ "$st" -eq 0 ] && grep -q '^\* gimp-3.0: ' "$HOME/fzf.rows" && grep -q '^\* reader: ' "$HOME/fzf.rows" && grep -qx 'gimp-3.0' "$apps_file" && ! grep -q '^reader' "$apps_file" \
            && ok "old spellings: desktop tools opens the same picker; an allowed row wears *, picking it again takes it off" || bad "apps flip" "st=$st $out $(cat "$HOME/fzf.rows" "$apps_file" 2>&1)"
        cp "$apps_file" "$H/apps.before"; rm -f "$HOME/fzf.pick"
        st=0; out=$(on_tty env SPARK_OS_RELEASE="$H/os-arch" sh "$SH" apps </dev/null 2>&1) || st=$?
        [ "$st" -eq 0 ] && printf '%s\n' "$out" | grep -q 'nothing changed' && cmp -s "$apps_file" "$H/apps.before" && ok "apps: Esc leaves the file as it was" || bad "apps esc" "st=$st $out"
        rm -f "$apps_file" "$HOME/fzf.rows" "$HOME/fzf.args"
    fi
    # status and check, unmarked: every entry (the five fixtures and tmux)
    st=$(sh "$SH" status); printf '%s\n' "$st" | grep -q '^  apps  all  *every app with a desktop entry (spark-shell apps picks the allowed apps)$' && ok "status: the apps row says all, every app with a desktop entry" || bad "status apps unmarked" "$(printf '%s\n' "$st" | grep apps)"
    ck=$(sh "$SH" check || true); printf '%s\n' "$ck" | grep -q '^ok     apps         6 apps installed, all allowed (spark-shell apps chooses)$' \
        && ok "check: the apps row counts the entries (five fixtures and tmux), all allowed" || bad "check apps unmarked" "$(printf '%s\n' "$ck" | grep apps)"
    # the unmarked inventory: tmux in its entry's words, a terminal app
    rm -f "$argv"
    SWAYSOCK=/tmp/x WAYLAND_DISPLAY=wayland-1 sh "$SH" layout "$need" >/dev/null 2>&1 || true
    if command -v tmux >/dev/null 2>&1; then
        grep -q 'tmux: A shell with panes, sessions and the status line' "$argv" && ok "inventory unmarked: tmux in its entry's words" || bad "inventory tmux" "$(grep -o 'tmux[^;]*' "$argv" 2>&1)"
    fi
    grep -q 'gimp-3.0: Create images and edit photographs' "$argv" && ! grep -q 'gimp:' "$argv" && ok "inventory unmarked: an entry's Exec name, never the package name (gimp-3.0, not gimp)" || bad "inventory gimp" "$(grep -o 'gimp[^;]*' "$argv" 2>&1)"
    # marked: the names, the rows; a name that is gone is a FAIL with the remedy
    printf '# mine\nreader: my browser\nmicro\n' > "$apps_file"
    st=$(sh "$SH" status); printf '%s\n' "$st" | grep -q '^  apps  2 allowed  *reader, micro (spark-shell apps)$' && ok "status: the apps row counts and names the allowed apps" || bad "status apps marked" "$(printf '%s\n' "$st" | grep apps)"
    ck=$(sh "$SH" check || true); printf '%s\n' "$ck" | grep -q '^ok     apps         2 allowed apps, 6 apps installed$' && ok "check: ok apps when every allowed name is here" || bad "check apps marked" "$(printf '%s\n' "$ck" | grep apps)"
    printf 'reader: my browser\nmicro\nghost\n' > "$apps_file"
    ck=$(sh "$SH" check || true); printf '%s\n' "$ck" | grep -q '^FAIL   apps         allowed but not here: ghost -- spark-shell apps$' && ok "check: FAIL apps naming the allowed name that is gone, the remedy is spark-shell apps" || bad "check apps gone" "$(printf '%s\n' "$ck" | grep apps)"
    rm -f "$apps_file"
    # off hands the tmux entry back
    sh "$SH" off >/dev/null
    [ ! -e "$tmuxd" ] && ok "off: the tmux entry is gone (no .bak: there was none before)" || bad "tmux entry off" "$(ls "$HOME/.local/share/applications")"
    ck=$(sh "$SH" check || true); printf '%s\n' "$ck" | grep -q '^ok     apps         5 apps installed, all allowed' && ok "check after off: tmux is out of the count (five entries)" || bad "check apps after off" "$(printf '%s\n' "$ck" | grep apps)"
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
desk_last=$H/.local/state/spark-shell/desk.last; desks=$H/.config/spark-shell/layouts
# a need with no sway: the rooms player, the terminal apps offered, one room per app that is one
st=0; out=$(sh "$SH" layout "$need" 2>&1) || st=$?
[ "$st" -eq 0 ] && printf '%s\n' "$out" | grep -q "^layout> $need\$" && printf '%s\n' "$out" | grep -q '^  photo work in gimp with the two feeds' \
    && ok "tmux windows: words with no sway open as tmux windows: exit 0, the layout> line, the why" || bad "rooms need" "st=$st $out"
printf '%s\n' "has-session -t =$sname" "new-session -d -s $sname -n micro micro" > "$H/expected.rooms"
cmp -s "$tlog" "$H/expected.rooms" && ok "rooms: tmux got has-session, then one new-session with micro as its first window, nothing else" || bad "rooms tmux log" "$(cat "$tlog" 2>&1)"
printf '%s\n' "$out" | grep -q '^  gimp-3.0 -- needs the desktop$' && printf '%s\n' "$out" | grep -q '^  firefox https://instagram.com -- needs the desktop$' && printf '%s\n' "$out" | grep -q '^  micro$' \
    && ok "rooms: a graphical app is one line (needs the desktop), a terminal app runs" || bad "rooms outcome lines" "$out"
printf '%s\n' "$out" | grep -q '^  refused  window ghostapp ghostapp  (ghostapp is not on this machine)$' && ok "rooms: the gate reads a tmux window line like an exec" || bad "rooms gate" "$out"
printf '%s\n' "$out" | grep -q "^tmux session $sname -- spark-shell layout save NAME saves it\$" && printf '%s\n' "$out" | grep -q "^tmux session $sname -- tmux attach-session -t $sname joins it\$" \
    && ok "rooms: the closing line names the session and keep; on a pipe, the line that joins them" || bad "rooms closing" "$out"
grep -q 'attach-session\|switch-client' "$tlog" && bad "rooms: attached on a pipe" "$(cat "$tlog")" || ok "rooms: no attach on a pipe"
grep -q '^A layout of tmux windows: the apps for one need, each in a terminal window, on a [0-9]*x[0-9]* terminal\. ' "$argv" && ok "rooms brief: tmux windows, a terminal, its columns and lines" || bad "rooms brief" "$(grep -o 'A layout[^.]*' "$argv")"
grep -q 'micro: Micro' "$argv" && grep -q 'shell: a terminal with a prompt' "$argv" && ! grep -q 'gimp-3.0\|firefox\|"screen"\|on one screen\|on screens' "$argv" \
    && ok "rooms brief: the terminal apps and shell only; no graphical app, no screen field, no screens" || bad "rooms brief apps" "$(grep -o 'Apps on this machine[^.]*' "$argv")"
jq -e --arg w "$need" '.words == $w and .main.app == "gimp-3.0"' "$desk_last" >/dev/null 2>&1 && ok "rooms: desk.last is the same JSON shape (keep works the same)" || bad "rooms desk.last" "$(cat "$desk_last" 2>&1)"
[ ! -e "$swlog" ] && ok "rooms: swaymsg never sent a line" || bad "rooms swaymsg" "$(cat "$swlog")"
# a need of * from a directory with files: the word, never the file names
rm -f "$argv"
(cd "$H/.local/bin" && sh "$SH" layout '*' >/dev/null 2>&1) || true
[ "$(tail -1 "$argv")" = 'write the layout for this need: *' ] && ok "a need of * reaches the model as *, not as the cwd's file names" || bad "glob need" "$(tail -1 "$argv" 2>&1)"
rm -f "$argv"
sh "$SH" layout 'notes\nand a backslash' >/dev/null 2>&1 || true
[ "$(tail -1 "$argv")" = 'write the layout for this need: notes\nand a backslash' ] && ok "a need with a literal backslash reaches the model byte-exact" || bad "backslash need" "$(tail -1 "$argv" 2>&1)"
# inside tmux: switch-client; a session already open is joined, not built again
: > "$tlog"
st=0; out=$(TMUX=/x sh "$SH" layout "$need" --terminal 2>&1) || st=$?
[ "$st" -eq 0 ] && [ "$(tail -1 "$tlog")" = "switch-client -t =$sname" ] && ok "inside tmux (TMUX set, --terminal): switch-client to the session" || bad "rooms switch" "st=$st $(cat "$tlog")"
: > "$tlog"
st=0; out=$(TMUX=/x sh "$SH" desktop "$need" --rooms 2>&1) || st=$?
[ "$st" -eq 0 ] && [ "$(tail -1 "$tlog")" = "switch-client -t =$sname" ] && printf '%s\n' "$out" | grep -q "^layout> $need\$" && ok "old spellings: desktop WORDS --rooms still opens the tmux windows" || bad "alias rooms" "st=$st $out $(cat "$tlog")"
touch "$H/tmux.has"; : > "$tlog"
st=0; out=$(sh "$SH" layout "$need" 2>&1) || st=$?
[ "$st" -eq 0 ] && printf '%s\n' "$out" | grep -q "^  the tmux session $sname is open already\$" && ! grep -q 'new-session' "$tlog" \
    && ok "rooms open already: said in one line, no session built, joined" || bad "rooms has-session" "st=$st $out $(cat "$tlog")"
rm -f "$H/tmux.has"
# a kept desk named studio; shell and editor are desk words
mkdir -p "$desks"
cat > "$desks/studio" <<'EOF2'
{"words": "studio",
 "why": "a shell, the editor, the feeds, the web and the mail, one room each",
 "main": {"app": "shell", "args": "", "width": 70},
 "side": [{"app": "editor", "args": ""},
          {"app": "newsboat", "args": ""},
          {"app": "w3m", "args": "duckduckgo.com"},
          {"app": "aerc", "args": ""}]}
EOF2
: > "$tlog"; rm -f "$argv"
st=0; out=$(sh "$SH" layout studio 2>&1) || st=$?
printf '%s\n' 'has-session -t =studio' 'new-session -d -s studio -n shell' 'new-window -t =studio -n editor micro' 'new-window -t =studio -n newsboat newsboat' 'new-window -t =studio -n w3m w3m duckduckgo.com' 'new-window -t =studio -n aerc aerc' > "$H/expected.studio"
[ "$st" -eq 0 ] && cmp -s "$tlog" "$H/expected.studio" && [ ! -e "$argv" ] \
    && ok "desktop studio: the session with a bare shell window, then one window per room, the editor micro with EDITOR unset; no model call" || bad "studio play" "st=$st $out $(cat "$tlog")"
printf '%s\n' "$out" | grep -q '^layout> studio$' && printf '%s\n' "$out" | grep -q '^  a shell, the editor, the feeds' && printf '%s\n' "$out" | grep -q '^  editor micro$' && printf '%s\n' "$out" | grep -q '^  w3m duckduckgo.com$' \
    && printf '%s\n' "$out" | grep -q '^tmux session studio -- the saved layout studio$' && ok "layout studio: the layout> line, the why, one line per window, the closing line" || bad "studio lines" "$out"
printf '#!/bin/sh\n:\n' > "$H/.local/bin/nano"; chmod +x "$H/.local/bin/nano"   # the containers have no nano; a kept desk runs what is on PATH
: > "$tlog"
st=0; out=$(EDITOR=/usr/bin/nano sh "$SH" layout studio 2>&1) || st=$?
grep -q '^new-window -t =studio -n editor nano$' "$tlog" && ok "editor is EDITOR's basename (nano)" || bad "editor nano" "$(cat "$tlog")"
rm -f "$H/.local/bin/nano"; : > "$tlog"
st=0; out=$(EDITOR=/usr/bin/nosucheditor sh "$SH" layout studio 2>&1) || st=$?
[ "$st" -eq 0 ] && printf '%s\n' "$out" | grep -q '^  refused  window editor nosucheditor  (nosucheditor is not on this machine)$' && grep -q '^new-window -t =studio -n newsboat newsboat$' "$tlog" \
    && ok "EDITOR naming a program that is not here: its room is refused, the rest opens" || bad "editor absent" "st=$st $out"
mkdir -p "$H/noed"   # a PATH with everything but micro and vi (this machine may have the real ones)
for d in $(printf '%s' "$PATH" | tr ':' ' '); do
    [ -d "$d" ] || continue
    for f in "$d"/*; do n=${f##*/}; if [ "$n" != micro ] && [ "$n" != vi ] && [ -x "$f" ] && [ ! -e "$H/noed/$n" ]; then ln -s "$f" "$H/noed/$n"; fi; done
done
: > "$tlog"
st=0; out=$(PATH=$H/noed sh "$SH" layout studio 2>&1) || st=$?
[ "$st" -eq 0 ] && printf '%s\n' "$out" | grep -qx '  editor -- no editor on this machine: set EDITOR in ~/.config/spark-shell/rc' && ! grep -q ' -n editor' "$tlog" \
    && grep -q '^new-session -d -s studio -n shell$' "$tlog" && grep -q '^new-window -t =studio -n newsboat newsboat$' "$tlog" \
    && ok "no EDITOR, no micro, no vi: that one window is skipped in one line, the rest opens" || bad "no editor" "st=$st $out $(cat "$tlog")"
printf '#!/bin/sh\n:\n' > "$H/noed/vi"; chmod +x "$H/noed/vi"   # a vi of our own: the containers may lack one
: > "$tlog"
st=0; out=$(PATH=$H/noed sh "$SH" layout studio 2>&1) || st=$?
[ "$st" -eq 0 ] && grep -q '^new-window -t =studio -n editor vi$' "$tlog" && ! printf '%s\n' "$out" | grep -q 'no editor' \
    && ok "no EDITOR and no micro: the editor is vi when vi is here" || bad "editor vi" "st=$st $out $(cat "$tlog")"
st=0; out=$(sh "$SH" layout studio -v 2>&1) || st=$?
printf '%s\n' "$out" | grep -q '^  window shell$' && printf '%s\n' "$out" | grep -q '^  window editor micro$' && printf '%s\n' "$out" | grep -q '^  window w3m w3m duckduckgo.com$' \
    && ok "-v shows the tmux lines (window NAME [CMD ARGS])" || bad "rooms verbose" "$out"
printf '%s\n' "$out" | grep -q '^  session studio$' && ok "-v: the session line" || bad "rooms verbose session" "$out"
printf '{"words": "pipe", "main": {"app": "w3m", "args": "a|b"}}\n' > "$desks/pipe"; : > "$tlog"
st=0; out=$(sh "$SH" layout pipe 2>&1) || st=$?
[ "$st" -eq 1 ] && printf '%s\n' "$out" | grep -qF '  refused  window w3m w3m a|b  (shell syntax' && ! grep -q 'new-session' "$tlog" && printf '%s\n' "$out" | grep -q 'nothing ran$' \
    && ok "a kept desk edited by hand: shell syntax in a room is refused; with no room left, nothing ran" || bad "rooms pipe" "st=$st $out"
# --terminal inside sway: the session is built, then a foot window of its own on a fresh workspace
export SWAYSOCK=$H/sway.sock; : > "$tlog"; rm -f "$swlog"
st=0; out=$(sh "$SH" layout studio --terminal 2>&1) || st=$?
[ "$st" -eq 0 ] && grep -q '^new-session -d -s studio -n shell$' "$tlog" && [ "$(head -1 "$swlog")" = 'workspace number 3' ] && [ "$(tail -1 "$swlog")" = 'exec foot -e tmux attach-session -t =studio' ] \
    && ! grep -q 'attach-session\|switch-client' "$tlog" && ok "--terminal inside sway: the tmux windows built, then workspace 3 and one foot that attaches to them" || bad "rooms in sway" "st=$st $out $(cat "$swlog" "$tlog" 2>&1)"
: > "$tlog"; rm -f "$swlog"
st=0; out=$(sh "$SH" desktop studio --rooms 2>&1) || st=$?
[ "$st" -eq 0 ] && grep -q '^new-session -d -s studio -n shell$' "$tlog" && [ "$(tail -1 "$swlog")" = 'exec foot -e tmux attach-session -t =studio' ] \
    && ok "old spellings: desktop NAME --rooms inside sway, the same as layout NAME --terminal" || bad "alias rooms in sway" "st=$st $out $(cat "$swlog" "$tlog" 2>&1)"
unset SWAYSOCK
# the saved layouts live in layouts/; the old desks/ folder is not read, not moved, not deleted
mkdir -p "$H/.config/spark-shell/desks"; cp "$desks/studio" "$H/.config/spark-shell/desks/olddesk"
out=$(sh "$SH" layout)
printf '%s\n' "$out" | grep -q '^  studio ' && ! printf '%s\n' "$out" | grep -q olddesk && ok "layout (bare): lists layouts/, never the old desks/ folder" || bad "layouts list" "$out"
: > "$tlog"; rm -f "$argv"
st=0; out=$(sh "$SH" layout olddesk 2>&1) || st=$?
[ "$st" -eq 0 ] && [ "$(tail -1 "$argv" 2>&1)" = 'write the layout for this need: olddesk' ] && [ -f "$H/.config/spark-shell/desks/olddesk" ] && [ ! -e "$desks/olddesk" ] \
    && ok "layout NAME of a file in desks/: words for the model, the old file left where it is" || bad "desks ignored" "st=$st $out"
st=$(sh "$SH" status); printf '%s\n' "$st" | grep -q '^  layouts [0-9]* saved  *pipe, studio (spark-shell layout NAME)$' && ok "status: the layouts row counts layouts/ alone" || bad "status layouts dir" "$(printf '%s\n' "$st" | grep layouts)"
rm -rf "$H/.config/spark-shell/desks"
# the old spellings of save and delete land in layouts/ too
sh "$SH" layout "$need" >/dev/null 2>&1 || true
out=$(sh "$SH" desktop keep oldword 2>&1)
[ "$out" = "saved oldword -- spark-shell layout oldword opens it ($desks/oldword)" ] && [ -f "$desks/oldword" ] && ok "old spellings: desktop keep NAME saves to layouts/" || bad "alias keep" "$out"
out=$(sh "$SH" desktop forget oldword 2>&1)
[ "$out" = "deleted oldword" ] && [ ! -e "$desks/oldword" ] && ok "old spellings: desktop forget NAME deletes it" || bad "alias forget" "$out"
st=0; out=$(sh "$SH" desktop forget oldword 2>&1) || st=$?
[ "$st" -eq 1 ] && [ "$out" = "spark-shell desktop: no saved layout named oldword" ] && ok "old spellings: a refusal names the verb as typed (desktop)" || bad "alias forget twice" "st=$st $out"
st=0; out=$(sh "$SH" layout delete 2>&1) || st=$?
[ "$st" -eq 1 ] && [ "$out" = "spark-shell layout: delete NAME -- which layout?" ] && ok "layout delete with no name: refused in one line" || bad "delete bare" "st=$st $out"
: > "$tlog"; rm -f "$argv"
st=0; out=$(sh "$SH" desktop --ask </dev/null 2>&1) || st=$?
[ "$st" -eq 0 ] && printf '%s\n' "$out" | sed -n 1p | grep -q '^layout     ' && [ ! -e "$argv" ] \
    && ok "old spellings: desktop --ask is the panel with the layouts first" || bad "alias ask" "st=$st $out"
# named apps open, the others are suggestions: the model answers $HOME/answer.json
printf '[Desktop Entry]\nName=btop\nComment=Resource monitor\nExec=btop\nTerminal=true\nType=Application\n' > "$XDG_DATA_HOME/applications/btop.desktop"
for t in btop vi; do printf '#!/bin/sh\n:\n' > "$H/.local/bin/$t"; chmod +x "$H/.local/bin/$t"; done
printf '{"why": "vi to write, btop to watch, a shell", "main": {"app": "vi", "args": "", "width": 70}, "side": [{"app": "btop", "args": ""}, {"app": "shell", "args": ""}]}\n' > "$H/answer.json"
wname=writing-with-vi-and-the-prompt-shell; : > "$tlog"
st=0; out=$(sh "$SH" layout "writing with vi and the prompt shell" 2>&1) || st=$?
printf '%s\n' "has-session -t =$wname" "new-session -d -s $wname -n vi vi" "new-window -t =$wname -n shell" > "$H/expected.named"
[ "$st" -eq 0 ] && cmp -s "$tlog" "$H/expected.named" && ok "named: the words name vi and shell, only those two open" || bad "named open" "st=$st $out $(cat "$tlog")"
printf '%s\n' "$out" | grep -qx '  also suggested: btop -- add it to your words to open it' && ok "named: the one app not named is said in one line, a suggestion" || bad "named suggestion" "$out"
jq -e '.main.app == "vi" and (.side | map(.app)) == ["shell"] and .suggested == ["btop"] and (has("why") | not)' "$desk_last" >/dev/null 2>&1 \
    && ok "named: desk.last holds what opened (vi and shell), btop as suggested for the panel's row, and no why" || bad "named desk.last" "$(cat "$desk_last")"
printf '%s\n' "$out" | grep -q 'vi to write, btop to watch' && bad "named: the model's why said though btop was dropped" "$out" || ok "named: btop dropped, so the model's why is not said"
printf '{"main": {"app": "btop", "args": "", "width": 60}, "side": [{"app": "newsboat", "args": ""}, {"app": "shell", "args": ""}, {"app": "micro", "args": ""}]}\n' > "$H/answer.json"
dname=the-feeds-in-newsboat-and-a-shell; : > "$tlog"
st=0; out=$(sh "$SH" layout "the feeds in Newsboat and a shell" 2>&1) || st=$?
printf '%s\n' "has-session -t =$dname" "new-session -d -s $dname -n newsboat newsboat" "new-window -t =$dname -n shell" > "$H/expected.dropped"
[ "$st" -eq 0 ] && cmp -s "$tlog" "$H/expected.dropped" && printf '%s\n' "$out" | grep -qx '  also suggested: btop and micro -- add them to your words to open them' \
    && jq -e '.main.app == "newsboat" and .main.width == 60 and (.side | map(.app)) == ["shell"]' "$desk_last" >/dev/null 2>&1 \
    && ok "named: the main window not named, the first named takes its place (its width kept); two suggestions in one line" || bad "named main dropped" "st=$st $out $(cat "$tlog" "$desk_last")"
printf '{"why": "micro for notes, btop to watch", "main": {"app": "micro", "args": ""}, "side": [{"app": "btop", "args": ""}]}\n' > "$H/answer.json"
nname=news-reading-and-music; : > "$tlog"
st=0; out=$(sh "$SH" layout "news reading and music" 2>&1) || st=$?
printf '%s\n' "has-session -t =$nname" "new-session -d -s $nname -n micro micro" "new-window -t =$nname -n btop btop" > "$H/expected.none"
[ "$st" -eq 0 ] && cmp -s "$tlog" "$H/expected.none" && ! printf '%s\n' "$out" | grep -q 'also suggested' && printf '%s\n' "$out" | grep -qx '  micro for notes, btop to watch' \
    && jq -e '.why == "micro for notes, btop to watch"' "$desk_last" >/dev/null 2>&1 \
    && ok "named: words that name no app open the model's picks as they are, with its why (said and kept)" || bad "named none" "st=$st $out $(cat "$tlog" "$desk_last")"
printf '{"main": {"app": "editor", "args": "notes.txt"}, "side": [{"app": "btop", "args": ""}]}\n' > "$H/answer.json"
ename=notes-in-micro; : > "$tlog"
st=0; out=$(sh "$SH" layout "notes in micro" 2>&1) || st=$?
printf '%s\n' "has-session -t =$ename" "new-session -d -s $ename -n editor micro notes.txt" > "$H/expected.editor"
[ "$st" -eq 0 ] && cmp -s "$tlog" "$H/expected.editor" && printf '%s\n' "$out" | grep -qx '  also suggested: btop -- add it to your words to open it' \
    && ok "named: the editor's own program (micro) names the editor window" || bad "named editor" "st=$st $out $(cat "$tlog")"
# the box's case: the words name vi and shell, the answer has shell, tmux and btop; vi is added
printf '[Desktop Entry]\nName=tmux\nComment=Terminal multiplexer\nExec=tmux\nTerminal=true\nType=Application\n' > "$XDG_DATA_HOME/applications/tmux.desktop"
printf '{"why": "a shell to write in, tmux to split it, btop to watch", "main": {"app": "shell", "args": "", "width": 60}, "side": [{"app": "tmux", "args": ""}, {"app": "btop", "args": ""}]}\n' > "$H/answer.json"
bname=writing-with-vi-and-shell-window; : > "$tlog"
st=0; out=$(sh "$SH" layout "writing with vi and shell window" 2>&1) || st=$?
printf '%s\n' "has-session -t =$bname" "new-session -d -s $bname -n shell" "new-window -t =$bname -n vi vi" > "$H/expected.box"
[ "$st" -eq 0 ] && cmp -s "$tlog" "$H/expected.box" && ok "named: the box's words (vi and shell) open shell and vi, vi added though the answer lacks it" || bad "named box" "st=$st $out $(cat "$tlog")"
printf '%s\n' "$out" | grep -qx '  also suggested: tmux and btop -- add them to your words to open them' && ok "named: the box's case suggests tmux and btop" || bad "named box suggested" "$out"
printf '%s\n' "$out" | grep -q 'tmux to split it' && bad "named: the box's case said the model's why" "$out" || ok "named: the box's case says no why (the set changed)"
jq -e '.main.app == "shell" and .main.width == 60 and .side == [{"app": "vi", "args": ""}] and (has("why") | not)' "$desk_last" >/dev/null 2>&1 \
    && ok "named: desk.last holds shell and vi, no why" || bad "named box desk.last" "$(cat "$desk_last")"
sh "$SH" layout save box-case >/dev/null; : > "$tlog"
st=0; out=$(sh "$SH" layout box-case 2>&1) || st=$?
[ "$st" -eq 0 ] && grep -q "^new-window -t =$bname -n vi vi\$" "$tlog" && [ "$(printf '%s\n' "$out" | sed -n 2p)" = '  shell' ] \
    && ok "named: the saved layout replays shell and vi with no stale why" || bad "named box replay" "st=$st $out $(cat "$tlog")"
# no named app in the answer: the named ones are the layout (the first the main), the model's picks suggested
printf '{"why": "btop to watch, micro for notes", "main": {"app": "btop", "args": "", "width": 50}, "side": [{"app": "micro", "args": ""}]}\n' > "$H/answer.json"
fname=feeds-in-newsboat-beside-vi; : > "$tlog"
st=0; out=$(sh "$SH" layout "feeds in newsboat beside vi" 2>&1) || st=$?
printf '%s\n' "has-session -t =$fname" "new-session -d -s $fname -n newsboat newsboat" "new-window -t =$fname -n vi vi" > "$H/expected.added"
[ "$st" -eq 0 ] && cmp -s "$tlog" "$H/expected.added" && printf '%s\n' "$out" | grep -qx '  also suggested: btop and micro -- add them to your words to open them' \
    && ! printf '%s\n' "$out" | grep -q 'btop to watch' && jq -e '.main.app == "newsboat" and .main.width == 50 and (.side | map(.app)) == ["vi"] and (has("why") | not)' "$desk_last" >/dev/null 2>&1 \
    && ok "named: none of the answer named, the words name newsboat and vi: those two open, the answer suggested, no why" || bad "named added" "st=$st $out $(cat "$tlog" "$desk_last")"
# editor and its own program are one app: added once
printf '{"why": "btop to watch", "main": {"app": "btop", "args": ""}}\n' > "$H/answer.json"
oname=notes-in-the-editor-with-vi; : > "$tlog"
st=0; out=$(EDITOR="vi" sh "$SH" layout "notes in the editor with vi" 2>&1) || st=$?
printf '%s\n' "has-session -t =$oname" "new-session -d -s $oname -n editor vi" > "$H/expected.once"
[ "$st" -eq 0 ] && cmp -s "$tlog" "$H/expected.once" && printf '%s\n' "$out" | grep -qx '  also suggested: btop -- add it to your words to open it' \
    && ok "named: the words say editor and vi (EDITOR=vi), one editor window opens" || bad "named once" "st=$st $out $(cat "$tlog")"
# the answer is what the words name: unchanged, so its why is said and kept
printf '{"why": "vi to write and btop to watch", "main": {"app": "editor", "args": ""}, "side": [{"app": "btop", "args": ""}]}\n' > "$H/answer.json"
sname_=notes-in-vi-and-btop; : > "$tlog"
st=0; out=$(EDITOR="vi" sh "$SH" layout "notes in vi and btop" 2>&1) || st=$?
printf '%s\n' "has-session -t =$sname_" "new-session -d -s $sname_ -n editor vi" "new-window -t =$sname_ -n btop btop" > "$H/expected.same"
[ "$st" -eq 0 ] && cmp -s "$tlog" "$H/expected.same" && printf '%s\n' "$out" | grep -qx '  vi to write and btop to watch' && ! printf '%s\n' "$out" | grep -q 'also suggested' \
    && jq -e '.why == "vi to write and btop to watch"' "$desk_last" >/dev/null 2>&1 \
    && ok "named: the answer opens unchanged (vi names the editor), so its why is said and kept" || bad "named same" "st=$st $out $(cat "$tlog" "$desk_last")"
rm -f "$XDG_DATA_HOME/applications/tmux.desktop" "$desks/box-case"
sh "$SH" layout save named-one >/dev/null
printf '{"words": "saved as is", "main": {"app": "micro", "args": ""}, "side": [{"app": "btop", "args": ""}]}\n' > "$desks/as-is"; : > "$tlog"
st=0; out=$(sh "$SH" layout as-is 2>&1) || st=$?
[ "$st" -eq 0 ] && grep -q '^new-window -t =saved-as-is -n btop btop$' "$tlog" && ! printf '%s\n' "$out" | grep -q 'also suggested' \
    && ok "named: a saved layout opens as saved, nothing narrowed" || bad "named saved" "st=$st $out $(cat "$tlog")"
rm -f "$H/answer.json" "$desks/as-is" "$desks/named-one"
if [ "$(uname -s)" != Darwin ]; then
    # --desktop from a console: the words wait, sway starts, --pending lays them out once
    theme_fixture '#ff5555'; mkdir -p "$HOME/.config/spark-shell"; printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"
    sh "$SH" on --yes >/dev/null
    desk_pending=$H/.local/state/spark-shell/desk.pending; rm -f "$argv" "$swlog"
    st=0; out=$(TEST_TTY=/dev/tty1 sh "$SH" layout "news and music" --desktop 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$(cat "$desk_pending" 2>&1)" = 'news and music' ] && grep -q 'sway-stub' "$H/.local/state/spark-shell/sway.log" && [ ! -e "$argv" ] \
        && ok "layout WORDS --desktop from a console: the words wait in desk.pending, sway starts, no model call yet" || bad "pending write" "st=$st $out $(cat "$desk_pending" 2>&1)"
    st=0; out=$(SWAYSOCK=$H/sway.sock sh "$SH" layout --pending 2>&1) || st=$?
    [ "$st" -eq 0 ] && printf '%s\n' "$out" | grep -q '^layout> news and music$' && printf '%s\n' "$out" | grep -q '^on workspace 3' && [ ! -e "$desk_pending" ] \
        && [ "$(tail -1 "$argv")" = 'write the layout for this need: news and music' ] \
        && ok "layout --pending: lays the waiting words out as sway windows, the file is gone" || bad "pending play" "st=$st $out"
    st=0; out=$(SWAYSOCK=$H/sway.sock sh "$SH" layout --pending 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ -z "$out" ] && ok "layout --pending twice: a quiet no-op" || bad "pending twice" "st=$st $out"
    rm -f "$argv"
    st=0; out=$(TEST_TTY=/dev/tty1 sh "$SH" desktop "news and music" --windows 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$(cat "$desk_pending" 2>&1)" = 'news and music' ] && [ ! -e "$argv" ] \
        && ok "old spellings: desktop WORDS --windows from a console waits the same" || bad "alias windows" "st=$st $out"
    st=0; out=$(SWAYSOCK=$H/sway.sock sh "$SH" desktop --pending 2>&1) || st=$?
    [ "$st" -eq 0 ] && printf '%s\n' "$out" | grep -q '^layout> news and music$' && [ ! -e "$desk_pending" ] \
        && ok "old spellings: desktop --pending (the sway config's line) lays them out" || bad "alias pending" "st=$st $out"
fi
grep -q '^## Allowed apps$' "$REPO/README.md" && ok "README: Allowed apps" || bad "README allowed apps section"

# --- 19. the console: theme, font, quiet (spark 1.62 handed them over) ----
# Every Linux shape runs on any OS: a uname stub says Linux (or Darwin),
# root paths live under SPARK_SHELL_ROOT, and stubs stand in for
# setvtrgb, setfont, setupcon, update-grub, mkinitcpio, systemctl and
# python3, each logging its arguments to $H/log. A fixture file is
# compared byte for byte with its copy after the hand-back.
console_stubs() {   # console_stubs Linux|Darwin
    mkdir -p "$H/lx" "$H/root/sys/module/vt/parameters"
    printf '#!/bin/sh\nif [ "$1" = -s ]; then echo %s; else exec %s "$@"; fi\n' "$1" "$(command -v uname)" > "$H/lx/uname"
    vga_red='0,170,0,170,0,170,0,170,85,255,85,255,85,255,85,255'
    printf '%s\n' "$vga_red" > "$H/root/sys/module/vt/parameters/default_red"
    cat > "$H/lx/setvtrgb" <<EOF
#!/bin/sh
echo "setvtrgb \$*" >> "$H/log"
if [ "\$1" = vga ]; then echo '$vga_red'; else head -1 "\$1"; fi > "$H/root/sys/module/vt/parameters/default_red"
EOF
    for t in setfont setupcon; do printf '#!/bin/sh\necho "%s $*" >> "%s/log"\n' "$t" "$H" > "$H/lx/$t"; done
    cat > "$H/lx/update-grub" <<EOF
#!/bin/sh
echo "update-grub" >> "$H/log"
[ ! -e "$H/fail" ] || exit 1
mkdir -p "$H/root/boot/grub"
if [ -e "$H/root/etc/default/grub.d/zz-spark-shell-quiet.cfg" ] || grep -q 'spark-shell-quiet' "$H/root/etc/default/grub" 2>/dev/null; then
    echo 'linux /vmlinuz quiet loglevel=3' > "$H/root/boot/grub/grub.cfg"
else echo 'linux /vmlinuz' > "$H/root/boot/grub/grub.cfg"; fi
EOF
    printf '#!/bin/sh\necho "mkinitcpio $*" >> "%s/log"\n[ ! -e "%s/fail" ]\n' "$H" "$H" > "$H/lx/mkinitcpio"
    # the helper: has-profile fails once $H/gone is there, remove once $H/stuck is
    printf '#!/bin/sh\necho "python3 $*" >> "%s/log"\ncase $2 in has-profile) [ ! -e "%s/gone" ] ;; remove) [ ! -e "%s/stuck" ] ;; esac\n' "$H" "$H" "$H" > "$H/lx/python3"
    cat > "$H/lx/systemctl" <<'EOF'
#!/bin/sh
st=${SPARK_SHELL_ROOT:-$HOME/root}/units
mkdir -p "$st"
echo "systemctl $*" >> "$HOME/log"
case $1 in
    enable) touch "$st/$2" ;;
    disable) rm -f "$st/$2" ;;
    is-enabled) [ -e "$st/$2" ] ;;
    is-active) [ -e "$st/active-$2" ] ;;
esac
EOF
    chmod +x "$H/lx"/*
    : > "$H/log"
}
L() { PATH=$H/lx:$PATH sh "$SH" "$@"; }   # spark-shell as the uname stub says
palette_fixture() {   # palette_fixture NAME ACCENT -- a palette of yours, gruvbox's sixteen
    mkdir -p "$HOME/.config/spark-shell/themes"
    {
        printf '# a test palette\nTHEME_BG=#282828\nTHEME_FG=#ebdbb2\nTHEME_ACCENT=%s\nTHEME_MUTED=#928374\n' "$2"
        i=0
        for c in 282828 cc241d 98971a d79921 458588 b16286 689d6a a89984 928374 fb4934 b8bb26 fabd2f 83a598 d3869b 8ec07c ebdbb2; do
            printf 'THEME_ANSI_%d=#%s\n' "$i" "$c"; i=$((i + 1))
        done
    } > "$HOME/.config/spark-shell/themes/$1.env"
}
esc=$(printf '\033')

# theme, systemd: the three files, the unit, the kernel's defaults, then none
fresh
console_stubs Linux
mkdir -p "$H/root/run/systemd/system"
palette_fixture test '#fe8019'
out=$(L theme list)
printf '%s\n' "$out" | grep -q '^  none  *the console' && printf '%s\n' "$out" | grep -q '^  test  *yours$' && ok "theme list: none, and a palette of yours says so" || bad "theme list" "$out"
rc=0; out=$(L theme nosuch 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = "spark-shell theme: no palette named nosuch -- spark-shell theme list shows them" ] && [ ! -e "$HOME/.config/spark-shell/config" ] \
    && ok "theme NAME: an unknown palette is one sentence, exit 1, the config untouched" || bad "theme nosuch" "rc=$rc $out"
sed 's/^THEME_ANSI_3=.*/THEME_ANSI_3=yellow/' "$HOME/.config/spark-shell/themes/test.env" > "$HOME/.config/spark-shell/themes/broken.env"
rc=0; out=$(L theme broken 2>&1) || rc=$?
[ "$rc" = 1 ] && printf '%s\n' "$out" | grep -q 'THEME_ANSI_3 is not #rrggbb' && [ ! -e "$HOME/.config/spark/theme.env" ] && ok "theme NAME: a palette with a key that is not #rrggbb is refused" || bad "theme broken" "rc=$rc $out"
rm -f "$HOME/.config/spark-shell/themes/broken.env"
rc=0; out=$(L theme test 2>&1) || rc=$?
[ "$rc" = 0 ] && grep -qx 'THEME=test' "$HOME/.config/spark-shell/config" && ok "theme test: THEME=test in the config" || bad "theme test config" "rc=$rc $out"
te=$HOME/.config/spark/theme.env
head -1 "$te" | grep -q '^# rendered by spark-shell from the palette test' && [ "$(grep -c '^THEME_' "$te")" = 20 ] && grep -qx 'THEME_ACCENT=#fe8019' "$te" \
    && ok "theme test: theme.env holds the marker and the 20 keys" || bad "theme.env" "$(cat "$te")"
[ "$(cat "$HOME/.config/spark-shell/console-colors")" = "${esc}]P0282828${esc}]P1cc241d${esc}]P298971a${esc}]P3d79921${esc}]P4458588${esc}]P5b16286${esc}]P6689d6a${esc}]P7a89984${esc}]P8928374${esc}]P9fb4934${esc}]Pab8bb26${esc}]Pbfabd2f${esc}]Pc83a598${esc}]Pdd3869b${esc}]Pe8ec07c${esc}]Pfebdbb2" ] \
    && ok "theme test: console-colors holds the 16 escapes, slot 10 as a" || bad "console-colors" "$(od -c "$HOME/.config/spark-shell/console-colors" | head -3)"
[ "$(sed -n 1p "$HOME/.config/spark-shell/console-colors.rgb")" = '40,204,152,215,69,177,104,168,146,251,184,250,131,211,142,235' ] && [ "$(wc -l < "$HOME/.config/spark-shell/console-colors.rgb" | tr -d ' ')" = 3 ] \
    && ok "theme test: console-colors.rgb is setvtrgb's three lines" || bad "console-colors.rgb" "$(cat "$HOME/.config/spark-shell/console-colors.rgb")"
unit=$H/root/etc/systemd/system/spark-shell-console.service
grep -qx "ExecStart=/usr/bin/setvtrgb $HOME/.config/spark-shell/console-colors.rgb" "$unit" && grep -q '^# rendered by spark-shell' "$unit" && grep -q 'systemctl enable spark-shell-console.service' "$H/log" \
    && ok "theme test (systemd): spark-shell-console.service written and enabled" || bad "console unit" "$(cat "$unit" 2>&1; cat "$H/log")"
grep -qx "setvtrgb $HOME/.config/spark-shell/console-colors.rgb" "$H/log" && ok "theme test: the kernel's defaults set now (setvtrgb)" || bad "setvtrgb now" "$(cat "$H/log")"
out=$(L theme test --dry-run)
[ "$(printf '%s\n' "$out" | tail -1)" = "Nothing to do" ] && ! printf '%s\n' "$out" | grep -q '^would' && ok "theme test again: Nothing to do" || bad "theme idempotent" "$out"
ck=$(L check || true)
printf '%s\n' "$ck" | grep -q "^ok     theme        test: theme.env and the console's palette are current$" && ok "check: the theme row is ok" || bad "check theme ok" "$(printf '%s\n' "$ck" | grep theme)"
echo '1,2,3' > "$H/root/sys/module/vt/parameters/default_red"
st=0; ck=$(L check) || st=$?
printf '%s\n' "$ck" | grep -q '^warn   theme        test: the console uses another palette until the next boot -- spark-shell on$' && ok "check: another palette live is a warn with its remedy" || bad "check theme warn" "$(printf '%s\n' "$ck" | grep theme)"
rm -f "$unit"
ck=$(L check || true)
printf '%s\n' "$ck" | grep -q '^FAIL   theme        test: spark-shell-console.service does not set it at boot -- spark-shell on (sudo once)$' && ok "check: a missing unit is a FAIL with its remedy" || bad "check theme fail" "$(printf '%s\n' "$ck" | grep theme)"
L theme test >/dev/null
[ -f "$unit" ] && ok "theme test again: the unit is back" || bad "unit back"
: > "$H/log"
out=$(L theme none)
[ ! -e "$te" ] && [ ! -e "$unit" ] && [ ! -e "$HOME/.config/spark-shell/console-colors" ] && [ ! -e "$HOME/.config/spark-shell/console-colors.rgb" ] \
    && grep -q 'systemctl disable spark-shell-console.service' "$H/log" && grep -qx 'setvtrgb vga' "$H/log" && grep -qx 'THEME=none' "$HOME/.config/spark-shell/config" \
    && ok "theme none: theme.env, the unit and the console files gone, VGA set" || bad "theme none" "$out $(cat "$H/log")"
ck=$(L check || true)
printf '%s\n' "$ck" | grep -q "^ok     theme        none: the console's and the terminal's own colors" && ok "check: theme none is ok" || bad "check none" "$(printf '%s\n' "$ck" | grep theme)"

# the repository's palettes (themes/*.env): each one a theme NAME takes
if ls "$REPO"/themes/*.env >/dev/null 2>&1; then
    for env in "$REPO"/themes/*.env; do
        name=${env##*/}; name=${name%.env}
        rc=0; out=$(L theme "$name" 2>&1) || rc=$?
        [ "$rc" = 0 ] && [ "$(grep -c '^THEME_\(BG\|FG\|ACCENT\|MUTED\|ANSI_[0-9]*\)=#' "$HOME/.config/spark/theme.env")" = 20 ] \
            && ok "theme $name: the repository's palette is taken, 20 keys" || bad "theme $name" "rc=$rc $out"
    done
else
    printf '  NOTICE: no themes/*.env in this clone -- the repository'"'"'s palettes not exercised\n'
fi

# theme repaints the open terminals: plain files stand in for /dev/pts/N
# (SPARK_SHELL_PTS_DIR). 0 is yours and a tmux client's, 1 is not
# writable, 2 is a tmux pane, 3 is not yours, ptmx is never a terminal.
fresh
console_stubs Linux
palette_fixture test '#fe8019'
mkdir -p "$H/pts"
: > "$H/pts/0"; : > "$H/pts/1"; : > "$H/pts/2"; : > "$H/pts/ptmx"; chmod 0444 "$H/pts/1"
if [ "$(id -u)" = 0 ]; then : > "$H/pts/3"; chown 65534 "$H/pts/3"   # root: a file of nobody's
else ln -s /dev/null "$H/pts/3"; fi                                 # a user: root's /dev/null, writable by all
cat > "$H/lx/tmux" <<EOF
#!/bin/sh
echo "tmux \$*" >> "$H/tmux.log"
case \$1 in
    list-panes) echo "$H/pts/2" ;;
    list-clients) echo "$H/pts/0" ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$H/lx/tmux"
want=$H/osc.want; : > "$want"
i=0
for c in 282828 cc241d 98971a d79921 458588 b16286 689d6a a89984 928374 fb4934 b8bb26 fabd2f 83a598 d3869b 8ec07c ebdbb2; do
    printf '\033]4;%d;#%s\033\\' "$i" "$c" >> "$want"; i=$((i + 1))
done
printf '\033]10;#ebdbb2\033\\\033]11;#282828\033\\' >> "$want"
out=$(L theme test)
cmp -s "$want" "$H/pts/0" && ok "theme test: an open terminal of yours gets OSC 4 for the 16 slots, then OSC 10 and 11, byte for byte" || bad "repaint bytes" "$(od -c "$H/pts/0" | head -4)"
[ ! -s "$H/pts/2" ] && grep -q '^tmux list-panes -a -F #{pane_tty}$' "$H/tmux.log" && ok "theme test: a tmux pane gets nothing (tmux would keep the codes), its client's terminal gets them" || bad "repaint tmux pane" "$(od -c "$H/pts/2" | head -2; cat "$H/tmux.log")"
[ ! -s "$H/pts/ptmx" ] && ok "theme test: ptmx is never painted" || bad "repaint ptmx"
if [ "$(id -u)" = 0 ]; then
    [ ! -s "$H/pts/3" ] && ok "theme test: a terminal that is not yours gets nothing" || bad "repaint not yours"
    n=2   # root writes a file whatever its mode, and 1 is root's
else
    [ ! -s "$H/pts/1" ] && ok "theme test: a terminal you cannot write gets nothing" || bad "repaint not writable"
    ok "theme test: /dev/null (root's) is not yours, so it is skipped (the count says so)"
    n=1
fi
if [ "$n" = 1 ]; then said="Repainted 1 open terminal."; else said="Repainted $n open terminals."; fi
[ "$(printf '%s\n' "$out" | tail -2 | head -1)" = "$said" ] && [ "$(printf '%s\n' "$out" | tail -1)" = "The palette is test. A program that is already running, such as btop, takes it when it starts again." ] \
    && ok "theme test: one line counts the terminals, then the closing line" || bad "repaint line" "$out"
printf 'THEME_CURSOR=#FE8019\n' >> "$HOME/.config/spark-shell/themes/test.env"
printf '\033]12;#fe8019\033\\' >> "$want"
L theme test >/dev/null
cmp -s "$want" "$H/pts/0" && ok "theme test: a palette with THEME_CURSOR adds OSC 12, lowercase" || bad "repaint cursor" "$(od -c "$H/pts/0" | tail -3)"
: > "$H/pts/0"
out=$(L theme test --dry-run)
[ ! -s "$H/pts/0" ] && ! printf '%s\n' "$out" | grep -q '^Repainted' && ok "theme test --dry-run: no terminal is painted" || bad "repaint dry" "$out"
out=$(L theme none)
[ "$(cat "$H/pts/0")" = "${esc}]104${esc}\\${esc}]110${esc}\\${esc}]111${esc}\\${esc}]112${esc}\\" ] && [ ! -s "$H/pts/2" ] \
    && ok "theme none: the resets, OSC 104, 110, 111 and 112" || bad "repaint none" "$(od -c "$H/pts/0" | head -3)"
[ "$(printf '%s\n' "$out" | tail -2 | head -1)" = "$said" ] && ok "theme none: the same line counts them" || bad "repaint none line" "$out"
rm -f "$H/pts/0" "$H/pts/1" "$H/pts/3"
out=$(L theme test)
! printf '%s\n' "$out" | grep -q '^Repainted' && ok "theme test: with no terminal to paint, no line" || bad "repaint nothing" "$out"
# macOS: Terminal.app is its profile's, no pty is written
fresh
console_stubs Darwin
palette_fixture test '#fe8019'
mkdir -p "$H/pts"; : > "$H/pts/0"
out=$(L theme test)
[ ! -s "$H/pts/0" ] && ! printf '%s\n' "$out" | grep -q '^Repainted' && ok "macOS: theme test writes to no pty (the profile does it)" || bad "mac repaint" "$out"

# theme, runit: one marked line in /etc/rc.local, and off hands it back byte for byte
fresh
console_stubs Linux
mkdir -p "$H/root/etc/runit"
printf '#!/bin/sh\n# yours\necho hello\n' > "$H/root/etc/rc.local"; cp "$H/root/etc/rc.local" "$H/rc.local.orig"
palette_fixture test '#fe8019'
L theme test >/dev/null
[ "$(grep -c ' #spark-shell-palette#$' "$H/root/etc/rc.local")" = 1 ] && head -3 "$H/root/etc/rc.local" | cmp -s - "$H/rc.local.orig" \
    && grep -q "^\[ -r '$HOME/.config/spark-shell/console-colors.rgb' \] && setvtrgb '$HOME/.config/spark-shell/console-colors.rgb' #spark-shell-palette#\$" "$H/root/etc/rc.local" \
    && [ ! -e "$H/root/etc/systemd" ] && ok "theme test (runit): one marked line at the end of /etc/rc.local, no unit" || bad "rc.local line" "$(cat "$H/root/etc/rc.local")"
ck=$(L check || true)
printf '%s\n' "$ck" | grep -q '^ok     theme        test:' && ok "check (runit): the theme row is ok" || bad "check runit" "$(printf '%s\n' "$ck" | grep theme)"
L theme none >/dev/null
cmp -s "$H/root/etc/rc.local" "$H/rc.local.orig" && ok "theme none (runit): /etc/rc.local byte for byte as it was" || bad "rc.local back" "$(cat "$H/root/etc/rc.local")"
printf '#!/bin/sh\necho hello\nexit 0' > "$H/root/etc/rc.local"; cp "$H/root/etc/rc.local" "$H/rc.local.orig"   # a last line with no newline
L theme test >/dev/null
sed -n 3p "$H/root/etc/rc.local" | grep -q ' #spark-shell-palette#$' && [ "$(tail -c 6 "$H/root/etc/rc.local")" = 'exit 0' ] \
    && printf '%s\n' "$(L check || true)" | grep -q '^ok     theme        test:' && ok "theme test (runit): the line goes before a last exit 0, and check reads it there" || bad "rc.local exit 0" "$(cat "$H/root/etc/rc.local")"
L theme none >/dev/null
cmp -s "$H/root/etc/rc.local" "$H/rc.local.orig" && ok "theme none (runit): byte for byte again, the last line still without a newline" || bad "rc.local exit back" "$(od -c "$H/root/etc/rc.local" | tail -3)"
rm -f "$H/root/etc/rc.local"
L theme test >/dev/null
[ "$(head -1 "$H/root/etc/rc.local")" = '#!/bin/sh' ] && [ "$(wc -l < "$H/root/etc/rc.local" | tr -d ' ')" = 2 ] && ok "theme test (runit): no rc.local, one made with the shebang and the line" || bad "rc.local made" "$(cat "$H/root/etc/rc.local" 2>&1)"
L theme none >/dev/null
[ ! -e "$H/root/etc/rc.local" ] && ok "theme none (runit): the rc.local spark-shell made is gone" || bad "rc.local made gone" "$(cat "$H/root/etc/rc.local")"
# no root file (no systemd, no runit): theme none asks no root, sets no VGA with setvtrgb
fresh
console_stubs Linux
palette_fixture test '#fe8019'
L theme test >/dev/null; : > "$H/log"
L theme none >/dev/null
[ ! -e "$HOME/.config/spark-shell/console-colors" ] && ! grep -q setvtrgb "$H/log" && ok "theme none: only the files in ~/.config, no root asked" || bad "palette off no root" "$(cat "$H/log")"

# on applies THEME from the config before the renders; off hands the palette back
fresh
console_stubs Linux
mkdir -p "$H/root/run/systemd/system" "$HOME/.config/spark-shell"
palette_fixture test '#fb4934'
printf 'THEME=test\n' > "$HOME/.config/spark-shell/config"
out=$(L on --yes)
grep -q 'fg=colour9,bold' "$HOME/.tmux.conf" && [ -f "$H/root/etc/systemd/system/spark-shell-console.service" ] && ok "on: THEME=test is the palette the renders read (colour9), the unit written" || bad "on theme" "$out"
out=$(L on --dry-run)
printf '%s\n' "$out" | grep -q '^Nothing to do$' && ok "on again: Nothing to do with THEME set" || bad "on theme idempotent" "$out"
L theme test >/dev/null
palette_fixture test '#b8bb26'
out=$(L theme test)
grep -q 'fg=colour10,bold' "$HOME/.tmux.conf" && ok "theme NAME with the seat on: the renders follow (colour10)" || bad "theme follows" "$out $(grep color "$HOME/.tmux.conf" | head -2)"
out=$(L off --dry-run)
printf '%s\n' "$out" | grep -q '^would  palette ' && printf '%s\n' "$out" | grep -q '^would  theme ' && [ -f "$HOME/.config/spark/theme.env" ] \
    && ok "off --dry-run: would rows for the palette, nothing touched" || bad "off dry palette" "$out"
out=$(L off)
[ ! -e "$HOME/.config/spark/theme.env" ] && [ ! -e "$H/root/etc/systemd/system/spark-shell-console.service" ] && [ ! -e "$HOME/.config/spark-shell/console-colors" ] \
    && grep -qx 'THEME=test' "$HOME/.config/spark-shell/config" && ok "off: theme.env, the unit and the console files handed back, the config kept" || bad "off palette" "$out"
# a theme.env that is not spark-shell's stays on off
fresh
console_stubs Linux
theme_fixture '#ff5555'
L on --yes >/dev/null; L off >/dev/null
[ -f "$HOME/.config/spark/theme.env" ] && ok "off: a theme.env spark-shell did not write stays" || bad "foreign theme.env removed"

# font: console-setup (Debian), vconsole.conf (Arch), rc.conf (Void)
psf2() { printf '\162\265\112\206\0\0\0\0\040\0\0\0\0\0\0\0\0\1\0\0\100\0\0\0\040\0\0\0\020\0\0\0' | gzip -c > "$1"; }   # a 16x32 PSF2 header, gzipped
psf1() { printf '\066\004\000\020' > "$1"; }                                                                          # an 8x16 PSF1 header
fresh
console_stubs Linux
mkdir -p "$H/root/etc/default" "$H/root/usr/share/consolefonts"
printf 'ACTIVE_CONSOLES="/dev/tty[1-6]"\nCHARMAP="UTF-8"\nCODESET="guess"\nFONTFACE="Fixed"\nFONTSIZE="8x16"\n' > "$H/root/etc/default/console-setup"
cp "$H/root/etc/default/console-setup" "$H/cs.orig"
: > "$H/root/usr/share/consolefonts/Uni2-Terminus32x16.psf.gz"; : > "$H/root/usr/share/consolefonts/Uni2-Fixed16.psf.gz"; : > "$H/root/usr/share/consolefonts/Lat15-TerminusBold32x16.psf.gz"
out=$(L font list)
printf '%s\n' "$out" | grep -q '^  Terminus  *16x32$' && printf '%s\n' "$out" | grep -q '^  Fixed  *8x16$' && printf '%s\n' "$out" | grep -q 'puts one in .*/etc/default/console-setup\.$' \
    && ok "font list (console-setup): the composed faces, WxH" || bad "font list setup" "$out"
rc=0; out=$(L font Terminus 8x16 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = "spark-shell font: Terminus comes in 16x32, not 8x16" ] && ok "font FACE SIZE: a size the face lacks is refused" || bad "font size refused" "rc=$rc $out"
rc=0; out=$(L font Nope 8x16 2>&1) || rc=$?
[ "$rc" = 1 ] && printf '%s\n' "$out" | grep -q '^spark-shell font: no console font named Nope here' && ok "font FACE SIZE: an unknown face is refused" || bad "font face refused" "rc=$rc $out"
out=$(L font Terminus 16x32)
f=$H/root/etc/default/console-setup
grep -qx 'FONTFACE="Terminus"' "$f" && grep -qx 'FONTSIZE="16x32"' "$f" && grep -qx 'CODESET="guess"' "$f" && cmp -s "$f.spark-shell-orig" "$H/cs.orig" && grep -qx 'setupcon --force' "$H/log" \
    && grep -qx 'CONSOLE_FONT=Terminus 16x32' "$HOME/.config/spark-shell/config" && ok "font Terminus 16x32: console-setup set, its copy kept, setupcon ran" || bad "font setup" "$out $(cat "$f")"
[ "$(L font)" = "font  Terminus 16x32 ($f)" ] && ok "font: bare says the one in use" || bad "font show" "$(L font)"
ck=$(L check || true)
printf '%s\n' "$ck" | grep -q "^ok     font         Terminus 16x32 ($f)$" && ok "check: the font row is ok" || bad "check font" "$(printf '%s\n' "$ck" | grep font)"
printf '%s\n' "$(sed 's/^FONTFACE=.*/FONTFACE="VGA"/' "$f")" > "$f"
ck=$(L check || true)
printf '%s\n' "$ck" | grep -q "^FAIL   font         $f says VGA 16x32 -- spark-shell on (sudo once)$" && ok "check: a changed font is a FAIL with its remedy" || bad "check font fail" "$(printf '%s\n' "$ck" | grep font)"
L font none >/dev/null
cmp -s "$f" "$H/cs.orig" && [ ! -e "$f.spark-shell-orig" ] && ok "font none: console-setup byte for byte as it was, the copy gone" || bad "font none setup" "$(diff "$H/cs.orig" "$f")"
# vconsole.conf: a kbd font file's stem, its size from its own header
fresh
console_stubs Linux
mkdir -p "$H/root/etc" "$H/root/usr/share/kbd/consolefonts"
printf 'KEYMAP=us\n' > "$H/root/etc/vconsole.conf"; cp "$H/root/etc/vconsole.conf" "$H/vc.orig"
psf2 "$H/root/usr/share/kbd/consolefonts/ter-132n.psf.gz"; psf1 "$H/root/usr/share/kbd/consolefonts/lat2-16.psfu"
out=$(L font list)
printf '%s\n' "$out" | grep -q '^  ter-132n  *16x32$' && printf '%s\n' "$out" | grep -q '^  lat2-16  *8x16$' && ok "font list (vconsole): sizes read from each file's header (PSF2, PSF1)" || bad "font list vconsole" "$out"
L font ter-132n 16x32 >/dev/null
grep -qx 'FONT=ter-132n' "$H/root/etc/vconsole.conf" && grep -qx 'systemctl restart systemd-vconsole-setup' "$H/log" && ok "font ter-132n 16x32: vconsole.conf FONT= added, the console redrawn" || bad "font vconsole" "$(cat "$H/root/etc/vconsole.conf")"
L font none >/dev/null
cmp -s "$H/root/etc/vconsole.conf" "$H/vc.orig" && ok "font none: vconsole.conf as it was (the added line gone)" || bad "font none vconsole" "$(cat "$H/root/etc/vconsole.conf")"
# rc.conf beside /etc/runit: the commented FONT= line is the one taken over, and given back
fresh
console_stubs Linux
mkdir -p "$H/root/etc/runit" "$H/root/usr/share/kbd/consolefonts"
printf '# /etc/rc.conf\nHARDWARECLOCK="UTC"\n#FONT="lat9w-16"\n#FONT_MAP=\n' > "$H/root/etc/rc.conf"; cp "$H/root/etc/rc.conf" "$H/rc.orig"
psf2 "$H/root/usr/share/kbd/consolefonts/ter-132n.psf.gz"
L font ter-132n 16x32 >/dev/null
[ "$(sed -n 3p "$H/root/etc/rc.conf")" = 'FONT="ter-132n"' ] && grep -qx '#FONT_MAP=' "$H/root/etc/rc.conf" && grep -qx 'setfont ter-132n' "$H/log" \
    && ok "font ter-132n 16x32 (rc.conf): the #FONT= line taken over, FONT_MAP kept, setfont now" || bad "font rcconf" "$(cat "$H/root/etc/rc.conf")"
L font none >/dev/null
cmp -s "$H/root/etc/rc.conf" "$H/rc.orig" && ok "font none (rc.conf): byte for byte as it was" || bad "font none rcconf" "$(cat "$H/root/etc/rc.conf")"
# no console file, and WSL: one sentence each
fresh
console_stubs Linux
rc=0; out=$(L font ter-132n 16x32 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = "spark-shell font: this Linux has no console-setup, vconsole.conf or rc.conf." ] && ok "font: no console file here, one sentence" || bad "font no shape" "rc=$rc $out"
rc=0; out=$(WSL_DISTRO_NAME=Debian L font ter-132n 16x32 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = "spark-shell font: WSL has no console: the font is Windows Terminal's." ] && ok "font on WSL: one sentence" || bad "font wsl" "rc=$rc $out"

# quiet login: the motd, the issue and 10-uname, back only while still spark-shell's
fresh
console_stubs Linux
mkdir -p "$H/root/etc/update-motd.d"
printf 'The programs included with Debian are free software.\n' > "$H/root/etc/motd"; printf 'Debian GNU/Linux 13 \\n \\l\n\n' > "$H/root/etc/issue"
printf '#!/bin/sh\nuname -snrvm\n' > "$H/root/etc/update-motd.d/10-uname"; chmod +x "$H/root/etc/update-motd.d/10-uname"
cp "$H/root/etc/motd" "$H/motd.orig"; cp "$H/root/etc/issue" "$H/issue.orig"
L quiet login on >/dev/null
[ ! -s "$H/root/etc/motd" ] && [ "$(cat "$H/root/etc/issue")" = "${esc}[?25h" ] && [ ! -x "$H/root/etc/update-motd.d/10-uname" ] && grep -qx 'QUIET_LOGIN=yes' "$HOME/.config/spark-shell/config" \
    && cmp -s "$H/root/etc/motd.spark-shell-orig" "$H/motd.orig" && ok "quiet login on: motd empty, issue the cursor escape, 10-uname off, copies kept" || bad "quiet login on" "$(ls -la "$H/root/etc")"
out=$(L quiet login on --dry-run)
[ "$(printf '%s\n' "$out" | tail -1)" = "Nothing to do" ] && ! printf '%s\n' "$out" | grep -q '^would' && ok "quiet login on again: Nothing to do" || bad "quiet login idempotent" "$out"
ck=$(L check || true)
printf '%s\n' "$ck" | grep -q '^ok     quiet        login quiet, ' && ok "check: the quiet row says login quiet" || bad "check quiet login" "$(printf '%s\n' "$ck" | grep quiet)"
L quiet login off >/dev/null
cmp -s "$H/root/etc/motd" "$H/motd.orig" && cmp -s "$H/root/etc/issue" "$H/issue.orig" && [ -x "$H/root/etc/update-motd.d/10-uname" ] && [ ! -e "$H/root/etc/motd.spark-shell-orig" ] \
    && ok "quiet login off: motd and issue byte for byte, 10-uname runs again" || bad "quiet login off" "$(ls -la "$H/root/etc")"
L quiet login on >/dev/null
printf 'mine now\n' > "$H/root/etc/motd"
L quiet login off >/dev/null
[ "$(cat "$H/root/etc/motd")" = 'mine now' ] && [ ! -e "$H/root/etc/motd.spark-shell-orig" ] && cmp -s "$H/root/etc/issue" "$H/issue.orig" \
    && ok "quiet login off: a motd you changed since stays yours, only the stale copy goes" || bad "quiet login yours" "$(cat "$H/root/etc/motd")"
[ "$(L quiet login)" = "login  off: the distro's notice and the kernel line (spark-shell quiet login on)" ] && ok "quiet login: bare says the state" || bad "quiet login show" "$(L quiet login)"
# only spark-shell's own records: never an escape-only issue it did not
# write, nothing while spark core's /etc/issue.orig is there
printf '%s' "${esc}[?25h" > "$H/root/etc/issue"
L quiet login off >/dev/null
[ "$(cat "$H/root/etc/issue")" = "${esc}[?25h" ] && ok "quiet login off: an escape-only issue spark-shell did not write stays" || bad "foreign issue" "$(od -c "$H/root/etc/issue")"
printf 'Debian\n' > "$H/root/etc/issue.orig"; printf 'ours\n' > "$H/root/etc/issue.spark-shell-orig"
L quiet login off >/dev/null
[ "$(cat "$H/root/etc/issue")" = "${esc}[?25h" ] && [ -e "$H/root/etc/issue.orig" ] && [ -e "$H/root/etc/issue.spark-shell-orig" ] \
    && ok "quiet login off: nothing moves while spark core's /etc/issue.orig is there" || bad "spark core issue" "$(ls "$H/root/etc")"
rm -f "$H/root/etc/issue.orig"; : > "$H/root/etc/issue"
L quiet login off >/dev/null
[ "$(cat "$H/root/etc/issue")" = ours ] && [ ! -e "$H/root/etc/issue.spark-shell-orig" ] && ok "quiet login off: an empty issue comes back from spark-shell's copy" || bad "empty issue" "$(cat "$H/root/etc/issue")"
# Debian 13 has no /etc/motd: 10-uname comes back by its own mark
rm -f "$H/root/etc/motd"; chmod +x "$H/root/etc/update-motd.d/10-uname"
L quiet login on >/dev/null
[ ! -x "$H/root/etc/update-motd.d/10-uname" ] && [ -e "$HOME/.local/state/spark-shell/uname.off" ] && ok "quiet login on, no motd: 10-uname off, its mark kept" || bad "uname off" "$(ls -la "$H/root/etc/update-motd.d")"
L quiet login off >/dev/null
[ -x "$H/root/etc/update-motd.d/10-uname" ] && [ ! -e "$HOME/.local/state/spark-shell/uname.off" ] && ok "quiet login off, no motd: 10-uname runs again" || bad "uname back" "$(ls -la "$H/root/etc/update-motd.d")"
rc=0; out=$(L quiet loud on 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = "spark-shell quiet: loud is not known here (login or boot)" ] && ok "quiet WORD: an unknown word is one sentence" || bad "quiet word" "rc=$rc $out"

# quiet boot, Debian: one GRUB drop-in, /etc/default/grub never edited, a failed rebuild runs again
fresh
console_stubs Linux
printf 'ID=debian\n' > "$H/os-release"
mkdir -p "$H/root/etc/default"
printf 'GRUB_DEFAULT=0\nGRUB_TIMEOUT=5\nGRUB_CMDLINE_LINUX_DEFAULT="quiet"\n' > "$H/root/etc/default/grub"; cp "$H/root/etc/default/grub" "$H/grub.orig"
L quiet boot on --yes >/dev/null
d=$H/root/etc/default/grub.d/zz-spark-shell-quiet.cfg
[ "$(cat "$d")" = "GRUB_TIMEOUT=0
GRUB_TIMEOUT_STYLE=hidden
GRUB_CMDLINE_LINUX_DEFAULT=\"\$GRUB_CMDLINE_LINUX_DEFAULT quiet splash loglevel=3 systemd.show_status=false udev.log_level=3 fbcon=nodefer\"" ] \
    && cmp -s "$H/root/etc/default/grub" "$H/grub.orig" && grep -qx update-grub "$H/log" && [ ! -e "$HOME/.local/state/spark-shell/boot-rebuild" ] \
    && ok "quiet boot on (Debian): the drop-in, update-grub, /etc/default/grub untouched" || bad "quiet boot grub" "$(cat "$d" 2>&1)"
out=$(L quiet boot on --dry-run)
[ "$(printf '%s\n' "$out" | tail -1)" = "Nothing to do" ] && ! printf '%s\n' "$out" | grep -q '^would' && ok "quiet boot on again: Nothing to do" || bad "quiet boot idempotent" "$out"
ck=$(L check || true)
printf '%s\n' "$ck" | grep -q '^ok     quiet        login loud, boot quiet$' && ok "check: boot quiet" || bad "check boot quiet" "$(printf '%s\n' "$ck" | grep quiet)"
mkdir -p "$H/root/proc"; echo 'BOOT_IMAGE=/vmlinuz ro quiet' > "$H/root/proc/cmdline"
ck=$(L check || true)
printf '%s\n' "$ck" | grep -q '^warn   quiet        login loud, boot quiet after a reboot -- reboot: the next boot is quiet$' && ok "check: a running kernel without the line is a warn" || bad "check boot warn" "$(printf '%s\n' "$ck" | grep quiet)"
: > "$H/fail"
out=$(L quiet boot off)
[ ! -e "$d" ] && grep -qx grub "$HOME/.local/state/spark-shell/boot-rebuild" && printf '%s\n' "$out" | grep -q '^todo   quiet        boot: update-grub failed -- spark-shell on runs it again$' \
    && ok "quiet boot off, update-grub failing: the drop-in gone, the rebuild pending, a todo" || bad "boot off fail" "$out"
ck=$(L check || true)
printf '%s\n' "$ck" | grep -q '^FAIL   quiet        login loud, boot still quiet (QUIET_BOOT=no) -- spark-shell on (sudo once)$' && ok "check: a pending rebuild is a FAIL" || bad "check pending" "$(printf '%s\n' "$ck" | grep quiet)"
rm -f "$H/fail"; : > "$H/log"
L on --yes >/dev/null
grep -qx update-grub "$H/log" && [ ! -e "$HOME/.local/state/spark-shell/boot-rebuild" ] && cmp -s "$H/root/etc/default/grub" "$H/grub.orig" \
    && ok "on: the pending update-grub runs again and the mark goes" || bad "rebuild retry" "$(cat "$H/log")"
# quiet boot, Void: marked lines at the end of three files, byte for byte back
fresh
console_stubs Linux
printf 'ID="void"\n' > "$H/os-release"
mkdir -p "$H/root/etc/default" "$H/root/etc/runit" "$H/root/etc/sv/agetty-tty1"
printf 'GRUB_DEFAULT=0\nGRUB_TIMEOUT=5' > "$H/root/etc/default/grub"   # no final newline: the first marked line must not glue on
printf '# /etc/rc.conf\nKEYMAP="us"\n' > "$H/root/etc/rc.conf"; printf 'GETTY_ARGS="--noclear"\n' > "$H/root/etc/sv/agetty-tty1/conf"
cp "$H/root/etc/rc.conf" "$H/rc.orig"; cp "$H/root/etc/sv/agetty-tty1/conf" "$H/getty.orig"
L quiet boot on --yes >/dev/null
[ "$(grep -c ' #spark-shell-quiet#$' "$H/root/etc/default/grub")" = 3 ] && [ "$(grep -c ' #spark-shell-quiet#$' "$H/root/etc/rc.conf")" = 10 ] && [ "$(grep -c ' #spark-shell-quiet#$' "$H/root/etc/sv/agetty-tty1/conf")" = 2 ] \
    && grep -qx 'GRUB_TIMEOUT=5' "$H/root/etc/default/grub" && grep -qx 'GRUB_TIMEOUT=0 #spark-shell-quiet#' "$H/root/etc/default/grub" && grep -qx update-grub "$H/log" \
    && ok "quiet boot on (Void): 3, 10 and 2 marked lines, nothing glued, update-grub" || bad "quiet boot void" "$(cat "$H/root/etc/default/grub")"
sh -n "$H/root/etc/rc.conf" && sh -n "$H/root/etc/sv/agetty-tty1/conf" && ok "quiet boot on (Void): rc.conf and the getty's conf still parse" || bad "void lines parse"
ck=$(L check || true)
printf '%s\n' "$ck" | grep -q '^ok     quiet        login loud, boot quiet$' && ok "check (Void): boot quiet" || bad "check void boot" "$(printf '%s\n' "$ck" | grep quiet)"
L quiet boot off >/dev/null
[ "$(cat "$H/root/etc/default/grub")" = "$(printf 'GRUB_DEFAULT=0\nGRUB_TIMEOUT=5')" ] && cmp -s "$H/root/etc/rc.conf" "$H/rc.orig" && cmp -s "$H/root/etc/sv/agetty-tty1/conf" "$H/getty.orig" \
    && ok "quiet boot off (Void): the three files as they were (grub's lines, rc.conf and the getty's byte for byte)" || bad "void off" "$(cat "$H/root/etc/rc.conf")"
# quiet boot, Arch with a unified kernel image: the cmdline drop-in, the splash marked, loader.conf's wait
fresh
console_stubs Linux
printf 'ID=arch\n' > "$H/os-release"
mkdir -p "$H/root/etc/mkinitcpio.d" "$H/root/boot/loader"
printf 'ALL_kver="/boot/vmlinuz-linux"\ndefault_uki="/efi/EFI/Linux/arch-linux.efi"\ndefault_options="--splash /usr/share/systemd/bootctl/splash-arch.bmp"\n' > "$H/root/etc/mkinitcpio.d/linux.preset"
printf 'timeout 3\n#console-mode max\n' > "$H/root/boot/loader/loader.conf"
cp "$H/root/etc/mkinitcpio.d/linux.preset" "$H/preset.orig"; cp "$H/root/boot/loader/loader.conf" "$H/loader.orig"
L quiet boot on --yes >/dev/null
[ "$(cat "$H/root/etc/cmdline.d/zz-spark-shell-quiet.conf")" = 'quiet splash loglevel=3 systemd.show_status=false udev.log_level=3 fbcon=nodefer' ] \
    && grep -q '^#spark-shell-quiet# default_options=' "$H/root/etc/mkinitcpio.d/linux.preset" && [ "$(head -1 "$H/root/boot/loader/loader.conf")" = 'timeout 0' ] && grep -qx 'mkinitcpio -P' "$H/log" \
    && ok "quiet boot on (Arch UKI): the drop-in, the splash marked off, timeout 0, mkinitcpio -P" || bad "quiet boot uki" "$(cat "$H/root/etc/mkinitcpio.d/linux.preset" "$H/root/boot/loader/loader.conf")"
L quiet boot off >/dev/null
[ ! -e "$H/root/etc/cmdline.d/zz-spark-shell-quiet.conf" ] && cmp -s "$H/root/etc/mkinitcpio.d/linux.preset" "$H/preset.orig" && cmp -s "$H/root/boot/loader/loader.conf" "$H/loader.orig" \
    && [ "$(grep -c 'mkinitcpio -P' "$H/log")" = 2 ] && ok "quiet boot off (Arch UKI): the preset and loader.conf byte for byte, the image rebuilt" || bad "uki off" "$(cat "$H/root/boot/loader/loader.conf")"
# the ESP is vfat: a chmod there fails, and quiet boot on still reaches mkinitcpio -P
mkdir -p "$H/esp"
printf '#!/bin/sh\nfor a; do case $a in %s/root/boot/*) echo "chmod: not permitted" >&2; exit 1 ;; esac; done\nexec /bin/chmod "$@"\n' "$H" > "$H/esp/chmod"; /bin/chmod +x "$H/esp/chmod"
rm -f "$H/root/boot/loader/loader.conf"; : > "$H/log"
rc=0; PATH=$H/esp:$H/lx:$PATH sh "$SH" quiet boot on --yes >/dev/null 2>&1 || rc=$?
[ "$rc" = 0 ] && [ "$(cat "$H/root/boot/loader/loader.conf")" = 'timeout 0' ] && [ -e "$H/root/boot/loader/loader.conf.spark-shell-orig" ] && grep -qx 'mkinitcpio -P' "$H/log" \
    && ok "quiet boot on (Arch UKI, vfat ESP): a failed chmod is no error, timeout 0 and mkinitcpio -P" || bad "uki vfat" "rc=$rc $(cat "$H/log")"
PATH=$H/esp:$H/lx:$PATH sh "$SH" quiet boot off >/dev/null 2>&1
[ ! -s "$H/root/boot/loader/loader.conf" ] && [ ! -e "$H/root/boot/loader/loader.conf.spark-shell-orig" ] && ok "quiet boot off (Arch UKI, vfat ESP): no timeout line of spark-shell's left" || bad "uki vfat off" "$(cat "$H/root/boot/loader/loader.conf")"
# refused in one sentence: an Arch without a UKI, WSL, macOS
rm -f "$H/root/etc/mkinitcpio.d/linux.preset"
rc=0; out=$(L quiet boot on 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = "spark-shell quiet: This Arch has no unified kernel image, so its kernel line is the boot loader's and stays as it is." ] && grep -qx 'QUIET_BOOT=no' "$HOME/.config/spark-shell/config" \
    && ok "quiet boot on (Arch, no UKI): one sentence, the config untouched" || bad "arch no uki" "rc=$rc $out"
rc=0; out=$(WSL_DISTRO_NAME=Debian L quiet boot on 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = "spark-shell quiet: WSL has no boot of its own: Windows boots it." ] && ok "quiet boot on (WSL): one sentence" || bad "wsl boot" "rc=$rc $out"

# on and off: every key applied from the config, then everything handed back byte for byte
fresh
console_stubs Linux
printf 'ID=debian\n' > "$H/os-release"
mkdir -p "$H/root/run/systemd/system" "$H/root/etc/default" "$H/root/usr/share/consolefonts" "$HOME/.config/spark-shell"
printf 'FONTFACE="Fixed"\nFONTSIZE="8x16"\n' > "$H/root/etc/default/console-setup"; : > "$H/root/usr/share/consolefonts/Uni2-Terminus32x16.psf.gz"
printf 'GRUB_TIMEOUT=5\n' > "$H/root/etc/default/grub"; printf 'motd\n' > "$H/root/etc/motd"; printf 'issue\n' > "$H/root/etc/issue"
( cd "$H/root" && find etc -type f | sort | while read -r f; do cksum "$f"; done ) > "$H/before"
palette_fixture test '#fe8019'
printf 'THEME=test\nCONSOLE_FONT=Terminus 16x32\nQUIET_LOGIN=yes\nQUIET_BOOT=yes\n' > "$HOME/.config/spark-shell/config"
L on --yes >/dev/null
ck=$(L check || true)
[ "$(printf '%s\n' "$ck" | grep -cE '^ok     (theme|font|quiet) ')" = 3 ] && ok "on: THEME, CONSOLE_FONT and QUIET_* applied from the config, three ok rows" || bad "on console" "$(printf '%s\n' "$ck" | grep -E 'theme|font|quiet')"
st=$(L status)
printf '%s\n' "$st" | grep -q '^  font  Terminus 16x32 ' && printf '%s\n' "$st" | grep -q '^  quiet login on  *boot on (' && printf '%s\n' "$st" | grep -q '^  theme test ' \
    && ok "status: the theme, font and quiet rows" || bad "status console" "$st"
L off >/dev/null
( cd "$H/root" && find etc -type f | sort | while read -r f; do cksum "$f"; done ) > "$H/after"
cmp -s "$H/before" "$H/after" && [ ! -e "$HOME/.config/spark/theme.env" ] && ok "off: every root file byte for byte as before, no copy, no unit, no drop-in" || bad "off console" "$(diff "$H/before" "$H/after")"

# Void: the terminal setup; the package names looked up through xbps
fresh
console_stubs Linux
printf 'NAME="Void"\nID="void"\n' > "$H/os-release"
printf '#!/bin/sh\nexit 0\n' > "$H/lx/xbps-query"; chmod +x "$H/lx/xbps-query"
out=$(L on --dry-run)
printf '%s\n' "$out" | grep -q '^ok     packages     installed$' && printf '%s\n' "$out" | grep -q '^skip   desktop      DESKTOP=none (the config)$' \
    && ok "Void: xbps finds the packages, the desktop row is the config's" || bad "void dry-run" "$out"
L on --yes >/dev/null
ck=$(L check || true)
printf '%s\n' "$ck" | grep -q '^ok     desktop      na (DESKTOP=none)$' && ok "Void: check says the desktop is na while DESKTOP=none" || bad "void check" "$(printf '%s\n' "$ck" | grep desktop)"
grep -q '^PKG_CONSOLE=kbd$' "$REPO/distro/void.env" && ok "distro/void.env: kbd for the console" || bad "void.env"
if command -v jq >/dev/null 2>&1; then
    mkdir -p "$H/root/var/db/xbps"
    printf '<key>files</key><string>/usr/bin/tmux</string>\n' > "$H/root/var/db/xbps/.tmux-files.plist"
    cat > "$H/lx/xbps-query" <<'EOF'
#!/bin/sh
case "$1" in
    -m) echo tmux-3.7c_1 ;;
    -l) echo 'ii tmux-3.7c_1                        Terminal Multiplexer'; echo 'ii ncurses-libs-6.6_1                Libraries' ;;
    -p) [ "$3" = tmux ] && echo ISC ;;
esac
exit 0
EOF
    out=$(L sbom tmux)
    printf '%s\n' "$out" | grep -q '^tool  tmux 3.7c_1$' && printf '%s\n' "$out" | grep -q '^  licence   ISC$' && printf '%s\n' "$out" | grep -q '^  reason    chosen$' && printf '%s\n' "$out" | grep -q '^  commands  tmux$' \
        && ok "Void: sbom reads xbps (version, licence, chosen, commands)" || bad "void sbom" "$out"
fi

# Void: the desktop too. No logind there, so on desktop links seatd into
# /var/service and adds you to _seatd, each with a record of its own, and
# off desktop undoes exactly what the records say. The package manager,
# usermod, gpasswd and pgrep are stubs; /etc/group is the root's.
void_desktop() {   # void_desktop -- a fresh Void root: runit, seatd's service dir, /var/service, /etc/group
    fresh
    console_stubs Linux
    desktop_stubs
    printf 'NAME="Void"\nID="void"\n' > "$H/os-release"
    mkdir -p "$H/root/etc/runit" "$H/root/etc/sv/seatd" "$H/root/var/service"
    printf 'root:x:0:\nwheel:x:4:%s\n_seatd:x:990:\n' "$(id -un)" > "$H/root/etc/group"
    printf '#!/bin/sh\nexit 0\n' > "$H/lx/xbps-query"
    cat > "$H/lx/usermod" <<'EOF'
#!/bin/sh
echo "usermod $*" >> "$HOME/log"
[ "$1" = -aG ] || exit 2
awk -F: -v OFS=: -v g="$2" -v u="$3" '$1 == g { $4 = ($4 == "" ? u : $4 "," u) } { print }' "$SPARK_SHELL_ROOT/etc/group" > "$HOME/group.new" && cat "$HOME/group.new" > "$SPARK_SHELL_ROOT/etc/group"
EOF
    cat > "$H/lx/gpasswd" <<'EOF'
#!/bin/sh
echo "gpasswd $*" >> "$HOME/log"
[ "$1" = -d ] || exit 2
awk -F: -v OFS=: -v u="$2" -v g="$3" '$1 == g { n = split($4, m, ","); s = ""; for (i = 1; i <= n; i++) if (m[i] != u) s = (s == "" ? m[i] : s "," m[i]); $4 = s } { print }' "$SPARK_SHELL_ROOT/etc/group" > "$HOME/group.new" && cat "$HOME/group.new" > "$SPARK_SHELL_ROOT/etc/group"
EOF
    printf '#!/bin/sh\n[ -e "%s/sway-running" ]\n' "$H" > "$H/lx/pgrep"
    chmod +x "$H/lx"/*
}
me=$(id -un)
void_desktop
out=$(L on desktop --dry-run </dev/null)
printf '%s\n' "$out" | grep -q '^would  desktop      seatd: link /etc/sv/seatd into /var/service' && printf '%s\n' "$out" | grep -q "^would  desktop      add $me to the _seatd group (sudo)\$" \
    && [ ! -e "$H/root/var/service/seatd" ] && ! grep -q 'usermod' "$H/log" && [ ! -e "$HOME/.config/spark-shell/config" ] \
    && ok "Void: on desktop --dry-run says seatd and the group, touches nothing" || bad "void desktop dry-run" "$out"
out=$(L on desktop --yes </dev/null 2>&1); st=$?
[ "$st" -eq 0 ] && [ -L "$H/root/var/service/seatd" ] && [ "$(readlink "$H/root/var/service/seatd")" = /etc/sv/seatd ] \
    && ok "Void: on desktop links /etc/sv/seatd into /var/service" || bad "void seatd link" "st=$st $out"
grep -q "^_seatd:x:990:$me\$" "$H/root/etc/group" && grep -qx "usermod -aG _seatd $me" "$H/log" && ok "Void: on desktop adds you to _seatd (usermod -aG)" || bad "void group" "$(cat "$H/root/etc/group" "$H/log")"
[ -f "$HOME/.local/state/spark-shell/seatd.linked" ] && [ -f "$HOME/.local/state/spark-shell/seatd.group" ] && ok "Void: both steps recorded (seatd.linked, seatd.group)" || bad "void records" "$(ls "$HOME/.local/state/spark-shell" 2>&1)"
printf '%s\n' "$out" | grep -q "^ok     desktop      $me is in the _seatd group now: it takes effect at your next login\$" && ok "Void: one line says the group takes effect at the next login" || bad "void group line" "$out"
grep -q '^DESKTOP=sway$' "$HOME/.config/spark-shell/config" && [ -f "$HOME/.config/sway/config" ] && [ -f "$HOME/.config/foot/foot.ini" ] && ok "Void: on desktop writes DESKTOP=sway and renders sway and foot" || bad "void renders" "$out"
[ ! -e "$H/root/etc/greetd" ] && ! grep -q 'greetd\|getty' "$H/log" && ok "Void: no greetd, getty left alone" || bad "void greetd" "$(cat "$H/log")"
: > "$H/log"; out=$(L on --dry-run </dev/null)
[ "$(printf '%s\n' "$out" | tail -1)" = 'Nothing to do' ] && ok "Void: on --dry-run after on desktop: Nothing to do" || bad "void idempotent" "$out"
ck=$(L check || true)
printf '%s\n' "$ck" | grep -q '^ok     desktop      sway and foot' && ok "Void: check says the desktop is ok" || bad "void check ok" "$(printf '%s\n' "$ck" | grep desktop)"
printf '#!/bin/sh\n:\n' > "$H/.local/bin/spark"; chmod +x "$H/.local/bin/spark"
st=$(L status); printf '%s\n' "$st" | grep -q '^  next  desktop .*Log out and in again: the _seatd group takes effect at the next login\.$' && ok "Void: status next says to log in again for the group" || bad "void next group" "$(printf '%s\n' "$st" | grep next)"
rm -f "$H/root/var/service/seatd"
ck=$(L check || true)
printf '%s\n' "$ck" | grep -q '^FAIL   desktop      seatd does not start at boot (Void has no logind) -- spark-shell on desktop$' && ok "Void: check FAILs without seatd at boot, the remedy is on desktop" || bad "void check seatd" "$(printf '%s\n' "$ck" | grep desktop)"
st=$(L status); printf '%s\n' "$st" | grep -q '^  next  desktop .*spark-shell on desktop at a terminal sets up seatd (sudo once)\.$' && ok "Void: status next says on desktop sets up seatd" || bad "void next seatd" "$(printf '%s\n' "$st" | grep next)"
rm -f "$H/.local/bin/spark"
L on --yes >/dev/null </dev/null
[ -L "$H/root/var/service/seatd" ] && ok "Void: on (DESKTOP=sway) links seatd again" || bad "void relink"
out=$(L desktop wallpaper none 2>&1) && grep -q '^WALLPAPER=none$' "$HOME/.config/spark-shell/config" && ok "Void: desktop wallpaper is no longer refused" || bad "void wallpaper" "$out"
# off desktop while a desktop runs: seatd stays (stopping it would end it), the group goes
: > "$H/sway-running"; : > "$H/log"
out=$(L off desktop 2>&1)
[ -L "$H/root/var/service/seatd" ] && [ -f "$HOME/.local/state/spark-shell/seatd.linked" ] && printf '%s\n' "$out" | grep -q '^todo   desktop      seatd stays while a desktop runs' \
    && ok "Void: off desktop with a desktop running keeps seatd, one todo row" || bad "void off running" "$out"
! grep -q "^_seatd:x:990:.*$me" "$H/root/etc/group" && grep -qx "gpasswd -d $me _seatd" "$H/log" && [ ! -e "$HOME/.local/state/spark-shell/seatd.group" ] \
    && ok "Void: off desktop takes you out of _seatd (gpasswd -d), the record gone" || bad "void off group" "$(cat "$H/root/etc/group" "$H/log")"
rm -f "$H/sway-running"
out=$(L off desktop --dry-run)
printf '%s\n' "$out" | grep -q "^would  desktop      seatd's link and your _seatd membership removed" && [ -L "$H/root/var/service/seatd" ] && ok "Void: off desktop --dry-run says seatd, touches nothing" || bad "void off dry" "$out"
out=$(L off desktop 2>&1)
[ ! -e "$H/root/var/service/seatd" ] && [ ! -L "$H/root/var/service/seatd" ] && [ ! -e "$HOME/.local/state/spark-shell/seatd.linked" ] && printf '%s\n' "$out" | grep -q '^ok     desktop      seatd no longer starts at boot' \
    && ok "Void: off desktop after leaving the desktop removes the link spark-shell made" || bad "void off link" "$out"
[ -d "$H/root/etc/sv/seatd" ] && ok "Void: off desktop leaves the package's /etc/sv/seatd alone" || bad "void sv dir"
: > "$H/log"; out=$(L off desktop 2>&1)
! printf '%s\n' "$out" | grep -q 'seatd' && ! grep -q 'gpasswd\|usermod' "$H/log" && ok "Void: off desktop twice: nothing of seatd's left to undo, nothing said" || bad "void off twice" "$out"
# a seatd you set up yourself: on desktop records nothing, off desktop leaves it
void_desktop
ln -s /etc/sv/seatd "$H/root/var/service/seatd"
printf 'root:x:0:\n_seatd:x:990:%s\n' "$me" > "$H/root/etc/group"; cp "$H/root/etc/group" "$H/group.orig"
L on desktop --yes >/dev/null </dev/null
[ ! -e "$HOME/.local/state/spark-shell/seatd.linked" ] && [ ! -e "$HOME/.local/state/spark-shell/seatd.group" ] && ! grep -q usermod "$H/log" && ok "Void: a seatd and a group already there are not recorded as spark-shell's" || bad "void yours on" "$(ls "$HOME/.local/state/spark-shell")"
L off >/dev/null
[ -L "$H/root/var/service/seatd" ] && cmp -s "$H/root/etc/group" "$H/group.orig" && ! grep -q gpasswd "$H/log" && ok "Void: off leaves your own seatd link and membership as they were" || bad "void yours off" "$(cat "$H/log")"
# seatd not installed yet: a todo row after the packages, nothing linked
void_desktop
rm -rf "$H/root/etc/sv/seatd"
out=$(L on desktop --yes </dev/null 2>&1)
printf '%s\n' "$out" | grep -q '^todo   desktop      seatd is not installed -- spark-shell on desktop (the packages)$' && [ ! -e "$H/root/var/service/seatd" ] && ok "Void: no seatd package, a todo row, no link" || bad "void no seatd" "$out"
# the sound on Void: PipeWire's two ALSA files linked into /etc/alsa/conf.d
# (Void's package leaves them in /usr/share) and you in the audio group (no
# logind), each recorded; off desktop undoes exactly those
void_sound() {   # void_sound -- a Void root with PipeWire installed, an audio group, the bar's old ALSA file
    void_desktop
    printf 'audio:x:12:\n' >> "$H/root/etc/group"
    mkdir -p "$H/root/usr/share/alsa/alsa.conf.d"; for f in 50-pipewire.conf 99-pipewire-default.conf; do : > "$H/root/usr/share/alsa/alsa.conf.d/$f"; done
    printf '#!/bin/sh\nexit 0\n' > "$H/lx/pipewire"; chmod +x "$H/lx/pipewire"
    share=/usr/share/alsa/alsa.conf.d; conf=$H/root/etc/alsa/conf.d
    mkdir -p "$HOME/.config/alsa"; printf '# rendered by spark-shell (bar): the sound card for programs started from now -- spark-shell off removes it\ndefaults.pcm.!card HDMI\ndefaults.ctl.!card HDMI\n' > "$HOME/.config/alsa/asoundrc"
}
void_sound
out=$(L on desktop --dry-run </dev/null)
printf '%s\n' "$out" | grep -q '^would  sound        ALSA programs play through PipeWire: link 50-pipewire.conf 99-pipewire-default.conf into /etc/alsa/conf.d (sudo)$' \
    && printf '%s\n' "$out" | grep -q "^would  sound        add $me to the audio group: the sound devices open to you (sudo)\$" \
    && printf '%s\n' "$out" | grep -q "^would  sound        remove $HOME/.config/alsa/asoundrc: PipeWire picks the output now\$" \
    && [ ! -e "$conf" ] && [ -f "$HOME/.config/alsa/asoundrc" ] && ! grep -q usermod "$H/log" \
    && ok "Void: on desktop --dry-run says the ALSA links, the audio group and the bar's old file, touches nothing" || bad "void sound dry" "$out"
out=$(L on desktop --yes </dev/null 2>&1)
[ "$(readlink "$conf/50-pipewire.conf")" = "$share/50-pipewire.conf" ] && [ "$(readlink "$conf/99-pipewire-default.conf")" = "$share/99-pipewire-default.conf" ] \
    && ok "Void: on desktop links PipeWire's two ALSA files into /etc/alsa/conf.d" || bad "void alsa links" "$(ls -l "$conf" 2>&1) $out"
grep -q "^audio:x:12:$me\$" "$H/root/etc/group" && grep -qx "usermod -aG audio $me" "$H/log" && [ -f "$HOME/.local/state/spark-shell/sound.alsa" ] && [ -f "$HOME/.local/state/spark-shell/sound.group" ] \
    && ok "Void: on desktop adds you to audio; both steps recorded (sound.alsa, sound.group)" || bad "void audio group" "$(cat "$H/root/etc/group" "$H/log")"
[ ! -e "$HOME/.config/alsa/asoundrc" ] && printf '%s\n' "$out" | grep -q "^ok     sound        $me is in the audio group now: it takes effect at your next login\$" \
    && ok "Void: the bar's own ALSA file is gone (PipeWire picks the output), one line says the group takes effect at the next login" || bad "void sound lines" "$out"
ck=$(L check || true)
printf '%s\n' "$ck" | grep -q '^ok     sound        PipeWire starts with the desktop$' && ! printf '%s\n' "$ck" | grep -q '^warn   sound' \
    && ok "Void: check says PipeWire starts with the desktop, and no warn" || bad "void sound check" "$(printf '%s\n' "$ck" | grep sound)"
: > "$H/log"; out=$(L on desktop --yes </dev/null 2>&1)
! printf '%s\n' "$out" | grep -q 'sound' && ! grep -q usermod "$H/log" && ok "Void: on desktop again: nothing of the sound left to do, nothing said" || bad "void sound twice" "$out"
rm -f "$conf/99-pipewire-default.conf"
awk -F: -v OFS=: '$1 == "audio" { $4 = "" } { print }' "$H/root/etc/group" > "$H/g" && cat "$H/g" > "$H/root/etc/group"
ck=$(L check || true)
printf '%s\n' "$ck" | grep -q '^warn   sound        ALSA programs skip PipeWire: /etc/alsa/conf.d lacks 99-pipewire-default.conf -- spark-shell on desktop$' \
    && printf '%s\n' "$ck" | grep -q "^warn   sound        $me is not in the audio group, so the sound devices stay closed -- spark-shell on desktop\$" \
    && ok "Void: check warns when a link or the group is gone, the remedy on desktop" || bad "void sound check warns" "$(printf '%s\n' "$ck" | grep sound)"
L on desktop --yes </dev/null >/dev/null 2>&1
: > "$H/log"; out=$(L off desktop 2>&1)
[ ! -e "$conf/50-pipewire.conf" ] && [ ! -e "$conf/99-pipewire-default.conf" ] && grep -qx "gpasswd -d $me audio" "$H/log" && ! grep -q "^audio:x:12:.*$me" "$H/root/etc/group" \
    && [ ! -e "$HOME/.local/state/spark-shell/sound.alsa" ] && [ ! -e "$HOME/.local/state/spark-shell/sound.group" ] && [ -f "$H/root$share/50-pipewire.conf" ] \
    && printf '%s\n' "$out" | grep -q '^ok     sound        ALSA programs no longer play through PipeWire (the links spark-shell made are gone)$' \
    && ok "Void: off desktop removes the links and the membership it made, the records with them; the package's files stay" || bad "void sound off" "$out $(cat "$H/log")"
# one link yours, the other spark-shell's: the record names its own, and off removes only that one
void_sound
mkdir -p "$conf"; ln -s "$share/50-pipewire.conf" "$conf/50-pipewire.conf"
L on desktop --yes </dev/null >/dev/null 2>&1
[ "$(cat "$HOME/.local/state/spark-shell/sound.alsa")" = 99-pipewire-default.conf ] && L off desktop >/dev/null 2>&1 && [ -L "$conf/50-pipewire.conf" ] && [ ! -e "$conf/99-pipewire-default.conf" ] \
    && ok "Void: a link of yours beside one spark-shell made: the record names its own, off removes only that" || bad "void sound half" "$(ls -l "$conf"; cat "$HOME/.local/state/spark-shell/sound.alsa" 2>&1)"
# links and a membership that were there before: nothing recorded, nothing undone
void_sound
mkdir -p "$conf"; for f in 50-pipewire.conf 99-pipewire-default.conf; do ln -s "$share/$f" "$conf/$f"; done
awk -F: -v OFS=: -v u="$me" '$1 == "audio" { $4 = u } { print }' "$H/root/etc/group" > "$H/g" && cat "$H/g" > "$H/root/etc/group"
L on desktop --yes </dev/null >/dev/null 2>&1; L off desktop >/dev/null 2>&1
[ -L "$conf/50-pipewire.conf" ] && [ -L "$conf/99-pipewire-default.conf" ] && grep -q "^audio:x:12:$me\$" "$H/root/etc/group" && ! grep -q 'gpasswd -d [^ ]* audio\|usermod -aG audio' "$H/log" \
    && ok "Void: links and a membership of yours are not recorded, and off desktop leaves them" || bad "void sound yours" "$(ls -l "$conf"; cat "$H/log")"
# Arch with pulseaudio: pipewire-pulse left out (pacman --noconfirm would refuse the conflict, and every package with it), one todo says how
fresh
console_stubs Linux
desktop_stubs
printf 'ID=arch\n' > "$H/os-release"
printf '#!/bin/sh\n[ "$*" = "-Qq pulseaudio" ]\n' > "$H/lx/pacman"; chmod +x "$H/lx/pacman"
mkdir -p "$HOME/.config/spark-shell"; printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"
out=$(L on --dry-run </dev/null 2>&1)
pk=$(printf '%s\n' "$out" | grep -E '^(would|todo) +packages ')
printf '%s\n' "$out" | grep -q '^todo   sound        pulseaudio is installed, and pipewire-pulse takes its place -- sudo pacman -S pipewire-pulse (it asks before removing pulseaudio)$' \
    && printf '%s' "$pk" | grep -q ' pipewire-alsa' && ! printf '%s' "$pk" | grep -q 'pipewire-pulse' \
    && ok "Arch with pulseaudio: pipewire-pulse is left out of the install, one todo says how to take it" || bad "arch pulseaudio" "$out"
grep -q '^PKG_SOUND=pipewire wireplumber alsa-pipewire libspa-bluetooth$' "$REPO/distro/void.env" && grep -q '^PKG_SOUND=pipewire wireplumber pipewire-pulse pipewire-alsa libspa-0.2-bluetooth$' "$REPO/distro/debian.env" \
    && grep -q '^PKG_SOUND=pipewire wireplumber pipewire-pulse pipewire-alsa$' "$REPO/distro/arch.env" && ok "distro: the sound's packages, each family's names" || bad "PKG_SOUND" "$(grep -h PKG_SOUND "$REPO"/distro/*.env)"
grep -q '^PKG_DESKTOP=sway swaybg foot foot-terminfo dejavu-fonts-ttf mesa-dri seatd curl openssh swayidle swaylock grim slurp wl-clipboard$' "$REPO/distro/void.env" && ok "distro/void.env: the desktop's packages, seatd among them" || bad "void.env desktop"

# the login screen of v0.41 (greetd on tty1, spark-shell's files in
# /etc/greetd): handed back to getty at the next boot by on, on desktop,
# off desktop and off -- greetd is disabled, never stopped
old_greetd() {   # old_greetd [ORIG] -- a root as v0.41 left it; ORIG: a config.toml of the package's kept as .spark-orig
    fresh
    console_stubs Linux
    printf 'ID=debian\n' > "$H/os-release"
    printf '#!/bin/sh\necho "install ok installed"\n' > "$H/lx/dpkg-query"; chmod +x "$H/lx/dpkg-query"
    mkdir -p "$H/root/run/systemd/system" "$H/root/etc/greetd/spark-shell" "$H/root/etc/systemd/system/greetd.service.d" "$H/root/units"
    printf '# rendered by spark-shell from templates/etc/greetd/config.toml\n[terminal]\nvt = 1\n' > "$H/root/etc/greetd/config.toml"
    [ -z "${1:-}" ] || printf '[terminal]\nvt = 1\n# agreety\n' > "$H/root/etc/greetd/config.toml.spark-orig"
    for f in desktop console; do printf '# rendered by spark-shell\n' > "$H/root/etc/greetd/spark-shell/$f.desktop"; done
    printf '# rendered by spark-shell\n[Unit]\nAfter=spark-shell-console.service\n' > "$H/root/etc/systemd/system/greetd.service.d/spark-shell.conf"
    : > "$H/root/units/greetd.service"; : > "$H/log"
}
old_gone() {   # old_gone -- spark-shell's greetd files gone, getty@tty1 on, greetd off, nothing stopped
    [ ! -e "$H/root/etc/greetd/spark-shell" ] && [ ! -e "$H/root/etc/systemd/system/greetd.service.d" ] \
        && [ -e "$H/root/units/getty@tty1.service" ] && [ ! -e "$H/root/units/greetd.service" ] \
        && grep -qx 'systemctl enable getty@tty1.service' "$H/log" && grep -qx 'systemctl disable greetd.service' "$H/log" \
        && ! grep -Eq '^systemctl (start|stop|restart|kill)' "$H/log"
}
old_greetd
out=$(L on --dry-run </dev/null)
printf '%s\n' "$out" | grep -q "^would  login        the normal console login on tty1 from the next boot: greetd turned off, its spark-shell files removed (sudo)\$" \
    && [ -f "$H/root/etc/greetd/config.toml" ] && [ -e "$H/root/units/greetd.service" ] && ok "v0.41 upgrade: on --dry-run says the login screen goes back to getty, touches nothing" || bad "upgrade dry-run" "$out"
out=$(L on --yes </dev/null 2>&1)
old_gone && [ ! -e "$H/root/etc/greetd/config.toml" ] && ok "v0.41 upgrade: on hands tty1 back to getty at the next boot, greetd disabled (never stopped), its files gone" || bad "upgrade on" "$(find "$H/root/etc" "$H/root/units"; cat "$H/log")"
[ "$(printf '%s\n' "$out" | grep -c '^ok     login ')" = 1 ] && printf '%s\n' "$out" | grep -q '^ok     login        the normal console login is back on tty1 from the next boot: greetd is off, its packages stay$' \
    && ok "v0.41 upgrade: one plain line says so" || bad "upgrade line" "$out"
: > "$H/log"; out=$(L on --yes </dev/null 2>&1)
! printf '%s\n' "$out" | grep -q 'login ' && ! grep -q greetd "$H/log" && ok "v0.41 upgrade: on again has nothing to hand back" || bad "upgrade twice" "$out"
old_greetd orig
mkdir -p "$HOME/.config/spark-shell"; printf 'DESKTOP=none\n' > "$HOME/.config/spark-shell/config"
L on desktop --yes </dev/null >/dev/null 2>&1
old_gone && grep -q agreety "$H/root/etc/greetd/config.toml" && [ ! -e "$H/root/etc/greetd/config.toml.spark-orig" ] && grep -q '^DESKTOP=sway$' "$HOME/.config/spark-shell/config" \
    && ok "v0.41 upgrade: on desktop hands it back too, the package's config.toml restored from .spark-orig" || bad "upgrade on desktop" "$(ls -a "$H/root/etc/greetd"; cat "$H/log")"
old_greetd
out=$(L off desktop --dry-run)
printf '%s\n' "$out" | grep -q '^would  login ' && [ -e "$H/root/units/greetd.service" ] && ok "v0.41 upgrade: off desktop --dry-run says it, touches nothing" || bad "upgrade off dry" "$out"
L off desktop >/dev/null 2>&1
old_gone && ok "v0.41 upgrade: off desktop hands it back" || bad "upgrade off desktop" "$(cat "$H/log")"
old_greetd
L off >/dev/null 2>&1
old_gone && ok "v0.41 upgrade: off hands it back" || bad "upgrade off" "$(cat "$H/log")"

# the console is the tty, never XDG_VTNR (logind's; Void has none), and
# sway gets a private XDG_RUNTIME_DIR when no login manager made one
fresh
console_stubs Linux
desktop_stubs
printf '#!/bin/sh\necho "XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR" >&2\n' > "$H/.local/bin/sway"
mkdir -p "$HOME/.config/spark-shell"; printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"
L on --yes >/dev/null </dev/null
slog=$HOME/.local/state/spark-shell/sway.log
mkdir -p "$H/tmp"
rc=0; out=$(TEST_TTY=/dev/pts/3 XDG_VTNR=1 env -u WAYLAND_DISPLAY PATH="$H/lx:$PATH" sh "$SH" desktop 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = 'spark-shell desktop: needs a console login (tty1 to tty9): ssh and terminal windows cannot start sway' ] \
    && ok "desktop: a terminal window (/dev/pts) is refused even with XDG_VTNR set" || bad "desktop pts" "rc=$rc $out"
rc=0; out=$(TEST_TTY=/dev/tty2 env -u XDG_VTNR -u WAYLAND_DISPLAY -u XDG_RUNTIME_DIR TMPDIR="$H/tmp/" PATH="$H/lx:$PATH" sh "$SH" desktop 2>&1) || rc=$?
rd=$H/tmp/$(id -u)-runtime-dir
[ "$rc" = 0 ] && grep -qx "XDG_RUNTIME_DIR=$rd" "$slog" && ok "desktop: by hand on tty2 with no XDG_VTNR, sway starts" || bad "desktop tty2" "rc=$rc $out $(cat "$slog" 2>&1)"
[ -d "$rd" ] && [ ! -L "$rd" ] && [ "$(ls -ld "$rd" | cut -c1-10)" = drwx------ ] && [ "$(ls -ldn "$rd" | awk '{print $3}')" = "$(id -u)" ] \
    && ok "desktop: no XDG_RUNTIME_DIR, a private one made under TMPDIR (0700, yours) and handed to sway" || bad "runtime dir" "$(ls -ld "$rd" 2>&1)"
chmod 0755 "$rd"
rc=0; out=$(TEST_TTY=/dev/tty1 env -u WAYLAND_DISPLAY -u XDG_RUNTIME_DIR TMPDIR="$H/tmp" PATH="$H/lx:$PATH" sh "$SH" desktop 2>&1) || rc=$?
[ "$rc" = 0 ] && grep -qx "XDG_RUNTIME_DIR=$rd" "$slog" && [ "$(ls -ld "$rd" | cut -c1-10)" = drwx------ ] && ok "desktop: the same directory again, back to 0700" || bad "runtime dir again" "rc=$rc $out"
rm -rf "$rd"; mkdir -p "$H/elsewhere"; ln -s "$H/elsewhere" "$rd"
rc=0; out=$(TEST_TTY=/dev/tty1 env -u WAYLAND_DISPLAY -u XDG_RUNTIME_DIR TMPDIR="$H/tmp" PATH="$H/lx:$PATH" sh "$SH" desktop 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = "spark-shell desktop: $rd is not a private directory of yours, and sway needs one (XDG_RUNTIME_DIR)" ] && ok "desktop: a symlink in its place is refused, sway never starts" || bad "runtime dir symlink" "rc=$rc $out"
rc=0; out=$(TEST_TTY=/dev/tty1 XDG_RUNTIME_DIR=$H/run env -u WAYLAND_DISPLAY PATH="$H/lx:$PATH" sh "$SH" desktop 2>&1) || rc=$?
[ "$rc" = 0 ] && grep -qx "XDG_RUNTIME_DIR=$H/run" "$slog" && ok "desktop: an XDG_RUNTIME_DIR a login manager set is kept" || bad "runtime dir kept" "rc=$rc $out $(cat "$slog")"
# no systemd: PipeWire, WirePlumber and the PulseAudio server start before
# sway and stop after it; with systemd (its user units) or one already
# answering, none is started
py3=$(command -v python3 || :)   # the real one (console_stubs put a fake in $H/lx); a container without it: the stub makes no socket, and the start waits its 5 s
for t in pipewire wireplumber pipewire-pulse; do
    { printf '#!/bin/sh\necho $$ > "$HOME/%s.pid"\n' "$t"
      [ "$t" != pipewire ] || [ -z "$py3" ] || printf '%s -c "import socket,sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])" "$XDG_RUNTIME_DIR/pipewire-0"\n' "$py3"
      printf 'exec sleep 60\n'; } > "$H/lx/$t"
done
printf '#!/bin/sh\nsleep 1; for t in pipewire wireplumber pipewire-pulse; do [ -f "$HOME/$t.pid" ] && kill -0 "$(cat "$HOME/$t.pid")" 2>/dev/null && echo "$t runs" >&2; done; exit 0\n' > "$H/.local/bin/sway"
chmod +x "$H/lx/pipewire" "$H/lx/wireplumber" "$H/lx/pipewire-pulse" "$H/.local/bin/sway"
mkdir -p "$H/rt"; chmod 700 "$H/rt"
t0=$(date +%s); rc=0; out=$(TEST_TTY=/dev/tty1 XDG_RUNTIME_DIR=$H/rt env -u WAYLAND_DISPLAY PATH="$H/lx:$PATH" sh "$SH" desktop 2>&1) || rc=$?
[ "$rc" = 0 ] && [ "$(grep -c ' runs$' "$slog")" = 3 ] && { [ -z "$py3" ] || [ $(($(date +%s) - t0)) -lt 4 ]; } \
    && ok "desktop, no systemd: PipeWire, WirePlumber and pipewire-pulse run while sway does (WirePlumber once PipeWire's socket is there)" || bad "sound start" "rc=$rc $(($(date +%s) - t0))s $out $(cat "$slog" "$HOME/.local/state/spark-shell/sound.log" 2>&1)"
alive=''; for t in pipewire wireplumber pipewire-pulse; do ! kill -0 "$(cat "$HOME/$t.pid")" 2>/dev/null || alive="$alive $t"; done
[ -z "$alive" ] && ok "desktop: all three stop when sway ends, waited for" || bad "sound stop" "still running:$alive"
for t in pipewire wireplumber pipewire-pulse; do kill "$(cat "$HOME/$t.pid")" 2>/dev/null || :; done
# the Void handbook's way: pipewire.conf.d files have PipeWire start WirePlumber and its PulseAudio server itself
rm -f "$HOME"/*.pid "$H/rt/pipewire-0"; mkdir -p "$H/root/etc/pipewire/pipewire.conf.d"
printf 'context.exec = [ { path = "/usr/bin/wireplumber" args = "" } ]\n' > "$H/root/etc/pipewire/pipewire.conf.d/10-wireplumber.conf"
printf 'context.exec = [ { path = "/usr/bin/pipewire" args = "-c pipewire-pulse.conf" } ]\n' > "$H/root/etc/pipewire/pipewire.conf.d/20-pipewire-pulse.conf"
rc=0; out=$(TEST_TTY=/dev/tty1 XDG_RUNTIME_DIR=$H/rt env -u WAYLAND_DISPLAY PATH="$H/lx:$PATH" sh "$SH" desktop 2>&1) || rc=$?
[ "$rc" = 0 ] && grep -qx 'pipewire runs' "$slog" && [ ! -e "$HOME/wireplumber.pid" ] && [ ! -e "$HOME/pipewire-pulse.pid" ] \
    && ok "desktop: pipewire.conf.d files that start WirePlumber and pipewire-pulse: PipeWire alone, no second of either" || bad "sound by pipewire" "rc=$rc $(cat "$slog")"
rm -rf "$H/root/etc/pipewire"
rm -f "$HOME"/*.pid "$H/rt/pipewire-0"; mkdir -p "$H/root/run/systemd/system"
rc=0; out=$(TEST_TTY=/dev/tty1 XDG_RUNTIME_DIR=$H/rt env -u WAYLAND_DISPLAY PATH="$H/lx:$PATH" sh "$SH" desktop 2>&1) || rc=$?
[ "$rc" = 0 ] && ! grep -q ' runs$' "$slog" && [ ! -e "$HOME/pipewire.pid" ] && ok "desktop, systemd: none started (the packages' user units start them)" || bad "sound systemd" "rc=$rc $(cat "$slog")"
rm -rf "$H/root/run/systemd"
printf '#!/bin/sh\nexit 0\n' > "$H/lx/wpctl"; chmod +x "$H/lx/wpctl"
rc=0; out=$(TEST_TTY=/dev/tty1 XDG_RUNTIME_DIR=$H/rt env -u WAYLAND_DISPLAY PATH="$H/lx:$PATH" sh "$SH" desktop 2>&1) || rc=$?
[ "$rc" = 0 ] && [ ! -e "$HOME/pipewire.pid" ] && ok "desktop: a PipeWire that answers already is left as it is, none started" || bad "sound running" "rc=$rc $(cat "$slog")"
rm -f "$H/lx/wpctl" "$H/lx/pipewire" "$H/lx/wireplumber" "$H/lx/pipewire-pulse"

# the lock and screen capture: the template's keys and swayidle, then the
# verbs against stubs (swaylock, pgrep, grim, slurp, wl-copy, swaymsg, date)
sw_t=$REPO/templates/.config/sway/config
grep -qx "exec swayidle -w timeout 600 'swaymsg \"output \* power off\"' resume 'swaymsg \"output \* power on\"' timeout 900 '@REPO@/spark-shell desktop lock || swaylock -f' before-sleep '@REPO@/spark-shell desktop lock || swaylock -f'" "$sw_t" \
    && grep -qx 'bindsym $mod+Escape exec @REPO@/spark-shell desktop lock || swaylock -f' "$sw_t" \
    && ok "sway template: ten idle minutes turn the display off, fifteen lock, and it locks before sleep; Super+Escape locks now" || bad "lock template" "$(grep -n 'swayidle\|Escape' "$sw_t")"
grep -qx 'bindsym Print exec @REPO@/spark-shell desktop capture screen' "$sw_t" && grep -qx 'bindsym Shift+Print exec @REPO@/spark-shell desktop capture area' "$sw_t" && grep -qx 'bindsym $mod+Print exec @REPO@/spark-shell desktop capture window' "$sw_t" \
    && ok "sway template: Print the screen, Shift+Print an area, Super+Print the window" || bad "capture keys" "$(grep -n Print "$sw_t")"
printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "$HOME/swaylock.args"\n' > "$H/lx/swaylock"
printf '#!/bin/sh\n[ "$*" = "-u %s -x swaylock" ] && [ -e "$HOME/locked" ]\n' "$(id -u)" > "$H/lx/pgrep"
printf '#!/bin/sh\necho "$*" >> "$HOME/grim.log"\nfor a; do f=$a; done\n[ ! -e "$HOME/grim-fails" ] || exit 1\nprintf PNG > "$f"\n' > "$H/lx/grim"
printf '#!/bin/sh\n[ -e "$HOME/slurp-none" ] && exit 1\necho "10,20 300x200"\n' > "$H/lx/slurp"
printf '#!/bin/sh\necho "$*" >> "$HOME/wlcopy.log"; cat > "$HOME/clip"\n' > "$H/lx/wl-copy"
cat > "$H/lx/swaymsg" <<'STUB'
#!/bin/sh
echo "$*" >> "$HOME/swaymsg.log"
case "$*" in
    "-t get_version") echo '{"major":1}' ;;
    "-t get_outputs") echo '[{"name":"DP-1","focused":false},{"name":"HDMI-A-1","focused":true}]' ;;
    "-t get_tree") [ -e "$HOME/no-window" ] && echo '{"type":"root","nodes":[{"type":"workspace","focused":true,"rect":{"x":0,"y":0,"width":1,"height":1}}]}' \
        || echo '{"type":"root","nodes":[{"type":"output","nodes":[{"type":"workspace","focused":false,"nodes":[{"type":"con","focused":true,"rect":{"x":10,"y":40,"width":800,"height":600}}]}]}]}' ;;
esac
STUB
printf '#!/bin/sh\ncase "$1" in +%%Y-%%m-%%d-%%H%%M%%S) echo 2026-10-19-153012 ;; *) exec %s "$@" ;; esac\n' "$(command -v date)" > "$H/lx/date"
chmod +x "$H/lx/swaylock" "$H/lx/pgrep" "$H/lx/grim" "$H/lx/slurp" "$H/lx/wl-copy" "$H/lx/swaymsg" "$H/lx/date"
theme_fixture '#ff5555'
printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"
rc=0; out=$(WAYLAND_DISPLAY=wayland-1 PATH="$H/lx:$PATH" sh "$SH" desktop lock 2>&1) || rc=$?
args=$(paste -sd ' ' - < "$HOME/swaylock.args" 2>/dev/null)
[ "$rc" = 0 ] && case " $args " in *" --daemonize --color 000000 --font DejaVu Sans Mono --font-size 20 "*) true ;; *) false ;; esac \
    && case " $args " in *" --ring-color ff5555 "*) true ;; *) false ;; esac && case " $args " in *" --ring-wrong-color aa0000 "*) true ;; *) false ;; esac \
    && ! case " $args " in *indicator-idle-visible*) true ;; *) false ;; esac \
    && ok "desktop lock: swaylock, daemonized, over the ground, the ring in the accent, wrong in the red, no ring at rest" || bad "lock args" "rc=$rc $out $args"
printf 'DESKTOP=sway\nWALLPAPER=ripples\n' > "$HOME/.config/spark-shell/config"; rm -f "$HOME/swaylock.args"
WAYLAND_DISPLAY=wayland-1 PATH="$H/lx:$PATH" sh "$SH" desktop lock >/dev/null 2>&1 || :
args=$(paste -sd ' ' - < "$HOME/swaylock.args" 2>/dev/null)
case " $args " in *" --image $REPO/wallpaper/ripples.png --scaling fill "*) ok "desktop lock: a wallpaper picture is the lock's picture, filled" ;; *) bad "lock picture" "$args" ;; esac
# a theme.env that will not load: the lock still comes up, in the VGA's colors
printf 'THEME_BG=$(oops)\n' > "$HOME/.config/spark/theme.env.bad"; cp "$HOME/.config/spark/theme.env" "$HOME/.config/spark/theme.env.good"; cp "$HOME/.config/spark/theme.env.bad" "$HOME/.config/spark/theme.env"; rm -f "$HOME/swaylock.args"
rc=0; WAYLAND_DISPLAY=wayland-1 PATH="$H/lx:$PATH" sh "$SH" desktop lock >/dev/null 2>&1 || rc=$?
[ "$rc" = 0 ] && grep -qx -- --daemonize "$HOME/swaylock.args" && ok "desktop lock with a theme.env that will not load: the lock comes up anyway" || bad "lock bad theme" "rc=$rc $(cat "$HOME/swaylock.args" 2>&1)"
mv "$HOME/.config/spark/theme.env.good" "$HOME/.config/spark/theme.env"; rm -f "$HOME/.config/spark/theme.env.bad"
touch "$HOME/locked"; rm -f "$HOME/swaylock.args"
rc=0; WAYLAND_DISPLAY=wayland-1 PATH="$H/lx:$PATH" sh "$SH" desktop lock >/dev/null 2>&1 || rc=$?
[ "$rc" = 0 ] && [ ! -e "$HOME/swaylock.args" ] && ok "desktop lock: a lock already up stays, no second" || bad "lock twice" "rc=$rc"
rm -f "$HOME/locked"
rc=0; out=$(env -u WAYLAND_DISPLAY PATH="$H/lx:$PATH" sh "$SH" desktop lock 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = 'spark-shell desktop: locks the desktop: run it inside it (Super+Escape)' ] && ok "desktop lock outside the desktop: refused in one line" || bad "lock outside" "rc=$rc $out"
shots=$HOME/pictures/screenshots
rc=0; out=$(WAYLAND_DISPLAY=wayland-1 PATH="$H/lx:$PATH" sh "$SH" desktop capture screen 2>&1) || rc=$?
# shellcheck disable=SC2088   # the line as the user reads it, a tilde and all
[ "$rc" = 0 ] && [ "$out" = '~/pictures/screenshots/2026-10-19-153012.png, and on the clipboard' ] && [ "$(cat "$shots/2026-10-19-153012.png")" = PNG ] \
    && [ "$(tail -1 "$HOME/grim.log")" = "-o HDMI-A-1 $shots/2026-10-19-153012.png" ] && [ "$(cat "$HOME/wlcopy.log")" = '--type image/png' ] && [ "$(cat "$HOME/clip")" = PNG ] \
    && ok "desktop capture screen: the screen in use, a PNG named by the time in ~/pictures/screenshots, and on the clipboard" || bad "capture screen" "rc=$rc $out $(cat "$HOME/grim.log" 2>&1)"
rc=0; out=$(WAYLAND_DISPLAY=wayland-1 PATH="$H/lx:$PATH" sh "$SH" desktop capture area 2>&1) || rc=$?
# shellcheck disable=SC2088   # the line as the user reads it, a tilde and all
[ "$rc" = 0 ] && [ "$out" = '~/pictures/screenshots/2026-10-19-153012-2.png, and on the clipboard' ] && [ "$(tail -1 "$HOME/grim.log")" = "-g 10,20 300x200 $shots/2026-10-19-153012-2.png" ] \
    && ok "desktop capture area: the area slurp gives; a second picture in the same second gets -2" || bad "capture area" "rc=$rc $out $(tail -1 "$HOME/grim.log")"
rc=0; out=$(WAYLAND_DISPLAY=wayland-1 PATH="$H/lx:$PATH" sh "$SH" desktop capture window 2>&1) || rc=$?
[ "$rc" = 0 ] && [ "$(tail -1 "$HOME/grim.log")" = "-g 10,40 800x600 $shots/2026-10-19-153012-3.png" ] && ok "desktop capture window: the window in front, by its place on the screen" || bad "capture window" "rc=$rc $out $(tail -1 "$HOME/grim.log")"
touch "$HOME/slurp-none"; n0=$(ls "$shots" | wc -l)
rc=0; out=$(WAYLAND_DISPLAY=wayland-1 PATH="$H/lx:$PATH" sh "$SH" desktop capture area 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = 'no area picked: nothing captured' ] && [ "$(ls "$shots" | wc -l)" = "$n0" ] && ok "desktop capture area, Esc in slurp: nothing captured, one line" || bad "capture no area" "rc=$rc $out"
rm -f "$HOME/slurp-none"; touch "$HOME/no-window"
rc=0; out=$(WAYLAND_DISPLAY=wayland-1 PATH="$H/lx:$PATH" sh "$SH" desktop capture window 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = 'spark-shell desktop: no window in front to capture' ] && ok "desktop capture window with no window: refused in one line" || bad "capture no window" "rc=$rc $out"
rm -f "$HOME/no-window"; touch "$HOME/grim-fails"
rc=0; out=$(WAYLAND_DISPLAY=wayland-1 PATH="$H/lx:$PATH" sh "$SH" desktop capture screen 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = 'spark-shell desktop: grim could not take the picture' ] && [ "$(ls "$shots" | wc -l | tr -d ' ')" = 3 ] && ok "desktop capture: grim failing leaves no file, one line" || bad "capture grim fails" "rc=$rc $out $(ls "$shots")"
rm -f "$HOME/grim-fails"
rc=0; out=$(WAYLAND_DISPLAY=wayland-1 PATH="$H/lx:$PATH" sh "$SH" desktop capture photo 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = 'spark-shell desktop: capture takes screen, area or window' ] && ok "desktop capture: a wrong word refused in one line" || bad "capture word" "rc=$rc $out"
# the dialog's window section: two capture rows; a pick closes the dialog and captures a second later
rows=$(SWAYSOCK=$H/sock PATH="$H/lx:$PATH" sh "$SH" bar panel window --list 2>&1)
printf '%s\n' "$rows" | grep -q 'capture the screen	window capture screen$' && printf '%s\n' "$rows" | grep -q 'capture an area	window capture area$' \
    && ok "the dialog's window section: capture the screen, capture an area" || bad "capture rows" "$rows"
rm -f "$HOME/swaymsg.log"
rc=0; out=$(SWAYSOCK=$H/sock PATH="$H/lx:$PATH" sh "$SH" bar panel window capture area 2>&1) || rc=$?
[ "$rc" = 0 ] && [ "$out" = 'capture: the area, in ~/pictures/screenshots' ] && grep -qx -- "-- exec $REPO/spark-shell desktop capture area --wait 1" "$HOME/swaymsg.log" \
    && ok "the dialog: capture runs through sway a second later, after the dialog closes" || bad "capture from the dialog" "rc=$rc $out $(cat "$HOME/swaymsg.log" 2>&1)"
rm -f "$H/lx/swaylock" "$H/lx/pgrep" "$H/lx/grim" "$H/lx/slurp" "$H/lx/wl-copy" "$H/lx/swaymsg" "$H/lx/date"

# macOS: the palette and the font are Terminal.app's profile, through the helper
fresh
console_stubs Darwin
palette_fixture test '#fe8019'
L theme test >/dev/null
grep -qx "python3 $REPO/lib/terminal_profile.py apply $HOME/.config/spark/theme.env Menlo-Regular 13" "$H/log" && [ ! -e "$H/root/etc" ] \
    && ok "macOS: theme test runs the helper with theme.env, Menlo-Regular 13, no root file" || bad "mac theme" "$(cat "$H/log")"
: > "$H/log"; L theme test >/dev/null
[ "$(cat "$H/log")" = "python3 $REPO/lib/terminal_profile.py has-profile" ] && ok "macOS: theme test again asks the helper, and leaves the profile alone" || bad "mac idempotent" "$(cat "$H/log")"
: > "$H/gone"; : > "$H/log"
ck=$(L check || true)
printf '%s\n' "$ck" | grep -q "^warn   theme        test: Terminal.app has no spark-shell profile -- spark-shell on$" && ok "macOS: check warns when the profile is gone, the stamp alone is not enough" || bad "mac check gone" "$(printf '%s\n' "$ck" | grep theme)"
L theme test >/dev/null
grep -qx "python3 $REPO/lib/terminal_profile.py apply $HOME/.config/spark/theme.env Menlo-Regular 13" "$H/log" && ok "macOS: theme test imports the profile again when it is gone" || bad "mac reimport" "$(cat "$H/log")"
rm -f "$H/gone"
rc=0; out=$(SPARK_SHELL_MAC_FONTS="Menlo-Regular Monaco" L font VGA 14 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = "spark-shell font: no font named VGA is installed here (spark-shell font list shows them)" ] && ok "macOS: a face this Mac lacks is refused" || bad "mac font refused" "rc=$rc $out"
SPARK_SHELL_MAC_FONTS="Menlo-Regular Monaco" L font Monaco 14 >/dev/null
grep -qx "python3 $REPO/lib/terminal_profile.py apply $HOME/.config/spark/theme.env Monaco 14" "$H/log" && ok "macOS: font Monaco 14 rewrites the profile" || bad "mac font" "$(cat "$H/log")"
rc=0; out=$(L quiet login on 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = "spark-shell quiet: macOS has no login notice or boot menu to quiet." ] && ok "macOS: quiet login on is one sentence" || bad "mac quiet" "rc=$rc $out"
: > "$H/stuck"; out=$(L theme none)
printf '%s\n' "$out" | grep -q '^todo   terminal     Terminal.app kept the profile' && [ -f "$HOME/.local/state/spark-shell/terminal.seen" ] \
    && ok "macOS: a remove that failed is a todo, and the stamp stays" || bad "mac remove stuck" "$out"
rm -f "$H/stuck"; : > "$H/log"; L theme none >/dev/null
grep -qx "python3 $REPO/lib/terminal_profile.py remove" "$H/log" && [ ! -e "$HOME/.config/spark/theme.env" ] && [ ! -e "$HOME/.local/state/spark-shell/terminal.seen" ] \
    && ok "macOS: theme none removes the profile and theme.env" || bad "mac none" "$(cat "$H/log")"
rc=0; out=$(L theme -h 2>&1) || rc=$?
[ "$rc" = 0 ] && printf '%s\n' "$out" | grep -q '^  spark-shell theme NAME|none  ' && ok "theme -h: the help answers first" || bad "theme -h" "rc=$rc $out"

# --- the warning: on, on desktop and quiet boot on ask first -------------
# The question is asked at a terminal only; the suite has none, so it
# drives the answer through stdin with SPARK_SHELL_TEST_TTY set. A
# sudo stub logs every call: a refused or stopped run makes none.
snap() { ( cd "$H" && find . -print | LC_ALL=C sort && find . -type f -exec cksum {} + | LC_ALL=C sort ); }
A() { SPARK_SHELL_TEST_TTY=1 PATH=$H/lx:$PATH sh "$SH" "$@"; }   # spark-shell with an answer on stdin (the assignments on sh, never kept)
fresh
console_stubs Linux
printf '#!/bin/sh\necho "sudo $*" >> "%s/sudo.log"\n' "$H" > "$H/lx/sudo"; chmod +x "$H/lx/sudo"
warn_on='spark-shell replaces your shell files, installs packages
and changes the console colors. spark-shell on --dry-run
shows every change.

Continue? [y/N] spark-shell: nothing was changed.'
snap_a=$(mktemp); snap_b=$(mktemp)
snap > "$snap_a"
rc=0; out=$(L on </dev/null 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = "spark-shell: no terminal to ask on -- add --yes to go ahead" ] && ok "warning: no terminal and no --yes, one line, exit 1" || bad "warning no terminal" "rc=$rc $out"
rc=0; out=$(L apply </dev/null 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = "spark-shell: no terminal to ask on -- add --yes to go ahead" ] && ok "warning: apply is on, the same line" || bad "warning apply" "rc=$rc $out"
printf 'ID=arch\n' > "$H/os-release"
rc=0; out=$(L on desktop </dev/null 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = "spark-shell: no terminal to ask on -- add --yes to go ahead" ] && ok "warning: on desktop with no terminal, the same line" || bad "warning desktop no terminal" "rc=$rc $out"
rc=0; out=$(L desktop on </dev/null 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = "spark-shell: no terminal to ask on -- add --yes to go ahead" ] && ok "warning: desktop on is on desktop, the same line" || bad "warning desktop on" "rc=$rc $out"
printf 'ID=fixture\n' > "$H/os-release"
rc=0; out=$(printf 'n\n' | A on 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = "$warn_on" ] && ok "warning: on says what it changes and asks; n stops it (exit 1)" || bad "warning text" "rc=$rc $out"
rc=0; out=$(printf '\n' | A on 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = "$warn_on" ] && ok "warning: Enter alone is No" || bad "warning enter" "rc=$rc $out"
rc=0; out=$(A on </dev/null 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$(printf '%s\n' "$out" | tail -1)" = "spark-shell: nothing was changed." ] && ok "warning: no answer at all is No" || bad "warning eof" "rc=$rc $out"
snap > "$snap_b"
cmp -s "$snap_a" "$snap_b" && ok "warning: a refused or stopped on leaves HOME byte for byte as it was" || bad "warning HOME changed" "$(diff "$snap_a" "$snap_b" | head -5)"
rm -f "$snap_a" "$snap_b"
[ ! -e "$H/sudo.log" ] && ok "warning: a refused or stopped on asks sudo nothing" || bad "warning sudo" "$(cat "$H/sudo.log")"
# the desktop: the distro's PKG_DESKTOP, the login, Void's two lines
printf 'ID=arch\n' > "$H/os-release"
rc=0; out=$(printf 'n\n' | A on desktop 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = "spark-shell replaces your shell files, installs packages
and changes the console colors.
spark-shell on desktop --dry-run shows every change.

spark-shell changes how this machine works:

  packages     sway swaybg foot foot-terminfo ttf-dejavu curl openssh swayidle
               swaylock grim slurp wl-clipboard pipewire wireplumber
               pipewire-pulse pipewire-alsa (sudo)
  login        logging in on tty1 starts the desktop
               Alt+F2 is a plain shell

spark-shell off desktop puts the login back.
Packages stay.

Continue? [y/N] spark-shell: nothing was changed." ] && ok "warning: on desktop names the packages (the desktop's, then the sound's), the login and the way back" || bad "warning desktop" "rc=$rc $out"
[ ! -e "$HOME/.config/spark-shell/config" ] && [ ! -e "$H/sudo.log" ] && ok "warning: a stopped on desktop writes nothing, no sudo" || bad "warning desktop wrote" "$(cat "$HOME/.config/spark-shell/config" 2>&1)"
printf 'ID=void\n' > "$H/os-release"
rc=0; out=$(printf 'n\n' | A on desktop 2>&1) || rc=$?
printf '%s\n' "$out" | grep -qx '  groups       adds you to _seatd and audio (sudo)' && printf '%s\n' "$out" | grep -qx '  services     turns on seatd at boot (sudo)' \
    && printf '%s\n' "$out" | grep -qx '  sound        PipeWire starts with the desktop, and ALSA programs play through' && printf '%s\n' "$out" | grep -qx '               it (sudo)' \
    && ok "warning: on desktop on Void adds the _seatd and audio groups, the seatd service, and says PipeWire starts with the desktop" || bad "warning void" "rc=$rc $out"
pk=$(sed -n 's/^PKG_DESKTOP=//p' "$REPO/distro/void.env")
if [ -n "$pk" ]; then printf '%s\n' "$out" | grep -q "^  packages     ${pk%% *} " && ok "warning: Void's PKG_DESKTOP named" || bad "warning void packages" "$out"
else printf '%s\n' "$out" | grep -q '^  packages' && bad "warning: a packages row with no PKG_DESKTOP" "$out" || ok "warning: no PKG_DESKTOP, no packages row"; fi
rc=0; out=$(printf 'n\n' | PKG_DESKTOP="$(printf 'pkg%s ' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17)" PKG_SOUND=pkg18 SPARK_SHELL_TEST_TTY=1 PATH=$H/lx:$PATH sh "$SH" on desktop 2>&1) || rc=$?
[ "$(printf '%s\n' "$out" | awk 'length > 79' | wc -l | tr -d ' ')" = 0 ] && [ "$(printf '%s\n' "$out" | grep -c '^               pkg')" -ge 1 ] && printf '%s\n' "$out" | grep -q 'pkg18 (sudo)$' \
    && ok "warning: a long package list wraps under its column, within 80" || bad "warning wrap" "$out"
# y and --yes go ahead; --dry-run never asks
printf 'ID=fixture\n' > "$H/os-release"
rc=0; out=$(printf 'y\n' | A on 2>&1) || rc=$?
[ "$rc" = 0 ] && [ -L "$HOME/.bashrc" ] && printf '%s\n' "$out" | grep -q '^Continue? \[y/N\] ' && ok "warning: y goes ahead" || bad "warning y" "rc=$rc $out"
rm -f "$H/sudo.log"
fresh
console_stubs Linux
rc=0; out=$(L on --yes </dev/null 2>&1) || rc=$?
[ "$rc" = 0 ] && [ -L "$HOME/.bashrc" ] && ! printf '%s\n' "$out" | grep -q 'Continue?\|no terminal' && ok "warning: --yes goes ahead with no terminal, no question" || bad "warning --yes" "rc=$rc $out"
rc=0; out=$(L on --dry-run </dev/null 2>&1) || rc=$?
[ "$rc" = 0 ] && ! printf '%s\n' "$out" | grep -q 'Continue?\|no terminal' && ok "warning: on --dry-run never asks" || bad "warning dry-run" "rc=$rc $out"
printf 'ID=arch\n' > "$H/os-release"
rc=0; out=$(L on desktop --dry-run </dev/null 2>&1) || rc=$?
printf 'ID=fixture\n' > "$H/os-release"
[ "$rc" = 0 ] && ! printf '%s\n' "$out" | grep -q 'Continue?\|no terminal' && ok "warning: on desktop --dry-run never asks" || bad "warning desktop dry-run" "rc=$rc $out"
# off, follow, theme and quiet login never ask
rc=0; out=$(L off </dev/null 2>&1) || rc=$?
[ "$rc" = 0 ] && ! printf '%s\n' "$out" | grep -q 'Continue?\|no terminal' && ok "warning: off never asks" || bad "warning off" "rc=$rc $out"
rc=0; out=$(L off desktop </dev/null 2>&1) || rc=$?
[ "$rc" = 0 ] && ! printf '%s\n' "$out" | grep -q 'Continue?\|no terminal' && ok "warning: off desktop never asks" || bad "warning off desktop" "rc=$rc $out"
L on --yes >/dev/null
theme_fixture '#55ff55'
rc=0; out=$(printf 'n\n' | A follow 2>&1) || rc=$?
[ "$rc" = 0 ] && printf '%s\n' "$out" | grep -q '^spark-shell: [0-9]* files updated for the new palette\.$' && ! printf '%s\n' "$out" | grep -q 'Continue?\|no terminal' \
    && ok "warning: follow (the login profile) never asks, even at a terminal" || bad "warning follow" "rc=$rc $out"
rc=0; out=$(L theme none </dev/null 2>&1) || rc=$?
! printf '%s\n' "$out" | grep -q 'Continue?\|no terminal' && ok "warning: theme never asks" || bad "warning theme" "rc=$rc $out"
printf 'ID=debian\n' > "$H/os-release"
rc=0; out=$(L quiet login on </dev/null 2>&1) || rc=$?
[ "$rc" = 0 ] && ! printf '%s\n' "$out" | grep -q 'Continue?\|no terminal' && ok "warning: quiet login on never asks" || bad "warning quiet login" "rc=$rc $out"
# quiet boot on asks; quiet boot off does not
mkdir -p "$H/root/etc/default"; printf 'GRUB_TIMEOUT=5\n' > "$H/root/etc/default/grub"
rc=0; out=$(L quiet boot on </dev/null 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = "spark-shell: no terminal to ask on -- add --yes to go ahead" ] && [ ! -e "$H/root/etc/default/grub.d" ] && ok "warning: quiet boot on with no terminal, one line, nothing written" || bad "warning boot no terminal" "rc=$rc $out"
rc=0; out=$(printf 'n\n' | A quiet boot on 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = "spark-shell quiet boot on changes how this machine starts:
the boot menu is hidden, and the kernel and init are silent.
It adds a GRUB settings file and runs update-grub (sudo).
spark-shell quiet boot off puts it back.

Continue? [y/N] spark-shell: nothing was changed." ] && [ ! -e "$H/root/etc/default/grub.d" ] && ! grep -q 'QUIET_BOOT=yes' "$HOME/.config/spark-shell/config" \
    && ok "warning: quiet boot on names what it changes and asks; n stops it" || bad "warning boot text" "rc=$rc $out"
rc=0; out=$(L quiet boot on --dry-run </dev/null 2>&1) || rc=$?
[ "$rc" = 0 ] && ! printf '%s\n' "$out" | grep -q 'Continue?\|no terminal' && ok "warning: quiet boot on --dry-run never asks" || bad "warning boot dry-run" "rc=$rc $out"
rc=0; out=$(printf 'yes\n' | A quiet boot on 2>&1) || rc=$?
[ "$rc" = 0 ] && [ -e "$H/root/etc/default/grub.d/zz-spark-shell-quiet.cfg" ] && ok "warning: quiet boot on, yes goes ahead" || bad "warning boot yes" "rc=$rc $out"
rc=0; out=$(L quiet boot off </dev/null 2>&1) || rc=$?
[ "$rc" = 0 ] && ! printf '%s\n' "$out" | grep -q 'Continue?\|no terminal' && ok "warning: quiet boot off never asks" || bad "warning boot off" "rc=$rc $out"
# macOS: the Terminal.app colors
fresh
console_stubs Darwin
rc=0; out=$(printf 'n\n' | A on 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = "spark-shell replaces your shell files, installs packages
and changes the Terminal.app colors.
spark-shell on --dry-run shows every change.

Continue? [y/N] spark-shell: nothing was changed." ] && ok "warning (macOS): the Terminal.app colors" || bad "warning mac" "rc=$rc $out"

# --- 20. the bar at the top of the screen --------------------------------
# a fixture tree in place of /sys and /proc (SPARK_SHELL_SYS, SPARK_SHELL_PROC),
# stubs for ip, bluetoothctl and amixer (wpctl and pactl stubs that fail, so
# plain ALSA is the audio system), jq the real one. The theme fixture's
# accent is #ff5555, its muted #555555, its red #aa0000. The Linux half is
# guarded by uname like 14.
bar_fixture() {   # a wire up, wifi up at 49/70, a bluetooth controller with a device, a battery at 80, two ALSA cards (0 plays and captures, 1 plays)
    S=$H/sys; P=$H/proc; export SPARK_SHELL_SYS=$S SPARK_SHELL_PROC=$P
    mkdir -p "$S/class/net/eth0" "$S/class/net/wlan0/wireless" "$S/class/net/lo" "$S/class/bluetooth/hci0" "$S/class/power_supply/BAT0" "$P/net" "$P/asound/card0/pcm0p/sub0" "$P/asound/card0/pcm0c/sub0" "$P/asound/card1/pcm0p/sub0"
    : > "$S/class/net/eth0/device"; echo 1 > "$S/class/net/eth0/type"; echo 1 > "$S/class/net/eth0/carrier"; echo up > "$S/class/net/eth0/operstate"; echo 1000 > "$S/class/net/eth0/speed"
    : > "$S/class/net/wlan0/device"; echo 1 > "$S/class/net/wlan0/type"; echo up > "$S/class/net/wlan0/operstate"
    echo 772 > "$S/class/net/lo/type"
    echo Battery > "$S/class/power_supply/BAT0/type"; echo 80 > "$S/class/power_supply/BAT0/capacity"; echo Discharging > "$S/class/power_supply/BAT0/status"
    echo 40000000 > "$S/class/power_supply/BAT0/energy_now"; echo 50000000 > "$S/class/power_supply/BAT0/energy_full"; echo 60000000 > "$S/class/power_supply/BAT0/energy_full_design"
    echo 20000000 > "$S/class/power_supply/BAT0/power_now"; echo 123 > "$S/class/power_supply/BAT0/cycle_count"
    printf 'Inter-| sta-|   Quality        |   Discarded packets               | Missed | WE\n face | tus | link level noise |  nwid  crypt   frag  retry   misc | beacon | 22\n wlan0: 0000   49.  -61.  -256        0      0      0      0      0        0\n' > "$P/net/wireless"
    printf ' 0 [Jabra          ]: USB-Audio - Jabra SPEAK 410 USB\n                      Jabra SPEAK 410 USB at usb-0000:00:14.0-2, full speed\n 1 [HDMI           ]: HDA-Intel - HD-Audio Generic\n                      HD-Audio Generic at 0xdc5c8000 irq 104\n' > "$P/asound/cards"
    for s in card0/pcm0p card0/pcm0c card1/pcm0p; do echo closed > "$P/asound/$s/sub0/status"; done
    cat > "$H/.local/bin/ip" <<'STUB'
#!/bin/sh
case "$*" in
    *route*) echo 'default via 192.0.2.1 dev eth0 proto dhcp src 192.0.2.10 metric 100' ;;
    *"dev eth0"*) echo '2: eth0    inet 192.0.2.10/24 brd 192.0.2.255 scope global eth0' ;;
    *"dev wlan0"*) echo '3: wlan0    inet 192.0.2.20/24 brd 192.0.2.255 scope global wlan0' ;;
esac
STUB
    cat > "$H/.local/bin/bluetoothctl" <<'STUB'
#!/bin/sh
log=${XDG_STATE_HOME:-$HOME/.local/state}/bt.log; mkdir -p "$(dirname "$log")"
case "$*" in
    show) printf 'Controller 00:11:22:33:44:55 (public)\n\tPowered: yes\n' ;;
    "devices Connected") [ -e "$HOME/bt-none" ] || echo 'Device 00:25:D1:4A:C2:AA MAJOR V' ;;
    "devices Paired") echo 'Device 00:25:D1:4A:C2:AA MAJOR V' ;;
    devices) printf 'Device 00:25:D1:4A:C2:AA MAJOR V\nDevice 11:22:33:44:55:66 Buds\n' ;;
    "connect "*) echo "$*" >> "$log"; echo 'Connection successful' ;;
    "disconnect "*) echo "$*" >> "$log"; echo 'Successful disconnected' ;;
    *) echo "$*" >> "$log" ;;
esac
STUB
    cat > "$H/.local/bin/wpa_cli" <<'STUB'
#!/bin/sh
log=${XDG_STATE_HOME:-$HOME/.local/state}/wpa.log; mkdir -p "$(dirname "$log")"
[ "$1" != -i ] || shift 2
sel=$(cat "$HOME/wpa.sel" 2>/dev/null || echo 0)
name() { case $1 in 0) echo home ;; 1) echo old ;; 2) echo open ;; esac; }
case "$*" in
    status) [ -e "$HOME/wpa.down" ] || printf 'bssid=00:11:22:33:44:55\nssid=%s\nwpa_state=COMPLETED\n' "$(name "$sel")" ;;
    scan) echo OK ;;
    scan_results) printf 'bssid / frequency / signal level / flags / ssid\n00:11:22:33:44:55\t2412\t-55\t[WPA2-PSK-CCMP][ESS]\thome\n00:11:22:33:44:66\t2437\t-80\t[WPA2-PSK-CCMP][ESS]\tcafe\n00:11:22:33:44:77\t2462\t-70\t[ESS]\topen\n' ;;
    list_networks) printf 'network id / ssid / bssid / flags\n0\thome\tany\t[CURRENT]\n1\told\tany\t\n' ;;
    add_network) echo 2 ;;
    "select_network "*) echo "$*" >> "$log"; echo "$2" > "$HOME/wpa.sel"; rm -f "$HOME/wpa.down"; echo OK ;;
    disconnect) echo "$*" >> "$log"; touch "$HOME/wpa.down"; echo OK ;;
    *) echo "$*" >> "$log"; echo OK ;;
esac
STUB
    printf '#!/bin/sh\nprintf "%%s | %%s\\n" "$*" "${SPARK_SHELL_PANEL_AT:-}" >> "${XDG_STATE_HOME:-$HOME/.local/state}/foot.log"\n' > "$H/.local/bin/foot"
    cat > "$H/.local/bin/amixer" <<'STUB'
#!/bin/sh
log=${XDG_STATE_HOME:-$HOME/.local/state}/amixer.log; mkdir -p "$(dirname "$log")"
[ "$1" != -q ] || shift
case "$*" in *scontrols) [ ! -e "$HOME/amixer-refuse" ] || exit 1 ;; esac   # amixer-refuse: ALSA cannot read its configuration
case "$*" in
    "-D default info") exit 1 ;;
    "-D bluealsa sget MAJOR V - A2DP") m=on; [ ! -e "$HOME/bmuted" ] || m=off; printf "Simple mixer control 'MAJOR V - A2DP',0\n  Limits: Playback 0 - 127\n  Front Left: Playback 76 [60%%] [0.00dB] [%s]\n" "$m" ;;
    "-D bluealsa sget MAJOR V - SCO") m=on; [ ! -e "$HOME/bcmuted" ] || m=off; printf "Simple mixer control 'MAJOR V - SCO',0\n  Mono: Playback 10 [67%%] [-5.82dB] [on] Capture 9 [60%%] [0.00dB] [%s]\n" "$m" ;;
    "-D bluealsa sset "*) echo "$*" >> "$log"
        case "$*" in *"A2DP mute") touch "$HOME/bmuted" ;; *"A2DP unmute") rm -f "$HOME/bmuted" ;; *"SCO nocap") touch "$HOME/bcmuted" ;; *"SCO cap") rm -f "$HOME/bcmuted" ;; esac ;;
    "-c 0 scontrols") printf "Simple mixer control 'Master',0\nSimple mixer control 'PCM',0\nSimple mixer control 'Capture',0\n" ;;
    "-c 1 scontrols") printf "Simple mixer control 'IEC958',0\n" ;;
    "-c 0 sget Master") m=on; [ ! -e "$HOME/muted" ] || m=off; printf "Simple mixer control 'Master',0\n  Front Left: Playback 26214 [40%%] [%s]\n  Front Right: Playback 26214 [40%%] [%s]\n" "$m" "$m" ;;
    "-c 0 sget Capture") m=on; [ ! -e "$HOME/cmuted" ] || m=off; printf "Simple mixer control 'Capture',0\n  Front Left: Capture 1000 [50%%] [%s]\n" "$m" ;;
    "-c "*" sset "*) echo "$*" >> "$log"   # the switches, as amixer keeps them: mute/unmute/toggle for a playback switch, cap/nocap/toggle for a capture one
        case "$*" in
            "-c 0 sset Master mute") touch "$HOME/muted" ;; "-c 0 sset Master unmute") rm -f "$HOME/muted" ;;
            "-c 0 sset Master toggle") if [ -e "$HOME/muted" ]; then rm -f "$HOME/muted"; else touch "$HOME/muted"; fi ;;
            "-c 0 sset Capture nocap") touch "$HOME/cmuted" ;; "-c 0 sset Capture cap") rm -f "$HOME/cmuted" ;;
            "-c 0 sset Capture toggle") if [ -e "$HOME/cmuted" ]; then rm -f "$HOME/cmuted"; else touch "$HOME/cmuted"; fi ;;
            "-c 0 sset Capture mute"|"-c 0 sset Capture unmute") echo "amixer: Invalid command!" >&2; exit 1 ;;
        esac ;;
esac
STUB
    cat > "$H/.local/bin/bluealsa-aplay" <<'STUB'
#!/bin/sh
# bluez-alsa's list, as 3.1 prints it: a headset that plays on A2DP and plays and listens on SCO (only while bt-audio is there)
[ "$1" = -L ] && [ -e "$HOME/bt-audio" ] || exit 0
printf 'bluealsa:SRV=org.bluealsa,DEV=00:25:D1:4A:C2:AA,PROFILE=sco\n    MAJOR V, trusted audio-headset, playback\n    SCO (CVSD): S16_LE 1 channel 8000 Hz\n'
printf 'bluealsa:SRV=org.bluealsa,DEV=00:25:D1:4A:C2:AA,PROFILE=sco\n    MAJOR V, trusted audio-headset, capture\n    SCO (CVSD): S16_LE 1 channel 8000 Hz\n'
printf 'bluealsa:SRV=org.bluealsa,DEV=00:25:D1:4A:C2:AA,PROFILE=a2dp\n    MAJOR V, trusted audio-headset, playback\n    A2DP (AAC): S16_LE 2 channels 48000 Hz\n'
printf 'bluealsa:SRV=org.bluealsa,DEV=bad;dev,PROFILE=a2dp\n    Crafted, trusted audio-headset, playback\n'
STUB
    chmod +x "$H/.local/bin/bluealsa-aplay"
    printf '#!/bin/sh\nexit 1\n' > "$H/.local/bin/wpctl"; cp "$H/.local/bin/wpctl" "$H/.local/bin/pactl"
    cp "$H/.local/bin/wpctl" "$H/.local/bin/tmux"   # a tmux that is not running (this machine may run one)
    chmod +x "$H/.local/bin/ip" "$H/.local/bin/bluetoothctl" "$H/.local/bin/amixer" "$H/.local/bin/wpctl" "$H/.local/bin/pactl" "$H/.local/bin/tmux" "$H/.local/bin/wpa_cli" "$H/.local/bin/foot"
}
full=$(printf '\342\226\210'); shade=$(printf '\342\226\221')
count() { printf '%s' "$1" | LC_ALL=C grep -o "$2" | wc -l | tr -d ' '; }   # count TEXT GLYPH -> how many
fresh
desktop_stubs
desk_stubs
bar_fixture
theme_fixture '#ff5555'
mkdir -p "$HOME/.config/spark-shell"; printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"
sh "$SH" on --yes >/dev/null
sway=$HOME/.config/sway/config; amlog=$H/.local/state/amixer.log
if [ "$(uname -s)" = Darwin ]; then
    st=0; out=$(sh "$SH" bar status --once 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = 'spark-shell bar: not on macOS, which has its own desktop' ] && ok "macOS: bar status refuses, na, one line, exit 1" || bad "macOS bar status" "st=$st $out"
    st=0; out=$(sh "$SH" bar --desktop 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = 'spark-shell bar: no desktop here (spark-shell on desktop)' ] && ok "macOS: bar --desktop refuses, one line" || bad "macOS bar --desktop" "st=$st $out"
    st=0; out=$(sh "$SH" bar 2>&1) || st=$?
    [ "$st" -eq 0 ] && ok "macOS: bare bar exits 0 (the status line's state, or that tmux is not running)" || bad "macOS bar" "st=$st $out"
else
    # the render: the bar block from the config, the palette's hex, the font in pango's words
    grep -q '^bar {$' "$sway" && grep -q '^    position top$' "$sway" && grep -q "^    status_command $REPO/spark-shell bar status\$" "$sway" && grep -q '^    mode dock$' "$sway" \
        && ok "sway: a bar at the top, dock mode, drawn by the clone's spark-shell bar status" || bad "sway bar render" "$(grep -n 'bar {\|position\|status_command\|mode ' "$sway")"
    grep -q '^    font pango:DejaVu Sans Mono 12$' "$sway" && ok "sway: the bar's font is FONT in pango's words (DejaVu Sans Mono 12)" || bad "bar font" "$(grep -n 'font' "$sway")"
    grep -q '^        background #000000d9$' "$sway" && grep -q '^        focused_workspace #ff5555 #ff5555 #000000$' "$sway" && grep -q '^        inactive_workspace #000000d9 #000000d9 #555555$' "$sway" \
        && ok "sway: the bar's colors are the palette's, the background with the picture's alpha (d9 = 0.85)" || bad "bar colors" "$(grep -n 'background\|_workspace' "$sway")"
    grep -q "^bindsym XF86AudioRaiseVolume exec $REPO/spark-shell bar volume up\$" "$sway" && grep -q "^bindsym XF86AudioMicMute exec $REPO/spark-shell bar volume mic\$" "$sway" \
        && ok "sway: the volume keys and the mic mute key run spark-shell bar volume" || bad "volume keys" "$(grep -n XF86 "$sway")"
    ! grep -q 'mod+p ' "$sway" && grep -q '^for_window \[app_id="spark-dialog"\] floating enable, border none, move position center$' "$sway" \
        && ok "sway: no Super+p any more; the panel window floats in the middle" || bad "panel key" "$(grep -n 'spark-dialog\|mod+p' "$sway")"
    printf 'DESKTOP=sway\nFONT=Test Mono:pixelsize=14\nWALLPAPER=none\n' > "$HOME/.config/spark-shell/config"
    sh "$SH" on --yes >/dev/null
    grep -q '^    font pango:Test Mono 14px$' "$sway" && grep -q '^        background #000000$' "$sway" && ok "sway: a pixelsize font is Npx in pango; no picture, an opaque bar" || bad "bar font px" "$(grep -n 'font\|background' "$sway")"
    printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"
    sh "$SH" on --yes >/dev/null
    # one line: every block present, in its group, parted by dividers
    st=0; line=$(sh "$SH" bar status --once 2>&1) || st=$?
    names=$(printf '%s' "$line" | jq -r '[.[] | .name + ":" + .instance] | join(" ")' 2>/dev/null || :)
    [ "$st" -eq 0 ] && [ "$names" = 'lan: wifi: bt: div: out:name out:gauge mic:name mic:gauge div: bat: div: clock: logo:' ] \
        && ok "bar status --once: lan, wifi, bt | out (name, gauge), mic (name, gauge) | bat | clock, one JSON array; no theme block (the palette is the panel's)" || bad "bar line" "st=$st $names $line"
    printf '%s' "$line" | jq -e 'all(.[]; .markup == "pango" and .separator == false)' >/dev/null 2>&1 && ok "bar: every block is pango markup with swaybar's own separator off" || bad "bar markup" "$line"
    t() { printf '%s' "$line" | jq -r --arg n "$1" --arg i "${2:-}" '.[] | select(.name == $n and .instance == $i) | .full_text'; }   # t NAME [INSTANCE] -> its text
    [ "$(t lan)" = "<span foreground='#555555'>lan</span>" ] && ok "lan: the word alone, muted, when the wire is up (no address on screen)" || bad "lan block" "$(t lan)"
    w=$(t wifi); [ "$(count "$w" "'#ff5555'")" = 3 ] && [ "$(count "$w" "'#555555'")" = 2 ] && ! printf '%s' "$w" | grep -q '192\.' \
        && ok "wifi: four rising bars, 3 lit in the accent at 49/70 (70%), the word muted, no address" || bad "wifi block" "$w"
    [ "$(t bt)" = "<span foreground='#555555'>bt</span> <span foreground='#ff5555'>$(printf '\342\227\217')</span> major v" ] && ok "bt: the word muted, a dot in the accent, the connected device's name in the text color, lowercase" || bad "bt block" "$(t bt)"
    [ "$(t out name)" = "<span foreground='#555555'>out</span> jabra" ] && ok "out: the word muted, the card's ALSA id in the text color, lowercase (jabra)" || bad "out name" "$(t out name)"
    g=$(t out gauge); [ "$(count "$g" "$full")" = 4 ] && [ "$(count "$g" "$shade")" = 6 ] && printf '%s' "$g" | grep -q "^<span foreground='#ff5555'>" \
        && ok "out: the gauge is 10 cells, 4 full blocks in the accent at 40%, 6 light shades muted" || bad "out gauge" "$g"
    [ "$(t mic name)" = "<span foreground='#555555'>mic</span> jabra" ] && ok "mic: muted while idle, with the card's name" || bad "mic block" "$(t mic name)"
    g=$(t mic gauge); [ "$(count "$g" "$full")" = 5 ] && [ "$(count "$g" "$shade")" = 5 ] && printf '%s' "$g" | grep -q "^<span foreground='#ff5555'>" \
        && ok "mic: its own gauge, 5 full blocks in the accent at 50% (the Capture level)" || bad "mic gauge" "$g"
    [ "$(t bat)" = "<span foreground='#555555'>bat</span> <span foreground='#aaaaaa'>80</span>" ] && ok "bat: the word muted, the number in the text color, no gauge" || bad "bat block" "$(t bat)"
    printf '%s' "$(t clock)" | grep -Eq "^<span foreground='#555555'>[A-Za-z]+ [0-9]{2} [A-Za-z]+</span> [0-9]{2}:[0-9]{2}$" && ok "clock: the date muted, the time in the text color" || bad "clock block" "$(t clock)"
    printf '%s' "$(t logo)" | grep -Eq "^<span foreground='#[0-9a-f]{6}'>$(printf '\342\235\257')</span>$" && ok "logo: spark-shell's sign, the prompt sign in the palette's yellow, one cell" || bad "logo block" "$(t logo)"
    [ "$(printf '%s' "$line" | jq -r '[.[] | select(.name == "div")] | length')" = 3 ] && [ "$(printf '%s' "$line" | jq -r '.[3].full_text')" = "<span foreground='#555555'>$(printf '\342\224\202')</span>" ] && [ "$(printf '%s' "$line" | jq -r '.[-1].name')" = logo ] \
        && ok "bar: three thin dividers in the muted color, one between each pair of groups, the sign last" || bad "dividers" "$line"
    LC_ALL=C grep -q "[^ -~${tab}]" "$SH" && bad "the script holds a byte outside ASCII (the glyphs must be built from their bytes)" || ok "the script stays ASCII: the glyphs are built from their bytes"
    # the states: mute, a recording mic, a low battery, a charging one, sound on another card
    touch "$H/muted"; line=$(sh "$SH" bar status --once)
    g=$(t out gauge); [ "$(count "$g" "'#ff5555'")" = 0 ] && [ "$(count "$g" "$full")" = 4 ] && ok "out muted: the level stays, the whole gauge turns muted" || bad "muted gauge" "$g"
    rm -f "$H/muted"
    echo 'state: RUNNING' > "$P/asound/card0/pcm0c/sub0/status"; line=$(sh "$SH" bar status --once)
    [ "$(t mic name)" = "<span foreground='#aa0000'>mic $(printf '\342\227\217')</span> jabra" ] && ok "mic recording: the word turns red, with a dot" || bad "mic live" "$(t mic name)"
    echo closed > "$P/asound/card0/pcm0c/sub0/status"
    echo 10 > "$S/class/power_supply/BAT0/capacity"; line=$(sh "$SH" bar status --once)
    [ "$(t bat)" = "<span foreground='#555555'>bat</span> <span foreground='#aa0000'>$(printf '\342\232\240') 10</span>" ] && ok "bat under 15: a warning sign and the number, red" || bad "bat low" "$(t bat)"
    echo Charging > "$S/class/power_supply/BAT0/status"; line=$(sh "$SH" bar status --once)
    [ "$(t bat)" = "<span foreground='#555555'>bat</span> <span foreground='#aaaaaa'>10</span><span foreground='#ff5555'>+</span>" ] && ok "bat charging: a plus in the accent, and no red while it charges" || bad "bat charging" "$(t bat)"
    echo 80 > "$S/class/power_supply/BAT0/capacity"; echo Discharging > "$S/class/power_supply/BAT0/status"
    echo 'state: RUNNING' > "$P/asound/card1/pcm0p/sub0/status"; line=$(sh "$SH" bar status --once)
    [ "$(t out name)" = "<span foreground='#555555'>out</span> hdmi" ] && [ -z "$(t out gauge)" ] && ok "sound playing on the HDMI card: out follows it; no volume control there, so no gauge" || bad "out follows" "$(t out name) / $(t out gauge)"
    echo closed > "$P/asound/card1/pcm0p/sub0/status"
    touch "$H/bt-none"; line=$(sh "$SH" bar status --once)
    [ "$(t bt)" = "<span foreground='#555555'>bt</span>" ] && ok "bt with nothing connected: the word alone, muted" || bad "bt idle" "$(t bt)"
    rm -f "$H/bt-none"
    echo 0 > "$S/class/net/eth0/carrier"; line=$(sh "$SH" bar status --once)
    [ "$(t lan)" = "<span foreground='#555555'>lan</span> <span foreground='#aa0000'>$(printf '\342\232\240') down</span>" ] && ok "lan with no carrier: a warning sign and down, in red" || bad "lan down" "$(t lan)"
    echo 1 > "$S/class/net/eth0/carrier"
    # present-only: a machine with none of it shows the clock alone, and no divider
    mv "$S" "$S.full"; mv "$P" "$P.full"; mkdir -p "$S" "$P"
    line=$(sh "$SH" bar status --once)
    [ "$(printf '%s' "$line" | jq -r '[.[] | .name] | join(" ")')" = 'clock logo' ] && ok "present-only: no hardware, no block for it and no divider; the clock and the sign alone" || bad "bare machine" "$line"
    rm -rf "$S" "$P"; mv "$S.full" "$S"; mv "$P.full" "$P"
    # clicks: swaybar's stream on stdin; the gauges set the levels, any other block opens the panel; each redraws the bar at once
    rm -f "$amlog" "$H/.local/state/foot.log"
    printf '[\n,{"name":"out","instance":"gauge","button":1,"relative_x":60,"width":100}\n,{"name":"out","instance":"gauge","button":4}\n,{"name":"out","instance":"gauge","button":3}\n,{"name":"mic","instance":"gauge","button":3}\n,{"name":"mic","instance":"gauge","button":1,"relative_x":30,"width":100}\n,{"name":"out","instance":"name","button":1,"x":1500,"relative_x":12,"width":90}\n,{"name":"lan","instance":"","button":1,"x":1200,"relative_x":5,"width":40}\n' > "$H/clicks"
    sh "$SH" bar status < "$H/clicks" > "$H/bar.out" 2> "$H/bar.err" & bp=$!
    sleep 3
    kill "$bp" 2>/dev/null || :; wait "$bp" 2>/dev/null || :
    head -1 "$H/bar.out" | grep -q '^{"version":1,"click_events":true}$' && [ "$(sed -n 2p "$H/bar.out")" = '[' ] && ok "bar status: the i3bar header asks for clicks, then the array opens" || bad "bar header" "$(head -2 "$H/bar.out")"
    [ "$(grep -c '^\[{' "$H/bar.out")" -ge 2 ] && ok "bar status: one line at start, and the bar drawn again after the clicks (quick clicks share one redraw)" || bad "bar redraws" "$(grep -c '^\[{' "$H/bar.out") lines; $(cat "$H/bar.err")"
    [ "$(cat "$amlog" 2>/dev/null)" = "$(printf '%s\n' '-c 0 sset Master 60%' '-c 0 sset Master 5%+' '-c 0 sset Master toggle' '-c 0 sset Capture toggle' '-c 0 sset Capture 30%')" ] \
        && ok "clicks: a click at 60% of the gauge sets 60%, the wheel up adds 5, a right click mutes; the mic gauge mutes on a right click and sets 30% on a click" || bad "click actions" "$(cat "$amlog" 2>&1)"
    for _i in 1 2 3 4 5 6; do [ "$(wc -l < "$H/.local/state/foot.log" 2>/dev/null || echo 0)" -ge 2 ] && break; sleep 1; done   # two detached openers write the log
    [ "$(sort "$H/.local/state/foot.log" 2>/dev/null | grep -v '^--version')" = "$(printf '%s\n' "--app-id spark-dialog -W 60x44 -o pad=24x19 -o colors-dark.background=0f0f0f -o colors-dark.alpha=1.0 -e $REPO/spark-shell dialog lan | " "--app-id spark-dialog -W 60x44 -o pad=24x19 -o colors-dark.background=0f0f0f -o colors-dark.alpha=1.0 -e $REPO/spark-shell dialog out | ")" ] \
        && ok "a click on out or lan opens the panel with that block first, in a foot window; no placement passed" || bad "panel open" "$(cat "$H/.local/state/foot.log" 2>&1); $(cat "$H/bar.err")"
    ! tail -1 "$H/bar.out" | grep -q '192\.0\.2\.' && ok "a click never puts an address in the bar" || bad "address in the bar" "$(tail -1 "$H/bar.out")"
    [ ! -e "$H/.local/state/spark-shell/bar.pid" ] && ok "bar status ended: its pid file is gone" || bad "bar pid file stays"
    # the volume keys reach the running bar (the default card back to the first: the asoundrc the click wrote is gone)
    rm -f "$amlog" "$H/.config/alsa/asoundrc"
    sh "$SH" bar status < /dev/null > "$H/bar.out" 2> "$H/bar.err" & bp=$!
    sleep 1
    sh "$SH" bar volume up; sleep 1; sh "$SH" bar volume mute; sleep 1; sh "$SH" bar volume mic
    sleep 1
    kill "$bp" 2>/dev/null || :; wait "$bp" 2>/dev/null || :
    [ "$(cat "$amlog" 2>/dev/null)" = "$(printf '%s\n' '-c 0 sset Master 5%+' '-c 0 sset Master toggle' '-c 0 sset Capture toggle')" ] && [ "$(grep -c '^\[{' "$H/bar.out")" -ge 3 ] \
        && ok "bar volume up|mute|mic: the key's change, and the running bar redrawn after each" || bad "volume keys" "$(cat "$amlog" 2>&1); $(grep -c '^\[{' "$H/bar.out") lines"
    st=0; out=$(sh "$SH" bar volume louder 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = 'spark-shell bar: volume takes up, down, mute or mic' ] && ok "bar volume: a wrong word is refused in one line" || bad "volume refuse" "st=$st $out"
    # the out page switches the card: ALSA's default for new programs, in spark-shell's own marked file, the ! form alsa.conf takes for a name
    st=0; out=$(sh "$SH" bar panel out use hdmi 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$out" = 'out HDMI for programs started from now' ] && [ "$(sed -n '2,3p' "$H/.config/alsa/asoundrc" 2>/dev/null | paste -sd ' ' -)" = 'defaults.pcm.!card HDMI defaults.ctl.!card HDMI' ] && head -1 "$H/.config/alsa/asoundrc" | grep -q '^# rendered by spark-shell' \
        && ok "bar panel out use hdmi: the HDMI card becomes ALSA's default for new programs, in spark-shell's own marked file, the ! form" || bad "asoundrc" "st=$st $out; $(cat "$H/.config/alsa/asoundrc" 2>&1)"
    rm -f "$H/.config/alsa/asoundrc"
    # a file of yours is never written over
    printf 'pcm.!default { type hw card 1 }\n' > "$H/.config/alsa/asoundrc"
    st=0; out=$(sh "$SH" bar panel out use hdmi 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = 'asoundrc is yours' ] && [ "$(cat "$H/.config/alsa/asoundrc")" = 'pcm.!default { type hw card 1 }' ] \
        && ok "out use with an asoundrc of yours: the file stays, one line says so" || bad "asoundrc yours" "st=$st $out; $(cat "$H/.config/alsa/asoundrc")"
    rm -f "$H/.config/alsa/asoundrc"
    # a file ALSA refuses would take every program's sound with it: taken back at once, one line says so
    touch "$H/amixer-refuse"
    st=0; out=$(sh "$SH" bar panel out use hdmi 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = 'ALSA refused the file' ] && [ ! -e "$H/.config/alsa/asoundrc" ] \
        && ok "out use when ALSA refuses the file: the file is taken back, one line says so" || bad "asoundrc refused" "st=$st $out; $(cat "$H/.config/alsa/asoundrc" 2>&1)"
    rm -f "$H/amixer-refuse"
    # the file v0.45 wrote (the card by name without !) is mended when the bar starts, and read
    printf '# rendered by spark-shell (bar): the sound card for programs started from now -- spark-shell off removes it\ndefaults.pcm.card HDMI\ndefaults.ctl.card HDMI\n' > "$H/.config/alsa/asoundrc"
    line=$(sh "$SH" bar status --once)
    [ "$(sed -n '2,3p' "$H/.config/alsa/asoundrc" | paste -sd ' ' -)" = 'defaults.pcm.!card HDMI defaults.ctl.!card HDMI' ] && head -1 "$H/.config/alsa/asoundrc" | grep -q '^# rendered by spark-shell' && [ "$(t out name)" = "<span foreground='#555555'>out</span> hdmi" ] \
        && ok "bar status: a file v0.45 wrote is mended to the ! form at the start, and the out block reads it (hdmi)" || bad "asoundrc mend" "$(cat "$H/.config/alsa/asoundrc"); $(t out name)"
    rm -f "$H/.config/alsa/asoundrc"
    # Bluetooth on plain ALSA (issue 6): bluez-alsa's devices beside the cards, a pick routed through spark-shell's file, its level bluez-alsa's mixer
    touch "$HOME/bt-audio"; rm -f "$amlog"
    out=$(printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"t","version":"0"}}}' '{"jsonrpc":"2.0","method":"notifications/initialized"}' '{"jsonrpc":"2.0","id":2,"method":"resources/read","params":{"uri":"spark-shell://out/rows"}}' | sh "$SH" provide out 2>/dev/null)
    printf '%s\n' "$out" | jq -r 'select(.id == 2) | .result.contents[0].text' | jq -e '[.rows[] | .text] | index("MAJOR V") != null and index("Crafted") == null' >/dev/null \
        && ok "out on plain ALSA: a headset bluez-alsa offers is a row beside the cards; a device whose address is no address is not" || bad "bt out row" "$(printf '%s\n' "$out" | tail -2 | cut -c1-400)"
    st=0; out=$(sh "$SH" bar panel out use major v 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$out" = 'out MAJOR V for programs started from now' ] && grep -qxF '    playback.pcm { type plug slave.pcm "bluealsa:DEV=00:25:D1:4A:C2:AA,PROFILE=a2dp" }' "$H/.config/alsa/asoundrc" \
        && grep -qxF '    capture.pcm "sysdefault"' "$H/.config/alsa/asoundrc" && grep -qx '# bluetooth out: MAJOR V' "$H/.config/alsa/asoundrc" && head -1 "$H/.config/alsa/asoundrc" | grep -q '^# rendered by spark-shell' \
        && ok "out use a headset: playing goes through bluez-alsa's A2DP for programs started from now, listening stays the card's, in spark-shell's own file" || bad "bt out use" "st=$st $out; $(cat "$H/.config/alsa/asoundrc" 2>&1)"
    line=$(sh "$SH" bar status --once)
    [ "$(t out name)" = "<span foreground='#555555'>out</span> major v" ] && sh "$SH" bar panel out level 35 >/dev/null && sh "$SH" bar panel out mute >/dev/null \
        && [ "$(cat "$amlog")" = "$(printf '%s\n' '-D bluealsa sset MAJOR V - A2DP 35%' '-D bluealsa sset MAJOR V - A2DP mute')" ] \
        && ok "out on a headset: the bar names it, and the level and mute are bluez-alsa's mixer" || bad "bt out level" "$(t out name); $(cat "$amlog" 2>&1)"
    rm -f "$amlog" "$HOME/bmuted"
    st=0; out=$(sh "$SH" bar panel mic use major v 2>&1) || st=$?
    [ "$st" -eq 0 ] && grep -qxF '    capture.pcm { type plug slave.pcm "bluealsa:DEV=00:25:D1:4A:C2:AA,PROFILE=sco" }' "$H/.config/alsa/asoundrc" && grep -q 'PROFILE=a2dp' "$H/.config/alsa/asoundrc" \
        && sh "$SH" bar panel mic mute >/dev/null && [ "$(cat "$amlog")" = '-D bluealsa sset MAJOR V - SCO nocap' ] \
        && ok "mic use a headset: listening on its hands-free link, playing kept; the mute is the SCO capture switch" || bad "bt mic" "st=$st $out; $(cat "$H/.config/alsa/asoundrc" 2>&1); $(cat "$amlog" 2>&1)"
    rm -f "$HOME/bcmuted"
    st=0; out=$(sh "$SH" bar panel out use hdmi 2>&1) || st=$?
    [ "$st" -eq 0 ] && ! grep -q 'PROFILE=a2dp' "$H/.config/alsa/asoundrc" && grep -q 'PROFILE=sco' "$H/.config/alsa/asoundrc" && grep -qx 'defaults.pcm.!card HDMI' "$H/.config/alsa/asoundrc" \
        && ok "out use a card after a headset: playing back on the card, the headset's mic kept" || bad "bt back to card" "st=$st $out; $(cat "$H/.config/alsa/asoundrc" 2>&1)"
    rm -f "$HOME/bt-audio"
    line=$(sh "$SH" bar status --once)
    printf '%s' "$line" | grep -q 'major v' \
        && ok "a headset gone: the bar still names the device the file sends listening to" || bad "bt gone" "$line"
    rm -f "$H/.config/alsa/asoundrc"
    # your own ~/.asoundrc setting the default (here through a file it includes): spark-shell says so and writes nothing
    mkdir -p "$HOME/.config/box"; printf 'pcm.!default { type hw card 1 }\n' > "$HOME/.config/box/box.conf"; printf '<~/.config/box/box.conf>\n' > "$HOME/.asoundrc"
    st=0; out=$(sh "$SH" bar panel out use hdmi 2>&1) || st=$?
    # shellcheck disable=SC2088   # the line as the user reads it, a tilde and all
    [ "$st" -eq 1 ] && [ "$out" = 'spark-shell panel: ~/.config/box/box.conf picks the sound device, read by your ~/.asoundrc: spark-shell leaves it to that file' ] && [ ! -e "$H/.config/alsa/asoundrc" ] \
        && ok "out use when your own ~/.asoundrc sets the default, through a file it includes: one line names that file, nothing written" || bad "asoundrc theirs" "st=$st $out"
    rows=$(sh "$SH" bar panel out --list 2>&1 | cut -f3 | sed -n '/^out /p')
    # shellcheck disable=SC2088   # the line as the user reads it, a tilde and all
    ! printf '%s\n' "$rows" | grep -q '^out use ' && sh "$SH" bar panel out --list 2>&1 | grep -q '~/.config/box/box.conf picks the sound device, read by your ~/.asoundrc' \
        && ok "out rows when your own file picks the device: the devices shown with no pick that could only be refused, and one row names the file" || bad "asoundrc theirs rows" "$rows"
    rm -rf "$HOME/.asoundrc" "$HOME/.config/box"
    # PipeWire: the same bar through wpctl (the stub answers as WirePlumber 0.5 does), the volume keys and a pick of output
    wplog=$H/.local/state/wpctl.log; rm -f "$wplog"
    cat > "$H/.local/bin/wpctl" <<'STUB'
#!/bin/sh
log=${XDG_STATE_HOME:-$HOME/.local/state}/wpctl.log; mkdir -p "$(dirname "$log")"
[ ! -e "$HOME/wp-down" ] || { echo 'Could not connect to PipeWire' >&2; exit 1; }
sink=$(cat "$HOME/wp-sink" 2>/dev/null || echo 50)
V=$(printf '\342\224\202'); T=$(printf '\342\224\234\342\224\200'); E=$(printf '\342\224\224\342\224\200')   # the tree wpctl draws, built from its bytes
s50=' '; s51=' '; [ "$sink" = 50 ] && s50='*' || s51='*'
case "$1" in
    status) printf '%s\n' "PipeWire 'pipewire-0' [1.6.8, ada@box, cookie:1]" " $E Clients:" '        33. WirePlumber                         [1.6.8, ada@box, pid:900]' '' 'Audio' " $T Devices:" "  $V      46. Jabra SPEAK 410 USB                 [alsa]" "  $V      47. Built-in Audio                      [alsa]" "  $V  " \
            " $T Sinks:" " $V  $s50   50. Jabra SPEAK 410 USB Analog Stereo   [vol: 0.40]" " $V  $s51   51. Built-in Audio Digital Stereo (HDMI) [vol: 1.00]" " $V  " " $T Sources:" " $V  *   52. Jabra SPEAK 410 USB Mono            [vol: 0.50]" " $V  " " $T Filters:" " $V  " " $E Streams:" '' 'Video' " $T Devices:" " $V  " " $T Sinks:" " $V  " " $E Sources:" ;;
    get-volume) case $2 in *SINK*) v=0.40; f=$HOME/wp-muted ;; *) v=0.50; f=$HOME/wp-cmuted ;; esac
        if [ -e "$f" ]; then echo "Volume: $v [MUTED]"; else echo "Volume: $v"; fi ;;
    set-default) echo "$*" >> "$log"; echo "$2" > "$HOME/wp-sink" ;;
    set-mute) echo "$*" >> "$log"; f=$HOME/wp-muted; case $2 in *SOURCE*) f=$HOME/wp-cmuted ;; esac
        case $3 in 1) touch "$f" ;; 0) rm -f "$f" ;; toggle) if [ -e "$f" ]; then rm -f "$f"; else touch "$f"; fi ;; esac ;;
    *) echo "$*" >> "$log" ;;
esac
STUB
    printf '#!/bin/sh\n[ -e "$HOME/wp-rec" ] && echo %s || echo %s\n' "'[{\"info\":{\"state\":\"running\",\"props\":{\"media.class\":\"Stream/Input/Audio\"}}}]'" "'[]'" > "$H/.local/bin/pw-dump"
    printf '#!/bin/sh\nexit 0\n' > "$H/.local/bin/pipewire"
    printf '#!/bin/sh\n[ "$*" = "-x bluealsa" ] && [ -e "$HOME/bluealsa-runs" ]\n' > "$H/.local/bin/pgrep"
    chmod +x "$H/.local/bin/wpctl" "$H/.local/bin/pw-dump" "$H/.local/bin/pipewire" "$H/.local/bin/pgrep"
    line=$(sh "$SH" bar status --once)
    [ "$(t out name)" = "<span foreground='#555555'>out</span> jabra speak" ] && [ "$(t mic name)" = "<span foreground='#555555'>mic</span> jabra speak" ] \
        && ok "PipeWire: out and mic name WirePlumber's defaults, whole words up to 12 characters" || bad "wp names" "$(t out name) / $(t mic name)"
    g=$(t out gauge); m=$(t mic gauge); [ "$(count "$g" "$full")" = 4 ] && [ "$(count "$m" "$full")" = 5 ] && ok "PipeWire: the gauges are wpctl's volumes (40, 50)" || bad "wp gauges" "$g / $m"
    touch "$H/wp-rec"; line=$(sh "$SH" bar status --once)
    [ "$(t mic name)" = "<span foreground='#aa0000'>mic $(printf '\342\227\217')</span> jabra speak" ] && ok "PipeWire: a running capture stream turns the mic red, with a dot" || bad "wp mic live" "$(t mic name)"
    rm -f "$H/wp-rec"
    sh "$SH" bar volume up; sh "$SH" bar volume down; sh "$SH" bar volume mute; sh "$SH" bar volume mic
    [ "$(cat "$wplog" 2>/dev/null)" = "$(printf '%s\n' 'set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+' 'set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%-' 'set-mute @DEFAULT_AUDIO_SINK@ toggle' 'set-mute @DEFAULT_AUDIO_SOURCE@ toggle')" ] \
        && ok "PipeWire: the volume keys are wpctl's, capped at 100 (-l 1.0); mute and the mic key toggle" || bad "wp keys" "$(cat "$wplog" 2>&1)"
    line=$(sh "$SH" bar status --once); g=$(t out gauge)
    [ "$(count "$g" "'#ff5555'")" = 0 ] && ok "PipeWire: a muted output turns its gauge muted" || bad "wp muted" "$g"
    rm -f "$wplog" "$H/wp-muted" "$H/wp-cmuted"
    st=0; out=$(sh "$SH" bar panel out use built-in audio digital stereo '(hdmi)' 2>&1) || st=$?
    line=$(sh "$SH" bar status --once)
    [ "$st" -eq 0 ] && [ "$(cat "$wplog")" = 'set-default 51' ] && [ "$(t out name)" = "<span foreground='#555555'>out</span> built-in" ] && [ ! -e "$H/.config/alsa/asoundrc" ] \
        && ok "PipeWire: out use moves sound at once (wpctl set-default), no ALSA file written" || bad "wp out use" "st=$st $out; $(cat "$wplog" 2>&1); $(t out name)"
    out=$(sh "$SH" check || true); printf '%s\n' "$out" | grep -q '^ok     sound        PipeWire answers: out Built-in Audio Digital Stereo (HDMI), mic Jabra SPEAK 410 USB Mono$' \
        && [ "$(printf '%s\n' "$out" | grep -c '^[a-zA-Z]* *sound ')" = 1 ] \
        && ok "check: one sound row, PipeWire answers, naming the output and the mic" || bad "check wp" "$(printf '%s\n' "$out" | grep sound)"
    # what keeps sound from PipeWire, each a warn of its own: bluez-alsa beside it, your own ALSA default
    touch "$H/bluealsa-runs"; printf 'pcm.!default { type hw card 1 }\n' > "$HOME/.asoundrc"
    out=$(sh "$SH" check || true)
    # shellcheck disable=SC2088   # the line as the user reads it, a tilde and all
    printf '%s\n' "$out" | grep -q '^warn   sound        bluez-alsa runs beside PipeWire, and only one of them can offer Bluetooth sound -- turn one of them off$' \
        && printf '%s\n' "$out" | grep -q '^warn   sound        your ~/.asoundrc picks the sound device, so ALSA programs that use it skip PipeWire -- take the default out of it$' \
        && ok "check: bluez-alsa running and an ~/.asoundrc of yours with a default are said, each with its remedy" || bad "check wp warns" "$(printf '%s\n' "$out" | grep sound)"
    rm -f "$H/bluealsa-runs" "$HOME/.asoundrc" "$H/.local/bin/pgrep"
    printf '# a file with no default\npcm.mine { type hw card 1 }\n' > "$HOME/.asoundrc"
    out=$(sh "$SH" check || true)
    ! printf '%s\n' "$out" | grep -q 'asoundrc' && ok "check: an ~/.asoundrc that sets no default is not said (no empty name)" || bad "asoundrc no default" "$(printf '%s\n' "$out" | grep sound)"
    rm -f "$HOME/.asoundrc"
    # PipeWire installed and silent: outside a desktop it starts with the next one (no systemd); inside, a warn
    touch "$H/wp-down"
    out=$(env -u WAYLAND_DISPLAY sh "$SH" check || true); printf '%s\n' "$out" | grep -q '^ok     sound        PipeWire starts with the desktop$' && ok "check: PipeWire silent outside a desktop, no systemd: it starts with the desktop, ok" || bad "check wp later" "$(printf '%s\n' "$out" | grep sound)"
    out=$(WAYLAND_DISPLAY=wayland-1 sh "$SH" check || true); printf '%s\n' "$out" | grep -q '^warn   sound        PipeWire does not answer -- leave the desktop and log in again$' && ok "check: PipeWire silent inside a desktop: a warn, log in again" || bad "check wp silent" "$(printf '%s\n' "$out" | grep sound)"
    rm -f "$H/wp-down"
    rm -f "$wplog" "$H/wp-sink"
    printf '#!/bin/sh\nexit 1\n' > "$H/.local/bin/wpctl"; rm -f "$H/.local/bin/pw-dump" "$H/.local/bin/pipewire"; chmod +x "$H/.local/bin/wpctl"
    # the verb: both halves, one of them, the config key, the render, a running sway
    export SWAYSOCK=$H/sway.sock
    st=0; out=$(sh "$SH" bar 2>&1) || st=$?
    [ "$st" -eq 0 ] && printf '%s\n' "$out" | grep -q '^status line: tmux is not running (it shows inside tmux)$' && printf '%s\n' "$out" | grep -q '^bar: shown at the top of the screen -- bat, bt, clock, lan, mic, out, wifi (spark-shell bar off --desktop hides it)$' \
        && ok "bar: both halves said -- tmux not running, the bar shown with its blocks" || bad "bar bare" "st=$st $out"
    st=0; out=$(sh "$SH" bar --terminal 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = 'spark-shell bar: tmux is not running -- start tmux first' ] && ok "bar --terminal with no tmux: refused in one line" || bad "bar --terminal" "st=$st $out"
    st=0; out=$(sh "$SH" bar off --desktop 2>&1) || st=$?
    [ "$st" -eq 0 ] && grep -q '^DESKTOP_BAR=no$' "$HOME/.config/spark-shell/config" && grep -q '^    mode invisible$' "$sway" && printf '%s\n' "$out" | grep -q '^ok     sway         reloaded' && printf '%s\n' "$out" | grep -q '^bar: hidden (spark-shell bar on --desktop shows it)$' \
        && ok "bar off --desktop: DESKTOP_BAR=no, the bar block in invisible mode, sway reloaded, one closing line" || bad "bar off" "st=$st $out $(grep -n 'mode ' "$sway")"
    st=$(sh "$SH" status); printf '%s\n' "$st" | grep -q '^  bar   hidden' && ok "status: the bar row says hidden" || bad "status bar hidden" "$(printf '%s\n' "$st" | grep '^  bar')"
    out=$(sh "$SH" check || true); printf '%s\n' "$out" | grep -q '^ok     top          hidden (spark-shell bar on --desktop shows it)' && ok "check: the top row says hidden, ok" || bad "check top hidden" "$out"
    st=0; out=$(sh "$SH" bar on --desktop 2>&1) || st=$?
    [ "$st" -eq 0 ] && grep -q '^DESKTOP_BAR=yes$' "$HOME/.config/spark-shell/config" && grep -q '^    mode dock$' "$sway" && ok "bar on --desktop: DESKTOP_BAR=yes, dock mode again" || bad "bar on" "st=$st $out"
    st=$(sh "$SH" status); printf '%s\n' "$st" | grep -q '^  bar   shown .*at the top of the screen: bat, bt, clock, lan, mic, out, wifi' && ok "status: the bar row names the blocks present" || bad "status bar shown" "$(printf '%s\n' "$st" | grep '^  bar')"
    out=$(sh "$SH" check || true); printf '%s\n' "$out" | grep -q '^ok     top          the bar draws bat, bt, clock, lan, mic, out, wifi$' \
        && [ "$(printf '%s\n' "$out" | grep '^[a-zA-Z]* *sound ')" = 'warn   sound        PipeWire is not installed: the bar reads plain ALSA -- spark-shell on desktop' ] \
        && ok "check: the top row names the blocks; on plain ALSA one sound warn, PipeWire missing, the remedy on desktop" || bad "check top" "$out"
    # the panel as text (no terminal): the title line restates what opened it, then ONE list in sections -- the first section's rows, then what every other section can do; each row wears a sign, names its section and carries its action
    DOT=$(printf '\342\227\217'); RING=$(printf '\342\227\213'); TICK=$(printf '\342\234\223'); CROSS=$(printf '\342\234\227'); GO=$(printf '\342\226\270'); SEP=$(printf '\302\267')
    journal=$H/.local/state/spark-shell/panel; rm -f "$journal/undo" "$journal/recent"   # the lists below in their plain order: nothing picked yet
    out=$(sh "$SH" bar panel lan --list)
    [ "$(printf '%s\n' "$out" | sed -n 1p)" = "lan        up $SEP 192.0.2.10" ] && [ "$(printf '%s\n' "$out" | sed -n 2p)" = "  lan        address 192.0.2.10	lan show" ] && printf '%s\n' "$out" | grep -q "^  lan        speed 1000 Mb/s	lan show$" && printf '%s\n' "$out" | grep -q "^  lan        gateway 192.0.2.1	lan show$" \
        && ok "panel lan: the address, the speed and the gateway, a look only, first (the old bar panel spelling)" || bad "panel lan" "$out"
    printf '%s\n' "$out" | grep -q "^$RING wifi       cafe .*	wifi connect cafe$" && printf '%s\n' "$out" | grep -q "^  theme      [a-z-]* $SEP size 12 $SEP more	theme more$" && ! printf '%s\n' "$out" | grep -q "^  theme      dracula	" && ! printf '%s\n' "$out" | grep -q "^. bat        " && ! printf '%s\n' "$out" | grep -q "^. clock      " && ! printf '%s\n' "$out" | grep -q "^. layout     none" \
        && [ "$(printf '%s\n' "$out" | grep -c "	lan show$")" = "$(printf '%s\n' "$out" | grep -c "	[a-z]* show$")" ] && printf '%s\n' "$out" | grep -q "^$GO apps       choose the allowed apps	apps pick$" && [ "$(printf '%s\n' "$out" | grep -n "^$GO apps" | head -1 | cut -d: -f1)" -lt "$(printf '%s\n' "$out" | grep -n "^$RING wifi       cafe" | cut -d: -f1)" ] \
        && ok "panel lan: then what every other section can do, in order, the slow wifi last; never another section's look-only rows (no layout saved: its one row is a look)" || bad "panel lan rest" "$out"
    out=$(sh "$SH" panel --list)
    printf '%s\n' "$out" | sed -n 1p | grep -q "^$(date '+%A %d %B') $SEP [0-9][0-9]:[0-9][0-9]$" && [ "$(printf '%s\n' "$out" | sed -n 2p)" = "wifi home $SEP bt $DOT MAJOR V $SEP out 40% $SEP mic 50% $SEP bat 80% $SEP theme none" ] && [ "$(printf '%s\n' "$out" | sed -n 3p)" = "$GO spark      chat	spark chat" ] && printf '%s\n' "$out" | grep -q "^$DOT wifi       home	wifi disconnect$" && ! printf '%s\n' "$out" | grep -q "	[a-z]* show$" \
        && ok "panel with nothing first (Super+d): the glance (the date and time, the bar's facts; a wire that is up says nothing), the chat row first, then everything it can do" || bad "panel bar" "$out"
    out=$(sh "$SH" panel spark --list)
    [ "$(printf '%s\n' "$out" | sed -n 1p)" = "spark      a conversation, in this window" ] && [ "$(printf '%s\n' "$out" | sed -n 2p)" = "$GO spark      chat	spark chat" ] && ok "panel spark --list: the one row that opens the conversation" || bad "panel spark" "$out"
    # the cache: a probe's last answer is kept with its age; a long section shows what matters and a `more` row
    cache=$H/.local/state/spark-shell/panel; mkdir -p "$cache"
    { echo "$(date +%s)"; printf 'a1\t4\t1\nb2\t3\t1\nc3\t3\t1\nd4\t2\t1\ne5\t1\t1\nopen\t2\t0\nold\t1\t1\n'; } > "$cache/wifi.scan"
    out=$(sh "$SH" panel --list)
    [ "$(printf '%s\n' "$out" | grep -c "^$RING wifi       ")" = 4 ] && printf '%s\n' "$out" | grep -q "^$RING wifi       old .* $TICK saved	wifi connect old$" && printf '%s\n' "$out" | grep -q "^  wifi       3 more	wifi more$" \
        && ok "panel: a fresh scan is read from the cache; wifi shows the saved ones, the strongest three and a more row" || bad "wifi more" "$out"
    [ "$(sh "$SH" panel wifi --list | grep -c "^$RING wifi       ")" = 7 ] && ! sh "$SH" panel wifi --list | grep -q "	wifi more$" && ok "panel wifi: the section that opened the panel shows every network, no more row" || bad "wifi full" "$(sh "$SH" panel wifi --list)"
    { echo "$(( $(date +%s) - 120 ))"; printf 'stale\t4\t1\n'; } > "$cache/wifi.scan"
    sh "$SH" panel --list | grep -q "^$RING wifi       cafe" && ! sh "$SH" panel --list | grep -q stale && grep -q "^cafe" "$cache/wifi.scan" && [ $(( $(date +%s) - $(sed -n 1p "$cache/wifi.scan") )) -lt 60 ] \
        && ok "panel: a scan older than a minute is made again and kept, with its time" || bad "wifi stale" "cache: $(tr '\n' '|' < "$cache/wifi.scan"); list: $(sh "$SH" panel --list 2>&1 | grep wifi | tr '\n' '|')"
    { echo "$(( $(date +%s) - 120 ))"; printf 'stale\t4\t1\n'; } > "$cache/wifi.scan"; printf '#!/bin/sh\n[ "$3" = scan_results ] && printf "bssid\\tfreq\\tsignal\\tflags\\tssid\\n00\\t2412\\t-50\\t[WPA2]\\thome\\n"; [ "$3" = status ] && echo ssid=home; exit 0\n' > "$H/.local/bin/wpa_cli.thin"
    mv "$H/.local/bin/wpa_cli" "$H/wpa_cli.full"; mv "$H/.local/bin/wpa_cli.thin" "$H/.local/bin/wpa_cli"; chmod +x "$H/.local/bin/wpa_cli"
    sh "$SH" panel --list >/dev/null; _age=$(( $(date +%s) - $(sed -n 1p "$cache/wifi.scan") ))
    mv "$H/wpa_cli.full" "$H/.local/bin/wpa_cli"
    [ "$_age" -ge 50 ] && [ "$_age" -lt 60 ] && ok "panel: a scan that found one network at most (the radio was busy) is kept for ten seconds, not a minute" || bad "wifi thin" "age $_age: $(tr '\n' '|' < "$cache/wifi.scan")"
    rm -f "$cache/wifi.scan"
    printf '%s\n' "$out" | grep -q "^  theme      none $SEP size 12 $SEP more	theme more$" && [ "$(printf '%s\n' "$out" | grep -c "^. theme      ")" = 1 ] && sh "$SH" panel theme --list > "$H/theme.list" && ! grep -q "^. theme      wallpaper" "$H/theme.list" && sh "$SH" panel wallpaper --list | grep -q "^  wallpaper  navy	wallpaper use navy$" && grep -q "^  theme      dracula	theme dracula$" "$H/theme.list" && grep -q "^  theme      more transparency	theme transparency more$" "$H/theme.list" \
        && ok "panel: theme is one row in the list, the palette and the size, a more; opened on theme, the palettes, the font and transparency; the wallpaper its own section" || bad "theme more" "$(printf '%s\n' "$out" | grep theme; grep theme "$H/theme.list" | head -3)"
    out=$(sh "$SH" panel apps --list)
    [ "$(printf '%s\n' "$out" | sed -n 1p)" = "apps       every app allowed $SEP Enter opens one" ] && [ "$(printf '%s\n' "$out" | sed -n 2p)" = "$GO apps       terminal	apps terminal" ] && [ "$(printf '%s\n' "$out" | sed -n 3p)" = "$GO apps       firefox	apps open firefox" ] && printf '%s\n' "$out" | grep -q "^$GO apps       gimp-3.0	apps open gimp-3.0$" && [ "$(printf '%s\n' "$out" | grep "^$GO apps       " | tail -1)" = "$GO apps       choose the allowed apps	apps pick" ] \
        && ok "panel apps --list: the title says what is allowed, a terminal first, a row per app that opens it, the picker last" || bad "panel apps" "$out"
    rm -f "$H/.local/state/swaymsg.log"; st=0; out=$(SWAYSOCK=/tmp/x sh "$SH" panel apps terminal 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$out" = 'opened a terminal' ] && grep -qx 'exec foot' "$H/.local/state/swaymsg.log" && ok "panel apps terminal: a terminal window, as Super+Return" || bad "apps terminal" "st=$st $out $(cat "$H/.local/state/swaymsg.log" 2>&1)"
    st=0; out=$(SWAYSOCK=/tmp/x sh "$SH" panel apps open GIMP-3.0 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$out" = 'opened gimp-3.0' ] && grep -q '^exec gimp-3.0' "$H/.local/state/swaymsg.log" && ok "panel apps open NAME: the app opens on the current workspace the way its entry says (any case)" || bad "apps open" "st=$st $out $(tail -2 "$H/.local/state/swaymsg.log" 2>&1)"
    [ "$(sh "$SH" panel --list | sed -n 3p)" = "$GO apps       gimp-3.0	apps open gimp-3.0" ] && [ "$(sed -n 1p "$journal/recent")" = "apps	open gimp-3.0" ] \
        && ok "recent: the app just opened is the first row of the next list, and the journal's first line" || bad "recent" "$(sh "$SH" panel --list | sed -n 2,4p) | $(cat "$journal/recent")"
    st=0; out=$(SWAYSOCK=/tmp/x sh "$SH" panel apps open nowhere 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = 'spark-shell panel: apps: no app named nowhere here' ] && ok "panel apps open: an app that is not here is refused in one line" || bad "apps open gate" "st=$st $out"
    # undo: a step's inverse is read before the act, kept in the journal, played back newest first
    rm -f "$amlog" "$journal/recent"; sh "$SH" panel out use hdmi >/dev/null
    [ "$(sh "$SH" panel undo --list | sed -n 2p)" = "  undo       out Jabra	undo all" ] && [ "$(sh "$SH" panel --list | sed -n 3p)" = "  undo       out Jabra	undo all" ] && [ "$(cat "$journal/undo")" = "out	use Jabra	out Jabra" ] \
        && ok "undo: after out use hdmi the undo row says out Jabra, first in the list; the journal holds the inverse step" || bad "undo row" "$(sh "$SH" panel --list | sed -n 2,5p) | $(cat "$journal/undo" 2>&1)"
    st=0; out=$(sh "$SH" panel undo all 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$out" = "$TICK out Jabra for programs started from now" ] && [ "$(sh "$SH" panel out --list | sed -n 1p)" = "out        Jabra $SEP 40%" ] && ! sh "$SH" panel --list | grep -q "^  undo       " \
        && ok "undo all: the inverse played (out is Jabra again), then nothing to undo" || bad "undo all" "st=$st $out $(sh "$SH" panel out --list | sed -n 1p)"
    rm -f "$journal/undo" "$journal/recent"
    mkdir -p "$HOME/.config/spark-shell/layouts"; printf '{"words": "news and music", "why": "the feeds and a player", "main": {"app": "newsboat"}}\n' > "$HOME/.config/spark-shell/layouts/news"
    out=$(sh "$SH" panel --list)
    _ln=$(printf '%s\n' "$out" | grep -nxF "$GO layout     news and music	layout open news" | cut -d: -f1); _an=$(printf '%s\n' "$out" | grep -n "^$GO apps " | tail -1 | cut -d: -f1)
    [ -n "$_ln" ] && [ -n "$_an" ] && [ "$_ln" -gt "$_an" ] && [ "$(sh "$SH" panel layout --list | sed -n 1p)" = "layout     1 saved" ] \
        && ok "panel: a saved layout comes after the apps, by its words, opening it by name; the layout title counts it" || bad "panel layout row" "$out"
    rm -rf "$HOME/.config/spark-shell/layouts"
    [ ! -e "$H/.local/bin/spark" ] || mv "$H/.local/bin/spark" "$H/spark.away"   # no spark for a moment: the want is refused, not asked
    st=0; out=$(PATH=$H/.local/bin:$sys sh "$SH" panel sideways --list 2>&1) || st=$?
    [ ! -e "$H/spark.away" ] || mv "$H/spark.away" "$H/.local/bin/spark"
    [ "$st" -eq 1 ] && [ "$out" = 'spark-shell panel: spark is not installed -- spark reads what you want (github.com/forgewright-ai/spark)' ] && ok "panel WORDS: a word that is no section is a want (here without spark: refused in one line)" || bad "panel no block" "st=$st $out"
    out=$(sh "$SH" bar panel wifi --list)
    [ "$(printf '%s\n' "$out" | sed -n 1p)" = "wifi       $(printf '\342\226\202\342\226\204\342\226\206\342\226\221') home $SEP 192.0.2.20" ] && [ "$(printf '%s\n' "$out" | sed -n 2p)" = "$DOT wifi       home	wifi disconnect" ] && printf '%s\n' "$out" | sed -n 3p | grep -q "^$RING wifi       cafe .*	wifi connect cafe$" && printf '%s\n' "$out" | sed -n 4p | grep -q "^$RING wifi       open .*	wifi connect open$" && [ "$(printf '%s\n' "$out" | sed -n 5p)" = "  wifi       forget old	wifi forget old" ] \
        && ok "panel wifi (wpa_cli): the network in use first, the ones around strongest first, then forget for a saved one" || bad "panel wifi" "$out"
    st=0; out=$(sh "$SH" bar panel wifi connect cafe 2>&1 </dev/null) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = 'no password given, so not connected' ] && ok "panel wifi connect, a secured network that is new: asks for the password; with none, nothing is done" || bad "wifi connect secured" "st=$st $out"
    wlog=$H/.local/state/wpa.log; rm -f "$wlog"
    st=0; out=$(sh "$SH" bar panel wifi connect open 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$out" = 'connected to open' ] && grep -qx 'set_network 2 ssid "open"' "$wlog" && grep -qx 'set_network 2 key_mgmt NONE' "$wlog" && grep -qx 'enable_network 2' "$wlog" && grep -qx save_config "$wlog" && grep -qx 'select_network 2' "$wlog" \
        && ok "panel wifi connect, an open network: added, saved, selected, connected" || bad "wifi connect open" "st=$st $out; $(cat "$wlog" 2>&1)"
    rm -f "$wlog"
    st=0; out=$(sh "$SH" bar panel wifi disconnect 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$out" = 'disconnected from open' ] && grep -qx disconnect "$wlog" && ok "panel wifi disconnect: one line, the tool told" || bad "wifi disconnect" "st=$st $out"
    echo 0 > "$H/wpa.sel"; rm -f "$H/wpa.down" "$wlog"
    st=0; out=$(sh "$SH" bar panel wifi forget old 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$out" = 'forgot old' ] && grep -qx 'remove_network 1' "$wlog" && grep -qx save_config "$wlog" && ok "panel wifi forget: the saved network removed, the config saved" || bad "wifi forget" "st=$st $out; $(cat "$wlog" 2>&1)"
    st=0; out=$(sh "$SH" bar panel wifi connect nowhere 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = 'spark-shell panel: wifi: connect nowhere is not on the panel now' ] && ok "panel: an action the section does not offer is refused in one line" || bad "panel gate" "st=$st $out"
    out=$(sh "$SH" bar panel bt --list); blog=$H/.local/state/bt.log
    [ "$(printf '%s\n' "$out" | sed -n 1p)" = "bt         $DOT MAJOR V" ] && [ "$(printf '%s\n' "$out" | sed -n 2p)" = "$DOT bt         MAJOR V	bt disconnect MAJOR V" ] && printf '%s\n' "$out" | grep -q "^$RING bt         Buds $SEP new	bt pair Buds$" && printf '%s\n' "$out" | grep -q "^  bt         find new devices	bt scan$" && printf '%s\n' "$out" | grep -q "^  bt         turn off	bt power off$" \
        && ok "panel bt: the connected device, a new one to pair, a row that scans, and off" || bad "panel bt" "$out"
    rm -f "$blog"; st=0; out=$(sh "$SH" bar panel bt disconnect MAJOR V 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$out" = 'disconnected MAJOR V' ] && grep -qx 'disconnect 00:25:D1:4A:C2:AA' "$blog" && ok "panel bt disconnect NAME: the device's address told to bluetoothctl" || bad "bt disconnect" "st=$st $out; $(cat "$blog" 2>&1)"
    out=$(sh "$SH" bar panel out --list)
    [ "$(printf '%s\n' "$out" | sed -n 1p)" = "out        Jabra $SEP 40%" ] && [ "$(printf '%s\n' "$out" | sed -n 2p)" = "$DOT out        Jabra	out show" ] && printf '%s\n' "$out" | grep -q "^$RING out        HDMI	out use HDMI$" && printf '%s\n' "$out" | grep -q "^  out        mute	out mute$" && printf '%s\n' "$out" | grep -q "^  mic        mute	mic mute$" && ! printf '%s\n' "$out" | grep -q "^$DOT mic        Jabra" \
        && ok "panel out: the cards that play, the one in use named, and mute; the mic's mute after, never its look-only row" || bad "panel out" "$out"
    printf ' 0 [USB            ]: USB-Audio - Jabra SPEAK 410 USB\n                      Jabra SPEAK 410 USB at usb-0000:00:14.0-2, full speed\n 1 [HDMI           ]: HDA-Intel - HD-Audio Generic\n' > "$P/asound/cards"
    [ "$(sh "$SH" bar panel out --list | sed -n 1p)" = "out        Jabra SPEAK 410 USB $SEP 40%" ] && ok "ALSA: a card with the generic id USB is named by its long name, read past the driver's own hyphen (USB-Audio)" || bad "alsa usb name" "$(sh "$SH" bar panel out --list | sed -n 1p)"
    printf ' 0 [Jabra          ]: USB-Audio - Jabra SPEAK 410 USB\n                      Jabra SPEAK 410 USB at usb-0000:00:14.0-2, full speed\n 1 [HDMI           ]: HDA-Intel - HD-Audio Generic\n                      HD-Audio Generic at 0xdc5c8000 irq 104\n' > "$P/asound/cards"
    out=$(sh "$SH" bar panel mic --list)
    [ "$(printf '%s\n' "$out" | sed -n 1p)" = "mic        Jabra $SEP 50%" ] && [ "$(printf '%s\n' "$out" | sed -n 2p)" = "$DOT mic        Jabra	mic show" ] && ! printf '%s\n' "$out" | grep -q "mic        HDMI" && printf '%s\n' "$out" | grep -q "^  mic        mute	mic mute$" \
        && ok "panel mic: the cards that capture only, with the level" || bad "panel mic" "$out"
    rm -f "$amlog"; sh "$SH" bar panel mic mute >/dev/null && sh "$SH" bar panel out level 35 >/dev/null
    [ "$(cat "$amlog")" = "$(printf '%s\n' '-c 0 sset Capture nocap' '-c 0 sset Master 35%')" ] && ok "panel mic mute, out level 35: set, not toggled; the mic's capture switch by amixer's own word" || bad "panel sound actions" "$(cat "$amlog")"
    m1=$(sh "$SH" bar panel mic --list | sed -n 1p); un=$(sh "$SH" bar panel mic unmute); m2=$(sh "$SH" bar panel mic --list | sed -n 1p)
    [ "$m1" = "mic        Jabra $SEP 50% $SEP muted" ] && [ "$un" = 'mic unmuted' ] && [ "$m2" = "mic        Jabra $SEP 50%" ] \
        && ok "panel mic mute then unmute: the state read back from amixer, the title says muted in between" || bad "panel mic read back" "$m1 | $un | $m2"
    out=$(sh "$SH" bar panel bat --list)
    [ "$(printf '%s\n' "$out" | sed -n 1p)" = "bat        80% $SEP discharging $SEP 2:00 left" ] && printf '%s\n' "$out" | grep -q "^  bat        health 83% of new	bat show$" && printf '%s\n' "$out" | grep -q "^  bat        cycles 123	bat show$" && printf '%s\n' "$out" | grep -q "^  bat        power 20.0 W	bat show$" \
        && ok "panel bat: the charge, the time left from the kernel's numbers, the health, the cycles" || bad "panel bat" "$out"
    out=$(sh "$SH" bar panel clock --list)
    B=$(printf '\342\226\210')   # the full block: three bytes, so the patterns below never count characters (the CI containers run in the C locale)
    [ "$(printf '%s\n' "$out" | sed -n 1p)" = "$(date '+%A %d %B %Y')" ] && [ -z "$(printf '%s\n' "$out" | sed -n 2p)" ] && printf '%s\n' "$out" | sed -n 3p | grep -q "^ \{40\} *$(date '+%B %Y')$" && printf '%s\n' "$out" | sed -n 4p | grep -q " Su  Mo  Tu  We  Th  Fr  Sa$" && [ "$(printf '%s\n' "$out" | sed -n '4,8p' | grep -c "^[$B ]*${B}[$B ]*      ")" = 5 ] && printf '%s\n' "$out" | sed -n '4,8p' | grep -q "$B$B  *$B" && ! printf '%s\n' "$out" | grep -q "	clock show$" \
        && ok "panel clock: the date alone on top, then the time five rows tall in strokes two cells wide on the left and this month on the right, 34 cells apart; no clock rows" || bad "panel clock" "$out"
    out=$(sh "$SH" bar panel look --list)
    [ "$(printf '%s\n' "$out" | sed -n 1p)" = "theme      none $SEP DejaVu Sans Mono 12" ] && [ "$(printf '%s\n' "$out" | sed -n 2p)" = "$TICK theme      none	theme show" ] && printf '%s\n' "$out" | grep -q "^  theme      dracula	theme dracula$" && printf '%s\n' "$out" | grep -q "^  theme      font bigger $SEP 12 now	theme font bigger$" && ! printf '%s\n' "$out" | grep -q "^. theme      wallpaper" && printf '%s\n' "$out" | grep -q "^$TICK theme      transparency 15%	theme show$" && printf '%s\n' "$out" | grep -q "^  theme      less transparency	theme transparency less$" \
        && ok "panel theme (look, the old word, still opens it): the palettes by name, the font size and transparency, the current ones named" || bad "panel look" "$out"
    st=0; out=$(sh "$SH" panel theme font bigger 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$out" = 'font 13' ] && grep -q '^FONT=DejaVu Sans Mono:size=13$' "$HOME/.config/spark-shell/config" && grep -q '^    font pango:DejaVu Sans Mono 13$' "$sway" \
        && ok "panel theme font bigger: FONT in the config, the bar's font rendered, said in two words" || bad "look font" "st=$st $out $(grep -n 'FONT\|font' "$HOME/.config/spark-shell/config" "$sway")"
    st=0; out=$(sh "$SH" panel theme alpha 0.5 2>&1) || st=$?
    [ "$st" -eq 0 ] && grep -q '^ALPHA=0.5$' "$HOME/.config/spark-shell/config" && grep -q '^        background #00000080$' "$sway" && ok "panel look alpha 0.5: ALPHA in the config, the bar's background rendered with it (80)" || bad "look alpha" "st=$st $out $(grep -n 'background' "$sway")"
    st=0; out=$(sh "$SH" panel theme see-through more 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = 'transparency stops at 50%' ] && grep -q '^ALPHA=0.5$' "$HOME/.config/spark-shell/config" && ok "panel theme see-through more (the word before v0.71) at 50%: transparency refused in one line, nothing written" || bad "transparency floor" "st=$st $out"
    st=0; out=$(sh "$SH" panel theme transparency less 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$out" = "transparency 40% $SEP new windows take it" ] && grep -q '^ALPHA=0.6$' "$HOME/.config/spark-shell/config" && sh "$SH" panel theme --list | grep -q "^$TICK theme      transparency 40%	theme show$" \
        && ok "panel theme transparency less: a tenth less, said as a percent, the row follows (foot takes it with a wallpaper)" || bad "transparency less" "st=$st $out $(grep ALPHA "$HOME/.config/spark-shell/config")"
    sh "$SH" panel --list | grep -q "^  undo       transparency 50%	undo all$" && ok "undo: the transparency step's inverse names the percent it was" || bad "transparency undo" "$(sh "$SH" panel --list | grep undo)"
    # the bar: hide and show from the panel, remembered in the config and the render
    rm -f "$journal/undo"; st=0; out=$(SWAYSOCK=/tmp/x sh "$SH" panel bar off 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$out" = "bar hidden $SEP Super+d opens the dialog" ] && grep -q '^DESKTOP_BAR=no$' "$HOME/.config/spark-shell/config" && grep -q '^    mode invisible$' "$sway" && [ "$(sh "$SH" panel bar --list | sed -n 2p)" = "  bar        show	bar on" ] && sh "$SH" panel --list | grep -q "^  undo       bar shown	undo all$" \
        && ok "panel bar off (the row says hide): DESKTOP_BAR=no, the bar invisible in the render, the row says show now, the undo says shown" || bad "bar off" "st=$st $out $(grep -n 'mode ' "$sway"; sh "$SH" panel bar --list)"
    st=0; out=$(SWAYSOCK=/tmp/x sh "$SH" panel bar on 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$out" = 'bar shown' ] && grep -q '^DESKTOP_BAR=yes$' "$HOME/.config/spark-shell/config" && grep -q '^    mode dock$' "$sway" && [ "$(sh "$SH" panel bar --list | sed -n 2p)" = "  bar        hide	bar off" ] \
        && ok "panel bar on: back, and the row says hide again" || bad "bar on" "st=$st $out"
    # the windows: how new ones sit, this workspace now and the default for new ones
    rm -f "$H/.local/state/swaymsg.log"; st=0; out=$(SWAYSOCK=/tmp/x sh "$SH" panel window tabs 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$out" = 'windows tabs' ] && grep -q '^WINDOWS=tabs$' "$HOME/.config/spark-shell/config" && grep -q '^workspace_layout tabbed$' "$sway" && grep -qxF '[workspace=__focused__ tiling] layout tabbed' "$H/.local/state/swaymsg.log" \
        && [ "$(sh "$SH" panel window --list | sed -n 1p)" = "window     tabs" ] && sh "$SH" panel window --list | grep -q "^$TICK window     tabs	window show$" && sh "$SH" panel window --list | grep -q "^  window     side by side	window split$" && sh "$SH" panel --list | grep -q "^  undo       windows side by side	undo all$" \
        && ok "panel window tabs: WINDOWS=tabs, workspace_layout tabbed rendered, this workspace's tiling windows in tabs now, the rows and the undo say it" || bad "window tabs" "st=$st $out $(grep -n 'workspace_layout' "$sway"; cat "$H/.local/state/swaymsg.log"; sh "$SH" panel window --list)"
    st=0; out=$(SWAYSOCK=/tmp/x sh "$SH" panel window split 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$out" = 'windows side by side' ] && grep -q '^WINDOWS=split$' "$HOME/.config/spark-shell/config" && grep -q '^workspace_layout default$' "$sway" && grep -qxF '[workspace=__focused__ tiling] layout splith' "$H/.local/state/swaymsg.log" \
        && ok "panel window split: side by side again, workspace_layout default" || bad "window split" "st=$st $out"
    st=0; out=$(sh "$SH" panel window sideways 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = 'spark-shell panel: window: sideways is not on the panel now' ] && ok "panel window WORD: a way that is not a row is refused" || bad "window refuse" "st=$st $out"
    # the windows open now: a row that puts one in front, a close row, the steps by name; the tree shows a firefox window while $HOME/fullscreen is there
    touch "$HOME/fullscreen" "$HOME/aerc"; rm -f "$H/.local/state/swaymsg.log"
    st=0; out=$(SWAYSOCK=/tmp/x sh "$SH" panel window close firefox 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$out" = 'firefox closed' ] && grep -qxF '[con_id=77] kill' "$H/.local/state/swaymsg.log" && ! grep -q 'app_id=firefox\] kill' "$H/.local/state/swaymsg.log" && ! sh "$SH" panel --list | grep -q 'undo.*firefox' \
        && ok "panel window close firefox: that one window, by its id, is told to close; no undo row for it" || bad "window close" "st=$st $out $(cat "$H/.local/state/swaymsg.log" 2>&1)"
    rm -f "$H/.local/state/swaymsg.log"; st=0; out=$(SWAYSOCK=/tmp/x sh "$SH" panel window close aerc 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$out" = 'aerc closed' ] && grep -qxF '[con_id=79] kill' "$H/.local/state/swaymsg.log" && ! grep -q 'foot' "$H/.local/state/swaymsg.log" \
        && ok "panel window close aerc: a terminal window goes by what runs in it, and only that terminal is told to close" || bad "window close aerc" "st=$st $out $(cat "$H/.local/state/swaymsg.log" 2>&1)"
    rm -f "$H/.local/state/swaymsg.log"; st=0; out=$(SWAYSOCK=/tmp/x sh "$SH" panel apps close aerc 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$out" = 'aerc closed' ] && grep -qxF '[con_id=79] kill' "$H/.local/state/swaymsg.log" && ok "panel apps close NAME: read as window close, the way spark tends to say it" || bad "apps close" "st=$st $out"
    SWAYSOCK=/tmp/x sh "$SH" panel window --list > "$H/win.list"
    grep -q "^$(printf '\342\226\270') window     firefox	window focus firefox$" "$H/win.list" && grep -q "^  window     close firefox	window close firefox$" "$H/win.list" && grep -q "^$(printf '\342\226\270') window     aerc	window focus aerc$" "$H/win.list" && ! grep -q 'spark-dialog\|window     foot' "$H/win.list" \
        && ok "panel window --list: each open window by its name is a row that puts it in front, and a close row; the terminal by what runs in it; the panel's own window not listed" || bad "window rows" "$(cat "$H/win.list")"
    st=0; out=$(SWAYSOCK=/tmp/x sh "$SH" panel window close nothing 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = 'spark-shell panel: window: no window named nothing is open' ] && ok "panel window close NAME: a window that is not open is refused" || bad "window close refuse" "st=$st $out"
    rm -f "$HOME/fullscreen" "$HOME/aerc" "$H/win.list"
    printf 'DESKTOP=sway\nTHEME=dracula\n' > "$HOME/.config/spark-shell/config"
    line=$(sh "$SH" bar status --once)
    printf '%s' "$line" | jq -e '[.[] | select(.name == "theme")] | length == 0' >/dev/null && ok "bar: no theme block even with a palette set (the panel's theme section has it)" || bad "theme block" "$line"
    [ "$(sh "$SH" bar panel look --list | grep -c "^$TICK theme      dracula	theme show$")" = 1 ] && ok "panel look: the current palette named" || bad "look current" "$(sh "$SH" bar panel look --list | head -4)"
    printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"
    # a want: spark turns the words into steps from what this machine offers; the gate refuses the rest
    cat > "$H/.local/bin/spark" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" > "$HOME/spark.argv"
printf '{"why": "quiet: no sound out, no mic, no bluetooth", "steps": [{"page": "out", "action": "mute"}, {"page": "mic", "action": "mute"}, {"page": "bt", "action": "power", "arg": "off"}, {"page": "bt", "action": "dance", "arg": "x"}, {"page": "theme", "action": "alpha", "arg": "7"}, {"page": "desktop", "action": "lights", "arg": "low"}]}\n'
EOF
    chmod +x "$H/.local/bin/spark"; rm -f "$amlog" "$blog"
    st=0; out=$(sh "$SH" bar quiet please 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$out" = "$(printf '%s\n' 'panel> quiet please' "  $TICK out muted" "  $TICK mic muted" "  $TICK bluetooth off" "  $CROSS bt: dance x is not on the panel now" "  $CROSS theme: alpha takes 0 to 1" "  $CROSS no desktop here")" ] \
        && ok "bar WORDS: one line per step with its sign and no why line; a step the panel does not offer, or a section it does not have, is refused in a few words, the rest played" || bad "bar want" "st=$st $out"
    [ "$(cat "$amlog")" = "$(printf '%s\n' '-c 0 sset Master mute' '-c 0 sset Capture nocap')" ] && grep -qx 'power off' "$blog" && ok "bar WORDS: the steps reached amixer and bluetoothctl" || bad "want steps" "$(cat "$amlog" "$blog" 2>&1)"
    grep -q '^do this on the desktop: quiet please$' "$H/spark.argv" && grep -q 'bt: disconnect MAJOR V, pair Buds, scan, power off' "$H/spark.argv" && grep -q 'out: use HDMI, mute, level N' "$H/spark.argv" && grep -q 'layout: new TASK' "$H/spark.argv" && grep -q 'theme: .*dracula, .*font bigger' "$H/spark.argv" && grep -q "What the bar shows now: lan up $SEP 192.0.2.10; wifi .* home $SEP 192.0.2.20; bt $DOT MAJOR V; out Jabra $SEP 40%" "$H/spark.argv" \
        && ok "bar WORDS: spark gets the words, what the bar shows now (a question has its facts) and what each section offers, a new layout among them" || bad "want brief" "$(cat "$H/spark.argv")"
    printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "$HOME/spark.argv"; printf "{\\"why\\": \\"a question\\", \\"answer\\": \\"192.0.2.10 on the wire, 192.0.2.20 on wifi.\\", \\"steps\\": []}\\n"\n' > "$H/.local/bin/spark"; chmod +x "$H/.local/bin/spark"
    rm -f "$H/spark.argv"; st=0; out=$(SWAYSOCK=/tmp/x sh "$SH" panel Firefox please 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$out" = "$(printf '%s\n' 'panel> Firefox please' "  $TICK opened firefox")" ] && [ ! -e "$H/spark.argv" ] && grep -q '^exec firefox' "$H/.local/state/swaymsg.log" \
        && ok "panel WORDS, one or two, that name an app this machine declares (Firefox): the app opens at once, spark is not asked" || bad "want program" "st=$st $out $(cat "$H/spark.argv" 2>&1)"
    rm -f "$H/spark.argv"; st=0; out=$(SWAYSOCK=/tmp/x sh "$SH" panel Firefox fullscreen please now 2>&1) || st=$?
    printf '%s\n' "$out" | grep -q '^  layout> Firefox fullscreen please now$' && grep -q 'write the layout for this need' "$H/spark.argv" && ! grep -q 'do this on the desktop' "$H/spark.argv" \
        && ok "panel WORDS, more of them, that name an app: a layout for the task, and that is the whole answer (spark is not asked for steps after)" || bad "want layout" "st=$st $out $(head -2 "$H/spark.argv")"
    rm -f "$H/spark.argv"; st=0; out=$(SWAYSOCK=/tmp/x sh "$SH" panel what is my address 2>&1) || st=$?
    grep -q 'do this on the desktop: what is my address' "$H/spark.argv" && ok "panel WORDS with no app named go to spark, even where a word is a command (what, on a Mac)" || bad "want not an app" "st=$st $out $(head -3 "$H/spark.argv" 2>&1)"
    rm -f "$H/spark.argv"; st=0; out=$(SWAYSOCK=/tmp/x sh "$SH" panel Firefox fullscreen 2>&1) || st=$?
    grep -q 'write the layout for this need: Firefox fullscreen' "$H/spark.argv" && ok "panel WORDS, two, naming an app with a layout word (fullscreen): a layout, not a bare open" || bad "want app layout word" "st=$st $out $(head -2 "$H/spark.argv")"
    rm -f "$journal/undo" "$journal/recent"
    st=0; out=$(sh "$SH" panel what is my address 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$out" = "$(printf '%s\n' 'panel> what is my address' '  192.0.2.10 on the wire, 192.0.2.20 on wifi.')" ] && ok "panel WORDS that ask: the answer in place, no steps" || bad "want answer" "st=$st $out"
    rm -f "$H/spark.argv"; st=0; out=$(SWAYSOCK=/tmp/x sh "$SH" panel writing with vi and the prompt shell 2>&1) || st=$?
    printf '%s\n' "$out" | grep -q '^  layout> writing with vi and the prompt shell$' && ! printf '%s\n' "$out" | grep -q '192.0.2.10' \
        && ok "panel WORDS that are no question and get no step: a layout for the task, never the model's shrug or a facts dump" || bad "want task fallback" "st=$st $out"
    # words about closing an app never open it or a layout: they go to the list, where spark picks window close
    cat > "$H/.local/bin/spark" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" > "$HOME/spark.argv"
printf '{"why": "close it", "steps": [{"page": "window", "action": "close", "arg": "firefox"}]}\n'
EOF
    chmod +x "$H/.local/bin/spark"; touch "$HOME/fullscreen"; rm -f "$H/.local/state/swaymsg.log" "$HOME/spark.argv"
    st=0; out=$(SWAYSOCK=/tmp/x sh "$SH" panel close the window with firefox 2>&1) || st=$?
    [ "$st" -eq 0 ] && printf '%s\n' "$out" | grep -q "^  $TICK firefox closed$" && grep -qxF '[con_id=77] kill' "$H/.local/state/swaymsg.log" && ! grep -q '^exec firefox' "$H/.local/state/swaymsg.log" && grep -q 'close firefox' "$HOME/spark.argv" \
        && ok "panel WORDS about closing an app: never the app opened or a layout; spark picks window close firefox from the list, and the window is told to close" || bad "want close" "st=$st $out $(cat "$H/.local/state/swaymsg.log" 2>&1)"
    printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "$HOME/spark.argv"\nprintf "{\\"why\\": \\"no\\", \\"steps\\": []}\\n"\n' > "$H/.local/bin/spark"; chmod +x "$H/.local/bin/spark"; rm -f "$H/.local/state/swaymsg.log"
    st=0; out=$(SWAYSOCK=/tmp/x sh "$SH" panel quit firefox 2>&1) || st=$?
    printf '%s\n' "$out" | grep -q "^  $CROSS no step on the panel does that$" && ! grep -q '^exec firefox' "$H/.local/state/swaymsg.log" 2>/dev/null \
        && ok "panel WORDS about closing with no step from spark: one honest line, never a layout" || bad "want close no step" "st=$st $out"
    rm -f "$HOME/spark.argv"; st=0; out=$(SWAYSOCK=/tmp/x sh "$SH" panel zebra stripes 2>&1) || st=$?
    printf '%s\n' "$out" | grep -q "^  $CROSS no step on the panel does that$" && ! printf '%s\n' "$out" | grep -q 'layout>' && ! grep -q 'write the layout' "$HOME/spark.argv" 2>/dev/null \
        && ok "panel WORDS, a word or two with no step from spark: one honest line, never a layout (about once opened aerc)" || bad "want short no step" "st=$st $out"
    rm -f "$HOME/fullscreen"
    # the window itself, driven by an fzf of the test's: a pick runs through panel_run and panel_step, the next list carries the undo row
    cat > "$H/.local/bin/fzf" <<'STUB'
#!/bin/sh
case $1 in --version) echo 0.60.3; exit 0 ;; esac
n=$(cat "$HOME/fzf.calls" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$HOME/fzf.calls"
cat > "$HOME/fzf.in.$n"; printf '%s\n' "$*" > "$HOME/fzf.args.$n"
if [ "$n" -eq 1 ]; then printf '\n  out        mute\tout mute\n'; exit 0; else exit 130; fi
STUB
    chmod +x "$H/.local/bin/fzf"; rm -f "$H/fzf.calls" "$H/fzf.in."* "$H/fzf.args."* "$amlog" "$journal/undo" "$journal/recent"
    st=0; out=$(SPARK_SHELL_TEST_TTY=1 sh "$SH" panel 2>&1 </dev/null) || st=$?
    [ "$st" -eq 0 ] && [ "$(cat "$H/fzf.calls")" = 2 ] && sed "s/$(printf '\033')\[[0-9;]*m//g" "$H/fzf.in.2" | grep -q "^  $TICK out muted$" && printf '%s\n' "$out" | sed "s/$(printf '\033')\[[0-9;]*m//g" | grep -q "^    $(date '+%A %d %B') *$(printf '\342\235\257')$" && ! printf '%s\n' "$out" | grep -q 'not found' && grep -q "undo.*out unmute	undo all$" "$H/fzf.in.2" && grep -q -- "--highlight-line --pointer  --marker  --padding 1,0,0,2 --header-lines=[0-9]* --bind change:reload(cat .*/head; if \[ -n {q} \]; then cat .*/rows.full; else cat .*/rows.short; fi) --bind resize:reload(cat .*/head; " "$H/fzf.args.2" && grep -q -- 'click-header:transform(if \[ "$FZF_CLICK_HEADER_LINE" = 1 \] && \[ "$FZF_CLICK_HEADER_COLUMN" -ge [0-9]* \]; then echo abort; fi)' "$H/fzf.args.2" && grep -qx -- '-c 0 sset Master mute' "$amlog" \
        && ok "the window: Enter on out mute plays the step, the receipt rides in fzf's first lines with a check, the next list opens with the undo row, fzf holds the glance (header lines, a reload with the head on a change and on a resize, the corner's click told by line and column); Esc ends it" || bad "window pick" "st=$st calls=$(cat "$H/fzf.calls" 2>&1) out=$(printf '%s' "$out" | tr -d '\033' | tr '\n' '|' | tail -c 400) in2=$(grep undo "$H/fzf.in.2" 2>&1)"
    plain=$(sed "s/$(printf '\033')\[[0-9;]*m//g" "$H/fzf.in.1")
    printf '%s\n' "$plain" | grep -q "^  $(date '+%A %d %B') *$(printf '\342\235\257')$" && printf '%s\n' "$plain" | grep -q "$B$B.*      .* Su  Mo  Tu  We  Th  Fr  Sa$" && [ "$(printf '%s\n' "$plain" | grep -c "$B$B")" -ge 5 ] && [ "$(grep -c "$B$B" "$H/fzf.in.2")" -ge 5 ] && ! printf '%s\n' "$plain" | grep -q "wifi home $SEP" && ! printf '%s\n' "$plain" | grep -q "out        Jabra" && grep -q "	about open$" "$H/fzf.in.1" && grep -q "pick an option, or say what you would like .* Esc .*closes" "$H/fzf.args.1" \
        && ok "the window: one view behind every door as fzf's first lines -- the date with the close glyph in the last cell, the time in strokes beside this month, no facts line and no title line; the about row last; the hint names the keys; drawn again after the pick" || bad "window view" "$(printf '%s' "$plain" | tr '\n' '|' | head -c 600)"
    rm -f "$H/.local/bin/fzf" "$H/fzf.calls" "$H/fzf.in."* "$H/fzf.args."* "$journal/undo" "$journal/recent"
    # a pick that puts a window on the screen closes the panel: fzf runs once, the receipt is the last thing printed, the app was sent to sway
    cat > "$H/.local/bin/fzf" <<'STUB'
#!/bin/sh
case $1 in --version) echo 0.60.3; exit 0 ;; esac
n=$(cat "$HOME/fzf.calls" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$HOME/fzf.calls"
cat > "$HOME/fzf.in.$n"; printf '%s\n' "$*" > "$HOME/fzf.args.$n"
if [ "$n" -eq 1 ]; then printf '\n  apps       firefox\tapps open firefox\n'; exit 0; else exit 130; fi
STUB
    swlog=$H/.local/state/swaymsg.log; chmod +x "$H/.local/bin/fzf"; rm -f "$H/fzf.calls" "$H/fzf.in."* "$H/fzf.args."* "$journal/undo" "$journal/recent" "$swlog"
    st=0; out=$(SWAYSOCK=/tmp/x SPARK_SHELL_TEST_TTY=1 sh "$SH" panel 2>&1 </dev/null) || st=$?
    plain=$(printf '%s\n' "$out" | sed "s/$(printf '\033')\[[0-9;]*m//g" | tr -d '\033' | sed 's/\[2J\[H//')
    [ "$st" -eq 0 ] && [ "$(cat "$H/fzf.calls")" = 1 ] && [ "$(printf '%s\n' "$plain" | grep -v '^ *$' | tail -1)" = "    $TICK opened firefox" ] && grep -q '^exec firefox' "$swlog" \
        && ok "the window: Enter on an app opens it and the panel closes at once, the receipt its last line (the window is the receipt)" || bad "window app closes" "st=$st calls=$(cat "$H/fzf.calls" 2>&1) out=$(printf '%s' "$plain" | tr '\n' '|' | tail -c 300) sway=$(grep exec "$swlog" 2>&1)"
    rm -f "$H/.local/bin/fzf" "$H/fzf.calls" "$H/fzf.in."* "$H/fzf.args."* "$journal/undo" "$journal/recent" "$swlog"
    # a palette picked inside the panel: the next list is drawn with the new palette's shades (the settings read anew), not the ones the panel opened with
    cat > "$H/.local/bin/fzf" <<'STUB'
#!/bin/sh
case $1 in --version) echo 0.60.3; exit 0 ;; esac
n=$(cat "$HOME/fzf.calls" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$HOME/fzf.calls"
cat > "$HOME/fzf.in.$n"; printf '%s\n' "$*" > "$HOME/fzf.args.$n"
if [ "$n" -eq 1 ]; then printf '\n  theme      nord\ttheme nord\n'; exit 0; else exit 130; fi
STUB
    chmod +x "$H/.local/bin/fzf"; rm -f "$H/fzf.calls" "$H/fzf.in."* "$H/fzf.args."* "$journal/undo" "$journal/recent"
    st=0; out=$(SPARK_SHELL_TEST_TTY=1 sh "$SH" panel 2>&1 </dev/null) || st=$?
    plain=$(printf '%s\n' "$out" | sed "s/$(printf '\033')\[[0-9;]*m//g")
    [ "$st" -eq 0 ] && [ "$(cat "$H/fzf.calls")" = 2 ] && sed "s/$(printf '\033')\[[0-9;]*m//g" "$H/fzf.in.2" | grep -q "$TICK theme nord" && grep -q '^THEME=nord$' "$HOME/.config/spark-shell/config" && grep -q 'bg+:#4c525e,hl:#88c0d0' "$H/fzf.args.2" && ! grep -q 'bg+:#4c525e' "$H/fzf.args.1" && grep -q "undo.*theme none	undo all$" "$H/fzf.in.2" \
        && ok "the window: a palette picked is read anew -- the next list is lit and marked in nord's shades (bg+ a fifth of the way to the text, hl the accent), the undo row goes back to none" || bad "window theme reload" "st=$st calls=$(cat "$H/fzf.calls" 2>&1) a1=$(grep -o 'color=[^ ]*' "$H/fzf.args.1" 2>&1) a2=$(grep -o 'color=[^ ]*' "$H/fzf.args.2" 2>&1) out=$(printf '%s' "$plain" | tr '\n' '|' | tail -c 200)"
    sh "$SH" theme none >/dev/null 2>&1 || true; printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"   # as before the pick
    rm -f "$H/.local/bin/fzf" "$H/fzf.calls" "$H/fzf.in."* "$H/fzf.args."* "$journal/undo" "$journal/recent"
    # a window fullscreen on the workspace steps aside for the panel, which is focused over it; Esc puts it back. The panel's parent pid is written for the stub's tree
    cat > "$H/.local/bin/fzf" <<'STUB'
#!/bin/sh
case $1 in --version) echo 0.60.3; exit 0 ;; esac
n=$(cat "$HOME/fzf.calls" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$HOME/fzf.calls"
cat > "$HOME/fzf.in.$n"; printf '%s\n' "$*" > "$HOME/fzf.args.$n"
if [ "$n" -eq 1 ]; then printf '\n  out        mute\tout mute\n'; exit 0; else exit 130; fi
STUB
    chmod +x "$H/.local/bin/fzf"; : > "$H/fullscreen"; rm -f "$H/fzf.calls" "$H/fzf.in."* "$H/fzf.args."* "$journal/undo" "$journal/recent" "$swlog" "$amlog"
    mkdir -p "$H/ft"; ln -sf "$(command -v sh)" "$H/ft/foot"   # the panel's parent must be a foot: a shell by that name stands in, and writes its pid for the stub's tree
    out=$(SWAYSOCK=/tmp/x SPARK_SHELL_TEST_TTY=1 "$H/ft/foot" -c 'echo $$ > "$HOME/panel.ppid"; sh "$1" panel 2>&1 </dev/null; echo "exit $?"' foot "$SH"); st=${out##*exit }
    [ "$st" = 0 ] && [ "$(cat "$H/fzf.calls")" = 2 ] && [ "$(grep 'fullscreen\|focus' "$swlog" | tr '\n' '|')" = '[con_id=77] fullscreen disable|[app_id=spark-dialog] focus|[con_id=77] fullscreen enable|' ] && grep -qx -- '-c 0 sset Master mute' "$amlog" \
        && ok "the window under a fullscreen one: the window steps aside and the panel is focused over it; after the pick and Esc it is fullscreen again" || bad "window fullscreen" "st=$st calls=$(cat "$H/fzf.calls" 2>&1) sway=$(tr '\n' '|' < "$swlog" 2>&1) out=$(printf '%s' "$out" | tr -d '\033' | tr '\n' '|' | tail -c 200)"
    cat > "$H/.local/bin/fzf" <<'STUB'
#!/bin/sh
case $1 in --version) echo 0.60.3; exit 0 ;; esac
n=$(cat "$HOME/fzf.calls" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$HOME/fzf.calls"
cat > "$HOME/fzf.in.$n"; printf '%s\n' "$*" > "$HOME/fzf.args.$n"
if [ "$n" -eq 1 ]; then printf '\n  apps       firefox\tapps open firefox\n'; exit 0; else exit 130; fi
STUB
    chmod +x "$H/.local/bin/fzf"; rm -f "$H/fzf.calls" "$H/fzf.in."* "$H/fzf.args."* "$journal/undo" "$journal/recent" "$swlog"
    out=$(SWAYSOCK=/tmp/x SPARK_SHELL_TEST_TTY=1 "$H/ft/foot" -c 'echo $$ > "$HOME/panel.ppid"; sh "$1" panel 2>&1 </dev/null; echo "exit $?"' foot "$SH"); st=${out##*exit }
    [ "$st" = 0 ] && [ "$(cat "$H/fzf.calls")" = 1 ] && grep -q '^\[con_id=77\] fullscreen disable$' "$swlog" && grep -q '^exec firefox' "$swlog" && ! grep -q 'fullscreen enable' "$swlog" \
        && ok "the window under a fullscreen one, an app picked: the panel closes and the window stays as it is, the app has the screen" || bad "window fullscreen app" "st=$st calls=$(cat "$H/fzf.calls" 2>&1) sway=$(tr '\n' '|' < "$swlog" 2>&1)"
    rm -rf "$H/fullscreen" "$H/panel.ppid" "$H/ft" "$H/.local/bin/fzf" "$H/fzf.calls" "$H/fzf.in."* "$H/fzf.args."* "$journal/undo" "$journal/recent" "$swlog"
    rm -f "$H/.local/bin/spark"
    rm -f "$H/.local/bin/amixer" "$P/asound/cards"
    out=$(sh "$SH" check || true); printf '%s\n' "$out" | grep -q '^warn   sound        no audio system found, so no out or mic block -- spark-shell on desktop$' \
        && ok "check: no audio system is a warn with the package to install, never a FAIL" || bad "check sound warn" "$out"
    printf 'DESKTOP_BAR=maybe\n' > "$HOME/.config/spark-shell/config"
    sh "$SH" status >/dev/null 2>&1 && bad "DESKTOP_BAR=maybe accepted" || ok "config: DESKTOP_BAR=maybe is refused"
    printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"
    st=0; out=$(PATH=$H/.local/bin:$sys sh "$SH" bar sideways 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = 'spark-shell panel: spark is not installed -- spark reads what you want (github.com/forgewright-ai/spark)' ] && ok "bar WORDS without spark: refused in one line" || bad "bar want no spark" "st=$st $out"
    # off takes the ALSA file spark-shell wrote, never one of yours
    printf '# rendered by spark-shell (bar): the sound card for programs started from now -- spark-shell off removes it\ndefaults.pcm.!card HDMI\ndefaults.ctl.!card HDMI\n' > "$H/.config/alsa/asoundrc"
    sh "$SH" off >/dev/null
    [ ! -e "$H/.config/alsa/asoundrc" ] && ok "off: the asoundrc spark-shell wrote is removed" || bad "off asoundrc"
    mkdir -p "$H/.config/alsa"; printf 'pcm.!default { type hw card 1 }\n' > "$H/.config/alsa/asoundrc"
    sh "$SH" off >/dev/null
    [ "$(cat "$H/.config/alsa/asoundrc")" = 'pcm.!default { type hw card 1 }' ] && ok "off: an asoundrc of yours stays" || bad "off asoundrc yours"
fi
unset SPARK_SHELL_SYS SPARK_SHELL_PROC SWAYSOCK

# --- 21. the providers: a section as an MCP server, the want verb, the dialog's keys
# `spark-shell provide SECTION` driven on a pipe by a scripted client:
# each request a jq line, every line out parsed. The Linux half reads
# the bar's fixture (wpa_cli, bluetoothctl, amixer stubs).
fresh
desktop_stubs
desk_stubs
bar_fixture
theme_fixture '#ff5555'
mkdir -p "$HOME/.config/spark-shell"; printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"
rq() { jq -cn --argjson i "$1" --arg m "$2" --argjson p "${3:-null}" '{jsonrpc: "2.0", id: $i, method: $m} + (if $p == null then {} else {params: $p} end)'; }   # rq ID METHOD [PARAMS] -> one request
call() { rq "$1" tools/call "$(jq -cn --arg n "$2" --argjson a "${3:-{\}}" '{name: $n, arguments: $a}')"; }   # call ID TOOL [ARGUMENTS]
mcp() { _s=$1; shift; printf '%s\n' "$@" | sh "$SH" provide "$_s" > "$H/mcp.out" 2> "$H/mcp.err"; }   # mcp SECTION LINE... -> $H/mcp.out, its stderr apart
ans() { jq -c --argjson i "$1" 'select(.id == $i)' "$H/mcp.out"; }   # ans ID -> that answer
init=$(rq 1 initialize '{"protocolVersion":"2025-06-18","capabilities":{"elicitation":{}},"clientInfo":{"name":"test","version":"0"}}')
mcp theme "$init" '{"jsonrpc":"2.0","method":"notifications/initialized"}' "$(rq 2 tools/list)" "$(rq 3 ping)"
st=$?; [ "$st" -eq 0 ] && [ "$(ans 1 | jq -r '.result.protocolVersion + " " + .result.serverInfo.name')" = '2025-06-18 theme' ] && ans 1 | jq -e '.result.capabilities == {tools: {listChanged: true}, resources: {subscribe: true, listChanged: true}, logging: {}}' >/dev/null \
    && [ "$(grep -c '' "$H/mcp.out")" = 3 ] && [ "$(ans 3 | jq -c .result)" = '{}' ] \
    && ok "provide: initialize answers 2025-06-18, the section as the server's name, tools, resources with subscribe, logging; a notification gets no answer; ping is {}" || bad "provide initialize" "st=$st $(cat "$H/mcp.out" "$H/mcp.err")"
ans 1 | jq -e '.result.serverInfo.title | test("^none")' >/dev/null && ok "provide: the server's title is the context title, the panel's title line (the palette in use)" || bad "provide title" "$(ans 1)"
jq -e -s 'all(.[]; .jsonrpc == "2.0")' "$H/mcp.out" >/dev/null && ok "provide: every line on stdout is a JSON-RPC 2.0 message, nothing else" || bad "provide stdout" "$(cat "$H/mcp.out")"
long=$(awk 'BEGIN { s = "{\"jsonrpc\":\"2.0\",\"id\":9,\"method\":\"ping\",\"params\":{\"x\":\""; while (length(s) < 70000) s = s "aaaaaaaaaa"; print s "\"}}" }')
mcp theme 'not json' '[1,2]' '{"jsonrpc":"2.0","id":null,"method":"ping"}' '{"jsonrpc":"1.0","id":4,"method":"ping"}' "$(rq 5 prompts/list)" "$long" "$(rq 6 ping)"
[ "$(jq -r -s 'map(.error.code // "ok") | map(tostring) | join(" ")' "$H/mcp.out")" = '-32700 -32600 -32600 -32600 -32601 -32600 ok' ] && [ "$(ans 6 | jq -c .result)" = '{}' ] \
    && ok "provide: bad JSON -32700, an array, a null id, the wrong jsonrpc and a line over 64 kB -32600, a method it lacks -32601; the server goes on" || bad "provide errors" "$(cat "$H/mcp.out")"
# the shipped wallpapers: each name in WALL_SHIPPED has its SVG source and a PNG of 3840 by 2160 in wallpaper/, and nothing else is there
_wb=''
for n in $(sed -n 's/^WALL_SHIPPED="\(.*\)"$/\1/p' "$SH" | tr ' ' '\n' | cut -d: -f1); do
    [ -f "$REPO/wallpaper/$n.svg" ] && [ -f "$REPO/wallpaper/$n.png" ] && [ "$(od -An -tu1 -j16 -N8 "$REPO/wallpaper/$n.png" | tr -s ' \n' ' ' | sed 's/^ //; s/ $//')" = '0 0 15 0 0 0 8 112' ] || _wb="$_wb $n"
done
[ -z "$_wb" ] && [ "$(ls "$REPO/wallpaper" | wc -l | tr -d ' ')" = 20 ] && ok "wallpaper/: the ten shipped wallpapers, each its SVG and a 3840 by 2160 PNG, nothing else" || bad "wallpaper files" "$_wb $(ls "$REPO/wallpaper")"
# every tool of every section: one name shape, one title shape, the hints spelled out, the destructive and read-only ones named
: > "$H/tools.all"
for s in lan wifi bt out mic bat clock theme wallpaper window bar layout apps about undo files; do mcp "$s" "$(rq 1 tools/list)"; ans 1 | jq -c '.result.tools[]' >> "$H/tools.all"; done
[ "$(grep -c '' "$H/tools.all")" = 41 ] && [ "$(jq -r .name "$H/tools.all" | sort | paste -sd ' ' -)" = "$(sed -n 's/^PROVIDE_TOOLS="\(.*\)"$/\1/p' "$SH" | tr ' ' '\n' | sort | paste -sd ' ' -)" ] \
    && ok "provide: the sixteen sections hold the 41 tools of PROVIDE_TOOLS, each once" || bad "provide tool count" "$(jq -r .name "$H/tools.all" | paste -sd ' ' -)"
# the rows carry the section's state, the dialog's subtitle, read again with every rows read
mcp theme "$(rq 1 initialize '{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"t","version":"0"}}')" "$(rq 2 resources/read '{"uri":"spark-shell://theme/rows"}')"
ans 2 | jq -r '.result.contents[0].text' | jq -e '.title == "theme" and (.state | type == "string" and length > 0)' >/dev/null \
    && ok "provide: a rows read carries the section's state beside its title, so a subtitle follows each step" || bad "rows state" "$(ans 2 | head -c 300)"
# the wallpaper's picture: a path, no row of it (the dialog's pick), so its own gate: under home, no link, nothing hidden, a picture's type
mkdir -p "$H/Pictures" "$H/.hid"; printf 'x' > "$H/Pictures/sea.png"; printf 'x' > "$H/.hid/sea.png"; printf 'x' > "$H/Pictures/sea.txt"; PH=$(realpath "$H")
mcp wallpaper "$(rq 1 initialize '{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"t","version":"0"}}')" \
    "$(call 2 wallpaper_picture "$(jq -cn --arg p "$PH/.hid/sea.png" '{path: $p}')")" "$(call 3 wallpaper_picture "$(jq -cn --arg p "$PH/Pictures/sea.txt" '{path: $p}')")" "$(call 4 wallpaper_picture '{"path":"/etc/hosts"}')"
[ "$(ans 2 | jq -r '.result.content[0].text')" = 'wallpaper: a hidden file is not offered' ] && [ "$(ans 3 | jq -r '.result.content[0].text')" = 'wallpaper: a picture is jpg jpeg png webp' ] && [ "$(ans 4 | jq -r '.result.content[0].text')" = 'wallpaper: a picture comes from under your home' ] \
    && ok "provide wallpaper_picture: a path no row holds, held to its own gate: a hidden file, a type that is no picture, a path outside home refused" || bad "wallpaper picture gate" "$(cat "$H/mcp.out")"
jq -e -s 'all(.[]; (.name | test("^[a-z][a-z0-9_]{0,63}$")) and (.title | test("^[a-z][a-z-]*( [a-z-]+| [A-Z]+)*$")) and (.title | length) <= 60)' "$H/tools.all" >/dev/null \
    && ok "provide: every tool name is lower case with underscores, every title a sentence of plain words with its argument in capitals, 60 at most" || bad "tool shapes" "$(jq -r '.name + " | " + .title' "$H/tools.all")"
jq -e -s 'all(.[]; .annotations | (.readOnlyHint | type) == "boolean" and (.destructiveHint | type) == "boolean" and (.idempotentHint | type) == "boolean" and .openWorldHint == false)' "$H/tools.all" >/dev/null \
    && [ "$(jq -r 'select(.annotations.destructiveHint) | .name' "$H/tools.all" | sort | paste -sd ' ' -)" = 'layout_save wifi_forget window_close' ] \
    && [ "$(jq -r 'select(.annotations.readOnlyHint) | .name' "$H/tools.all" | paste -sd ' ' -)" = 'about_open files_show files_attach' ] \
    && ok "provide: every hint spelled out (the spec's default is destructive); destructive: wifi forget, window close, layout save; read only: about" || bad "tool hints" "$(jq -c '[.name, .annotations]' "$H/tools.all")"
jq -e -s 'all(.[]; .inputSchema.type == "object" and .inputSchema.additionalProperties == false and .outputSchema.type == "object")' "$H/tools.all" >/dev/null \
    && [ "$(jq -c 'select(.name == "wifi_connect") | .inputSchema.properties.password' "$H/tools.all")" = '{"type":"string","format":"password","maxLength":256}' ] \
    && [ "$(jq -c 'select(.name == "bt_power") | .inputSchema.properties.state.enum' "$H/tools.all")" = '["on","off"]' ] && [ "$(jq -c 'select(.name == "out_level") | .inputSchema.properties.level' "$H/tools.all")" = '{"type":"integer","minimum":0,"maximum":100}' ] \
    && ok "provide: every input schema closed (no other argument), a password a masked string, a closed set an enum, a level 0 to 100" || bad "tool schemas" "$(jq -c '[.name, .inputSchema]' "$H/tools.all" | head -5)"
# the rows resource, a call, its undo, the refusals
mcp theme "$(rq 1 resources/list)" "$(rq 2 resources/read '{"uri":"spark-shell://theme/rows"}')" "$(rq 3 resources/read '{"uri":"spark-shell://wifi/rows"}')"
ans 2 | jq -r '.result.contents[0].text' > "$H/rows.json"
[ "$(ans 1 | jq -c '.result.resources[0] | [.uri, .mimeType]')" = '["spark-shell://theme/rows","application/json"]' ] && [ "$(ans 3 | jq -r .error.code)" = -32002 ] \
    && jq -e '.title == "theme" and (.rows[] | select(.id == "theme:show:none") | .sign == "check" and .tool == null) and (.rows[] | select(.id == "theme:dracula") | .tool == {name: "theme_palette", arguments: {name: "dracula"}})' "$H/rows.json" >/dev/null \
    && jq -e '.short == ["theme:more"] and (.rows[] | select(.id == "theme:more") | .children == "spark-shell://theme/rows" and .tool == null)' "$H/rows.json" >/dev/null \
    && ok "provide: the rows resource: the palette in use a check with no tool, every other a row whose tool takes it by name; the short form the one row that opens the section" || bad "provide rows" "$(cat "$H/rows.json" | head -c 600)"
mcp theme "$(call 1 theme_palette '{"name":"nord"}')" "$(call 2 theme_palette '{"name":"nowhere"}')" "$(call 3 theme_font '{"size":"huge"}')" "$(call 4 theme_alpha '{"value":0.9,"x":1}')" "$(call 5 wifi_connect '{"name":"home"}')" "$(call 6 'Theme_Font')" "$(call 7 theme_alpha '{"value":2}')"
[ "$(ans 1 | jq -c .result.structuredContent)" = '{"receipt":"theme nord","undo":{"name":"theme_palette","arguments":{"name":"none"}}}' ] && ans 1 | jq -e '.result.isError == false and (.result.content[0].text | fromjson) == .result.structuredContent' >/dev/null && grep -q '^THEME=nord$' "$HOME/.config/spark-shell/config" \
    && ok "provide tools/call: the palette set, the receipt in the present tense, the undo the step that takes it back, the same JSON in a text block" || bad "provide call" "$(ans 1) $(cat "$H/mcp.err")"
[ "$(ans 2 | jq -c .result)" = '{"content":[{"type":"text","text":"theme: nowhere is not on the panel now"}],"isError":true}' ] && [ "$(ans 3 | jq -r .error.message)" = 'theme_font: size is one of bigger, smaller' ] && [ "$(ans 4 | jq -r .error.message)" = 'theme_alpha: no argument x' ] \
    && [ "$(ans 5 | jq -r .error.message)" = 'no tool wifi_connect in theme' ] && [ "$(ans 6 | jq -r .error.code)" = -32602 ] && [ "$(ans 7 | jq -r .error.message)" = 'theme_alpha: value is a number, 0 to 1' ] \
    && ok "provide: a step no row offers is refused in the result, one sentence; an argument outside its schema, an argument it lacks, another section's tool and a name of another shape are -32602" || bad "provide refusals" "$(cat "$H/mcp.out")"
mcp theme "$(call 1 theme_palette '{"name":"none"}')"; grep -q '^THEME=none$' "$HOME/.config/spark-shell/config" && ok "provide: the undo, called as a tool, puts the palette back" || bad "provide undo" "$(cat "$H/mcp.out")"
# subscribe: an updated notification after a step, and from the watcher when the rows change under it
{ rq 1 resources/subscribe '{"uri":"spark-shell://theme/rows"}'; rq 2 tools/call '{"name":"theme_transparency","arguments":{"amount":"more"},"_meta":{"progressToken":"p1"}}'
  sleep 2; printf 'THEME=dracula\n' >> "$HOME/.config/spark-shell/config"; sleep 3; rq 3 resources/unsubscribe '{"uri":"spark-shell://theme/rows"}'; } \
    | SPARK_SHELL_PROVIDE_POLL=1 sh "$SH" provide theme > "$H/mcp.out" 2> "$H/mcp.err"
order=$(jq -r 'if .id then "r" + (.id | tostring) else .method end' "$H/mcp.out" | uniq | paste -sd ' ' -)
case $order in "r1 notifications/progress r2 notifications/resources/updated r3") ok "provide: progress against the token while a step runs, then its result, then the rows updated (after the step, and from the watcher), unsubscribed" ;;
    *) bad "provide subscribe" "$order $(cat "$H/mcp.err")" ;; esac
[ "$(jq -s '[.[] | select(.method == "notifications/resources/updated")] | length' "$H/mcp.out")" -ge 2 ] && jq -e -s '[.[] | select(.method == "notifications/progress") | .params.progress] | . == (sort | unique)' "$H/mcp.out" >/dev/null \
    && ok "provide: the watcher saw the palette change made outside it; progress only grows" || bad "provide watcher" "$(cat "$H/mcp.out")"
printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"
st=0; out=$(sh "$SH" provide spark 2>&1 >/dev/null) || st=$?
[ "$st" -eq 1 ] && [ "$out" = 'spark-shell provide: spark is not one: lan, wifi, bt, out, mic, bat, clock, theme, wallpaper, window, bar, layout, apps, about, undo, files' ] && ok "provide spark: no provider (the dialog holds the chat itself), the list on stderr, exit 1" || bad "provide spark" "st=$st $out"
st=0; out=$(sh "$SH" provide theme wifi 2>&1 >/dev/null) || st=$?
[ "$st" -eq 1 ] && printf '%s\n' "$out" | grep -q '^spark-shell provide: one section: lan, ' && ok "provide with two words: one section, refused on stderr" || bad "provide two" "st=$st $out"
# the files provider: the host's roots, a folder's rows, three read-only tools held to four lines
F=$H/files; mkdir -p "$F/docs/deep/x" "$F/.secret"; printf 'hello\nworld\n' > "$F/notes.md"; printf 'x\000y' > "$F/blob.txt"; printf 'p' > "$F/pic.png"
ln -s /etc "$F/etc-link"; printf 'k' > "$F/.secret/key"; mkfifo "$F/pipe"; printf 'a\n' > "$F/docs/a.txt"
FR=$(realpath "$F"); uri() { printf 'spark-shell://files/rows/%s' "$(printf '%s' "$1" | base64 | tr -d '\n=' | tr '+/' '-_')"; }
rinit=$(rq 1 initialize '{"protocolVersion":"2025-06-18","capabilities":{"roots":{}},"clientInfo":{"name":"test","version":"0"}}')
roots=$(jq -cn --arg u "file://$FR" '{jsonrpc: "2.0", id: "roots", result: {roots: [{uri: $u}, {uri: "file:///"}]}}')
fcall() { call "$1" "$2" "$(jq -cn --arg p "$3" '{path: $p}')"; }
mcp files "$rinit" '{"jsonrpc":"2.0","method":"notifications/initialized"}' "$roots" "$(rq 2 resources/read '{"uri":"spark-shell://files/rows"}')" \
    "$(rq 3 resources/read "$(jq -cn --arg u "$(uri "$FR")" '{uri: $u}')")" \
    "$(fcall 4 files_show "$FR/notes.md")" "$(fcall 5 files_attach "$FR/notes.md")" "$(fcall 6 files_show "$FR/.secret/key")" "$(fcall 7 files_show "$FR/blob.txt")" \
    "$(fcall 8 files_show "$FR/etc-link/hosts")" "$(fcall 9 files_show /etc/hosts)" "$(fcall 10 files_attach "$FR/pic.png")" \
    "$(rq 11 resources/read "$(jq -cn --arg u "$(uri "$FR/.secret")" '{uri: $u}')")" "$(rq 12 resources/read "$(jq -cn --arg u "$(uri /)" '{uri: $u}')")" \
    "$(rq 13 resources/read "$(jq -cn --arg u "$(uri "$FR/docs")" '{uri: $u}')")" \
    "$(rq 14 resources/read "$(jq -cn --arg u "$(uri "$FR/docs/deep")" '{uri: $u}')")" "$(rq 15 resources/read "$(jq -cn --arg u "$(uri "$FR/docs/deep/x")" '{uri: $u}')")"
[ "$(jq -c 'select(.method == "roots/list") | .id' "$H/mcp.out")" = '"roots"' ] && ok "provide files: a host that has roots is asked for them once initialized" || bad "files roots ask" "$(cat "$H/mcp.out" | head -3)"
ans 2 | jq -r '.result.contents[0].text' | jq -e --arg u "$(uri "$FR")" '.rows | length == 1 and .[0].children == $u and .[0].sign == "opens"' >/dev/null \
    && ok "provide files: the roots are the rows at the top, each opening its folder; / is never a root" || bad "files root rows" "$(ans 2)"
ans 3 | jq -r '.result.contents[0].text' > "$H/folder.json"
[ "$(jq -r '[.rows[] | .text] | join("|")' "$H/folder.json")" = "docs|blob.txt|notes.md|pic.png|etc-link -> /etc|3 files $(printf '\302\267') 16 B" ] \
    && jq -e '(.rows[] | select(.text == "docs") | .children != null and .columns == ["2 items"]) and (.rows[] | select(.text == "notes.md") | .tool.name == "files_open" and .columns[0] == "12 B" and ([.more[].name] == ["files_show", "files_attach"])) and (.rows[] | select(.text | startswith("etc-link")) | .tool == null and .children == null)' "$H/folder.json" >/dev/null \
    && ok "provide files: a folder lists its folders, then its files with the size and the date; a link is shown and never followed; a hidden file and a pipe are not listed" || bad "files folder" "$(jq -c '.rows[] | [.text, .columns, .tool.name]' "$H/folder.json")"
[ "$(ans 4 | jq -r .result.structuredContent.receipt)" = "$(printf 'notes.md\nhello\nworld')" ] && [ "$(ans 5 | jq -r .result.structuredContent.attach)" = "$FR/notes.md" ] \
    && ok "provide files: show gives a text file's first lines; attach gives its path for the next want" || bad "files show attach" "$(ans 4) $(ans 5)"
for i in 6 8 9; do [ "$(ans $i | jq -r '.result.content[0].text')" = 'files: that is not a file in the folders given' ] || bad "files refusal $i" "$(ans $i)"; done
[ "$(ans 7 | jq -r '.result.content[0].text')" = 'files: blob.txt is not text' ] && [ "$(ans 10 | jq -r '.result.content[0].text')" = 'files: pic.png is not a type plus attaches (txt md)' ] \
    && [ "$(ans 11 | jq -r .error.code)" = -32002 ] && [ "$(ans 12 | jq -r .error.code)" = -32002 ] \
    && ok "provide files: a hidden file, a path through a link and a file outside the roots are refused; a binary and a type plus does not take too; a hidden folder and / are no resource" || bad "files refusals" "$(ans 7) $(ans 10) $(ans 11) $(ans 12)"
ans 13 | jq -r '.result.contents[0].text' | jq -e --arg u "$(uri "$FR")" '.rows[0].text == ".." and .rows[0].children == $u and (.rows[] | select(.text == "deep") | .children != null)' >/dev/null \
    && ok "provide files: a folder under a root opens with .. back to its parent" || bad "files up" "$(ans 13 | head -c 300)"
[ "$(ans 14 | jq -r '.result.contents[0].text' | jq -r '.rows[-1].text')" = '1 folder' ] && [ "$(ans 15 | jq -r '.result.contents[0].text' | jq -r '[.rows[].text] | join("|")')" = '..|empty' ] \
    && ok "provide files: a folder of folders counts its folders, and an empty folder says empty" || bad "files totals" "$(ans 14 | head -c 300) $(ans 15 | head -c 300)"
mcp files "$(rq 1 initialize '{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"0"}}')" '{"jsonrpc":"2.0","method":"notifications/initialized"}' "$(rq 2 resources/read '{"uri":"spark-shell://files/rows"}')" "$(fcall 3 files_show "$FR/notes.md")"
! grep -q roots/list "$H/mcp.out" && [ "$(ans 2 | jq -r '.result.contents[0].text' | jq -c .rows)" = '[]' ] && [ "$(ans 3 | jq -r '.result.content[0].text')" = 'files: that is not a file in the folders given' ] \
    && ok "provide files: a host with no roots is never asked, and no file is reachable" || bad "files no roots" "$(cat "$H/mcp.out")"
# the dialog's keys
for kv in DIALOG_ATTACH=maybe DIALOG_MODEL=1 DIALOG_TALK=off 'DIALOG_ATTACH_TYPES=.exe' 'DIALOG_ATTACH_TYPES=TXT'; do
    printf 'DESKTOP=sway\n%s\n' "$kv" > "$HOME/.config/spark-shell/config"; st=0; out=$(sh "$SH" status 2>&1) || st=$?
    [ "$st" -eq 1 ] && printf '%s\n' "$out" | grep -q "^spark-shell: ${kv%%=*}=" || bad "key $kv refused" "st=$st $out"
done
ok "config: DIALOG_ATTACH, DIALOG_MODEL and DIALOG_TALK take yes or no, DIALOG_ATTACH_TYPES lower-case types; anything else is refused in one line"
printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"
grep -q "^CONFIG_UNSET=.* -u DIALOG_ATTACH -u DIALOG_ATTACH_TYPES -u DIALOG_MODEL -u DIALOG_TALK'" "$SH" && grep -q '^DIALOG_ATTACH=yes$' "$REPO/config.example" && grep -q '^DIALOG_ATTACH_TYPES=txt md$' "$REPO/config.example" && grep -q '^DIALOG_MODEL=yes$' "$REPO/config.example" && grep -q '^DIALOG_TALK=yes$' "$REPO/config.example" \
    && ok "config: the four keys are unset for what spark-shell starts, and config.example shows their defaults" || bad "dialog keys" "$(grep -n DIALOG "$REPO/config.example")"
# the want verb: one entry for words, the plan as JSON, a file asked about
cat > "$H/.local/bin/spark" <<'STUB'
#!/bin/sh
printf '%s\n' "$@" > "$HOME/spark.argv"; cat > "$HOME/spark.stdin"
case "$*" in
    *--source*) echo 'the notes say to buy bread.' ;;
    *) printf '{"why": "a palette", "steps": [{"page": "theme", "action": "nord"}, {"page": "theme", "action": "rainbow"}, {"page": "out", "action": "level", "arg": "30"}]}\n' ;;
esac
STUB
chmod +x "$H/.local/bin/spark"
st=0; out=$(sh "$SH" want --json the nord palette and quieter 2>&1) || st=$?
[ "$st" -eq 0 ] && printf '%s' "$out" | jq -e --arg c "$(printf '\342\234\227')" '.answer == "" and .steps[0] == {name: "theme_palette", arguments: {name: "nord"}, line: "theme nord"} and .refused[0] == ($c + " theme: rainbow is not on the panel now")' >/dev/null \
    && ! grep -q '^THEME=nord' "$HOME/.config/spark-shell/config" && grep -q '^do this on the desktop: the nord palette and quieter$' "$HOME/spark.argv" \
    && ok "want --json: the steps spark picked, each gated and named as a tool with its arguments and its line, the refused ones as lines; nothing run" || bad "want json" "st=$st $out"
if [ "$(uname -s)" != Darwin ]; then
    printf '%s' "$out" | jq -e '.steps[1] == {name: "out_level", arguments: {level: 30}, line: "out level 30"}' >/dev/null && ok "want --json: a level is a number in the arguments, as the tool's schema says" || bad "want json level" "$out"
fi
st=0; out=$(sh "$SH" want the nord palette 2>&1) || st=$?
[ "$st" -eq 0 ] && printf '%s\n' "$out" | grep -q "^$(printf '\342\234\223') theme nord$" && grep -q '^THEME=nord$' "$HOME/.config/spark-shell/config" \
    && ok "want WORDS: the same steps run, one line each with its sign, as the panel's prompt does" || bad "want run" "st=$st $out"
# spark 1.90's planner (issue 7): the desktop's tools on stdin, the names each tool takes now as the about; each step mapped back and gated here
cat > "$H/.local/bin/spark" <<'STUB'
#!/bin/sh
case $1 in
    help) echo ' spark steps <words> < TOOLS  the tool calls that do what you say (-h)' ;;
    steps) printf '%s\n' "$@" > "$HOME/spark.argv"; cat > "$HOME/spark.stdin"
        case "$*" in
            *'what time'*) printf '{"answer": "It is noon.", "steps": [], "refused": []}\n' ;;
            *zebra*|*sandwich*) printf '{"answer": "", "steps": [], "refused": []}\n' ;;
            *) printf '{"answer": "", "steps": [{"name": "theme_palette", "arguments": {"name": "dracula"}}, {"name": "out_level", "arguments": {"level": 30}}, {"name": "theme_palette", "arguments": {"name": "rainbow"}}, {"name": "rm_rf", "arguments": {}}], "refused": ["out_use: no argument loud"]}\n' ;;
        esac ;;
    *) printf '%s\n' "$@" > "$HOME/spark.argv"; cat > "$HOME/spark.stdin"; case "$*" in *--source*) echo 'the notes say to buy bread.' ;; *) echo '{"steps": []}' ;; esac ;;
esac
STUB
chmod +x "$H/.local/bin/spark"
st=0; out=$(sh "$SH" want --json the nord palette and quieter 2>&1) || st=$?
x=$(printf '\342\234\227')
[ "$st" -eq 0 ] && printf '%s' "$out" | jq -e --arg x "$x" '.steps[0] == {name: "theme_palette", arguments: {name: "dracula"}, line: "theme dracula"} and (.refused | index($x + " out_use: no argument loud") != null and index($x + " theme: rainbow is not on the panel now") != null and index($x + " rm_rf is not a step the panel takes") != null)' >/dev/null \
    && [ "$(sed -n 1p "$HOME/spark.argv")" = steps ] && [ "$(sed -n 2p "$HOME/spark.argv")" = --about ] && sed -n 3p "$HOME/spark.argv" | grep -q 'The names each tool takes now -- .*out_use: HDMI.*whole and exactly as written here' && ! sed -n 3p "$HOME/spark.argv" | grep -q 'theme_palette:' && [ "$(sed -n '4,5p' "$HOME/spark.argv" | paste -sd ' ' -)" = '-- the nord palette and quieter' ] \
    && jq -e '[.tools[].name] as $n | ($n | index("theme_palette") != null and index("undo_all") != null and index("about_open") != null and index("files_open") == null) and (.tools[0].inputSchema.type == "object")' "$HOME/spark.stdin" >/dev/null \
    && ok "want with spark steps: the tools on stdin (the about and undo, never the files'), the names each tool takes now as the about; each step mapped back and gated, spark's refusals and the gate's as lines" || bad "want steps" "st=$st $out $(cat "$HOME/spark.argv")"
if [ "$(uname -s)" != Darwin ]; then
    printf '%s' "$out" | jq -e '.steps[1] == {name: "out_level", arguments: {level: 30}, line: "out level 30"}' >/dev/null && ok "want with spark steps: a level comes back a number" || bad "want steps level" "$out"
fi
st=0; out=$(sh "$SH" want --json what time is it 2>&1) || st=$?; st2=0; out2=$(sh "$SH" want --json zebra stripes 2>&1) || st2=$?; st3=0; out3=$(sh "$SH" want --json make me a sandwich please 2>&1) || st3=$?
[ "$st" -eq 0 ] && printf '%s' "$out" | jq -e '.answer == "It is noon." and .steps == []' >/dev/null && [ "$st2" -eq 0 ] && printf '%s' "$out2" | jq -e --arg x "$x" '.steps == [] and .refused == [$x + " no step on the panel does that"]' >/dev/null \
    && [ "$st3" -eq 0 ] && printf '%s' "$out3" | jq -e --arg x "$x" '.steps == [] and .refused == [$x + " no step on the panel does that"]' >/dev/null \
    && ok "want with spark steps: a question gets its answer; words with no step, however many, the honest line and never a layout of ours (spark picks layout_new itself)" || bad "want steps nostep" "$out | $out2 | $out3"
printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"
printf 'buy bread\n' > "$H/notes.md"; printf 'x\000y' > "$H/blob.txt"; printf 'a' > "$H/pic.png"
st=0; out=$(sh "$SH" want --attach "$H/notes.md" "what do these say" 2>&1) || st=$?
[ "$st" -eq 0 ] && [ "$out" = 'the notes say to buy bread.' ] && [ "$(cat "$HOME/spark.stdin")" = 'buy bread' ] && [ "$(paste -sd ' ' - < "$HOME/spark.argv")" = 'edit --source --name notes.md -- ? what do these say' ] \
    && ok "want --attach FILE: the file is the text on stdin of spark edit ? --source, by its name alone, never its path" || bad "want attach" "st=$st $out $(cat "$HOME/spark.argv")"
st=0; o1=$(sh "$SH" want --attach "$H/pic.png" what 2>&1) || st=$?; st2=0; o2=$(sh "$SH" want --attach "$H/blob.txt" what 2>&1) || st2=$?; st3=0; o3=$(sh "$SH" want --attach "$H/none.md" what 2>&1) || st3=$?
[ "$st" -eq 1 ] && [ "$o1" = 'pic.png is not a type plus attaches (txt md)' ] && [ "$st2" -eq 1 ] && [ "$o2" = 'blob.txt is not text: spark reads text' ] && [ "$st3" -eq 1 ] && [ "$o3" = "$H/none.md is not a file that can be read" ] \
    && ok "want --attach: a type outside DIALOG_ATTACH_TYPES, a file that is not text, a file that is not there: one line each, exit 1" || bad "want attach refusals" "$st $o1 | $st2 $o2 | $st3 $o3"
printf 'DIALOG_ATTACH=no\n' > "$HOME/.config/spark-shell/config"; st=0; out=$(sh "$SH" want --json --attach "$H/notes.md" what 2>&1) || st=$?
[ "$st" -eq 1 ] && [ "$out" = '{"answer":"","steps":[],"refused":["attaching is off (DIALOG_ATTACH=no)"]}' ] && ok "want --attach with DIALOG_ATTACH=no: refused; in JSON, as a refused line" || bad "want attach off" "st=$st $out"
printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"
st=0; out=$(sh "$SH" want 2>&1) || st=$?; st2=0; out2=$(sh "$SH" want --loud x 2>&1) || st2=$?
[ "$st" -eq 1 ] && [ "$out" = 'spark-shell want: say what you would like, as spark-shell want "mute everything"' ] && [ "$st2" -eq 1 ] && [ "$out2" = 'spark-shell want: --loud is not an option here: --attach FILE, --json, then the words' ] \
    && ok "want: no words, or an option it lacks, refused in one line" || bad "want usage" "$st $out | $st2 $out2"
if [ "$(uname -s)" != Darwin ]; then
    export SWAYSOCK=$H/sway.sock
    # wifi through the provider: a saved network connects with no password; a secured new one takes it as an argument, never kept
    mcp wifi "$(rq 3 resources/read '{"uri":"spark-shell://wifi/rows"}')" "$(call 2 wifi_forget '{"name":"nowhere"}')"
    ans 3 | jq -r '.result.contents[0].text' | jq -e '.rows[] | select(.text == "home") | .sign == "dot" and .tool == {name: "wifi_disconnect", arguments: {}}' >/dev/null \
        && ok "provide wifi rows: the network in use a dot, its tool disconnects" || bad "provide wifi rows" "$(ans 3 | head -c 400)"
    [ "$(ans 2 | jq -r '.result.content[0].text')" = 'wifi: forget nowhere is not on the panel now' ] && ok "provide wifi: forget names a saved network or nothing" || bad "provide forget" "$(ans 2)"
    rm -f "$H/.local/state/wpa.log"; mcp wifi "$(call 1 wifi_connect '{"name":"cafe","password":"s3cret-pass"}')"
    grep -q 'set_network 2 psk "s3cret-pass"' "$H/.local/state/wpa.log" && ans 1 | jq -e '.result.content[0].text | startswith("could not connect to cafe")' >/dev/null && ! grep -rq 's3cret-pass' "$H/mcp.out" "$H/mcp.err" "$H/.local/state/spark-shell" \
        && ok "provide wifi: a new secured network takes its password as the tool's argument, straight to the Wi-Fi tool (this stub cannot join it); it is in no answer, no log and no journal" || bad "provide wifi connect" "$(ans 1) $(cat "$H/.local/state/wpa.log") $(grep -rl s3cret "$H/.local/state/spark-shell" 2>&1)"
    rm -f "$H/wpa.sel" "$H/wpa.down"
    [ "$(ls -ld "$H/.local/state/spark-shell/panel" | cut -c1-10)" = drwx------ ] && ok "the panel's journal folder is yours alone (0700)" || bad "journal mode" "$(ls -ld "$H/.local/state/spark-shell/panel")"
    # the scrubber: a name in the air with an escape and a bidi control reaches no screen, no row, no brief
    esc=$(printf '\033'); rlo=$(printf '\342\200\256')
    cp "$H/.local/bin/wpa_cli" "$H/wpa_cli.keep"
    sed "s/\\\\topen\\\\n' ;;/\\\\topen\\\\n00:11:22:33:44:88\\\\t2462\\\\t-60\\\\t[ESS]\\\\tev${esc}[2Jil${rlo}x\\\\n' ;;/" "$H/wpa_cli.keep" > "$H/.local/bin/wpa_cli"; chmod +x "$H/.local/bin/wpa_cli"
    rm -f "$H/.local/state/spark-shell/panel/wifi.scan"
    sh "$SH" panel wifi --list > "$H/wifi.list"; mcp wifi "$(rq 1 resources/read '{"uri":"spark-shell://wifi/rows"}')"
    grep -q 'ev\[2Jilx' "$H/wifi.list" && ! grep -q "$esc" "$H/wifi.list" && ! grep -q "$rlo" "$H/wifi.list" && ans 1 | jq -r '.result.contents[0].text' | jq -e 'any(.rows[]; .text | startswith("ev[2Jilx")) and all(.rows[]; .text | test("[\u001b\u202e]") | not)' >/dev/null \
        && ok "scrub: a network named with an escape and a bidi control is listed without them, in the panel and in the rows" || bad "scrub" "$(cat -v "$H/wifi.list" | grep ev)"
    mv "$H/wpa_cli.keep" "$H/.local/bin/wpa_cli"; rm -f "$H/.local/state/spark-shell/panel/wifi.scan"
    # the rows the dialog reads: a secured network not saved asks its password; the window section in two groups; a save asks its name
    rm -f "$H/.local/state/spark-shell/panel/wifi.scan"
    mcp wifi "$(rq 1 resources/read '{"uri":"spark-shell://wifi/rows"}')"; ans 1 | jq -r '.result.contents[0].text' > "$H/wifi.rows"
    jq -e '(.rows[] | select(.tool.name == "wifi_connect" and .tool.arguments.name == "cafe") | .tool.ask == ["password"]) and (.rows[] | select(.tool.name == "wifi_connect" and .tool.arguments.name == "open") | .tool.ask == null)' "$H/wifi.rows" >/dev/null \
        && ok "provide wifi rows: a secured network not saved asks its password; an open one asks nothing" || bad "wifi ask" "$(jq -c '.rows[] | .tool' "$H/wifi.rows")"
    mcp window "$(rq 1 resources/read '{"uri":"spark-shell://window/rows"}')"; ans 1 | jq -r '.result.contents[0].text' > "$H/window.rows"
    jq -e '[.rows[] | .group] | unique | . - [null] | inside(["layout", "open now"]) and contains(["layout"])' "$H/window.rows" >/dev/null && jq -e 'all(.rows[] | select((.tool.name // "") | test("^window_(focus|close)$")); .group == "open now")' "$H/window.rows" >/dev/null \
        && ok "provide window rows: the open windows under open now, split, tabs and stacked under layout" || bad "window groups" "$(jq -c '.rows[] | [.id, .group]' "$H/window.rows")"
    mcp layout "$(rq 1 resources/read '{"uri":"spark-shell://layout/rows"}')"
    ans 1 | jq -r '.result.contents[0].text' | jq -e '.rows[] | select(.tool.name == "layout_save") | .tool.ask == ["name"]' >/dev/null && ok "provide layout rows: save what is open asks a name" || bad "layout ask" "$(ans 1 | head -c 300)"
    # the undo journal plays an ARG as it is: a glob in a name never expands against the folder it runs in
    mkdir -p "$H/globdir"; : > "$H/globdir/Jx"; printf 'out\tuse J*\tout J*\n' > "$H/.local/state/spark-shell/panel/undo"
    out=$(cd "$H/globdir" && sh "$SH" panel undo all 2>&1 || :)
    [ "$out" = "$(printf '\342\234\227') no output named J*" ] && ok "undo: a step's ARG with a glob is played as written, never as the files it matches" || bad "undo glob" "$out"
    unset SWAYSOCK
fi
# --- 22. the dialog: its binary from a signed tag, the verb, its rows -------
# A fixture clone of this tree: a stub spark-dialog whose sha256 the
# clone's dialog/dialog.env pins, a tag signed with a scratch key that the
# clone's allowed-signers names, the release assets in a file:// folder.
fresh
desktop_stubs
theme_fixture '#ff5555'
grep -q '^spark-shell-release namespaces="git" ssh-ed25519 [A-Za-z0-9+/=]*$' "$REPO/allowed-signers" && [ "$(grep -c '' "$REPO/allowed-signers")" = 1 ] \
    && ok "allowed-signers: one key, the release's, its principal a role and no address" || bad "allowed-signers" "$(cut -c1-60 "$REPO/allowed-signers")"
grep -q '^DIALOG_SHA256_X86_64_LINUX_MUSL=[0-9a-f]\{64\}$' "$REPO/dialog/dialog.env" && ok "dialog.env: the x86_64 build pinned by its sha256" || bad "dialog.env" "$(cat "$REPO/dialog/dialog.env")"
# the about provider: the template's key sentences, each combo a column, the splash's groups
printf '%s\n' "$(rq 1 resources/read '{"uri":"spark-shell://about/rows"}')" | sh "$SH" provide about | jq -r 'select(.id == 1) | .result.contents[0].text' > "$H/about.json"
[ "$(jq -r '[.rows[] | select(.group // "" | startswith("keys"))] | length' "$H/about.json")" = "$(sh "$SH" desktop keys | grep -c '')" ] \
    && [ "$(jq -c '.rows[0] | [.columns, .text, .group]' "$H/about.json")" = '[["Super+Return"],"opens a terminal window.","keys 1"]' ] \
    && [ "$(jq -c '.short' "$H/about.json")" = '["about:open"]' ] && jq -e '.rows[] | select(.id == "about:open") | .tool.name == "about_open"' "$H/about.json" >/dev/null \
    && ok "provide about: a row per key sentence, the combo a column, in groups; the address; the short form is the row that opens it" || bad "about rows" "$(head -c 400 "$H/about.json")"
sh "$SH" desktop keys | grep -v '^\(\(Super\|Ctrl\|Alt\|Shift\)+[^ ,]*\|Print\) [a-z]' | grep -v '^The volume\|^Typing exit' > "$H/keys.odd" || :
[ ! -s "$H/keys.odd" ] && ok "desktop keys: each sentence opens with one combo and a verb (the about's two columns)" || bad "key sentences" "$(cat "$H/keys.odd")"
if [ "$(uname -s)" = Darwin ]; then
    st=0; out=$(sh "$SH" dialog 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = 'spark-shell dialog: the dialog is the Linux desktop'"'"'s; in a terminal here, spark-shell panel' ] && ok "macOS: dialog refuses in one line, the panel named" || bad "macOS dialog" "st=$st $out"
else
    C=$H/clone; mkdir -p "$C"
    (cd "$REPO" && tar --exclude=.git --exclude=target --exclude=target2 -cf - .) | (cd "$C" && tar --no-same-owner -xf -)   # the files ours: git refuses a clone another user owns
    printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "$HOME/dialog.argv"\nexit "${DIALOG_EXIT:-0}"\n' > "$H/stub-dialog"
    sum256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }
    sha=$(sum256 "$H/stub-dialog")
    sed "s/^DIALOG_SHA256_X86_64_LINUX_MUSL=.*/DIALOG_SHA256_X86_64_LINUX_MUSL=$sha/" "$REPO/dialog/dialog.env" > "$C/dialog/dialog.env"
    ssh-keygen -q -t ed25519 -N '' -C '' -f "$H/key" >/dev/null
    printf 'spark-shell-release namespaces="git" %s\n' "$(cut -d' ' -f1,2 "$H/key.pub")" > "$C/allowed-signers"
    g() { git -C "$C" -c user.name=test -c user.email=you@example.com -c gpg.format=ssh -c "user.signingkey=$H/key" "$@"; }   # spark:allow-secret (a scratch key, made here)
    g init -q && g add -A && g commit -q -m fixture && g tag -s v9.9 -m 'spark-shell v9.9'
    mkdir -p "$H/assets/v9.9"; cp "$H/stub-dialog" "$H/assets/v9.9/spark-dialog-x86_64-linux-musl"
    mkdir -p "$HOME/.config/spark-shell"; printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"
    bin=$H/.local/share/spark-shell/spark-dialog
    st=0; out=$(SPARK_SHELL_DIALOG_URL="file://$H/assets" sh "$C/spark-shell" on --yes 2>&1) || st=$?
    printf '%s\n' "$out" | grep -q "^ok     dialog       installed for v9.9 ($bin), sha256 checked$" && [ -x "$bin" ] && [ "$(sum256 "$bin")" = "$sha" ] \
        && ok "on: the dialog fetched for the signed release tag, its sha256 the tag's own tree pins, installed" || bad "dialog install" "st=$st $(printf '%s\n' "$out" | grep dialog)"
    cp "$C/dialog/dialog.env" "$H/dialog.env.keep"; sed 's/=.*/=0000000000000000000000000000000000000000000000000000000000000000/' "$H/dialog.env.keep" > "$C/dialog/dialog.env"
    out=$(SPARK_SHELL_DIALOG_URL="file://$H/assets" sh "$C/spark-shell" on --dry-run 2>&1 || :); cp "$H/dialog.env.keep" "$C/dialog/dialog.env"
    printf '%s\n' "$out" | grep -q '^todo   dialog       this clone is past its release: the dialog comes with the next tag$' && ok "on: a dialog.env edited in the working copy is no release: the tag's own tree decides" || bad "dialog env edited" "$(printf '%s\n' "$out" | grep dialog)"
    out=$(SPARK_SHELL_DIALOG_URL="file://$H/assets" sh "$C/spark-shell" on --dry-run 2>&1 || :)
    printf '%s\n' "$out" | grep -q '^ok     dialog       ' && ok "on --dry-run: the dialog in place is ok" || bad "dialog ok" "$(printf '%s\n' "$out" | grep dialog)"
    # a file that is not the pinned one, a tag no key here signed, a tree past its release: nothing installed
    rm -f "$bin"; printf 'x' >> "$H/assets/v9.9/spark-dialog-x86_64-linux-musl"
    out=$(SPARK_SHELL_DIALOG_URL="file://$H/assets" sh "$C/spark-shell" on --yes 2>&1 || :)
    printf '%s\n' "$out" | grep -q '^todo   dialog       the spark-dialog fetched for v9.9 is not the one the tree pins: not installed$' && [ ! -e "$bin" ] \
        && ok "on: a fetched file with another sha256 is refused, nothing installed" || bad "dialog tampered" "$(printf '%s\n' "$out" | grep dialog)"
    cp "$H/stub-dialog" "$H/assets/v9.9/spark-dialog-x86_64-linux-musl"
    ssh-keygen -q -t ed25519 -N '' -C '' -f "$H/other" >/dev/null
    printf 'spark-shell-release namespaces="git" %s\n' "$(cut -d' ' -f1,2 "$H/other.pub")" > "$C/allowed-signers"
    out=$(SPARK_SHELL_DIALOG_URL="file://$H/assets" sh "$C/spark-shell" on --yes 2>&1 || :)
    printf '%s\n' "$out" | grep -q '^todo   dialog       v9.9 is not signed by a key in allowed-signers: no dialog installed$' && [ ! -e "$bin" ] \
        && ok "on: a tag no key in allowed-signers signed installs nothing" || bad "dialog unsigned" "$(printf '%s\n' "$out" | grep dialog)"
    printf 'spark-shell-release namespaces="git" %s\n' "$(cut -d' ' -f1,2 "$H/key.pub")" > "$C/allowed-signers"
    printf '\n' >> "$C/dialog/src/main.rs"; g commit -q -am 'past the tag'
    out=$(SPARK_SHELL_DIALOG_URL="file://$H/assets" sh "$C/spark-shell" on --yes 2>&1 || :)
    printf '%s\n' "$out" | grep -q '^todo   dialog       this clone is past its release: the dialog comes with the next tag$' && [ ! -e "$bin" ] \
        && ok "on: a clone whose dialog/ moved past its tag installs nothing" || bad "dialog past" "$(printf '%s\n' "$out" | grep dialog)"
    g reset -q --hard v9.9
    SPARK_SHELL_DIALOG_URL="file://$H/assets" sh "$C/spark-shell" on --yes >/dev/null 2>&1 || :
    # spark's MCP list (issue 8): each provider put on it through spark mcp add; a server of yours under one of the names stays; an older clone's line is replaced
    cat > "$H/.local/bin/spark" <<'STUB'
#!/bin/sh
f=${XDG_CONFIG_HOME:-$HOME/.config}/spark/mcp.env; mkdir -p "$(dirname "$f")"; touch "$f"
case $1 in
    help) echo ' spark mcp [NAME]               the MCP servers on the list (-h)' ;;
    mcp) echo "$*" >> "$HOME/mcp.log"; k=MCP_SERVER_$(printf '%s' "$3" | tr 'a-z' 'A-Z')
        case $2 in
            add) if grep -q "^$k=" "$f"; then echo "$3 is on the list already" >&2; exit 1; fi; n=$3; shift 3; printf '%s="%s"\n' "$k" "$*" >> "$f" ;;
            rm) grep -v "^$k=" "$f" > "$f.t" || :; mv "$f.t" "$f" ;;
        esac ;;
esac
STUB
    chmod +x "$H/.local/bin/spark"; mcpf=$HOME/.config/spark/mcp.env; mkdir -p "$HOME/.config/spark"; rm -f "$HOME/mcp.log"
    printf 'MCP_SERVER_FILES="/opt/mine/files-server"\nMCP_SERVER_WIFI="/old/clone/spark-shell provide wifi"\n' > "$mcpf"
    out=$(SPARK_SHELL_DIALOG_URL="file://$H/assets" sh "$C/spark-shell" on --yes 2>&1 || :)
    printf '%s\n' "$out" | grep -q "^ok     mcp          15 providers on spark's MCP list: the prompt line and spark do know the desktop's tools$" \
        && printf '%s\n' "$out" | grep -q "^todo   mcp          already on spark's MCP list as servers of yours, left as they are: files$" \
        && grep -qx 'MCP_SERVER_FILES="/opt/mine/files-server"' "$mcpf" && grep -qx "MCP_SERVER_WIFI=\"$C/spark-shell provide wifi\"" "$mcpf" && grep -qx "MCP_SERVER_CLOCK=\"$C/spark-shell provide clock\"" "$mcpf" \
        && [ "$(grep -c '^MCP_SERVER_' "$mcpf")" = 16 ] && grep -qx 'mcp rm wifi' "$HOME/mcp.log" && ! grep -q 'mcp add files' "$HOME/mcp.log" \
        && ok "on desktop: each provider on spark's MCP list through spark mcp add; a server of yours under one of the names stays; an older clone's line replaced" || bad "mcp add" "$(printf '%s\n' "$out" | grep mcp); $(cat "$mcpf")"
    rm -f "$HOME/mcp.log"; SPARK_SHELL_DIALOG_URL="file://$H/assets" sh "$C/spark-shell" on --yes >/dev/null 2>&1 || :
    [ ! -e "$HOME/mcp.log" ] && sh "$C/spark-shell" check 2>&1 | grep -q "^warn   mcp          15 of 16 providers on spark's MCP list -- spark-shell on desktop$" \
        && ok "on desktop again: nothing asked of spark; check counts the providers on the list" || bad "mcp again" "$(cat "$HOME/mcp.log" 2>&1); $(sh "$C/spark-shell" check 2>&1 | grep mcp)"
    out=$(sh "$C/spark-shell" off desktop --dry-run 2>&1 || :)
    printf '%s\n' "$out" | grep -q "^would  mcp          take lan wifi bt out mic bat clock theme wallpaper window bar layout apps about undo off spark's MCP list$" \
        && ok "off desktop --dry-run: the lines that are ours, by name; a server of yours is not among them" || bad "mcp off would" "$(printf '%s\n' "$out" | grep mcp)"
    st=0; out=$(sh "$C/spark-shell" off desktop 2>&1) || st=$?
    printf '%s\n' "$out" | grep -q "^ok     mcp          15 providers off spark's MCP list$" && [ "$(cat "$mcpf")" = 'MCP_SERVER_FILES="/opt/mine/files-server"' ] \
        && ok "off desktop: spark-shell's lines off spark's MCP list through spark mcp rm, a server of yours left" || bad "mcp off" "st=$st $(printf '%s\n' "$out" | grep mcp); $(cat "$mcpf")"
    printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"; rm -f "$mcpf" "$H/.local/bin/spark"
    SPARK_SHELL_DIALOG_URL="file://$H/assets" sh "$C/spark-shell" on --yes >/dev/null 2>&1 || :
    # the verb: the providers, the home, the composer; the binary checked each time
    st=0; out=$(sh "$C/spark-shell" dialog 2>&1) || st=$?
    [ "$st" -eq 0 ] && grep -qx -- "$C/spark-shell provide layout" "$HOME/dialog.argv" && grep -qx -- "$C/spark-shell provide about" "$HOME/dialog.argv" && ! grep -q 'provide spark$\|provide undo$' "$HOME/dialog.argv" \
        && grep -qx -- --composer "$HOME/dialog.argv" && grep -qx 'plus,model,talk' "$HOME/dialog.argv" && grep -qx -- "$C/spark-shell provide files" "$HOME/dialog.argv" && grep -qx 'txt md' "$HOME/dialog.argv" && grep -qx -- "$C/spark-shell" "$HOME/dialog.argv" && grep -qx -- --mark "$HOME/dialog.argv" && ! grep -qx -- --home "$HOME/dialog.argv" \
        && ok "dialog: every section a provider but spark and undo, the composer by the keys, the attach types, this spark-shell for the want, the logo for the about however it is reached" || bad "dialog argv" "st=$st $out $(cat "$HOME/dialog.argv")"
    sh "$C/spark-shell" dialog about >/dev/null 2>&1; [ "$(grep -A1 -x -- --home "$HOME/dialog.argv" | tail -1)" = about ] && grep -qx -- --mark "$HOME/dialog.argv" \
        && ok "dialog about: the about first, with the mark" || bad "dialog about" "$(cat "$HOME/dialog.argv")"
    sh "$C/spark-shell" dialog wifi >/dev/null 2>&1; [ "$(grep -A1 -x -- --home "$HOME/dialog.argv" | tail -1)" = wifi ] && [ "$(grep -x -- "--provider" "$HOME/dialog.argv" | wc -l)" -ge 3 ] && [ "$(grep -A1 -x -- --provider "$HOME/dialog.argv" | sed -n 2p)" = "$C/spark-shell provide wifi" ] \
        && ok "dialog wifi: the section that opened it first" || bad "dialog wifi" "$(cat "$HOME/dialog.argv")"
    sh "$C/spark-shell" dialog >/dev/null 2>&1; c1=$(grep -cx -- "$C/spark-shell provide clock" "$HOME/dialog.argv"); sh "$C/spark-shell" dialog clock >/dev/null 2>&1; c2=$(grep -cx -- "$C/spark-shell provide clock" "$HOME/dialog.argv")
    [ "$c1" = 1 ] && [ "$c2" = 1 ] && [ "$(grep -A1 -x -- --home "$HOME/dialog.argv" | tail -1)" = clock ] \
        && ok "dialog: the clock is started once however the dialog opens, so the Calendar opens from any view" || bad "dialog clock" "$c1 $c2 $(cat "$HOME/dialog.argv")"
    sh "$C/spark-shell" dialog files >/dev/null 2>&1; [ "$(grep -A1 -x -- --home "$HOME/dialog.argv" | tail -1)" = files ] && [ "$(grep -cx -- "$C/spark-shell provide files" "$HOME/dialog.argv")" = 1 ] \
        && ok "dialog files: the files first, its provider started once" || bad "dialog files" "$(cat "$HOME/dialog.argv")"
    printf 'DESKTOP=sway\nDIALOG_ATTACH=no\nDIALOG_MODEL=no\nDIALOG_TALK=no\n' > "$HOME/.config/spark-shell/config"
    sh "$C/spark-shell" dialog >/dev/null 2>&1; [ "$(grep -A1 -x -- --composer "$HOME/dialog.argv" | tail -1)" = '' ] && ok "dialog: DIALOG_ATTACH, DIALOG_MODEL and DIALOG_TALK at no leave the composer bare" || bad "dialog keys" "$(cat "$HOME/dialog.argv")"
    printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"
    st=0; out=$(sh "$C/spark-shell" dialog nonsense 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = 'spark-shell dialog: nonsense is not a section of the dialog' ] && ok "dialog WORD: a word that is no section, refused" || bad "dialog nonsense" "st=$st $out"
    printf 'x' >> "$bin"; st=0; out=$(sh "$C/spark-shell" dialog 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = 'spark-shell dialog: the dialog is not installed, or not the release'"'"'s -- spark-shell on' ] && ok "dialog: a binary changed since it was installed is not run" || bad "dialog changed" "st=$st $out"
fi
unset SPARK_SHELL_SYS SPARK_SHELL_PROC SWAYSOCK

# --- 23. the login screen: greetd on tty1, its own switch -----------------
# on login writes the screen's root files under a throwaway root and
# hands tty1 to greetd at the next boot only: systemd enables and
# disables, never starts or stops; Void's line in rc.local runs
# login-boot before runit. A clone with a signed tag pins the stub
# dialog, as section 22 does. Every root tool is a stub that logs.
if [ "$(uname -s)" = Darwin ]; then
    fresh
    st=0; out=$(sh "$SH" on login --yes 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = "spark-shell login: not on macOS, which has its own login screen" ] && [ ! -e "$HOME/.config/spark-shell/config" ] \
        && ok "macOS: on login refuses in one line, nothing written" || bad "macOS on login" "st=$st $out"
else
    login_clone() {   # login_clone -- $C: this tree, a tag signed by a key in its allowed-signers, the stub dialog pinned and in place
        C=$H/clone; mkdir -p "$C"
        (cd "$REPO" && tar --exclude=.git --exclude=target --exclude=target2 -cf - .) | (cd "$C" && tar --no-same-owner -xf -)
        printf '#!/bin/sh\nexit 0\n' > "$H/stub-dialog"
        sha=$(if command -v sha256sum >/dev/null 2>&1; then sha256sum "$H/stub-dialog"; else shasum -a 256 "$H/stub-dialog"; fi | cut -d' ' -f1)
        sed "s/^DIALOG_SHA256_X86_64_LINUX_MUSL=.*/DIALOG_SHA256_X86_64_LINUX_MUSL=$sha/" "$REPO/dialog/dialog.env" > "$C/dialog/dialog.env"
        ssh-keygen -q -t ed25519 -N '' -C '' -f "$H/key" >/dev/null
        printf 'spark-shell-release namespaces="git" %s\n' "$(cut -d' ' -f1,2 "$H/key.pub")" > "$C/allowed-signers"
        git -C "$C" -c user.name=test -c user.email=you@example.com -c gpg.format=ssh -c "user.signingkey=$H/key" init -q   # spark:allow-secret (a scratch key, made here)
        git -C "$C" add -A
        git -C "$C" -c user.name=test -c user.email=you@example.com commit -q -m fixture
        git -C "$C" -c user.name=test -c user.email=you@example.com -c gpg.format=ssh -c "user.signingkey=$H/key" tag -s v9.9 -m 'spark-shell v9.9'   # spark:allow-secret
        mkdir -p "$H/.local/share/spark-shell"; cp "$H/stub-dialog" "$H/.local/share/spark-shell/spark-dialog"; chmod 755 "$H/.local/share/spark-shell/spark-dialog"
    }
    LC() { PATH=$H/lx:$PATH sh "$C/spark-shell" "$@" </dev/null; }   # the clone as the uname stub says
    login_root() {   # login_root ID -- a root with greetd installed, its package config, its account
        fresh
        console_stubs Linux
        desktop_stubs
        printf 'ID=%s\n' "$1" > "$H/os-release"
        mkdir -p "$H/root/etc/greetd" "$H/root/usr/bin" "$H/root/usr/sbin"
        printf '[terminal]\nvt = 1\n# agreety, the package'"'"'s\n' > "$H/root/etc/greetd/config.toml"
        printf 'root:x:0:0::/root:/bin/sh\n_greeter:x:900:900::/var/lib/_greeter:/sbin/nologin\n_greetd:x:901:901::/var/lib/greetd:/bin/false\n' > "$H/root/etc/passwd"
        printf 'root:x:0:\n_seatd:x:990:\n' > "$H/root/etc/group"
        printf '#!/bin/sh\necho "visudo $*" >> "$HOME/log"\n! grep -q BAD "$2"\n' > "$H/lx/visudo"
        printf '#!/bin/sh\n[ "$2" = greetd ] && [ -e "$HOME/greetd-running" ]\n' > "$H/lx/pgrep"
        printf '#!/bin/sh\necho "usermod $*" >> "$HOME/log"\nsed "s/^%s:x:990:.*/&,$3/;s/:,/:/" "$SPARK_SHELL_ROOT/etc/group" > "$HOME/g" && cat "$HOME/g" > "$SPARK_SHELL_ROOT/etc/group"\n' '_seatd' > "$H/lx/usermod"
        printf '#!/bin/sh\necho "gpasswd $*" >> "$HOME/log"\nsed "s/^\\(_seatd:x:990:\\).*/\\1/" "$SPARK_SHELL_ROOT/etc/group" > "$HOME/g" && cat "$HOME/g" > "$SPARK_SHELL_ROOT/etc/group"\n' > "$H/lx/gpasswd"
        printf '#!/bin/sh\nexit 0\n' > "$H/lx/xbps-query"; printf '#!/bin/sh\necho "install ok installed"\n' > "$H/lx/dpkg-query"
        chmod +x "$H/lx"/*
        login_clone
        : > "$H/log"
    }
    le=$H/root/etc/spark-shell/login   # moved by each fresh: set again below
    # Void: runit, the boot hook, the account in _seatd, sudoers for the power keys
    login_root void
    le=$H/root/etc/spark-shell/login; ll=$H/root/usr/local/lib/spark-shell
    mkdir -p "$H/root/etc/runit/runsvdir/default" "$H/root/etc/sv/greetd" "$H/root/etc/sv/agetty-tty1"
    ln -s /etc/sv/agetty-tty1 "$H/root/etc/runit/runsvdir/default/agetty-tty1"; : > "$H/root/usr/bin/greetd"
    out=$(LC on login --dry-run)
    printf '%s\n' "$out" | grep -q '^would  config       LOGIN=yes' && printf '%s\n' "$out" | grep -q "^would  login        write the login screen's files: session window run sway.conf foot.ini spark-dialog config.toml sudoers login-boot (sudo)\$" \
        && [ ! -e "$le" ] && [ ! -e "$HOME/.config/spark-shell/config" ] && ok "Void: on login --dry-run says the config and the files, touches nothing" || bad "void login dry" "$out"
    st=0; out=$(LC on login --yes 2>&1) || st=$?
    [ "$st" -eq 0 ] && grep -q '^LOGIN=yes$' "$HOME/.config/spark-shell/config" && ok "Void: on login writes LOGIN=yes" || bad "void login config" "st=$st $out"
    for f in session window run sway.conf foot.ini; do [ -f "$le/$f" ] || bad "Void: on login: $f missing"; done
    [ -x "$le/session" ] && [ -x "$le/window" ] && [ -x "$le/run" ] && [ -x "$ll/spark-dialog" ] && [ -x "$ll/login-boot" ] && cmp -s "$ll/spark-dialog" "$H/stub-dialog" \
        && ok "Void: on login writes the screen's files, the pinned dialog copied for its account" || bad "void login files" "$(ls -la "$le" "$ll" 2>&1)"
    grep -q '^user = "_greeter"$' "$H/root/etc/greetd/config.toml" && grep -q '^command = "/etc/spark-shell/login/session"$' "$H/root/etc/greetd/config.toml" && grep -q agreety "$H/root/etc/greetd/config.toml.spark-shell-orig" \
        && ok "Void: greetd's config.toml is ours (the session as _greeter), the package's kept" || bad "void greetd conf" "$(cat "$H/root/etc/greetd/config.toml")"
    grep -q -- '--desktop off --restart "/usr/bin/sudo -n /usr/bin/reboot" --shutdown "/usr/bin/sudo -n /usr/bin/poweroff"\( --spark-port [0-9]*\)\{0,1\}$' "$le/run" && grep -q '^export PANEL_BG=[0-9a-f]\{6\} ' "$le/run" \
        && ok "Void: the run file: no desktop yet, the power keys through sudo, the palette" || bad "void run" "$(cat "$le/run")"
    [ "$(cat "$H/root/etc/sudoers.d/spark-shell-login")" = "$(sed -n '$p' "$REPO/templates/login/sudoers" | sed 's/@LOGIN_ACCOUNT@/_greeter/')" ] || [ "$(sed -n '$p' "$H/root/etc/sudoers.d/spark-shell-login")" = '_greeter ALL=(root) NOPASSWD: /usr/bin/reboot, /usr/bin/poweroff' ] \
        && grep -q '^visudo -cf ' "$H/log" && ok "Void: sudoers lets _greeter run reboot and poweroff only, checked by visudo first" || bad "void sudoers" "$(cat "$H/root/etc/sudoers.d/spark-shell-login" "$H/log")"
    grep -q '^_seatd:x:990:_greeter$' "$H/root/etc/group" && [ -e "$le/seatd.group" ] && ok "Void: _greeter joins _seatd, recorded" || bad "void seatd" "$(cat "$H/root/etc/group")"
    [ "$(cat "$le/boot")" = on ] && grep -q '/usr/local/lib/spark-shell/login-boot #spark-shell-login#$' "$H/root/etc/rc.local" \
        && [ -L "$H/root/etc/runit/runsvdir/default/agetty-tty1" ] && [ ! -e "$H/root/etc/runit/runsvdir/default/greetd" ] \
        && ok "Void: tty1 changes hands at the next boot (a line in rc.local), getty untouched now" || bad "void boot" "$(cat "$H/root/etc/rc.local" 2>&1; ls -la "$H/root/etc/runit/runsvdir/default")"
    printf '%s\n' "$out" | grep -q '^ok     login        the login screen takes tty1 from the next boot (tty2 keeps the console login)$' && ok "Void: one line says it" || bad "void line" "$out"
    out=$(LC on --dry-run); printf '%s\n' "$out" | grep -q '^Nothing to do$' && ok "Void: on again: Nothing to do" || bad "void login again" "$out"
    out=$(LC check 2>&1 || :); printf '%s\n' "$out" | grep -q '^ok     login        the login screen takes tty1 at boot, tty2 keeps the console login$' && ok "Void: check says the login screen is set up" || bad "void check" "$(printf '%s\n' "$out" | grep login)"
    out=$(LC status); printf '%s\n' "$out" | grep -q '^  login screen  *the login screen on tty1 from the next boot, the console login on tty2$' && ok "Void: status says from the next boot" || bad "void status" "$(printf '%s\n' "$out" | grep login)"
    # the boot: login-boot as rc.local runs it, its paths under the root
    sed "s|/etc/|$H/root/etc/|g" "$ll/login-boot" > "$H/boot.sh"
    sh "$H/boot.sh" && [ ! -e "$H/root/etc/runit/runsvdir/default/agetty-tty1" ] && [ "$(readlink "$H/root/etc/runit/runsvdir/default/greetd")" = "$H/root/etc/sv/greetd" ] && [ -e "$le/getty.off" ] && [ -e "$le/greetd.on" ] \
        && ok "Void: at boot greetd takes tty1 from its getty, each change recorded" || bad "void hook on" "$(ls -la "$H/root/etc/runit/runsvdir/default" "$le")"
    sh "$H/boot.sh" && [ -e "$le/greetd.on" ] && ok "Void: the hook at the next boot again changes nothing" || bad "void hook twice"
    : > "$HOME/greetd-running"
    out=$(LC status); printf '%s\n' "$out" | grep -q '^  login screen  *the login screen on tty1, the console login on tty2$' && ok "Void: status with greetd running" || bad "void status live" "$(printf '%s\n' "$out" | grep login)"
    # a new palette reaches the screen; a program the screen runs is put in place by a rename, so a running one (a link held here) keeps its old file
    ln "$le/run" "$H/run.held"
    palette_fixture other '#123456'; LC theme other >/dev/null 2>&1 || :
    grep -q '^export HEX_BG=282828 HEX_FG=ebdbb2 HEX_ACCENT=123456 ' "$le/run" && ok "Void: theme NAME writes the login screen's palette too" || bad "void theme follow" "$(grep HEX_BG "$le/run")"
    ! grep -q 'HEX_ACCENT=123456' "$H/run.held" && [ -x "$le/run" ] && [ -z "$(find "$le" "$ll" -name '*.spark-shell-new')" ] \
        && ok "Void: the screen's programs are replaced by a rename, never written over (Linux refuses a write to a running binary)" || bad "void swap" "$(ls -la "$le" "$ll")"
    rm -f "$H/run.held"
    # off login while greetd runs: the boot goes back, the files stay until it stopped
    out=$(LC off login 2>&1)
    grep -q '^LOGIN=no$' "$HOME/.config/spark-shell/config" && [ "$(cat "$le/boot")" = off ] && [ -f "$le/session" ] && [ ! -e "$H/root/etc/sudoers.d/spark-shell-login" ] && grep -q '^_seatd:x:990:$' "$H/root/etc/group" \
        && printf '%s\n' "$out" | grep -q "^todo   login        the login screen runs until the next boot, then tty1 has the console login" \
        && ok "Void: off login with greetd running: the boot back, sudoers and the group gone, the screen's files kept" || bad "void off live" "$out $(ls "$le")"
    rm -f "$HOME/greetd-running"; sh "$H/boot.sh"
    [ -L "$H/root/etc/runit/runsvdir/default/agetty-tty1" ] && [ ! -e "$H/root/etc/runit/runsvdir/default/greetd" ] && [ ! -e "$le/getty.off" ] && [ ! -e "$le/greetd.on" ] \
        && ok "Void: at the next boot the hook gives tty1 back to getty" || bad "void hook off" "$(ls -la "$H/root/etc/runit/runsvdir/default")"
    out=$(LC off login 2>&1)
    [ ! -e "$le" ] && [ ! -e "$ll" ] && ! grep -q 'spark-shell-login' "$H/root/etc/rc.local" 2>/dev/null && grep -q agreety "$H/root/etc/greetd/config.toml" && [ ! -e "$H/root/etc/greetd/config.toml.spark-shell-orig" ] \
        && printf '%s\n' "$out" | grep -q "^ok     login        the console login is back on tty1 from the next boot, the login screen's files are gone (greetd's package stays)$" \
        && ok "Void: off login after it: every file gone, the package's config.toml back" || bad "void off" "$out $(find "$H/root/etc/spark-shell" "$H/root/usr/local" 2>&1)"
    out=$(LC off login 2>&1); ! printf '%s\n' "$out" | grep -q '^\(ok\|todo\) *login' && ok "Void: off login twice: nothing left, nothing said" || bad "void off twice" "$out"
    # visudo refuses: nothing written
    sed 's|/usr/bin/reboot|BAD|' "$C/templates/login/sudoers" > "$H/s" && cp "$H/s" "$C/templates/login/sudoers"
    out=$(LC on login --yes 2>&1 || :)
    printf '%s\n' "$out" | grep -q '^todo   login        visudo refused the sudoers file -- nothing written' && [ ! -e "$H/root/etc/sudoers.d/spark-shell-login" ] && [ ! -e "$le/run" ] \
        && ok "Void: a sudoers file visudo refuses is never written, nor the rest" || bad "void visudo" "$out"
    # Debian: systemd enables and disables, never starts or stops; logind lets the screen restart and shut down
    login_root debian
    le=$H/root/etc/spark-shell/login; ll=$H/root/usr/local/lib/spark-shell
    mkdir -p "$H/root/run/systemd/system" "$H/root/units"; : > "$H/root/units/getty@tty1.service"; : > "$H/root/usr/sbin/greetd"
    mkdir -p "$HOME/.config/spark-shell"; printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"
    st=0; out=$(LC on login --yes 2>&1) || st=$?
    [ "$st" -eq 0 ] && grep -q '^user = "_greetd"$' "$H/root/etc/greetd/config.toml" && [ -e "$H/root/units/greetd.service" ] && [ ! -e "$H/root/units/getty@tty1.service" ] \
        && [ "$(grep -n 'enable greetd' "$H/log" | cut -d: -f1)" -lt "$(grep -n 'disable getty@tty1' "$H/log" | cut -d: -f1)" ] && ! grep -Eq '^systemctl (start|stop|restart|kill)' "$H/log" \
        && ok "Debian: greetd enabled before getty@tty1 is disabled, nothing started or stopped" || bad "debian login" "st=$st $out $(cat "$H/log")"
    [ -e "$le/greetd.on" ] && [ -e "$le/getty.off" ] && [ ! -e "$H/root/etc/sudoers.d/spark-shell-login" ] && [ ! -e "$ll/login-boot" ] && ! grep -q usermod "$H/log" \
        && grep -q -- '--desktop on --restart "/usr/bin/systemctl reboot" --shutdown "/usr/bin/systemctl poweroff"\( --spark-port [0-9]*\)\{0,1\}$' "$le/run" \
        && ok "Debian: no sudoers, no boot hook, no group; the power keys are systemctl's; the desktop offered" || bad "debian extras" "$(cat "$le/run"; ls "$le")"
    out=$(LC off login 2>&1)
    [ -e "$H/root/units/getty@tty1.service" ] && [ ! -e "$H/root/units/greetd.service" ] && [ "$(grep -n 'enable getty@tty1' "$H/log" | cut -d: -f1)" -lt "$(grep -n 'disable greetd' "$H/log" | cut -d: -f1)" ] \
        && [ ! -e "$le" ] && grep -q agreety "$H/root/etc/greetd/config.toml" && ok "Debian: off login: getty@tty1 enabled first, greetd disabled, the files gone" || bad "debian off" "$out $(cat "$H/log")"
    # a family the screen does not know, and no greetd yet
    login_root fixture
    out=$(LC on login --yes 2>&1 || :); printf '%s\n' "$out" | grep -q '^todo   login        the login screen knows Debian, Arch and Void$' && ok "an unknown family: a todo row, nothing written" || bad "login unknown" "$out"
    login_root void; mkdir -p "$H/root/etc/runit"
    out=$(LC on login --yes 2>&1 || :); printf '%s\n' "$out" | grep -q '^todo   login        greetd is not installed -- spark-shell on login (the packages)$' && [ ! -e "$H/root/etc/spark-shell" ] && ok "Void without greetd: a todo row, nothing written" || bad "login no greetd" "$out"
fi
[ "$(grep -h '^PKG_LOGIN=' "$REPO"/distro/*.env | sort -u)" = 'PKG_LOGIN=greetd swayidle' ] && grep -q '^LOGIN_ACCOUNT=_greeter$' "$REPO/distro/void.env" && grep -q '^LOGIN_ACCOUNT=greeter$' "$REPO/distro/arch.env" && grep -q '^LOGIN_ACCOUNT=_greetd$' "$REPO/distro/debian.env" \
    && ok "distro/*.env: greetd, swayidle and each package's account for the login screen" || bad "distro login keys"
! grep -v '^#' "$REPO/templates/login/sway.conf" | grep -q fullscreen && grep -q '^gaps outer 0$' "$REPO/templates/login/sway.conf" && grep -q '^alpha=0.0$' "$REPO/templates/login/foot.ini" \
    && ok "templates/login: the window fills the screen tiled, never fullscreen (foot draws a fullscreen background solid), clear over the wallpaper" || bad "login sway fullscreen"
sw=$(grep '^exec swayidle ' "$REPO/templates/login/sway.conf"); [ "$sw" = "exec swayidle timeout 300 'swaymsg \"output * power off\"' resume 'swaymsg \"output * power on\"'" ] \
    && ok "templates/login: five idle minutes turn the display off, a key or a move turns it on" || bad "login swayidle" "$(grep -n swayidle "$REPO/templates/login/sway.conf")"
# the session says nothing on tty1: the console cleared and its cursor hidden, then what sway and its children say lands in login.log
ls_d=$(mktemp -d); mkdir -p "$ls_d/bin" "$ls_d/run"
printf '#!/bin/sh\necho "sway $*"\necho "[main.c:332] Found config * for output" >&2\n' > "$ls_d/bin/sway"; chmod +x "$ls_d/bin/sway"
sed 's|@LOGIN_ETC@|etc/spark-shell/login|g' "$REPO/templates/login/session" > "$ls_d/session"
out=$(PATH="$ls_d/bin:$PATH" XDG_RUNTIME_DIR="$ls_d/run" sh "$ls_d/session" 2>&1)
[ "$out" = "$(printf '\033[2J\033[H\033[?25l')" ] && grep -qx 'sway -c /etc/spark-shell/login/sway.conf' "$ls_d/run/login.log" && grep -q 'Found config' "$ls_d/run/login.log" \
    && ok "templates/login/session: tty1 is cleared, its cursor hidden, and sway's words go to login.log, none on the screen" || bad "login session quiet" "$(printf '%s' "$out" | od -c | head -3) $(cat "$ls_d/run/login.log" 2>&1)"
rm -rf "$ls_d"
bp=$REPO/templates/linux/.bash_profile
grep -q 'SPARK_SHELL_SESSION:-}" != shell' "$bp" && ok ".bash_profile: the login screen's shell session never starts the desktop" || bad ".bash_profile shell session"

# --- the voice: the docs and the help hold to it -------------------------
# README.md, the top entry of CHANGELOG.md, CREDITS.md, config.example, the
# help (sh spark-shell -h) and the comment lines of the sway template are
# plain English: none of the made-up words that are out, no contraction,
# capitals only for acronyms and placeholders, 80 columns. README is read
# without its fenced and indented blocks (a command block is quoted there,
# not prose). The key sentences are held above (desktop keys: a period
# each, verbatim in README). Not uname-guarded: the words are the same on
# both OSes. Each check names the file and the words it found. Runs last:
# a red row here belongs to a document, not to the program.
voice=$(mktemp -d)
awk '/^```/ {fence = !fence; next} fence {next} /^    / {next} {print}' "$REPO/README.md" > "$voice/README.md"
awk '/^## v/ {n++} n == 1' "$REPO/CHANGELOG.md" > "$voice/CHANGELOG.md"
cp "$REPO/CREDITS.md" "$voice/CREDITS.md"
cp "$REPO/config.example" "$voice/config.example"
sh "$SH" -h > "$voice/help"
grep '^ *#' "$REPO/templates/.config/sway/config" > "$voice/sway-config-comments"
out_words="colours?|desks?|rooms?|seat|login box|marks?|marked|player|this machine's cycles|the forge wallpaper|greeter|the box|stranger|newcomer|founder|inventory|the hands|shell layer|monitors?"
contractions="[A-Za-z]*n't\b|\bit's\b|\byou'll\b|\bwe're\b|\bthat's\b|\bthere's\b|\blet's\b"
caps_ok='ASCII|ALSA|A2DP|POSIX|JSON|SGR|SBOM|PATH|NAME|WORDS|PAGE|SECTION|KEY|VALUE|FILE|DIR|HOME|EDITOR|FACE|SIZE|GRUB|FAIL|WARN|TODO|LICENSE|MIT|ISC|GPL|CC|README|CHANGELOG|CREDITS|VGA|RGB|ANSI|CI|LAN|XDG|PPT|HDMI|URL|HTTP|THEME|SITE|SPARK|DESKTOP|LOGIN|WALLPAPER|ALPHA|WINDOWS|FONT|PROMPT|GIT|PM|PKG|CDX|CP437|UKI|macOS'
for n in README.md CHANGELOG.md CREDITS.md config.example help sway-config-comments; do
    f=$voice/$n
    # (a) the words that are out, as whole words in any case
    hit=$(grep -ioEw "$out_words" "$f" | sort -u | paste -sd, -)
    [ -z "$hit" ] && ok "voice: $n has none of the words that are out" || bad "voice: $n has a word that is out" "$hit"
    # (b) no contraction
    hit=$(grep -ioE "$contractions" "$f" | sort -u | paste -sd, -)
    [ -z "$hit" ] && ok "voice: $n has no contraction" || bad "voice: $n has a contraction" "$hit"
    # (c) capitals only for acronyms: a word of 4+ capitals outside a code span is on the list or carries an underscore
    hit=$(sed 's/`[^`]*`//g' "$f" | tr -c 'A-Za-z0-9_' '\n' | grep -E '^[A-Z][A-Z0-9]{3,}$' | grep -vxE "($caps_ok)" | sort -u | paste -sd, -)
    [ -z "$hit" ] && ok "voice: $n has capitals only for acronyms" || bad "voice: $n has a word in capitals" "$hit"
    # (d) ASCII only
    LC_ALL=C grep -q "[^ -~${tab}]" "$f" && bad "voice: $n has a byte outside ASCII" "$(LC_ALL=C grep -n "[^ -~${tab}]" "$f" | head -2)" || ok "voice: $n is ASCII"
done
# (e) the widths: the help and README at most 80 columns a line
wide=$(awk 'length > 80 {print FNR ": " length}' "$voice/help" | head -3 | paste -sd, -)
[ -z "$wide" ] && ok "voice: every help line is 80 columns or fewer" || bad "voice: a help line is wider than 80 (line: width)" "$wide"
wide=$(awk 'length > 80 {print FNR ": " length}' "$REPO/README.md" | head -3 | paste -sd, -)
[ -z "$wide" ] && ok "voice: every README line is 80 columns or fewer" || bad "voice: a README line is wider than 80 (line: width)" "$wide"
rm -rf "$voice"

printf '%s\n' "shell_test: $pass ok, $fail failed"
[ "$fail" -eq 0 ]
