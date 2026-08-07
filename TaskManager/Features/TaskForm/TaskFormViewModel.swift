//
//  TaskFormViewModel.swift
//  TaskManager
//
//  Created by Siddhant Kumar on 08/08/26.
//

import Combine
import Foundation

/// One view model for both modes. A non-nil `task` means edit — it prefills the
/// fields and routes submit to `update`; nil means create. Splitting this in two
/// would duplicate the field handling for the sake of one branch.
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

    var submitLabel: String { isEditing ? "Save" : "Create" }

    var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The only method that touches the repository — dismissing the sheet never
    /// calls it, so a cancelled edit leaves no trace in the outbox.
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
}
