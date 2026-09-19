#!/bin/sh
# spark-shell tests -- a throwaway HOME, no network, no packages: the
# package row is forced to `todo` by an unknown distro fixture, and the
# pinned rows are satisfied by stubs, so `on` exercises the render and
# link machinery only. Run: sh tests/shell_test.sh
set -eu
REPO=$(cd "$(dirname "$0")/.." && pwd)
pass=0; fail=0
ok() { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s   %s\n' "$1" "${2:-}"; }

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

theme_fixture() {   # theme_fixture ACCENT -- a full 21-key theme.env
    {
        printf 'THEME_BG=#101010\nTHEME_FG=#e0e0e0\nTHEME_ACCENT=%s\nTHEME_MUTED=#808080\nTHEME_BTOP=TTY\n' "$1"
        i=0
        while [ $i -le 15 ]; do printf 'THEME_ANSI_%d=#0000%02x\n' "$i" "$i"; i=$((i + 1)); done
    } > "$HOME/.config/spark/theme.env"
}

SH=$REPO/spark-shell

# --- 1. dry-run: rows, nothing touched -----------------------------------
fresh
out=$(sh "$SH" on --dry-run)
printf '%s\n' "$out" | grep -q '^would  rc' && ok "dry-run: would link the rc files" || bad "dry-run rc rows" "$out"
printf '%s\n' "$out" | grep -q '^would  look' && ok "dry-run: would render the look" || bad "dry-run look rows" "$out"
printf '%s\n' "$out" | grep -q '^todo   packages' && ok "dry-run: an unknown family is a todo, not a guess" || bad "dry-run packages row" "$out"
printf '%s\n' "$out" | grep -q ' to do$' && ok "dry-run ends with the count" || bad "dry-run count" "$out"
[ ! -e "$HOME/.tmux.conf" ] && ok "dry-run touched nothing" || bad "dry-run wrote files"

# --- 2. on: links, renders, idempotence ----------------------------------
theme_fixture '#ff8800'
printf 'yours\n' > "$HOME/.bashrc"     # a pre-existing rc file of the user's
out=$(sh "$SH" on)
case $(uname -s) in Darwin) rc1=.zshrc ;; *) rc1=.bashrc ;; esac
[ -L "$HOME/$rc1" ] && ok "on: $rc1 is spark-shell's link" || bad "rc link" "$(ls -la "$HOME")"
if [ "$rc1" = .bashrc ]; then
    [ -f "$HOME/.bashrc.bak" ] && grep -q yours "$HOME/.bashrc.bak" && ok "on: yours went to .bak" || bad "rc backup"
fi
[ -f "$HOME/.tmux.conf" ] && grep -q '#ff8800' "$HOME/.tmux.conf" && ok "on: tmux.conf rendered with the palette" || bad "tmux render"
grep -q '@[A-Z_0-9]*@' "$HOME/.tmux.conf" && bad "unrendered placeholder left" || ok "on: no placeholder left"
[ -f "$HOME/.config/starship.toml" ] && ok "on: starship.toml rendered (minimal)" || bad "starship render"
[ -f "$HOME/.gitconfig" ] && ok "on: .gitconfig rendered" || bad "gitconfig render"
out=$(sh "$SH" on --dry-run)
printf '%s\n' "$out" | grep -q '^Nothing to do$' && ok "second run: Nothing to do" || bad "idempotence" "$out"

# --- 3. apply follows the palette ----------------------------------------
theme_fixture '#00cc66'
sh "$SH" apply >/dev/null
grep -q '#00cc66' "$HOME/.tmux.conf" && ok "apply: a new palette lands in the render" || bad "apply rerender"
out=$(sh "$SH" check || true)
printf '%s\n' "$out" | grep -q '^ok     look' && ok "check: the look matches the palette" || bad "check look row" "$out"

# --- 4. the prompt choices ------------------------------------------------
mkdir -p "$HOME/.config/spark-shell"
printf 'PROMPT=plain\n' > "$HOME/.config/spark-shell/config"
rm -f "$HOME/.config/starship.toml"
sh "$SH" apply >/dev/null
[ ! -e "$HOME/.config/starship.toml" ] && ok "PROMPT=plain renders no starship.toml" || bad "plain prompt"
printf 'PROMPT=starship\nPROMPT_STYLE=full\n' > "$HOME/.config/spark-shell/config"
sh "$SH" apply >/dev/null
[ -f "$HOME/.config/starship.toml" ] && ok "PROMPT_STYLE=full renders the full style" || bad "full style"

# --- 5. off hands back ----------------------------------------------------
out=$(sh "$SH" off)
if [ "$rc1" = .bashrc ]; then
    [ ! -L "$HOME/.bashrc" ] && grep -q yours "$HOME/.bashrc" && ok "off: the rc file came back from .bak" || bad "rc restore" "$(ls -la "$HOME")"
fi
[ ! -e "$HOME/.tmux.conf" ] && ok "off: a render with no .bak is removed, never a husk" || bad "render removal"
printf '%s\n' "$out" | grep -q 'packages stay installed' && ok "off: packages stay, said so" || bad "off closing" "$out"

# --- 6. adoption: a file spark's old layer rendered is ours ---------------
fresh
theme_fixture '#123456'
printf '# rendered by spark install.sh from templates/.tmux.conf\nold\n' > "$HOME/.tmux.conf"
sh "$SH" on >/dev/null
grep -q '#123456' "$HOME/.tmux.conf" && [ ! -e "$HOME/.tmux.conf.bak" ] && ok "adoption: an old spark render is re-rendered, no .bak" || bad "adoption"

# --- 7. config seeded from site.env once ----------------------------------
fresh
printf 'SITE_PROMPT=starship\nSITE_PROMPT_STYLE=full\nSITE_GIT_NAME=Test Person\n' > "$HOME/.config/spark/site.env"
sh "$SH" status >/dev/null
grep -q 'PROMPT_STYLE=full' "$HOME/.config/spark-shell/config" && grep -q 'GIT_NAME=Test Person' "$HOME/.config/spark-shell/config" \
    && ok "first run seeds the config from site.env" || bad "seeding" "$(cat "$HOME/.config/spark-shell/config" 2>/dev/null)"

# --- 8. invoked through a symlink (~/.local/bin): the repo still found --
fresh
theme_fixture '#abcdef'
ln -s "$SH" "$H/.local/bin/spark-shell"
sh -c '"$0" on' "$H/.local/bin/spark-shell" >/dev/null 2>&1 || true
[ -f "$HOME/.tmux.conf" ] && grep -q '#abcdef' "$HOME/.tmux.conf" \
    && ok "a symlinked spark-shell still finds its templates" || bad "symlink invocation" "$(ls -la "$HOME" | head -4)"
case $(uname -s) in Darwin) r8=.zshrc ;; *) r8=.bashrc ;; esac
[ -L "$HOME/$r8" ] && [ -e "$HOME/$r8" ] && ok "the rc link resolves (no dangling target)" || bad "rc link dangles" "$(readlink "$HOME/$r8" 2>&1)"

printf '%s\n' "shell_test: $pass ok, $fail failed"
[ "$fail" -eq 0 ]
