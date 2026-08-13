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

    private let task: Task?
    private let useCases: TaskUseCases

    init(task: Task?, useCases: TaskUseCases) {
        self.task = task
        self.useCases = useCases
        title = task?.title ?? ""
        description = task?.description ?? ""
    }

    var isEditing: Bool { task != nil }

    var canDelete: Bool { task != nil }

    /// Nothing to archive until the task exists, so the button is absent while
    /// creating one — and absent in Done, which is a resting place of its own.
    var canArchive: Bool {
        guard let task else { return false }
        return task.status != .done
    }

    /// Names the column a restore would return the task to.
    var archiveOriginLabel: String { task?.status.displayName ?? "its column" }

    var submitLabel: String { isEditing ? "Save" : "Create" }

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
}
