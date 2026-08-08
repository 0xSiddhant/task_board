//
//  TaskFormViewModelTests.swift
//  TaskBoardTests
//
//  Created by Siddhant Kumar on 08/08/26.
//

import Testing
import Foundation
@testable import TaskBoard

@MainActor
struct TaskFormViewModelTests {

    private func makeRepository() -> MockTaskRepository { MockTaskRepository() }

    @Test func createModeCannotDelete() {
        let repository = makeRepository()
        let viewModel = TaskFormViewModel(task: nil, useCases: TaskUseCases(repository: repository))

        #expect(viewModel.canDelete == false)
        #expect(viewModel.submitLabel == "Create")

        // Guarded, so calling it anyway is harmless.
        viewModel.delete()
        #expect(repository.outbox.isEmpty)
    }

    @Test func editModeDeletesAndQueuesOneDeleteEntry() {
        let repository = makeRepository()
        let task = repository.createTask(title: "A", description: "")
        repository.clearOutbox()

        let viewModel = TaskFormViewModel(task: task, useCases: TaskUseCases(repository: repository))
        #expect(viewModel.canDelete)

        viewModel.delete()

        #expect(repository.fetchTasks(status: nil).isEmpty)
        #expect(repository.fetchTask(id: task.id)?.deletedAt != nil)   // soft, until the sync acks
        #expect(repository.outbox.map(\.op) == [.delete])
    }

    @Test func openingTheSheetWithoutActingLeavesNoTrace() {
        let repository = makeRepository()
        let task = repository.createTask(title: "A", description: "")
        repository.clearOutbox()

        let viewModel = TaskFormViewModel(task: task, useCases: TaskUseCases(repository: repository))
        viewModel.title = "typed but abandoned"

        #expect(repository.outbox.isEmpty)
        #expect(repository.fetchTask(id: task.id)?.title == "A")
    }
}
