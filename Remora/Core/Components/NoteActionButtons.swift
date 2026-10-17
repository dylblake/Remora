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
    /// False hides the icon until the pointer comes by. The button stays
    /// in the accessibility tree, so VoiceOver can still reach it.
    var isRevealed = true

    var body: some View {
        Button {
            appState.addToTodo([note])
        } label: {
            Image(systemName: "circle.badge.plus")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(RemoraTheme.secondaryText)
                .opacity(isRevealed ? 1 : 0)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help("Add to To-Do")
        .accessibilityLabel("Add to To-Do")
    }
}

/// Asks a To-Do row's circle to tick, as if clicked: ⌘Return on the
/// focused row. The token tells two requests for the same note apart.
struct TodoTickRequest: Equatable {
    let noteID: UUID
    let token = UUID()
}

extension EnvironmentValues {
    /// The latest ⌘Return request; circles that answer it watch this.
    @Entry var todoTickRequest: TodoTickRequest?
}

/// The empty circle on a to-do. A click shows the checkmark for a moment,
/// then ticks the note off (with "Completed · Undo"). VoiceOver's action
/// ticks straight away.
struct TodoCheckCircle: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.todoTickRequest) private var tickRequest
    /// Nil for a drawer with nothing stored yet.
    let noteID: UUID?
    /// The note's title as the caller shows it, for VoiceOver.
    let title: String
    var origin: TodoCompletionOrigin = .allNotes
    /// True for a row's circle: ⌘Return ticks rows, not tiles.
    var answersTickRequests = false
    /// What ticking does, in place of the plain `completeTodo`: the row
    /// wraps it in its removal animation and moves keyboard focus.
    var complete: (() -> Void)?
    var iconSize: CGFloat = 15
    var hitSize: CGFloat = 26
    /// The editor footer's buttons light up under the pointer.
    var highlightsOnHover = false

    @State private var isTicking = false
    @State private var isHovered = false

    static let checkmarkDuration: Duration = .milliseconds(350)

    var body: some View {
        Button(action: tick) {
            Image(systemName: isTicking ? "checkmark.circle.fill" : "circle")
                .font(.system(size: iconSize, weight: .regular))
                .foregroundStyle(isTicking ? RemoraTheme.accent : RemoraTheme.secondaryText)
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                .frame(width: hitSize, height: hitSize)
                .background(
                    Circle()
                        .fill(highlightsOnHover && isHovered ? Color.primary.opacity(0.08) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .onHover { isHovered = $0 }
        .help("Complete")
        .accessibilityLabel("Complete \u{201C}\(title)\u{201D}")
        .accessibilityAction {
            guard !isTicking else { return }
            isTicking = true
            commit()
        }
        .onChange(of: tickRequest) { _, request in
            guard answersTickRequests, let noteID, request?.noteID == noteID else { return }
            tick()
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
        } else if let noteID {
            // The row it also has in the To-Do list fades out.
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                appState.completeTodo([noteID], origin: origin)
            }
        }
    }
}

/// "Completed · Undo" for a few seconds after a tick: floating at the
/// bottom of All Notes, or in the editor footer after a footer tick.
struct TodoUndoBar: View {
    let title: String
    var identifier = "todoUndoBar"
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Text(title)
                .font(.subheadline.weight(.medium))
            Text("·")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Button("Undo", action: onUndo)
                .buttonStyle(.borderless)
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
        .glassEffect(.regular, in: Capsule(style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}

struct NoteDeleteButton: View {
    @Environment(AppState.self) private var appState
    @State private var showingConfirmation = false
    let note: ContextNote
    /// As for `TodoAddButton`: hidden from sight, not from VoiceOver.
    var isRevealed = true

    var body: some View {
        Button(role: .destructive) {
            showingConfirmation = true
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(RemoraTheme.secondaryText)
                .opacity(isRevealed ? 1 : 0)
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
