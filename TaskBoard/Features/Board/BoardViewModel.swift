//
//  BoardViewModel.swift
//  TaskBoard
//
//  Created by Siddhant Kumar on 08/08/26.
//

import Combine
import Foundation

@MainActor
final class BoardViewModel: ObservableObject {
    @Published private(set) var tasksByStatus: [TaskStatus: [Task]] = [:]

    private let useCases: TaskUseCases
    private var cancellable: AnyCancellable?

    init(useCases: TaskUseCases) {
        self.useCases = useCases
        // Driven by the store rather than by use-case return values, so the board
        // stays correct when the sync engine writes behind us.
        cancellable = useCases.observeTasks()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tasks in
                self?.regroup(tasks)
            }
    }

    func tasks(in status: TaskStatus) -> [Task] {
        tasksByStatus[status] ?? []
    }

    /// Moves `task` so it sits directly above `anchorID`, or to the end of the
    /// column when that is nil. A drop onto the slot the task already occupies
    /// writes nothing — no position change, and no outbox entry to sync.
    func move(_ task: Task, to status: TaskStatus, before anchorID: UUID?) {
        let full = tasks(in: status)
        let column = full.filter { $0.id != task.id }
        let insertIndex = anchorID.flatMap { id in column.firstIndex { $0.id == id } } ?? column.count

        if task.status == status,
           let currentIndex = full.firstIndex(where: { $0.id == task.id }),
           currentIndex == insertIndex {
            return
        }

        let above = insertIndex > 0 ? column[insertIndex - 1].position : nil
        let below = insertIndex < column.count ? column[insertIndex].position : nil

        _ = useCases.move(id: task.id, to: status, afterPosition: above, beforePosition: below)
    }

    private func regroup(_ tasks: [Task]) {
        var grouped = Dictionary(uniqueKeysWithValues: TaskStatus.allCases.map { ($0, [Task]()) })
        for task in tasks where task.deletedAt == nil {
            grouped[task.status]?.append(task)
        }
        for status in TaskStatus.allCases {
            grouped[status]?.sort { $0.position < $1.position }
        }
        tasksByStatus = grouped
    }
}
