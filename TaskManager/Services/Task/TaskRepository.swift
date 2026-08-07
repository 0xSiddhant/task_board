import Foundation

/// The remote operation an outbox entry replays. A move is an `update` — the
/// remote service has no separate move call, only the changed task.
enum OutboxOp: String {
    case create
    case update
    case delete
}

/// Domain view of a queued outbox row, so the sync engine never touches Core Data.
struct OutboxEntry: Identifiable, Equatable {
    let id: UUID
    let op: OutboxOp
    let taskId: UUID
    /// The task's `updatedAt` before the mutation this entry represents.
    let baseUpdatedAt: Date
    let createdAt: Date
}

protocol TaskRepository {
    func createTask(title: String, description: String) -> Task
    func updateTask(id: UUID, title: String?, description: String?) -> Task?
    func moveTask(id: UUID, to status: TaskStatus, position: Double) -> Task?
    func deleteTask(id: UUID)
    func fetchTasks(status: TaskStatus?) -> [Task]

    // MARK: Sync support

    /// Oldest first — the order the sync engine must drain them in.
    func pendingOutboxEntries() -> [OutboxEntry]
    func removeOutboxEntry(id: UUID)
    /// Includes soft-deleted rows; sync still needs the row a delete refers to.
    func fetchTask(id: UUID) -> Task?
    func markSyncStatus(_ status: SyncStatus, for taskId: UUID)
    /// Applies remote state locally, marked `.synced`. Inserts if absent.
    func applyRemote(_ task: Task)
    /// Removes the row for real, after a confirmed remote ack.
    func hardDelete(id: UUID)
}
