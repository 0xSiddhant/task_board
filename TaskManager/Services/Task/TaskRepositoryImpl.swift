import CoreData

final class TaskRepositoryImpl: TaskRepository {
    private let context: NSManagedObjectContext

    init(stack: CoreDataStack) {
        self.context = stack.viewContext
    }

    // MARK: TaskRepository

    func createTask(title: String, description: String) -> Task {
        var result: Task!
        context.performAndWait {
            let now = Date()
            let cdTask = CDTask(context: context)
            cdTask.id = UUID()
            cdTask.title = title
            cdTask.taskDescription = description
            cdTask.status = TaskStatus.todo.rawValue
            cdTask.position = nextPosition(in: .todo)
            cdTask.createdAt = now
            cdTask.updatedAt = now
            cdTask.syncStatus = SyncStatus.pending.rawValue
            cdTask.deletedAt = nil

            enqueue(.create, taskId: cdTask.id, baseUpdatedAt: now)
            result = cdTask.toDomain()
            save()
        }
        return result
    }

    func updateTask(id: UUID, title: String?, description: String?) -> Task? {
        var result: Task?
        context.performAndWait {
            guard let cdTask = fetch(id: id) else { return }
            let baseUpdatedAt = cdTask.updatedAt

            if let title { cdTask.title = title }
            if let description { cdTask.taskDescription = description }
            cdTask.updatedAt = Date()
            cdTask.syncStatus = SyncStatus.pending.rawValue

            enqueue(.update, taskId: id, baseUpdatedAt: baseUpdatedAt)
            result = cdTask.toDomain()
            save()
        }
        return result
    }

    func moveTask(id: UUID, to status: TaskStatus, position: Double) -> Task? {
        var result: Task?
        context.performAndWait {
            guard let cdTask = fetch(id: id) else { return }
            let baseUpdatedAt = cdTask.updatedAt

            cdTask.status = status.rawValue
            cdTask.position = position
            cdTask.updatedAt = Date()
            cdTask.syncStatus = SyncStatus.pending.rawValue

            enqueue(.update, taskId: id, baseUpdatedAt: baseUpdatedAt)
            result = cdTask.toDomain()
            save()
        }
        return result
    }

    /// Soft delete. The row survives until plan 02's sync engine gets a remote ack,
    /// so a delete queued offline is still replayable after a relaunch.
    func deleteTask(id: UUID) {
        context.performAndWait {
            guard let cdTask = fetch(id: id) else { return }
            let baseUpdatedAt = cdTask.updatedAt

            cdTask.deletedAt = Date()
            cdTask.updatedAt = Date()
            cdTask.syncStatus = SyncStatus.pending.rawValue

            enqueue(.delete, taskId: id, baseUpdatedAt: baseUpdatedAt)
            save()
        }
    }

    func fetchTasks(status: TaskStatus?) -> [Task] {
        var result: [Task] = []
        context.performAndWait {
            let request = CDTask.typedFetchRequest()
            request.predicate = status.map {
                NSPredicate(format: "deletedAt == nil AND status == %@", $0.rawValue)
            } ?? NSPredicate(format: "deletedAt == nil")
            request.sortDescriptors = [NSSortDescriptor(key: "position", ascending: true)]
            result = ((try? context.fetch(request)) ?? []).map { $0.toDomain() }
        }
        return result
    }

    // MARK: Outbox

    /// Never saves. The caller commits the task change and this entry in one
    /// `save()`, which is what makes a force-quit mid-write leave the queue
    /// consistent rather than half-applied.
    private func enqueue(_ op: OutboxOp, taskId: UUID, baseUpdatedAt: Date) {
        let entry = CDOutboxEntry(context: context)
        entry.id = UUID()
        entry.op = op.rawValue
        entry.taskId = taskId
        entry.baseUpdatedAt = baseUpdatedAt
        entry.createdAt = Date()
    }

    // MARK: Core Data

    private func fetch(id: UUID) -> CDTask? {
        let request = CDTask.typedFetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }

    private func nextPosition(in status: TaskStatus) -> Double {
        let request = CDTask.typedFetchRequest()
        request.predicate = NSPredicate(format: "deletedAt == nil AND status == %@", status.rawValue)
        request.sortDescriptors = [NSSortDescriptor(key: "position", ascending: false)]
        request.fetchLimit = 1
        let highest = (try? context.fetch(request))?.first?.position
        return (highest ?? -1) + 1
    }

    /// Rolls back on failure so a rejected save never leaves a task change
    /// persisted without its outbox entry, or the reverse.
    private func save() {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            context.rollback()
            _Concurrency.Task {
                await Logger.shared.log("Core Data save failed: \(error)", level: .error)
            }
        }
    }
}

// MARK: - Mapping

private extension CDTask {
    func toDomain() -> Task {
        Task(
            id: id,
            title: title,
            description: taskDescription,
            status: TaskStatus(rawValue: status) ?? .todo,
            position: position,
            createdAt: createdAt,
            updatedAt: updatedAt,
            syncStatus: SyncStatus(rawValue: syncStatus) ?? .pending,
            deletedAt: deletedAt
        )
    }
}
