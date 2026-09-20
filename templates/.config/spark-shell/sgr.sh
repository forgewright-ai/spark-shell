# rendered by spark-shell from templates/.config/spark-shell/sgr.sh -- edit the template, then spark-shell apply
# spark's prompt colour: three SGR parameter strings from the palette
# slots (30-37, 90-97; bold only), read by spark at a tty -- the hint
# row's mark, chat's prompt, do's steps. Unset = plain.
export SPARK_ACCENT_SGR='1;@ACCENT_SGR@' SPARK_MUTED_SGR='@MUTED_SGR@' SPARK_WARN_SGR='1;31'
