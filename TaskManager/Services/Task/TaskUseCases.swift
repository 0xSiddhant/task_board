import Foundation

struct TaskUseCases {
    let repository: TaskRepository

    func create(title: String, description: String) -> Task {
        repository.createTask(title: title, description: description)
    }

    func update(id: UUID, title: String?, description: String?) -> Task? {
        repository.updateTask(id: id, title: title, description: description)
    }

    func move(id: UUID, to status: TaskStatus, afterPosition before: Double?, beforePosition after: Double?) -> Task? {
        repository.moveTask(id: id, to: status, position: Self.fractionalPosition(before: before, after: after))
    }

    func delete(id: UUID) {
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
