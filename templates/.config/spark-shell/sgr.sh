# rendered by spark-shell from templates/.config/spark-shell/sgr.sh -- edit the template, then spark-shell on
# spark's prompt colours: three SGR parameter strings from the palette
# (30-37 and 90-97, bold only). spark reads them at a terminal for its
# hint row, the chat prompt and the steps of spark do. Unset means no
# colour.
export SPARK_ACCENT_SGR='1;@ACCENT_SGR@' SPARK_MUTED_SGR='@MUTED_SGR@' SPARK_WARN_SGR='1;31'
