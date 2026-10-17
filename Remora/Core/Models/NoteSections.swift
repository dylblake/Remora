import Foundation

struct NoteSection: Identifiable, Hashable {
    let id: String
    let title: String
    let notes: [ContextNote]
}

/// One keyboard stop in All Notes. A to-do shows twice, as a row and as
/// a tile, so a stop is the note *in a section*; it is also the scroll ID.
nonisolated struct ListFocus: Hashable, Sendable {
    let sectionID: String
    let noteID: UUID
}

/// Builds the two sections shown in All Notes: the To-Do list (pinned
/// notes, in the user's order) and every note as one grid. A pure
/// function of the (already filtered, sorted) note list, so NotesState can
/// cache the result and recompute it only when notes or the search query
/// change.
enum NoteSectionBuilder {
    /// The pinned notes' section, drawn as the To-Do list rather than tiles.
    static let todoSectionID = "todo"
    /// Every note, to-dos included, in the order given (newest first).
    static let notesSectionID = "notes"

    /// `includesTodo` is false while searching: results come from the
    /// grid alone, and the To-Do section is left empty (so not drawn).
    static func build(from notes: [ContextNote], todoOrder: [UUID] = [], includesTodo: Bool = true) -> [NoteSection] {
        [
            includesTodo
                ? todoSection(notes: notes.filter(\.isPinned), order: todoOrder)
                : NoteSection(id: todoSectionID, title: "To-Do", notes: []),
            NoteSection(id: notesSectionID, title: "Notes", notes: notes)
        ]
    }

    /// Keyboard stops in on-screen order: the rows, then every tile.
    static func focusOrder(_ sections: [NoteSection]) -> [ListFocus] {
        sections.flatMap { section in
            section.notes.map { ListFocus(sectionID: section.id, noteID: $0.id) }
        }
    }

    /// Where keyboard focus goes when the focused To-Do row is ticked:
    /// the next row, else the previous one, else the first tile. Uses the
    /// sections from before the tick.
    static func focusAfterTicking(_ row: ListFocus, in sections: [NoteSection]) -> ListFocus? {
        let rows = sections.first { $0.id == todoSectionID }?.notes ?? []
        if let index = rows.firstIndex(where: { $0.id == row.noteID }) {
            let neighbor = rows.indices.contains(index + 1) ? rows[index + 1]
                : rows.indices.contains(index - 1) ? rows[index - 1] : nil
            if let neighbor {
                return ListFocus(sectionID: todoSectionID, noteID: neighbor.id)
            }
        }
        return sections.first { $0.id == notesSectionID }?.notes.first
            .map { ListFocus(sectionID: notesSectionID, noteID: $0.id) }
    }

    /// Pinned notes in the user's manual order. A note missing from
    /// `order` sorts after the ordered ones, most recently updated first.
    private static func todoSection(notes: [ContextNote], order: [UUID]) -> NoteSection {
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let sortedNotes = notes.sorted { lhs, rhs in
            switch (rank[lhs.id], rank[rhs.id]) {
            case let (lhsRank?, rhsRank?): return lhsRank < rhsRank
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return lhs.updatedAt > rhs.updatedAt
            }
        }
        return NoteSection(id: todoSectionID, title: "To-Do", notes: sortedNotes)
    }
}
