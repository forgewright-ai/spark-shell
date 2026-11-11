# Changelog

## v0.137

Names say what things are, and every path written in the tree exists.
No change in behavior.

- test/paths_check.py scans the tracked files for references into the
  tree's folders and fails on any that names nothing; CI and the
  pre-push gate run it.
- The wallpaper crate's folder is component/wallpaper (the binary stays
  spark-wallpaper); the variable that says where a layout opens is
  LAYOUT_ON, with the values desktop and terminal.
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
- The animation scripts move to lib/animation.py and lib/brand.py and
  write to gallery/animation and asset/brand-transitions by default.
- Comments in the ten largest modules are cut by half.

## v0.135

The record starts here.
