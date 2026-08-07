//
//  BoardViewModelTests.swift
//  TaskManagerTests
//
//  Created by Siddhant Kumar on 08/08/26.
//

import Testing
import Foundation
@testable import TaskManager

@MainActor
struct BoardViewModelTests {

    private func makeSubject() -> (BoardViewModel, MockTaskRepository) {
        let repository = MockTaskRepository()
        return (BoardViewModel(useCases: TaskUseCases(repository: repository)), repository)
    }

    /// The board is fed through a Combine hop, so let the main queue deliver.
    private func settle(until condition: @escaping () -> Bool) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await _Concurrency.Task.sleep(nanoseconds: 5_000_000)
        }
    }

    @Test func groupsTasksByStatus() async {
        let (viewModel, repository) = makeSubject()

        let a = repository.createTask(title: "A", description: "")
        _ = repository.createTask(title: "B", description: "")
        _ = repository.moveTask(id: a.id, to: .done, position: 0)

        await settle { viewModel.tasks(in: .done).count == 1 }

        #expect(viewModel.tasks(in: .todo).map(\.title) == ["B"])
        #expect(viewModel.tasks(in: .done).map(\.title) == ["A"])
        #expect(viewModel.tasks(in: .inProgress).isEmpty)
    }

    // MARK: Reorder within a column
    //
    // `insertingAt` counts slots in the column *with the dragged card removed*.
    // Passing an index from the unfiltered column silently lands cards one slot
    // late when moving downwards, which is what these pin down.

    @Test func movingACardDownwardsWithinItsColumnLandsInTheRequestedSlot() async {
        let (viewModel, repository) = makeSubject()

        _ = repository.createTask(title: "A", description: "")
        _ = repository.createTask(title: "B", description: "")
        let c = repository.createTask(title: "C", description: "")
        await settle { viewModel.tasks(in: .todo).count == 3 }

        // A is dragged to the slot between B and C. With A removed the column is
        // [B, C], so that is index 1.
        let a = viewModel.tasks(in: .todo)[0]
        viewModel.move(a, to: .todo, insertingAt: 1)

        await settle { viewModel.tasks(in: .todo).map(\.title) == ["B", "A", "C"] }
        #expect(viewModel.tasks(in: .todo).map(\.title) == ["B", "A", "C"])
        #expect(c.id == viewModel.tasks(in: .todo)[2].id)
    }

    @Test func movingACardUpwardsWithinItsColumnLandsInTheRequestedSlot() async {
        let (viewModel, repository) = makeSubject()

        _ = repository.createTask(title: "A", description: "")
        _ = repository.createTask(title: "B", description: "")
        _ = repository.createTask(title: "C", description: "")
        await settle { viewModel.tasks(in: .todo).count == 3 }

        let c = viewModel.tasks(in: .todo)[2]
        viewModel.move(c, to: .todo, insertingAt: 0)

        await settle { viewModel.tasks(in: .todo).map(\.title) == ["C", "A", "B"] }
        #expect(viewModel.tasks(in: .todo).map(\.title) == ["C", "A", "B"])
    }

    @Test func movingACardToTheEndOfItsOwnColumn() async {
        let (viewModel, repository) = makeSubject()

        _ = repository.createTask(title: "A", description: "")
        _ = repository.createTask(title: "B", description: "")
        _ = repository.createTask(title: "C", description: "")
        await settle { viewModel.tasks(in: .todo).count == 3 }

        let a = viewModel.tasks(in: .todo)[0]
        // With A removed the column is [B, C], so the end is index 2.
        viewModel.move(a, to: .todo, insertingAt: 2)

        await settle { viewModel.tasks(in: .todo).map(\.title) == ["B", "C", "A"] }
        #expect(viewModel.tasks(in: .todo).map(\.title) == ["B", "C", "A"])
    }

    @Test func movingACardOntoItsOwnSlotIsANoOp() async {
        let (viewModel, repository) = makeSubject()

        _ = repository.createTask(title: "A", description: "")
        _ = repository.createTask(title: "B", description: "")
        await settle { viewModel.tasks(in: .todo).count == 2 }

        let a = viewModel.tasks(in: .todo)[0]
        viewModel.move(a, to: .todo, insertingAt: 0)

        await settle { viewModel.tasks(in: .todo).count == 2 }
        #expect(viewModel.tasks(in: .todo).map(\.title) == ["A", "B"])
    }

    // MARK: Cross-column

    @Test func movingBetweenColumnsLandsAtTheRequestedSlot() async {
        let (viewModel, repository) = makeSubject()

        let a = repository.createTask(title: "A", description: "")
        let b = repository.createTask(title: "B", description: "")
        _ = repository.moveTask(id: a.id, to: .inProgress, position: 0)
        await settle { viewModel.tasks(in: .inProgress).count == 1 }

        let dragged = viewModel.tasks(in: .todo).first { $0.id == b.id }!
        viewModel.move(dragged, to: .inProgress, insertingAt: 0)

        await settle { viewModel.tasks(in: .inProgress).count == 2 }
        #expect(viewModel.tasks(in: .inProgress).map(\.title) == ["B", "A"])
        #expect(viewModel.tasks(in: .todo).isEmpty)
    }

    @Test func outOfRangeIndexIsClampedRatherThanCrashing() async {
        let (viewModel, repository) = makeSubject()

        _ = repository.createTask(title: "A", description: "")
        let b = repository.createTask(title: "B", description: "")
        await settle { viewModel.tasks(in: .todo).count == 2 }

        viewModel.move(b, to: .todo, insertingAt: 99)
        await settle { viewModel.tasks(in: .todo).map(\.title) == ["A", "B"] }
        #expect(viewModel.tasks(in: .todo).map(\.title) == ["A", "B"])

        viewModel.move(b, to: .todo, insertingAt: -5)
        await settle { viewModel.tasks(in: .todo).map(\.title) == ["B", "A"] }
        #expect(viewModel.tasks(in: .todo).map(\.title) == ["B", "A"])
    }

    @Test func deleteRemovesTheCardFromTheBoard() async {
        let (viewModel, repository) = makeSubject()

        let task = repository.createTask(title: "A", description: "")
        await settle { viewModel.tasks(in: .todo).count == 1 }

        viewModel.delete(task)

        await settle { viewModel.tasks(in: .todo).isEmpty }
        #expect(viewModel.tasks(in: .todo).isEmpty)
    }
}
