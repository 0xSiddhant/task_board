import Combine
import Foundation

struct TaskUseCases {
    let repository: TaskRepository

    func observeTasks() -> AnyPublisher<[Task], Never> {
        repository.tasksPublisher()
    }

    // Logged by id, never by title — these lines end up in an uploaded file.
    func create(title: String, description: String) -> Task {
        let task = repository.createTask(title: title, description: description)
        Logger.record("Created task \(task.id)")
        return task
    }

    func update(id: UUID, title: String?, description: String?) -> Task? {
        Logger.record("Updated task \(id)")
        return repository.updateTask(id: id, title: title, description: description)
    }

    func move(id: UUID, to status: TaskStatus, afterPosition before: Double?, beforePosition after: Double?) -> Task? {
        Logger.record("Moved task \(id) to \(status.rawValue)")
        return repository.moveTask(id: id, to: status, position: Self.fractionalPosition(before: before, after: after))
    }

    func delete(id: UUID) {
        Logger.record("Deleted task \(id)")
        repository.deleteTask(id: id)
    }

    /// Midpoint between neighbors. Handles both ends of a column without
    /// special-casing above.
    static func fractionalPosition(before: Double?, after: Double?) -> Double {
        switch (before, after) {
        case let (.some(b), .some(a)): return (b + a) / 2
        case let (.some(b), .none): return b + 1
        case let (.none, .some(a)): return a - 1
        case (.none, .none): return 0
        }
    }
}
