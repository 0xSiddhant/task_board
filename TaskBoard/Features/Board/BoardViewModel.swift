//
//  BoardViewModel.swift
//  TaskBoard
//
//  Created by Siddhant Kumar on 08/08/26.
//

import Combine
import Foundation

/// How many of a parent's subtasks are finished.
struct SubtaskProgress: Equatable {
    let done: Int
    let total: Int
}

@MainActor
final class BoardViewModel: ObservableObject {
    @Published private(set) var tasksByStatus: [TaskStatus: [Task]] = [:]

    /// Child id → parent title, for the breadcrumb on a subtask card.
    @Published private(set) var parentTitles: [UUID: String] = [:]
    /// Parent id → its subtask counts, for the badge on a parent card.
    @Published private(set) var subtaskProgress: [UUID: SubtaskProgress] = [:]

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

    /// Direct hits only, in board order — left to right, top to bottom — so
    /// "first match" means the one a reader would reach first, and the result
    /// count reports what actually matched rather than what stayed visible.
    var matches: [Task] {
        guard isSearchActive else { return [] }
        return TaskStatus.allCases
            .flatMap { tasks(in: $0) }
            .filter { $0.matches(activeQuery) }
    }

    /// Direct hits plus the rest of their group: a parent stays lit when one of
    /// its subtasks matches, and subtasks stay lit when their parent does.
    /// Dimming half a group would hide the context that makes a hit legible —
    /// and since non-matching cards aren't interactive, it would also make a
    /// matched subtask's parent untappable.
    var matchedIDs: Set<UUID> {
        guard isSearchActive else { return [] }

        let direct = matches
        var visible = Set(direct.map(\.id))

        for task in direct {
            // A matched subtask keeps its parent.
            if let parentId = task.parentId { visible.insert(parentId) }
            // A matched parent keeps its subtasks.
            for child in allTasks where child.parentId == task.id {
                visible.insert(child.id)
            }
        }
        return visible
    }

    private var allTasks: [Task] {
        TaskStatus.allCases.flatMap { tasks(in: $0) }
    }

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

        rebuildHierarchy(from: tasks.filter { $0.deletedAt == nil })
    }

    /// Derived from the list the store already handed us, so neither the
    /// breadcrumb nor the progress badge costs a query. A subtask whose parent
    /// hasn't arrived yet simply gets no breadcrumb.
    private func rebuildHierarchy(from tasks: [Task]) {
        let titlesByID = Dictionary(tasks.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })

        var titles: [UUID: String] = [:]
        var counts: [UUID: SubtaskProgress] = [:]

        for task in tasks {
            guard let parentId = task.parentId else { continue }
            if let parentTitle = titlesByID[parentId] {
                titles[task.id] = parentTitle
            }
            let running = counts[parentId] ?? SubtaskProgress(done: 0, total: 0)
            counts[parentId] = SubtaskProgress(
                done: running.done + (task.status == .done ? 1 : 0),
                total: running.total + 1
            )
        }

        parentTitles = titles
        subtaskProgress = counts
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
