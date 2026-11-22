# Unified theme revamp — one implementation arc

## Founder-controlled flagship artwork gate (2026-11-22)

**This section takes precedence over any contrary asset-delivery wording below.**
The founder has NOT approved Neon Rain or any other cinematic illustration as
final. All generated images, GIF motion studies, previews and the earlier
`spark_shell_theme_revamp_codex_assets.zip` are UNAPPROVED EXPLORATION,
not production art. DO NOT import, commit, convert, upscale, package, deploy,
release, or use them as final artwork. In particular, do not silently import
the previously supplied "clean" Neon Rain draft from any ZIP or scratch path.
Do not interpret a provisional color palette as an approved theme palette.

The founder and ChatGPT will art-direct **one flagship theme together**,
including its clean/unbranded artwork, intended day/night art concept,
landscape and portrait companion compositions, optional three-panel
composition, animation treatment and derived interface/terminal palette.
**Only after the founder explicitly approves the final artwork version
and hands over the approved assets may Codex integrate them.** Do not infer
approval from a favorable comment about an earlier study.

**Codex must continue independently now**: implement the complete
manifest/theme-engine, variants, existing-terminal-palette support,
per-theme animation/static modes, curated font/glyph/spacing/icon options,
gallery UX, output orientation/triptych routing, lock and idle artwork
display, compatibility/security/tests; conduct actual current-art visual
and animation review; apply reversible pruning/archive decisions (never
delete original user-accessible themes without explicit owner approval).
Implement proof fixtures using existing shipped art or conspicuously
TEST-ONLY generated gradients/checkerboards; never ship placeholders as
an exhibition or pretend fixture work is production artwork.

Original high-detail art production for all Cinematic Worlds work should
follow the founder-approved flagship visual standard. Codex may prepare
asset manifests, tests and empty *development* slots, but must not mark a
cinematic exhibition or theme as finished while its artwork is pending.

Report two separate statuses: **engineering ready for artwork integration**
and **complete exhibition ready for owner review**. The first may pass
CI while the second must remain blocked until approved flagship art and
other required exhibited artwork are integrated, tested and reviewed.
Do not close/merge/release PR #36 until the full arc is approved.

## Mandate

Complete the theme/art/appearance experience as ONE coherent, reviewable change on
the existing draft PR #36 branch `feat/curated-gallery-rooms`. Do not fork into a
chain of follow-up PRs, silently narrow the scope, merge, tag, or release.
The founder reviews the whole end-to-end result before deciding to merge.

This brief supersedes treating PR #36 as only a gallery taxonomy change.

## Absolute artwork rule

**Artwork is 100% art.** Never place the words "spark", "spark-shell" or
"forgewright", product names, logos, nested diamonds, product chevrons,
watermarks, promotional copy, or other product-brand motifs INSIDE an
illustration, wallpaper, animation frame, triptych panel, lock/idle image,
or gallery art preview. An artist's own visual language and unbranded
environmental details are welcome. This does not prohibit attribution or
normal labels in the gallery's separate UI chrome.

Do not repurpose the earlier branded Neon Rain draft: only the CLEAN,
unbranded version supplied for this arc may become artwork.

## Existing source of truth / don't break

- `gallery/core/themes.tsv`: 34 existing stable theme names / aliases
- `gallery/core/curation.json`: six Permanent Collection sections (PR #36)
- `src/appearance.sh`, `src/rows.sh`, `src/mcp.sh`: gallery provider
- `component/dialog/src/appearance.rs`, `app.rs`, `scene.rs`: gallery UI
- `gallery/theme/*.env`, `component/theme`, `src/theme.sh`, `src/look.sh`:
  shared palette contract, CLI, theme settings, wallpaper
- `lib/wallpaper.py`: 12 animated scene types in two existing art families
- `lib/animation.py`: six dialog transition animations, open/wait/close
- `src/screen.sh`: output ID, geometry, orientation, arrangement
- Existing display saver / lock / panel and window implementation, read
  their real source before extending.
- Existing `test/gate.sh`, `test/lane.sh`, release binary SHA pins and
  signed data-only community gallery policy remain authoritative.

Read and follow any AGENTS.md/CLAUDE.md instructions that actually exist.
Do not invent new background daemons or rewrite the desktop stack.
Prefer a single, explicit manifest per *art family*, with a compatible
adapter for the existing FORMAT=2 theme format.

## Theme domain

- **Art family:** one visual concept, e.g. sunset or neon-rain.
- **Variant:** dark and/or light, with independently composed art permitted.
  Never merely invert a wallpaper to simulate a paired variant.
- **Art media:** minimal vector/graphic art versus cinematic illustration;
  distinguish and describe them in the gallery, not generic light/dark bins.
- **Presentation:** wallpaper mode (still/ambient motion), orientation
  (landscape/portrait), 1/2/3-display composition, idle and lock display.
- **Palette:** curated background/foreground/accent/muted plus ANSI 16,
  source reference/credits and terminal export formats.
- **UI profile:** dialog animation, font family, text size, density/spacing,
  glyph family; app icons on/off, bar icons on/off, dialog row spacing.
  Preserve user override and existing behavior when unset.
- **Capabilities / fallback:** explicit manifest indicates which optional
  companion arts exist; absent assets use a safe, beautiful still/art
  orientation fallback rather than an error or forced crop. Do not claim
  "triptych" on a work that has no authored companion panels.

Any new manifest format MUST have strict validation and versioning; it may
not execute arbitrary code or weaken the signed external-gallery trust
boundary. Reuse the current theme engine, not a competing second engine.

## Gallery selection UX — implement, not merely mock up

1. Gallery home: Permanent Collection + separately identifiable curated
   exhibitions; each has its own lead art, short note and work count.
2. Permanent Collection: keep six current curatorial sections as a baseline.
   Judge work by rendered imagery, not filenames or palette names.
3. Individual work: large accurate still preview, optional motion preview,
   dark/light, palette sample / ANSI swatches, dialog motion preview,
   typography, glyph and UI-option metadata, companion compositions.
4. Preview must never change active theme. "Apply" is always explicit;
   preserve F3 artwork view, F4 terminal palette, keyboard list navigation,
   pointer and touch with uncramped usable hit targets.
5. At compact and wide dimensions controls must not jump as focus changes.
   Never sacrifice keyboard-first behavior for a giant card grid.
6. The color scheme reference and its upstream attribution stay available
   and exportable exactly as today.

## Curation and deliverables

### Permanent Collection (current 34 stable keys)
Keep both original media and themed source palettes. Curate, don't blindly
delete: mark strongest pieces as exhibited, weaker repetitions as archive
or supporting works. Preserve existing names, terminal palettes and older
configs. Initial visual shortlist, pending full rendered checks:

- Featured vector studies: contours, orbit, ripples, sunset, arches.
- Refine/retain: shore, hills, dunes, grove.
- Rework: skyline, fjord, forest.
- Reduce near duplicates: morning, fields, meadow (retain one lead, do not
  silently remove other existing theme keys).
- Demote to supporting, not default heroes: kites, flight, embers, unless
  a better art revision justifies promotion.
- Review all 12 animated wallpaper scenes as actual motion, not only
  source code; review the six dialog GIF families too.
- Do not retire or delete existing artwork before founder sees contact
  sheets and approves the specific proposed removals.

### Cinematic Worlds (new original exhibition)
Six distinct original high-detail anime-inspired environmental works:
Neon Rain, Ghost Circuit, Iron Kingdom, Elder Realm, Twin Suns, Starward.
Draw inspiration from the broad sci-fi/fantasy genres, not copyrighted
characters, franchise logos, exact ships, named locations or emblems.
No product branding in any pixels. Use 16:9 landscape originals plus
authored portrait companions, never a generic center crop.
Use a clean Neon Rain starter image from the supplied handoff only after
verifying it contains no product motif.

Each exhibited work should have a real curated palette, font/glyph/dialog
motion pairing and usable static wallpaper. Build coherent dark/light
variants of flagship concepts where appropriate; theme system must support
both even if a legacy work has only one. Ambient wallpaper motion must be
optional and restrained. No empty placeholders may masquerade as published
art.

### 1–3 display / triptych
- For *flagship works*, create intentionally related 1, 2 and 3-screen
  compositions, including distinct landscape and portrait companion art.
- Bind panels to stable outputs / their actual left-to-right placement and
  rotation; test mixed portrait-landscape and monitor detach/reorder.
- Avoid merely stretching one image across rotated monitors. Use safe
  fallback per-output composition when a given theme lacks authored panels.
- Reuse existing output discovery / configuration; do not add a daemon.

### Art-only idle and lock
- Idle/lock can display clean full-screen, unobstructed artwork with
  optional clock as UI overlay, never drawn into artwork.
- Lock must remain securely authenticated; don't expose user notes, icons,
  prompts or notifications through the artwork presentation.
- Support still mode / reduced motion / low-power default. Never force
  video rendering in a lock screen or on battery.
- Restore the previous screen state predictably after unlock.

## Technical acceptance and release gate

Implement as one draft PR and produce *one final visual evidence packet*:
- Complete theme contract and a real flagship family exercising variants,
  still/animated, landscape/portrait/triptych, terminal palette, font/glyph,
  dialog motion, optional chrome and art-only lock/idle.
- Six cinematic works included only when artwork and configuration are
  truly production quality; no superficial filler just to reach six.
- 34 existing theme keys and aliases still readable/usable; current
  terminal export, copy hex, saved looks and local collections work.
- Tests cover roundtrip persistence, fallback, preview non-mutation,
  invalid manifests/paths, 1/2/3 monitors, screen reorder, orientation,
  motion disabled, lock authentication, icon/spacing behavior.
- Native screenshots: gallery compact + wide; artwork before/after
  theme apply; dark/light; each companion composition, triptych; idle/lock.
- Static contact sheets of ALL old/new artwork plus sampled motion frames;
  name each reviewed piece and disposition (keep/rework/archive), with
  a specific visual reason. Include performance/memory/CPU evidence and
  contrast for readable dialogs and terminals.
- Run targeted tests first; then `sh test/gate.sh --quick`,
  `sh test/gate.sh`, relevant native proofs and push CI / CodeQL.
- Preserve the reproducible dialog build hash rule. If Rust changes,
  regenerate the SHA once after source stabilizes using the repo's
  reproducible build workflow, rather than changing the pin after every edit.
- Treat full CI red, missing evidence, or incomplete art as NOT DONE.

## Immediate blockers already verified on PR #36

Latest tested head 1f86b449bd7c5d925d9b485174dd9832cba00bd6:
- Dialog Rust formatting check failed (`component/dialog/src/app.rs`);
  run cargo fmt after edits stabilize.
- Shell suite still expects the old flat gallery (failing "theme gallery");
  migrate the behavioral assertions to the room navigation and preserve
  personal alias semantics.
- README voice check rejects "room"/"rooms"; revise prose without hiding
  the product concept.
- CodeQL and the previous deterministic build pin check passed.
Do not run the whole CI matrix repeatedly for these small fixes.

## Scope discipline

One branch, one draft PR, one final owner review, one release gate.
Do not alter protected main, tag, auto-merge, publish, delete assets,
rework repository governance or licenses, or push to an unknown repo.
Use the existing fast/standard/guarded change gates and record
what was actually tested. If an acceptance item is not achieved, say
precisely what remains rather than calling the arc complete.
