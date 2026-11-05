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

    row 0   the header: back at the left where there is a level above,
            where you are and its state in the middle, the x at the right
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

      home                            Wed 4 Nov . 09:39   x

      > search or ask

        attach   gemma4-e4b . local v   talk
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

      apps . installed apps           Wed 4 Nov . 09:39   x

      > search or ask

        attach   gemma4-e4b . local v   talk
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

      files . ~                       Wed 4 Nov . 09:39   x

      > search or ask

        attach   gemma4-e4b . local v   talk
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
Enter and Right on it open the folder's actions. In a subfolder `..`
stands first and opens the folder above, as Esc, Left and Backspace
do with nothing typed.

### Several files: a check

Insert checks the lit file or folder for one operation and moves the
bar down a row, as Norton Commander's did; Insert on a checked row
unchecks it. A check is a sign cell before the name, drawn as a checked
list draws its picks: the rows' words move to the sign's right while
any row is checked, and back when none is. There is no other mark: no
color on the name, no bold. The status row says the count and the
checked files' size while checks stand, in place of the lit row's line.
Esc with nothing typed clears the checks first; the next Esc goes back.
A check keeps to its row by the row's own identity through a filter and
a refresh, and the pane's checks go when it opens another folder.

      home
          documents               12 items
        v notes.md                    2 KB   4 Nov
          todo.txt                    1 KB   2025            <- selection bar
        v report.pdf                4.5 MB   today

          this folder . 2 folders . 3 files . 4.5 MB

      2 checked . 4.5 MB
      --------------------------------------------------------

      back  Esc    actions  ->    preview  Space

`v` stands for the check sign, at the row column, the words after it
at the sign's right. With checks standing, Right and the
actions chip open the actions of the checked set, whichever row is
lit, and copy, move and trash act on every checked file in the list's
order.

### The actions

Right on a row opens a page of its own, a menu: its rows act on one
click. The header names the row. The row's actions come first, then
the folder's under a heading, so a new folder is in reach from any row
of a folder of thousands. `check` carries its key as a chip beside it,
the one key chip on a row. The rows stand in the provider's order.
Typing narrows the page to the rows the words name, as typing
searches every list, the best match lit so Enter acts on it; words
that name no row leave `no action by these words`, muted.

      < back           files . notes.md                       x

      > search or ask

        attach   gemma4-e4b   talk
      ---------------------------<*>--------------------------

        open                                                  <- selection bar
        preview
        attach to the next request
        rename
        move to a folder
        copy to a folder
        trash
        check                                        Insert

      this folder
        new folder
        new text file
        two panes
        open in the system file manager


      --------------------------------------------------------

      back  Esc

A folder's row has open, rename, move, copy, trash and check; a file's
has `reveal in the system file manager` after attach where one is
configured. `..` and the folder's own row open the folder's actions
alone. With checks
standing the page is the checked set's: the header reads `files . 2
checked`, the rows copy, move, trash and `uncheck all`, then the
folder's. `open in the system file manager` stands only where one is
configured.

### Two panes

`two panes` in the folder's actions opens a second pane beside the
first, showing the same folder; `one pane` closes it. Each pane keeps
its own folder, selection, scroll and typed words. One pane is active:
it has the selection bar, its path on its first row in the text color,
and the header names its place. The other pane has no bar and its path
is muted: nothing else tells them apart, no accent, no frame. The
status row is the active pane's. Ctrl+Tab makes the other pane active,
as Tab did in Norton Commander and Tab here is the prompt's; a click on
a row of the other pane makes it active and selects that row, and a
second click opens it; a click on its path makes it active too. The
key bar adds `pane  Ctrl+Tab` while two panes stand. Space previews the
active pane's lit file in the whole window and Esc comes back to the
panes as they were. Opening a folder, going back, typing and checking
act in the active pane alone.

At 60 cells each pane is 30: the name cut in its middle, its size or
its count, the size column lined up after the widest name as the list
lines its columns up, and the key bar's `pane  Ctrl+Tab` wrapped whole
to the bar's second line. At 120 each pane is 60, the list drawn above. Below 60 cells
the active pane alone is drawn and the other waits, nothing said;
`two panes` asked in such a window is refused: `two panes need a window
60 cells wide`.

      < back          files . ~/documents                     x

      > search or ask

        attach   gemma4-e4b   talk
      ---------------------------<*>--------------------------

      ~/documents                   ~/pictures
        ..                            ..
        drafts         3 items        2024          120 items
        notes.md          2 KB        holiday.jpg     4.8 MB
        todo.txt          1 KB        photo-0412.jpg  4.8 MB
        this folder . 1 fol...        this folder . 1 fol...


      notes.md . Markdown . 2 KB . 4 Nov 09:14 . ~/documents
      --------------------------------------------------------

      back  Esc   actions  ->   preview  Space   pane  Ctrl+Tab

The bar is on `todo.txt` in the left pane. At 120 cells, the left pane
`~/documents` at 60 and the right `~/pictures` at 60, each pane the
list the page draws for a folder: name, size or count, date.

In two panes copy and move go to the other pane's folder, and the
action says where: `copy to ~/pictures`, `move to ~/pictures`. The
other pane on the same folder, on the trash or on a search refuses:
`the other pane shows this folder: open another there`, `the other
pane is not a folder`. In one pane `copy to a folder` and `move to a
folder` pick the folder as today: open folders until the right one,
Enter on the row that lands it here. After a copy or a move the other
pane reads its folder again, so the result is seen.

### The operation and its receipt

One file goes through the provider's step as today, its receipt on the
status row with `undo`. Several checked files run one after another,
in the list's order. While one is felt, a third of a second in, the
status row shows the march with the file and the count:

      copying photo-0412.jpg . 2 of 5

Then one receipt for the whole, with the real counts, and `undo` that
takes the whole back, newest first:

      5 copied to ~/pictures . 12.4 MB                    undo
      3 of 5 moved to ~/pictures, 2 refused: notes.md is there already
      2 of 5 trashed, 3 not: stopped                      undo

Esc while files are being copied, moved or trashed stops after the
file under way, wherever you are, and the receipt says what was done;
the x does the same and the dialog stays open, so no transfer ends
with the window. The next Esc or x closes. A transfer goes on while
you look at home or apps. Typed `undo` at the prompt takes the last
change back too. The checks clear once the operation ends.

### A conflict: a page of choices

Before a copy or a move starts, the names already in the destination
are read from its rows. Each conflict is a page, a menu, never a
message box; the second column says what the choice does, muted:

      < back     files . notes.md is in ~/pictures already    x

      > search or ask

        attach   gemma4-e4b   talk
      ---------------------------<*>--------------------------

        skip                                                  <- selection bar
        keep both              the copy is named notes 2.md
        replace                the one there goes to the trash

      the 2 others too
        skip all
        keep both for all
        replace all


      --------------------------------------------------------

      back  Esc

The second group stands only while more conflicts remain. Esc lets the
operation go and nothing is said: Esc said it. A replaced file is in
the trash and the receipt says so; a conflict the rows could not show
(a file past the first page of a large folder, a hidden one) is refused
by the provider with its reason and the operation goes on with the
rest.

### A form typed in the prompt

Rename, new folder and new text file take their words in the prompt,
as apps' forms do: the placeholder says what to type (`the new name`,
`a name for the folder`, `a name for the text file`), the key bar says
`let go  Esc   save  Enter`, Enter saves and Esc lets it go. Rename
starts with the name as it is, so a letter can be changed. The header
names the form: `files . rename`, `files . new folder`, `files . new
text file`.

### Not in v0

Select all and checks by pattern; sorting other than folders first,
then by name; a cancel inside one large file (Esc stops after it); a
percentage while totals are unknown; archive contents.

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
