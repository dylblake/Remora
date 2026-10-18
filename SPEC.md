# SPEC: To-Do you can check off

Decision doc: `docs/ideas/todo-checkoff.md`. Related: `docs/ideas/notes-grid-archive.md` (built later).

## Objective
To-Do in All Notes becomes a list you work through. A to-do is a flag on a note: the note stays in the Notes grid the whole time, and ticking it off clears the flag. To-Do shows only what's left, and the pin is replaced throughout by a to-do icon.

**Who:** Remora users who put notes on To-Do as tasks tied to a place (a page, a file, an app context).
**Success:** a user can add a note to To-Do, tick it off from the To-Do list, its grid tile, the editor or the keyboard, and undo a mis-tick, without the note ever leaving the grid.

## Vocabulary
- **To-Do**: the list at the top of All Notes (today's pinned notes).
- **Notes grid**: the tiles below it.
- **On To-Do**: the note's to-do flag is set (today's "pinned").
- **Tick**: clearing the flag from the circle; the note becomes a plain note.

## Acceptance criteria

### Adding to To-Do
1. Everywhere a pin button appears today (grid tile, editor footer, the multi-select bar), it is replaced by a `circle.badge.plus` "Add to To-Do" button. No pin symbol remains anywhere in the app.
2. Adding a note to To-Do puts a row for it at the bottom of the To-Do list, and the count beside "To-Do" goes up by one.
3. **A note on To-Do also appears in the Notes grid** in its normal newest-first position, and its tile shows an empty circle (always visible, not only on hover).
4. Notes that were pinned before this update appear on To-Do in their saved order, with no user action needed.

### Ticking
5. Each To-Do row has an empty circle at its leading edge. Clicking it ticks the note: the circle shows a checkmark briefly, then the row leaves the list and the count goes down by one.
6. After a tick, the note's tile is still in the Notes grid, in the same position, without the circle. Nothing on it marks it as done.
7. Clicking the circle on a grid tile ticks the note the same way (same result, same undo).
8. In the editor footer, a note on To-Do shows the empty circle and clicking it ticks the note. A note not on To-Do shows "Add to To-Do". The footer has exactly these two states.
9. With a To-Do row focused by the arrow keys, ⌘Return ticks it. Return still opens the note and Space still selects it.
10. VoiceOver: each To-Do row and tile circle offers a "Complete" action, labelled with the note's title. "Add to To-Do" has its label too.
11. With Reduce Motion on, ticking removes the row without movement (no slide, at most a fade).

### Undo
12. After any tick, a "Completed · Undo" bar appears in All Notes for about 5 seconds. Clicking Undo puts the note back on To-Do **in the position it had** and restores its circle in the grid.
13. While that bar is showing, ⌘Z in All Notes does the same as clicking Undo, except while the search field has the caret: there ⌘Z undoes typing. A tick from the editor footer shows its undo only in the footer (14), so All Notes' bar and ⌘Z don't offer it.
14. Ticking from the editor footer shows "Completed · Undo" in the footer for about 5 seconds, with the same effect.
15. Starting another tick while the bar is showing replaces the bar; Undo then restores only the most recent tick (or the most recent batch, see 17).
16. After the bar is gone, adding the note to To-Do again puts it at the bottom of the list.

### Multi-select
17. In the Notes grid's multi-select bar, the to-do button adds every selected note to To-Do. If every selected note is already on To-Do, it ticks them all instead, and a single Undo restores the whole batch in their previous order.

### Search
18. While the search field has a query (text or tag), the To-Do list is hidden and results come from the Notes grid only. To-dos are still found there, with their circle. Clearing the search brings the To-Do list back unchanged.

### Must not break
19. Dragging To-Do rows to reorder, and VoiceOver Move Up / Move Down, work as before. Clicking a row (without dragging) still opens the note. Clicking the circle never starts a drag or opens the note.
20. Saved notes and the To-Do order survive relaunch. A note ticked off before quit isn't on To-Do after relaunch.
21. Existing UI tests for All Notes, search and the editor pass, updated only where they referred to the pin.

## Out of scope
- Archive, auto-archive, and the archive rules from the decision doc (unarchive on add; tick resets the auto-archive clock). These land with the grid/archive work, which is built second.
- Any record of completed to-dos: a Completed group, completion dates, a history, unticking.
- Checklist items inside a note's body; due dates, reminders, priorities.
- Section renames or any grid restructuring.

## Constraints
- No new account, network or permission requirements.
- The existing note store format must stay readable by this version (existing pinned notes keep working, see 4 and 20).
- Tests use the README's workflow: `xcodebuild -project Remora.xcodeproj -scheme Remora -destination 'platform=macOS' test`, UI tests with the `UITEST_*` isolation hooks and `-trialNotesCreated 0`.
- Changelog entry in the project's existing style.

## Assumptions (confirmed at sign-off)
- While searching, the To-Do list is hidden (criterion 18).
- The undo bar's ~5 seconds is a target, not exact; 4–6s passes.

## Decisions made in review
- **Closing or switching the drawer saves only if the note was edited.** Opening a note and closing it untouched, or ticking it in the footer and pressing Escape, leaves its date alone, so its tile keeps its place in the grid (C6). Typing, a new title or an emptied note still save (or delete) as before.
- **⌘Z in the search field keeps text undo.** The tick's ⌘Z applies only while the search field doesn't have the caret; the bar's Undo button always works (C13).
- **Footer ticks show their undo only in the footer.** The All Notes bar, and ⌘Z there, cover ticks made in All Notes (rows, tiles, the multi-select bar, ⌘Return) only (C13, C14).
- **The multi-select button shows its action.** `checkmark.circle` when every selected note is on To-Do (it completes them), `circle.badge.plus` otherwise (C1, C17).
