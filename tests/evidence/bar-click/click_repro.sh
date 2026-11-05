#!/bin/sh
# click_repro.sh -- the bar's notifications block clicked inside a real headless sway, with the
# release dialog: the click written into the running bar's own stdin (swaybar's pipe), as swaybar
# writes it. Case A: no home open. Case B: home open already, at its root.
set -eu
REPO=${REPO:?}; export HOME=${HOME:?}
export XDG_RUNTIME_DIR=$HOME/run SPARK_SHELL_ROOT=$HOME/root LANG=C.UTF-8
export SPARK_SHELL_FONT_URL=${FONT_ZIP:+file://$FONT_ZIP}
export WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1
unset DISPLAY WAYLAND_DISPLAY SWAYSOCK
mkdir -p "$XDG_RUNTIME_DIR" "$SPARK_SHELL_ROOT/etc" "$HOME/.config/spark-shell" "$HOME/bin"; chmod 700 "$XDG_RUNTIME_DIR"
cp /etc/os-release /etc/group /etc/passwd "$SPARK_SHELL_ROOT/etc/"
printf '#!/bin/sh\nexit 0\n' > "$HOME/bin/usermod"; cp "$HOME/bin/usermod" "$HOME/bin/gpasswd"; chmod 755 "$HOME/bin"/*
export PATH=$HOME/bin:$PATH
printf 'DESKTOP=sway\nTHEME=nord\nWALLPAPER=skyline\nDISPLAY_IDLE=0\nDISPLAY_LOCK=0\n' > "$HOME/.config/spark-shell/config"
cd "$HOME"; P=$HOME/proof; mkdir -p "$P"
sh "$REPO/spark-shell" on --yes > on.out 2>&1 || { tail -20 on.out; exit 1; }
grep -i 'dialog' on.out | head -3
sh "$REPO/spark-shell" check 2>/dev/null | grep -i dialog || :
dbus-daemon --session --fork --print-address=1 --print-pid=1 > bus.out
DBUS_SESSION_BUS_ADDRESS=$(sed -n 1p bus.out); export DBUS_SESSION_BUS_ADDRESS
sway -c "$HOME/.config/sway/config" > sway.log 2>&1 &
sock=''; for _ in $(seq 15); do sock=$(ls "$XDG_RUNTIME_DIR"/sway-ipc.*.sock 2>/dev/null | head -1); [ -z "$sock" ] || break; sleep 1; done
export SWAYSOCK=$sock
for w in "$XDG_RUNTIME_DIR"/wayland-[0-9]*; do [ -S "$w" ] && { WAYLAND_DISPLAY=${w##*/}; break; }; done; export WAYLAND_DISPLAY
swaymsg "output $(swaymsg -t get_outputs | jq -r '.[0].name') resolution 1920x1080" >/dev/null
pidf=$HOME/.local/state/spark-shell/bar.pid
for _ in $(seq 20); do [ -s "$pidf" ] && makoctl mode >/dev/null 2>&1 && break; sleep 1; done
sleep 2
bp=$(cat "$pidf"); echo "bar pid $bp: $(tr '\0' ' ' < /proc/$bp/cmdline)"
click() {   # click: one left click on the notifications block, into the bar's stdin (the pipe swaybar writes)
    printf ',{"name":"notifications","instance":"count","button":1,"x":1500,"y":10,"relative_x":4,"relative_y":10,"width":30,"height":20}\n' > "/proc/$bp/fd/0"
}
dialogs() { swaymsg -t get_tree | jq -r '[.. | objects | select(.app_id? == "spark-dialog")] | length'; }
notes() { for n in 1 2 3; do notify-send -a aerc "mail $n" "words $n"; done; sleep 1; makoctl dismiss -a; kill -USR1 "$bp"; sleep 2; }
count() { sh "$REPO/spark-shell" bar status --once | jq -r '[.[] | select(.name == "notifications") | .full_text | gsub("<[^>]*>"; "")] | join(" ")'; }

echo "== case A: no home open"
notes; echo "before: count '$(count)', dialogs $(dialogs)"
click; sleep 6
echo "after:  count '$(count)', dialogs $(dialogs)"
grim "$P/a-after-click.png"; ps -eo pid,args | grep -E 'home.py|spark-dialog|dialog notifications' | grep -v grep || :
echo "== case B: home open already, at its root"
swaymsg '[app_id="spark-dialog"] kill' >/dev/null 2>&1 || :; sleep 2
sh "$REPO/spark-shell" desktop home > "$HOME/desktop-home.out" 2>&1 &
for _ in $(seq 40); do [ "$(dialogs)" = 1 ] && break; sleep 1; done; sleep 4
echo "home open: dialogs $(dialogs)"; echo "desktop home said: $(cat "$HOME/desktop-home.out")"; grim "$P/b-home-root.png"
notes; echo "before: count '$(count)'"
click; sleep 3
echo "goto file left: $(ls $XDG_RUNTIME_DIR/spark-home.goto 2>/dev/null || echo none)"
echo "after:  count '$(count)', dialogs $(dialogs)"
grim "$P/b-after-click.png"
swaymsg exit >/dev/null 2>&1 || :
