# house — the standalone window over the home

A Godot 4.7 project, shown to people as **Asterion**: one isometric room and one sidebar. The home keeps in sight what the operator's
jots left open, what is coming, and the newest notes. `main.gd` polls and posts the home's data,
`room.gd` draws the room (floor, walls, furniture, a front door), `sidebar.gd` is everything
that is not the room (below).

**The sidebar** is one 360 px column on the right of the full window (`Sidebar.WIDTH`), always there;
the room takes the rest and is drawn as large as whole steps of its art fit (`room.gd` `fit_scale`,
applied by `main.gd` `_fit_room` as the room Control's scale; the 3x art is the largest). Nothing
floats over the room but pet bubbles, a short hover name (gone when the pointer leaves or has been
still for 2 s) and the selected thing's gold outline. Top: an optional banner strip (the rhythm slip,
a reply, a ringing reminder; buttons, never covering the pane, never closing a view, never taking a
room click), then the header and the context pane, a paper sheet. The header has one layout in every
view: a fixed left slot (a drawn back chevron, tooltip "Back (Esc)", empty at Home), the view's title
in the pixel face ("Home", "Calendar", "Settings"), and on the right the drawn plus (tooltip "Add (I)")
and the settings cog, always in the same place. Bottom: the chat dock. `sidebar.gd` owns the views and the
chat modes; `views.gd` builds Home, an item, the "On the desk" list; `blocks.gd`
turns a card's blocks (title, text, dim, gap, month, buttons, row, foot, day) into Controls.
**One look for the sidebar.** `fonts.gd` holds the type scale: the pixel face only for the view title
(`TITLE`), one body face for everything else at `BODY`, `SMALL` and `LABEL` (a section's label: small, dim,
`Paper.section`); text is sentence case. `paper.gd` holds the three button styles: primary (filled, at most one
per group: Done, Save), secondary (a 1 px outline at low alpha, the default of `Paper.chip`) and quiet (text
only, underlined on hover: Something else, Not today, Cancel, "no"); a block's button or a row's mark takes
`"k": "primary"|"quiet"`. A chip (a kind or a personality) is the secondary look unselected and a gold fill
selected. Arrows, the plus and the chat's handle are `icons.gd` drawings (`icon_button.gd` is one as a
button), never characters; a shortcut is in the tooltip.
Views: `home` (in this order, an empty section drawing nothing, not even its label: "Now", the pick with Done /
Something else / Not today, and the pinned thing with its timer; "Today", what has a time today in time
order, each row time-first in one aligned column: meetings still on (a quiet line, "09:00  Standup": no tick, no click), reminders due today and an
agenda due today; "Open", the to-dos but not the pick or the pinned thing, six with "N more..."; "Proposed (N)" when sources have suggested things (`proposals` of `GET /api/home`: `{id, source, text, why, url}`; `views.gd` `_proposed`: three rows, each its text with the why line small under it and two small buttons, "add" and "no", which post `/api/home/proposals/:id/take|dismiss`; then "N more..." in place; never a banner, a ring or a badge; the family's local list has no sources and answers none; "Later (N)", the coming things after today, one line that opens in place; the weather in one line, which opens the window's view; "Notes (N)" collapsed. At 1100x700 with the demo list and the dock compact Home does not scroll; the soak holds it), `card`
(calendar, jar, window, clock, board, plant, book, mousehole, fireplace, piano, globe: `home.card`
holds which, `home.card_blocks` the blocks; the "book" card is the shelf, `shelf.gd`: Agendas (a row each
with its note count and when it is next, worded by the time rule below; "new agenda" asks a name), then every note newest
first, Someday, Projects (each shows 8 then "N more...", a filter line over 8 rows) and all the Borges
titles, a click on a title showing the pet's remark under it and granting the "book" find; a note,
someday or project row opens its item view; a note's has Edit and Delete, and the board's notes tab,
Home's expanded notes and the shelf all open it; a note with no id opens the board's notes), `agenda` (an
agenda's pile, `views.gd` `agenda_view`: its rhythm as text, its notes, each opening as a note, an add line where
Enter puts a note on it, and Clear, which archives the pile; opened from a shelf row or from Home's row
"14:00  Retro · 3 things" under "Today" when an agenda with notes is due today; back from it goes to the shelf
it came from. The data is `agendas` of `GET /api/home`: `{id, name, every, next_at, notes}`; the notes are in no
other list), `people` and `door` (`people_view.gd`, below), `item`, `open`, `add` (`jot.gd` the jot line alone and what the house read it as; `form.gd` the
typed form, behind its "Fill in the details instead" link), `edit`, `pet` (`pet_view.gd`), `closet` (`closet.gd`), `settings`
(`settings_view.gd`), `decorate`. A click on a thing replaces the view; the back chevron, Esc and a click on
empty floor go back. The chat dock (`chat_view.gd`, "Chat") is its input line alone until there is a real exchange: a line he typed or the house's word to him (a pet's passing remark is logged and shown once the dock is open, but never grows it). It grows
to its docked size (30% of the sidebar, 176 px at least); its handle
(two drawn chevrons) collapses it to the input line or gives it the whole sidebar; it is the input line alone
while a thing's view is open, and `K` or a click on the phone brings it up. While a LineEdit or TextEdit has focus no letter hotkey fires (`main.gd` `_input`).

**Meetings** are `meetings` of `GET /api/home` (`Server.Home.Day`: today's remaining and tomorrow's, already
cleaned, UTC, `home.meetings`; over the local list the same rows from the calendar feed (below), `[]` with none set); Today lists the ones still on. The wall calendar's card reads the month in view from `GET /api/home/meetings` (once per
month while the view is open, again when it is reopened; `things.calendar_blocks` asks, so every way of opening
the card does: `things.want_meetings`, `month_meetings`; the local list answers the feed's, `[]` with none set). A month's rows stay as
last fetched: a failed refetch keeps the last good copy, and a failed first one shows "nothing" until the card
is reopened. With no date picked it shows Today and Tomorrow, each headed with its date, its meetings
then the home's own things, "nothing" when it has neither; a clicked date shows its own block (headed "Today ·"
or "Tomorrow ·" when it is), and clicking it again goes back. A tentative meeting is dimmed, one that
has ended dimmer still (the `meet` block; the same ink, a lower alpha, no new colour). The grid marks a day with meetings with a blue dot beside the red one for the home's own things, and
tomorrow with a pale disc beside today's filled one. Nothing in the house writes a calendar, scores a meeting
or says a word about one. `--demo` makes its meetings from `demo.json` relative to now.

The home is a lived-in room, not a dashboard. `home.gd` owns its state and the order it draws in
(it hands `room.gd` sortable items); `pets.gd` is Nina, Argos and the grid they and the person walk
(perches, toys); `voices.gd` is what they say; `props.gd` is everything the packs do not have, drawn in code (paper,
corkboard, calendar, phone, notepad, bubbles, light and weather). One file per thing that lives in it:
`person.gd` (the person's activities), `look.gd` (who they are: layered composition, flat fallback,
saved choice), `tv.gd` and `hacks.gd` (the TV and its screen hacks), `view.gd` (the window's scene),
`closet.gd`, `jot.gd`, `focus.gd` (the now pin and its timer), `jar.gd`
(the done jar), `knock.gd` (Nina's one nag),
`rhythm.gd` (the day's two beats and their banners), `layout.gd` (the furniture and the rules of placing it),
`decorate.gd` (the catalogue and the pointer work of decorating), `pet_view.gd` (the pet view) and `pet_now.gd` (its "right now" phrase). `drive.gd` (`--drive`: the live house driven over TCP). `soak.gd` is the scripted check, `logic.gd` the logic-only one.

Where the list lives is one `Backend` (`backend.gd`): `backend_http.gd` is the tlon server, `backend_local.gd`
the house's own file (`local_list.gd` the list, `reader_rules.gd` the loose-line reader; agendas are there too,
added through the shelf only: the reader has none, and an agenda's pile is told once, 15 minutes ahead, to the
house's own Telegram chat as reminders are, `told_agenda`). `main.gd` holds one and
never asks which. The sections below describe the server's list; with `where` = `local` (below) the same room
runs on the local list.

- Notes are slips pinned to the corkboard (four shown, "+N" for the rest); hover shows the
  whole note, a click opens the board view. Open things are stickies on and around the monitor and a stack of paper on the desk
  whose height and small badge follow the count. A reminder's next due time is the wall calendar
  and the caption above the room, in local time.
  **Times** (`when.gd`, the one function every due time the sidebar prints goes through: Home's rows, Later, the item
  view, the calendar's rows and "Coming up", the clock and plant cards, the shelf's agendas, the caption above the
  room): today the time alone ("14:00"), tomorrow "tomorrow 14:00", the next six days "Sat 14:00", later the date
  ("28 Nov"); past due "since 09:00" today, "since Tue" before, the date a week back; never red. A repeating
  thing's rhythm is a small dim suffix, never part of the title. `--demo`'s rows carry `in_days` and a local `at`, so
  they never go stale; due times are UTC `Z` and shown local.
- Ticking a thing off (after the server says 200) crumples its paper into a ball that arcs into the
  bin; sometimes it misses and Nina chases it in. The last one ticked is a little confetti.
- The room keeps the machine's clock and `weather` from `/api/office` (light, lamp, a sun patch).
  The big window over the sofa is the view: sky by local time (dawn, day, golden hour, dusk, night
  with moon and stars), a skyline, hills and a tree, and the weather kinds of `weather.ex` on top
  (sun, drifting clouds, fog, rain with a wet glass, storm flashes, snow that settles on the sill).
  Hover shows the description and the temperature in his `degrees`. Nina sometimes sits on the sill. The plant droops a
  little as more things are open (with a watering chore it follows the chore, below); no text says so.
- **The person** (`person.gd`) walks the pets' grid and picks by state: at the desk in the chair
  (typing) when things are open, on the sofa when clear, watching the TV now and then when nothing
  is open (10:00-23:00), at the board or with a coffee now and then (mornings), asleep on the sofa
  late at night when no reminder is open, standing up to stretch when a timer ends, at the desk with
  a "!" when the phone rings. The chair and sofa seat are reached by a short step from a standing
  cell; pets treat the person as air (they never route around or get stuck on him). Click him for a
  line. Seated on the sofa he sorts after the window, so head and shoulders show over the back.
- **The TV** (`tv.gd`, `hacks.gd`) is just a TV: it knows nothing of the computer. It is on while
  the person watches and off otherwise and in the deep night. A click on it (no view)
  turns it off if on and on if off, and that choice holds until the next click or until the
  automatic state changes (he sits down or leaves, or the deep night begins), whichever is first.
  On, it runs one of the code-drawn screen hacks (`spectrum stars plasma logo
  rain life pipes moire scope sunset fireworks toasters note`), a new one every 2-4 minutes through
  a short static flicker, never the same twice in a row.
  Add a hack: a `_name(c, q, t)` drawer in `hacks.gd` and its name in `NAMES`. Nina sometimes sits
  in front of it when it is on.
- **The done jar** (`jar.gd`) is a glass jar on a shelf over the bin: one marble per thing done this
  week (`done_week`, drawn up to 27, colours stable per week). A thing done drops a marble with a
  bounce and a clink mark; a new week (Monday) starts it empty, quietly. Hover: "N done this week".
  The count is `done_week`; names come only from a `done` list in the status.
- **Thing views** (`card.gd` holds which; blocks built in `home.gd` `card_blocks`, drawn by
  `blocks.gd` in the sidebar pane): a click on the calendar, jar, window, clock, board (cork, a note
  or the "+N" tag), large plant, bookshelf, mouse hole, fireplace, piano or snow globe opens its view
  in the pane, replacing the one before, and outlines the thing in the room; hover shows only its
  short name. the back chevron, Esc and a click on empty floor go back. No view opens in decorate mode. A
  rhythm banner never stops a click. The piano plays and the globe shakes on the click that opens
  its view; the fireplace view has a lit/unlit button and an "into the fire" list.
  Calendar: the month grid with a dot on each day a reminder falls (a repeating one on each of its days,
  `every` being `day|week|month` or `"N unit"`, worded "every other week", "every 6 weeks"), today
  marked, two drawn arrows (and the arrow keys) for the month and a click on its name for today's; a click on a
  day lists that day's things and an "add" button; the next five coming up when no day is picked.
  A click on a thing opens its item view. The card says nothing of a birthday (it is set in Settings) except on the day itself, in a
  line. "Coming up" rows are one clipped line each: the time by the time rule and the text, the rhythm ("every week") small and dim at the end. Jar: the count, and the names newest
  first when the status has `done` (`[{text, done_at}]`; ten shown). Window: the weather in words
  and the temperature in his `degrees`, then up to three forecast rows (Today, Tomorrow, the weekday; an icon
  from `forecast.gd`, high / low, the chance of rain or snow from 20%; none when there is none, no "unavailable"
  line; days before today are dropped, the server may hold a stale forecast). The forecast is `GET /api/home`'s
  `forecast` (`[{date, high_c, low_c, kind, wet}]`; an older server has no key). Clock (a `clock` piece on a wall): the time and date, the next reminder and how long
  ("in 2 h 10 min"), and timers: in 10 min / 30 min / 1 h make a reminder "timer" at once, "named..."
  opens its form. Board (`things.gd`, tabs): Notes (five a page, "add a note", an `x` that asks "sure?"
  once), Projects (each with its open step and the plan; a project's page has Done/Delete on the open
  step, the planned steps with up/down/remove, the steps done dimmed, "add a step", "finish project",
  Delete asking twice, "new project"), Waiting (who and how long, "got it", `x`, "add") and Someday
  ("bring back", `x`). Plant: when a repeating reminder
  that mentions water or the plant is next due, else a plain line. TV: the screen hack playing and a
  Next (or Turn on) button; no play state, no media titles. The pets' bowls and bed have none.
- **Argos celebrates** every done thing: runs to the desk and hops, with a line. He greets the person
  at the door when he comes in. **Nina's one nag**: when the oldest open thing without a future
  `due_at` has sat over 3 days (`since`), she now and then (checks every 3-10 min, 4 h apart at
  most, 08:00-21:00, never at night) walks to the desk and knocks that sticky onto the floor
  (`knock.gd`); one at a time; it lies there until clicked, which opens its item view and puts it
  back on the desk. It is not kept across restarts, only the time of the last knock. She also sits on
  the notepad now and then while the jot field is closed.
- **The day's rhythm** (`rhythm.gd`), each beat once a day, remembered in `user://house_rhythm.json`:
  at the server's `home_list_at` (`GET /api/settings`, `knobs[].key`; empty never; 17:30 until
  read) he comes home through the door with a bag, Argos greets him, and a banner of what is still open
  shows for 14 s (an item opens its view; "Put away" or Esc ends it; it waits while the pointer is on it); for 3 h after
  that time at most. In the morning (first run after 05:30, or the clock passing 08:00, before noon)
  he stretches and a banner shows what is coming today. Late at night with nothing due the lights dim
  further, he sleeps, the TV is off, Nina sleeps on the sofa and Argos on the rug beside it.
- Small things: a "water the plant" thing done perks the plant up for 10 min with a can and drops;
  a note, open thing or reminder due today that says birthday or anniversary hangs bunting; the
  window gets lights in December, a pumpkin from 25 Oct, hearts 10-14 Feb.
- **Chores** (`chores.gd`, wired in `home.gd` `chores`): a repeating reminder (`kind` reminder, `every` and `due_at`
  set) whose text names a chore thing is that thing in the room, so the operator glances at the room instead of a
  list. `Chores.TABLE` is the one table, first match wins, words matched whole and case-insensitive ("binder" is not
  "bin"): laundry, washing: the laundry basket; trash, bins, bin, garbage, recycling, rubbish: the bin; feed with
  cat, dog, pets or a pet's own name (`Settings.cat`/`dog`): the pets' bowls; meds, medication, pills, vitamins:
  a pill bottle on the desk; water with plant or plants: the large plant. Of two rows for one thing the more urgent
  stands for it (due, then soon, then fine; the earlier time breaks a tie) and the other stays a list row.
  Each thing shows three states, from the row's `due_at` and `every` and the house clock (`Chores.state`): *fine*
  (far off), *soon* (less than half an interval left) and *due* (due today or gone by). Laundry: an empty basket, a
  mound filling it, a heap over the rim with a sleeve down the side. Bin: lid shut, lid lifted, mouth open with the lid
  on the floor, a tied bag and a fly. Bowls: full, low, empty and dark (both bowls follow, the food one can sit
  behind a pet thing). Bottle: on its side, upright capped, upright with the cap off. Plant: perky and in flower,
  soft and leaning, drooped and drab (with no watering chore it droops with the open count as before). No text, badge
  or red. Hover says `short name · when` ("laundry · due today", "bins · Thursday", `Chores.hover`); a click opens the
  chore's item view and outlines the thing (`chore:<thing>` hits, "plant" for the plant; `sidebar.gd`
  `selected_key`); Done, through `main.gd` `_remove`, keeps the thing as it was until the read of the room that began after the
  write has come (`home.chore_reload`; a read already on its way does not end it, and `Chores.HOLD` ends it anyway), shows the old state for `Chores.PAUSE`, then fine with a
  moment of its own (clothes lift, the bag goes, sparks, the bowls pour, the can waters), and the server or the local
  list moves the row to its next time (the demo does it in `_demo_repeat`). A chore whose thing is in the room is left
  out of Home's Today, Open and Later (`home.chore_thing_of`); it stays on the calendar card and in its item view, and
  the Now pick may pick it. With its thing not in the room (the basket taken away, the pet things off) it is a list
  row as any other; a repeating row whose rhythm does not read (`Chores.interval` 0) is no chore. The basket is the plain piece `laundry_basket` (default cell 0,10, the corner by the piano, in decorate's home tab), drawn in
  code and never as a sprite row, at the depth of the cell it stands in (`_basket_key`); a saved layout from before it is
  offered it once on load (`Layout.NEWER`, `offered` in the file: its cell, else the nearest free one) and a basket taken
  out stays out. The bin, desk and plant are fixed so their chores are always in the room. Add a
  chore: a row in `TABLE`, a name in `NAMES`, a drawer in `chores.gd` and a hit in `home.gd`; `logic_chores.gd` holds the
  table, the rhythm, the states and the words; `soak_chores.gd` the hits, the lists, the basket's place and record, and
  Done over the demo, the stub server (a delayed read, a read already in flight) and the local list. `--demo` has laundry (soon),
  bins (due today) and feed the cat (fine).
- **People** (`people.gd` the rules and the two drawings, `people_view.gd` the views): `GET /api/home` sends `people`,
  `[{id, name, birthday ("MM-DD" or "YYYY-MM-DD" or null), next_birthday (local date, today counting, or null), notes:
  [{id, text, since}], todos: [the open rows that name them]}]`, soonest first, none last. The framed photo is the
  plain wall piece `photo_frame` (a framed group photo hung on the north-east wall, default cell 10,0 beside the bookshelf, face `ne`, in decorate's home tab; drawn in
  code at its cell's depth, `_frame_key`; offered once to a saved layout through `Layout.NEWER`; a frame a file saved before `Layout.SAVED` 4 holds on the floor cannot stand on a wall, so it goes to the default cell, else the nearest wall cell, on load; movable along the wall like a painting, and on the north-west wall too, where it is drawn with a turned pen (`People.turned`), the picture mirrored; it is refused in a cell where a piece taller than its lower edge (`People.BOTTOM`, 20) or a hugging piece stands in front of it, and such a piece is refused in front of it: `Layout._clear`). It wears a small red bow while a birthday is a week away or less (`home.frame_marked`, `People.SOON`). Hover
  says "the people" and outlines it in gold like the door (`_hover_outline`); a click opens the People view and keeps the outline (`frame` hit). A card is the name, the next birthday
  in `When.birthday` words ("in 3 days · Mon 23 Nov", "today"), the notes (an add line; a quiet "drop" is
  `POST /api/home/:id/drop`, which is how a note comes off, `done` is 404 for one), then the to-dos naming them,
  tickable as on Home. "Add a person" and "edit" open one form: a name and a birthday that says what it read
  (`SettingsView.parse_birthday`); a birthday sent only when its text changed, null when emptied; Remove asks twice
  (`Sure`, `rm:<id>`). Writes: `POST /api/home/agendas {name, kind: "person", birthday?}`, `.../agendas/:id/edit
  {name?, birthday?}`, `.../agendas/:id/add {text}`, `.../agendas/:id/drop`; a 400's `error` is shown over the view
  (a name already taken, a birthday that is no day). The wall calendar marks a birthday's day with a small pink
  diamond and lists "Sam's birthday" under it (from the stored `birthday`, 29 Feb on the 28th in a year without
  one); Home's Today has one calm row on the day itself, which opens People. Over the local list people are agendas
  with `kind` "person" and a `birthday`, and the to-dos naming them are found by text or `who`. `--demo` has Sam
  (in three days), Jude and Robyn (no birthday). `logic_people.gd` the rules, the words and the list's keeping;
  `soak_people.gd` (sections `people` and `door`) the stub server's routes, the views, the marks and the layout.
- **The door** is the front door and a click target (`door` hit, a gold outline on hover, "the door"). It opens a little
  when the person comes in or a visitor calls. `door: {id, notes: [{id, text, since}]}` of `GET /api/home` is the pile
  of notes left by it: a canvas tote with an umbrella stands in the doorway cell while there is one
  (`People.door_state`), and a click on the door or the tote opens "By the door": an add line
  (`POST /api/home/door/add {text}`) and each note with a tick that drops it (`POST /api/home/:id/drop`). The pile is
  never edited or dropped as a whole. Over the local list it is an agenda with `kind` "door", in neither the shelf nor
  the agendas of the status.
- **Money** (`money.gd` the rules and the pig, `logic_money.gd` the checks): `money` of `GET /api/home` is `{balance,
  available, as_of, due_this_week: [{name, amount, on}], next_deposit: {name, amount, on} | null, accounts}`, amounts
  cents, null when the bank is off; `things.money` holds it, null over the local list and from an older server. The piggy
  bank is the plain floor piece `piggy_bank` (a pig in profile drawn in code at its cell's depth, default cell 5,8, a cell of the dining table's top; a bank may stand on any cell of `Layout.TABLE_TOPS`
  (`Layout.table_under`) or on open floor. On a table it is drawn in the middle of the table's top, whichever of its cells it is on
  (`Layout.seat`, a little toward the front, `SEAT_FRONT`, so the feet's level line clears the sloping back edge), at that table's drawn top (`TABLE_TOPS` holds each one's height, below the sprite's `height`, which is its rim), after the table; its hover, hit,
  decorate's ghost and outline follow it there; in decorate's home tab, movable like the
  basket, offered once to a saved layout through `Layout.NEWER`; a file's rows are placed bank-last so the table is there first). A basket or bank a file saved before `Layout.SAVED` 4 holds on its old default cell (`Layout.OLD_DEFAULTS`) moves to the new default once, when that is free (`_move_old_defaults`). It is drawn, hit and listed in decorate **only while
  `things.money` is not null**: without money the piece takes no cell (`Layout.money_shown`, `show_money`; not solid, not
  walked around, free for another piece), and when money comes it stands on its cell or, taken meanwhile, the nearest one
  it may. Quiet most days; with a recurring charge due
  within `Money.SOON` (5) days an envelope leans against it (`Money.envelope`: "none", "due", and "short", amber, when
  `available` (else `balance`) is less than the sum of those charges). No number is ever drawn in the room. Hover says
  "the piggy bank" and outlines it in gold (`piggy` hit). `--demo` has money (`demo.json` `money`, `in_days` for dates)
  and its forecast (`money_forecast`, built by `Money.staged_forecast`); `--money quiet|short|none` stages the room's
  three states. A click opens the **Money view** (`money_view.gd`; `viewed` "money", `sb.open_money()`, the sidebar's
  `money_ui`): Now (`available`, else `balance`; savings beside it from the forecast's `other_available_cents` and
  `other_accounts`, named and never added in), Until the next deposit (`Money.lowest_line`, to the whole dollar, from `before_next_deposit`
  and `basis.next_deposit`, then a `DayStrip` of the days ahead with each of `events` on its date), Subscriptions
  (`subscriptions`: `amount_cents`, `rhythm`, `next`, a rise mark and "was $X" from `was_cents`), Noticed (the forecast's
  `notices` `[{key, kind, text, why}]`, absent from an older server: a row each under Now, the first three and "and N
  more", a quiet "seen" that clears the row at once and posts `{key}` to `POST /api/home/money/notices/seen`; a
  failed post brings it back with the next forecast; nothing drawn, no heading, when there are none), Worth a look (the
  proposals of `GET /api/home` with `source` "bank", add and no as on Home) and a line to ask: `POST
  /api/home/money/ask {text, thread?}` answers `{reply, figures, thread}`, the thread kept until the view is left, a
  `figures` that holds a forecast (or an afford answer's `with`) drawn as the same strip. The forecast is
  `GET /api/home/money/forecast` (`main.gd` `_fetch_forecast`; null body: "No forecast yet."). Home's Today has one
  row when a charge is due within `Money.SOON` days (`Money.today_row` "Rent $1,200 due Fri", the others counted under it by `Money.today_more`, "and 1 more"). Money is formatted only by `Money.fmt` (`fmt_whole` for an estimate);
  there are no budgets, category charts, totals or scores. `soak_money.gd` (section `money`) is its stub server, the
  states, the view, the ask and the room without money.
- **The room** is 11x11 cells (`Pets.COLS`/`ROWS`, which the home, the room and the walkers all follow; the back walls are column 0 and row 0, so a bigger room grows toward the front and a saved layout loads unchanged) and, in the 1100x700 window beside the sidebar, drawn with the 2x art (`fit_scale`; the 3x art needs a 1072 px area, which a 1450x980 window has). `layout.gd` holds what stands in it: the fixed pieces the behaviour is tied to
  (desk, office chair, TV stand, sofa, wardrobe, bin, large plant, floor lamp; also the door, window,
  board, calendar, jar, none of them movable) and the plain ones (the rest of
  the default room: armchair, plants, paintings, clock, rugs, fireplace with its fire, bookshelf,
  piano, dining set, mirror...), plus the wall and floor style. `room.gd` draws what it hands over.
- **Surprises** (`eggs.gd` the director and the pets' scenes, `hearth.gd`, `sound.gd`; more files below as
  they land). One big thing at a time, minutes apart (7-20 min, seeded), never while a view, the notepad,
  the closet, decorate mode or the phone's ring is up; `--egg a,b` forces them for a picture (`push bring zoomies
  flop sulk box piano fire`). Nina pushes the pen or mug off the desk (or walks the piano keys) and looks at you (it returns after a
  minute or on a click); Argos brings the yarn, a slipper or a crumple from the bin and sits proud; one of
  them tears a lap (`zoomies`) while the other watches; with a crate or barrel in the room Nina ends up on it
  within a minute; 20 pats in a row flop Argos belly up, 14 on Nina and she sulks in the corner for a minute.
  `P` held is a laser dot at the pointer (`--laser X,Y`): Nina chases it, Argos chases Nina, never onto a
  blocked cell. A lit fireplace (snow, under 8 C, or a Nov-Feb evening; a click toggles it) draws them in
  front of it now and then, and the item view offers "Into the fire". A bed draws a nap; a click on the piano
  has the person play a few bars (a hero stands and plays badly); the soak pins both.
- **Outside** (`outside.gd`, drawn in the window's glass and on its sill): a bird on the sill and a
  balloon by day, a plane by day, a cat on the fence at night that
  Nina goes to stare at from the sill, a shooting star at night that a click turns into a wish (a one-line
  reply and a chime), snow on the sill Dec-Feb, fireworks 31 Dec 23:00 to 1 Jan 01:00. Each comes minutes
  apart on the seeded dice, only in the weather and hour that suit it; `--egg bird|balloon|plane|nightcat|star|fireworks`
  (use `--at 23:00` for the night ones).
- **Finds** (`finds.gd`): a birthday (the settings' `birthday`, `"MM-DD"`, set in
  Settings; `--birthday` forces it) puts a cake on the table; a click on a title on the bookshelf's
  shelf view shows Nina's or Argos's remark (the `muse` lines, built-in fallback); a mouse leaves its hole on a quiet night
  (`--egg mouse`) and flees a pet or a click; the snow globe shakes on a click. The "found" card (`--egg found`,
  click the mouse hole) says only "N of M found"; `eggs.CATALOGUE` is the list, `user://house_found.json`
  `{"found":[ids]}` the state.
- **Secrets** (`secrets.gd`): the old code (arrows, `B`, `A`) is ten seconds of disco; typed words at home
  (not in the notepad): `borges` (shelf glows, a Babel line), `tlon` (colours drift), `uqbar` (a second
  moon), `argos` (he hops). `quirks.gd`: desk fidgets (`spin pencil stretch nod`, `--egg ...`), hero perks
  (staff: `cast` lights the fire; blade: salutes a visitor at the door; bow: an arrow stays in the wall), and a
  visitor, one at a time (never over a view, form or ringing reminder), `visitors_rate` apart (`rare` 40-90
  min, `sometimes` 15-35, `often` 7-15; default sometimes) and, by `Quirks.HOURS`, between 09:00 and 21:00 for the
  people and the farm, 07:00-23:00 for the wild: a hero (`--egg visitor`), a seeded pedestrian of the city-people
  pack (`--egg visitor_city[:punk]`), a farm animal that walks in at the door, looks around and leaves
  (`--egg visitor_farm[:cow_brown]`, its cry once), a wild animal that crosses the ground outside the window
  and stops to look (`--egg visitor_wild[:deer_stag]`, `outside.gd`; deer by day, wolves and bears at night), and
  a friendly monster of the monsters pack on 25-31 October by day (`--egg visitor_monster[:ghost]`) or, about once a
  week of running time (`Quirks._night_t`), at night on any date. The setting `visitors`: `all`, `calm` (no monster)
  or `none` (nobody, a forced visit refused too). The cat-species pet goes to the sill to watch, the dog-species
  pet barks once and hops (the sound only if not muted); a monster also draws a line from each pet. Each kind met
  is one "found" entry; a missing pack removes its kind. `Quirks.allowed` is the date/hour rule,
  `Quirks.PEDESTRIANS`/`MONSTERS`/`FARM`/`WILD` the casts. `delights.gd`: a moth at the lamp at night, an umbrella by the door in
  rain, Nina at the sill in rain, Argos hiding in a storm, TV remarks, a greeting for a new look, sparks when
  the jar fills; a snowman on the sill in snow and a lit pumpkin after dark (`outside.gd`, `home.gd`).
- **Sound** (`sound.gd`): a cue plays a file of the Gridwright UI and Retro packs found under the art dir
  (`TLON_ART_DIR`; loaded at runtime with `AudioStreamOggVorbis.load_from_file`, never imported, never in the
  repo), and falls back per cue to a synth when the pack or file is missing. `CUES` is the one table (file
  list rotated on repeat, dB, pitch jitter, gap); `piano`, `bad_piano`, `purr`, `bark`, `meow`, `squeak`,
  `rustle` and the `crackle`/`rain` loops stay synthesized (no pack fit). It starts muted; `M` toggles,
  `-`/`=` change the master volume by 0.1 (not while typing), kept with the mute in `user://house_sound.json`
  (`{"muted", "volume"}`, default 0.6); the speaker mark shows the level. At most `MAX_VOICES` sound at once
  (the oldest is cut) and a cue's `gap` drops a burst of itself. Cues come from `sound.request(name)` (kept
  in `requested`, which the soak reads; a name with no cue is ignored), from `sound.process(dt, home)`
  watching the view, note, closet, decorate, door and timer open and close, and from `eggs.find(id)` as
  `egg_<id>`. `--sounds` prints every cue with the file it resolved to (or `synth`/`none`) and quits.
- **Looks** (`looks.gd` the four switches and the one loader of their textures, from the art dir, cached;
  `glow.gd`, `weather.gd`, `spells.gd`, `fonts.gd`): what the light-textures, weather-effects, spell-vfx and
  pixel-fonts-2 packs add on top of the code-drawn room, each falling back to the code-drawn look, silently,
  when its pack or file is missing. Each has a switch under "looks" in the settings screen, applied at once
  (`glow`, `weather_art`, `spells`, `font`; on by default but `weather_art`, which in the pictures was no
  better than the code-drawn weather). `--plain` forces all four off and `--looks glow,font` exactly the named
  ones on, for pictures and comparing. Each module's `files()` names what it opens, which is the art pack's
  list (`art_pack.gd`); the soak holds that list to the files the looks really opened.
  *Glow*: after dark (the clock's `day` under 0.5; the lamp follows its own `lamp` value) a soft radial or
  pool texture is drawn at the lamp, a lit fire (flickering on a seeded table, stepped ten times a second), a
  TV that is on, the moon in the window, any candle piece and the pumpkin, in `Glow.SOURCES`, the one table
  (texture, colour, width, strength, lift). Each is cut to the room's outline (the moon to the glass) so none
  spills onto the desktop; with it on, the lamp's code-drawn halo gives way. By day nothing is drawn.
  *Weather* (when on): the window's rain, snow and fog loops, clipped to the glass quad and nowhere else,
  stepped at most ten times a second; a storm gets rain and every third flash a lightning bolt sprite inside
  the pane. They replace the code-drawn drops, flakes and the fog haze there; the sill, the snowman and the wet
  glass's drips stay. A loop tile is 128 px and the pane is smaller, so a few windows into the tile are stacked
  to make it dense.
  *Spells*: a ring of flame (`cast_fire`) at the hearth when a hero's staff spell lights the
  fire, and a starburst (`impact_holy`) at the window on a wish, each played once (about a second) and dropped;
  the Konami disco has none.
  *Font*: Gridwright Round, loaded from the TTF at its design size (16 px) or a
  whole multiple of it whatever size is asked (`fixed_size`), unsmoothed, for headings only: the sidebar's
  titles, view titles, the settings' and the chat's; body text keeps the default font, as the pack's
  text fonts were thin or wide at 14-17 px. Labels take it through the `Heading` theme variation
  (`Fonts.HEADING`, `Paper.heading`), so the switch applies at once; the default font is its fallback for
  what Round lacks (a thing's text in another script, an emoji).
- **Decorate** (`D`, or `--decorate`; the home only, not the widget): its view in the sidebar is the
  catalogue (`decorate.gd`): wall and floor styles, `reset`, and every placeable piece of the pack's
  index grouped and scrolled, a piece's four sides (or a rug's two, a wall piece's two) one entry. Click a piece, a ghost follows the pointer
  snapped to the cell (red where it cannot go), click places it and keeps it chosen, `R` turns it
  (right click with nothing under the pointer lets go). Click a placed piece to pick it up and
  click to put it down; `X`, Delete or right click on a placed piece removes it; `Esc` or `D`
  leaves. A fixed piece says "that one stays". Furniture on the floor blocks its cells for Nina,
  Argos and the person (`pets.blocked_cells`, from `layout.blocked`; they route around it, rugs
  and wall pieces block nothing); a placement is refused on a cell someone stands on, on any pet or
  person spot, on a fixed piece, and when it would cut a spot (or someone) off from the door
  (flood fill). A fireplace and wall pieces go on the wall their side names (ne: top row, nw: left
  column), not on the segments the board, window, calendar, jar and door use.
  The layout is saved on every change to `user://house_layout.json`
  (`{"v": 2, "wall": "brick", "floor": "oak", "pieces": [{"p": "bookshelf", "f": "se", "c": 9, "r": 0}]}`:
  `p` the catalogue name, `f` the side or `""`, `c`/`r` the back cell; the fixed pieces are not
  saved; the pets' things are saved too, as `pet.<key>` with `"own": true` for one he put out for animals not here, and the file's `pets_seen`) and read at start; a missing or unparsable file, an unknown name or side, or a piece that can no longer
  stand is skipped and the rest kept. `--demo` and `--shot` neither read nor write it unless
  `--layout PATH` names a file (read and written). With no art there is no decorating (one line
  says so) and the default room is boxes.
  **Packs** (`packs.gd`): the catalogue draws from the interiors plus the castle, haunted-mansion and
  farm packs when they are under the art dir (a missing one adds nothing, silently): `Packs.PACKS` lists
  the curated pieces, walls and floors of each, merged into `room._index` as `<pack>.<name>` ids
  (`castle.throne`, wall style `castle.ashlar`); an id without a dot is the interiors', so old layout
  files load as they were. Its view has tabs home / castle / mansion / garden (the farm pack) / pets (the pets' things, below); `--pick`
  switches to the piece's tab. A saved piece of a pack that is missing is not placed but is kept in the
  file when saving (until `reset`). All packs share the interiors' grid, anchors and footprints. Add a
  piece: a row in `Packs.PACKS` (options `faces`, `still`, `as`).
  `guests.gd` lends what is not the layout: at breakfast 07-09, lunch 12-13 and dinner 18-20 by the house
  clock a dish and a drink from `food-icons` sit on a dining, round or tavern table (stable for the
  meal, none with a cake or without the pack); on 25-31 October the mansion's cobwebs and candles stand
  in free cells as `layout.guests` (fixed, blocking like furniture, never saved, chosen again when the
  layout changes, `--date 10-28`).
- **The closet** (wardrobe, or `C`) picks who the person is. With the character-creator pack it
  composes `Layers/<build>/<group>/…png` from `layers.json`'s layer order in GDScript (alpha-stacked,
  scaled nearest) and offers build, skin, hair and colour, beard, top and colour, trousers and
  colour, shoes and colour, hat, eyewear, scarf, backpack and apron (worn together, each with none), the 20 ready-made recipes and a random button; an arrow pair on each row;
  Random and Keep; the person in the room wears the choice as it is made, and the back chevron or Esc leaves with the old look back. Without the pack: skin, shirt, hat, glasses, scarf drawn
  in code. The choice is saved to `user://house_person.json` (an old `extra` loads into its slot).
  With the hero-creator pack there is a second tab, "hero" (a click switches; absent without the
  pack): its ready-mades, build, skin and every group of `layers.json` (cape, chest, gloves, beard, hair,
  helmet, legs, shoes, shoulders, weapon) as a style row and a colour row (the colours are the ones that
  style comes in; "none" where a piece is optional), and random. Keep wears the tab it was kept on: the
  file holds the everyday look at the top level, `"wear": "everyday"|"hero"` and `"hero": {...}` (a hero
  look with the pack gone falls back to the everyday one). Animations, columns, fps and layer order are
  read from the pack's `layers.json`. A hero has no sit, type, eat, wave, cheer, pickup or talk: he
  stands on the floor cell he would walk to (no seat offset) and the action maps to `HERO_ACT` in
  `look.gd` (desk typing: `ready`; sofa, TV, coffee, sleep, talk: `idle`; wave: `block`; cheer: `cast`;
  pickup: `thrust`; walk: `walk`). Changing between the two re-places the person.
- **Settings** (`settings.gd` the store, `settings_view.gd` the settings view): the cog in the sidebar header
  or `,` opens it in the pane, replacing any view; the back chevron or Esc closes. A banner never closes it.
  Five groups, chips across the top ("You", "Pets", "Look", "Sound", "Connections"), one open at a time: You (name,
  birthday, temperature), Pets (each pet's name, animal and personality, talk, antics, the pets' things, visitors),
  Look (the four looks, the widget, the room's reset, the finds, the art), Sound, Connections (where the list lives,
  weather, calendar, Telegram, Claude, the phone's chat). Captions are sentence case. The birthday is one field that reads "8 June",
  "June 8" or "06-08" (`parse_birthday`), says what it kept ("Kept as 8 June.", "No birthday set.") or that it is
  not a day, and "none" or empty clears it.
  One flat object in `user://house_settings.json`, written on a change only, other keys kept as found, never in a
  scripted or staged run: `name` (used in the birthday line and a server line's `{name}`; a line with `{name}` and
  no name is skipped), `birthday` (`"MM-DD"`, `""`), `cat` and `dog` (default Nina and Rocky: shown everywhere the
  house prints them, the server's pet lines too, by `Settings.pets`; the server and `voices.gd` still key on the roles
  Nina and Argos, and `Settings.pets` turns the word Argos into the dog's name, Rocky unless he chose one), `pet1` and `pet2` (the animal of the first, aloof pet and the second, eager one: a key of `Pets.KINDS`
  or `"none"`; absent is `cat_black` and `dog_golden`; applies at once; a pet that is `none` is not in the room and
  every scene, line, sound and card that needs it is skipped; `--pets cat=KIND,dog=KIND` stages them),
  `pet1_personality`/`pet2_personality` (`sassy`, `sweet`, `lazy`, `mischievous`, `shy`, `bold`; absent is sassy for
  the first, sweet for the second; applies at once. `Pets.TRAITS` holds what each moves: the wait between remarks,
  the weight of sleeping and of the yarn, the walk, the chance of a run, a shy pet's pause before a pat; `voices.gd`
  `PERSONA` its offline lines; `quirks.gd` `_react` how it takes a visitor; `eggs.gd` `pace` how soon the big things
  come. Lines the server writes are not changed by it), `pet_chatter` (`quiet`, `normal`, `chatty`: stretches the
  waits between remarks), `visitors` and `visitors_rate`, `litter_box`, `bowls`, `pet_things` (the switches),
  `weather` (on) and `weather_town` (`""`: the wttr.in weather of the local house, below), `degrees` (`"f"` or `"c"`; absent follows the system locale, `f` for a US one, else `c`: the server sends Celsius,
  `Settings.temp` words it everywhere a temperature is shown),
  `widget` (start as the small widget), `on_top` (the widget stays on top), `background` (off; above, "Background"), `url` (empty: `TLON_URL`, else
  `http://127.0.0.1:4040`), `where` (`"server"`, or `"local"`: the house's own list; no key means the server), and over the
  house's own list only `telegram` (off), `telegram_morning_at` (`"08:30"`), `telegram_list_at` (`"17:30"`), `claude` (off) and `claude_command`
  (`"claude"`): the two helpers below (the bot's token is not here but in its own file); and the four
  looks, `glow`, `weather_art`, `spells`, `font` (above, "Looks").
  **Precedence: a command-line arg beats the settings file beats the default** (`--widget`
  is the arg of `widget`; `Settings.forced`). The screen also shows sound (`sound.gd`'s own file keeps it), "N of M
  found" with "Forget them all", "Reset the room to how it came" (`layout.reset`) and "Clear" for the chat, each
  asking for a second click (`sure.gd`), "where the list lives" (`where`: "a tlon server" with its address and a
  "check" (`GET /api/home`), or "this computer" with one quiet line of where the file is kept), the art folder, and the morning message time, the daily list time and weekly review day only
  when `GET /api/settings` already returned them (`home_morning_at`, `home_list_at`, `home_review_on`). Quiet hours are the server's and
  no existing route returns them, so they are not shown. `--settings "name=Sam;cat=Mimi;scroll;armed=reset"` stages it (`scroll=PIXELS` too); it also takes `weather=on|off`, `weather_town=TOWN`, `degrees=f|c`, `telegram=on`, `claude=on`, `claude_command=PATH` and `phone=pairing|paired` (a made-up bot state, no request).
- **Chat** (`chat.gd` the history, `chat_view.gd` the dock at the bottom of the sidebar): the desk phone, clicked while it is not ringing, or
  `K`, brings it up from its input line: his lines on the right, the home's on the left, newest at the bottom, the wheel and
  PageUp/PageDown scroll, Enter sends (`POST /api/home`, the notepad's request: both go through `main.gd` `_tell`),
  Up recalls his last line, the "-" and "+" chips collapse it to the line or open it to the whole sidebar. A failure says "couldn't reach tlon - not sent" and puts the text back. It
  holds his lines and the replies (the notepad's too), each reminder the house is told of (the ring's moment) with
  Done / In an hour / Tomorrow / Delete (the item view's routes through `_act`; a repeating one asks twice) that
  become a quiet line once used, the day's banners, and now and then a pet's bubble (not twice in ten minutes), marked
  with the pet's name. A message that arrives while it is closed puts a small dot on the phone until it opens. The
  last 300 are kept in `user://house_chat.json` (`{"messages": [{t, who: me|home|cat|dog, text, done?, via?}]}`, `via` "phone" on a line from Telegram and its reply, a
  reminder also `id` and `told_at`), never in a scripted or staged run. A question the server holds for him is not
  shown: the house has no route that lists them. `--chat "talk,reminder,acted,pet,phone,reading,fail|empty"` and `--unread` stage it.
- **One place for the list's calls**: `main.gd` `_post`, `_write`, `_act`, `_tell` and `_refresh` carry every
  write and the notepad/chat line; the polls (`_poll`, `_slow_poll`, `_pets_ask`, `_watch_weather`, `_ask_now`) are plain
  GETs there too. All of them are `Backend.fetch(route, cb, timeout)` and `Backend.send(route, body, cb, timeout)`,
  which answer `cb(reached, code, parsed)` on a later frame, never inside the call; `Backend.check(url, cb)` is the
  address check. `main.gd` `_make_backend` picks the server's (`backend_http.gd`, at `base`) or the house's own
  (`backend_local.gd`) from the `where` setting and swaps it at once when that changes.
- **The project name is the data folder.** `config/name` ("Asterion") names Godot's `user://` folder; `adopt.gd` copies the old `the house` folder into it once at start (`main.gd` `_ready`). Renaming the project again needs the same step first, or every list and Telegram pairing is left behind.
- **The house's own list** (`where`: `"server"` by default, `"local"` for "this computer"; the cog's screen chooses,
  `--local FILE|starters` stages it, nothing saved; `--tell "line;line"` sends loose lines and opens the chat). The same room runs on `backend_local.gd`: every route of the
  server's list answered on the next frame by `local_list.gd`, a Dictionary kept in `user://house_list.json`
  `{"v": 1, "next_id": N, "things": [...], "agendas": [...]}` (an agenda may carry `kind` "person" with a `birthday`, or "door"; one without is an agenda; a thing: `id kind text state since due_at every every_day told_at nudges
  project_id who plan done_at hidden_until`; unknown keys, top level or on a thing, are kept; `due_at` is UTC `Z` as
  the server's rows). Saved after every change, written to a temp file and renamed over the old one, which stays as
  `house_list.bak.json`; a file that cannot be read is moved aside as `house_list.broken-N.json` and the house starts
  empty, saying so once. The clock is injected (`clock` is the house's `_now_local`), so the soak moves time.
  Done history is the last 200 (`done_at`); `done_week` is the last seven days. Errors are the server's lines:
  `text is required`, `kind is todo, reminder, note, waiting or project`, `a reminder needs at`, `at is for a
  reminder`, the `at` format and `at is no more than a year back or 20 years ahead`, `every is for a reminder`, `every
  is day, week or month, or a number then one of them: 6 week`, `who is required for a waiting-on`, `steps is a list
  of texts, at least one`, `project is a project's id`, `project is for a to-do`, `kind is only todo or reminder`,
  `a to-do has no time: send kind reminder with at`, `a to-do has no time and no repeat`, `plan is a list of texts`;
  and `choice is required`, `choice is nottoday`, `skip is ids joined by commas, minutes a number`; 404 ({error: "no such
  route"}) for an id that is not live, for /done on anything but a to-do or reminder, for /later with no `until` or on
  anything else, and for the choices of a question (the local list holds none). What now is overdue reminders (most
  overdue first), the to-do that has sat longest, then a project's open step (`minutes` is validated, not weighed);
  "not today" hides a thing until 06:00 tomorrow. `GET /api/settings` answers the server's defaults of `home_morning_at`,
  `home_list_at` and `home_review_on`.
  **Reminders**: once a second the backend marks due reminders told (`told_at`, `nudges`), and the room rings from it
  as it does for the server's; a told one not acted on is told again after 30 min, 1 h, 2 h, then every 4 h, six times
  in all, never between 22:00 and 08:00 (it waits for 08:00); a repeating one missed for days stands at its newest time;
  one that came due while the house was closed is told at the next start. A re-ring changes `told_at`, and the room
  rings once per `(id, told_at)`: the phone, a new chat message, the sound.
  **The loose line** (the notepad, the chat) has no model: `reader_rules.gd` reads it, case-insensitively, and the
  reply says what it understood. A plain line is a to-do ("To do: buy milk."); with a time, a reminder ("Reminder set:
  call the plumber, tomorrow 09:00 (no hour given: 09:00)."): `remind me (to|about) X`, `at 3pm|15:00|3:30pm|at 9`,
  `tomorrow`, `tonight` (19:00), `today`, a weekday (`thursday`, `on thursday`, `next thursday`: the next such day,
  never today), `in N minutes|hours|days|weeks|in an hour`, `on 21 nov|nov 21|11/21`, combined; no hour is 09:00, a time
  already gone today is tomorrow's; `every day|week|month|N days|weeks|months|other week|monday` repeats ("then every
  week"); `note: X` ("Noted: X."), `waiting on WHO for X` or `WHO owes me X` ("Waiting on Dana for the lease. I'll ask
  in 3 days."), `done|did|finished X` and `delete|forget X` ("Done: buy milk.", "Deleted: ..."; the one whose words
  overlap most, a tie is listed and nothing changes, a repeating reminder or a project is left to its card),
  `what's left|list|today` (what is open and today's reminders). A line it cannot read a time from stays a to-do with
  the whole line as its text: nothing is dropped.
  **Seams** (what the two helpers below use): the reader is `read(text, context) -> reading` (`context`: `now`,
  `bias`, `status`; `reading`: `action` add|done|delete|say, `say`, and `body` or `id`), set as `backend_local.gd`
  `reader`; `backend_local.gd` `claude` is an asynchronous reader in front of it, asked first (`ask(text, context,
  cb(reading))`, `{}` meaning "read it with the rules"); and `Backend` announces `told(row)` (a reminder was just
  told), `replied(said, reply)` (a loose line and the answer; nothing listens) and `changed` (the list moved by itself).
  **Two helpers, over the house's own list only** (the server's house has neither, is offered neither, and runs
  exactly as before). Each is off until switched on in the settings screen (the keys below), is never started in a
  staged or scripted run (`main.gd` `talk_live`), and fails quietly: nothing nags.
  **Calendar** (`calendar_feed.gd`, a node `main.gd` holds; only over the local list): an optional feed. The
  settings' "Calendar" section takes the calendar's secret `.ics` link (`webcal://` is read as `https://`),
  fetches it once to see that it is a calendar, keeps it in `user://house_calendar.json` at mode 0600 and nowhere
  else (never in `house_settings.json`, never printed or shown: the section says "connected", or "connected;
  " and a fixed phrase when the last fetch failed), then fetches it every 15 minutes, a failure keeping the last
  good copy. `ics.gd` reads it as `Server.Calendar.Feed` does (RRULE, EXDATE, moved instances, all-day, busy and
  cancelled, `clean`); Godot has no zone database, so a TZID is read from a table of the common zones, else the
  feed's own VTIMEZONE, else the `(UTC±hh:mm)` prefix, else UTC. `calendar_feed.gd` answers `meetings` of
  `GET /api/home` and `GET /api/home/meetings?from=&to=` as `Server.Home.Day` does, and the route's date check
  is the server's (400, at most 62 days). The house only reads.
  **Telegram** (`telegram.gd`, a node `main.gd` holds): a bot of his own. The settings: "a Telegram bot in the
  house", three lines of setup (message @BotFather, `/newbot`, paste the token), the token field (masked, emptied once
  saved, then shown by its last four) and "connect" (`getMe`: the bot's @name or Telegram's own one-line reason),
  the pairing code (four digits, shown until a chat sends exactly it; five wrong messages change it), "last reached",
  the day's card times (`telegram_morning_at` and `telegram_list_at`, each `HH:MM` or `off`, default 08:30 and 17:30)
  and "disconnect" (second click; forgets token, chat, offset and card). The token, the paired chat id, the
  `getUpdates` offset, the day the evening card was last said and the day's card live in `user://house_telegram.json`
  `{"token", "chat", "offset", "listed", "card"}` and nowhere else (never in the settings
  file, and never in a line printed or shown: the URL carries it, so `_call` is the one place it is built). Methods
  called: `getMe`, `getUpdates` (long poll 25 s, `allowed_updates` message and callback_query, the offset kept before
  the batch is handled so nothing is filed twice; a backlog is read oldest first at start), `sendMessage`,
  `editMessageText`, `deleteMessage`, `answerCallbackQuery`. An edit never notifies the
  phone; a new message does, so what must be seen is sent again at the bottom and the old one deleted (Telegram lets a
  bot delete its own messages for 48 h). Only the paired private chat is ever heard or
  answered; every other message, before pairing or after, is ignored. A text goes through `main.gd` `_tell` (so the
  reader reads it, the chat keeps it marked `via: phone`, and the reply goes back); `/start` is greeted; a voice
  note, photo or sticker is answered "I can only read text here." and filed nowhere. A told reminder (`told(row)`)
  is "⏰ text" with Done / Later / Skip (`callback_data` `verb:id`: `done`, `hour`, and Skip is `tomorrow` for a
  one-off, `skip` for a repeating one, which goes through the list's done: that moves a repeating reminder to its next
  time and records nothing as done); a press goes through `_act` and edits the message to what was done; a re-ring
  deletes the old message and sends "⏰ text · still waiting since HH:MM" (the first tell's time); a thing done in the
  house (`_act`) or no longer ringing (`sync`, not within `grace`, 3 s, of the message) edits its message too, even one acted on before Telegram has answered the send (the message ids are kept in memory only, so a
  message from before a restart is followed only by its own buttons; an older message's Tomorrow, Delete and its
  "Delete for good?" still work). **The day's card** (`daily`, every 20 s; `card_text`, `card_keys` and `number` are
  static, checked in `logic_telegram.gd`): at `telegram_morning_at` by the house clock, or at the next start that day,
  one message, "Today · Wed 18 Nov", then "To do" numbered: the open things, then the reminders still to come today
  with their time, each keeping its number for the day (a new one takes the next; a ticked one stays, "2. ✓ …"; one
  put off or deleted loses its line). Under it one "✓ Tick…" button, which swaps the keyboard for the numbers still
  to tick (five a row) and "‹ Back"; a number ticks it. A reply that is only numbers ("2", "2 4 5", "2, 4") ticks
  those through `_act` and is answered "✓ text, …" (a number not to tick: "Nothing to tick at 9."); any other line is
  read as before. Every tick, and any change of the list (`sync`), edits the card in place, only when what it says
  changed. At `telegram_list_at` the evening's card, "This evening · …", what was done today and what is still to do
  under the same numbers, is sent at the bottom and the morning's deleted; on Saturday and Sunday only when the day
  moved (something done, ticked or added since the morning). Nothing to say, nothing sent; the day still counts. The
  card is kept in the bot's file, so a restart edits the same message; a press on another day's card ticks nothing.
  The local list has no sources yet, so the card has no notices or proposals. A network
  failure backs off 5 s doubling to 5 min and shows nothing in the room; a refused token stops it and says so in the
  settings. It works while this computer is on and the house is running (open, or in the background).
  **Background** (`background.gd`, the setting `background`, off; Connections): the house keeps running with its window
  shut. Turning it on writes the login entry, which starts the app with `-- --background` (hidden); turning it off removes it
  (`Background.entry` per OS: Linux `~/.config/autostart/asterion.desktop`, macOS a LaunchAgent plist with RunAtLoad,
  Windows the `HKCU\...\Run` value through `reg`; macOS and Windows are written but never run here, so unverified; an
  unexported run from the engine writes none). A close request then hides the window to a tray icon (`StatusIndicator`, menu Show /
  Quit, left click shows) where the system has one, else minimizes it; with the setting off a close quits. One house at a time:
  the running one beats into `user://house_running.json` every 2 s, and a second launch that sees a beat under 6 s old
  drops `user://house_show` and quits, which the running one answers by showing its window (`OS.is_process_running` only
  knows children, so a heartbeat is the liveness). The engine's own `--headless` (no display) runs the same loop with
  the room and sidebar hidden and stopped (`main.gd` `go_headless`): the list's tick, Telegram and the polls go on,
  and there is no window to show. A staged or scripted run does none of this. `soak_background.gd` (section
  `background`) tells a due reminder and answers a line against the Telegram stub with the room stopped;
  `logic_background.gd` holds the entries and the one-house rule.
  **Claude reading** (`reader_claude.gd`, `claude` and `claude_command` in the settings): "read my messages with
  Claude", the command (default `claude`, resolved on PATH, with the Windows extensions; the screen says whether it
  was found), a "test" button (one tiny reading: "works" or the reason), the last reading's outcome and "your messages
  are sent to your own Claude account". A loose line runs `<command> -p <prompt> --model haiku --output-format json`
  with stdin closed, in a thread (`/bin/sh -c 'exec "$0" "$@" </dev/null'` on Unix, the prompt still one argument
  of the array; on Windows the array goes straight to `execute_with_pipe`, and a `.cmd` gets a prompt stripped of what
  `cmd.exe` reads), killed at 45 s (`limit`). The prompt holds the local date-time and weekday, up to 40 open things
  as `id: text`, the line and the JSON shape asked for. The envelope's `result` (bare, fenced or after a line of
  talk) is checked strictly (`check`: known action and kind, a reminder and only a reminder has an `at` that
  `LocalList` accepts, a repeat `every_of` accepts, a project has 1-10 steps, `done`/`delete` an id that is live) and
  becomes the rules' reading shape (`list` and `answer` are `say`). Any failure (not found, exit, timeout,
  `is_error`, unreadable, invalid) answers `{}`: the rules read the line, once, and the settings say "last Claude
  reading: failed (reason), used the simple reader". The chat's "reading..." covers the wait.
  **Weather over the local list** (`wttr.gd`, a node `main.gd` holds): the one outward call of the local house, on by
  default. `GET https://wttr.in/<town>?format=j1` (no town: the service places the caller by internet address) at
  start, once the settings are read, and every 30 min, never oftener, 15 s timeout, only the URL (no name, no list
  text, the default user agent). `parse` reads it as the server's `weather.ex` does (`kind_of` the code table; a day's
  kind the most severe of the 09:00-18:00 entries, `wet` their highest chance; a day that does not read is left out)
  and feeds `home.set_weather` and `set_forecast`, so the window, the pets, the fire and the card act as with a server.
  A failure keeps the last report and waits for the next turn: no retry. Settings `weather` (`true`; `false` makes no
  request at all and clears what was held) and `weather_town` (letters, digits, spaces, `, . ' -`, up to 60; anything
  else is no town); a change takes effect after one debounced (2 s) fetch. The "weather" section shows the switch and
  the town only over the local list; `degrees` shows always. Never in a staged run (`live` is `not home.staged`: soak,
  `--demo`, `--shot`, `--local`), so a picture or the soak never reaches wttr.in; `--forecast` stages the days. The soak
  (`soak_weather.gd`) serves the stub of wttr.in from its own server (`base` is injectable); no check calls the real one.
  **First start**: no settings file, no `TLON_URL`, and nothing answering at the default address starts the house on
  its own list with a to-do "say hello to the cat", a weekly reminder "water the plant" and a note, once and only then.
  **Not shown over the local list**: the server's polls (`/api/office` for the weather, `/api/settings`: the daily list time stays
  17:30), the "couldn't reach tlon" states, and the address row of the settings. Choosing the other side applies at
  once and deletes neither side's data; the settings screen says where the file is kept.
- **Importing the server's home** (`mise run house:import`, `import_server.gd`, `import_list.gd`): a one-shot, read-only on the server (`GET /api/home/export`: every jot incl. done, dropped and someday, agendas, people, the door, the open proposals and the two Telegram times, in the list's own shape, with `counts` per kind). The dry run prints server, added, already and local counts per kind and writes nothing; `-- --write` (the house closed) writes the list and the times (`telegram_list_at`, `telegram_morning_at`) and stops red unless every kind's local count equals the server's. An empty, miscounted or dangling read stops before any write. Each imported row carries `origin` ("server:<id>"), so a second run adds nothing; ids are the list's own with a step's project and a note's agenda mapped; a hand-made person, agenda or door of the same name is joined, not doubled. A dropped row is kept as state `dropped` (inert: no view reads it); open proposals are counted and not carried (the list has no sources); the Telegram offset and the server's bot are not carried. Done history beyond 200 is trimmed by the list's next Done. `logic_import.gd` holds it.
- **Jotting** (the notepad on the desk, `N`, `/` or Enter): the add view's one paper line, focused,
  with one line of example under it; Enter sends the text to the server (a model reads it, so a pencil scribbles
  while it waits). The view then says what the house read it as ("Reminder · tomorrow 10:00 · every week" over the
  text) with a primary "OK" (back) and a secondary "Change", which opens that thing's edit form. The kept row is
  `row` of the answer, `{reply, row}` from the server and the local list alike (`main.gd` `_made`; a note's row has
  no kind, so it is made one; a null `row`, an ask or a correction, shows the reply with OK only). A server that does not
  answer says "couldn't reach tlon — not kept" and keeps the text in the field.
- **Acting on a thing**: click a sticky, a row of the Home view or a stack (which lists "On the desk") for its item
  view: Done (the crumple), Into the fire (while it burns), In an hour, Tomorrow (the paper flies to the wall calendar), Now, Edit, Delete (and Plan for a project).
  Each row's tick circle ticks. Delete asks nothing of a one-off; a repeating reminder or a
  project asks again on the same button ("Delete for good?", 4 s, `sure.gd`).
- **Forms** (`form.gd`, `things.gd`): `I`, `N` or the header's plus opens the add view, the jot line (`jot.gd`; same reader and route, Enter keeps it); its quiet link "Fill in the details instead" swaps to the typed form: kind chips "To-do" (selected first),
  "Reminder", "Note", "Waiting on someone" and "Project (several steps)", the field's placeholder following the kind; a reminder has a date (a month grid), a time (typed `HH:MM`, default
  09:00, chips morning/noon/evening) and a repeat (once, every day/week/month, or every N day/week/month).
  The calendar's day and its things, the clock's named timer, the board and its tabs open it too, and a
  thing is changed the same way (to-do or reminder, text, date, time, repeat; Done, Delete, "Stop
  repeating"). Enter saves (Ctrl+Enter in the project's steps), Esc cancels, Tab moves between fields.
  One at a time, in the pane (it replaces any other view; a banner never closes it); the room still
  takes clicks, which open their own views. A refused request (the server's 400 line, 404, no
  answer) is said on the form, which stays as typed; after any change the room is read again at once.
  Local times go to the server without a zone. `H` or the Home view's Now line asks `GET /api/home/now`
  and shows the pick on the Home view's Now line: Done, Something else (the skip list grows), Not today
  (`POST /api/home/:id/answer` `nottoday`), Delete. In `--demo` nothing is sent: adds and deletes only
  change what is on screen.
- **The phone** on the desk buzzes with a ring mark while an open reminder has `told_at` (the server
  has nudged it); the window asks for attention once per reminder; click it for that reminder's item view, or for the chat when it is quiet.
- **Now** pins one open thing: large above the monitor and as a pin under the Now line of the Home view, with a
  timer you start there (click the length for 10 / 25 / 45 min), a progress ring, no sound. Kept in
  `user://house_now.json`; cleared when the thing is done or leaves `open`.
- **Widget** (`--widget`, `W`, `mise run house:widget`): the room alone (no sidebar) in a borderless always-on-top
  window of 720x464, exactly the room at scale 2 so it stays crisp; drag the room to move it, the
  spot is kept in `user://house_widget.json`. Only bubbles and the hover name are drawn; a click on a thing leaves
  the widget for the full window with that thing's view open.
- The pets are roles, not animals: `nina` (naps on furniture, pushes things off the desk, walks the piano) and
  `argos` (brings gifts, flops), each any animal of `Pets.KINDS` (all 29 of the animals pack, horses and bears
  included: every sheet has all of `Pets.ANIMS`, so each animation plays under its own name) or `none`
  (`Critter.away`: not stepped, drawn, hit, heard or counted). Species keys the voice: `Pets.CRIES` (the
  sound a species makes, none for a rabbit, fox or deer; only a cat purrs, only a dog barks), `Voices.SPECIES`
  (house lines that suit one species) and `Voices.OWN` (what a species says offline).
  A new kind is a row in `KINDS`, and its sheets are in the art pack at once (`art_pack.gd`).
- **Antics** (`antics.gd`; the setting `pet_antics` `few|some|lots`, default `some`, with `pet_chatter`): short
  (2-12 s) rare behaviours by species and personality, one at a time and never over a view, form or ring;
  they read cells from `pets.spots` and need nothing of the art folder. The table is `ANTICS`: to add one, a row
  (`who` species weights, `need`, `go`/`pgo` spots, `dur`, `pers` weights; `pair`, `trig` for one only a hook
  starts), a branch of `_pose` that sets the critter's `dir`/`anim`/`lift`/`flip` from the clock, and its offline
  lines in `LINES` (dry; never about what is undone, late or counted). `_need` holds the conditions (hour,
  weather, tv, visitor). `--antic <name> [--antic-who nina|argos] [--antic-t <s>]` stages one for a picture.
  `soak_antics.gd` forces every row for every species it allows and checks the pet is released and normal.
- **The pets' things** (`petlife.gd` the logic, `pet_things.gd` the table and the code-drawn pictures; the settings `litter_box`,
  `bowls`, `pet_things`, all on, are master switches): each thing is a layout piece named `pet.<key>` (`THINGS`: who it is for,
  `flat` walked over, `walk` flat with walls a pet stands in, `solid` blocks and is used from beside it, height, the sides it turns
  to, whether it is put out by itself). Bowls, round bed, cushion bed (sized to its pet), litter box, scratching post, cat tower
  (pink, three platforms and a cube; both sides), cardboard box, fish toy, aquarium, bone, rope toy, tennis balls, chicken perch
  and nest box, bunny house, carrot, hay bale (the farm pack's sprite), trough, salt lick, kiddie pool, blanket, scratching log,
  honey pot, window perch (`raised`: a flat thing drawn with the furniture; a cushioned ledge bracketed to the back wall at sill height when its cell is against either back wall, `PetThings.perch_wall`, else a cushioned platform on a post; a cat uses both; while the ledge
  hangs on the north-west wall at the window (`Pets.WINDOW_ROWS`) the `sill` spot is the perch, else the window's own, so every antic that goes to the sill uses it, and a cat
  naps there by day), bird cage (for every animal, not put out by itself, only added from the pets tab: a bird hops between two
  perches and sings now and then or on a click, `cage` is its hit, and a cat now and then goes to watch it, the antic `cage_watch`).
  One signature thing for each species that shared the rest: dog house (it sleeps by it; the night home when it has no bed),
  howling rock (wider than its cell, so it shows around and below the wolf standing on top; the wolf howls once on arriving, `petlife` `_arrivals`), den (a fox curls up in it), apple bucket (horse eats), milk pail and bell post (cow stands
  by it), wool basket (sheep lies by it), mossy stump (deer stands by it). A pet arriving at its own thing (these and the window perch)
  now and then says one of its two lines (`THING_LINES`: short, lowercase, never about tasks; `thing_say` the chance, then 2 to 5 minutes
  of quiet for that pet).
  A thing is put out once, at a free cell (`_default`): never in front of a piece or at a spot (`layout.in_front`: the side each
  seat, the TV, the desk, the piano, the fireplace, the wardrobe and the rest face, the door's and the pets' spots; the window perch
  is on the wall and exempt), on no other thing, and as far from the others as the room allows (2 cells from any thing or furniture piece, 3 from the other things with
  height; the tallest are put first), the open floor along the two front edges first, from the corner out, then the cells
  against a wall. It is put out when an animal that uses it lives here and its `def` is set; `layout.pets_seen` (saved as `pets_seen`)
  remembers it, so one he took away is not put back. The file's `"v"` is `Layout.SAVED`; a file saved before `THINGS_SAVED` (`old_things`) has its
  things looked at once: one still at the cell the first rule would have chosen in the 10x10 room (`OLD_PLACES`, `_old_pick`; the
  layout does not record that a thing was moved, so a thing he moved onto exactly that cell is placed again too) is put again by the
  current rule, one anywhere else stays.
  Putting them out is computed in memory and never writes `user://`: the layout file is written only by a change in
  decorate mode (`place`/`remove`/`reset`), so an untouched house leaves none. Hidden (`hide`, not deleted, not blocking, not drawn) when no animal here uses it or its switch is off, and back in its place; one
  he put out for animals not here is `own` and stays. The pets tab of decorate lists what fits the animals here ("all animals"
  lists every one); a thing is placed once, a click on a placed one picks it up. Spots follow the piece (`_register`, on every
  layout change); a pet's use of a thing is its `_habits` row and the spot's `use` key. Nothing scores or nags; a bowl's level only shows.
  Add a thing: a row in `THINGS`, its `_name(s, ...)` drawer in `pet_things.gd` (a `Pen` draws in the cell's own 0..1 coordinates,
  `box`, `ell`, `diamond`, `line`; `part` "back" and "front" for a `walk` thing), a `_register_one` arm for its spot and a `_habits`
  row (or an entry in `_plain`); `soak_petthings.gd` covers every thing by itself.
- Nina is a black cat with a jewelled collar (smart, sassy, wins every argument), Rocky (the role Argos) a golden dog
  (sweet, not bright). A left click pets and selects it, opening its view (a right click does too), its view (`pet_view.gd`): the pet drawn large with its name and "kind · way", "right now" (one phrase from its state, `pet_now.gd`: mode, spot, running antic; never invented), buttons that each send it somewhere with the room's own behaviours (pat; call over to the person; treat at its bowl or food thing; play at its toy thing, or the yarn for a cat, dog, fox or wolf; off to bed at its night home; a button whose thing is not out or not reachable is not shown, and a scene of the room's that holds the pet leaves only pat), "Its things" (the pet things of its kind in the room, six and "N more...", a row sends it there), "Lately" (its last lines) and "change who this is": the animal as a grid of idling sprites and `none`, the name and the way, behind a "< back" (Esc goes back to the pet first, then home; it writes the same `pet1`/`pet2`, `cat`/`dog` the settings screen writes; antics wait while it is up, as for any form); nothing counts or nags; `--pet-card nina|argos` stages it. Their lines are `voices.gd`: `GET /api/home/pets` (with `nina_name`, `nina_species`, `nina_personality` and the same three for `argos`, URL-encoded: the first and second pet as set; a pet that is `none` sends none; an older server ignores them; any of the six changing asks once more), a batch a
  model wrote for the home as it is now, `{Nina: {occasion: [lines]}, Argos: {...}, duo: [[
  "Nina: ...", "Argos: ..."]]}` (`{}` until the first exists). Asked at start, every 20 s while empty
  (3 min, then every 5 min), else every 5 min, and once 60 s after the open list changes; a failure or
  `{}` keeps what is held. Occasions: `pet` (click), `wake` (clicked or woken), `muse` (unprompted),
  `done` (Argos names the thing; `all_done` for the last), `old` (Nina as she knocks), `jot` (note sent),
  `ring`, `home` (Argos at the door), `morning`, `tv`, `night`; the pet nearest and awake speaks, never
  two at once. `{thing}` is the thing's text, trimmed; a line with it and no thing is skipped. A line
  never repeats until the pet's others for that occasion have been used (reset on a new batch), nor
  twice in a row; a bubble wraps and stays 3.5-9 s by length. Now and then both awake and idle play a
  `duo`, alternating bubbles. Built-in lines (one or two) are only for a pet and occasion the server gave
  nothing for; none and no line means no bubble. `--demo` serves `pets` from `demo.json`.

## Law

- **The art is bought and never enters the repo, nor a public place.** `art.gd` is the one place that says where it is read from:
  `--art <folder|pack>`, else art already inside the program (`res://art` in its pck: every build), else
  `house-art.zip|pck` beside the executable, mounted at `res://art`, else `TLON_ART_DIR` (default `~/projects/thatch/packs/x`: the Gridwright packs). Every loader takes the one
  `art_dir` string and opens files under it with FileAccess/DirAccess/Image, which read the mounted pack like a folder: a
  new loader takes `art_dir` and never a path of its own. `mise run house:art-pack` packs only what the loaders can open
  (`art_pack.gd` reads the loaders' own tables and folders; a loader that opens a new kind of file adds it there), and
  `house:build` ships it inside the executable (`SHIPPING.md`). The licence allows shipping the art inside the finished app and
  forbids redistributing it as assets: the pack and the builds are written only outside any git work tree
  (`~/.cache/tlon/house-dist/`, refused otherwise), never committed, pushed or linked publicly. The window asks for the
  "Art by Gridwright" credit and shows it.
  With no art the room is drawn in flat shapes (the pets too) and says so. Whatever the packs lack
  is drawn in code; never add a bought image.
- **It talks to the server only over the operator API**, on `TLON_URL` (default
  `http://127.0.0.1:4040`): the home is polled every 5 s — `GET /api/home` (rows carry
  `since` and `told_at`; `done_week` fills the jar, an optional `done` list names what was done)
  (`GET /api/home` also carries `waiting`, `someday`, `projects` and `note_rows`) and posts
  `POST /api/home/:id/done`, `.../later` (`{"until": "hour"|"tomorrow"}`), `.../drop`, `.../revive`,
  `.../edit`, `.../plan`, `.../answer`, `POST /api/home/add`, asks `GET /api/home/now?skip=`, and
  `POST /api/home` (`{"text"}` → `{"reply"}`, slow: a model reads it). The home also asks
  `/api/settings` every 5 min and `/api/office` (its `weather` only; the route is the server's, the house reads nothing else from it) every 60 s and `/api/home/pets` on its own schedule (above). With `where` = `local` it talks to no server at all and keeps its own list (above), apart from one outward call, the weather from wttr.in (below), the calendar feed he pasted (when he has), and only when he has switched them on to Telegram (`api.telegram.org`) and to the `claude` program (his own account). A server that does not answer leaves the
  last data on screen and a quiet line saying so; a post that fails moves nothing.

- **Nothing nags.** No scores, streaks or warnings; the only settings are the ones on the cog's screen (sound starts muted and is his to turn on); the only timer is the one you
  start on the pinned now. A bubble fades by itself and stays inside the room.

## Dev loop

- `mise run house:run` — over the live server. `mise run house:demo` — on `demo.json` (the home at
  the top level, with `weather`), no server.
- `mise run house:widget` — over the live server as the small always-on-top widget.
- `mise run house:check` — every script, the soak's too, loads in headless Godot, then `logic.gd` runs:
  the checks that need no scene tree and no simulated room (the due-time rule `when.gd`, the reader and
  the list's rules `logic_local.gd`, the forecast, the j1 reader and the address `logic_weather.gd`, the chores' table, rhythm and states `logic_chores.gd`, the people's birthdays and the door's mark `logic_people.gd`,
  the money's envelope states, day strip, lowest-point sentence and wording `logic_money.gd`,
  voices, the jar, the knock and rhythm rules, the TV, `Card`'s dates, the pet settings). A few seconds:
  **iterate here.** Godot is the machine's own, so this is not part of `mise run check`. A check
  that needs neither the tree nor the clock goes in `logic.gd`, not in the soak; none runs in both.
- `mise run house:soak -- <section>...` runs only those sections, in the suite's order; `-- --list`
  prints the names (`home sim decorate packs looks hacks eggs guests petlife antics petthings cards
  routes forms sidebar chores people door money chat local talk telegram background weather drive packlooks art`); an unknown name prints
  them and fails. **Iterate on your own section by name** and run the whole soak once, alone, on the
  final tree. Each section stands alone: the runner (`soak.gd` `_sections`, `_reset`, `_leave`) reseeds
  with 7 and resets the stub server's state, its log and its flags before it, and fails the section
  that leaves a node under the root, a file in `user://` or the server listening. The sections that
  need the house over the stub (`routes forms sidebar chores people door money chat local talk telegram`) get a fresh `main`
  from `_on_main`; a section that needs more builds it itself and never reads what another left.
  A wait is on the condition the next check needs, with a bound (`_until(done, what)`: it fails the soak
  naming `what` when the bound passes); that nothing happens is a named window (`_quiet`, or `_quiet_frames`
  for what per-frame code decides): a quiet window proves nothing more happens, it never waits for
  something to happen. Never a bare `create_timer`. It prints each section's wall time as it
  ends and a table at the end.
- `mise run house:gate` — the whole verification, fast: `house:check`, then every soak section as its own
  headless Godot, `TLON_HOUSE_JOBS` at once (default half the cores), each with its own throwaway
  `XDG_DATA_HOME` (the stub server listens on port 0, so none collide). It prints a table of section times and
  every `FAIL` line under its section, and fails on a failed section, one with no `SOAK OK`, or one still running
  after 10 minutes (killed, reported as a timeout; no Godot of the gate outlives it). About two minutes, against
  the serial soak's seven. **This is what the repo's gate runs** (`check:house`, inside `mise run check`) whenever
  `house/` changed in the commits being gated, so a builder runs their own section and `house:check` while working
  and leaves the full run to the gate; run `house:gate` by hand only to see it before submitting. A section must
  pass alone and beside the others: no shared file, port or `user://` state. No `godot` on PATH is a named skip
  unless `TLON_HOUSE_GATE=required` (the home machine sets it), which makes it red.
- `mise run house:soak` (about 7 minutes quiet, up to twice that loaded; its own deadline is 15 minutes and the task wraps it in `timeout 1000`, so a caller's wrapper needs at least that) — ten simulated hours of the person and the pets on the grid with random
  state changes (nobody on a blocked cell, nobody walking in place, the person always settles), the
  closet's composition over every ready-made recipe, decorating (placement rules, reachability from the door, random layouts walked on, saving and loading, the pointer work), the cards (each opens from its hit area, one at a time, none over a menu), the hero look, every layer file reachable from the closet, the knock and the day's rhythm in the room, the TV hacks drawn, the POST and GET routes against a local stub, and the forms (each request body, local times across midnight and month ends, the server's refusals, delete's second click, plan order, what now, the calendar's repeats), the settings (file, precedence, names, the second clicks, the address check) and the chat (history, told reminders and their buttons, unread, blockers), the calendar feed (`soak_calendar.gd`: the address kept at 0600, a fetch from a stub feed host, a failure keeping the last copy, the local routes over it; `logic_calendar.gd` holds the server's feed, Outlook, `clean` and `Day` tests as cases of `ics.gd`), and the two helpers (`soak_talk.gd`: Claude reading against a fake `claude` script in a temp dir; `soak_telegram.gd`: the bot against a stub of Telegram's API on the same local server; neither real service is ever reached), the contract (`soak_contract.gd`, section `contract`: every case of `home_contract.json`, the server's `/api/home/*` and `GET /api/settings` as it answers them, run against the local backend; a case marked with a `gap` must still differ, so closing a gap fails the soak until its mark is deleted; the gap list is the contract's `gaps`), the weather (`soak_weather.gd`: degrees, the card's days, the j1 reader, the address, the pace and the switch, against a stub of wttr.in), and the four looks (`soak_looks.gd`: tables that resolve and load, no art falls back, the settings and `--plain`, no glow by day, weather inside the glass, a cast played once, the font's coverage, the pack list, and the frame cost of plain against all four on, printed). Stdout ends `SOAK OK`; the task fails when an `ERROR` or `SCRIPT ERROR` line comes before it (the engine's own `ERROR` leak lines at exit, printed after it, are not counted).
- `mise run house:art-pack` / `mise run house:build -- windows|mac|linux|all` — the art the house can open, packed to
  `~/.cache/tlon/house-dist/house-art.zip` (`-- --list` prints the files only), and a build of the house per platform
  with it inside (Windows and Linux: one file; the Mac app ad-hoc signed by the export, nothing added to it after; the art raw in the pck), zipped as
  `asterion-<platform>.zip` there. Templates are Godot's own 4.7.2 export
  templates; presets in `export_presets.cfg`; what to hand over and the first run on each OS: `SHIPPING.md`. The soak's
  art section (`soak_art.gd`) holds the order the art is looked up in over packs generated from 1x1 PNGs.

## Verify

Headless Godot draws nothing. A picture of the real window, with none opened on the desktop:
`gamescope --backend headless -W 1100 -H 700 -- godot --display-driver x11 --path house -- --demo --shot /tmp/house.png`
(`--shot PATH` saves the viewport after 1.5 s and quits). Look at the
picture.

### Driving it

`mise run house:drive:start [-- house args]` starts the real house LIVE (pets moving, real time) under
headless gamescope on a throwaway `XDG_DATA_HOME`, over the starter list (`-- --demo` for the demo
one), no server and no network (`-- --server`: over the tlon server at `TLON_URL`, else the settings' default URL, instead of the starter list; **a click in that drive acts on the real list**), and prints its port; `mise run house:drive -- '<json>' ...` sends
each command and prints one reply line each; `house:drive:errors` prints the Godot `ERROR` lines since
the last call; `house:drive:stop` quits it and removes the data folder. One house at a time. Save,
load and the settings file work, inside that folder. `drive.gd` (`--drive [PORT]`) takes one JSON object
per line on 127.0.0.1, input as real events through `Input.parse_input_event` (window pixels):

```
{"do":"move","x":N,"y":N}  {"do":"click","x":N,"y":N,"button":"left|right|middle","double":false}
{"do":"down|up","x":N,"y":N,"button":"left"}  {"do":"drag","from":[x,y],"to":[x,y],"seconds":0.4}
{"do":"wheel","x":N,"y":N,"dy":-1}  {"do":"key","key":"I|Escape|Enter|Tab|Backspace|F2|...","shift":false,"ctrl":false}
{"do":"type","text":"buy milk"}  {"do":"wait","seconds":1.5}  {"do":"frames","n":3}
{"do":"shot","path":"a.png"}  (relative: under the run's folder; the reply holds the absolute path)
{"do":"at","x":N,"y":N}  topmost key, the Control there, a decorate hit
{"do":"things"}  registered keys with centres, the sidebar (view, selected key, banner, chat mode, every control with text and centre), decorate hits, mode, window
{"do":"state"}  items, pets, person, tv, fire, weather, clock, settings, layout, said, mode
{"do":"set","what":"time|date|weather|pet|setting","value":"23:00|10-31|snow|cat=bear_brown|degrees=f"}
{"do":"resize","w":N,"h":N}  {"do":"quit"}
```

Every reply has `ok`, and `error` when it is false; a bad command never stops the house. `things` is how
to find what to click: do not guess pixels. Gotchas: decorate is click-to-pick then click-to-place, a
drag's release drops nothing; the window size comes from `HOUSE_DRIVE_W` and `HOUSE_DRIVE_H` (default 1100x700); the
`shot` verb needs a window (headless answers an error; `soak_drive.gd` holds the verbs over a real TCP client).
**A change that touches clicks, keys, views, forms or decorate is verified in drive mode before it
lands; photos alone are not enough.** Not reachable by it: the OS's own window drag and
always-on-top, hover tooltips' delay, anything the compositor decides.

User args (after `--`) that fix a state for a picture; `--shot` also freezes the pets' own choices
and seeds their dice (`--seed N` to pick another):

- `--at HH:MM` pretend local time; `--weather clear|partly|cloudy|fog|rain|storm|snow`;
  `--forecast none|JSON` the window view's days (rows as the server's, `in_days` for `date`: 0 is today; `demo.json` has three).
- `--tick-demo` ticks thing 1 off at 0.75 s (a picture at 1.5 s catches the paper in the air);
  `--tick-all` ticks 1, 2, 3 for the confetti; `--bat` makes the paper miss so Nina chases it;
  `--empty` is the demo with nothing open, no notes, nothing coming.
- `--say Nina|Argos` a bubble at 0.3 s (`--occasion NAME` for its line; `--duo` plays an exchange; `--no-voices` drops the demo batch to show the built-ins); `--nina SPOT[:sleep|sit|walk|run]`, `--argos SPOT[:...]` start a pet
  at a spot (`pets.gd` `SPOTS`: `sofa`, `desk`, `rug`, `bed`, ...); `--wait SECONDS` when to shoot.
- `--hover X,Y` and `--click X,Y` run the room's own hover and click at a window pixel, so a view, a
  name tag or a pat can be photographed without a pointer.
- `--tv on|off`, `--hack NAME` a TV state and screen hack (`spectrum stars plasma logo rain life pipes moire scope sunset fireworks toasters note`); `--jar N` the jar's marbles, `--jar-drop` one more at 0.7 s; `--knocked ID` that sticky on the floor with Nina; `--homecoming` / `--morning` the day beats; `--date MM-DD` the season; `--plain` / `--looks glow,weather_art,spells,font` the looks all off / only the named on; `--person
  desk|sofa|tv|coffee|sleep|board` the person's activity; `--closet` opens the closet (`--tab hero` on its hero tab); `--look k=v,...` sets look keys for the picture (not kept; `wear=hero,recipe=mage` then group keys such as `weapon=staff,weapon_c=royal` for a hero); `--card calendar|jar|weather|clock|board|plant` opens that view at 0.45 s (`calendar:DAY[:MONTHS_AHEAD]`, `board:projects|waiting|someday[:PROJECT_ID]`); `--form "KIND;key=value;..."` opens the form view at 0.4 s (`todo reminder note waiting project`, or `edit:ID`; keys `kinds text who steps date time every error`, `date` as `MM-DD` or `YYYY-MM-DD`, `steps` lines split by `\n`); `--what-now` asks for the Now line; `--then ACT` switches `--person` to ACT at 0.3 s so he is caught walking; `--typing
  "text"` opens the add view with the jot field filled (`--sending` shows the scribble); `--reply "text"` the reply banner;
  `--menu ID` the item view of thing ID; `--ring ID` rings the phone for thing ID; `--now
  ID[:MINUTES[:DONE_FRACTION]]` pins thing ID with a running timer (nothing saved); `--widget`;
  `--layout PATH` a layout file; `--decorate` opens decorate mode, `--pick NAME[:SIDE]` chooses a piece
  and `--cell COL,ROW` puts the ghost there.
  For `--widget` give gamescope `-W 720 -H 464`. `TLON_ART_DIR=/none` for no art.
- Not covered by any picture or script: a real pointer (drag, hover feel), the compositor's
  always-on-top and attention request, the real hour of the beats.
