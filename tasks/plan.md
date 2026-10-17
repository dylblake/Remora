# Plan: To-Do you can check off

Spec: `SPEC.md` (approved). Decision doc: `docs/ideas/todo-checkoff.md`. Branch: `team/todo-checkoff`.
Criterion numbers below (C1–C21) are the numbered acceptance criteria in `SPEC.md`.

## Commands (from README "Testing" and the XCUITest workflow note)

There is no CLAUDE.md; these come from `README.md` and are the only commands the build loop should use.

- **Build:** `xcodebuild -project Remora.xcodeproj -scheme Remora -destination 'platform=macOS' build`
- **Full suite:** `xcodebuild -project Remora.xcodeproj -scheme Remora -destination 'platform=macOS' test`
- **One unit test class:** `xcodebuild -project Remora.xcodeproj -scheme Remora -destination 'platform=macOS' test -only-testing:RemoraTests/TodoOrderTests`
- **UI tests: special workflow, do not fall back to a plain `test` run.**
  1. Check `automationmodetool` first. If it reports Automation Mode disabled / needs authentication, every UI test fails at init in ~60s ("Timed out while enabling automation mode"). Only the user can re-enable it. Stop and report; don't read it as a test failure.
  2. Build once into a scratch derived-data path, then run without building, wrapped in a watchdog (there is no `timeout` binary):
     ```sh
     DD=<scratchpad>/remora-dd
     xcodebuild -project Remora.xcodeproj -scheme Remora -destination 'platform=macOS' -derivedDataPath "$DD" build-for-testing
     xcodebuild -project Remora.xcodeproj -scheme Remora -destination 'platform=macOS' -derivedDataPath "$DD" \
       test-without-building -only-testing:RemoraUITests/TodoListUITests &
     XB=$!; ( sleep 540; kill $XB 2>/dev/null ) & WD=$!; wait $XB; kill $WD 2>/dev/null
     ```
     After a hang: `pkill -x Remora; pkill -f RemoraUITests-Runner`.
  3. Every UI test launches with the isolation hooks: `UITEST_LAUNCH_ACTION` (`allNotes` / `quickNote`), `UITEST_STORE_DIRECTORY=<tmp>`, `REMORA_PANE_WIDTH=640`, `REMORA_DISABLE_FAVICONS=1`, and launch args `-hasCompletedOnboarding YES -trialNotesCreated 0 -autoTitleEnabled NO` (`-editorTextZoom 1` for editor tests). Without `-trialNotesCreated 0`, editor tests fail with "Note editor did not open"; that's the trial gate, not flakiness.
  4. The AX deadlock guard: don't add background accessibility calls. Anything new that walks AX must keep the own-pid guard in `ContextResolver.resolveCurrentContext`.
  5. While a scratch-store instance is running it takes the user's hotkey. Keep runs short, and check the scratch `notes.json` for notes nobody seeded before throwing it away.
  6. SwiftUI `Menu` labels show up as `element.title` in XCUITest, not `.label`.
- **No-pin sweep (C1):** `grep -rnE '"pin(\.fill)?"|systemName: *"pin' Remora` must print nothing.

## Current state (what exists)

- `ContextNote.isPinned` (`Remora/Core/Models/ContextNote.swift`) is the to-do flag. It's decoded with `decodeIfPresent ?? false`, and `copying(updatedAt:isPinned:)` already exists.
- `NoteSectionBuilder.build(from:todoOrder:)` (`Remora/Core/Models/NoteSections.swift`) puts pinned notes in `todo` and only **unpinned** ones in `notes`. That's the line C3 changes.
- `NotesState` (`Remora/App/NotesState.swift`):
  - `todoOrder` is reconciled in `notes.didSet` by `reconciledTodoOrder`: unpinned IDs drop out and newly pinned ones are appended, newest first.
  - `togglePin` and `togglePinForSelectedNotes` **bump `updatedAt` to `.now`**. That moves the tile to the top of the newest-first grid and changes its date label, which breaks C3/C6.
  - `reorderTodo(visibleOrder:)` already copes with a filtered list.
  - The search path (`scheduleSearchRecompute`) builds sections off the main thread.
- `AppState.togglePin`, `togglePinForSelectedNotes` and `togglePinForActiveNote` (`Remora/App/AppState.swift` ~1111–1155) keep `editor.isActiveNotePinned` in sync. `togglePinForActiveNote` goes through `editor.persistCurrentEditorContent`, which always writes `updatedAt: .now`.
- `ContentView.swift`:
  - Keyboard navigation flattens `noteSections` into `orderedVisibleNotes` and tracks `keyboardFocusedNoteID: UUID?`.
  - Rows and tiles both use `.id(note.id)` for `ScrollViewReader`. **Once a to-do is in both sections, the same UUID appears twice**: the focus highlight shows on both the row and the tile, `firstIndex` gets stuck, and `scrollTo` is ambiguous.
  - `TodoRow` puts its `reorderGesture` on the inner title HStack only. `NotePinButton` is a sibling *outside* the gesture, which is the pattern the circle reuses.
  - Hidden ⌘F `Button(...).keyboardShortcut` in `.background` is the proven pattern for key equivalents in this non-activating panel.
- `NoteTile` hosts its actions in a `sourceLine` overlay inside `.pressableCard` (an `onTapGesture`). Buttons in there already win over the tap, as the pin does today.
- The footer pin (`FloatingNoteEditorView.swift` ~204) is an `IconButton` with identifier `editorPinButton`.
- Project uses `PBXFileSystemSynchronizedRootGroup`: new `.swift` files are picked up without editing `project.pbxproj`.
- The CHANGELOG uses a `## Unreleased` heading between releases (see the history of 5c1629c and 1472f6f), with `###` feature headings and bold lead sentences.

## Architecture decisions

1. **Keep the stored field `isPinned`.** No store-format change and no migration (C4, C20, Constraints). Internal Swift names that only the code sees (`isPinned`, `isActiveNotePinned`) stay as they are, to keep the diff small. New methods use to-do vocabulary. Each `isPinned` declaration gets a one-line doc comment: "On To-Do."
2. **Changing the flag never touches `updatedAt`.** Ticking, adding and undoing all use `copying(isPinned:)` without `updatedAt`, so the tile keeps its grid position and date (C3, C6). The one exception is the editor footer when the editor holds unsaved typing: then the normal persist runs, since the content really changed.
3. **Undo is a snapshot of order indexes.** `completeTodos` returns a `TodoCompletion` that records each note's index in `todoOrder` before removal. `restore` re-inserts them by index, lowest index first, clamped. A pure static function does the order maths, so it can be unit-tested.
4. **One undo slot.** A small `@Observable TodoUndoState` (new file `Remora/App/TodoUndoState.swift`) holds `pending` (the completion, its origin `.allNotes` or `.editor`, and a token). Its lifetime is injected (default 5s) so tests can run it fast. Registering a new completion replaces the pending one and restarts the timer (C15). AppState owns it, because undo must also sync the editor.
5. **Keyboard focus and scroll IDs become (section, note).** `struct ListFocus: Hashable { let sectionID: String; let noteID: UUID }` replaces `keyboardFocusedNoteID`. Rows and tiles use it as their `.id`, so the same note in the To-Do list and in the grid is two distinct stops.
6. **Search hides the To-Do list in the builder.** `build(from:todoOrder:includesTodo:)` returns an empty `todo` section when `includesTodo` is false. `NotesState` passes `searchText.isEmpty`, the same test `filter` uses. The view already skips empty sections.
7. **⌘Return and ⌘Z use hidden `keyboardShortcut` buttons**, the existing ⌘F pattern, rather than `onKeyPress` with modifiers (see Risks).

## Dependency graph

```
T1 NotesState flag ops + restore maths (pure)
 ├─ T2 Sections: to-dos in grid, search hides To-Do, ListFocus
 └─ T3 TodoUndoState + AppState coordinator
       ├─ T4 Shared buttons; tiles + multi-select bar   (needs T2)
       │    └─ T5 To-Do row circle, VO, motion
       │         ├─ T6 All Notes undo bar + ⌘Z
       │         └─ T7 ⌘Return tick
       └─ T8 Editor footer two states + footer undo
T9 Persistence/relaunch + regression sweep  (after T1–T8)
T10 Changelog + README                       (last)
```

---

## Task 1: Flag operations and undo-order maths in NotesState

**Description:** Replace `togglePin` / `togglePinForSelectedNotes` with to-do operations that leave `updatedAt` alone, and add the pure restore function. This is all model work, no UI. It goes first because index-accurate undo is the riskiest logic.

Signatures (pseudocode):
```swift
nonisolated struct TodoCompletion: Equatable, Sendable {
    struct Entry: Equatable, Sendable { let noteID: UUID; let index: Int }
    let entries: [Entry]            // ascending index, captured before removal
    var noteIDs: [UUID] { entries.map(\.noteID) }
}
// NotesState
func addToTodo(_ ids: Set<UUID>)                      // flag on, updatedAt kept; reconcile appends at end
func completeTodos(_ ids: [UUID]) -> TodoCompletion?  // nil if none of ids is on To-Do
func restore(_ completion: TodoCompletion)            // skips deleted notes; todoOrder = restoringOrder(...); rebuild sections; save
nonisolated static func restoringOrder(_ current: [UUID], inserting: [TodoCompletion.Entry]) -> [UUID]
```
`restore` assigns `notes` (didSet reconciles and appends the restored IDs at the end). It then overwrites `todoOrder` with `restoringOrder(current minus restored, entries)`, rebuilds `noteSections` and calls `save()`, the same way `reorderTodo` does.

**Acceptance criteria:**
- [ ] `addToTodo` puts each note at the end of `todoOrder` without changing its `updatedAt` (C2, C3; supports C16).
- [ ] `completeTodos` clears the flag, removes the note from `todoOrder`, keeps `updatedAt`, and records the pre-removal indexes (C6, C12).
- [ ] `restore` puts notes back at their recorded indexes. A batch comes back in its previous order, and a note deleted in the meantime is skipped (C12, C17).

**Verification:**
- [ ] Unit tests (new, in `RemoraTests/TodoOrderTests.swift`):
  - `restoringOrder` with one entry, a batch of non-adjacent entries, an index past the end (clamped), and a note added in between.
  - complete then restore gives back an identical `todoOrder`.
  - `updatedAt` is unchanged after add, complete and restore.
  - restore after delete.
  - Update `testPinningAppendsToTheEndAndUnpinningRemoves` to the new API.
- [ ] `xcodebuild -project Remora.xcodeproj -scheme Remora -destination 'platform=macOS' test -only-testing:RemoraTests/TodoOrderTests`
- [ ] Build succeeds. Temporary call-site shims in `AppState` are fine until T3, but no behaviour change ships half-done.

**Dependencies:** None
**Files:** `Remora/App/NotesState.swift`, `RemoraTests/TodoOrderTests.swift`, `Remora/App/AppState.swift` (call sites only)
**Scope:** S

## Task 2: To-dos also in the Notes grid; search hides To-Do; per-section keyboard focus

**Description:** Make the `notes` section contain every filtered note, newest first. The To-Do section is empty while there's a query. Replace `keyboardFocusedNoteID` with `ListFocus` so a note shown twice is two separate keyboard stops and two separate scroll targets.

**Acceptance criteria:**
- [ ] With no query, a note on To-Do appears both as a row and as a tile in its newest-first position. The "Notes, N notes" heading counts it (C3; circle comes in T4).
- [ ] With a text or `#tag` query, no To-Do list is shown, and matching to-dos appear as tiles. Clearing the query brings back the same list in the same order (C18).
- [ ] Arrow keys walk the rows, then every tile, with no stop skipped or duplicated. Return, Space and Delete act on the focused stop (C9's "Return/Space unchanged", C21).

**Verification:**
- [ ] Unit tests:
  - `NoteSectionBuilder.build`: to-dos in both sections; `includesTodo: false` gives an empty todo section.
  - A pure `focusOrder(sections) -> [ListFocus]` lists rows first, then tiles, with no collisions.
  - Update `testSectionFollowsOrderAndPutsUnorderedNotesLast` (the grid now includes a, b, c).
- [ ] UI tests (`RemoraUITests/TodoListUITests.swift`):
  - Update `testPinnedNotesShowAsACountedListInStoredOrder`: the grid heading is now "Notes, 4 notes" and the tiles include Alpha to Charlie.
  - New `testSearchHidesTheToDoListAndFindsToDosInTheGrid`: type "Bravo"; `todoList` is gone and a `noteTile` labelled Bravo exists; clear the search and the rows are back in stored order.
- [ ] `AllNotesSearchUITests` still passes unchanged.
- [ ] Unit command as T1; UI via the watchdog workflow with `-only-testing:RemoraUITests/TodoListUITests -only-testing:RemoraUITests/AllNotesSearchUITests`.

**Dependencies:** T1
**Files:** `Remora/Core/Models/NoteSections.swift`, `Remora/App/NotesState.swift` (`keyboardFocus`, `includesTodo` in both recompute paths and `reorderTodo`), `Remora/App/AppState.swift` (`resetAllNotesBrowsing`), `Remora/Features/MenuBar/ContentView.swift` (nav helpers, `.id`, highlight checks), tests
**Scope:** M

## Task 3: Undo slot and AppState coordinator

**Description:** Add `TodoUndoState`. Replace the three `AppState` pin methods with to-do ones that sync `editor.isActiveNotePinned` whenever the active note is affected, including on undo.

```swift
enum TodoCompletionOrigin { case allNotes, editor }
@MainActor @Observable final class TodoUndoState {
    struct Pending: Equatable { let completion: TodoCompletion; let origin: TodoCompletionOrigin; let token: UUID }
    private(set) var pending: Pending?
    init(lifetime: Duration = .seconds(5))
    func register(_ c: TodoCompletion, origin: TodoCompletionOrigin)  // replaces; restarts expiry Task
    func take() -> TodoCompletion?                                    // returns and clears
}
// AppState
func addToTodo(_ notes: [ContextNote])
func completeTodo(_ noteIDs: [UUID], origin: TodoCompletionOrigin)
func undoLastCompletion()
func toggleTodoForSelectedNotes()   // all on To-Do → complete batch (origin .allNotes); else add the rest
```

**Acceptance criteria:**
- [ ] A completion registers a pending undo that clears itself after the lifetime. A second completion replaces the first, and undo then restores only the second (C12, C15).
- [ ] After expiry, `undoLastCompletion` does nothing, and adding the note again appends it at the end (C16).
- [ ] Completing, or undoing, the note open in the editor updates `editor.isActiveNotePinned`, so dismissing the drawer doesn't write the old flag back.

**Verification:**
- [ ] Unit tests (new `RemoraTests/TodoUndoTests.swift`): `TodoUndoState` with a ~0.1s lifetime covering expiry, replacement and `take` clearing. Batch selection: all on To-Do completes as one completion; a mixed selection adds. Use `NotesState` + `TodoUndoState` directly. AppState is too heavy to build in tests; keep the selection decision in a `NotesState` method that AppState calls.
- [ ] Editor sync: extend the `DrawerStackTests` style (EditorState + NotesState) for complete/restore of the active note's flag, if the sync is moved there. Otherwise review it manually.
- [ ] `xcodebuild -project Remora.xcodeproj -scheme Remora -destination 'platform=macOS' test -only-testing:RemoraTests/TodoUndoTests -only-testing:RemoraTests/TodoOrderTests`

**Dependencies:** T1
**Files:** `Remora/App/TodoUndoState.swift` (new), `Remora/App/AppState.swift`, `Remora/App/NotesState.swift`, `RemoraTests/TodoUndoTests.swift` (new)
**Scope:** M

## Checkpoint A (after T1–T3)
- [ ] Full unit suite passes: `xcodebuild -project Remora.xcodeproj -scheme Remora -destination 'platform=macOS' test -only-testing:RemoraTests`
- [ ] Build succeeds. All Notes shows to-dos in the grid. Keyboard navigation is sane.

## Task 4: Shared to-do buttons, on tiles and in the multi-select bar

**Description:** Replace `NotePinButton` in `NoteActionButtons.swift` with two components:
- **`TodoAddButton(note:)`**: `circle.badge.plus`, label and help "Add to To-Do".
- **`TodoCheckCircle(note:, origin:, onCompleted:)`**: `circle`. On click it shows `checkmark.circle.fill` for about 0.35s, then calls `appState.completeTodo`. A second click while it's ticking is ignored. VoiceOver label: `Complete “<title>”`. The accessibility action completes immediately, with no delay.

Tiles show `TodoCheckCircle` **always** when the note is on To-Do. Otherwise they show `TodoAddButton` with the hover actions. `reservedActionsWidth` accounts for the always-visible circle. The bulk bar uses `circle.badge.plus` and calls `appState.toggleTodoForSelectedNotes()`. Its label reads "Add selected notes to To-Do", or "Complete selected notes" when all are on To-Do.

**Acceptance criteria:**
- [ ] No pin symbol anywhere. The tile and bulk-bar buttons use `circle.badge.plus` (C1).
- [ ] A to-do tile shows the empty circle without hover. Clicking it ticks the note: the row leaves, the tile stays in place without a circle, and nothing marks it done (C3, C6, C7).
- [ ] With the multi-select bar, a mixed selection is added to To-Do. An all-to-do selection is ticked as one batch (C17; undo UI in T6).

**Verification:**
- [ ] No-pin sweep grep prints nothing.
- [ ] UI tests (`TodoListUITests`):
  - `testTileCircleTicksAndTileStays`: click the Bravo tile's "Complete “Bravo”" button. Rows become Alpha, Charlie; the header reads "To-Do, 2 notes"; the Bravo tile still exists and its frame index among tiles is unchanged; no "Complete “Bravo”" element remains.
  - `testAddToToDoFromTileAppendsRow`: hover Delta, click "Add to To-Do". Rows become Alpha, Bravo, Charlie, Delta.
  - `testMultiSelectAddsThenTicksBatch`: select Delta (checkbox) and click the bulk button, which adds. Then select all four and click it again: rows are empty.
- [ ] Watchdog UI command, `-only-testing:RemoraUITests/TodoListUITests`.

**Dependencies:** T2, T3
**Files:** `Remora/Core/Components/NoteActionButtons.swift`, `Remora/Features/MenuBar/ContentView.swift`, `RemoraUITests/TodoListUITests.swift`
**Scope:** M

## Task 5: To-Do row circle, VoiceOver, Reduce Motion

**Description:** Give each `TodoRow` a leading `TodoCheckCircle` as a **sibling before** the gesture-bearing title HStack, never inside it. That keeps a click on the circle out of the `DragGesture`, so it can't open the note or start a drag. Remove the trailing hover pin. The context-menu item "Remove from To-Do" becomes "Complete" (same tick and undo). Add a `Button("Complete")` to the row's `accessibilityActions`, next to Move Up/Down.

Row removal: complete inside `withAnimation(reduceMotion ? nil : settle)`. The row's transition is `.opacity` under Reduce Motion and opacity plus a collapse otherwise, with no horizontal slide either way. When the focused row is ticked, keyboard focus moves to the next row, then the previous one, then the first tile (mirrors `confirmDeleteKeyboardFocusedNote`).

**Acceptance criteria:**
- [ ] Each row has an empty leading circle. Clicking it shows a checkmark briefly, then the row leaves and the count drops by one (C5).
- [ ] VoiceOver: the row offers "Complete" next to Move Up / Move Down, and the circle is labelled `Complete “<title>”` (C10).
- [ ] Dragging, VO Move Up/Down and click-to-open behave exactly as before. Clicking the circle doesn't open the note or start a drag. With Reduce Motion, removal is instant or a fade only (C11, C19).

**Verification:**
- [ ] UI tests:
  - `testRowCircleTicksWithCheckmarkThenLeaves`: click Bravo's row circle. Rows become Alpha, Charlie; "All Notes" still exists (nothing opened); header count is 2; the Bravo tile is still present.
  - Keep `testDraggingARowReordersAndPersists` passing unchanged.
  - Replace `testRemovingFromToDoMovesTheNoteBackToTheTiles` with `testContextMenuCompleteTicks`, using the menu item "Complete".
  - VO action: `row("Alpha")` exposes the custom action. If XCUITest can't enumerate custom actions, check with Accessibility Inspector and record the result in the PR.
- [ ] Manual: Reduce Motion on in System Settings > Accessibility > Display; tick a row and confirm nothing slides. `PanelAnimation.prefersReducedMotion` has no test override, so this check stays manual.
- [ ] Watchdog UI command for `TodoListUITests`.

**Dependencies:** T4
**Files:** `Remora/Features/MenuBar/ContentView.swift`, `RemoraUITests/TodoListUITests.swift`
**Scope:** M

## Task 6: "Completed · Undo" bar in All Notes, and ⌘Z

**Description:** While `appState.todoUndo.pending != nil`, show a glass capsule overlay at the bottom centre of `ContentView`. Identifier `todoUndoBar`. It reads "Completed" (or "Completed 3" for a batch) and has an "Undo" button. It shows for ticks from any origin, as long as All Notes is on screen. Add a hidden `Button("") { appState.undoLastCompletion() }.keyboardShortcut("z", modifiers: .command)` to `.background`, present only while something is pending (so ⌘Z is a no-op otherwise). Transition: opacity under Reduce Motion, opacity and a small move otherwise.

**Acceptance criteria:**
- [ ] After any tick, the bar shows for about 5s (4–6s passes). Undo puts the note back at its old index, and its tile circle reappears (C12).
- [ ] ⌘Z while the bar shows does the same. With nothing pending, ⌘Z does nothing (C13).
- [ ] A second tick replaces the bar, and Undo restores only that tick or batch. After the bar has gone, adding the note puts it at the bottom (C15, C16, C17 undo).

**Verification:**
- [ ] UI tests:
  - `testUndoRestoresPosition`: tick Bravo, click "Undo"; rows are Alpha, Bravo, Charlie again.
  - `testCommandZUndoes`: tick Alpha, then `app.typeKey("z", modifierFlags: .command)`.
  - `testUndoBarExpires`: tick, then wait up to 7s for `todoUndoBar` to stop existing; it must still exist at 3.5s.
  - `testSecondTickReplacesUndo`: tick Alpha, tick Charlie, Undo; rows are Bravo, Charlie.
  - `testBatchUndoRestoresOrder`: select all three to-dos, use the bulk button, then Undo; rows are Alpha, Bravo, Charlie.
  - `testReAddAfterExpiryGoesToBottom`: tick Alpha, wait for the bar to go, add from the Alpha tile; rows are Bravo, Charlie, Alpha.
- [ ] Watchdog UI command for `TodoListUITests`. The expiry tests add about 14s.

**Dependencies:** T5
**Files:** `Remora/Features/MenuBar/ContentView.swift`, `RemoraUITests/TodoListUITests.swift`
**Scope:** S–M

## Task 7: ⌘Return ticks the focused To-Do row

**Description:** Add a hidden `keyboardShortcut(.return, modifiers: .command)` button next to the ⌘F one. Its action:
- does nothing while the search field is focused;
- does nothing unless `keyboardFocus.sectionID == todoSectionID`;
- otherwise calls `completeTodo([id], origin: .allNotes)` through the same tick path as the circle, checkmark included.

Plain `.onKeyPress(.return)` (open) and `.space` (select) stay as they are, but must ignore presses that carry ⌘, if `onKeyPress` sees them at all.

**Acceptance criteria:**
- [ ] With a row focused by the arrow keys, ⌘Return ticks it (with undo bar) (C9).
- [ ] Return still opens the note and Space still selects it. ⌘Return on a tile, or while the search field is focused, does nothing.

**Verification:**
- [ ] UI test `testCommandReturnTicksFocusedRow`: click the search field, press Down to focus the first row (Alpha), press ⌘Return. Rows become Bravo, Charlie and the undo bar shows. Then focus Bravo, press Space, and the "1 selected" bar appears.
- [ ] Existing Return-opens behaviour: review `AllNotesSearchUITests.testArrowKeysAndReturnPickAHighlightedTag` still passes.
- [ ] Watchdog UI command for `TodoListUITests` and `AllNotesSearchUITests`.

**Dependencies:** T5, T6
**Files:** `Remora/Features/MenuBar/ContentView.swift`, `RemoraUITests/TodoListUITests.swift`
**Scope:** S

## Checkpoint B (after T4–T7)
- [ ] Full unit suite plus `RemoraUITests/TodoListUITests` and `RemoraUITests/AllNotesSearchUITests` pass with the watchdog workflow.
- [ ] Manual run with a seeded scratch store (`open -n --env UITEST_LAUNCH_ACTION=allNotes --env UITEST_STORE_DIRECTORY=...`): tick, undo, ⌘Z, ⌘Return, search, drag. Keep it short (it takes the user's hotkey) and relaunch the real app afterwards.

## Task 8: Editor footer has two states, plus footer undo

**Description:** In `FloatingNoteEditorView.footer`, the to-do control has exactly two states:
- **Not on To-Do:** `IconButton("circle.badge.plus", "Add to To-Do")` → `appState.addActiveNoteToTodo()`.
- **On To-Do:** a `circle` button labelled `Complete “<title>”`. It shows the checkmark briefly, then `appState.completeActiveNote()` (origin `.editor`).

Identifier: `editorTodoButton`, which replaces `editorPinButton`. While `todoUndo.pending?.origin == .editor` and it contains the active note, a "Completed · Undo" capsule (identifier `editorUndoBar`) replaces the dismiss-hint capsule. The control itself shows "Add to To-Do" in that time, since the note is off To-Do.

`AppState` rewrites `togglePinForActiveNote` into add and complete:
- If the editor has unpersisted changes, persist with the new flag. `hasUnpersistedChanges` becomes internal.
- If there are none and a stored note exists, upsert `copying(isPinned:)` without `updatedAt`, then register the completion from `notesState.completeTodos` so the index is captured.
- If there's no stored note (empty new drawer), flip only `isActiveNotePinned`, with no undo bar.

Switching the drawer to another note drops the footer bar. The pending undo itself still lives until it expires.

**Acceptance criteria:**
- [ ] The footer shows exactly "Add to To-Do" or the circle, matching the note's state, including after a tick or undo from All Notes while the note is open (C8).
- [ ] Ticking from the footer shows "Completed · Undo" in the footer for about 5s. Undo puts the note back at its old To-Do index (C14).
- [ ] A footer tick with no typing doesn't change the note's `updatedAt`, so its grid tile doesn't move (C6).

**Verification:**
- [ ] UI test (in `NoteEditorUITests`, or a new `EditorTodoUITests` with the same `quickNote` setup and `-trialNotesCreated 0`):
  - type text; click `editorTodoButton` ("Add to To-Do"); its label becomes `Complete …`;
  - click it; `editorUndoBar` appears and the button reads "Add to To-Do";
  - click "Undo"; the label is `Complete …` again;
  - press Escape and read the scratch `notes.json`: `isPinned` is true and `todoOrder` contains the id.
- [ ] Update any UI test referring to `editorPinButton` (grep finds none today).
- [ ] Unit (`TodoUndoTests`): completing the active note with no edits keeps `updatedAt`.
- [ ] Watchdog UI command, `-only-testing:RemoraUITests/NoteEditorUITests` (or the new class).

**Dependencies:** T3, T4 (shared circle component)
**Files:** `Remora/Features/Editor/FloatingNoteEditorView.swift`, `Remora/App/AppState.swift`, `Remora/App/EditorState.swift`, UI test file
**Scope:** M

## Task 9: Persistence, relaunch and regression sweep

**Description:** Prove C4, C20 and C21 end to end, and remove any leftover pin wording.

**Acceptance criteria:**
- [ ] Notes pinned in an older store load onto To-Do in saved order, and also appear in the grid, with nothing for the user to do (C4).
- [ ] A note ticked before quit isn't on To-Do after relaunch. Order and notes survive (C20).
- [ ] All existing UI tests for All Notes, search and the editor pass. They were changed only where they referred to the pin (C21).

**Verification:**
- [ ] Unit tests:
  - extend `testFilesWithoutAnOrderStillLoad`: both notes are also in the grid;
  - new `testCompletionPersistsAcrossReload`: complete, `flush()`, reload a `NotesState` from the same directory, and the note isn't on To-Do.
- [ ] UI test `testTickSurvivesRelaunch`: tick Bravo, wait 1s (saves are debounced), `app.terminate()`, `app.launch()` with the same store; rows are Alpha, Charlie.
- [ ] No-pin sweep grep. Also `grep -rn "Remove from To-Do\|Pin" Remora/Features Remora/Core/Components` shows nothing user-facing.
- [ ] Full suite: `xcodebuild -project Remora.xcodeproj -scheme Remora -destination 'platform=macOS' test`, with the UI part run through the watchdog workflow.

**Dependencies:** T1–T8
**Files:** `RemoraTests/TodoOrderTests.swift`, `RemoraUITests/TodoListUITests.swift`
**Scope:** S

## Task 10: Changelog and README

**Description:**
- Add a `## Unreleased` section at the top of `CHANGELOG.md` in the house style: a `###` heading, bold lead sentences, a short "why it matters" for each. Cover:
  - to-dos stay in the grid with a circle;
  - ticking from the list, tile, editor or ⌘Return;
  - Completed · Undo and ⌘Z;
  - search covers the grid only;
  - the pin icon is replaced by Add to To-Do.
- Update the README feature line "Pin notes to a To-Do list…".
- Don't bump the version (that belongs to the release commit).

**Acceptance criteria:**
- [ ] The changelog entry matches the existing style, with no "pin" except to say it was replaced.
- [ ] The README feature list describes adding to and ticking off To-Do.

**Verification:** Proofread against the 2.0.3 entry. Build still succeeds.
**Dependencies:** T9
**Files:** `CHANGELOG.md`, `README.md`
**Scope:** XS

## Final checkpoint
- [ ] Full unit and UI suites green using the workflow above.
- [ ] Every criterion C1–C21 is ticked against the task that covers it (map below).
- [ ] Ready for review.

### Criterion → task map
C1 T4/T8/T9 · C2 T1/T4 · C3 T2/T4 · C4 T9 · C5 T5 · C6 T1/T4/T8 · C7 T4 · C8 T8 · C9 T2/T7 · C10 T4/T5 · C11 T5 · C12 T1/T3/T6 · C13 T6 · C14 T8 · C15 T3/T6 · C16 T3/T6 · C17 T1/T4/T6 · C18 T2 · C19 T5 · C20 T9 · C21 T2/T9

---

## Reuse

| Task | Builds on |
|---|---|
| T1 | `ContextNote.copying(isPinned:)` (`Remora/Core/Models/ContextNote.swift`), `NotesState.reconciledTodoOrder`, the `reorderTodo` pattern for overwriting `todoOrder` + rebuilding sections + `save()` (`Remora/App/NotesState.swift`), `NoteStore.save(notes:todoOrder:)`, `TodoOrderTests` helpers `note(_:pinned:updated:)` / `makeState()` |
| T2 | `NoteSectionBuilder` (`Remora/Core/Models/NoteSections.swift`), `NotesState.filter` and both recompute paths, `ContentView` keyboard helpers (`moveKeyboardFocus`, `confirmDeleteKeyboardFocusedNote` neighbour logic), `CountedSectionHeading`, the `TodoListUITests` seed and helpers, `AllNotesSearchUITests.searchField` / `focusSearchField` |
| T3 | `AppState.togglePin*` editor-sync logic (`Remora/App/AppState.swift` ~1111–1155), the debounce Task pattern in `scheduleSearchRecompute`, `DrawerStackTests.makeState()` for EditorState + NotesState tests |
| T4 | `NotePinButton` shape (26pt frame, `.borderless`, help + label) in `Remora/Core/Components/NoteActionButtons.swift`, `IconButton` (`Remora/Core/Components/IconButton.swift`), `NoteTile.actions` / `reservedActionsWidth`, `bulkActionBar` |
| T5 | `TodoRow` sibling layout (pin button already sits outside `reorderGesture`), `accessibilityActions` Move Up/Down, `settle` animation and `reduceMotion` env in `TodoListSection`, `.contextMenu` |
| T6 | `bulkActionBar` glass capsule styling (`.glassEffect(.regular, in: Capsule)`), the hidden ⌘F `keyboardShortcut` button in `ContentView`, `PanelAnimation.prefersReducedMotion` transition pattern |
| T7 | Same hidden-button pattern, `unlessSearching` / `isSearchFieldFocused`, `ListFocus` from T2 |
| T8 | Footer `IconButton` + `GlassEffectContainer`, the hint capsule's glass style, `EditorState.persistCurrentEditorContent` / `hasUnpersistedChanges`, `NoteEditorUITests` setup and `button(_:)` helper |
| T9 | `testFilesWithoutAnOrderStillLoad`, `testReorderPersistsAcrossReload` (flush + reload pattern), `TodoListUITests.storedOrder()` |
| T10 | CHANGELOG `## Unreleased` convention, 2.0.3 entry style |

## Risks and alternatives considered

### Risks
1. **The same note in two sections breaks keyboard focus and scroll IDs.** Today `keyboardFocusedNoteID` and `.id(note.id)` assume each note appears once. *Mitigation:* `ListFocus` (T2) lands in the same task that adds to-dos to the grid, so no intermediate build has duplicate stops. Selection (`selectedNoteIDs`) stays per note on purpose: selecting a row also marks its tile.
2. **Drag gesture vs circle hit-testing (C19).** The row's `DragGesture(minimumDistance: 0)` on `.global` captures any press inside its view. *Mitigation:* the circle is a sibling outside the gesture view (as the pin is now), and `testDraggingARowReordersAndPersists` stays as a guard. On tiles, the circle is a `Button` inside `pressableCard`'s overlay, the same position the pin works from today. Don't add `.highPriorityGesture` or `.simultaneousGesture` to the row.
3. **Undo restoring the index.** `notes.didSet` reconciliation appends re-flagged notes at the end, so a naive restore lands at the bottom. *Mitigation:* `restore` overwrites `todoOrder` after the assignment, using indexes captured before removal (pure, unit-tested in T1). Edge cases resolved: indexes are clamped; notes deleted in between are skipped; a reorder during the 5s window places the note by index, not by neighbour.
4. **⌘Z / ⌘Return routing in a non-activating panel.** `onKeyPress` with ⌘ may never see the event, because command keys go through `performKeyEquivalent` first. *Mitigation:* use hidden `keyboardShortcut` buttons, the pattern ⌘F already proves in this panel. When the panels are stacked and the note editor is key, ⌘Z belongs to the text view's own undo (`RichTextEditor.performKeyEquivalent`). That's correct, because C13 scopes ⌘Z to All Notes. The All Notes ⌘Z button exists only while an undo is pending, so it never swallows ⌘Z otherwise.
5. **Editor footer state sync.** The drawer writes `isActiveNotePinned` back on dismiss and autosave, so a tick or undo from All Notes must update it or the old flag returns. *Mitigation:* every flag change goes through AppState methods that sync the editor (T3), covered by a test. A footer tick must not bump `updatedAt` unless there's unsaved typing (T8).
6. **`updatedAt` churn.** Today pinning bumps `updatedAt`, so a tick would move the tile to the top and change its date, failing C6. *Mitigation:* flag changes keep `updatedAt` (decision 2), with unit assertions. Side effect: the ticked note no longer counts as "recent" in `recentNotes`. That's intended.
7. **UI-test environment.** Automation Mode can be off after an OS update, and expiry tests add wall-clock time. *Mitigation:* the workflow above (check `automationmodetool`, watchdog, scratch derived data). Undo-expiry tests use generous bounds (still there at 3.5s, gone by 7s).

### Alternatives rejected
- **Rename the stored field to `isTodo` / add a new key.** Rejected: it needs a migration and dual-read code for no user benefit, and the constraints require the old store to stay readable. Renaming only the Swift property (keeping the `isPinned` coding key) was also rejected, as churn across ~20 call sites and tests. It can be a follow-up.
- **Use `NSUndoManager` for ⌘Z.** Rejected: the All Notes panel has no responder chain undo today, the editor's text view owns its own manager, and C15 wants a single slot, not a stack. A purpose-built single slot is simpler and testable.
- **Restore by "insert after previous neighbour".** Rejected in favour of indexes. Neighbours can themselves be ticked in a batch, and indexes give the exact previous order for batches (C17).
- **Delay the model change until the checkmark animation finishes, by keeping the row in a "ticking" state in NotesState.** Rejected: it would put view timing into the model. The circle keeps the ~0.35s checkmark as local view state and commits at the end. ⌘Return goes through the same path, so it shows the checkmark too. The VoiceOver action commits immediately.
- **Put the undo bar in the header slot next to "All Notes"** (where the multi-select bar lives). Rejected: a single tick while notes are selected would fight for the slot. A bottom overlay is free.

### Ambiguities resolved (most conservative reading)
1. **The context menu "Remove from To-Do" on rows** is renamed "Complete" and does the same tick with undo. The decision doc says ticking and removing are now one action.
2. **The multi-select bar icon** stays `circle.badge.plus` in both modes (C1 literally). Only the label and help change to "Complete selected notes" when every selected note is on To-Do.
3. **Adding to To-Do doesn't bump `updatedAt`**, so the tile keeps its grid position (C3 "normal newest-first position"). New rows still go to the bottom (C2).
4. **⌘Return only ticks a focused To-Do row**, not a focused to-do tile (C9 names rows). It does nothing while the search field has focus.
5. **The All Notes undo bar shows for ticks from any origin**, editor included, when All Notes is visible (C12 "after any tick"). The footer bar shows only for footer ticks of the active note (C14). One shared slot backs both.
6. **⌘Z while the search field is focused**, with an undo pending, still undoes the tick. The field has no undo of its own in this menu-less app, and C13 says "in All Notes".
7. **The VoiceOver label** for the circles is `Complete “<title>”`. The row's custom action is named "Complete" (the row's label already starts with the title). "Add to To-Do" keeps its current label.
8. **Ticking a note in an empty, unsaved drawer** (flag set, nothing typed) clears the flag with no undo bar, since there's no stored note to restore.
9. **Keyboard focus after ticking the focused row** moves to the next row, then the previous one, then the first tile.
10. **The changelog** goes under `## Unreleased` with no version bump, following the project's commit history.
11. **Reduce Motion (C11)** is verified manually. There is no launch-argument override for `accessibilityDisplayShouldReduceMotion`, and adding one is out of scope.
