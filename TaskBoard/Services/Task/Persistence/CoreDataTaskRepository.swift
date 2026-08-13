import Combine
import CoreData

// @unchecked because the compiler can't see the invariant that holds it
// together: every access to `subject` and `controller` happens inside
// `context.performAndWait`, so the context's private queue serialises them.
nonisolated final class CoreDataTaskRepository: NSObject, TaskRepository, @unchecked Sendable {
    private let context: NSManagedObjectContext

    private let subject = CurrentValueSubject<[Task], Never>([])
    private let outboxCount = CurrentValueSubject<Int, Never>(0)
    private let archived = CurrentValueSubject<[ArchivedTask], Never>([])
    private var controller: NSFetchedResultsController<CDTask>?

    init(stack: CoreDataStack) {
        // A private-queue context, not viewContext: every read and write here
        // then runs off the main thread, and merges into the UI context.
        self.context = stack.newBackgroundContext()
        super.init()
    }

    // MARK: TaskRepository

    func createTask(title: String, description: String, parentId: UUID? = nil) -> Task {
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
            // Only honoured when the prospective parent exists and is itself
            // top-level, so a subtask can never be created under another one.
            cdTask.parentId = parentId.flatMap { candidate in
                guard let parent = fetch(id: candidate),
                      parent.deletedAt == nil,
                      parent.parentId == nil
                else { return nil }
                return candidate
            }

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

            // Finishing a parent finishes its subtasks. Only Done cascades:
            // dragging a parent to In Progress would otherwise un-complete work
            // that was genuinely finished.
            if status == .done {
                // Walked forward rather than re-querying per child, so the
                // positions stay distinct without depending on how Core Data
                // merges pending changes into a fetch.
                var nextDone = nextPosition(in: .done)
                for child in descendantRows(of: id) where child.status != TaskStatus.done.rawValue {
                    let childBase = child.updatedAt
                    child.status = TaskStatus.done.rawValue
                    child.position = nextDone
                    child.updatedAt = Date()
                    child.syncStatus = SyncStatus.pending.rawValue
                    enqueue(.update, taskId: child.id, baseUpdatedAt: childBase)
                    nextDone += 1
                }
            }

            result = cdTask.toDomain()
            save()
        }
        return result
    }

    /// Soft delete. The row survives until the sync engine gets a remote ack, so
    /// a delete queued offline is still replayable after a relaunch.
    func deleteTask(id: UUID) {
        context.performAndWait {
            guard let cdTask = fetch(id: id) else { return }

            // The whole subtree goes with the parent. Empty for a subtask, so
            // deleting one is unchanged.
            for child in descendantRows(of: id) { softDelete(child) }
            softDelete(cdTask)
            save()
        }
    }

    private func softDelete(_ cdTask: CDTask) {
        let baseUpdatedAt = cdTask.updatedAt
        cdTask.deletedAt = Date()
        cdTask.updatedAt = Date()
        cdTask.syncStatus = SyncStatus.pending.rawValue
        enqueue(.delete, taskId: cdTask.id, baseUpdatedAt: baseUpdatedAt)
    }

    // MARK: Hierarchy

    @discardableResult
    func setParent(id: UUID, parentId: UUID?) -> Task? {
        var result: Task?
        context.performAndWait {
            guard let cdTask = fetch(id: id), cdTask.deletedAt == nil else { return }

            if let parentId {
                guard parentId != id,                          // can't be its own parent
                      let parent = fetch(id: parentId),
                      parent.deletedAt == nil,
                      parent.parentId == nil,                  // parent must be top-level
                      childRows(of: id).isEmpty,               // and this task must have no subtasks
                      // Archived ones count too. Without this, a task whose only
                      // subtasks are archived looks childless, gets linked under
                      // another task, and then restoring those subtasks builds a
                      // three-level chain.
                      archivedChildRows(of: id).isEmpty
                else { return }
            }

            let baseUpdatedAt = cdTask.updatedAt
            cdTask.parentId = parentId
            cdTask.updatedAt = Date()
            cdTask.syncStatus = SyncStatus.pending.rawValue

            enqueue(.update, taskId: id, baseUpdatedAt: baseUpdatedAt)
            result = cdTask.toDomain()
            save()
        }
        return result
    }

    func childTasks(of id: UUID) -> [Task] {
        var result: [Task] = []
        context.performAndWait {
            result = childRows(of: id).map { $0.toDomain() }
        }
        return result
    }

    /// Backed by the `byParentId` fetch index on `CDTask`.
    private func childRows(of id: UUID) -> [CDTask] {
        let request = CDTask.typedFetchRequest()
        request.predicate = NSPredicate(format: "deletedAt == nil AND parentId == %@", id as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "position", ascending: true)]
        return (try? context.fetch(request)) ?? []
    }

    private func archivedChildRows(of id: UUID) -> [CDArchivedTask] {
        let request = CDArchivedTask.typedFetchRequest()
        request.predicate = NSPredicate(format: "parentId == %@", id as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "position", ascending: true)]
        return (try? context.fetch(request)) ?? []
    }

    /// Everything beneath `id`, parents always ahead of their own descendants.
    ///
    /// Nesting is capped at one level when links are made here, but a deeper
    /// chain can still arrive — from a device running an older build, or from a
    /// remote record `applyRemote` takes at face value. A cascade that stopped
    /// after one level would strand those rows on the board with their parent
    /// gone, so every cascade walks the whole subtree. `seen` also keeps a cycle
    /// in bad data from spinning forever.
    private func descendantRows(of id: UUID) -> [CDTask] {
        var result: [CDTask] = []
        var seen: Set<UUID> = [id]
        var frontier = [id]

        while let current = frontier.popLast() {
            for child in childRows(of: current) where seen.insert(child.id).inserted {
                result.append(child)
                frontier.append(child.id)
            }
        }
        return result
    }

    private func archivedDescendantRows(of id: UUID) -> [CDArchivedTask] {
        var result: [CDArchivedTask] = []
        var seen: Set<UUID> = [id]
        var frontier = [id]

        while let current = frontier.popLast() {
            for child in archivedChildRows(of: current) where seen.insert(child.id).inserted {
                result.append(child)
                frontier.append(child.id)
            }
        }
        return result
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

    func tasksPublisher() -> AnyPublisher<[Task], Never> {
        if controller == nil {
            context.performAndWait { startObserving() }
        }
        return subject.eraseToAnyPublisher()
    }

    private func startObserving() {
        let request = CDTask.typedFetchRequest()
        request.predicate = NSPredicate(format: "deletedAt == nil")
        request.sortDescriptors = [NSSortDescriptor(key: "position", ascending: true)]

        let controller = NSFetchedResultsController(
            fetchRequest: request,
            managedObjectContext: context,
            sectionNameKeyPath: nil,
            cacheName: nil
        )
        controller.delegate = self
        try? controller.performFetch()
        self.controller = controller
        publishCurrent()
    }

    private func publishCurrent() {
        subject.send((controller?.fetchedObjects ?? []).map { $0.toDomain() })
    }

    // MARK: Archive

    /// Moves the row out of `CDTask` and into `CDArchivedTask`, queuing one
    /// entry. Both halves and the entry commit in a single `save()`, so the task
    /// is never in both tables or neither.
    func archiveTask(id: UUID) {
        context.performAndWait {
            guard let cdTask = fetch(id: id), cdTask.deletedAt == nil else { return }

            // The whole subtree leaves the board together, each row carrying its
            // own entry so the queue can replay them independently.
            for child in descendantRows(of: id) { archive(child) }
            archive(cdTask)
            save()
        }
    }

    private func archive(_ cdTask: CDTask) {
        let entry = CDArchivedTask(context: context)
        entry.id = cdTask.id
        entry.title = cdTask.title
        entry.taskDescription = cdTask.taskDescription
        // The column and slot it held, which is what a restore reads back.
        entry.status = cdTask.status
        entry.position = cdTask.position
        entry.createdAt = cdTask.createdAt
        entry.updatedAt = Date()
        entry.archivedAt = Date()
        entry.parentId = cdTask.parentId

        enqueue(.archive, taskId: cdTask.id, baseUpdatedAt: cdTask.updatedAt)
        context.delete(cdTask)
    }

    /// The mirror image: out of `CDArchivedTask`, back into `CDTask` in the
    /// column it was archived from, one queued entry, one transaction.
    @discardableResult
    func restoreTask(id: UUID) -> Task? {
        var result: Task?
        context.performAndWait {
            guard let entry = fetchArchived(id: id) else { return }

            // The root first, then descendants in order, so every row finds its
            // own parent already on the board and keeps its link rather than
            // being flattened by the check in `restore`.
            result = restore(entry)
            for child in archivedDescendantRows(of: id) { _ = restore(child) }
            save()
        }
        return result
    }

    /// Always returns the task to the column it was archived from, never to the
    /// parent's current one. A subtask archived from To Do comes back to To Do
    /// even if the parent has since moved to Done — the cascade only fires when
    /// a parent is moved, and a restore is the subtask acting on its own. The
    /// parent's badge simply reads as incomplete again, which is true.
    private func restore(_ entry: CDArchivedTask) -> Task {
        let status = TaskStatus(rawValue: entry.status) ?? .todo

        let cdTask = fetch(id: entry.id) ?? CDTask(context: context)
        cdTask.id = entry.id
        cdTask.title = entry.title
        cdTask.taskDescription = entry.taskDescription
        cdTask.status = entry.status
        cdTask.position = restorePosition(entry.position, in: status)
        cdTask.createdAt = entry.createdAt
        cdTask.updatedAt = Date()
        cdTask.syncStatus = SyncStatus.pending.rawValue
        cdTask.deletedAt = nil
        // Kept only if the parent is actually on the board. Restoring a subtask
        // on its own while its parent is still archived brings it back as a
        // top-level card instead of one pointing at something invisible.
        cdTask.parentId = entry.parentId.flatMap { candidate in
            guard let parent = fetch(id: candidate), parent.deletedAt == nil else { return nil }
            return candidate
        }

        enqueue(.restore, taskId: entry.id, baseUpdatedAt: entry.updatedAt)
        context.delete(entry)
        return cdTask.toDomain()
    }

    /// Deduplicated because `publishArchived` runs after every save, most of
    /// which are board writes that leave the archive untouched.
    func archivedTasksPublisher() -> AnyPublisher<[ArchivedTask], Never> {
        context.performAndWait { publishArchived() }
        return archived.removeDuplicates().eraseToAnyPublisher()
    }

    func fetchArchivedTask(id: UUID) -> ArchivedTask? {
        var result: ArchivedTask?
        context.performAndWait {
            result = fetchArchived(id: id)?.toDomain()
        }
        return result
    }

    /// Remote archive state landing locally. Drops the task row if this device
    /// still has one, keeping the invariant that a record lives in exactly one
    /// of the two tables.
    func applyRemoteArchive(_ archived: ArchivedTask) {
        context.performAndWait {
            let entry = fetchArchived(id: archived.id) ?? CDArchivedTask(context: context)
            entry.id = archived.id
            entry.title = archived.title
            entry.taskDescription = archived.description
            entry.status = archived.status.rawValue
            entry.position = archived.position
            entry.createdAt = archived.createdAt
            entry.updatedAt = archived.updatedAt
            entry.archivedAt = archived.archivedAt
            entry.parentId = archived.parentId

            if let cdTask = fetch(id: archived.id) { context.delete(cdTask) }
            save()
        }
    }

    /// Refreshed on every save rather than through a second fetched-results
    /// controller: the archive only ever changes through a local write on this
    /// context, so there is nothing a controller would catch that this misses.
    private func publishArchived() {
        let request = CDArchivedTask.typedFetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "archivedAt", ascending: false)]
        archived.send(((try? context.fetch(request)) ?? []).map { $0.toDomain() })
    }

    private func fetchArchived(id: UUID) -> CDArchivedTask? {
        let request = CDArchivedTask.typedFetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }

    /// The slot the card left, when nothing has taken it since. Falling back to
    /// the end of the column keeps positions distinct — two cards sharing one
    /// position sort against each other arbitrarily.
    private func restorePosition(_ position: Double, in status: TaskStatus) -> Double {
        let request = CDTask.typedFetchRequest()
        request.predicate = NSPredicate(
            format: "deletedAt == nil AND status == %@ AND position == %@",
            status.rawValue,
            NSNumber(value: position)
        )
        request.fetchLimit = 1
        let taken = ((try? context.count(for: request)) ?? 0) > 0
        return taken ? nextPosition(in: status) : position
    }

    // MARK: Sync support

    func pendingOutboxEntries() -> [OutboxEntry] {
        var result: [OutboxEntry] = []
        context.performAndWait {
            let request = CDOutboxEntry.typedFetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
            result = ((try? context.fetch(request)) ?? []).compactMap { $0.toDomain() }
        }
        return result
    }

    func pendingOutboxCountPublisher() -> AnyPublisher<Int, Never> {
        context.performAndWait { publishOutboxCount() }
        return outboxCount.removeDuplicates().eraseToAnyPublisher()
    }

    /// A count query rather than fetching the rows — this runs after every save.
    private func publishOutboxCount() {
        let count = (try? context.count(for: CDOutboxEntry.typedFetchRequest())) ?? 0
        outboxCount.send(count)
    }

    func removeOutboxEntry(id: UUID) {
        context.performAndWait {
            let request = CDOutboxEntry.typedFetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.fetchLimit = 1
            guard let entry = (try? context.fetch(request))?.first else { return }
            context.delete(entry)
            save()
        }
    }

    func fetchTask(id: UUID) -> Task? {
        var result: Task?
        context.performAndWait {
            result = fetch(id: id)?.toDomain()
        }
        return result
    }

    func markSyncStatus(_ status: SyncStatus, for taskId: UUID) {
        context.performAndWait {
            guard let cdTask = fetch(id: taskId) else { return }
            cdTask.syncStatus = status.rawValue
            save()
        }
    }

    /// No outbox entry: this is remote state landing locally, not a local change
    /// that needs pushing back.
    func applyRemote(_ task: Task) {
        context.performAndWait {
            // A record the server holds as a live task is no longer archived —
            // another device restored it, so this device's archive row goes.
            if let archivedRow = fetchArchived(id: task.id) { context.delete(archivedRow) }

            let cdTask = fetch(id: task.id) ?? CDTask(context: context)
            cdTask.id = task.id
            cdTask.title = task.title
            cdTask.taskDescription = task.description
            cdTask.status = task.status.rawValue
            cdTask.position = task.position
            cdTask.createdAt = task.createdAt
            cdTask.updatedAt = task.updatedAt
            cdTask.syncStatus = SyncStatus.synced.rawValue
            cdTask.deletedAt = task.deletedAt
            cdTask.parentId = task.parentId
            save()
        }
    }

    // MARK: Outbox

    /// Never saves. The caller commits the task change and this entry in one
    /// `save()`, so a force-quit mid-write can't half-apply them.
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
            publishOutboxCount()
            publishArchived()
        } catch {
            context.rollback()
            Logger.record("Core Data save failed: \(error)", level: .error)
        }
    }
}

// MARK: - Live updates

nonisolated extension CoreDataTaskRepository: NSFetchedResultsControllerDelegate {
    nonisolated func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        publishCurrent()
    }
}

// MARK: - Mapping

private nonisolated extension CDOutboxEntry {
    /// nil for an unrecognized op, so the sync engine drops it rather than
    /// replaying something it can't interpret.
    func toDomain() -> OutboxEntry? {
        guard let op = OutboxOp(rawValue: op) else { return nil }
        return OutboxEntry(
            id: id,
            op: op,
            taskId: taskId,
            baseUpdatedAt: baseUpdatedAt,
            createdAt: createdAt
        )
    }
}

private nonisolated extension CDArchivedTask {
    func toDomain() -> ArchivedTask {
        ArchivedTask(
            id: id,
            title: title,
            description: taskDescription,
            status: TaskStatus(rawValue: status) ?? .todo,
            position: position,
            createdAt: createdAt,
            updatedAt: updatedAt,
            archivedAt: archivedAt,
            parentId: parentId
        )
    }
}

private nonisolated extension CDTask {
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
            deletedAt: deletedAt,
            parentId: parentId
        )
    }
}
