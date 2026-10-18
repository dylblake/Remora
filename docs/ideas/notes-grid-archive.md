# Notes grid: archive and a source icon strip

## Problem
Everything that isn't a to-do sits in one grid below To-Do in All Notes, newest first, and it only grows. Two things go wrong as it does:
1. **Too much vertical space.** The grid pushes on and on, and the user scrolls further and further. The only way to shrink it today is to delete notes.
2. **Hard to scan.** A grid of same-height tiles has no landmarks. The one cue that works at a glance is the source icon (the app icon or the site's favicon), and nothing lets the user act on it.

Finding a note from its place already works (notes come back when you return there), and search and the tag dropdown cover finding by text or topic. The gap is managing and browsing the pile from All Notes.

## Who it's for, and how we know
Remora users whose note count grows over months, especially once finished to-dos stay in the grid. The evidence is the product owner's own use and a prediction about where it goes: the live store holds 4 notes today and the free tier stops at 5, so nobody has hit 100+ yet. That argues for changes that are small and reversible.

## What we decided, and why
- **The 2.0.0 "one grid, no sections" decision stands.** Nothing here brings back per-site or per-project headings. The icon strip filters the grid; it doesn't split it, so tiles keep the full width of the pane.
- **Archive.** A note can be archived from its tile (hover or keyboard action) or in bulk through the existing multi-select. Archived notes leave the grid but aren't deleted. Archive is the common answer to a pile that only grows (Keep, Pocket, Gmail, Raindrop), and it's reversible, unlike delete.
- **Auto-archive, on by default.** A note that hasn't been opened or edited for 30 days is archived automatically. The period can be changed or auto-archive turned off in Settings. To-dos are never auto-archived. This keeps the grid's size roughly steady without the user doing anything (as Arc does with tabs and Things with its Logbook).
- **Archived notes still come back at their place.** Archive only hides a note from All Notes; the place stays where it lives. Opening an archived note, from its place or anywhere else, unarchives it, because using a note means it's alive again. This is what makes auto-archive safe to have on by default.
- **A source icon strip above the grid.** One icon per source in the grid (the site's favicon, the app's icon, or the file's icon), each with a count. Picking one filters the grid to that source. Users find a note by where it came from, which is how Remora attaches notes, and the icon is already the strongest cue on a tile.
- **Filtering by source includes that source's archived notes,** marked as archived. Once the view is narrowed to one source the set is small, and "everything I wrote on this Figma file" should be complete.
- **Archived (n) sits at the end of the icon strip.** That's the simple way to pull up archived notes, and it reuses the filter mechanism, so there's no separate control.
- **Search always finds archived notes,** marked as archived. Archive takes notes out of the grid's way; it never makes them harder to find.
- **To-dos show in the grid with the to-do icon.** To-Do is a flag on a note, not a location. Ticking a to-do clears the flag and the note simply stays in the grid. "Move to Notes" is dropped. This was handed to the To-Do work; see `todo-checkoff.md`.
- **Search covers the grid only, never the To-Do list.** Because to-dos are also in the grid, search still finds them.
- **A completed to-do is a plain note in the grid,** with nothing marking it as done.
- **The section stays "Notes"; "bookmark" isn't used anywhere in the app.** Every note already behaves like a bookmark, so the word wouldn't tell anything apart.
- **Multi-select is the same model as To-Do's,** with Archive added as a bulk action (Unarchive in archived views).
- **Only opening the editor resets the auto-archive clock.** A note coming back at its place doesn't, or notes on frequently visited sites would never archive.
- **To-dos are never archived, manually or automatically, and adding a note to To-Do unarchives it.** A note is always in exactly one state: on To-Do (and shown in the grid), in the grid, or archived. Without this rule, an archived note added to To-Do would be hidden from the grid while on To-Do, against `todo-checkoff.md`, and would drop back into the archive when ticked. Adding a note to To-Do means it's being used again, the same reasoning as opening an archived note.
- **Ticking a to-do also resets the clock.** A note can sit on To-Do for months without its editor being opened. Without this rule, it would become a plain note with an expired clock and be archived as soon as it was ticked, so finishing a task would make the note vanish from the grid too.
- **When there are too many sources, the strip scrolls with small arrows at its ends.**
- **Archived notes count towards the free tier's 5-note limit.** Archive isn't a way around the paywall.

## Smallest version
1. An archive flag on notes, with Archive and Unarchive on tiles and as multi-select bulk actions.
2. Archived notes are hidden from the default grid but still come back at their place. Opening one unarchives it.
3. A source icon strip with counts that filters the grid; a source's filter includes its archived notes, marked.
4. Archived (n) at the end of the strip.
5. Search includes archived notes, marked.
6. Auto-archive after 30 days without being opened or edited, on by default, with a Settings control. To-dos are exempt.

## Not doing
- Folders or collections: a third manual organising system, which would also force a home to be picked for every note.
- Grouping or sections (by source, date or tag), or bringing back a list/grid switch. Both would reverse 2.0.0.
- Tags promoted to a tab bar or chips. The search field's tag dropdown already covers finding by topic.
- New sort orders.
- Deleting archived notes automatically.

## Parked decisions (and what would unpark them)
- **Tag chips beside the icon strip.** Unpark if users report finding by topic rather than by source.
- **Auto-archive off by default.** Unpark if auto-archive in practice hides notes the user expected to see.
- **The whole rework.** Hold if, at ~100 notes, the plain grid still feels manageable in the owner's own use.

## Open questions for the spec
- When auto-archive first ships, should existing old notes be archived at once, or should their clock start on the day of the update? The owner is unsure. Proposed: the clock starts at the update for every existing note, so nothing archives for the first 30 days and nobody is surprised by a mass archive.
- How auto-archive tells the user: silent, or a one-time note about what was archived.
- Strip order: most notes first, or most recently used?
- Archive on a to-do's tile, alone or in a multi-select that includes to-dos: hide or disable the action, or skip to-dos and say so?
- Do the strip's counts include archived notes? (Proposed: active notes only, while the filtered view also shows archived ones.)
- Can a source filter be combined with search or a tag?
- How archived tiles look (dimmed, or with a badge), and where archived notes sort within a filtered view (proposed: after active ones).
- Whether the archive state shows in the editor, and whether there's an action there.
- Data: storing the archive flag and the last-opened date, plus migrating existing notes so their clock starts at upgrade, not at `updatedAt`.
- VoiceOver labels for strip icons (the source name and count), and keyboard navigation of the strip.
