# To-Do you can check off

## Problem
Pinning a note puts it on the To-Do list at the top of All Notes, but nothing on that list can be *done*. The only exit is unpinning, which drops the note back into the grid with no checkmark, no strike-through and no feeling of finishing anything. The list behaves like a shelf of bookmarks, not a list to work through.

## Who it's for, and how we know
Remora users who pin notes as tasks tied to a place: a PR page, a Figma file, a Slack thread, a project folder. The signal is the product owner's own use and the 2.0.0 direction (Pinned was renamed To-Do). It hasn't been checked against other users' feedback yet.

## What we decided, and why
- **Simple over complete.** To-Do is strictly "what's left". The product owner chose this over keeping a record of finished items.
- **A to-do is a whole note, not lines inside it.** Each pinned note already maps to "a thing to do in this context". Checklists inside notes are a different feature.
- **A to-do is a flag on a note, not a location.** A note on To-Do also stays in the grid below, with the to-do icon on its tile. The note never leaves the grid. (Agreed with the grid rework conversation.)
- **Replace the pin icon with one that reads as "to-do".** A pin suggests "keep forever", which is the opposite of the intent. The exact symbol is chosen in the spec.
- **Each To-Do row gets an open circle. Ticking it clears the flag:** the row leaves To-Do, the tile in the grid loses its to-do icon, and the note stays where it always was as a plain note. Ticking and "remove from To-Do" are now the same action, so there's no separate remove path.
- **A short "Completed · Undo" covers mis-ticks.** After it's gone, the fix is adding the note back to To-Do from its tile or the editor.
- **The circle is also in the editor footer**, so a to-do can be ticked from the note itself, in the context where the work happens.
- **Search covers the grid only, never the To-Do list.** To-dos are in the grid, so they're still found. (Agreed with the grid rework conversation.)
- **To-Do and Archive.** The grid gets Archive and auto-archive (see `notes-grid-archive.md`). A note is always in exactly one state: on To-Do (and shown in the grid), in the grid, or archived. So:
  - **To-dos are never archived**, manually or automatically.
  - **Adding a note to To-Do unarchives it.** "Add to To-Do" can be used on an archived note (in the Archived view or a search result), and it unarchives the note as well as setting the flag.
  - **Ticking a to-do resets the note's auto-archive clock**, as opening the editor does. Otherwise a note that sat on To-Do for months would be archived the moment it's ticked, so finishing a task would make the note vanish from the grid too.
  - **Undo after a tick puts the flag back.** It doesn't need to restore the clock.

## Smallest version
1. The pin icon becomes a to-do icon that adds a note to To-Do, on grid tiles and in the editor footer. Tiles of notes on To-Do show the icon.
2. Open circle on To-Do rows and in the editor footer for notes on To-Do. Ticking it clears the flag.
3. A short "Completed · Undo" after a tick.
4. Adding to To-Do unarchives the note; ticking resets its auto-archive clock (once Archive exists).

## Not doing
- The word "bookmark" anywhere in the app. The grid stays "Notes".
- A Completed group, a "Completed <date>" record, or unticking. (Considered and dropped for simplicity.)
- Multi-select actions on To-Do (Move to Notes / Delete). The note never leaves the grid, so there's nothing to move.
- Checklist items inside a note's body.
- Due dates, reminders, notifications, priorities.
- The grid rework itself (its own decision doc).

## Parked decisions (and what would unpark them)
- **A record of finished to-dos.** It unparks if users ask "what did I finish?" or miss checked items. The flag model can add a *completed* state later without moving notes.
- **Kill / rework condition:** if the grid rework settles on a model where a note can't be both in the grid and a to-do, revisit this before building. Checked against `notes-grid-archive.md`: it doesn't, so the condition isn't triggered.
- **Is pin used today as a permanent "keep at top" shelf?** Not tested. If users push back on ticking being the only way off the list, reconsider.

## Open questions for the spec
- The exact to-do icon (candidates: `checklist`, `circle.badge.plus`), and how it reads on a grid tile.
- The editor footer's two states: not on To-Do (add), and on To-Do (circle, which ticks).
- The undo: where it appears (the To-Do list, the editor, both), how long it lasts, and whether ⌘Z also undoes a tick.
- The tick animation (the circle fills, then the row leaves) and the Reduce Motion version.
- Data: existing pinned notes become to-dos. The to-do flag reuses `isPinned`, so there's no migration unless the spec says otherwise.
- VoiceOver label and action for ticking; a keyboard shortcut for ticking the focused row.
- Build order with the grid work: the archive and clock rules land with whichever feature is built second. The grid doc's spec owns where the clock's date is stored.
