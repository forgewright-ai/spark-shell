# Changelog

## v0.139

The compositor and the terminal are spoken to through one module each,
and the desktop stays on.

- src/compositor.sh and src/terminal.sh are the only modules that name
  sway, its tools and foot, and lib/compositor.py the only helper; the
  module check refuses any other that does. Each implements a stated
  contract, so another compositor or terminal is one module behind the
  same calls.
- check has two new rows: the compositor and the terminal in use.
- Always on: the lock timer locks and no longer turns the display off;
  the idle screen is the resting state.
- CI times each family's package install and writes the seconds to the
  job summary.

## v0.138

The long functions are short ones with names, and the layout's state
files carry the layout's name. No change in behavior.

- The eight functions over 100 lines are each under 60 now: a
  dispatcher and named helpers. panel_rows and panel_act have one
  helper a section, tool_spec one a domain, provide_one and
  provide_call one a phase of a call, cmd_on and cmd_check_lines one a
  row, provide_files_call one a kind of step. The longest function in
  the shell is 96 lines.
- The layout's state files are layout.last and layout.pending; a file
  under the old name is moved to the new one once, on the next run.
- The credits name the five Monaspace faces the setup installs.
- The brand animation's frames and the script that drew them leave the
  tree: nothing in spark-shell used them.

## v0.137

Names say what things are, and every path written in the tree exists.
No change in behavior.

- test/paths_check.py scans the tracked files for references into the
  tree's folders and fails on any that names nothing; CI and the
  pre-push gate run it.
- The wallpaper crate's folder is component/wallpaper (the binary stays
  spark-wallpaper); the override SPARK_SHELL_WALLPAPER replaces
  SPARK_SHELL_PLAYER, which is still read for one release; the variable
  that says where a layout opens is LAYOUT_ON, with the values desktop
  and terminal.
- The shell modules are named by their domain: config, setup, undo, ask,
  rows, devices and facts replace read, verbs, step, want, provide,
  probes and machine; system.sh is notifications, storage and power; the
  layout code says layout_ where it said desk_.
- The python helpers are wifi, reminders, launch, running, terminal,
  dhcp, bluetooth and layout, with lib/shim/ for the terminal shim; the
  tests follow.
- The dialog crate keeps its login screen in login/ (mod, ui, run) and
  its animation module under that name.
- The three crates carry the release's version, a description without
  the brand and the repository.

## v0.136

The shell script is split into modules with declared interfaces. No
change in behavior apart from a few words in the help text and rows.

- Each module in src/ declares the globals it reads from other modules
  and the ones it sets at source time; test/modules_check.py verifies
  the declarations, flags functions that are never called and flags
  top-level references to modules sourced later. CI and the pre-push
  gate run it.
- core.sh is sourced first and holds the paths, the row printers, the
  CLI flags and the signal traps. font_quiet.sh and session.sh are
  merged into their domains; sources.sh is renamed sections.sh;
  tools.sh and files.sh are split into tools.sh, mcp.sh, files.sh,
  preview.sh and files_provider.sh. Six unused functions are removed.
- The help text and user-facing rows refer to the desktop, the terminal
  and the login screen instead of the underlying programs; rows that
  name a package to install keep the package name.
- The animation scripts move to lib/ and write to gallery/animation and
  the brand frames' folder by default.
- Comments in the ten largest modules are cut by half.

## v0.135

The record starts here.
