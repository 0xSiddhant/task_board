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

    /// What the field holds right now, updated on every keystroke.
    @Published var searchQuery = ""
    /// What the board actually filters on, trailing the field by the debounce
    /// interval. Scrolling and highlighting key off this one so they don't chase
    /// each character as it's typed.
    @Published private(set) var activeQuery = ""

    private let useCases: TaskUseCases
    private var cancellables = Set<AnyCancellable>()

    init(useCases: TaskUseCases, searchDebounce: Duration = .milliseconds(250)) {
        self.useCases = useCases
        // Driven by the store rather than by use-case return values, so the board
        // stays correct when the sync engine writes behind us.
        useCases.observeTasks()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tasks in
                self?.regroup(tasks)
            }
            .store(in: &cancellables)

        $searchQuery
            .debounce(for: .seconds(searchDebounce.asTimeInterval), scheduler: DispatchQueue.main)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .removeDuplicates()
            .sink { [weak self] query in
                self?.activeQuery = query
            }
            .store(in: &cancellables)
    }

    func tasks(in status: TaskStatus) -> [Task] {
        tasksByStatus[status] ?? []
    }

    // MARK: Search

    var isSearchActive: Bool { !activeQuery.isEmpty }

    /// Matches in board order — left to right, top to bottom — so "first match"
    /// means the one a reader would reach first.
    var matches: [Task] {
        guard isSearchActive else { return [] }
        return TaskStatus.allCases
            .flatMap { tasks(in: $0) }
            .filter { $0.matches(activeQuery) }
    }

    var matchedIDs: Set<UUID> { Set(matches.map(\.id)) }

    func clearSearch() {
        searchQuery = ""
        activeQuery = ""
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

private extension Task {
    func matches(_ query: String) -> Bool {
        title.localizedCaseInsensitiveContains(query)
            || description.localizedCaseInsensitiveContains(query)
    }
}

private extension Duration {
    /// `debounce` wants a TimeInterval; `Duration` is the nicer thing to pass in.
    var asTimeInterval: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}
