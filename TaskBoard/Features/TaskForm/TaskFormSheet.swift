//
//  TaskFormSheet.swift
//  TaskBoard
//
//  Created by Siddhant Kumar on 08/08/26.
//

import SwiftUI

/// Identity is the task id, so moving straight from one card to another rebuilds
/// the form instead of reusing the previous card's fields.
enum TaskFormMode: Identifiable {
    case create
    case edit(Task)

    var id: String {
        switch self {
        case .create: return "create"
        case .edit(let task): return task.id.uuidString
        }
    }

    var task: Task? {
        switch self {
        case .create: return nil
        case .edit(let task): return task
        }
    }
}

struct TaskFormSheet: View {
    @StateObject private var viewModel: TaskFormViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingDelete = false
    @FocusState private var isAddingSubtask: Bool

    /// Hands a task back to the board to present once this sheet has closed.
    private let onOpenTask: (Task) -> Void

    init(mode: TaskFormMode, useCases: TaskUseCases, onOpenTask: @escaping (Task) -> Void = { _ in }) {
        self.onOpenTask = onOpenTask
        _viewModel = StateObject(wrappedValue: TaskFormViewModel(task: mode.task, useCases: useCases))
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $viewModel.title)

                TextField("Description", text: $viewModel.description, axis: .vertical)
                    .lineLimit(3...6)

                if let parent = viewModel.parent {
                    parentSection(parent)
                }

                if viewModel.canOwnSubtasks {
                    subtasksSection
                }

                if viewModel.canLinkToParent {
                    linkSection
                }

                if viewModel.canArchive {
                    Section {
                        Button {
                            viewModel.archive()
                            dismiss()
                        } label: {
                            Label("Archive Task", systemImage: "archivebox")
                        }
                    } footer: {
                        Text("Moves the task off the board. Restore it from the archive to put it back in \(viewModel.archiveOriginLabel).")
                    }
                }

                if viewModel.canDelete {
                    Section {
                        Button("Delete Task", role: .destructive) {
                            isConfirmingDelete = true
                        }
                    }
                }
            }
            .confirmationDialog(
                "Delete this task?",
                isPresented: $isConfirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    viewModel.delete()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
            .navigationTitle(viewModel.isEditing ? "Edit Task" : "New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(viewModel.submitLabel) {
                        viewModel.submit()
                        dismiss()
                    }
                    .disabled(!viewModel.canSubmit)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Parent

    /// Tapping hands the parent up to the board and closes this sheet; the
    /// board presents the parent once the dismissal finishes.
    private func parentSection(_ parent: Task) -> some View {
        Section("Subtask of") {
            Button {
                onOpenTask(parent)
                dismiss()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: parent.status.symbolName)
                        .foregroundStyle(parent.status.tint)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(parent.title)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(parent.status.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .accessibilityHint("Opens the parent task")

            Button("Unlink from parent", role: .destructive) {
                viewModel.unlinkFromParent()
            }
        }
    }

    // MARK: Subtasks

    private var subtasksSection: some View {
        Section {
            // Read-only: status is shown but never changed here. A subtask is
            // an ordinary card, so it is completed by dragging it to Done on
            // the board — one place where status changes, not two.
            ForEach(viewModel.subtasks) { subtask in
                HStack(spacing: 10) {
                    Image(systemName: subtask.status.symbolName)
                        .foregroundStyle(subtask.status.tint)

                    Text(subtask.title)
                        .strikethrough(subtask.status == .done, color: .secondary)
                        .foregroundStyle(subtask.status == .done ? .secondary : .primary)
                        .lineLimit(2)

                    Spacer(minLength: 0)

                    Text(subtask.status.displayName)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button("Delete", role: .destructive) {
                        viewModel.deleteSubtask(subtask)
                    }
                }
            }

            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Color.accentColor)

                TextField("Add subtask", text: $viewModel.newSubtaskTitle)
                    .focused($isAddingSubtask)
                    .submitLabel(.done)
                    // Keeps focus so several can be added in a row.
                    .onSubmit {
                        viewModel.addSubtask()
                        isAddingSubtask = true
                    }

                if viewModel.canAddSubtask {
                    Button("Add") {
                        viewModel.addSubtask()
                        isAddingSubtask = true
                    }
                    .buttonStyle(.borderless)
                }
            }
        } header: {
            HStack {
                Text("Subtasks")
                Spacer()
                if viewModel.subtaskProgress.total > 0 {
                    Text("\(viewModel.subtaskProgress.done)/\(viewModel.subtaskProgress.total)")
                        .monospacedDigit()
                }
            }
        } footer: {
            Text("New subtasks start in To Do. Move one to Done on the board to complete it — finishing this task completes them all.")
        }
    }

    // MARK: Linking

    private var linkSection: some View {
        Section {
            NavigationLink {
                ParentPickerView(candidates: viewModel.linkCandidates) { parent in
                    viewModel.link(to: parent)
                }
            } label: {
                Label("Link to a parent task", systemImage: "link")
            }
            .disabled(viewModel.linkCandidates.isEmpty)
        } footer: {
            Text(viewModel.linkCandidates.isEmpty
                 ? "No other top-level tasks to link to yet."
                 : "Makes this task a subtask. Nesting is one level deep, so a task with subtasks of its own can't be linked.")
        }
    }
}

/// Picks the task to become the parent. The candidate list is filtered by the
/// view model, so everything shown here is a legal choice.
private struct ParentPickerView: View {
    let candidates: [Task]
    let onSelect: (Task) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(candidates) { candidate in
            Button {
                onSelect(candidate)
                dismiss()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: candidate.status.symbolName)
                        .foregroundStyle(candidate.status.tint)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(candidate.title)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(candidate.status.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Choose Parent")
        .navigationBarTitleDisplayMode(.inline)
    }
}
