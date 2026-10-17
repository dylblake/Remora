# To-Do: To-Do you can check off

Full detail, commands and the UI-test workflow are in `tasks/plan.md`. C-numbers refer to the acceptance criteria in `SPEC.md`.

- [x] **T1** Flag ops (`addToTodo`, `completeTodos` → `TodoCompletion`, `restore`, `restoringOrder`) with no `updatedAt` bump (C2, C6, C12, C17). Unit: `TodoOrderTests`.
- [x] **T2** To-dos also in the Notes grid; search hides To-Do; `ListFocus` (section, note) for keyboard focus and scroll IDs (C3, C18, C9 Return/Space). Unit + UI: `TodoListUITests`, `AllNotesSearchUITests`.
- [x] **T3** `TodoUndoState` single slot (5s, injectable) and AppState coordinator with editor sync (C12, C15, C16). Unit: `TodoUndoTests`.
- [x] **Checkpoint A:** unit suite green, build OK.
- [x] **T4** `TodoAddButton` (`circle.badge.plus`) and `TodoCheckCircle`; tiles (circle always visible on to-dos) and multi-select bar (C1, C3, C6, C7, C17). UI.
- [x] **T5** Leading row circle outside the drag gesture; context menu "Complete"; VO "Complete" action; Reduce Motion removal (C5, C10, C11, C19). UI + manual Reduce Motion check.
- [x] **T6** "Completed · Undo" bar in All Notes plus hidden ⌘Z shortcut (C12, C13, C15, C16, C17). UI.
- [x] **T7** ⌘Return ticks the focused To-Do row; Return/Space unchanged (C9). UI.
- [ ] **Checkpoint B:** unit + TodoList/Search UI green via watchdog workflow; short manual scratch-store run.
- [x] **T8** Editor footer: two states plus footer "Completed · Undo"; `editorTodoButton` (C8, C14, C6). UI + unit.
- [x] **T9** Relaunch/persistence tests, legacy pinned store, no-pin sweep, full suite (C4, C20, C21, C1). Tile actions reachable by VoiceOver without hover (C10). Open: `testDraggingARowReordersAndPersists` still fails (as on `main`); the CGEvent rewrite is blocked because the UI-test runner may not post events.
- [x] **T10** CHANGELOG `## Unreleased` entry and README feature line.
- [ ] **Final checkpoint:** full suite green; every criterion mapped and checked.
