# rendered by spark-shell from templates/.config/spark-shell/sgr.sh -- edit the template, then spark-shell on
# spark's prompt marks: three SGR parameter strings from the palette
# slots (30-37 and 90-97, bold only). spark reads them at a tty for the
# hint row's mark, the chat prompt and the steps of spark do. Unset
# means plain.
export SPARK_ACCENT_SGR='1;@ACCENT_SGR@' SPARK_MUTED_SGR='@MUTED_SGR@' SPARK_WARN_SGR='1;31'
