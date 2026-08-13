//
//  ArchiveViewModel.swift
//  TaskBoard
//

import Combine
import Foundation

@MainActor
final class ArchiveViewModel: ObservableObject {
    /// Newest first — ordered by the repository's fetch, not re-sorted here.
    @Published private(set) var tasks: [ArchivedTask] = []
    /// Task id → title, covering both tables. A subtask's parent may have been
    /// archived alongside it or may still be on the board, so naming it needs
    /// both sources.
    @Published private(set) var titles: [UUID: String] = [:]

    private let useCases: TaskUseCases
    private var cancellables = Set<AnyCancellable>()

    init(useCases: TaskUseCases) {
        self.useCases = useCases

        // Store-driven for the same reason the board is: a restore writes
        // through the repository and comes back on these publishers.
        useCases.observeArchived()
            .combineLatest(useCases.observeTasks())
            .receive(on: DispatchQueue.main)
            .sink { [weak self] archived, boardTasks in
                self?.tasks = archived
                var titles: [UUID: String] = [:]
                for task in boardTasks where task.deletedAt == nil { titles[task.id] = task.title }
                for entry in archived { titles[entry.id] = entry.title }
                self?.titles = titles
            }
            .store(in: &cancellables)
    }

    /// The name of the task this one is a subtask of, when it is one and the
    /// parent is still known.
    func parentTitle(for task: ArchivedTask) -> String? {
        task.parentId.flatMap { titles[$0] }
    }

    var isEmpty: Bool { tasks.isEmpty }

    func restore(_ task: ArchivedTask) {
        useCases.restore(id: task.id)
    }
}
