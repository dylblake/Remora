//
//  NotesState.swift
//  Remora
//

import Foundation
import Observation

/// One `#tag` across the whole store, with how many notes carry it.
nonisolated struct TagSummary: Hashable, Sendable, Identifiable {
    /// Lowercased, without the leading `#`.
    let name: String
    let count: Int
    var id: String { name }
}

/// What a tick took off the To-Do list, so Undo can put it back. Each
/// entry is a note's index in `todoOrder` just before it was removed.
nonisolated struct TodoCompletion: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        let noteID: UUID
        let index: Int
    }
    /// Ascending by index.
    let entries: [Entry]
    var noteIDs: [UUID] { entries.map(\.noteID) }
}

@MainActor
@Observable
final class NotesState {
    private(set) var notes: [ContextNote] = [] {
        didSet {
            _sortedNotes = notes.sorted { $0.updatedAt > $1.updatedAt }
            _notesByContextID = Dictionary(uniqueKeysWithValues: notes.map { ($0.context.id, $0) })
            allTags = Self.aggregateTags(notes)
            todoOrder = Self.reconciledTodoOrder(todoOrder, notes: notes)
            recomputeFilteredNotes()
        }
    }
    /// IDs of the pinned notes in the user's manual To-Do order. Kept in
    /// step with `notes`: unpinned and deleted notes drop out, newly
    /// pinned ones join at the end.
    private(set) var todoOrder: [UUID] = []
    /// How many notes are on the To-Do list (pinned), whatever the search.
    var todoCount: Int { todoOrder.count }
    private var _sortedNotes: [ContextNote] = []
    private var _notesByContextID: [String: ContextNote] = [:]
    /// Every tag in the store, most-used first, for the search suggestions.
    private(set) var allTags: [TagSummary] = []
    private(set) var filteredNotes: [ContextNote] = []
    private(set) var noteSections: [NoteSection] = []
    private(set) var recentNotes: [ContextNote] = []
    var searchText = "" {
        didSet { if searchText != oldValue { scheduleSearchRecompute() } }
    }
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    var selectedNoteIDs: Set<UUID> = []
    var allNotesScrollResetID = UUID()
    /// Row or tile highlighted by keyboard navigation in All Notes
    /// (distinct from the checkbox multi-selection).
    var keyboardFocus: ListFocus?

    /// Notes ever created, for the free-trial gate. Monotonic: deleting
    /// notes doesn't refund trial slots.
    private(set) var trialNotesCreated: Int

    @ObservationIgnored private let store: NoteStore

    private static let trialNotesCreatedKey = "trialNotesCreated"
    /// A scratch store (tests, UI-test launches) still reads the count,
    /// so a launch argument can set it, but never writes it: test notes
    /// must not move the real trial counter.
    @ObservationIgnored private let persistsTrialCount: Bool

    init(store: NoteStore) {
        self.store = store
        let loaded = store.loadNotes()

        // Seed with the on-disk note count so the counter survives fresh
        // preference files when notes already exist.
        persistsTrialCount = !store.usesScratchDirectory
        let storedCount = UserDefaults.standard.integer(forKey: Self.trialNotesCreatedKey)
        let seededCount = max(storedCount, loaded.count)
        trialNotesCreated = seededCount

        // Assign without triggering didSet (properties aren't initialized yet
        // during init, so we set the backing stores directly).
        notes = loaded
        _sortedNotes = loaded.sorted { $0.updatedAt > $1.updatedAt }
        _notesByContextID = Dictionary(uniqueKeysWithValues: loaded.map { ($0.context.id, $0) })
        allTags = Self.aggregateTags(loaded)
        todoOrder = Self.reconciledTodoOrder(store.loadedTodoOrder, notes: loaded)
        filteredNotes = _sortedNotes
        noteSections = NoteSectionBuilder.build(from: _sortedNotes, todoOrder: todoOrder)
        recentNotes = Array(_sortedNotes.prefix(5))

        if persistsTrialCount && seededCount != storedCount {
            UserDefaults.standard.set(seededCount, forKey: Self.trialNotesCreatedKey)
        }
    }

    func note(for context: NoteContext) -> ContextNote? {
        _notesByContextID[context.id]
    }

    func upsert(_ note: ContextNote) {
        // A note ID we've never seen is a creation (context rewrites and
        // edits reuse the existing ID) — count it toward the trial.
        let isNewNote = !notes.contains { $0.id == note.id }

        var updated = notes.filter { $0.context.id != note.context.id }
        updated.append(note)
        notes = updated
        save()

        if isNewNote {
            trialNotesCreated += 1
            if persistsTrialCount {
                UserDefaults.standard.set(trialNotesCreated, forKey: Self.trialNotesCreatedKey)
            }
        }
    }

    /// Told which notes were just deleted, so the open drawer can let go
    /// of one of them instead of saving it back.
    @ObservationIgnored var onNotesDeleted: ([ContextNote]) -> Void = { _ in }

    func delete(_ note: ContextNote) {
        notes.removeAll { $0.id == note.id }
        save()
        onNotesDeleted([note])
    }

    func toggleSelection(_ noteID: UUID) {
        if selectedNoteIDs.contains(noteID) {
            selectedNoteIDs.remove(noteID)
        } else {
            selectedNoteIDs.insert(noteID)
        }
    }

    func clearSelection() {
        selectedNoteIDs.removeAll()
    }

    func deleteSelectedNotes() {
        guard !selectedNoteIDs.isEmpty else { return }
        let toDelete = selectedNoteIDs
        let deleted = notes.filter { toDelete.contains($0.id) }
        notes.removeAll { toDelete.contains($0.id) }
        save()
        selectedNoteIDs.removeAll()
        onNotesDeleted(deleted)
    }

    /// Puts notes on the To-Do list, at the end. `updatedAt` is left
    /// alone so their tiles keep their place in the grid.
    func addToTodo(_ ids: Set<UUID>) {
        guard notes.contains(where: { ids.contains($0.id) && !$0.isPinned }) else { return }
        notes = notes.map { note in
            guard ids.contains(note.id), !note.isPinned else { return note }
            return note.copying(isPinned: true)
        }
        save()
    }

    /// Ticks notes off the To-Do list, keeping `updatedAt`. Returns where
    /// each one sat, for Undo, or nil when none of them was on the list.
    @discardableResult
    func completeTodos(_ ids: [UUID]) -> TodoCompletion? {
        let entries = todoOrder.enumerated()
            .filter { ids.contains($0.element) }
            .map { TodoCompletion.Entry(noteID: $0.element, index: $0.offset) }
        guard !entries.isEmpty else { return nil }

        let completed = Set(entries.map(\.noteID))
        notes = notes.map { completed.contains($0.id) ? $0.copying(isPinned: false) : $0 }
        save()
        return TodoCompletion(entries: entries)
    }

    /// Undoes a tick: the notes go back on To-Do at the indexes they had.
    /// A note deleted since is skipped.
    func restore(_ completion: TodoCompletion) {
        let present = Set(notes.map(\.id))
        // A skipped note's slot closes up: the ones after it in the batch
        // move down by one, so they keep their places among the others.
        var skipped = 0
        let entries = completion.entries.sorted { $0.index < $1.index }.compactMap { entry -> TodoCompletion.Entry? in
            guard present.contains(entry.noteID) else {
                skipped += 1
                return nil
            }
            return TodoCompletion.Entry(noteID: entry.noteID, index: entry.index - skipped)
        }
        guard !entries.isEmpty else { return }

        let restored = Set(entries.map(\.noteID))
        // didSet appends the re-flagged notes at the end; the order is
        // then rewritten with each one back in its slot.
        notes = notes.map { restored.contains($0.id) ? $0.copying(isPinned: true) : $0 }
        todoOrder = Self.restoringOrder(todoOrder.filter { !restored.contains($0) }, inserting: entries)
        noteSections = NoteSectionBuilder.build(from: filteredNotes, todoOrder: todoOrder, includesTodo: searchText.isEmpty)
        save()
    }

    /// Applies a drag in the To-Do list. `visibleOrder` is the new order
    /// of the rows on screen; while a search hides some pinned notes, the
    /// visible ones trade places among the slots they already held.
    func reorderTodo(visibleOrder: [UUID]) {
        let moving = Set(visibleOrder)
        guard moving.count == visibleOrder.count, moving.isSubset(of: todoOrder) else { return }

        var replacements = visibleOrder.makeIterator()
        let reordered = todoOrder.map { moving.contains($0) ? (replacements.next() ?? $0) : $0 }
        guard reordered != todoOrder else { return }

        todoOrder = reordered
        noteSections = NoteSectionBuilder.build(from: filteredNotes, todoOrder: todoOrder, includesTodo: searchText.isEmpty)
        save()
    }

    func flush() {
        store.flush()
    }

    private func save() {
        store.save(notes: notes, todoOrder: todoOrder)
    }

    /// Inserts each entry at its recorded index, lowest first, so a batch
    /// lands back in its previous order. Indexes past the end clamp to it.
    nonisolated static func restoringOrder(_ current: [UUID], inserting entries: [TodoCompletion.Entry]) -> [UUID] {
        let inserted = Set(entries.map(\.noteID))
        var order = current.filter { !inserted.contains($0) }
        for entry in entries.sorted(by: { $0.index < $1.index }) {
            order.insert(entry.noteID, at: min(max(entry.index, 0), order.count))
        }
        return order
    }

    /// Drops IDs that are no longer pinned and appends newly pinned notes
    /// (most recently updated first among themselves).
    nonisolated static func reconciledTodoOrder(_ order: [UUID], notes: [ContextNote]) -> [UUID] {
        let pinned = notes.filter(\.isPinned)
        let pinnedIDs = Set(pinned.map(\.id))
        var seen = Set<UUID>()
        let kept = order.filter { pinnedIDs.contains($0) && seen.insert($0).inserted }
        let added = pinned
            .filter { !seen.contains($0.id) }
            .sorted { $0.updatedAt > $1.updatedAt }
            .map(\.id)
        return kept + added
    }

    private func recomputeFilteredNotes() {
        // Note mutations recompute synchronously so deletes/pins reflect
        // immediately; a pending search recompute would apply stale data.
        searchTask?.cancel()
        recentNotes = Array(_sortedNotes.prefix(5))
        filteredNotes = Self.filter(notes: _sortedNotes, query: searchText)
        noteSections = NoteSectionBuilder.build(from: filteredNotes, todoOrder: todoOrder, includesTodo: searchText.isEmpty)
    }

    /// Typing path: debounced, with matching and section building off the
    /// main thread — full-body substring search over every note is too
    /// heavy to run per keystroke at large note counts.
    private func scheduleSearchRecompute() {
        searchTask?.cancel()
        let query = searchText
        let source = _sortedNotes
        let order = todoOrder

        guard !query.isEmpty else {
            filteredNotes = source
            noteSections = NoteSectionBuilder.build(from: source, todoOrder: order)
            return
        }

        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }

            let result: ([ContextNote], [NoteSection]) = await Task.detached(priority: .userInitiated) {
                let filtered = NotesState.filter(notes: source, query: query)
                return (filtered, NoteSectionBuilder.build(from: filtered, todoOrder: order, includesTodo: false))
            }.value

            guard let self, !Task.isCancelled, self.searchText == query else { return }
            self.filteredNotes = result.0
            self.noteSections = result.1
        }
    }

    /// Counts each tag once per note (a note's `tags` are already deduped),
    /// most-used first, ties alphabetical.
    nonisolated static func aggregateTags(_ notes: [ContextNote]) -> [TagSummary] {
        var counts: [String: Int] = [:]
        for note in notes {
            for tag in note.tags {
                counts[tag, default: 0] += 1
            }
        }
        return counts
            .map { TagSummary(name: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                lhs.count != rhs.count ? lhs.count > rhs.count : lhs.name < rhs.name
            }
    }

    /// Tags to offer under the search field. An empty query or a bare `#`
    /// offers everything; `#he` narrows to prefix matches first, then
    /// substring matches. A plain-text query (no `#`) is a body search,
    /// so nothing is suggested; likewise once a space follows the tag.
    nonisolated static func tagSuggestions(tags: [TagSummary], query: String) -> [TagSummary] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return tags }
        guard trimmed.hasPrefix("#") else { return [] }

        let needle = String(trimmed.dropFirst()).lowercased()
        guard !needle.contains(where: \.isWhitespace) else { return [] }
        if needle.isEmpty { return tags }

        let prefixed = tags.filter { $0.name.hasPrefix(needle) }
        let contained = tags.filter { !$0.name.hasPrefix(needle) && $0.name.contains(needle) }
        return prefixed + contained
    }

    nonisolated static func filter(notes: [ContextNote], query: String) -> [ContextNote] {
        guard !query.isEmpty else { return notes }

        if query.hasPrefix("#") {
            let tagQuery = String(query.dropFirst()).trimmingCharacters(in: .whitespaces).lowercased()
            if !tagQuery.isEmpty {
                return notes.filter { note in
                    note.tags.contains { $0.localizedCaseInsensitiveContains(tagQuery) }
                }
            }
        }

        return notes.filter { note in
            note.context.displayName.localizedCaseInsensitiveContains(query)
                || note.context.identifier.localizedCaseInsensitiveContains(query)
                || (note.context.secondaryLabel?.localizedCaseInsensitiveContains(query) ?? false)
                || note.body.localizedCaseInsensitiveContains(query)
                || (note.title?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }
}
