#!/bin/sh
# desktop_proof.sh -- the desktop proven in a container, as a plain user
# (CI's desktop job, one family a run): spark-shell on with DESKTOP=sway
# against a throwaway root, the renders in place, a drawing drawn again in
# the palette through rsvg-convert, the sway config read by sway -C, then a
# headless sway (no seat, no GPU: wlroots' headless backend and the pixman
# renderer) with a foot window in it, asked through swaymsg. Every step
# prints what it found; the first failure ends it. REPO is the clone.
# The root tools a plain user cannot run (usermod, gpasswd) are shims that
# edit the throwaway root's group file, as the suite's do.
set -eu
REPO=${REPO:?the clone path}
export HOME=${HOME:-/home/ada}
export XDG_RUNTIME_DIR=/tmp/proof-runtime SPARK_SHELL_ROOT=$HOME/root SPARK_SHELL_DIALOG_URL=none SPARK_SHELL_FONT_URL=none LANG=C.UTF-8
export WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1
unset DISPLAY WAYLAND_DISPLAY SWAYSOCK
R=$SPARK_SHELL_ROOT
mkdir -p "$XDG_RUNTIME_DIR" "$R/etc" "$R/var/service" "$R/etc/sv/seatd" "$HOME/.config/spark-shell" "$HOME/.config/spark" "$HOME/bin"
chmod 700 "$XDG_RUNTIME_DIR"
cp /etc/os-release "$R/etc/os-release"
cp /etc/group "$R/etc/group"
cp /etc/passwd "$R/etc/passwd"
me=$(id -un)
cat > "$HOME/bin/usermod" <<EOF
#!/bin/sh
# proof: usermod -aG GROUP USER edits the throwaway root's group file
echo "usermod \$*" >> "$HOME/root-tools.log"
[ "\$1" = -aG ] || exit 0
awk -F: -v g="\$2" -v u="\$3" 'BEGIN { OFS = ":" } \$1 == g { \$4 = (\$4 == "" ? u : \$4 "," u) } { print }' "$R/etc/group" > "$R/etc/group.new" && mv "$R/etc/group.new" "$R/etc/group"
EOF
printf '#!/bin/sh\necho "gpasswd $*" >> "%s/root-tools.log"\n' "$HOME" > "$HOME/bin/gpasswd"
chmod 755 "$HOME/bin/usermod" "$HOME/bin/gpasswd"
export PATH=$HOME/bin:${SWAY_NOCAP:+$SWAY_NOCAP:}$PATH   # SWAY_NOCAP: a folder with a copy of sway that carries no file capability (see ci.yml)
printf 'DESKTOP=sway\nTHEME=nord\nWALLPAPER=skyline\nDISPLAY_IDLE=0\nDISPLAY_LOCK=0\n' > "$HOME/.config/spark-shell/config"
cd "$HOME"
distro=$(sed -n 's/^PRETTY_NAME=//p' /etc/os-release | tr -d '"')

echo "== spark-shell on --yes -v ($distro, as $me)"
sh "$REPO/spark-shell" on --yes -v 2>&1 | tee "$HOME/on.out"
grep -q '^ok     packages     installed$' "$HOME/on.out" || { echo "FAIL: the packages row is not ok"; exit 1; }
grep -q '^render wallpaper    skyline drawn in nord ' "$HOME/on.out" || { echo "FAIL: skyline was not drawn in nord (rsvg-convert)"; exit 1; }
for f in .config/sway/config .config/foot/foot.ini .config/foot/dialog.ini .tmux.conf .config/spark-shell/sgr.sh; do
    [ -f "$HOME/$f" ] || { echo "FAIL: $f was not rendered"; exit 1; }
done
png=$HOME/.local/state/spark-shell/wallpapers/skyline-nord.png
[ -s "$png" ] || { echo "FAIL: no $png"; exit 1; }
echo "ok: the renders are in place; skyline drawn in nord, $(wc -c < "$png" | tr -d ' ') bytes"
[ ! -s "$HOME/root-tools.log" ] || { echo "-- the root steps a plain user cannot take, through the shims:"; cat "$HOME/root-tools.log"; }

echo "== spark-shell check"
sh "$REPO/spark-shell" check 2>&1 | tee "$HOME/check.out" || true
grep -Eq '^(ok|warn) +desktop +' "$HOME/check.out" || { echo "FAIL: check's desktop row is not ok or warn"; exit 1; }
grep -q '^ok     look ' "$HOME/check.out" || { echo "FAIL: check's look row is not ok"; exit 1; }
grep -q '^ok     tools ' "$HOME/check.out" || { echo "FAIL: check's tools row is not ok"; exit 1; }

echo "== sway -C: the rendered config reads"
if sway -C -c "$HOME/.config/sway/config" > "$HOME/sway-C.out" 2>&1; then echo "ok: sway -C accepts the config"; else cat "$HOME/sway-C.out"; echo "FAIL: sway -C refused the config"; exit 1; fi
cat "$HOME/sway-C.out"

echo "== a headless sway, then a foot window in it"
sway -c "$HOME/.config/sway/config" > "$HOME/sway.log" 2>&1 &
swaypid=$!
sock=''
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    sock=$(ls "$XDG_RUNTIME_DIR"/sway-ipc.*.sock 2>/dev/null | head -1)
    [ -z "$sock" ] || break
    kill -0 "$swaypid" 2>/dev/null || { echo "FAIL: sway ended before its socket came up"; cat "$HOME/sway.log"; exit 1; }
    sleep 1
done
[ -n "$sock" ] || { echo "FAIL: no sway socket after 15 s"; cat "$HOME/sway.log"; exit 1; }
export SWAYSOCK=$sock
sleep 2
swaymsg -t get_version | jq -r '"sway " + .human_readable'
swaymsg -t get_outputs | jq -r '.[] | "output " + .name + " " + (.current_mode.width|tostring) + "x" + (.current_mode.height|tostring)'
swaymsg exec 'foot --app-id proof-window' >/dev/null   # by its app id: the rc's prompt hook retitles a foot window to terminal at once
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    swaymsg -t get_tree | jq -e '.. | objects | select(.app_id? == "proof-window")' >/dev/null 2>&1 && break
    sleep 1
done
swaymsg -t get_tree | jq -e '.. | objects | select(.app_id? == "proof-window")' >/dev/null || { echo "FAIL: no foot window in sway's tree"; tail -40 "$HOME/sway.log"; exit 1; }
echo "ok: a foot window is open in the headless sway ($(swaymsg -t get_tree | jq -r '[.. | objects | select(.app_id? != null) | .app_id] | unique | join(", ")'))"
for b in $(swaymsg -t get_bar_config | jq -r '.[]'); do swaymsg -t get_bar_config "$b" | jq -r '"bar " + .id + ": mode " + .mode + ", at the " + .position'; done
swaymsg exit >/dev/null 2>&1 || true
wait "$swaypid" 2>/dev/null || true
grep -i 'error' "$HOME/sway.log" | head -5 || true
echo "== done: $distro installs the desktop, renders it, and sway runs it headless"
