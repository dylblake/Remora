import XCTest
@testable import Remora

/// The To-Do list: pinned notes in an order the user drags them into,
/// stored alongside the notes.
@MainActor
final class TodoOrderTests: XCTestCase {
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
            .appending(path: "TodoOrder-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (NotesState(store: NoteStore(directoryOverride: directory)), directory)
    }

    private func todoTitles(_ state: NotesState) -> [String] {
        state.noteSections
            .first { $0.id == NoteSectionBuilder.todoSectionID }?
            .notes.compactMap(\.title) ?? []
    }

    // MARK: reconciledTodoOrder

    func testReconcileDropsUnpinnedAndAppendsNewPinsNewestFirst() {
        let kept = note("kept", pinned: true)
        let unpinned = note("unpinned", pinned: false)
        let older = note("older", pinned: true, updated: 1)
        let newer = note("newer", pinned: true, updated: 2)
        let deleted = UUID()

        let order = NotesState.reconciledTodoOrder(
            [deleted, unpinned.id, kept.id, kept.id],
            notes: [older, kept, unpinned, newer]
        )

        XCTAssertEqual(order, [kept.id, newer.id, older.id])
    }

    // MARK: Section

    func testSectionFollowsOrderAndPutsUnorderedNotesLast() {
        let a = note("a", pinned: true, updated: 3)
        let b = note("b", pinned: true, updated: 2)
        let c = note("c", pinned: true, updated: 1)
        let tile = note("tile", pinned: false)

        let sections = NoteSectionBuilder.build(from: [a, b, c, tile], todoOrder: [c.id, a.id])
        let todo = sections.first { $0.id == NoteSectionBuilder.todoSectionID }

        XCTAssertEqual(todo?.title, "To-Do")
        XCTAssertEqual(todo?.notes.map(\.id), [c.id, a.id, b.id])
        XCTAssertEqual(sections.map(\.id), [NoteSectionBuilder.todoSectionID, NoteSectionBuilder.notesSectionID])
        // The grid holds every note, to-dos included, newest first.
        XCTAssertEqual(sections.last?.notes.map(\.id), [a.id, b.id, c.id, tile.id])
    }

    func testWithoutTheToDoListTheGridStillHoldsToDos() {
        let todo = note("todo", pinned: true, updated: 2)
        let tile = note("tile", pinned: false, updated: 1)

        let sections = NoteSectionBuilder.build(from: [todo, tile], todoOrder: [todo.id], includesTodo: false)

        XCTAssertEqual(sections.first { $0.id == NoteSectionBuilder.todoSectionID }?.notes, [])
        XCTAssertEqual(sections.last?.notes.map(\.id), [todo.id, tile.id])
    }

    /// A to-do shows as a row and as a tile: two keyboard stops, rows
    /// first, none repeated.
    func testFocusOrderListsRowsThenTilesWithoutCollisions() {
        let a = note("a", pinned: true, updated: 2)
        let b = note("b", pinned: false, updated: 1)
        let sections = NoteSectionBuilder.build(from: [a, b], todoOrder: [a.id])

        let stops = NoteSectionBuilder.focusOrder(sections)

        XCTAssertEqual(stops, [
            ListFocus(sectionID: NoteSectionBuilder.todoSectionID, noteID: a.id),
            ListFocus(sectionID: NoteSectionBuilder.notesSectionID, noteID: a.id),
            ListFocus(sectionID: NoteSectionBuilder.notesSectionID, noteID: b.id)
        ])
        XCTAssertEqual(Set(stops).count, stops.count)
    }

    /// Ticking the focused row hands focus to the next row, then the
    /// previous one, then the first tile.
    func testFocusAfterTickingARowMovesToTheNextRowThenThePreviousThenTheFirstTile() {
        let a = note("a", pinned: true, updated: 1)
        let b = note("b", pinned: true, updated: 2)
        let c = note("c", pinned: false, updated: 3)
        let row = { (n: ContextNote) in ListFocus(sectionID: NoteSectionBuilder.todoSectionID, noteID: n.id) }
        let tile = { (n: ContextNote) in ListFocus(sectionID: NoteSectionBuilder.notesSectionID, noteID: n.id) }
        let sections = NoteSectionBuilder.build(from: [c, b, a], todoOrder: [a.id, b.id])

        XCTAssertEqual(NoteSectionBuilder.focusAfterTicking(row(a), in: sections), row(b))
        XCTAssertEqual(NoteSectionBuilder.focusAfterTicking(row(b), in: sections), row(a))

        let lone = NoteSectionBuilder.build(from: [c, a], todoOrder: [a.id])
        XCTAssertEqual(NoteSectionBuilder.focusAfterTicking(row(a), in: lone), tile(c))

        let nothingElse = NoteSectionBuilder.build(from: [a], todoOrder: [a.id])
        XCTAssertEqual(NoteSectionBuilder.focusAfterTicking(row(a), in: nothingElse), tile(a),
                       "the ticked note's own tile stays, so it takes focus")
    }

    /// ⌘Return ticks a focused row, and nothing else: not a tile, not
    /// while the search field has the caret.
    func testCommandReturnTicksOnlyAFocusedRow() {
        let id = UUID()
        let row = ListFocus(sectionID: NoteSectionBuilder.todoSectionID, noteID: id)
        let tile = ListFocus(sectionID: NoteSectionBuilder.notesSectionID, noteID: id)

        XCTAssertEqual(NoteSectionBuilder.rowToTick(focus: row, isSearchFieldFocused: false), id)
        XCTAssertNil(NoteSectionBuilder.rowToTick(focus: row, isSearchFieldFocused: true))
        XCTAssertNil(NoteSectionBuilder.rowToTick(focus: tile, isSearchFieldFocused: false))
        XCTAssertNil(NoteSectionBuilder.rowToTick(focus: nil, isSearchFieldFocused: false))
    }

    func testSearchHidesTheToDoSectionAndClearingBringsItBack() throws {
        let (state, directory) = try makeState()
        defer { try? FileManager.default.removeItem(at: directory) }

        let notes = ["alpha", "bravo", "charlie"].map { note($0, pinned: true) }
        notes.forEach(state.upsert)
        state.reorderTodo(visibleOrder: [notes[2].id, notes[0].id, notes[1].id])

        state.searchText = "bravo"
        // A note change recomputes at once with the current query.
        state.upsert(note("delta", pinned: false))
        XCTAssertEqual(todoTitles(state), [])
        XCTAssertEqual(state.noteSections.last?.notes.compactMap(\.title), ["bravo"])

        state.searchText = ""
        XCTAssertEqual(todoTitles(state), ["charlie", "alpha", "bravo"])
    }

    // MARK: NotesState

    func testAddingAppendsToTheEndAndCompletingRemoves() throws {
        let (state, directory) = try makeState()
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = note("first", pinned: true)
        let second = note("second", pinned: false)
        state.upsert(first)
        state.upsert(second)
        XCTAssertEqual(todoTitles(state), ["first"])

        state.addToTodo([second.id])
        XCTAssertEqual(todoTitles(state), ["first", "second"])
        XCTAssertEqual(state.todoCount, 2)

        let completion = state.completeTodos([first.id])
        XCTAssertEqual(completion?.entries, [TodoCompletion.Entry(noteID: first.id, index: 0)])
        XCTAssertEqual(todoTitles(state), ["second"])
        XCTAssertEqual(state.todoOrder, [second.id])
        XCTAssertEqual(state.note(for: first.context)?.isPinned, false)
    }

    /// Ticking a note from anywhere (its tile, the multi-select bar, the
    /// editor) hands keyboard focus on when its To-Do row has it, so focus
    /// never sits on a row that's gone.
    func testCompletingAFocusedRowFromAnywhereMovesFocusOn() throws {
        let (state, directory) = try makeState()
        defer { try? FileManager.default.removeItem(at: directory) }
        let a = note("a", pinned: true, updated: 1)
        let b = note("b", pinned: true, updated: 2)
        let c = note("c", pinned: true, updated: 3)
        let d = note("d", pinned: false, updated: 4)
        [a, b, c, d].forEach(state.upsert)
        state.reorderTodo(visibleOrder: [a.id, b.id, c.id])
        let row = { (n: ContextNote) in ListFocus(sectionID: NoteSectionBuilder.todoSectionID, noteID: n.id) }
        let tile = { (n: ContextNote) in ListFocus(sectionID: NoteSectionBuilder.notesSectionID, noteID: n.id) }

        state.keyboardFocus = row(b)
        state.completeTodos([b.id])
        XCTAssertEqual(state.keyboardFocus, row(c))

        // A batch skips the rows leaving with it.
        state.addToTodo([b.id])
        state.reorderTodo(visibleOrder: [a.id, b.id, c.id])
        state.keyboardFocus = row(b)
        state.completeTodos([b.id, c.id])
        XCTAssertEqual(state.keyboardFocus, row(a))

        // The last row goes: the first tile takes focus.
        state.completeTodos([a.id])
        XCTAssertEqual(state.keyboardFocus, tile(d))

        // A focused tile stays put: the tile doesn't leave.
        state.addToTodo([a.id])
        state.keyboardFocus = tile(a)
        state.completeTodos([a.id])
        XCTAssertEqual(state.keyboardFocus, tile(a))
    }

    func testCompletingNotesThatAreNotOnTheListReturnsNil() throws {
        let (state, directory) = try makeState()
        defer { try? FileManager.default.removeItem(at: directory) }

        let loose = note("loose", pinned: false)
        state.upsert(loose)

        XCTAssertNil(state.completeTodos([loose.id, UUID()]))
        XCTAssertEqual(state.todoOrder, [])
    }

    /// Adding, ticking and undoing never touch `updatedAt`, so a tile
    /// keeps its place in the newest-first grid and its date.
    func testFlagChangesKeepUpdatedAt() throws {
        let (state, directory) = try makeState()
        defer { try? FileManager.default.removeItem(at: directory) }

        let a = note("a", pinned: false, updated: 10)
        let b = note("b", pinned: true, updated: 20)
        state.upsert(a)
        state.upsert(b)

        state.addToTodo([a.id])
        let completion = try XCTUnwrap(state.completeTodos([b.id]))
        state.restore(completion)

        XCTAssertEqual(state.note(for: a.context)?.updatedAt, a.updatedAt)
        XCTAssertEqual(state.note(for: b.context)?.updatedAt, b.updatedAt)
    }

    func testCompleteThenRestoreGivesBackTheSameOrder() throws {
        let (state, directory) = try makeState()
        defer { try? FileManager.default.removeItem(at: directory) }

        let notes = ["a", "b", "c", "d", "e"].map { note($0, pinned: true) }
        notes.forEach(state.upsert)
        let before = state.todoOrder

        let single = try XCTUnwrap(state.completeTodos([notes[2].id]))
        state.restore(single)
        XCTAssertEqual(state.todoOrder, before)

        // A batch, listed out of order, comes back in its previous order.
        let batch = try XCTUnwrap(state.completeTodos([notes[3].id, notes[0].id, notes[4].id]))
        XCTAssertEqual(batch.entries.map(\.index), [0, 3, 4])
        XCTAssertEqual(todoTitles(state), ["b", "c"])
        state.restore(batch)
        XCTAssertEqual(state.todoOrder, before)
        XCTAssertEqual(todoTitles(state), ["a", "b", "c", "d", "e"])
        XCTAssertTrue(notes.allSatisfy { state.note(for: $0.context)?.isPinned == true })
    }

    func testRestoreSkipsANoteDeletedInTheMeantime() throws {
        let (state, directory) = try makeState()
        defer { try? FileManager.default.removeItem(at: directory) }

        let notes = ["a", "b", "c"].map { note($0, pinned: true) }
        notes.forEach(state.upsert)

        let completion = try XCTUnwrap(state.completeTodos([notes[0].id, notes[1].id]))
        state.delete(try XCTUnwrap(state.note(for: notes[0].context)))
        state.restore(completion)

        XCTAssertEqual(todoTitles(state), ["b", "c"])
        XCTAssertNil(state.note(for: notes[0].context))
    }

    func testRestorePersistsAcrossReload() throws {
        let (state, directory) = try makeState()
        defer { try? FileManager.default.removeItem(at: directory) }

        let notes = ["a", "b", "c"].map { note($0, pinned: true) }
        notes.forEach(state.upsert)
        state.restore(try XCTUnwrap(state.completeTodos([notes[0].id])))

        state.flush()
        let reloaded = NotesState(store: NoteStore(directoryOverride: directory))
        XCTAssertEqual(todoTitles(reloaded), ["a", "b", "c"])
    }

    // MARK: restoringOrder

    func testRestoringOrderPutsOneNoteBackAtItsIndex() {
        let (a, b, c) = (UUID(), UUID(), UUID())
        XCTAssertEqual(
            NotesState.restoringOrder([a, c], inserting: [.init(noteID: b, index: 1)]),
            [a, b, c]
        )
    }

    func testRestoringOrderPutsANonAdjacentBatchBack() {
        let ids = (0..<6).map { _ in UUID() }
        let current = [ids[1], ids[2], ids[4]]
        let entries: [TodoCompletion.Entry] = [
            .init(noteID: ids[0], index: 0),
            .init(noteID: ids[3], index: 3),
            .init(noteID: ids[5], index: 5)
        ]
        XCTAssertEqual(NotesState.restoringOrder(current, inserting: entries), ids)
    }

    func testRestoringOrderClampsAnIndexPastTheEnd() {
        let (a, b) = (UUID(), UUID())
        XCTAssertEqual(
            NotesState.restoringOrder([a], inserting: [.init(noteID: b, index: 7)]),
            [a, b]
        )
    }

    /// A note added during the undo window stays where it went; the
    /// restored note goes back to its own index.
    func testRestoringOrderWithANoteAddedInBetween() {
        let (a, b, c, added) = (UUID(), UUID(), UUID(), UUID())
        XCTAssertEqual(
            NotesState.restoringOrder([a, c, added], inserting: [.init(noteID: b, index: 1)]),
            [a, b, c, added]
        )
    }

    func testRestoringOrderDoesNotDuplicateAnIDAlreadyThere() {
        let (a, b) = (UUID(), UUID())
        XCTAssertEqual(
            NotesState.restoringOrder([a, b], inserting: [.init(noteID: b, index: 0)]),
            [b, a]
        )
    }

    /// VoiceOver's Move Up / Move Down on a row swap it with its
    /// neighbour, and the new order is stored. The first row can't move
    /// up, the last can't move down.
    func testVoiceOverMoveUpAndDownReorderAndPersist() throws {
        let (state, directory) = try makeState()
        defer { try? FileManager.default.removeItem(at: directory) }
        let notes = ["a", "b", "c"].map { note($0, pinned: true) }
        notes.forEach(state.upsert)
        state.reorderTodo(visibleOrder: notes.map(\.id))
        let visible = { state.todoOrder }

        state.moveTodo(notes[0].id, by: 1, among: visible())
        XCTAssertEqual(todoTitles(state), ["b", "a", "c"])
        state.moveTodo(notes[2].id, by: -1, among: visible())
        XCTAssertEqual(todoTitles(state), ["b", "c", "a"])

        state.moveTodo(notes[1].id, by: -1, among: visible())
        state.moveTodo(notes[0].id, by: 1, among: visible())
        XCTAssertEqual(todoTitles(state), ["b", "c", "a"], "no move past either end")

        state.flush()
        let reloaded = NotesState(store: NoteStore(directoryOverride: directory))
        XCTAssertEqual(todoTitles(reloaded), ["b", "c", "a"])
    }

    func testReorderPersistsAcrossReload() throws {
        let (state, directory) = try makeState()
        defer { try? FileManager.default.removeItem(at: directory) }

        let notes = ["a", "b", "c"].map { note($0, pinned: true) }
        notes.forEach(state.upsert)
        XCTAssertEqual(todoTitles(state), ["a", "b", "c"])

        state.reorderTodo(visibleOrder: [notes[2].id, notes[0].id, notes[1].id])
        XCTAssertEqual(todoTitles(state), ["c", "a", "b"])

        state.flush()
        let reloaded = NotesState(store: NoteStore(directoryOverride: directory))
        XCTAssertEqual(todoTitles(reloaded), ["c", "a", "b"])
    }

    /// With a search hiding some rows, the visible ones swap among the
    /// slots they already held; hidden rows keep their place.
    func testReorderingAFilteredListLeavesHiddenRowsInPlace() throws {
        let (state, directory) = try makeState()
        defer { try? FileManager.default.removeItem(at: directory) }

        let notes = ["a", "b", "c", "d"].map { note($0, pinned: true) }
        notes.forEach(state.upsert)

        state.reorderTodo(visibleOrder: [notes[3].id, notes[0].id])
        XCTAssertEqual(state.todoOrder, [notes[3].id, notes[1].id, notes[2].id, notes[0].id])
    }

    func testReorderIgnoresIDsThatAreNotOnTheList() throws {
        let (state, directory) = try makeState()
        defer { try? FileManager.default.removeItem(at: directory) }

        let notes = ["a", "b"].map { note($0, pinned: true) }
        notes.forEach(state.upsert)

        state.reorderTodo(visibleOrder: [notes[1].id, UUID()])
        XCTAssertEqual(state.todoOrder, notes.map(\.id))
    }

    func testFilesWithoutAnOrderStillLoad() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "TodoOrder-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        struct Legacy: Encodable { let version: Int; let notes: [ContextNote] }
        let notes = [note("old", pinned: true, updated: 1), note("new", pinned: true, updated: 2)]
        try encoder.encode(Legacy(version: 3, notes: notes)).write(to: directory.appending(path: "notes.json"))

        let state = NotesState(store: NoteStore(directoryOverride: directory))
        XCTAssertEqual(todoTitles(state), ["new", "old"])
        // Pinned notes from before To-Do could be ticked are also tiles.
        let grid = state.noteSections.first { $0.id == NoteSectionBuilder.notesSectionID }
        XCTAssertEqual(grid?.notes.compactMap(\.title), ["new", "old"])
    }

    /// A note ticked before quitting stays off To-Do after relaunch; the
    /// rest keep their order and every note is still there.
    func testCompletionPersistsAcrossReload() throws {
        let (state, directory) = try makeState()
        defer { try? FileManager.default.removeItem(at: directory) }

        let notes = ["a", "b", "c"].map { note($0, pinned: true) }
        notes.forEach(state.upsert)
        XCTAssertNotNil(state.completeTodos([notes[1].id]))

        state.flush()
        let reloaded = NotesState(store: NoteStore(directoryOverride: directory))
        XCTAssertEqual(todoTitles(reloaded), ["a", "c"])
        XCTAssertEqual(reloaded.notes.count, 3)
        XCTAssertEqual(reloaded.note(for: notes[1].context)?.isPinned, false)
    }
}
