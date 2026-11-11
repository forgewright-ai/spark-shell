# shellcheck extended-analysis=false
# --- the providers
# sets: PROVIDE_CLIENT PROVIDE_LINE_MAX PROVIDE_PROTOCOL PROVIDE_SECTIONS PROVIDE_TOOLS SCRUB_JQ
# reads: ANIMATION_NAMES DESK_LAST KEPT_LAYOUTS LAYOUTS_DIR PANEL_CROSS PANEL_DOT PANEL_GO PANEL_RING PANEL_SEP PANEL_TICK REPO SAVER_NAMES TAB THUMB_DIR TMP US WALL_TYPES
# a section as an MCP server on stdio, JSON-RPC a line. Every JSON value
# is built by jq with --arg, every request is parsed by jq; a method or a
# tool name is matched by case, never run as a name
PROVIDE_PROTOCOL=2025-06-18
PROVIDE_SECTIONS="lan wifi bt printers out mic bat clock theme window display keyboard pointer notifications storage power notes reminders bar layout apps tools about undo files"   # every panel section but spark, and files
PROVIDE_LINE_MAX=65536    # a request longer than this is refused whole
PROVIDE_TOOLS="printers_default printers_pause printers_resume printers_cancel clock_format clock_week clock_zone wifi_connect wifi_disconnect wifi_forget bt_connect bt_disconnect bt_pair bt_remove bt_scan bt_power out_use out_level out_adjust out_mute out_unmute mic_use mic_level mic_adjust mic_mute mic_unmute theme_palette theme_save theme_delete theme_back theme_text theme_transparency theme_preview theme_animation theme_glyphs theme_icons theme_spacing theme_family theme_face theme_motion theme_alpha theme_wallpaper theme_wallpaper_color theme_wallpaper_picture theme_picture theme_words window_split window_tabs window_stacked window_restore window_move window_place window_focus window_close window_capture notes_new notes_open notes_add notes_append notes_find notes_rename notes_trash notes_restore reminders_add reminders_done reminders_snooze reminders_restore reminders_delete display_idle display_lock display_saver display_brightness display_scale display_mode display_position display_place display_transform display_main display_on display_off keyboard_use keyboard_next keyboard_repeat_delay keyboard_repeat_rate keyboard_caps pointer_tap pointer_scroll pointer_speed notifications_do_not_disturb notifications_dismiss notifications_restore storage_mount storage_unmount storage_open storage_eject power_lock power_suspend power_logout power_restart power_shutdown bar_on bar_off bar_top bar_bottom bar_text bar_tray layout_open layout_new layout_save layout_add layout_delete layout_restore layout_rename layout_back apps_open apps_terminal about_open about_site undo_all files_browse files_open files_app files_show files_attach files_reveal files_rename files_move files_copy files_trash files_restore files_purge files_empty files_new_folder files_new_text files_find files_say files_play files_stop lan_address lan_auto lan_dns lan_restore wifi_address wifi_auto wifi_dns wifi_restore wifi_setup wifi_hidden tools_check tools_fix tools_copy_details tools_update tools_update_system tools_export tools_front tools_end tools_measure tools_clean_packages"
# the scrubber for every string a provider hands on: what can redraw or
# reorder a screen goes
#   C0 but the tab, DEL and C1            \u0000-\u0008 \u000b-\u001f \u007f-\u009f
#   the bidi controls                     \u200e \u200f \u202a-\u202e \u2066-\u2069
#   the zero-width set                    \u200b-\u200d \u2060 \ufeff
#   the line and paragraph separators     \u2028 \u2029
SCRUB_JQ='gsub("[\u0000-\u0008\u000b-\u001f\u007f-\u009f\u200e\u200f\u202a-\u202e\u2066-\u2069\u200b-\u200d\u2060\ufeff\u2028\u2029]"; "")'
scrub_plain() {   # scrub_plain WORDS -> them scrubbed; printable ASCII as it is, no process
    case $1 in *[!\ -~]*) printf '%s' "$1" | scrub_text ;; *) printf '%s' "$1" ;; esac
}
tool_args_json() {   # tool_args_json TOOL VALUE -> the call's arguments as JSON; a plain value without jq
    tool_spec "$1" || return 1
    if [ -z "$_tp" ]; then printf '{}'; return 0; fi
    case $_tk:$_te in level:|delta:|alpha:|minutes:|speed:|delay:)   # a plain number is written here, no jq
        case $2 in ''|*[!0-9.-]*|?*-*|*.*.*|-|.|*.|.*|-.*|0[0-9]*|-0[0-9]*) ;; *) printf '{"%s":%s}' "$_tp" "$2"; return 0 ;; esac ;;
    esac
    case $_tk:$_te:$2 in level:*|delta:*|alpha:*|minutes:*|speed:*|delay:*|*:?*:*) ;; *:*:*[!A-Za-z0-9._:+-]*) ;; *) printf '{"%s":"%s"}' "$_tp" "$2"; return 0 ;; esac
    tool_call_json "$1" "$2" | jq -c .arguments
}
scrub_text() {   # stdin -> the same lines scrubbed; C0 and DEL alone where there is no jq
    if command -v jq >/dev/null 2>&1; then jq -Rr "$SCRUB_JQ" 2>/dev/null || :; else tr -d '\000-\010\013-\037\177'; fi
}

# tool_spec NAME -> _ts the section, _ta the panel's action (= takes the
# argument itself), _tp the argument, _tk its kind (string, level 0-100,
# bright, alpha 0-1, a|b a closed set), _tw what it says when asked for,
# _tq a secret argument, _te the extras (NAME:KIND, NAME? optional), _th
# the hints (r read only, d destructive, i idempotent, f free: names no
# row, o opens a window, p a person's step: a terminal or sudo, from its
# row alone), _tt the title, _td the words for a person; false for no tool
tool_spec() {
    _tp=''; _tk=''; _tq=''; _tw=''; _te=''
    case $1 in
        lan_address|wifi_address) _ts=${1%%_*} _ta=address _tp=device _tk=string _te='address:net gateway:net' _th=f _tt="$_ts address DEVICE" _td='Set a fixed IPv4 address with prefix and gateway (or none) through the active native manager. The connection may drop.' ;;
        lan_auto|wifi_auto) _ts=${1%%_*} _ta=auto _tp=device _tk=string _th=f _tt="$_ts auto DEVICE" _td='Use an automatic IPv4 address through the active native manager. The connection may drop.' ;;
        lan_dns|wifi_dns) _ts=${1%%_*} _ta=dns _tp=device _tk=string _te='servers:net' _th=f _tt="$_ts dns DEVICE" _td='Set IPv4 DNS servers (comma separated), or auto for the native default.' ;;
        lan_restore|wifi_restore) _ts=${1%%_*} _ta=restore _tp=receipt _tk=string _th=f _tt="$_ts restore RECEIPT" _td='Restore the native IPv4 settings from a network undo receipt, unless they changed since.' ;;
        wifi_setup)        _ts=wifi _ta=setup _th=d _tt='wifi setup' _td='Install and enable the native network manager only when none is already installed or configured.' ;;
        wifi_hidden)       _ts=wifi _ta=hidden _tp=name _tk=string _tq=password _th=if _tt='wifi hidden NAME' _td='Join a hidden network by its exact name. An empty password is an open network.' ;;
        wifi_connect)      _ts=wifi _ta=connect _tp=name _tk=string _tq=password _th=i _tt='wifi connect NAME' _td='Connect to a network around, or a saved one.' ;;
        wifi_disconnect)   _ts=wifi _ta=disconnect _th=i _tt='wifi disconnect' _td='Leave the network in use.' ;;
        wifi_forget)       _ts=wifi _ta=forget _tp=name _tk=string _th=di _tt='wifi forget NAME' _td='Forget a saved network and its password.' ;;
        printers_default) _ts=printers _ta=default _tp=name _tk=string _th=i _tt='printers default NAME' _td='Choose a configured native printer as the default.' ;;
        printers_pause) _ts=printers _ta=pause _tp=name _tk=string _th=i _tt='printers pause NAME' _td='Pause the configured print queue; resume takes it back. Native administrative permission may be needed.' ;;
        printers_resume) _ts=printers _ta=resume _tp=name _tk=string _th=i _tt='printers resume NAME' _td='Enable the configured print queue. Pending jobs may print.' ;;
        printers_cancel) _ts=printers _ta=cancel _tp=job _tk=string _th=d _tt='printers cancel JOB' _td='Cancel one pending job owned by the current user. The job cannot be restored.' ;;
        bt_connect)        _ts=bt _ta=connect _tp=name _tk=string _th=i _tt='bt connect NAME' _td='Connect a paired device.' ;;
        bt_disconnect)     _ts=bt _ta=disconnect _tp=name _tk=string _th=i _tt='bt disconnect NAME' _td='Disconnect a device.' ;;
        bt_remove)         _ts=bt _ta=remove _tp=name _tk=string _th=id _tt='bt remove NAME' _td='Remove a paired device and its saved trust. Pair it again to reconnect.' ;;
        bt_pair)           _ts=bt _ta=pair _tp=name _tk=string _th='' _tt='bt pair NAME' _td='Pair a new device and connect it.' ;;
        bt_scan)           _ts=bt _ta=scan _th='' _tt='bt scan' _td='Look for new devices nearby.' ;;
        bt_power)          _ts=bt _ta=power _tp=state _tk='on|off' _th=i _tt='bt power STATE' _td='Turn Bluetooth on or off.' ;;
        out_use)           _ts=out _ta=use _tp=name _tk=string _th=i _tt='out use NAME' _td='Play the sound on another output.' ;;
        out_level)         _ts=out _ta=level _tp=level _tk=level _th=if _tt='out level N' _td='Set the volume, 0 to 100. Native readback must match within one percentage point for mixer rounding; the result reports the actual level.' ;;
        out_adjust)        _ts=out _ta=adjust _tp=delta _tk=delta _th=f _tt='out adjust DELTA' _td='Change the volume by delta percentage points from its fresh native level. Negative lowers and positive raises; the result is bounded to 0 to 100 and read back. Use this for relative requests; no arithmetic from a remembered level is needed.' ;;
        out_mute)          _ts=out _ta=mute _th=if _tt='out mute' _td='Mute the sound.' ;;
        out_unmute)        _ts=out _ta=unmute _th=if _tt='out unmute' _td='Unmute the sound.' ;;
        mic_use)           _ts=mic _ta=use _tp=name _tk=string _th=i _tt='mic use NAME' _td='Listen on another microphone.' ;;
        mic_level)         _ts=mic _ta=level _tp=level _tk=level _th=if _tt='mic level N' _td='Set the microphone level, 0 to 100. Native readback must match within one percentage point for mixer rounding; the result reports the actual level.' ;;
        mic_adjust)        _ts=mic _ta=adjust _tp=delta _tk=delta _th=f _tt='mic adjust DELTA' _td='Change the microphone level by delta percentage points from its fresh native level. Negative lowers and positive raises; the result is bounded to 0 to 100 and read back. Use this for relative requests; no arithmetic from a remembered level is needed.' ;;
        mic_mute)          _ts=mic _ta=mute _th=if _tt='mic mute' _td='Mute the microphone.' ;;
        mic_unmute)        _ts=mic _ta=unmute _th=if _tt='mic unmute' _td='Unmute the microphone.' ;;
        theme_palette)     _ts=theme _ta='=' _tp=name _tk=${THEME_ENUM_NOW:-$(theme_enum)} _th=i _tt='theme NAME' _td='Use a palette everywhere, a saved theme, a look from the last ten, or none. A near name, heard or typed, is the nearest palette: groove box dark is gruvbox-dark.' ;;
        theme_save)        _ts=theme _ta=save _tp=name _tk=string _th=f _tt='theme save NAME' _td='Keep the look in use under a name: the palette, the wallpaper, the face and its size, the glyph family, the animation, the transparency. After the look is made, never before it.' ;;
        theme_delete)      _ts=theme _ta=delete _tp=name _tk=string _th=dif _tt='theme delete NAME' _td='Delete a saved theme.' ;;
        theme_back)        _ts=theme _ta=back _th=f _tt='theme back' _td='The look before this one.' ;;   # free: no row carries it, the gate asks the history
        theme_text)        _ts=theme _ta=text _tp=size _tk='bigger|smaller|6|7|8|9|10|11|12|13|14|15|16|17|18|19|20|21|22|23|24|25|26|27|28|29|30|31|32|33|34|35|36|37|38|39|40' _th='' _tt='theme text SIZE' _td='The text one size bigger or smaller, or a size from 6 to 40, on every surface.' ;;
        theme_wallpaper)   _ts=theme _ta=wallpaper _tp=name _tk=string _th=i _tt='theme wallpaper NAME' _td='The wallpaper: one of the drawings, or default (the ground, the palette a shade darker).' ;;
        theme_wallpaper_color) _ts=theme _ta=wallpaper-color _tp=color _tk=string _th=if _tt='theme wallpaper color COLOR' _td='A plain color as the wallpaper: a name (teal, navy, olive, maroon...) or #rrggbb.' ;;
        theme_wallpaper_picture) _ts=theme _ta=wallpaper-picture _tp=path _tk=path _th=if _tt='theme wallpaper picture PATH' _td='A picture of yours as the wallpaper.' ;;
        theme_picture)     _ts=theme _ta=picture _tp=path _tk=path _te="face?:$(look_pick_list face) family?:$(look_pick_list family) animation?:$(look_pick_list animation)" _th=f _tt='theme picture PATH' _td='A theme from a picture of yours: its colors as the palette, the picture as the wallpaper; the face, the glyph family and the animation when the words ask for them (as theme words takes them), else the face and the family in use and the animation the colors suggest.' ;;
        theme_words)       _ts=theme _ta=words _tp=hue _tk='red|orange|yellow|green|teal|blue|violet|pink|grey' _te="accent:red|orange|yellow|green|teal|blue|violet|pink|grey|same warmth:warm|neutral|cool contrast:soft|normal|high light:dark|light face:$(look_pick_list face) family:$(look_pick_list family) animation:$(look_pick_list animation) drawing:$(look_pick_list drawing) name:text" _th=f _tt='theme words HUE' _td='One whole look for one request: the hue of the ground, the hue of the accent (same when the words name one color), how warm, how much contrast, dark or light; then the parts that fit the words, each weighed, none by habit. face: neon for plain and modern, argon for soft and friendly, xenon for bookish and old, radon for handwritten and playful, krypton for technical and retro. family: star for night skies, space, magic and fine light looks; banner for bold, old, heraldic, sporty or retro looks; stone for calm, plain and solid ones. animation: moon for night, ripple for water and calm, tide for the sea, embers for fire, warmth and autumn, sun for day and summer, flight for wind, sky and spring. drawing: the scene closest to the words. And a short name from the words. A flag or a brand is one step with two hues, never two steps. A picture of yours as the wallpaper stays.' ;;
        theme_animation)   _ts=theme _ta=animation _tp=to _tk="next|back|none|$(printf '%s' "$ANIMATION_NAMES" | tr ' ' '|')" _th='' _tt='theme animation NAME' _td='The dialog'"'"'s animation as it opens, waits and closes: one by name, none for no motion, or the next or the one before.' ;;
        theme_glyphs)      _ts=theme _ta=glyphs _tp=to _tk='signs|words' _th='' _tt='theme glyphs SET' _td='The bar in signs (the default) or in words.' ;;
        theme_icons)       _ts=theme _ta=icons _tp=to _tk='on|off' _th='' _tt='theme icons ON' _td='Each app shows its icon before its name in home (on, the default), or the names alone.' ;;
        theme_spacing)     _ts=theme _ta=spacing _tp=to _tk='none|groups|rows' _th='' _tt='theme spacing SET' _td='The space around the apps in home where they show icons: none, around the categories (groups, the default), or between the apps too (rows).' ;;
        theme_face)        _ts=theme _ta=face _tp=to _tk='neon|argon|xenon|radon|krypton' _th='' _tt='theme face NAME' _td='The text'"'"'s face, one of Monaspace'"'"'s five, at the size it has: neon (the default), argon, xenon, radon or krypton.' ;;
        theme_family)      _ts=theme _ta=family _tp=to _tk='stone|star|banner' _th='' _tt='theme family NAME' _td='The glyph family: the signs of the dialog, the bar'"'"'s gauges and workspaces, and the animations while it waits. stone (the default), star or banner.' ;;
        theme_motion)      _ts=theme _ta=motion _tp=to _tk='on|off' _th='' _tt='theme motion ON' _td='The wallpaper moving (on), where the drawing has a motion, or still (off, the default).' ;;
        theme_transparency) _ts=theme _ta=transparency _tp=amount _tk='more|less|0|1|2|3|4|5|6|7|8|9|10|11|12|13|14|15|16|17|18|19|20|21|22|23|24|25|26|27|28|29|30|31|32|33|34|35|36|37|38|39|40|41|42|43|44|45|46|47|48|49|50' _th='' _tt='theme transparency AMOUNT' _td='The windows more or less transparent, or a percent from 0 (off) to 50.' ;;
        theme_preview)     _ts=theme _ta=preview _tp=name _tk="${THEME_ENUM_NOW:-$(theme_enum)}|off" _th='' _tt='theme preview NAME' _td='A palette on the screen while it is looked at, nothing kept; off puts the one in use back.' ;;
        theme_alpha)       _ts=theme _ta=alpha _tp=value _tk=alpha _th=if _tt='theme alpha N' _td='How solid the windows are, 0 to 1.' ;;
        window_split)      _ts=window _ta=split _th=if _tt='window split' _td='Windows side by side, on this workspace now and on every new one.' ;;
        window_tabs)       _ts=window _ta=tabs _th=if _tt='window tabs' _td='Windows in tabs, on this workspace now and on every new one.' ;;
        window_stacked)    _ts=window _ta=stacked _th=if _tt='window stacked' _td='Windows stacked, on this workspace now and on every new one.' ;;
        window_restore)    _ts=window _ta=restore _tp=to _tk='split|tabs|stacked' _te='now:text' _th=if _tt='window restore TO' _td='The default and this workspace as they were: the undo of an arrangement.' ;;
        window_move)       _ts=window _ta=move _tp=name _tk=string _te='to:text' _th=if _tt='window move NAME' _td='Move one open window to a workspace, by its native container ID from the row. The to argument is the workspace number.' ;;
        window_place)      _ts=window _ta=place _tp=name _tk=string _te='how:text' _th=if _tt='window place NAME' _td='How one open window sits, by its native container ID from the row. The how argument is tiled, floating, full, left, right, up or down.' ;;
        window_focus)      _ts=window _ta=focus _tp=name _tk=string _th=io _tt='window focus NAME' _td='Put one open window in front. Use its native container ID from the row, not its display label.' ;;
        window_close)      _ts=window _ta=close _tp=name _tk=string _th=d _tt='window close NAME' _td='Close one open window by its native container ID from the row. It cannot be undone.' ;;
        window_capture)    _ts=window _ta=capture _tp=what _tk='screen|area|window' _te='name:text' _th=f _tt='window capture WHAT' _td='A picture of the screen, of an area you drag, or of a window, in ~/pictures/screenshots. The name argument is the window by its native container ID; with none, the window in front.' ;;
        notes_new)         _ts=notes _ta=new _th='' _tt='notes new' _td='Open a blank note in the editor for the person to write. No supplied text is saved.' ;;
        notes_open)        _ts=notes _ta=open _tp=name _tk=string _th=o _tt='notes open NAME' _td='Only open a note in the editor; this does not append or save supplied text. To append text, use notes_append. Use the filename from the row; duplicate titles are not identities.' ;;
        notes_add)         _ts=notes _ta=add _tp=text _tk=string _th=f _tt='notes add TEXT' _td='Create a new note: text is the literal heading, never an invented filename or filename prefix. The result gives the actual filename. To add a body or append to an existing note, use notes_append with that filename and separate text. The legacy NAME: TEXT syntax still appends when NAME already exists.' ;;
        notes_append)      _ts=notes _ta=append _tp=name _tk=string _th=f _tt='notes append NAME' _td='Append a bullet to an existing note. name is its exact filename from the row or a prior result, never a guessed title or a new filename. text is saved verbatim inside the bullet, including spaces and line breaks; a final newline follows. This saves text without opening an editor.' ;;
        notes_find)        _ts=notes _ta=find _tp=words _tk=string _th=rf _tt='notes find WORDS' _td='Which notes say these words, and the line that does.' ;;
        notes_rename)      _ts=notes _ta=rename _tp=name _tk=string _th='' _tt='notes rename NAME' _td='Give a note a new title, its first line. name is its exact filename from the row; to is the new title. Undo puts the old title back.' ;;
        notes_trash)       _ts=notes _ta=trash _tp=name _tk=string _th='' _tt='notes trash NAME' _td='Put a note in the trash. name is its exact filename from the row. Undo brings it back.' ;;
        notes_restore)     _ts=notes _ta=restore _tp=name _tk=string _th=f _tt='notes restore NAME' _td='Bring a note put in the trash back, by its filename.' ;;
        reminders_add)     _ts=reminders _ta=add _tp=words _tk=string _tw='when and what: fri 9am call the vet' _th=f _tt='reminders add WORDS' _td='Save a reminder at a local time to come. words: a day and a time then the title (tomorrow 09:00 call the dentist), a time alone for today or else tomorrow (5pm gym), or in N minutes or hours before or after the title. Keep the words as the person said them; never invent a time. With no time in the words the provider asks for one.' ;;
        reminders_done)    _ts=reminders _ta='done' _tp=name _tk=string _th='' _tt='reminders done NAME' _td='Put aside one due or future reminder by its UID from the row. Undo brings that exact event back for 30 days.' ;;
        reminders_delete)  _ts=reminders _ta=delete _tp=name _tk=string _th='' _tt='reminders delete NAME' _td='Delete one reminder by its UID from the row: the event goes. Undo brings it back while this window is open.' ;;
        reminders_restore) _ts=reminders _ta=restore _tp=name _tk=string _th=f _tt='reminders restore NAME' _td='Bring back a reminder marked done in the last 30 days.' ;;
        reminders_snooze)  _ts=reminders _ta=snooze _tp=name _tk=string _th='' _tt='reminders snooze NAME' _td='Move one reminder, identified by its UID from the row, to 10 minutes from now.' ;;
        display_idle)      _ts=display _ta=idle _tp=minutes _tk=minutes _th=i _tt='display idle N' _td='Show the idle screen after N idle minutes; 0 never.' ;;
        display_lock)      _ts=display _ta=lock _tp=minutes _tk=minutes _th=i _tt='display lock N' _td='Lock the screen and turn the display off after N idle minutes; 0 never.' ;;
        display_saver)     _ts=display _ta=saver _tp=name _tk="clock|$(printf '%s' "$SAVER_NAMES" | tr ' ' '|')" _th=i _tt='display saver NAME' _td='What the idle screen shows: the clock alone, or an animation behind it.' ;;
        display_brightness) _ts=display _ta=brightness _tp=level _tk=bright _th=if _tt='display brightness N' _td='Set the screen brightness, 1 to 100, or up or down a step.' ;;
        display_scale) _ts=display _ta=scale _tp=screen _tk=string _te='scale:scale' _th=if _tt='screen scale' _td='Set the scale on one connected screen; larger means larger text.' ;;
        display_mode) _ts=display _ta=mode _tp=screen _tk=string _te='mode:mode' _th=if _tt='screen mode' _td='Set one of the resolutions offered by the connected screen.' ;;
        display_position) _ts=display _ta=position _tp=screen _tk=string _te='x:coordinate y:coordinate' _th=if _tt='screen position' _td='Place a connected screen at absolute layout coordinates.' ;;
        display_place) _ts=display _ta=place _tp=screen _tk=string _te='side:left-of|right-of|above|below other:port' _th=if _tt='screen arrangement' _td='Place a connected screen beside another active screen.' ;;
        display_transform) _ts=display _ta=transform _tp=screen _tk=string _te='transform:normal|90|180|270' _th=if _tt='screen orientation' _td='Turn a connected screen: normal, or 90, 180 or 270 degrees clockwise. No mirrored orientation.' ;;
        display_main) _ts=display _ta=main _tp=screen _tk=string _th=if _tt='screen main' _td='Make a connected screen the main one: workspace 1, the focus at the start and the login screen go to it.' ;;
        display_on) _ts=display _ta=screen-on _tp=screen _tk=string _th=if _tt='screen on' _td='Enable a connected screen now and at the next login.' ;;
        display_off) _ts=display _ta=screen-off _tp=screen _tk=string _th=if _tt='screen off' _td='Disable a connected screen now and at the next login; the last active screen stays on.' ;;
        clock_format) _ts=clock _ta=format _tp=format _tk='12|24' _th=if _tt='clock format' _td='Show a 12 or 24 hour clock on the bar, Calendar and idle screen.' ;;
        clock_week) _ts=clock _ta=week _tp=day _tk='sunday|monday' _th=if _tt='first weekday' _td='Start the Calendar week on Sunday or Monday.' ;;
        clock_zone) _ts=clock _ta=zone _tp=zone _tk=string _th=if _tt='time zone' _td='Change the machine time zone through its native settings; undo puts the one before back. Requires system permission.' ;;
        keyboard_use)      _ts=keyboard _ta=use _tp=name _tk=string _th=i _tt='keyboard use NAME' _td='Type in another of the keyboard layouts.' ;;
        pointer_tap)       _ts=pointer _ta=tap _tp=state _tk='on|off' _th=if _tt='pointer tap STATE' _td='Enable or disable tap to click on touchpads.' ;;
        pointer_scroll)    _ts=pointer _ta=scroll _tp=state _tk='on|off' _th=if _tt='pointer scroll STATE' _td='Set natural scrolling for mouse and touchpad.' ;;
        pointer_speed)     _ts=pointer _ta=speed _tp=value _tk=speed _th=if _tt='pointer speed N' _td='Set mouse and touchpad acceleration, -1 to 1; 0 is the default.' ;;
        keyboard_repeat_delay) _ts=keyboard _ta=repeat-delay _tp=value _tk=delay _th=if _tt='keyboard repeat-delay N' _td='Milliseconds before a held key repeats, 100 to 2000.' ;;
        keyboard_repeat_rate) _ts=keyboard _ta=repeat-rate _tp=value _tk=level _th=if _tt='keyboard repeat-rate N' _td='Key repeats per second, 0 to 100; 0 disables repeat.' ;;
        keyboard_caps)     _ts=keyboard _ta=caps _tp=key _tk='caps|control|escape' _th=if _tt='keyboard caps KEY' _td='Use Caps Lock as itself, Control or Escape.' ;;
        keyboard_next)     _ts=keyboard _ta=next _th='' _tt='keyboard next' _td='Go to the next keyboard layout.' ;;
        notifications_do_not_disturb) _ts=notifications _ta=do-not-disturb _tp=state _tk='on|off' _th=if _tt='notifications do-not-disturb STATE' _td='Keep notifications out of sight, or show them again; a critical one always shows.' ;;
        notifications_dismiss) _ts=notifications _ta=dismiss _th=i _tt='notifications dismiss' _td='Dismiss the notifications on the screen.' ;;
        notifications_restore) _ts=notifications _ta=restore _th='' _tt='notifications restore' _td='Show the last notification again.' ;;
        storage_mount)     _ts=storage _ta=mount _tp=name _tk=string _th=i _tt='storage mount NAME' _td='Mount a drive that is plugged in.' ;;
        storage_unmount)   _ts=storage _ta=unmount _tp=name _tk=string _th=i _tt='storage unmount NAME' _td='Unmount a drive.' ;;
        storage_open)      _ts=storage _ta=open _tp=name _tk=string _th=fo _tt='storage open NAME' _td='Open a drive in the file manager, mounted first when it is not.' ;;
        storage_eject)     _ts=storage _ta=eject _tp=name _tk=string _th='' _tt='storage eject NAME' _td='Unmount every part of a drive and power it off, so it can be taken out.' ;;
        power_lock)        _ts=power _ta=lock _th=o _tt='power lock' _td='Lock the screen.' ;;
        power_suspend)     _ts=power _ta=suspend _th='' _tt='power suspend' _td='Lock the screen and suspend the machine. The answer comes when it wakes.' ;;
        power_logout)      _ts=power _ta=logout _th=d _tt='power logout' _td='Log out. Every window closes and the session ends.' ;;
        power_restart)     _ts=power _ta=restart _th=d _tt='power restart' _td='Restart the machine. Everything open closes and it starts again.' ;;
        power_shutdown)    _ts=power _ta=shutdown _th=d _tt='power shutdown' _td='Shut the machine down. Everything open closes and the machine turns off.' ;;
        bar_on)            _ts=bar _ta=on _th=i _tt='bar on' _td='Show the bar where it was, at the top or the bottom of the screen.' ;;
        bar_off)           _ts=bar _ta=off _th=i _tt='bar off' _td='Hide the bar.' ;;
        bar_top)           _ts=bar _ta=top _th=i _tt='bar top' _td='Show the bar at the top of the screen.' ;;
        bar_bottom)        _ts=bar _ta=bottom _th=i _tt='bar bottom' _td='Show the bar at the bottom of the screen.' ;;
        bar_text)          _ts=bar _ta=text _tp=size _tk='auto|bigger|smaller|6|7|8|9|10|11|12|13|14|15|16|17|18|19|20|21|22|23|24|25|26|27|28|29|30|31|32|33|34|35|36|37|38|39|40' _th='' _tt='bar text SIZE' _td='The text on the bar one size bigger or smaller, a size from 6 to 40, or auto: the text size, larger on a screen of many pixels.' ;;
        bar_tray)          _ts=bar _ta=tray _tp=state _tk='on|off' _th=i _tt='bar tray STATE' _td='Show the icons apps put in the tray at the end of the bar, or keep them off it; the apps run either way.' ;;
        layout_open)       _ts=layout _ta=open _tp=name _tk=string _th='' _tt='layout open NAME' _td='Open a saved layout.' ;;
        layout_new)        _ts=layout _ta=new _tp=words _tk=string _th=f _tt='layout new WORDS' _td='Open the apps for a task, picked by spark.' ;;
        layout_save)       _ts=layout _ta=save _tp=name _tk=string _th=f _tt='layout save NAME' _td='Save what is open on this workspace as a layout.' ;;
        layout_add)        _ts=layout _ta=add _tp=name _tk=string _th='' _tt='layout add NAME' _td='Open an app spark also suggested for the last layout.' ;;
        layout_delete)     _ts=layout _ta=delete _tp=name _tk=string _th=if _tt='layout delete NAME' _td='Delete a saved layout. Undo brings it back.' ;;
        layout_restore)    _ts=layout _ta=restore _tp=name _tk=string _th=f _tt='layout restore NAME' _td='A deleted layout, back.' ;;
        layout_rename)     _ts=layout _ta=rename _tp=name _tk=string _te='to:name' _th=f _tt='layout rename NAME' _td='Give a saved layout a new name.' ;;
        layout_back)       _ts=layout _ta=back _th=f _tt='layout back' _td='The layout before this one, opened again.' ;;
        apps_open)         _ts=apps _ta=open _tp=name _tk=string _th=o _tt='apps open NAME' _td='Open an app on this workspace.' ;;
        apps_terminal)     _ts=apps _ta=terminal _th=o _tt='apps terminal' _td='Open a terminal window.' ;;
        about_open)        _ts=about _ta=open _th=ri _tt='about' _td='The version, the project, the license and the credits.' ;;
        about_site)        _ts=about _ta=site _th=o _tt='about site' _td='Open the project page in the browser.' ;;
        tools_check)       _ts=tools _ta=check _th=rf _tt='tools check' _td='Run spark-shell check again and keep its result.' ;;
        tools_fix)         _ts=tools _ta=fix _tp=command _tk=string _th=ofp _tt='tools fix COMMAND' _td='Run a fix the last check gave, a spark-shell command, in a terminal window.' ;;
        tools_copy_details) _ts=tools _ta=copy-details _th=f _tt='tools copy details' _td='Copy the hardware and software details to the clipboard, for a bug report.' ;;
        tools_update)      _ts=tools _ta=update _th=ofp _tt='tools update' _td='Run spark-shell update in a terminal window.' ;;
        tools_update_system) _ts=tools _ta=update-system _th=ofp _tt='tools update system' _td='Run the system upgrade in a terminal window.' ;;
        tools_export)      _ts=tools _ta=export _th=f _tt='tools export' _td='Save the installed software as a CycloneDX file.' ;;
        tools_front)       _ts=tools _ta=front _tp=name _tk=string _th=of _tt='tools front NAME' _td='Put a running program'"'"'s newest window in front.' ;;
        tools_measure)     _ts=tools _ta=measure _th=rf _tt='tools measure' _td='Measure what uses the disk again: your home by folder, the trash, the package cache and the app caches.' ;;
        tools_clean_packages) _ts=tools _ta=clean-packages _th=ofp _tt='tools clean packages' _td='Run the package manager'"'"'s clean of its download cache in a terminal window.' ;;
        tools_end)         _ts=tools _ta=end _tp=name _tk=string _th=df _tt='end NAME' _td='End a program and all its processes. Unsaved work is lost.' ;;
        undo_all)          _ts=undo _ta=all _th='' _tt='undo' _td='Take the last thing done back.' ;;
        files_browse)      _ts=files _ta=browse _tp=path _tk=path _th=ifo _tt='files browse PATH' _td='Open a folder in the system file manager, for anything beyond the steps here. path is a row'"'"'s own path, exactly as written.' ;;
        files_open)        _ts=files _ta=open _tp=path _tk=path _th=ifo _tt='files open PATH' _td='Open a file with the app that opens its kind. path is a row'"'"'s own path, exactly as written.' ;;
        files_app)         _ts=files _ta=app _tp=path _tk=path _th=ifo _tt='files app PATH' _td='Open a file in the app the system assigns to its kind, a folder in the system file manager. path is a row'"'"'s own path, exactly as written.' ;;
        files_show)        _ts=files _ta=show _tp=path _tk=path _th=rif _tt='files show PATH' _td='The first lines of a text file. path is a row'"'"'s own path, exactly as written.' ;;
        files_play)        _ts=files _ta=play _tp=path _tk=path _te='at:seconds x:pixels y:pixels w:pixels h:pixels' _th='' _tt='files play PATH' _td='Play a sound here, with no window, from at seconds (the start when none), until it ends or files stop; a video over the box x, y, w, h of the dialog the preview drew it in. path is a row'"'"'s own path, exactly as written.' ;;
        files_stop)        _ts=files _ta=stop _th=i _tt='files stop' _td='Stop the sound files play started.' ;;
        files_attach)      _ts=files _ta=attach _tp=path _tk=path _th=rif _tt='files attach PATH' _td='A text file to ask spark about, with the next words. path is a row'"'"'s own path, exactly as written.' ;;
        files_reveal)      _ts=files _ta=reveal _tp=path _tk=path _th=ifo _tt='files reveal PATH' _td='Show a file or folder in the system file manager, its folder opened. path is a row'"'"'s own path, exactly as written.' ;;
        files_rename)      _ts=files _ta=rename _tp=path _tk=path _te='name:filename' _th='' _tt='files rename PATH' _td='Give a file or folder a new name, in its folder. path is a row'"'"'s own path, exactly as written; name the new name alone, no folder in it. Undo puts the old name back.' ;;
        files_move)        _ts=files _ta=move _tp=path _tk=path _te='to:path name?:filename there?:keep|replace' _th='' _tt='files move PATH' _td='Move a file or folder into another folder. path and to are rows'"'"' own paths, exactly as written; to is a folder; name, when given, is the name it takes there, one name alone. A name there already is refused; there is what to do when the name already exists: keep both, the new one named with a number (notes 2.md), or replace, the one there put in the trash first. Undo moves it back, under its old name.' ;;
        files_copy)        _ts=files _ta=copy _tp=path _tk=path _te='to:path name?:filename there?:keep|replace' _th='' _tt='files copy PATH' _td='Copy a file or folder into another folder. path and to are rows'"'"' own paths, exactly as written; to is a folder; name, when given, is the name it takes there, one name alone. A name there already is refused; there is what to do when the name already exists: keep both, the new one named with a number (notes 2.md), or replace, the one there put in the trash first. Undo trashes the copy.' ;;
        files_trash)       _ts=files _ta=trash _tp=path _tk=path _th='' _tt='files trash PATH' _td='Put a file or folder in the trash: the delete here. path is a row'"'"'s own path, exactly as written. Undo brings it back.' ;;
        files_restore)     _ts=files _ta=restore _tp=path _tk=path _te='item?:filename' _th=f _tt='files restore PATH' _td='Bring a file or folder back from the trash to the path it had: item, a trash row'"'"'s own, when given; else the newest the trash holds from path.' ;;
        files_purge)       _ts=files _ta=purge _tp=path _tk=path _te='item?:filename' _th=d _tt='files purge PATH' _td='Delete for good a file or folder in the trash: item, a trash row'"'"'s own, when given; else the newest the trash holds from path, the path it had. It cannot be brought back.' ;;
        files_empty)       _ts=files _ta=empty _th=d _tt='files empty' _td='Empty the trash of your home folder: every file and folder in it is deleted for good.' ;;
        files_new_folder)  _ts=files _ta=new-folder _tp=path _tk=path _te='name:filename' _th='' _tt='files new-folder PATH' _td='Make a folder inside the folder path names, with the name given. Undo trashes it.' ;;
        files_new_text)    _ts=files _ta=new-text _tp=path _tk=path _te='name:filename' _th='' _tt='files new-text PATH' _td='Make an empty text file inside the folder path names, with the name given, and open it in the editor. Undo trashes it.' ;;
        files_find)        _ts=files _ta=find _tp=words _tk=string _th=rf _tt='files find WORDS' _td='Which files and folders under your home and your drives have these words in their name; the list opens.' ;;
        files_say)         _ts=files _ta=say _tp=words _tk=string _th=rf _tt='files say WORDS' _td='Which text files under your home and your drives hold these words; the list opens.' ;;
        *) return 1 ;;
    esac
}
action_tool() {   # action_tool SECTION "ACTION [ARG]" -> _tool and _tv; false when no tool does that step
    _av=${2%% *}; _tv=''; [ "$_av" = "$2" ] || _tv=${2#* }
    case $1:$_av in apps:close|apps:focus) _tool=window_$_av; tool_spec "$_tool"; return ;; esac   # said of an app, done to its window
    _tool=${1}_$_av; while case $_tool in *-*) true ;; *) false ;; esac; do _tool=${_tool%%-*}_${_tool#*-}; done   # dashes as underscores, no process
    if tool_spec "$_tool" && [ "$_ts" = "$1" ] && [ "$_ta" = "$_av" ]; then return 0; fi
    [ "$1" = theme ] && [ -z "$_tv" ] && tool_spec theme_palette || return 1   # a palette's step is its name alone
    _tool=theme_palette; _tv=$_av
}
tool_call_json() {   # tool_call_json TOOL VALUE [LINE] -> {"name", "arguments", "line"}, VALUE typed as its kind (bright stays text)
    tool_spec "$1" || return 1
    jq -cn --arg n "$1" --arg p "$_tp" --arg k "$_tk" --arg v "$2" --arg l "${3:-}" --arg x "$_te" \
        '{name: $n, arguments: (if $p == "" then {} elif $x != "" then (($v | split(" ")) as $ws | {($p): $ws[0]} + ([$ws[1:][] | select(. != "") | split("=") | {(.[0]): (if .[0] == "x" or .[0] == "y" then (.[1] | tonumber) else .[1] end)}] | add // {}))
            elif ($k == "level" or $k == "delta" or $k == "alpha" or $k == "minutes" or $k == "speed" or $k == "delay") then {($p): ($v | tonumber? // $v)} else {($p): $v} end)} + (if $l == "" then {} else {line: $l} end)'
}
# bright is one string enum (spark types an argument one way); the tens
# come first, as spark's brief names an enum's first twelve
tool_json() {   # tool_json NAME -> the tool as tools/list says it
    tool_spec "$1" || return 1
    jq -cn --arg n "$1" --arg t "$_tt" --arg d "$_td" --arg p "$_tp" --arg k "$_tk" --arg q "$_tq" --arg w "$_tw" --arg h "$_th" --arg x "$_te" '
        ($x | split(" ") | map(select(. != "") | split(":") | [(.[0] | rtrimstr("?")), .[1], (.[0] | endswith("?"))])) as $xs |   # name, kind, may be left out
        {name: $n, title: $t, description: $d,
         inputSchema: {type: "object",
            properties: ((if $p == "" then {} else {($p): ((
                if $k == "level" then {type: "integer", minimum: 0, maximum: 100}
                elif $k == "delta" then {type: "integer", minimum: -100, maximum: 100}
                elif $k == "bright" then {type: "string", enum: (["up", "down"] + [range(10; 101; 10) | tostring] + [range(1; 101) | select(. % 10 != 0) | tostring])}
                elif $k == "minutes" then {type: "integer", minimum: 0, maximum: 999}
                elif $k == "speed" then {type: "number", minimum: -1, maximum: 1}
                elif $k == "delay" then {type: "integer", minimum: 100, maximum: 2000}
                elif $k == "alpha" then {type: "number", minimum: 0, maximum: 1}
                elif $k == "path" then {type: "string", minLength: 2, maxLength: 4096, format: "path"}
                elif ($k | contains("|")) then {type: "string", enum: ($k | split("|"))}
                else {type: "string", minLength: 1, maxLength: 256} end) + (if $w == "" then {} else {description: $w} end))} end)
              + (if $q == "" then {} else {($q): {type: "string", format: "password", maxLength: 256}} end)
              + ([$xs[] | {(.[0]): (if .[1] == "text" then {type: "string", maxLength: 40, description: "two or three words from the request"} elif .[1] == "coordinate" then {type: "integer", minimum: -65535, maximum: 65535} elif .[1] == "scale" then {type: "string", pattern: "^[0-9]+([.][0-9]+)?$", maxLength: 16} elif .[1] == "mode" then {type: "string", pattern: "^[0-9]{2,5}x[0-9]{2,5}(@[0-9]{1,4}([.][0-9]{1,3})?Hz)?$"} elif .[1] == "net" then {type: "string", pattern: "^[A-Za-z0-9.,:/-]{1,80}$", description: "IPv4 value; gateway may be none and DNS may be auto"} elif .[1] == "port" then {type: "string", pattern: "^[A-Za-z0-9_.:-]+$", maxLength: 80} elif .[1] == "name" then {type: "string", minLength: 1, maxLength: 40, description: "the new name"} elif .[1] == "filename" then {type: "string", minLength: 1, maxLength: 255, description: "one name, no slash"} elif .[1] == "path" then {type: "string", minLength: 2, maxLength: 4096, format: "path"} elif .[1] == "seconds" then {type: "number", minimum: 0, maximum: 86400, description: "where to start, in seconds"} elif .[1] == "pixels" then {type: "integer", minimum: 0, maximum: 65535, description: "pixels from the corner of the dialog"} else {type: "string", enum: (.[1] | split("|"))} end)}] | add // {})),
            required: ((if $p == "" then [] else [$p] end) + [$xs[] | select(.[1] != "text" and .[1] != "seconds" and .[1] != "pixels" and (.[2] | not)) | .[0]]), additionalProperties: false},
         outputSchema: {type: "object", properties: {receipt: {type: "string"}, opened: {type: "boolean"}, attach: {type: "string"}, open: {type: "string"}, rows: {type: "object"},
            effect: {type: "object", properties: {kind: {type: "string"}, operation: {type: "string"}, id: {type: "string"}, title: {type: "string"}, localTime: {type: "string"}, level: {type: "integer"}, muted: {type: "boolean"}}, required: ["kind", "operation", "id", "title"], additionalProperties: false},
            undo: {type: "object", properties: {name: {type: "string"}, arguments: {type: "object"}}, required: ["name", "arguments"]},
            palette: {type: "object", additionalProperties: {type: "string"}}, transitions: {type: "string"}},
            required: (if $n == "notes_add" or $n == "notes_append" or ($n | startswith("reminders_")) or ($n | test("^(out|mic)_(level|adjust|mute|unmute)$")) then ["receipt", "effect"] elif $n == "window_focus" or $n == "window_close" then ["effect"] else [] end), additionalProperties: false},
         annotations: {title: $t, readOnlyHint: ($h | contains("r")), destructiveHint: ($h | contains("d")), idempotentHint: ($h | contains("i")), openWorldHint: false}}
         | if ($h | contains("o")) then ._meta = {"spark-shell/opens": true} else . end
         | if ($h | contains("p")) then ._meta = ((._meta // {}) + {"spark-shell/person": true}) else . end
         | if $n == "notes_append" then .inputSchema = {type:"object", properties:{name:{type:"string", minLength:1, maxLength:255, description:"Exact existing Markdown filename"}, text:{type:"string", minLength:1, maxLength:16384, contentMediaType:"text/plain", description:"Text to append; spaces and line breaks are preserved"}}, required:["name","text"], additionalProperties:false} else . end
         | if $n == "notes_rename" then .inputSchema = {type:"object", properties:{name:{type:"string", minLength:1, maxLength:255, description:"Exact existing Markdown filename"}, to:{type:"string", minLength:1, maxLength:255, description:"the new title"}}, required:["name","to"], additionalProperties:false} else . end'
}
provide_tools() {   # provide_tools SECTION -> the section's tools as one JSON array; a person's step (p) to the dialog alone
    for _n in $PROVIDE_TOOLS; do tool_spec "$_n" && [ "$_ts" = "$1" ] && { provide_person_ok || case $_th in *p*) false ;; esac; } && tool_json "$_n"; done | jq -cs .
}
# a person's step (hint p) runs from its row in the dialog, never from a plan: another client neither sees
# nor calls it; a client with no name is the suite's raw requests and sees every tool
PROVIDE_CLIENT=''
provide_person_ok() { case $PROVIDE_CLIENT in ''|spark-dialog) return 0 ;; esac; return 1; }
provide_rows() {   # provide_rows SECTION -> the rows resource: {"title", "state", "rows": [{"id", "sign", "text", "tool", "more", "columns", "children", "group"}], "short": [ID]}; a tool may carry "ask", the arguments the host asks for
    [ "$1" != clock ] || [ "${2:-}" = settings ] || { provide_clock_rows; return; }
    [ "$1" != about ] || { provide_about_rows; return; }
    [ "$1" != tools ] || { provide_tools_rows; return; }
    [ "$1" != files ] || { provide_files_rows; return; }
    THEME_ENUM_NOW=''; [ "$1" != theme ] || THEME_ENUM_NOW=$(theme_enum)   # the palette names once for this read, not once a row
    WIFI_TOOL_READ=''; [ "$1" != wifi ] || { WIFI_TOOL_NOW=$(wifi_tool); WIFI_TOOL_READ=1; }   # the wifi manager once for this read
    ROWS_READ=$TMP/once; read_once_end   # asked once a read; none left from a read cut short
    _pr_keys='{}'; [ "$1" != window ] || _pr_keys=$(python3 "$REPO/lib/home.py" map "$REPO/template/.config/sway/config")
    case $1 in window|layout) win_facts > "$TMP/win.facts"; WIN_FACTS_READ=1 ;; esac   # the tree read once a read
    _pr_chips='{}'; _pr_size=''; _pr_anim=''; _pr_trn=0; _pr_tr=''
    if [ "$1" = theme ]; then
        _pr_chips=$(theme_chips theme); _pr_size=$(look_font_size); _pr_anim=$(anim_now)
        _pr_trn=$(transparency_of "$ALPHA"); if [ "$_pr_trn" -eq 0 ]; then _pr_tr=off; else _pr_tr="$_pr_trn%"; fi
    fi
    _pr_bar=''; [ "$1" != bar ] || { _pr_bar=$(bar_line_font "$(font_spec)"); _pr_bar=${_pr_bar##* }; _pr_bar=${_pr_bar%px}; _pr_bar=${_pr_bar%%.*}; }   # the bar's size now, auto's included
    _asks='[]'
    if [ "$1" = wifi ] && [ -n "$(wifi_tool)" ]; then   # a secured network not saved yet: its password is asked, masked
        wifi_known | cut -f2 > "$TMP/wifi.known.ask"
        _asks=$(wifi_scan | awk -F '\t' '$3 == 1' | cut -f1 | grep -vxFf "$TMP/wifi.known.ask" | jq -R . | jq -cs . 2>/dev/null) || _asks='[]'
    fi
    panel_rows "$1" | while IFS="$TAB" read -r _m _t _a _x; do case $1:$_a in 'layout:rename '*) continue ;; esac; provide_row_line "$1" "$_m" "$_t" "$_a" "$_x"; done > "$TMP/rows.short"   # the short form, and a more row that opens the rest
    { panel_rows "$1" full | while IFS="$TAB" read -r _m _t _a _x; do case $1:$_a in 'window:close '*|'layout:rename '*) continue ;; esac; provide_row_line "$1" "$_m" "$_t" "$_a" "$_x"; done; grep "^$1:more$US" "$TMP/rows.short" || :; } \
        | jq -Rn --arg s "$1" --arg u "spark-shell://$1/rows" --arg st "$(provide_title "$1")" --rawfile short "$TMP/rows.short" '
            [inputs | split("\u001f") | {id: .[0], sign: .[1], text: .[2], tool: (if .[3] == "" then null else {name: .[3], arguments: (.[4] | fromjson)} end), more: [],
                columns: ((.[5] // "") | split("|") | .[1:2] | map(select(. != ""))),
                children: (if .[0] == ($s + ":more") then $u else null end), group: ((.[5] // "") | split("|") | .[0] | if . == "" or . == null then null else . end)}
                + ((.[5] // "") | split("|") | .[2] // "" | if . == "" then {} else {date: .} end)
                + (if $s == "reminders" then ((.[5] // "") | split("|") | .[3] // "") as $id |
                    if ($id | startswith("spark-shell-")) then {more: [{name:"reminders_done", arguments:{name:$id}, said:"done"}, {name:"reminders_snooze", arguments:{name:$id}, said:"again in 10 minutes"}, {name:"reminders_delete", arguments:{name:$id}, said:"delete"}]} else {} end
                   else {} end)] as $rows
            | {title: $s, state: $st, rows: $rows, short: ($short | split("\n") | map(select(. != "") | split("\u001f")[0]))}' \
        | jq -c --argjson desktopkeys "$_pr_keys" --arg s "$1" --argjson asks "$_asks" --arg types "$WALL_TYPES" --argjson chips "$_pr_chips" --arg size "$_pr_size" --arg anim "$_pr_anim" --arg glyphs "$BAR_GLYPHS" --arg icons "$DIALOG_ICONS" --arg spacing "$DIALOG_SPACING" --arg family "$GLYPH_FAMILY" --arg face "$(face_word "${FONT%%:*}" || :)" --arg motion "$WALLPAPER_MOTION" --argjson trn "$_pr_trn" --arg tr "$_pr_tr" --arg bartext "$BAR_TEXT" --arg barsize "$_pr_bar" --arg tray "$BAR_TRAY" '
            .rows |= map(
                (if $s == "theme" and ((.group // "") | test("^(dark|light|custom)$")) and $chips[.text] != null then .chip = $chips[.text] else . end)
                | (if $s == "theme" and ((.group // "") | test("^(dark|light)$")) and (.tool.name // "") == "theme_palette"
                   then .quiet = true | .look = {name: "theme_preview", arguments: {name: .tool.arguments.name}} else . end)   # kept in place, looked at while lit
                | (if $s == "theme" and .id == "theme:show:Text size" then
                     ((($size | tonumber? // 12) | if . < 6 then 6 elif . > 40 then 40 else . end) - 6) as $at
                     | .step = {values: [range(6; 41) | tostring | {shown: ., sent: .}], at: $at, set: {name: "theme_text", arguments: {}}, key: "size", words: ["smaller", "bigger"]}
                   elif $s == "theme" and .id == "theme:show:Transparency" then
                     (([0, 10, 20, 30, 40, 50] + [$trn]) | unique) as $v
                     | .step = {values: [$v[] | {shown: (if . == 0 then "off" else "\(.)%" end), sent: tostring}], at: ($v | index($trn)), set: {name: "theme_transparency", arguments: {}}, key: "amount", words: ["less", "more"]}
                   elif $s == "theme" and .id == "theme:show:Words on the bar" then .switch = {on: ($glyphs == "words"), turn_on: {name: "theme_glyphs", arguments: {to: "words"}}, turn_off: {name: "theme_glyphs", arguments: {to: "signs"}}}
                   elif $s == "theme" and .id == "theme:show:App spacing" then
                     ["none", "groups", "rows"] as $v
                     | .step = {values: [$v[] | {shown: ., sent: .}], at: (($v | index($spacing)) // 1), set: {name: "theme_spacing", arguments: {}}, key: "to", words: ["less", "more"]}
                   elif $s == "theme" and .id == "theme:show:App icons" then .switch = {on: ($icons == "on"), turn_on: {name: "theme_icons", arguments: {to: "on"}}, turn_off: {name: "theme_icons", arguments: {to: "off"}}}
                   elif $s == "theme" and .id == "theme:show:Glyph family" then
                     (["stone", "star", "banner"]) as $v
                     | .step = {values: [$v[] | {shown: ., sent: .}], at: ($v | index($family) // 0), set: {name: "theme_family", arguments: {}}, key: "to", words: ["back", "next"]}
                   elif $s == "theme" and .id == "theme:show:Text face" and $face != "" then
                     (["neon", "argon", "xenon", "radon", "krypton"]) as $v
                     | .step = {values: [$v[] | {shown: ., sent: .}], at: ($v | index($face)), set: {name: "theme_face", arguments: {}}, key: "to", words: ["back", "next"]}
                   elif $s == "theme" and .id == "theme:show:Text face" then .columns = ["yours"]   # a face of your own: no step
                   elif $s == "theme" and .id == "theme:show:Moving wallpaper" then .switch = {on: ($motion == "on"), turn_on: {name: "theme_motion", arguments: {to: "on"}}, turn_off: {name: "theme_motion", arguments: {to: "off"}}}
                   elif $s == "bar" and .id == "bar:show:Text size" then   # auto stands where its size is
                     (($barsize | tonumber? // 11) | if . < 6 then 6 elif . > 40 then 40 else . end) as $a
                     | ([range(6; $a) | tostring | {shown: ., sent: .}] + [{shown: "auto \($a)", sent: "auto"}] + [range($a; 41) | tostring | {shown: ., sent: .}]) as $v
                     | .step = {values: $v, at: (if $bartext == "auto" then $a - 6 else ($v | map(.sent) | index($bartext)) // ($a - 6) end), set: {name: "bar_text", arguments: {}}, key: "size", words: ["smaller", "bigger"]}
                   elif $s == "bar" and .id == "bar:show:App icons (the tray)" then .switch = {on: ($tray == "yes"), turn_on: {name: "bar_tray", arguments: {state: "on"}}, turn_off: {name: "bar_tray", arguments: {state: "off"}}}
                   else . end))
            | (if $s == "theme" then .look_back = {name: "theme_preview", arguments: {name: "off"}} else . end)
            | .rows |= map(
                if $s == "theme" and (.tool.name // "") == "theme_save" then .tool.ask = ["name"]
                elif $s == "theme" and .id == "theme:picture" then .children = "spark-shell://files/rows" | .pick = {tool: "theme_picture", types: ($types | split(" "))}
                elif $s == "theme" and .id == "theme:wallpaper" then .children = "spark-shell://theme/rows/wallpapers" | .tool = null
                elif $s == "theme" and .id == "theme:show:Animation" then .children = "spark-shell://theme/rows/animations" | .tool = null | .columns = [$anim]
                elif ($s == "lan" or $s == "wifi") and (.id | startswith($s + ":network-settings")) then .sign = "opens" | .children = ("spark-shell://" + $s + "/rows/network/" + (.id | split(":network-settings ")[1]))
                elif $s == "display" and (.text | startswith("screen ")) then .sign = "opens" | .children = ("spark-shell://display/rows/screen/" + (.text | split(" ")[1]))
                elif $s == "power" and (.columns | length) > 0 then .wide = .columns | .columns = []   # what each does: the status row while lit, a column in a wide list
                elif $s == "window" and (.tool.name // "") == "window_capture" then .key = ($desktopkeys["desktop.desktop-capture-" + .tool.arguments.what] // null)
                elif (.tool.name // "") == "layout_save" then .tool.ask = ["name"]
                elif (.tool.name // "") == "layout_rename" then .tool.ask = ["to"]
                elif $s == "layout" and .group == "recent" then .more = [{name: "layout_rename", arguments: {name: .tool.arguments.name}, ask: ["to"], said: "save as"}, {name: "layout_delete", arguments: {name: .tool.arguments.name}, said: "forget"}]
                elif $s == "layout" and (.tool.name // "") == "layout_open" then .more = [{name: "layout_rename", arguments: {name: .tool.arguments.name}, ask: ["to"], said: "rename"}, {name: "layout_delete", arguments: {name: .tool.arguments.name}, said: "delete"}]
                elif (.tool.name // "") == "clock_zone" then .tool.ask = ["zone"]
                elif (.tool.name // "") == "reminders_add" then .tool.ask = ["words"]
                elif (.tool.name // "") == "wifi_hidden" then .tool.ask = ["name", "password"]
                elif (.tool.name // "") == "wifi_connect" and (.tool.arguments.name as $n | $asks | index([$n])) then .tool.ask = ["password"]
                else . end)
            | .rows |= map(if $s == "notes" and (.tool.name // "") == "notes_open" then
                {name:"notes_append", arguments:{name:.tool.arguments.name}, ask:["text"], said:"append"} as $append |
                [. + {more:(.more + [$append, {name:"notes_rename", arguments:{name:.tool.arguments.name}, ask:["to"], said:"rename"}, {name:"notes_trash", arguments:{name:.tool.arguments.name}, said:"trash"}])}]
              else [.] end) | .rows |= (add // [])' | provide_rows_more "$1" | provide_rows_place "$1" && _prs=0 || _prs=$?
    THEME_ENUM_NOW=''; WIFI_TOOL_READ=''; WIN_FACTS_READ=''   # the next read sees a palette saved, a manager started meanwhile
    read_once_end; ROWS_READ=''   # and a device plugged in meanwhile
    return "$_prs"
}
provide_rows_place() { case $1 in window) provide_rows_window ;; layout) provide_rows_layout ;; *) cat ;; esac; }   # stdin: a rows resource -> the same as the workspace place shows it
provide_rows_window() {   # stdin: the window section's rows -> the same with the workspace facts in; no sway: no rows
    jq -c --slurpfile facts "$TMP/win.facts" --arg sep "$PANEL_SEP" '
        def step($n; $a; $w): {name: $n, arguments: $a, said: $w};
        ($facts[0] // null) as $f
        | if $f.here == null then .state = "no desktop" | .rows = []
          else (($f.windows | map({key: (.id | tostring), value: .})) | from_entries) as $by
            | ($f.windows | length) as $n
            | .state = (if $n == 0 then "no windows" elif $n == 1 then "1 window" else "\($n) windows" end)
            | ([.rows[] | select(.tool.name == "window_focus") | . as $r | $r.tool.arguments.name as $id | $by[$id] as $w | select($w != null)
                | $r + {group: $w.group, ws: $w.ws, front: $w.front,
                    wide: ([($r.columns[0] // ""), $w.placed]),
                    line: (([$r.text] + $r.columns + ["workspace \($w.place)", $w.placed]) | map(select(. != "")) | join(" \($sep) ")),
                    tool: ($r.tool + {said: "put in front"}),
                    more: [step("window_move"; {name: $id}; "move to workspace") + {value: $w.place, children: ("spark-shell://window/rows/move/" + $id)},
                           step("window_place"; {name: $id}; "placement") + {value: $w.placed, children: ("spark-shell://window/rows/place/" + $id)},
                           step("window_capture"; {what: "window", name: $id}; "capture this window"),
                           step("window_close"; {name: $id}; "close")]}]
               + (if ($f.here.empty // false) then [{id: "window:none", sign: "blank", text: "no windows here", tool: null, more: [], columns: [], children: null, group: $f.here.group, muted: true, ws: $f.here.ws}] else [] end)
               | sort_by([.ws < 0, .ws]) | map(del(.ws))) as $wins
            | ([.rows[] | select(.tool.name == "window_capture" and .tool.arguments.what != "window")]) as $caps
            | ($f.here.arrange // "split") as $a
            | .rows = $wins + $caps + [{id: "window:arrange", sign: "opens", text: "arrange windows", tool: null, more: [], choice: true,
                columns: [if $a == "split" then "side by side" else $a end], children: "spark-shell://window/rows/arrange", group: null}]
          end'
}
provide_window_rows() {   # provide_window_rows URI -> a picker as a rows resource: arrange, move/ID or place/ID
    win_facts > "$TMP/win.facts"
    _pwk=$(python3 "$REPO/lib/home.py" map "$REPO/template/.config/sway/config")
    family_set "$(bar_style GLYPH_FAMILY stone)"
    _pwm=$(for _n in 1 2 3 4 5 6 7 8 9 10; do bar_ws_label "$_n"; echo; done | jq -R . | jq -cs .)   # the bar's labels, one a line
    jq -cn --slurpfile facts "$TMP/win.facts" --argjson keys "$_pwk" --argjson marks "$_pwm" --arg uri "${1#spark-shell://window/rows/}" '
        def pick($id; $text; $on; $tool; $key; $group): {id: $id, sign: (if $on then "check" else "blank" end), text: $text, tool: (if $on then null else $tool end), more: [], columns: [], children: null, group: $group, back: true}
            + (if $key == null then {} else {key: $key} end);
        ($facts[0] // {windows: [], spaces: []}) as $f
        | ($uri | split("/")) as $u
        | ($f.windows | map(select((.id | tostring) == ($u[1] // ""))) | first) as $w
        | ($w.label // "" | split(": ")[0]) as $app
        | if $u[0] == "arrange" then ($f.here.arrange // "split") as $a
            | {title: "arrange windows", rows: [
                pick("window:arrange:split"; "side by side"; $a == "split"; {name: "window_split", arguments: {}}; $keys["layout.toggle-split"]; "arrange windows"),
                pick("window:arrange:tabs"; "tabs"; $a == "tabs"; {name: "window_tabs", arguments: {}}; $keys["layout.tabs"]; "arrange windows"),
                pick("window:arrange:stacked"; "stacked"; $a == "stacked"; {name: "window_stacked", arguments: {}}; $keys["layout.stack"]; "arrange windows"),
                {id: "window:arrange:note", sign: "blank", text: "this workspace now, and every new workspace", tool: null, more: [], columns: [], children: null, group: null, muted: true}]}
          elif $w == null then {title: "that window", rows: [{id: "window:gone", sign: "blank", text: "that window is no longer open", tool: null, more: [], columns: [], children: null, group: null, muted: true}]}
          elif $u[0] == "move" then ($w.ws) as $at
            | ($f.spaces | map({key: (.num | tostring), value: .}) | from_entries) as $by
            | {title: $app, rows: [(([range(1; 11)] + [$f.spaces[].num]) | unique)[] | . as $n | ($by[$n | tostring] // {mark: (($marks[$n - 1] // "") | if . == ($n | tostring) then "" else . end), apps: []}) as $s
                | pick("window:move:\($n)"; (($n | tostring) + (if ($s.mark // "") != "" then " " + $s.mark else "" end)); $n == $at;
                    {name: "window_move", arguments: {name: ($w.id | tostring), to: ($n | tostring)}}; null; "move to workspace")
                  + {columns: [if ($s.apps | length) > 0 then ($s.apps | join(", ")) else "empty" end]}]}
          elif $u[0] == "place" then ($w.id | tostring) as $id
            | def how($h; $text; $on; $key): pick("window:place:" + $h; $text; $on; {name: "window_place", arguments: {name: $id, how: $h}}; $keys[$key]; "placement");
              {title: $app, rows: [
                how("tiled"; "tiled"; $w.placed == "tiled"; "desktop.desktop-window-float"),
                how("floating"; "floating"; $w.placed == "floating"; "desktop.desktop-window-float"),
                how("full"; "full screen"; $w.placed == "full screen"; "window.fullscreen"),
                how("left"; "left half"; false; "desktop.desktop-window-left"),
                how("right"; "right half"; false; "desktop.desktop-window-right"),
                how("up"; "top half"; false; "desktop.desktop-window-up"),
                how("down"; "bottom half"; false; "desktop.desktop-window-down")]}
          else {title: "", rows: []} end'
}
layout_meta() {   # -> {NAME: {apps, why}}, a layout saved or kept for the history; the saved one wins
    for _lmf in "$KEPT_LAYOUTS"/* "$LAYOUTS_DIR"/*; do
        [ -f "$_lmf" ] || continue
        jq -c --arg n "${_lmf##*/}" '{($n): {apps: (([.main.app] + [(.side // [])[] | .app]) | map(select(. != null)) | join(", ")), why: (.why // "" | gsub("[\\n\\r]"; " "))}}' "$_lmf" 2>/dev/null
    done | jq -cs 'add // {}'
}
provide_rows_layout() {   # stdin: the layout section's rows -> the same with each layout's apps and why
    _prl=''; [ ! -f "$DESK_LAST" ] || _prl=$(desk_words "$DESK_LAST")
    jq -c --slurpfile facts "$TMP/win.facts" --argjson meta "$(layout_meta)" --arg sep "$PANEL_SEP" --arg last "$_prl" '
        ($facts[0] // null) as $f | ($f.here != null) as $desk
        | .rows |= ([.[] | (.tool.name // "") as $t
            | if $t == "layout_open" then
                ($meta[.tool.arguments.name] // {apps: "", why: ""}) as $m
                | (if .group == "recent" then ([$m.apps, (.columns[0] // "")] | map(select(. != "")) | join(", ")) else $m.apps end) as $c
                | .columns = (if $c == "" then [] else [$c] end)
                | .wide = ([$c, $m.why] | map(select(. != "")))
                | .line = (([.text, $m.apps, $m.why] + (if $desk then [] else ["opens in tmux"] end)) | map(select(. != "")) | join(" \($sep) "))
                | .tool.said = "open"
              elif $t == "layout_add" then .text = .tool.arguments.name | .group = "also open" | .columns = (if $last == "" then [] else ["suggested for " + $last] end)
              elif $t == "layout_save" and ($f.here.empty != false) then .tool = null | .muted = true
              elif (.id | startswith("layout:show:none saved")) then
                (.group = "layouts" | .muted = true | .when_model = true | (if $desk then . else .text = "none saved: ask at the prompt" end)),
                (.id = "layout:show:none" | .text = (if $desk then "none saved: save this workspace to keep one" else "none saved" end) | .group = "layouts" | .muted = true | .when_model = false)
              else . end]
          | map(select(.group == "also open")) + map(select(.group != "also open")))'
}
provide_rows_more() {   # provide_rows_more SECTION -- stdin: a rows resource -> the same with one row a thing, its other steps in more, and its page
    jq -c --arg s "$1" '
        def step($n; $a; $w): {name: $n, arguments: $a, said: $w};
        def b64: @base64 | gsub("="; "") | gsub("[+]"; "-") | gsub("/"; "_");
        ([.rows[] | select(.tool.name == "wifi_connect") | .tool.arguments.name]) as $around
        | ([.rows[] | select(.tool.name == "wifi_forget") | .tool.arguments.name]) as $saved
        | ([.rows[] | select(.tool.name == "bt_remove") | .tool.arguments.name]) as $paired
        | ([.rows[] | select(.tool.name == "storage_unmount") | .tool.arguments.name]) as $mounted
        | ([.rows[] | select(.tool.name == "storage_eject") | .tool.arguments.name]) as $drives
        | .rows |= map(
            (.tool.name // "") as $t | (.tool.arguments.name // "") as $n | (.group // "") as $g
            | if $s == "wifi" and $t == "wifi_forget" then
                (if ($around | index([$n])) then empty
                 else {id: ("wifi:saved " + $n), sign: "blank", text: $n, tool: null, more: [step("wifi_forget"; {name: $n}; "forget")], columns: ["saved, not around"], children: null, group: null} end)
              elif $s == "wifi" and $t == "wifi_connect" and ($saved | index([$n])) then .more += [step("wifi_forget"; {name: $n}; "forget")]
              elif $s == "bt" and $t == "bt_remove" then empty
              elif $s == "bt" and ($t == "bt_connect" or $t == "bt_disconnect") and ($paired | index([$n])) then .more += [step("bt_remove"; {name: $n}; "remove")]
              elif $s == "storage" and ($t == "storage_unmount" or $t == "storage_eject") then empty
              elif $s == "storage" and $g != "" and ($drives | index([$g])) and ($t == "storage_open" or $t == "storage_mount" or .tool == null) then
                  .more += ((if $t == "storage_open" and ($mounted | index([$n])) then [step("storage_unmount"; {name: $n}; "unmount")] else [] end) + [step("storage_eject"; {name: $g}; "eject")])
              else . end)
        | .rows |= map(
            if ($s == "apps" and .tool.name == "apps_open") or ($s == "notes" and .tool.name == "notes_open") or ($s == "reminders" and .date != null)
               or ($s == "window" and .tool.name == "window_focus") or ($s == "layout" and .tool.name == "layout_open")
               or ($s == "wifi" and (.tool.name == "wifi_connect" or .tool.name == "wifi_disconnect" or (.id | startswith("wifi:saved "))))
               or ($s == "bt" and ((.tool.name // "") | test("^bt_(connect|disconnect|pair)$"))) or ($s == "storage" and ((.tool.name // "") | test("^storage_(open|mount)$")))
            then .page = ("spark-shell://" + $s + "/page/" + (.id | b64)) else . end)'
}
provide_wall_rows() {   # -> the wallpaper list as a rows resource: the drawings with a preview each, a picture of yours, a color, the ground
    _tp=$(thumb_palette)
    ( TMP=$(mktemp -d) && { wall_thumbs; rm -rf "$TMP"; } ) >/dev/null 2>&1 </dev/null 3>&- 4<&- 5>&- &   # the previews drawn in the background; a row without one yet draws none
    _gr=$(wall_ground); _cc=''; ! wall_color || _cc=$(wall_hex "$WALLPAPER")
    panel_rows wallpapers full | while IFS="$TAB" read -r _m _t _a _x; do provide_row_line theme "$_m" "$_t" "$_a" "$_x"; done \
        | jq -Rn --arg types "$WALL_TYPES" --arg dir "$THUMB_DIR" --arg tp "$_tp" --arg ground "$_gr" --arg color "$_cc" '
            [inputs | split("\u001f") | {id: .[0], sign: .[1], text: .[2], tool: (if .[3] == "" then null else {name: .[3], arguments: (.[4] | fromjson)} end), more: [],
                columns: ((.[5] // "") | split("|") | .[1:2] | map(select(. != ""))), children: null, group: ((.[5] // "") | split("|") | .[0] | if . == "" or . == null then null else . end)}
             | if .group == "drawings" then .preview = ($dir + "/" + .text + "-" + $tp + ".png") else . end
             | if .text == "the ground" then .chip = [$ground] elif .id == ("theme:show:" + .text) and .group == "custom" and $color != "" and .columns == ["a color"] then .chip = [$color] else . end
             | if .id == "theme:wallpaper-color" then .tool.ask = ["color"] else . end
             | if (.tool.name // "") == "theme_wallpaper" then .quiet = true else . end   # a drawing or the ground kept in place, nothing said
             | if .id == "theme:wallpaper-picture" then .children = "spark-shell://files/rows" | .pick = {tool: "theme_wallpaper_picture", types: ($types | split(" "))} else . end]
            | {title: "wallpaper", state: "", rows: ., short: []}'
}
provide_anim_rows() {   # -> the animation list as a rows resource: the pieces and none, the one in use checked, each with its folder in the palette in use
    _ap=$(anim_palette); _an=$(anim_now); _apo=$(anim_for_palette "$_ap"); _anl="$ANIMATION_NAMES none"
    anim_drawn "$_ap" || _apo=''   # no shipped set for this palette: no piece is its own
    for _n in $_anl; do
        _af=''; [ "$_n" = none ] || [ -z "$_ap" ] || [ ! -f "$REPO/gallery/animation/$_n/$_ap/open.gif" ] || _af=$REPO/gallery/animation/$_n/$_ap
        printf '%s\t%s\n' "$_n" "$_af"
    done | jq -Rn --arg now "$_an" --arg paired "$_apo" '
        [inputs | split("\t") | {id: ("theme:animation:" + .[0]), sign: (if .[0] == $now then "check" else "blank" end), text: .[0],
            tool: {name: "theme_animation", arguments: {to: .[0]}}, more: [], children: null, group: null, quiet: true,
            columns: (if .[0] == "none" then ["no motion"] elif .[0] == $paired then ["the palette'"'"'s own"] else [] end)}
          + (if .[1] != "" then {film: .[1]} else {} end)]
        | {title: "animation", state: "", rows: ., short: []}'
}
theme_chips() {   # theme_chips SECTION -> {NAME: [nine colors]}, {} for any other section
    [ "$1" = theme ] || { printf '{}'; return 0; }
    dirs_cached theme.chips "$(THEME_DIRS)" theme_chips_now
}
theme_chips_now() {
    { palette_names; theme_saved_names; } | sort -u | while IFS= read -r _n; do _c=$(palette_chip "$_n") && printf '%s\t%s\n' "$_n" "$_c"; done \
        | jq -Rn '[inputs | split("\t") | {(.[0]): (.[1] | split(" ") | map(select(test("^#[0-9A-Fa-f]{6}$"))))}] | add // {}'
}
provide_in_use() {   # provide_in_use SECTION TOOL ARG -> 0 when ARG names what is in use: choosing it again is a receipt, not a refusal
    [ -n "$3" ] || return 1
    jq -e -s --arg id "$1:show:$3" 'any(.[].rows[]; .id == $id and .sign == "check")' "$TMP/rows.json" >/dev/null 2>&1 && return 0
    case $2 in theme_palette) [ "$3" = "${THEME:-}" ] ;; theme_wallpaper) [ "$3" = "$(wall_name)" ] ;; *) return 1 ;; esac
}
provide_row_line() {   # provide_row_line SECTION MARK TEXT ACTION [GROUP|COLUMN|DATE|SUFFIX] -> ID US SIGN US TEXT US TOOL US ARGUMENTS US EXTRAS; SUFFIX tells two rows with one step apart
    case $2 in "$PANEL_DOT") _sg="dot" ;; "$PANEL_RING") _sg="ring" ;; "$PANEL_TICK") _sg="check" ;; "$PANEL_CROSS") _sg="cross" ;; "$PANEL_GO") _sg="opens" ;; *) _sg="blank" ;; esac
    _tx=$(scrub_plain "$3"); _ac=$(scrub_plain "$4"); _id="$1:$_ac"; _tn=''; _ag='{}'
    if [ "$_ac" = show ]; then _id="$1:show:$_tx"
    elif [ "$_ac" = more ]; then :   # the rest of the section: its children, no tool
    elif action_tool "$1" "$_ac"; then _tn=$_tool; _ag=$(tool_args_json "$_tool" "$_tv"); fi
    _dt=''; _sx=''
    case ${5:-} in *'|'*'|'*) _dx=${5#*|}; _dx=${_dx#*|}; _dt=${_dx%%|*}; case $_dx in *'|'*) _dx=${_dx#*|}; _sx=${_dx%%|*} ;; esac ;; esac   # the third and fourth fields, no cut: a group alone has no pipe
    [ -z "$_dt" ] || _id="$_id:$_dt"   # a dated row's id is its own (two reminders may share a name)
    [ -z "$_sx" ] || _id="$_id:$_sx"
    printf '%s\n' "$_id$US$_sg$US$_tx$US$_tn$US$_ag$US$(scrub_plain "${5:-}")"   # the parts scrubbed, never the line: the scrubber drops US
}
provide_clock_rows() {
    jq -cn --arg state "$(time_zone), $(time_sync)" '{title: "clock", state: $state, rows: [{id: "clock:settings", sign: "opens", text: "time settings", tool: null, more: [], columns: [], children: "spark-shell://clock/rows/settings", group: null}], short: ["clock:settings"]}'
}
provide_title() { [ "$1" != about ] || return 0; [ "$1" != tools ] || return 0; [ "$1" != files ] || { echo "your home folder"; return; }; panel_title "$1" | sed -n 1p | sed "s/^$1 *//" | scrub_text; }
