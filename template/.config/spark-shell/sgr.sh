# rendered by spark-shell from templates/.config/spark-shell/sgr.sh -- edit the template, then spark-shell on
# spark's prompt colors: three SGR parameter strings from the palette,
# bold only. spark reads them at a terminal for its hint row, the chat
# prompt and the steps of spark do. In a terminal window of the desktop
# (foot, with spark-shell's foot.ini) the accent and the muted color are
# the slots 16 and 17, which a theme change recolors in place, text on
# screen too (#34); anywhere else, the nearest of the sixteen (30-37,
# 90-97). Unset means no color.
case ${TERM:-}:@DESK_SLOTS@ in
    foot*:yes) export SPARK_ACCENT_SGR='1;38;5;16' SPARK_MUTED_SGR='38;5;17'
        [ ! -r "$HOME/.config/starship-foot.toml" ] || export STARSHIP_CONFIG="$HOME/.config/starship-foot.toml" ;;
    *) export SPARK_ACCENT_SGR='1;@ACCENT_SGR@' SPARK_MUTED_SGR='@MUTED_SGR@' ;;
esac
export SPARK_WARN_SGR='1;31'
