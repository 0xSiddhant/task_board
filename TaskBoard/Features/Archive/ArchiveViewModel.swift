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

    private let useCases: TaskUseCases
    private var cancellables = Set<AnyCancellable>()

    init(useCases: TaskUseCases) {
        self.useCases = useCases

        // Store-driven for the same reason the board is: a restore writes
        // through the repository and comes back on this publisher.
        useCases.observeArchived()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] archived in
                self?.tasks = archived
            }
            .store(in: &cancellables)
    }

    var isEmpty: Bool { tasks.isEmpty }

    func restore(_ task: ArchivedTask) {
        useCases.restore(id: task.id)
    }
}
