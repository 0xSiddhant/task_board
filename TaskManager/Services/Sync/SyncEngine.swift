import Foundation

actor SyncEngine {
    private let repository: TaskRepository
    private let remote: RemoteTaskService

    init(repository: TaskRepository, remote: RemoteTaskService) {
        self.repository = repository
        self.remote = remote
    }

    /// Pull, diff, resolve, push — in that order. Resolving before pushing is the
    /// point: a stale local change gets reconciled against the server version
    /// first, so we never push a write that was already superseded.
    func sync() async {
        let remoteTasks: [Task]
        do {
            remoteTasks = try await remote.fetchTasks()
        } catch {
            // Nothing is drained and nothing is marked failed — the queue is
            // exactly as it was, ready for the next attempt.
            await log("Sync pull failed: \(error)")
            return
        }

        let serverByID = Dictionary(remoteTasks.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        let pending = repository.pendingOutboxEntries()
        let queuedTaskIDs = Set(pending.map(\.taskId))

        applyUncontestedRemoteChanges(remoteTasks, skipping: queuedTaskIDs)
        resolveConflicts(for: pending, against: serverByID)
        await push()
    }

    func hasConflict(baseUpdatedAt: Date, serverUpdatedAt: Date) -> Bool {
        serverUpdatedAt > baseUpdatedAt
    }

    // MARK: Steps

    /// Remote rows we have no queued write for. Another device changed them, so
    /// there's nothing to reconcile — take the server's word for it.
    private func applyUncontestedRemoteChanges(_ remoteTasks: [Task], skipping queued: Set<UUID>) {
        for task in remoteTasks where !queued.contains(task.id) {
            repository.applyRemote(task)
        }
    }

    /// A conflict is "the server moved since the version this write was based on".
    /// Resolution is last-write-wins: if the server is newer than our local task,
    /// the server overwrites it locally. If our local task is newer, we leave it
    /// alone and let the push carry it up.
    private func resolveConflicts(for pending: [OutboxEntry], against serverByID: [UUID: Task]) {
        for entry in pending {
            guard let serverTask = serverByID[entry.taskId],
                  hasConflict(baseUpdatedAt: entry.baseUpdatedAt, serverUpdatedAt: serverTask.updatedAt),
                  let localTask = repository.fetchTask(id: entry.taskId)
            else { continue }

            if serverTask.updatedAt > localTask.updatedAt {
                repository.applyRemote(serverTask)
                repository.removeOutboxEntry(id: entry.id)
            }
        }
    }

    /// Drains oldest-first and stops dead on the first failure. Skipping ahead
    /// would reorder writes against the same task, so a stuck entry blocks the
    /// queue by design.
    private func push() async {
        for entry in repository.pendingOutboxEntries() {
            guard let task = repository.fetchTask(id: entry.taskId) else {
                // The row is gone, so the operation has nothing left to describe.
                repository.removeOutboxEntry(id: entry.id)
                continue
            }

            do {
                switch entry.op {
                case .create: try await remote.create(task)
                case .update: try await remote.update(task)
                case .delete: try await remote.delete(id: task.id)
                }
            } catch {
                repository.markSyncStatus(.failed, for: entry.taskId)
                await log("Sync push failed for \(entry.taskId): \(error)")
                return
            }

            // Only after the remote confirmed. A hard delete before the ack would
            // lose the operation if the push failed.
            if entry.op == .delete {
                repository.hardDelete(id: task.id)
            } else {
                repository.markSyncStatus(.synced, for: task.id)
            }
            repository.removeOutboxEntry(id: entry.id)
        }
    }

    private func log(_ message: String) async {
        await Logger.shared.log(message, level: .error)
    }
}
