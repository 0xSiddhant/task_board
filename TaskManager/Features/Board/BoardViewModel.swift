//
//  BoardViewModel.swift
//  TaskManager
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

    /// `index` is the slot to land in, counted with the dragged card already
    /// removed from the column.
    func move(_ task: Task, to status: TaskStatus, insertingAt index: Int) {
        let column = tasks(in: status).filter { $0.id != task.id }
        let clamped = min(max(index, 0), column.count)
        let above = clamped > 0 ? column[clamped - 1].position : nil
        let below = clamped < column.count ? column[clamped].position : nil

        _ = useCases.move(id: task.id, to: status, afterPosition: above, beforePosition: below)
    }

    func delete(_ task: Task) {
        useCases.delete(id: task.id)
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
