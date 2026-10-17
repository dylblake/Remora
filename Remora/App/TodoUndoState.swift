//
//  TodoUndoState.swift
//  Remora
//

import Foundation
import Observation

/// Where a tick came from, so the right "Completed · Undo" bar shows.
enum TodoCompletionOrigin: Equatable {
    case allNotes
    case editor
}

/// The single undo slot behind "Completed · Undo". A tick registers its
/// completion here; it clears itself after `lifetime`, and a newer tick
/// replaces it (restarting the clock), so Undo only ever takes back the
/// most recent tick or batch.
@MainActor
@Observable
final class TodoUndoState {
    struct Pending: Equatable {
        let completion: TodoCompletion
        let origin: TodoCompletionOrigin
        /// Tells this registration apart from a later one of the same notes.
        let token: UUID
    }

    private(set) var pending: Pending?

    @ObservationIgnored private let lifetime: Duration
    @ObservationIgnored private var expiryTask: Task<Void, Never>?

    init(lifetime: Duration = .seconds(5)) {
        self.lifetime = lifetime
    }

    func register(_ completion: TodoCompletion, origin: TodoCompletionOrigin) {
        let token = UUID()
        pending = Pending(completion: completion, origin: origin, token: token)

        expiryTask?.cancel()
        expiryTask = Task { [weak self, lifetime] in
            try? await Task.sleep(for: lifetime)
            guard !Task.isCancelled, let self, self.pending?.token == token else { return }
            self.pending = nil
        }
    }

    /// The pending completion, if any, and an empty slot afterwards.
    func take() -> TodoCompletion? {
        expiryTask?.cancel()
        expiryTask = nil
        defer { pending = nil }
        return pending?.completion
    }
}
