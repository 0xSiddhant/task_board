//
//  BoardViewModelTests.swift
//  TaskBoardTests
//
//  Created by Siddhant Kumar on 08/08/26.
//

import Testing
import Foundation
@testable import TaskBoard

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

    private func seedThree(_ repository: MockTaskRepository, _ viewModel: BoardViewModel) async {
        _ = repository.createTask(title: "A", description: "")
        _ = repository.createTask(title: "B", description: "")
        _ = repository.createTask(title: "C", description: "")
        await settle { viewModel.tasks(in: .todo).count == 3 }
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

    @Test func movingDownwardsLandsAboveTheAnchor() async {
        let (viewModel, repository) = makeSubject()
        await seedThree(repository, viewModel)

        let a = viewModel.tasks(in: .todo)[0]
        let c = viewModel.tasks(in: .todo)[2]
        viewModel.move(a, to: .todo, before: c.id)

        await settle { viewModel.tasks(in: .todo).map(\.title) == ["B", "A", "C"] }
        #expect(viewModel.tasks(in: .todo).map(\.title) == ["B", "A", "C"])
    }

    @Test func movingUpwardsLandsAboveTheAnchor() async {
        let (viewModel, repository) = makeSubject()
        await seedThree(repository, viewModel)

        let a = viewModel.tasks(in: .todo)[0]
        let c = viewModel.tasks(in: .todo)[2]
        viewModel.move(c, to: .todo, before: a.id)

        await settle { viewModel.tasks(in: .todo).map(\.title) == ["C", "A", "B"] }
        #expect(viewModel.tasks(in: .todo).map(\.title) == ["C", "A", "B"])
    }

    @Test func nilAnchorAppendsToTheEnd() async {
        let (viewModel, repository) = makeSubject()
        await seedThree(repository, viewModel)

        let a = viewModel.tasks(in: .todo)[0]
        viewModel.move(a, to: .todo, before: nil)

        await settle { viewModel.tasks(in: .todo).map(\.title) == ["B", "C", "A"] }
        #expect(viewModel.tasks(in: .todo).map(\.title) == ["B", "C", "A"])
    }

    // MARK: Drops that change nothing must not write
    //
    // Every write queues an outbox entry and costs a sync round trip, so putting
    // a card back where it already was has to be free.

    @Test func droppingAboveTheCardAlreadyBelowItWritesNothing() async {
        let (viewModel, repository) = makeSubject()
        await seedThree(repository, viewModel)
        repository.clearOutbox()

        // A is already directly above B.
        let a = viewModel.tasks(in: .todo)[0]
        let b = viewModel.tasks(in: .todo)[1]
        viewModel.move(a, to: .todo, before: b.id)

        #expect(repository.outbox.isEmpty)
        #expect(viewModel.tasks(in: .todo).map(\.title) == ["A", "B", "C"])
    }

    @Test func droppingTheLastCardAtTheEndWritesNothing() async {
        let (viewModel, repository) = makeSubject()
        await seedThree(repository, viewModel)
        repository.clearOutbox()

        let c = viewModel.tasks(in: .todo)[2]
        viewModel.move(c, to: .todo, before: nil)

        #expect(repository.outbox.isEmpty)
        #expect(viewModel.tasks(in: .todo).map(\.title) == ["A", "B", "C"])
    }

    @Test func aRealReorderDoesWriteExactlyOneEntry() async {
        let (viewModel, repository) = makeSubject()
        await seedThree(repository, viewModel)
        repository.clearOutbox()

        let c = viewModel.tasks(in: .todo)[2]
        let a = viewModel.tasks(in: .todo)[0]
        viewModel.move(c, to: .todo, before: a.id)

        #expect(repository.outbox.map(\.op) == [.update])
    }

    // MARK: Cross-column

    @Test func movingBetweenColumnsLandsAboveTheAnchor() async {
        let (viewModel, repository) = makeSubject()

        let a = repository.createTask(title: "A", description: "")
        let b = repository.createTask(title: "B", description: "")
        _ = repository.moveTask(id: a.id, to: .inProgress, position: 0)
        await settle { viewModel.tasks(in: .inProgress).count == 1 }

        let dragged = viewModel.tasks(in: .todo).first { $0.id == b.id }!
        viewModel.move(dragged, to: .inProgress, before: a.id)

        await settle { viewModel.tasks(in: .inProgress).count == 2 }
        #expect(viewModel.tasks(in: .inProgress).map(\.title) == ["B", "A"])
        #expect(viewModel.tasks(in: .todo).isEmpty)
    }

    @Test func movingIntoAnEmptyColumnStillWrites() async {
        let (viewModel, repository) = makeSubject()

        let a = repository.createTask(title: "A", description: "")
        await settle { viewModel.tasks(in: .todo).count == 1 }
        repository.clearOutbox()

        viewModel.move(a, to: .done, before: nil)

        await settle { viewModel.tasks(in: .done).count == 1 }
        #expect(repository.outbox.map(\.op) == [.update])
        #expect(viewModel.tasks(in: .todo).isEmpty)
    }

    @Test func anUnknownAnchorFallsBackToTheEnd() async {
        let (viewModel, repository) = makeSubject()
        await seedThree(repository, viewModel)

        let a = viewModel.tasks(in: .todo)[0]
        viewModel.move(a, to: .todo, before: UUID())

        await settle { viewModel.tasks(in: .todo).map(\.title) == ["B", "C", "A"] }
        #expect(viewModel.tasks(in: .todo).map(\.title) == ["B", "C", "A"])
    }
}
