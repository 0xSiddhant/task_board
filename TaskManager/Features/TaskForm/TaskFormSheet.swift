//
//  TaskFormSheet.swift
//  TaskManager
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

    init(mode: TaskFormMode, useCases: TaskUseCases) {
        _viewModel = StateObject(wrappedValue: TaskFormViewModel(task: mode.task, useCases: useCases))
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $viewModel.title)

                TextField("Description", text: $viewModel.description, axis: .vertical)
                    .lineLimit(3...6)
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
}
