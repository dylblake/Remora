import SwiftUI

struct NoteSelectionCheckbox: View {
    @Environment(AppState.self) private var appState
    let noteID: UUID

    private var isSelected: Bool {
        appState.notesState.selectedNoteIDs.contains(noteID)
    }

    var body: some View {
        Button {
            appState.notesState.toggleSelection(noteID)
        } label: {
            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isSelected ? RemoraTheme.accent : RemoraTheme.secondaryText)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(isSelected ? "Deselect note" : "Select note")
    }
}

/// Puts a note at the bottom of the To-Do list.
struct TodoAddButton: View {
    @Environment(AppState.self) private var appState
    let note: ContextNote

    var body: some View {
        Button {
            appState.addToTodo([note])
        } label: {
            Image(systemName: "circle.badge.plus")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(RemoraTheme.secondaryText)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help("Add to To-Do")
        .accessibilityLabel("Add to To-Do")
    }
}

/// The empty circle on a to-do. A click shows the checkmark for a moment,
/// then ticks the note off (with "Completed · Undo"). VoiceOver's action
/// ticks straight away.
struct TodoCheckCircle: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let note: ContextNote
    /// The note's title as the caller shows it, for VoiceOver.
    let title: String
    var origin: TodoCompletionOrigin = .allNotes
    /// What ticking does, in place of the plain `completeTodo`: the row
    /// wraps it in its removal animation and moves keyboard focus.
    var complete: (() -> Void)?

    @State private var isTicking = false

    static let checkmarkDuration: Duration = .milliseconds(350)

    var body: some View {
        Button(action: tick) {
            Image(systemName: isTicking ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(isTicking ? RemoraTheme.accent : RemoraTheme.secondaryText)
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help("Complete")
        .accessibilityLabel("Complete \u{201C}\(title)\u{201D}")
        .accessibilityAction {
            guard !isTicking else { return }
            isTicking = true
            commit()
        }
    }

    /// Shows the checkmark, then commits. A second click meanwhile is
    /// ignored.
    private func tick() {
        guard !isTicking else { return }
        isTicking = true
        Task {
            try? await Task.sleep(for: Self.checkmarkDuration)
            commit()
        }
    }

    private func commit() {
        if let complete {
            complete()
        } else {
            // The row it also has in the To-Do list fades out.
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                appState.completeTodo([note.id], origin: origin)
            }
        }
    }
}

struct NoteDeleteButton: View {
    @Environment(AppState.self) private var appState
    @State private var showingConfirmation = false
    let note: ContextNote

    var body: some View {
        Button(role: .destructive) {
            showingConfirmation = true
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(RemoraTheme.secondaryText)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help("Delete")
        .accessibilityLabel("Delete note")
        .popover(isPresented: $showingConfirmation, arrowEdge: .bottom) {
            DeleteConfirmationPopover(
                onConfirm: {
                    showingConfirmation = false
                    appState.notesState.delete(note)
                },
                onCancel: {
                    showingConfirmation = false
                }
            )
        }
    }
}
