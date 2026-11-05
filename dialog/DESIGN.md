# The dialog's design

The decisions of 2026-11-04, after the owner's review of v0.123 and
v0.124. One set of rules for every frame, taken from the screens people
already know (Norton Commander, Sidekick, Turbo Vision, the launchers
and the chat boxes of today) and not invented here. A change to the
dialog follows this page; a change to this page is a decision of the
owner's.

The mocks are ASCII: `>` stands for the prompt sign, `-` for a rule,
`<>` and `<*>` for the hollow and the full diamond, `>` after a value
for its arrow, `...` for an ellipsis, and `<- selection bar` marks the
selected row, whose bar is a background that text cannot show.

## The frame

Every view is one column in the middle of the window: 60 cells for
home, apps, help, about and the conversation, up to 120 for a list
with columns, the whole window for a preview. Top and bottom have the
same shape, a strip, a rule, a row of air, then content:

    row 0   the header, a band across the window: back at the left where
            there is a level above, where you are and its state in the
            middle, the x at the right
    row 2   the prompt
    row 4   the prompt's tools: attach, the model, talk
    row 6   a rule with the diamond in its middle, a row of air each side
    row 8   the content, to the status row
    h-5     the status row
    h-4     a plain rule
    h-2     the key bar, a second line at h-1 when the keys need it

The diamond is the frame's one ornament and it carries one fact: full,
in the accent, when a model answers; hollow, muted, when none does or
AI is off. It is read, never clicked. Nothing else in the dialog is
drawn for decoration alone.

The march that says spark is thinking on your words stays in the
header, before the x. Nothing at the bottom animates. The header has
no clock: the bar has it (v0.124.4).

The header is a band (v0.124.5): a slot of its own, the accent at a
quarter over the surface, the tint the desktop gives the place a
moving window would land on, from the window's first cell to its
last. Its words are in the text color, since muted does not read on
the tint; the title is bold; the march is in the accent. The window
has no air of foot's own around its cells: the band and the selection
bar meet the window's edges, and the dialog's margins are the air,
two cells each side and a row under the key bar. A key bar that wraps
in a narrow window takes the row of air above it, h-3 and h-2, so the
last row stays empty. No rule is drawn under the header: the band's
lower edge is the divider. No border: the desktop's windows are flat
and draw none, and sway cannot give one window a line of its own.

In a window wider than the column, a wide one or a full screen, the
frame is the window and the column keeps its measure: the header, both
rules and the key bar take the window's width, the prompt, its tools,
the content and the status row stay in the column, centered
(v0.124.4). The diamond stays in the middle, which is the column's
middle too.

## The prompt

The placeholder reads `search or ask`. Typing searches the list in
front of you at once. Enter opens what the selection bar is on, in the
list and from the prompt: it is the one key anyone has to know.

Asking is a row, not a key. While there are words in the prompt and a
model answers, an `ask spark` row stands last among the matches, with
the words echoed muted beside it, and alone when nothing matches, so
Enter asks. With no model there is no ask row and typing searches
alone. Ctrl+Enter still asks, as a shortcut listed in help and shown on
no chip.

The tools row holds the prompt's controls alone, muted: attach, the
model and talk. An attached file's name replaces the word attach; talk
reads cancel while listening. Tab cycles these three and nothing else.
The model control is the model's name alone, `gemma4-e4b`: here is the
default and says nothing, a server says `gemma4-e4b, remote`, and the
control reads `model off` when asking is off. No glyph after it, and
no separator, which sat over the diamond (v0.124.3).

The model page opens from the control. Its first choice is asking: a
model answers, or off. Off, nothing is asked: no ask row, the diamond
hollow, Ctrl+Enter refused with the reason. The choice is kept across
runs, as talk's is.

The key bar holds the view's keys alone: what Esc does here, close at
home and back everywhere else, then what the list adds (details,
actions, preview, change, month, history). A key chip is a helper and
no control: never lit, never in focus, never a Tab stop; a click on it
sends the key. Enter has no chip in a view's key bar. A mode that
waits on Enter for something other than the selection (run the
commands spark planned, apply a model, land a step in this folder)
says so with its chip, as a question says what it takes.

Back has more doors than its chip (v0.124.3): Esc; with nothing typed,
Left, since Right opens a level, and Backspace, as a launcher's does;
and a click on the header's `< back`, or on its place name. None of
them closes the dialog from home: that is Esc's alone.

The wheel moves the bar a row at a time in a list, as the arrows do,
and three lines in text (v0.124.4). Enter with words typed is never
silent: the words open a place, run a command, or go to the model,
and where none of that can be, the status row says why.

## Selection and action

The selection bar is the one signal: the row's background, from the
column's first cell to its end, the same width on every row at every
size. Nothing else on the row changes: no pointer glyph, no accent on
the name, no bold. The palette's bar color is chosen so muted words
still read on it.

Every pointer sign is gone: the cursor before the bar, the small sign
before an app or a folder, the arrow at the right of home's rows. The
arrow after a value stays, because it says a list opens there.

Two kinds of row, told apart by what they are:

- A menu's row acts on one click: home's places, settings' rows, a
  choice among choices, an action or a preference on a details page.
- An object's row is selected by a click: an app, a file, a folder, a
  note, a window, a layout. Enter or a second click acts on it. Right
  arrow opens its details or its actions, Space previews a file. In
  apps only an app's own row is an object: the managing rows at the
  list's end open pages or run, so they are a menu's and act on one
  click (v0.124.4).

The pointer resting on a row changes nothing. The bar moves by the
arrows or by a click, never by the pointer.

## The status row

The last row above the rule is the one place a message is written:

- the selected object's line, muted, moving only with the bar; the
  whole of what the narrow columns cut: for a file its kind, size, date
  and place; for an app its description, its category, and its launch
  choice where it is not the default;
- a receipt with `undo` at the right, a control in the controls' own
  brush and no key's chip (v0.124.4), or a refusal, while it stands;
  Esc clears it, and so does the next action, talk again, ask or attach
  (v0.124.3: nothing heard stood through the next try);
- an action's march while it is felt: an app opening, a file opening,
  a copy. The header's own frames, with the words, after about a third
  of a second, so a launch that answers at once shows the receipt
  alone. Then the receipt or the refusal takes the row.

A machine read shows no march at all: the catalog, an app's facts and
a folder's rows come when they come.

## Words and casing

Every label the dialog writes is lowercase. A name that is a label is
lowercased too: an app, its role, a window's title, a category, a
note's title. A name that is an identifier keeps its spelling, since
changing it would misname the thing: a file, a drive, a network, a
package manager (XBPS).

A row's second column is muted, whatever it says: what the place
holds now, where the dialog has it, else what the place is for. One
color for the column, so the name leads in the text color and the
words after it read as its line, as a launcher's subtitle and the
status row do (v0.124.2: two colors there read as two fonts). At home,
tools and power have no state worth more than their purpose.

## Home

A menu. Air between its rows when the window has the rows for it, two
rows of air between its groups; the minimum window single spaces and
scrolls.

                                  home                         x   <- header band

      > search or ask

        attach             gemma4-e4b              talk
      ---------------------------<*>--------------------------

        apps         14 installed . 2 hidden

        files        ~ . 3 folders . 2 files

        workspace    3 windows . foot, firefox, btop

        notes        3 notes . shopping, 4 Nov

        calendar     no reminders ahead

        tools        utilities and diagnostics


        settings     dark . 2 screens

        help         38 shortcuts . 12 commands

        about        spark-shell v0.124                      <- selection bar


        power        lock, log out, restart, shut down




      --------------------------------------------------------

      close  Esc

What each second column says, and where it comes from, cheaply and
from what the dialog already holds:

- apps: the catalog's count and the hidden count, once the catalog has
  been read; the purpose until then.
- files: the folder's own summary, as the files section writes it.
- workspace: the window count and their names, lowercase, cut to fit.
- notes: the count, the newest note's title and its date.
- calendar: the next reminder, or none ahead.
- tools: its purpose, since it has no state yet.
- settings: the look and the screens, from what their sections say,
  whichever are known; never the network, whose name is no business of
  the home's first screen.
- help: the counts of shortcuts and commands.
- about: `spark-shell` and the installed release.
- power: its actions.

Words that match a place: the match selected, the ask row under it.
Words that match nothing: the ask row alone, selected.

      > notes

        notes        3 notes . shopping, 4 Nov                 <- selection bar

        ask spark    notes

## Apps

A list of objects, dense under its headings. An app's name and its
role are lowercase. The role is the entry's GenericName, else its
Comment with the trailing period dropped (a comment that only repeats
the name is dropped too), else nothing; cut with an ellipsis at the
column's end and whole on the status row and in the details.

        < back             apps . installed apps                 x   <- header band

      > search or ask

        attach             gemma4-e4b              talk
      ---------------------------<*>--------------------------

      system
        btop++               system monitor
        foot                 terminal
        manage printing      cups web interface

      web
        chromium             web browser
        firefox              web browser                       <- selection bar
        pyradio              terminal radio player
        steam                application for managing and pla...

      office
        aerc                 mail client

        category                                         all >
        hidden apps                                        2 >
        categories                                          >
        refresh apps



      firefox . browse the world wide web . web . application default
      --------------------------------------------------------

      back  Esc    details  ->

One click selects an app and the status row says what it is; a second
click or Enter launches it; Right arrow opens its details. While a
launch is felt the status row reads `opening firefox` with the march,
then `firefox opened`, or the refusal with its reason.

The category headings are the filter (v0.124.4): a click on `web`
shows web alone, the header reads `apps . web`, and Esc shows all
again, its chip reading `all apps` while a filter is on. The headings
stand at the top of every group, so the filter is in reach wherever
the list is scrolled; the arrows skip them, as before. There is no
filter row at the end of the list. The rows that stay there, `hidden
apps`, `edit categories` and `refresh apps`, act on one click. Hidden
is a state of the same apps, not another kind of list: `hidden apps`
opens the list's own shape, the hidden ones under their categories,
the header reading `apps . hidden`, Esc back to all, typing searching
it as it searches the list. Two hundred hidden apps behave as two
hundred installed ones do. With nothing hidden the row is a fact,
muted, and opens nothing.

Every page of apps says where you are in the header: `apps . web`,
`apps . hidden`, `apps . firefox` on an app's pages, `apps .
categories`, `apps . mappings`, `apps . Audio` on a desktop word's
mapping page, `apps . new category` in a form. A form says what to
type in the prompt's placeholder and its key bar says `save  Enter`;
nothing repeats them. Add mapping offers the desktop categories the
installed apps carry and no mapping places yet, to pick, and a word
the catalog lacks is typed. A refresh answers with its count.

A details page is a menu: its facts are not rows; open, the technical
details and the three preferences act on one click, and a change
applies at once with Undo on the status row. Its title is the app's
name, lowercase; the technical details keep the entry's text as
written. An action row (open, new category, add mapping, rename,
delete) stands at the row column like every row; only a checked list's
picks keep a sign cell before their words (v0.124.3). The mappings page
is its heading and its rows, a desktop word and our category: the rule
that resolves them is the README's, not a note above the list.

## Files

The same kind of list as apps. One click selects, Enter or a second
click opens, Space previews, Right arrow opens the actions. The status
row gives the line the narrow columns cannot: name, kind, size, the
date with its time, the place. Names keep their spelling. A folder is
told by its item count where a file has a size, and by its kind
column where there is one.

        < back                   files . ~                       x   <- header band

      > search or ask

        attach             gemma4-e4b              talk
      ---------------------------<*>--------------------------

      home
        documents               12 items
        downloads                3 items
        pictures                40 items
        notes.md                    2 KB   4 Nov              <- selection bar
        todo.txt                    1 KB   2025
        trash                    2 items

      recent
        invoice-0412.pdf          120 KB   today       downloads
        photo-0412.jpg            4.8 MB   yesterday   camera

      drives
        STICK               14.2 GB free

        this folder . 3 folders . 2 files . 3 KB



      notes.md . Markdown . 2 KB . 4 Nov 09:14 . ~
      --------------------------------------------------------

      back  Esc    actions  ->    preview  Space

At 120 cells the kind and the place come back as columns; nothing
else changes.

## About

The page opens on the versions: `spark-shell v0.124` first, the
dialog's own version under it, then the project, the license and the
credits.

## Outside this design

- The typed yes at the prompt stays as it is: a question needs a
  design of its own, not a component borrowed from elsewhere.
- No pane beside the list: the status row is the mini-status, as
  Norton Commander drew it under the panel.
- An app's version on the status row would need its details read at
  every selection; the row says what the catalog knows, and the
  details page says the rest.
