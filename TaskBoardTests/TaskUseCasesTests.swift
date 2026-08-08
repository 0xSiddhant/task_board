//
//  TaskUseCasesTests.swift
//  TaskBoardTests
//
//  Created by Siddhant Kumar on 08/08/26.
//

import Testing
import Foundation
@testable import TaskBoard

@MainActor
struct TaskUseCasesTests {

    private func makeUseCases() -> (TaskUseCases, MockTaskRepository) {
        let repository = MockTaskRepository()
        return (TaskUseCases(repository: repository), repository)
    }

    // MARK: CRUD

    @Test func createStoresTaskAndQueuesOneCreateEntry() {
        let (useCases, repository) = makeUseCases()

        let task = useCases.create(title: "Write tests", description: "for the domain layer")

        #expect(task.title == "Write tests")
        #expect(task.description == "for the domain layer")
        #expect(task.status == .todo)
        #expect(task.syncStatus == .pending)
        #expect(task.deletedAt == nil)

        #expect(repository.fetchTasks(status: nil).count == 1)
        #expect(repository.outbox.count == 1)
        #expect(repository.outbox[0].op == .create)
        #expect(repository.outbox[0].taskId == task.id)
    }

    @Test func updateChangesOnlyTheFieldsGiven() {
        let (useCases, repository) = makeUseCases()
        let created = useCases.create(title: "original", description: "details")
        repository.clearOutbox()

        let updated = useCases.update(id: created.id, title: "renamed", description: nil)

        #expect(updated?.title == "renamed")
        #expect(updated?.description == "details")
        #expect(repository.outbox.count == 1)
        #expect(repository.outbox[0].op == .update)
        #expect(repository.outbox[0].baseUpdatedAt == created.updatedAt)
    }

    @Test func updateOfMissingTaskReturnsNil() {
        let (useCases, repository) = makeUseCases()

        #expect(useCases.update(id: UUID(), title: "x", description: nil) == nil)
        #expect(repository.outbox.isEmpty)
    }

    @Test func moveChangesStatusAndPosition() {
        let (useCases, repository) = makeUseCases()
        let a = useCases.create(title: "A", description: "")
        let b = useCases.create(title: "B", description: "")
        repository.clearOutbox()

        // Land between the two existing positions in the target column.
        let moved = useCases.move(id: b.id, to: .inProgress, afterPosition: 0, beforePosition: 1)

        #expect(moved?.status == .inProgress)
        #expect(moved?.position == 0.5)
        #expect(repository.fetchTasks(status: .todo).map(\.id) == [a.id])
        #expect(repository.fetchTasks(status: .inProgress).map(\.id) == [b.id])
        // A move is an update remotely — there is no separate move operation.
        #expect(repository.outbox.map(\.op) == [.update])
    }

    @Test func deleteIsSoftAndHidesTheTaskFromFetches() {
        let (useCases, repository) = makeUseCases()
        let task = useCases.create(title: "A", description: "")
        repository.clearOutbox()

        useCases.delete(id: task.id)

        #expect(repository.fetchTasks(status: nil).isEmpty)
        #expect(repository.fetchTask(id: task.id)?.deletedAt != nil)
        #expect(repository.outbox.map(\.op) == [.delete])
    }

    @Test func eachOperationQueuesExactlyOneEntry() {
        let (useCases, repository) = makeUseCases()

        let task = useCases.create(title: "A", description: "")
        _ = useCases.update(id: task.id, title: "B", description: nil)
        _ = useCases.move(id: task.id, to: .done, afterPosition: nil, beforePosition: nil)
        useCases.delete(id: task.id)

        #expect(repository.outbox.map(\.op) == [.create, .update, .update, .delete])
    }

    // MARK: fractionalPosition

    @Test func noNeighboursGivesTheBaselinePosition() {
        #expect(TaskUseCases.fractionalPosition(before: nil, after: nil) == 0)
    }

    @Test func onlyABeforeNeighbourGivesSomethingGreater() {
        let result = TaskUseCases.fractionalPosition(before: 5, after: nil)
        #expect(result > 5)
    }

    @Test func onlyAnAfterNeighbourGivesSomethingSmaller() {
        let result = TaskUseCases.fractionalPosition(before: nil, after: 5)
        #expect(result < 5)
    }

    @Test func bothNeighboursGivesTheExactMidpoint() {
        #expect(TaskUseCases.fractionalPosition(before: 1, after: 2) == 1.5)
        #expect(TaskUseCases.fractionalPosition(before: -4, after: 4) == 0)
        #expect(TaskUseCases.fractionalPosition(before: 2.5, after: 2.75) == 2.625)
    }

    @Test func repeatedInsertsIntoTheSameGapDoNotCollide() {
        let lower = 1.0
        let upper = 2.0

        let first = TaskUseCases.fractionalPosition(before: lower, after: upper)
        let second = TaskUseCases.fractionalPosition(before: lower, after: first)
        let third = TaskUseCases.fractionalPosition(before: lower, after: second)

        #expect(first != second)
        #expect(second != third)
        // Still strictly ordered, so the column keeps its intended sequence.
        #expect(lower < third)
        #expect(third < second)
        #expect(second < first)
        #expect(first < upper)
    }

    @Test func repeatedInsertsAtTheTopOfAColumnKeepMovingUp() {
        var position = TaskUseCases.fractionalPosition(before: nil, after: 0)
        var previous = 0.0

        for _ in 0..<5 {
            #expect(position < previous)
            previous = position
            position = TaskUseCases.fractionalPosition(before: nil, after: position)
        }
    }
}
