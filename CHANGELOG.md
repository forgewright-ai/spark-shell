# Changelog

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
