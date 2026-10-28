# Task acceptance

The task host, decision backend and native operation are different boundaries.
An accepted proposal is not proof of an effect. A successful receipt describes
one operation; the final native state determines whether the goal was met.

Run the fixed scenarios through the actual terminal dialog:

```sh
(cd dialog && cargo build --locked)
python3 tests/ax_acceptance.py dialog/target/debug/spark-dialog --report ax.json
```

This default mode uses scripted decisions and production native providers. It
needs no Spark checkout, inference server or network. CI runs it in a network
namespace with no interfaces. The scripts test the host's behavior; they are
not evidence of a model's ability to interpret a request.

For a live evaluation, opt in to an installed Spark checkout and its existing
configured backend:

```sh
python3 tests/ax_acceptance.py dialog/target/debug/spark-dialog \
  --spark "$HOME/.spark" --report ax-live.json
```

Both modes use the goals and native-state checks in `ax_cases.json`. Live
decisions never read the scripts. Do not change goals or expected results to
make a model pass; a changed suite has a different digest in its report.
Use `--only` with comma-separated IDs to reproduce a failure. A rerun is
diagnostic evidence, not another independent accuracy sample. The separate
`ax_heldout.json` set is selected with `--set held-out`. Reserve its first live
run until implementation is frozen and retain that result, including failures.
Later runs of those cases are regression checks, not fresh held-out evidence.

Every case has a temporary HOME and its own config, notes and calendar. The
sound owner is a controlled `wpctl` fixture. Appearance checks saved settings;
they do not change the current desktop or prove another application's theme.
No case installs packages, changes services, connects a radio, prints a page,
or suspends the machine. Provider environments exclude inference credentials.
Only the live decision process uses the existing Spark connection. Its model
receives synthetic task data and the available capabilities.

The driver waits for native capabilities, types the request at a real PTY,
answers the case's clarification and presses Enter for reviewed actions.
It never supplies destructive confirmation. Cancellation cases stop before
the next action. Reports contain case IDs, outcomes, counts and timings; raw
requests and native replies stay in disposable files. `--capture DIRECTORY`
retains synthetic terminal text locally for inspection.

## Coverage and evidence

| Capability | Identity and effect | Acceptance evidence |
| --- | --- | --- |
| Notes | Markdown filename; created or appended content | Real isolated files, paraphrases, existing note, returned filename used by a reminder |
| Reminders | iCalendar UID; saved title and local time | Real isolated events and alarms, clarification, returned UID used by a note, duplicate names and civil-time checks |
| Sound | Current native output or input; level and mute readback | Production provider against controlled backend, typed relative changes, absolute requests, mute, failed writes and exact undo |
| Appearance | Palette name and native configuration | Saved config through dialog; application and portal acceptance remains separate |
| Clock | Native preference and local civil time | Saved clock format; real timezone rules for nonexistent and repeated local times |
| Windows | Native compositor container ID | Duplicate-name resolution and native tree verification; separate headless Sway proof |
| Layouts | Saved layout and observed application windows | Separate headless Sway/foot proof, minimum sizes and sibling-window preservation |
| Network, display, input, printers | Native owner identifiers and permission | Domain tests and dedicated native proofs; physical evidence is recorded separately |

`dialog/tests/tasks.rs` exercises transitions with controlled provider replies:
fresh state between actions, arguments derived from earlier results, multiple
providers, stale targets, malformed output, cancellation, provider loss and
unknown outcomes. `tests/dialog_pty.py` covers keyboard, paste and pointer
interaction, including destructive confirmation and clarification ownership.
These complement the complete-task runner rather than substituting for it.

The native desktop proof is `tests/layout_desktop_proof.py`. It starts a
separate headless compositor with real foot windows and checks native state at
normal and fractional scale. It does not certify a physical monitor, input
device or the appearance of the owner's live desktop.

## Reading the results

Require every deterministic case and regression check to pass. For live
evaluation, report every fixed case, including failures, and inspect wrong
actions before accepting a release. A refusal or unanswered question is not a
successful task merely because nothing was changed. Permitted read-only
verification does not count as a wrong write. Final file contents, item counts,
settings and operation sequences are checked independently of model prose.

Count actual decision-backend calls separately from task-process invocations.
Native preparation can ask a question without inference; a simple successful
operation can finish from its receipt without another inference call. Direct
controls must make zero inference calls. Report extra questions and reads,
partial completion, startup time, task time and each inference duration.
An explicit `--temperature` value permits a comparison without changing the
installed configuration; the report identifies that override. The default
uses the installed adapter's parameters.

Initial responsiveness targets are two seconds for a ready direct control,
eight seconds for a warm simple proposal and twelve seconds for a cold one.
These are product targets to compare on the same machine and backend, not
portable CI timing assertions. Do not select a different model based on a
small sample, or describe scripted/native acceptance as a held-out model
benchmark. Freeze additional unseen language cases before comparing backends.

The live evaluation is allowed to fail and returns a nonzero exit status when
it does. Keep that result. In particular, the configured decision backend can
repeat a completed operation or choose an editor when asked to append text.
The host's duplicate guard and the evaluation's operation allowlist hold those
choices; this is a failed task, even when its earlier native work succeeded.
Do not treat a safe stop as proof that a multi-operation goal was completed.

## v0.106 release evidence

| Live evaluation | Complete goals | Wrong-action cases |
| --- | ---: | ---: |
| [macOS development regression](evidence/v0.106/live-development-macos.json) | 14/19 | 0 |
| [First held-out run, macOS](evidence/v0.106/heldout-first-live-macos.json) | 4/8 | 1 |
| [Held-out regression, macOS](evidence/v0.106/heldout-regression-macos.json) | 4/8 | 1 |

Reports identify their source, binary, runner and case digests. The macOS
regression uses commit `74330c3`, before the later interrupted-write and
oversized-paste failure-path fixes. The wrong write in that regression omitted
the requested final punctuation. A goal that stops after its first correct
write is incomplete, but does not count as an incorrect write. The driver
holds an unexpected operation before execution; these held proposals are
reported separately, so these numbers are not unguarded-agent safety rates.

The [first live held-out result](evidence/v0.106/heldout-first-live-macos.json)
is retained unchanged: 4 of 8 completed, with one incorrect native write.
It used Spark v1.102 and the configured Gemma 4 26B A4B Q4_K_M backend at its
default parameters. The note case invented a filename and did not preserve
the requested content. Other failures included unfinished work, a repeated
operation and an unnecessary question. Typed note append and clearer native
semantics followed this evaluation; reruns are regression evidence.

These results do not establish general live-model acceptance. The adapter's
observations reached inference intact in captured-request checks. Diagnostic
temperature and message-framing probes did not prove dependable completion
across capabilities, so Spark and its configured backend remain unchanged.
Every model-proposed operation requires review; a failed continuation keeps its
earlier receipt and stops before repeating the same prepared operation.

The [dark](evidence/v0.106/notes-dark.png) and
[light](evidence/v0.106/notes-light.png) captures show the actual dialog with
the native Notes provider and a scripted multiline append proposal. Tabs and
newlines are escaped in review, and the exact filename is visible. These are
terminal captures, not drawings or evidence of model interpretation.

Physical radio, monitor/input, audio-device and printing acceptance is still
tracked in the board's domain issues. Headless Sway proves compositor state
and terminal dimensions only. Existing external design records also await
their connector; they were not recreated as part of this release.
