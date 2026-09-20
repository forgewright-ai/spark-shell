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
grep -q 'Tc' "$HOME/.tmux.conf" && bad "tmux still advertises truecolor" || ok "on: no truecolor override"
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
grep -q '${custom.spark}${custom.spark_down}$character' "$HOME/.config/starship.toml" && grep -q 'style = "bright-red"' "$HOME/.config/starship.toml" \
    && ok "on: starship's spark segment sits before the character, in the accent" || bad "starship segment" "$(grep -n 'custom\|^format' "$HOME/.config/starship.toml")"
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
    grep -q '^\[custom\.spark\]' "$st_t" && grep -q 'spark/prompt' "$st_t" && grep -q '^when = true' "$st_t" \
        && ok "starship $t: the spark segment reads spark/prompt, when = true" || bad "starship $t segment"
    grep -q '${custom.spark}${custom.spark_down}$character' "$st_t" && ok "starship $t: the segment sits right before the character" || bad "starship $t placement"
    sed -n '/^\[custom\.spark/,/^\[character\]/p' "$st_t" | grep -v '^#' | grep -q python && bad "starship $t: python on a prompt" || ok "starship $t: the segment is sh builtins only"
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

printf '%s\n' "shell_test: $pass ok, $fail failed"
[ "$fail" -eq 0 ]
