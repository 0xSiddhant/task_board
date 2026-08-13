//
//  TaskFormViewModel.swift
//  TaskBoard
//
//  Created by Siddhant Kumar on 08/08/26.
//

import Combine
import Foundation

/// A non-nil `task` means edit and routes submit to `update`; nil means create.
@MainActor
final class TaskFormViewModel: ObservableObject {
    @Published var title: String
    @Published var description: String

    /// The task this one belongs to, and the ones belonging to it. Both are
    /// kept live off the store rather than read once at init, so the sheet
    /// stays right when a sync or a drag changes something underneath it.
    @Published private(set) var parent: Task?
    @Published private(set) var subtasks: [Task] = []
    /// Tasks this one may be linked under. Empty while the rules forbid any
    /// link at all, which is what hides the picker.
    @Published private(set) var linkCandidates: [Task] = []

    /// Text for the inline "add subtask" field.
    @Published var newSubtaskTitle = ""

    private let task: Task?
    private let useCases: TaskUseCases
    private var cancellables = Set<AnyCancellable>()

    init(task: Task?, useCases: TaskUseCases) {
        self.task = task
        self.useCases = useCases
        title = task?.title ?? ""
        description = task?.description ?? ""

        guard let task else { return }
        useCases.observeTasks()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tasks in
                self?.rebuildHierarchy(from: tasks, for: task)
            }
            .store(in: &cancellables)
    }

    private func rebuildHierarchy(from tasks: [Task], for task: Task) {
        let live = tasks.filter { $0.deletedAt == nil }
        // Re-read rather than trusting the snapshot the sheet was opened with:
        // the link may have changed since.
        let current = live.first { $0.id == task.id } ?? task

        parent = current.parentId.flatMap { id in live.first { $0.id == id } }
        subtasks = live
            .filter { $0.parentId == current.id }
            .sorted { $0.position < $1.position }

        // One level deep: a task may take a parent only while it has no
        // subtasks of its own, and only a top-level task may become one.
        // A candidate that already has subtasks is fine — it just gains another.
        linkCandidates = subtasks.isEmpty
            ? live
                .filter { $0.id != current.id && $0.parentId == nil }
                .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            : []
    }

    var isEditing: Bool { task != nil }

    var canDelete: Bool { task != nil }

    var submitLabel: String { isEditing ? "Save" : "Create" }

    /// Nothing to archive until the task exists, so the button is absent while
    /// creating one — and absent in Done, which is a resting place of its own.
    var canArchive: Bool {
        guard let task else { return false }
        return task.status != .done
    }

    /// Names the column a restore would return the task to.
    var archiveOriginLabel: String { task?.status.displayName ?? "its column" }

    var subtaskProgress: SubtaskProgress {
        SubtaskProgress(done: subtasks.filter { $0.status == .done }.count, total: subtasks.count)
    }

    var canAddSubtask: Bool {
        !newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// A task that is itself a subtask can't own subtasks, and neither can one
    /// that doesn't exist yet.
    var canOwnSubtasks: Bool { task != nil && parent == nil }

    var canLinkToParent: Bool { task != nil && parent == nil && subtasks.isEmpty }

    var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The only method that touches the repository, so a cancelled edit leaves
    /// no trace in the outbox.
    func submit() {
        guard canSubmit else { return }
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = description.trimmingCharacters(in: .whitespacesAndNewlines)

        if let task {
            _ = useCases.update(id: task.id, title: title, description: description)
        } else {
            _ = useCases.create(title: title, description: description)
        }
    }

    func delete() {
        guard let task else { return }
        useCases.delete(id: task.id)
    }

    /// Deliberately does not save pending edits first: archiving is an action on
    /// the task as it stands, and silently committing text the user never
    /// confirmed would be a surprise.
    func archive() {
        guard let task else { return }
        useCases.archive(id: task.id)
    }

    // MARK: Subtasks

    func addSubtask() {
        guard let task, canAddSubtask else { return }
        let title = newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        newSubtaskTitle = ""
        _ = useCases.create(title: title, description: "", parentId: task.id)
    }

    /// Removes the subtask outright, through the same soft-delete path the
    /// board uses — not merely an unlink.
    func deleteSubtask(_ subtask: Task) {
        useCases.delete(id: subtask.id)
    }

    func link(to parent: Task) {
        guard let task else { return }
        useCases.setParent(id: task.id, parentId: parent.id)
    }

    func unlinkFromParent() {
        guard let task else { return }
        useCases.setParent(id: task.id, parentId: nil)
    }
}
