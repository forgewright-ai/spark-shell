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
with columns, the whole window for a view. Top and bottom have the
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
actions, view, change, month, history). A key chip is a helper and
no control: never lit, never in focus, never a Tab stop; a click on it
sends the key. Enter has no chip in a view's key bar. A mode that
waits on Enter for something other than the selection (run the
commands spark planned, apply a model, land a step in this folder)
says so with its chip, as a question says what it takes.

Back has more doors than its chip (v0.124.3): Esc; with nothing typed,
Left, outside files, where it is the left pane, and Backspace, as a
launcher's does; and a click on the header's `< back`, or on its place
name. None of
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
  note, a window, a layout. Enter or a second click acts on it. F9
  opens its details or its actions, F3 views it, Space selects a file. In apps only an app's own row is an object: the
  managing rows at the list's end open pages or run, so they are a
  menu's and act on one
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

        help         31 shortcuts

        about        spark-shell v0.124                      <- selection bar


        power        lock, logout, restart, shutdown




      --------------------------------------------------------

      close  Esc

What each second column says, and where it comes from, cheaply and
from what the dialog already holds:

- apps: the catalog's count and the hidden count, once the catalog has
  been read; the purpose until then.
- files: the folder's own summary, as the files section writes it.
- workspace: the window count and their apps, each named once,
  lowercase, cut to fit; no windows open and the layouts' count; with
  no desktop, the layouts by name, else the purpose.
- notes: the count, the newest note's title and its date.
- calendar: the next reminder, or none ahead.
- tools: its purpose, since it has no state yet.
- settings: the look and the screens, from what their sections say,
  whichever are known; never the network, whose name is no business of
  the home's first screen.
- help: how many keys it lists.
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

        < back                  apps                         x   <- header band

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

      back  Esc    details  F9

One click selects an app and the status row says what it is; a second
click or Enter launches it; F9 opens its details. While a
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
click opens, F3 views, Space selects, F9 opens the actions.
The status
row gives the line the narrow columns cannot: name, kind, size, the
date with its time, the place. Names keep their spelling. A folder is
told by its item count where a file has a size, and by its kind
column where there is one. F3 views the row the bar is on, words typed
or not: it is a function key, so typing never opens a view, and v is a
letter of the search as every letter is.

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

      back  Esc    actions  F9    view  F3

At 120 cells the kind and the place come back as columns; nothing
else changes.

The decisions of files v0 (2026-11-05), where the page above was
silent. The rule that decided each: what Norton Commander did, built
from the rows the dialog has.

The status row's place is the row's own folder where the row carries
one (a recent file, a file found), else the folder on screen, written
as the header writes it (`~`, `~/documents`). A folder's line is its
name, `folder`, its count and its place. Typing searches the folder on
screen at once, as everywhere; `files find NAME` and `files say WORDS`
search below it, as lists of their own.

The folder's own row stands last, muted, as drawn above: a summary.
Enter and F9 on it open the folder's actions. In a subfolder `..`
stands first and opens the folder above, as Esc and Backspace do with
nothing typed.

### Keys

One key, one meaning (2026-11-05). The function keys are the file
managers' own: F3 view and F5 to F8 Norton Commander's, F2 rename as in
Windows and the Linux file managers, F9 the menu as in Norton and mc.
Each is a named action, listed in help and free to rebind. A key you
set wins over a default: the action that held it by default goes
unbound, so an old `home-keys.json` never stops home from opening.

      F2      rename                 a row that can be renamed
      F3      view                   a row with a page
      F4      open in app            a file, a folder
      F5      copy                   the lit file or the selection
      F6      move                   the lit file or the selection
      F7      new folder             the active pane
      F8      trash                  the lit file or the selection
      F9      actions, details       every list, the whole dialog
      F10     the conversation       the whole dialog
      Space   select                 files
      Ctrl+C  copy path              files
      Ctrl+Q  quit                   the whole dialog

Left and Right are the panes. Right goes to the right pane, and in one
pane opens the second and goes to it; Left goes to the left pane and
does nothing in one pane; at the edge both stay put. With words typed
they move the cursor in the prompt. Back in files is Esc, Backspace
and the header's back. Ctrl+Tab is the other pane, opening the second
where there is none.

F4 hands the file to the app the system assigns to its kind: a picture
to the image viewer, a text file to the system's text app, a folder to
the system file manager. Enter stays what it was: a folder opens here,
a text file opens in your editor, any other file in its app. Ctrl+C
copies the lit row's path, or the selection's, one path a line.

The key bar is the same in one pane and two:

      back  Esc   nav  <- ^ v ->   ren  F2   view  F3   open  F4
      copy  F5   move  F6   new  F7   trash  F8   actions  F9

Two lines at 60 cells, one at 120.

### Several files: select

Space selects the lit file or folder for one operation and moves the
bar down a row, as Norton Commander's Insert did (v0.125.1: Insert is
far on a full keyboard and a chord on a laptop's; ranger, nnn and lf
select with Space); Space on a selected row deselects it. With words
typed Space is a letter of the search: Down first, then Space selects.
A selected row wears a sign cell before the name, drawn as a checked
list draws its picks: the rows' words move to the sign's right while
any row is selected, and back when none is. No color on the name, no
bold. The status row says the count and the size while a selection
stands, in place of the lit row's line. Esc with nothing typed clears
the selection first; the next Esc goes back. A selection keeps to its
rows by their own identity through a filter and a refresh, and goes
when the pane opens another folder.

      ~/documents                 | ~/pictures
          ..                      |   ..
          drafts          3 items |   2024            12 items
        v notes.md           2 KB |   holiday.jpg       4.8 MB
        v report.pdf       4.5 MB |   photo-0412.jpg    4.8 MB
          todo.txt           1 KB |                              <- selection bar on todo.txt
                                  |   3 items . 9.6 MB
          4 items . 4.5 MB        |

      2 selected . 4.5 MB
      --------------------------------------------------------

`v` stands for the sign, at the row column, the words after it. With a
selection standing F5, F6, F8 and Ctrl+C act on every selected row in
the list's order, whichever row is lit, and F9 opens the selection's
actions.

### The actions

F9 opens the lit row's actions: its rows act on one click, and each
says its key at the right, muted, as a menu does. The header names the
row. In two panes the menu draws inside the active pane, under its
path, and the other pane stays on screen; in one pane it takes the
list's place. The row's actions come first, then the folder's after a
row of air, so a new folder is in reach from any row of a folder of
thousands. Typing narrows the menu to the rows the words name, the
best match lit so Enter acts on it; words that name no row leave `no
action by these words`, muted.

      ~/documents                 | ~/pictures
        open                Enter |   ..                         <- selection bar on open
        open in app            F4 |   2024            12 items
        view                   F3 |   holiday.jpg       4.8 MB
        rename                 F2 |   photo-0412.jpg    4.8 MB
        copy                   F5 |
        move                   F6 |   3 items . 9.6 MB
        copy path          Ctrl+C |
        trash                  F8 |
        select              Space |
                                  |
        new folder             F7 |
        new file                  |
        close pane                |

The rows follow the provider's steps: `attach to the next request`
after view, `reveal in the system file manager` where one is
configured. A folder's row has open, open in app, rename, copy, move,
copy path, trash and select. `..` and the folder's own row open the
folder's actions alone. With a selection the header reads `files . 2
selected`, the rows copy, move, copy path, trash and `deselect all`,
then the folder's. `open in the system file manager` stands only where
one is configured, and `close pane` only in two panes.

### Two panes

Right opens the second pane beside the first, showing the same folder,
and goes to it; `close pane` in the actions closes it. Each pane keeps
its own folder, selection, scroll and typed words. One pane is active:
it has the selection bar, its path on its first row in the text color,
and the header names its place. The other pane has no bar and its path
is muted. A line stands between them, in the rule's color. The status
row is the active pane's. A click on a row of the other pane makes it
active and selects that row, and a second click opens it; a click on
its path makes it active too. F3 views the active pane's lit file in
the whole window and Esc comes back to the panes as they were. Opening
a folder, going back, typing and selecting act in the active pane
alone.

The window never resizes for a pane (2026-11-05). In the normal window
the panes are 29 and 30 cells with the line between them: the name cut
in its middle, the size or the count at the pane's right edge, no date
column, the folder's summary short (`4 items . 4.5 MB`). Super+f gives
120 cells, panes of 59 and 60, the date after the size and the summary
whole. Below 60 cells the active pane alone is drawn and the other
waits, nothing said; Right in such a window is refused: `two panes need
a window 60 cells wide`. In two panes your home shows the folder alone:
no `home` heading and no `recent`, whose files are in other folders.
One pane keeps them.

      < back          files . ~/documents                     x

      > search or ask

        attach   gemma4-e4b   talk
      ---------------------------<*>--------------------------

      ~/documents                 | ~/pictures
        ..                        |   ..
        drafts            3 items |   2024            12 items
        notes.md             2 KB |   holiday.jpg       4.8 MB   <- selection bar on notes.md
        report.pdf         4.5 MB |   photo-0412.jpg    4.8 MB
        todo.txt             1 KB |
                                  |   3 items . 9.6 MB
        4 items . 4.5 MB          |

        notes.md . Markdown . 2 KB . 4 Nov 09:14 . ~/documents
      --------------------------------------------------------
      back  Esc   nav  <- ^ v ->   ren  F2   view  F3   open  F4
      copy  F5   move  F6   new  F7   trash  F8   actions  F9

In two panes F5 and F6 go to the other pane's folder. The other pane on
the same folder, on the trash or on a search refuses: `the other pane
shows this folder: open another there`, `the other pane is not a
folder`. In one pane they pick the folder: open folders until the right
one, Enter on the row that lands it here. After a copy or a move the
other pane reads its folder again, so the result is seen.

### The operation and its receipt

F5, F6 and F8 act at once, with no question: the change applies and
`undo` stands on the status row. The prompt never confirms anything;
Enter submits what is typed there. One file goes through the provider's
step, its receipt on the status row. Several selected files run one
after another, in the list's order. While one is felt, a third of a
second in, the status row shows the march with the file and the count:

      copying photo-0412.jpg . 2 of 5

Then one receipt for the whole, with the real counts, and `undo` that
takes the whole back, newest first:

      5 files copied to ~/pictures                        undo
      3 of 5 moved to ~/pictures, 2 refused: notes.md already exists
      2 of 5 trashed, 3 not: stopped                      undo

Esc while files are being copied, moved or trashed stops after the
file under way, wherever you are, and the receipt says what was done;
the x does the same and the dialog stays open, so no transfer ends
with the window. The next Esc or x closes. A transfer goes on while
you look at home or apps. Typed `undo` at the prompt takes the last
change back too. The selection clears once the operation ends.

### When the name exists

Before a copy or a move starts, the names already in the destination
are read from its rows. Each one stops the operation on a list of
choices inside the active pane, a menu, never a message box, with the
other pane in view; the header says what happened:

      < back          files . notes.md already exists         x

      > search or ask

        attach   gemma4-e4b   talk
      ---------------------------<*>--------------------------

      ~/documents                 | ~/pictures
        replace                   |   ..                         <- selection bar on replace
        replace all               |   2024            12 items
        skip                      |   holiday.jpg       4.8 MB
        skip all                  |   notes.md            1 KB
        keep both                 |   photo-0412.jpg    4.8 MB
                                  |

      --------------------------------------------------------

      cancel  Esc

`replace all` and `skip all` stand only while more names remain. Esc
cancels the operation and nothing is said. A replaced file is in the
trash and the receipt says so; `keep both` numbers the new one (`notes
2.md`) and the receipt names it. A conflict the rows could not show (a
file past the first page of a large folder, a hidden one) is refused
by the provider with its reason and the operation goes on with the
rest.

### A form typed in the prompt

Rename, new folder and new file take their words in the prompt, as
apps' forms do, and the panes stay on screen: the placeholder says what
to type (`new name`, `folder name`, `file name`), the key bar says
`cancel  Esc   save  Enter`, Enter saves and Esc cancels. Rename starts
with the name as it is, so a letter can be changed. The header names
the form: `files . rename`, `files . new folder`, `files . new file`.

### Not in v0

Select all and selecting by pattern; sorting other than folders first,
then by name; a cancel inside one large file (Esc stops after it); a
percentage while totals are unknown; archive contents.

## The header's second part

State, or a place within the place, never a restatement (v0.127):
`apps` alone at the top of the list of every app, `help` alone at the
top of help; `apps . web`, `apps . firefox`, `files . ~` and
`power . up 3 days` stay.

## Help

One list by subject, searchable, scrolling: `in home` and `in a
view` are the dialog's keys as bound now, a sentence each;
`windows`, `workspaces` and `the desktop` are the desktop's, as the
about provider sends them; `at the prompt` is the words typed there. A
row is what you do, its key a chip at the right where the rows' arrows
stand; the sentence is whole on the status row while the row is lit.
Arrows, Home, End, Backspace and Delete need no help. Words typed keep
the rows they name, under their subjects, and the ask row stands last
when a model answers. The last lines are a note: the keys are yours to
change. Home's column is how many keys it lists.

        < back                  help                         x   <- header band

      > search or ask

        attach             gemma4-e4b              talk
      ---------------------------<*>--------------------------

      in home
        open what the bar is on                          Enter
        back a level; at home, close                       Esc
        ask spark the words                         Ctrl+Enter   <- selection bar
        a new line in the prompt                   Shift+Enter
        the conversation, and back                         F10
        the prompt's tools, one to the next                Tab
        a row's view                                        F3
        a row's actions or details                          F9
        select a file, and the next                      Space
        the other pane                                Ctrl+Tab
        a page up, a page down                PageUp  PageDown

      in a view
        bigger, smaller, as it fits                    +  -  0
        the page before, the page after                   <  >

      windows
        a terminal window                         Super+Return
        ...

      ask spark the words . Ctrl+Enter
      --------------------------------------------------------

      back  Esc

## About

Facts, then the rows that open, then where it is installed. The
installed release with the day of its tag, the dialog's own version
aligned under it, a row of air, the purpose line; `project` opens the
address in the browser, `license` and `credits` open the files as
read-only pages (Esc comes back with the row lit), `help` goes to
help. The status row says what the lit row does: `project . opens in
the browser`, `license . MIT . LICENSE in ~/.spark-shell`.

        < back                  about                        x   <- header band

      > search or ask

        attach             gemma4-e4b              talk
      ---------------------------<*>--------------------------

        spark-shell  v0.127               released 5 Nov 2026
        spark-dialog v0.127.0

        a lightweight sway shell

        project  github.com/forgewright-ai/spark-shell       <- selection bar
        license  MIT
        credits  48 projects and their licenses
        help     31 shortcuts

        installed at ~/.spark-shell



      project . opens in the browser
      --------------------------------------------------------

      back  Esc

## Power

Five verbs, one word each, each shown where it can act; the fact row
where restart and shutdown cannot; the uptime a fact under them, a row
of air before it, as the facts at any menu's end stand apart. What each
does is the status row's line while the row is lit, from the row's
wide column: `lock . the screen . Super+Escape`, `suspend . the screen
locks first`, `logout . every window closes`, `restart . asks first`.
Suspend answers `back from suspend` when the machine wakes; lock has
no receipt.

        < back              power . up 3 days                 x   <- header band

      > search or ask

        attach             gemma4-e4b              talk
      ---------------------------<*>--------------------------

        lock                                                   <- selection bar
        suspend
        logout
        restart
        shutdown

        up 3 days



      lock . the screen . Super+Escape
      --------------------------------------------------------

      back  Esc

## The question

Wherever a step loses something (power's logout, restart and shutdown;
forget a network, close a window, pair a device, set up the network
manager, empty the trash; any spark-planned destructive step), the
dialog asks on a page of its own, never a message box and never typed
words: the verb as the heading, one note in parentheses (the last
sentence of the tool's description, lowercase), two menu rows, the verb
and `keep working`, which is lit first (v0.127.2), so Enter again keeps
and the verb takes Up or a click. Enter or a click on the verb acts; `keep working`,
Esc and every back door keep; typed words are refused. The header says
the verb; the key bar `keep  Esc`. A spark-planned step's heading is
its line.

        < back              power . shutdown                  x   <- header band

      > search or ask

        attach             gemma4-e4b              talk
      ---------------------------<*>--------------------------

      shutdown
        (everything open closes and the machine turns off)

        shutdown
        keep working                                           <- selection bar



      --------------------------------------------------------

      keep  Esc

## Workspace

The decisions of 2026-11-05. One list: where every window is, the
layouts, then what a menu does. `<s>` stands for the bar's symbol of a
workspace, and a `v` before a pick for its check.

        < back           workspace . 4 windows               x   <- header band

      > search or ask

        attach             gemma4-e4b              talk
      ---------------------------<*>--------------------------

      workspace 1 <s> . HDMI-A-1
        firefox              claude code
        foot                 ~/projects

      workspace 2 <s> . this one . eDP-1
        foot                 btop                              <- selection bar
        chromium             invoice-0412.pdf

      also open
        btop                 suggested for writing

      layouts
        writing              foot, firefox
        news                 newsboat, firefox, mpv

      recent
        read the news        newsboat, firefox, today 09:12

        capture the screen   Print
        capture an area      Shift+Print
        arrange windows                      side by side >
        save this workspace


      foot . btop . workspace 2 . floating
      --------------------------------------------------------

      back  Esc    actions  F9    view  F3

A heading names a workspace by its number, the key, and the bar's
symbol, what you see; with numbered workspaces on, the number alone. A
layout's name follows where the workspace has one, `this one` marks the
workspace you are on and stands even when it is empty, and the screen's
name stands only with two screens or more: a workspace sits on one
screen, so a column per row would repeat it. Every heading is the
filter, as apps' categories are: a click shows it alone, the header
reads `workspace . 2 <s>` or `workspace . layouts`, Esc's chip reads
`all windows`.

The header says what the place holds: `workspace . 4 windows`,
`workspace . no windows`, `workspace . no desktop`. The bar starts on
the window that was in front, so F9 acts on what you were using.

A window's row is its app's name and its title, muted, both lowercase;
two windows of one app differ by title. A window in sway's scratchpad
is not listed. The status row says app, title, workspace and placement;
a layout's says its name, its apps and its reason. At 120 cells a
window's placement and a layout's reason come back as columns; nothing
else changes.

Only a window's row and a layout's row are objects: one click selects,
Enter or a second click puts it in front or opens it, F9 opens its
page, F3 its view. Capture, arrange, save and `also open` are a
menu's rows and act on one click.

A window's page keeps to 60 cells at any width. Its rows are a menu's;
the two choices show what the window has now and open a checked list,
as apps' do. A pick goes back to the page with the change on the status
row and `undo`.

        < back              workspace . foot                 x   <- header band

      foot
        btop

        put in front                                           <- selection bar
        move to workspace                                2 >
        placement                                 floating >
        capture this window
        close

      move to workspace                  placement
          1 <s>     firefox, foot            tiled          Super+Shift+space
        v 2 <s>     foot, chromium         v floating       Super+Shift+space
          3 <s>     empty                    full screen    Super+f
          ...                                left half      Super+Left
          10 <s>    empty                    right half     Super+Right
                                             top half       Super+Up
                                             bottom half    Super+Down

A move leaves you where you are, as Super+Shift+3 does. `full screen`
closes the dialog, since sway draws it over the dialog. Close keeps the
typed yes. Sway keeps resize, drag, split direction and focus order;
moving to a screen is no action, since a workspace sits on one screen.

`arrange windows` is one row, because sway cannot put only a
workspace's new windows in tabs: tabs and a stack are a state of the
container the windows share. So it changes this workspace now and is
the default for every new workspace, and its value is read from the
workspace you are on. Its list has `side by side`, `tabs` and `stacked`
with their keys, and a note saying that. Undo puts back both.

A layout's row shows its apps. Its page offers open, rename and delete;
a recent one's, open, save as and forget. Delete and rename carry
`undo`, and delete takes no typed yes, from a row or from a step spark
plans. `save this workspace` is a form in the prompt: the header reads
`workspace . save layout`, the placeholder `a name for this layout`,
the keys `cancel  Esc    save  Enter`. It keeps the apps and how they
stand, not their sizes. Opening one closes the dialog once its windows
are there. A layout asked in words follows the prompt's rules: the ask
row, the step in the prompt, nothing opens before Enter, the result
under `recent`.

A capture steps the dialog aside and it comes back on the same page
with the file's name on the status row, or the reason there is none. A
picture changes nothing, so it has no undo. `capture this window` puts
a window on another workspace in front for the picture, and you end
where you began.

With nothing open the heading of this workspace stands over `no windows
here`; with nothing saved, `layouts` stands over `none saved: ask at
the prompt or save this workspace`, or `none saved: save this workspace
to keep one` when no model answers. `save this workspace` is muted when
there is nothing to save, as `hidden apps` is; `arrange windows` stays
live, since it sets the default. With no sway the header says `no
desktop`, the layouts stand alone, and the selected one's line ends
`opens in tmux`: no note stands over the list.

Saved sizes and splits, a picture of the window in its view,
renaming a workspace and acting on several windows at once wait.

## Outside this design

- No pane beside the list: the status row is the mini-status, as
  Norton Commander drew it under the panel.
- An app's version on the status row would need its details read at
  every selection; the row says what the catalog knows, and the
  details page says the rest.
