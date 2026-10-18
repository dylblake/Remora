import XCTest
@testable import Remora

/// Ticking a note off To-Do and taking it back: the single undo slot, the
/// multi-select batch, and the open drawer's flag following along.
@MainActor
final class TodoUndoTests: XCTestCase {
    private final class StubTitleGenerator: TitleGenerating {
        func generateTitle(body: String, context: NoteContext) async -> String? { nil }
    }

    private func note(_ name: String, pinned: Bool, updated: TimeInterval = 0) -> ContextNote {
        ContextNote(
            id: UUID(),
            context: NoteContext(
                kind: .application,
                identifier: "com.example.\(name)",
                displayName: name,
                secondaryLabel: nil,
                navigationTarget: nil
            ),
            body: name,
            richTextData: nil,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: updated),
            isPinned: pinned,
            title: name
        )
    }

    private func makeState() throws -> (NotesState, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "TodoUndo-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (NotesState(store: NoteStore(directoryOverride: directory)), directory)
    }

    /// Notes a, b, c on To-Do in that order, and d off it.
    private func seeded(_ state: NotesState) -> [ContextNote] {
        let notes = [note("a", pinned: true), note("b", pinned: true), note("c", pinned: true), note("d", pinned: false)]
        notes.forEach(state.upsert)
        return notes
    }

    private func todoTitles(_ state: NotesState) -> [String] {
        state.todoOrder.compactMap { id in state.notes.first { $0.id == id }?.title }
    }

    private func makeEditor(_ state: NotesState) -> EditorState {
        EditorState(
            notesState: state,
            richTextController: RichTextEditorController(),
            contextResolver: ContextResolver(),
            browserPermissions: BrowserPermissionsState(browserURLProvider: BrowserURLProvider()),
            titleGenerator: StubTitleGenerator(),
            isAutoTitleEnabled: { false }
        )
    }

    /// Opens a stored note in the drawer as the editor saved it (with its
    /// rich text), so an untouched drawer has nothing unsaved.
    private func open(_ note: ContextNote, in editor: EditorState, state: NotesState) -> ContextNote {
        let saved = ContextNote(
            id: note.id,
            context: note.context,
            body: note.body,
            richTextData: editor.archivedRichText(from: NSAttributedString(string: note.body)),
            createdAt: note.createdAt,
            updatedAt: note.updatedAt,
            isPinned: note.isPinned,
            title: note.title
        )
        state.upsert(saved)
        editor.activeContext = saved.context
        editor.loadEditorState(for: saved)
        return saved
    }

    // MARK: TodoUndoState

    func testPendingUndoClearsItselfAfterItsLifetime() async throws {
        let undo = TodoUndoState(lifetime: .milliseconds(100))
        undo.register(TodoCompletion(entries: [.init(noteID: UUID(), index: 0)]), origin: .allNotes)
        XCTAssertNotNil(undo.pending)

        try await Task.sleep(for: .milliseconds(400))
        XCTAssertNil(undo.pending)
        XCTAssertNil(undo.take())
    }

    func testTakeReturnsTheCompletionAndClearsTheSlot() {
        let undo = TodoUndoState()
        let completion = TodoCompletion(entries: [.init(noteID: UUID(), index: 2)])
        undo.register(completion, origin: .editor)
        XCTAssertEqual(undo.pending?.origin, .editor)

        XCTAssertEqual(undo.take(), completion)
        XCTAssertNil(undo.pending)
        XCTAssertNil(undo.take())
    }

    /// A second tick replaces the first and restarts the clock: the first
    /// one's timer must not clear the second.
    func testASecondCompletionReplacesTheFirstAndRestartsTheTimer() async throws {
        let undo = TodoUndoState(lifetime: .milliseconds(300))
        let first = TodoCompletion(entries: [.init(noteID: UUID(), index: 0)])
        let second = TodoCompletion(entries: [.init(noteID: UUID(), index: 1)])

        undo.register(first, origin: .allNotes)
        try await Task.sleep(for: .milliseconds(200))
        undo.register(second, origin: .allNotes)
        try await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(undo.pending?.completion, second, "the first timer cleared the replacement")
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertNil(undo.pending)
    }

    /// Each place shows only its own ticks' bar: a footer tick's undo
    /// isn't offered in All Notes, and an All Notes tick's isn't in the
    /// footer (so ⌘Z in All Notes only takes back what its bar shows).
    func testEachPlaceSeesOnlyItsOwnTicksUndo() {
        let undo = TodoUndoState()
        undo.register(TodoCompletion(entries: [.init(noteID: UUID(), index: 0)]), origin: .editor)
        XCTAssertNotNil(undo.pending(from: .editor))
        XCTAssertNil(undo.pending(from: .allNotes))

        undo.register(TodoCompletion(entries: [.init(noteID: UUID(), index: 1)]), origin: .allNotes)
        XCTAssertNotNil(undo.pending(from: .allNotes))
        XCTAssertNil(undo.pending(from: .editor), "the newer tick replaced the footer's")
    }

    func testTheBarSaysCompletedAndCountsABatch() {
        let one = TodoCompletion(entries: [.init(noteID: UUID(), index: 0)])
        let three = TodoCompletion(entries: (0..<3).map { .init(noteID: UUID(), index: $0) })
        XCTAssertEqual(TodoUndoState.barTitle(for: one), "Completed")
        XCTAssertEqual(TodoUndoState.barTitle(for: three), "Completed 3")
    }

    func testUndoAfterTwoTicksRestoresOnlyTheSecond() throws {
        let (state, directory) = try makeState()
        defer { try? FileManager.default.removeItem(at: directory) }
        let notes = seeded(state)
        let undo = TodoUndoState()

        undo.register(try XCTUnwrap(state.completeTodos([notes[0].id])), origin: .allNotes)
        undo.register(try XCTUnwrap(state.completeTodos([notes[2].id])), origin: .allNotes)
        state.restore(try XCTUnwrap(undo.take()))

        XCTAssertEqual(todoTitles(state), ["b", "c"])
        XCTAssertEqual(state.note(for: notes[0].context)?.isPinned, false)
    }

    /// Once the bar has gone, Undo does nothing, and adding the note
    /// again puts it at the bottom like any other.
    func testAfterExpiryUndoDoesNothingAndAddingAgainAppends() async throws {
        let (state, directory) = try makeState()
        defer { try? FileManager.default.removeItem(at: directory) }
        let notes = seeded(state)
        let undo = TodoUndoState(lifetime: .milliseconds(100))

        undo.register(try XCTUnwrap(state.completeTodos([notes[0].id])), origin: .allNotes)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertNil(undo.take())
        XCTAssertEqual(todoTitles(state), ["b", "c"])

        state.addToTodo([notes[0].id])
        XCTAssertEqual(todoTitles(state), ["b", "c", "a"])
    }

    // MARK: Multi-select

    func testAnAllToDoSelectionCompletesAsOneBatch() throws {
        let (state, directory) = try makeState()
        defer { try? FileManager.default.removeItem(at: directory) }
        let notes = seeded(state)

        state.selectedNoteIDs = [notes[2].id, notes[0].id]
        let completion = try XCTUnwrap(state.toggleTodoForSelectedNotes())

        XCTAssertEqual(Set(completion.noteIDs), [notes[0].id, notes[2].id])
        XCTAssertEqual(todoTitles(state), ["b"])
        XCTAssertTrue(state.selectedNoteIDs.isEmpty)

        state.restore(completion)
        XCTAssertEqual(todoTitles(state), ["a", "b", "c"])
    }

    func testAMixedSelectionAddsTheRest() throws {
        let (state, directory) = try makeState()
        defer { try? FileManager.default.removeItem(at: directory) }
        let notes = seeded(state)

        state.selectedNoteIDs = [notes[1].id, notes[3].id]
        XCTAssertNil(state.toggleTodoForSelectedNotes())

        XCTAssertEqual(todoTitles(state), ["a", "b", "c", "d"])
        XCTAssertTrue(state.selectedNoteIDs.isEmpty)
    }

    /// The bulk bar names what its button will do: tick when every
    /// selected note is on To-Do, add otherwise.
    func testTheBulkButtonCompletesOnlyWhenEverySelectedNoteIsOnToDo() throws {
        let (state, directory) = try makeState()
        defer { try? FileManager.default.removeItem(at: directory) }
        let notes = seeded(state)

        XCTAssertFalse(state.selectionIsAllOnTodo, "an empty selection has nothing to tick")
        state.selectedNoteIDs = [notes[0].id, notes[2].id]
        XCTAssertTrue(state.selectionIsAllOnTodo)
        state.selectedNoteIDs = [notes[0].id, notes[3].id]
        XCTAssertFalse(state.selectionIsAllOnTodo)
    }

    func testAnEmptySelectionDoesNothing() throws {
        let (state, directory) = try makeState()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = seeded(state)

        XCTAssertNil(state.toggleTodoForSelectedNotes())
        XCTAssertEqual(todoTitles(state), ["a", "b", "c"])
    }

    // MARK: Editor sync

    /// A tick or undo from All Notes while the note is open in the drawer
    /// must reach the drawer's flag, or closing it writes the old one back.
    func testTheOpenDrawerFollowsCompleteAndRestore() throws {
        let (state, directory) = try makeState()
        defer { try? FileManager.default.removeItem(at: directory) }
        let notes = seeded(state)
        let editor = makeEditor(state)
        editor.activeContext = notes[1].context
        editor.loadEditorState(for: notes[1])
        XCTAssertTrue(editor.isActiveNotePinned)

        let completion = try XCTUnwrap(state.completeTodos([notes[1].id]))
        editor.syncActiveNoteTodoFlag()
        XCTAssertFalse(editor.isActiveNotePinned)

        state.restore(completion)
        editor.syncActiveNoteTodoFlag()
        XCTAssertTrue(editor.isActiveNotePinned)

        // Another note's change leaves the drawer alone.
        state.addToTodo([notes[3].id])
        editor.syncActiveNoteTodoFlag()
        XCTAssertTrue(editor.isActiveNotePinned)
    }

    // MARK: Editor footer

    /// A footer tick with nothing typed changes only the flag: the tile
    /// keeps its date and place in the grid, and Undo knows the index.
    func testAFooterTickWithoutTypingKeepsTheDate() throws {
        let (state, directory) = try makeState()
        defer { try? FileManager.default.removeItem(at: directory) }
        let notes = seeded(state)
        let editor = makeEditor(state)
        let b = open(notes[1], in: editor, state: state)

        XCTAssertFalse(editor.hasUnpersistedChanges())
        let stored = try XCTUnwrap(editor.storedActiveNoteSavingTyping())
        let completion = try XCTUnwrap(state.completeTodos([stored.id]))

        XCTAssertEqual(completion.entries.map { $0.index }, [1])
        XCTAssertEqual(state.note(for: b.context)?.updatedAt, b.updatedAt)
        XCTAssertEqual(state.note(for: b.context)?.isPinned, false)
    }

    /// With unsaved typing the text is saved first (a real edit, so it
    /// gets a new date) and the note is still ticked from where it sat.
    func testAFooterTickSavesUnsavedTypingFirst() throws {
        let (state, directory) = try makeState()
        defer { try? FileManager.default.removeItem(at: directory) }
        let notes = seeded(state)
        let editor = makeEditor(state)
        let b = open(notes[1], in: editor, state: state)
        editor.editorAttributedText = NSAttributedString(string: "b and more")

        XCTAssertTrue(editor.hasUnpersistedChanges())
        let stored = try XCTUnwrap(editor.storedActiveNoteSavingTyping())
        XCTAssertEqual(stored.body, "b and more")
        XCTAssertGreaterThan(stored.updatedAt, b.updatedAt)
        XCTAssertTrue(stored.isPinned)

        let completion = try XCTUnwrap(state.completeTodos([stored.id]))
        XCTAssertEqual(completion.entries.map { $0.index }, [1])
    }

    /// The footer's tick lands after its checkmark: it only goes ahead
    /// while the drawer still holds the note the circle was clicked on.
    func testAFooterTickOnlyLandsOnTheNoteItWasClickedOn() throws {
        let (state, directory) = try makeState()
        defer { try? FileManager.default.removeItem(at: directory) }
        let notes = seeded(state)
        let editor = makeEditor(state)
        let b = open(notes[1], in: editor, state: state)
        XCTAssertTrue(editor.isShowingStoredNote(b.id))

        // The drawer moves to Charlie during the checkmark.
        let c = open(notes[2], in: editor, state: state)
        XCTAssertFalse(editor.isShowingStoredNote(b.id))
        XCTAssertTrue(editor.isShowingStoredNote(c.id))
        XCTAssertFalse(editor.isShowingStoredNote(nil), "Charlie is stored")

        // An empty new drawer is the nil note.
        let fresh = note("fresh", pinned: false)
        editor.activeContext = fresh.context
        editor.loadEditorState(for: fresh.context)
        XCTAssertTrue(editor.isShowingStoredNote(nil))
        XCTAssertFalse(editor.isShowingStoredNote(c.id))
    }

    // MARK: Closing the drawer

    /// Opening a note and closing it untouched keeps its date, so its
    /// tile doesn't jump to the top of the grid.
    func testClosingAnUntouchedNoteKeepsItsDate() throws {
        let (state, directory) = try makeState()
        defer { try? FileManager.default.removeItem(at: directory) }
        let notes = seeded(state)
        let editor = makeEditor(state)
        let b = open(notes[1], in: editor, state: state)

        XCTAssertFalse(editor.persistCurrentEditorContentIfChanged())
        XCTAssertEqual(state.note(for: b.context)?.updatedAt, b.updatedAt)
    }

    /// A footer tick then Escape: the tick stays and the tile keeps its
    /// place (C6).
    func testClosingAfterAFooterTickKeepsTheTickAndTheDate() throws {
        let (state, directory) = try makeState()
        defer { try? FileManager.default.removeItem(at: directory) }
        let notes = seeded(state)
        let editor = makeEditor(state)
        let b = open(notes[1], in: editor, state: state)

        let stored = try XCTUnwrap(editor.storedActiveNoteSavingTyping())
        XCTAssertNotNil(state.completeTodos([stored.id]))
        editor.syncActiveNoteTodoFlag()
        editor.persistCurrentEditorContentIfChanged()

        let after = try XCTUnwrap(state.note(for: b.context))
        XCTAssertFalse(after.isPinned)
        XCTAssertEqual(after.updatedAt, b.updatedAt)
    }

    /// Typing is a real edit: closing saves it with a new date.
    func testClosingAfterTypingSaves() throws {
        let (state, directory) = try makeState()
        defer { try? FileManager.default.removeItem(at: directory) }
        let notes = seeded(state)
        let editor = makeEditor(state)
        let b = open(notes[1], in: editor, state: state)
        editor.editorAttributedText = NSAttributedString(string: "b, edited")

        XCTAssertTrue(editor.persistCurrentEditorContentIfChanged())
        let after = try XCTUnwrap(state.note(for: b.context))
        XCTAssertEqual(after.body, "b, edited")
        XCTAssertGreaterThan(after.updatedAt, b.updatedAt)
    }

    /// Emptying a note and closing still deletes it.
    func testClosingAnEmptiedNoteDeletesIt() throws {
        let (state, directory) = try makeState()
        defer { try? FileManager.default.removeItem(at: directory) }
        let notes = seeded(state)
        let editor = makeEditor(state)
        let b = open(notes[1], in: editor, state: state)
        editor.editorAttributedText = NSAttributedString(string: "  ")

        editor.persistCurrentEditorContentIfChanged()
        XCTAssertNil(state.note(for: b.context))
    }

    /// A new drawer put on To-Do before anything was stored is saved on
    /// close, on To-Do, at the bottom of the list.
    func testClosingANewDrawerAddedToToDoAppendsIt() throws {
        let (state, directory) = try makeState()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = seeded(state)
        let editor = makeEditor(state)
        let fresh = note("fresh", pinned: false)
        editor.activeContext = fresh.context
        editor.loadEditorState(for: fresh.context)
        editor.isActiveNotePinned = true
        editor.editorAttributedText = NSAttributedString(string: "fresh body")

        XCTAssertTrue(editor.persistCurrentEditorContentIfChanged())
        let stored = try XCTUnwrap(state.note(for: fresh.context))
        XCTAssertTrue(stored.isPinned)
        XCTAssertEqual(state.todoOrder.last, stored.id)
    }

    /// An empty new drawer has nothing stored: there's nothing to tick or
    /// restore, and nothing gets created.
    func testAnEmptyNewDrawerHasNoStoredNote() throws {
        let (state, directory) = try makeState()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = seeded(state)
        let editor = makeEditor(state)
        let fresh = note("fresh", pinned: false)
        editor.activeContext = fresh.context
        editor.loadEditorState(for: fresh.context)

        XCTAssertNil(editor.storedActiveNoteSavingTyping())
        XCTAssertEqual(state.notes.count, 4)
    }
}
