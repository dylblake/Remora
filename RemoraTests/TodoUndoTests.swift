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
        let editor = EditorState(
            notesState: state,
            richTextController: RichTextEditorController(),
            contextResolver: ContextResolver(),
            browserPermissions: BrowserPermissionsState(browserURLProvider: BrowserURLProvider()),
            titleGenerator: StubTitleGenerator(),
            isAutoTitleEnabled: { false }
        )
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
}
