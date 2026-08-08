//
//  SyncEngine.swift
//  TaskBoard
//
//  Created by Siddhant Kumar on 08/08/26.
//

import Foundation

actor SyncEngine {
    private let repository: TaskRepository
    private let remote: RemoteTaskService

    init(repository: TaskRepository, remote: RemoteTaskService) {
        self.repository = repository
        self.remote = remote
    }

    /// Pull, diff, resolve, push. Resolving before pushing is the point: it stops
    /// a write that was already superseded from going up.
    func sync() async {
        let remoteTasks: [Task]
        do {
            remoteTasks = try await remote.fetchTasks()
        } catch {
            // Nothing drained, nothing marked failed: the queue is untouched.
            await log("Sync pull failed: \(error)", level: .error)
            return
        }

        let serverByID = Dictionary(remoteTasks.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        let pending = repository.pendingOutboxEntries()
        let queuedTaskIDs = Set(pending.map(\.taskId))

        await log("Sync pulled \(remoteTasks.count) remote task(s), \(pending.count) queued locally")

        applyUncontestedRemoteChanges(remoteTasks, skipping: queuedTaskIDs)
        resolveConflicts(for: pending, against: serverByID)
        await push()

        await log("Sync finished, \(repository.pendingOutboxEntries().count) entr(ies) still queued")
    }

    func hasConflict(baseUpdatedAt: Date, serverUpdatedAt: Date) -> Bool {
        serverUpdatedAt > baseUpdatedAt
    }

    // MARK: Steps

    /// Remote rows with no queued write of ours. Nothing to reconcile.
    private func applyUncontestedRemoteChanges(_ remoteTasks: [Task], skipping queued: Set<UUID>) {
        for task in remoteTasks where !queued.contains(task.id) {
            repository.applyRemote(task)
        }
    }

    /// Last-write-wins. A newer server version overwrites locally and drops the
    /// queued entry; a newer local version is left for the push to carry up.
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

    /// Drains oldest-first and stops on the first failure. Skipping ahead would
    /// reorder writes against the same task, so a stuck entry blocks the queue.
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
                await log("Sync push failed for \(entry.taskId): \(error)", level: .error)
                return
            }

            // Only after the remote confirmed: a hard delete before the ack loses
            // the operation if the push failed.
            if entry.op == .delete {
                repository.hardDelete(id: task.id)
            } else {
                repository.markSyncStatus(.synced, for: task.id)
            }
            repository.removeOutboxEntry(id: entry.id)
        }
    }

    private func log(_ message: String, level: LogLevel = .info) async {
        await Logger.shared.log(message, level: level)
    }
}
