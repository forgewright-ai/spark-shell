# Read the validated theme.env produced by palette_render.
BEGIN { split("black red green yellow blue magenta cyan white", names, " ") }
/^THEME_(BG|FG|ACCENT|MUTED|ANSI_[0-9]+)=/ {
    if (format == "env") print
    split($0, entry, "=")
    value[substr(entry[1], 7)] = entry[2]
}
END {
    if (format == "env") exit
    print "# " theme " - spark-shell"
    print "# accent " value["ACCENT"] " / muted " value["MUTED"]
    if (format == native) {
        print "[" section "]"
        print "background=" substr(value["BG"], 2)
        print "foreground=" substr(value["FG"], 2)
    } else if (format == "alacritty") {
        print "[colors.primary]"
        print "background = \"" value["BG"] "\""
        print "foreground = \"" value["FG"] "\""
    } else {
        sep = (format == "kitty" ? " " : " = ")
        print "background" sep value["BG"]
        print "foreground" sep value["FG"]
    }
    for (i = 0; i < 16; i++) {
        rgb = value["ANSI_" i]
        if (format == native) print (i < 8 ? "regular" : "bright") (i % 8) "=" substr(rgb, 2)
        else if (format == "kitty") print "color" i " " rgb
        else if (format == "ghostty") print "palette = " i "=" rgb
        else {
            if (i == 0 || i == 8) print (i == 0 ? "\n[colors.normal]" : "\n[colors.bright]")
            print names[i % 8 + 1] " = \"" rgb "\""
        }
    }
}
