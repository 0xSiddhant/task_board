//
//  SyncEngine.swift
//  TaskBoard
//
//  Created by Siddhant Kumar on 08/08/26.
//

import Foundation

enum SyncError: Error {
    case timedOut
}

actor SyncEngine {
    private let repository: TaskRepository
    private let remote: RemoteTaskService
    private let timeout: TimeInterval
    private var isSyncing = false
    /// Set when a sync is requested while one is already running, so the request
    /// is deferred to the next pass rather than dropped.
    private var needsAnotherPass = false

    /// Firestore retries a rejected write stream indefinitely rather than
    /// erroring, so a misconfigured backend hangs `sync()` forever and the queue
    /// never drains. Every remote call gets a deadline for that reason.
    init(repository: TaskRepository, remote: RemoteTaskService, timeout: TimeInterval = 15) {
        self.repository = repository
        self.remote = remote
        self.timeout = timeout
    }

    /// Races the call against a sleep. Cancelling the group cancels the work, but
    /// a backend that ignores cancellation may still complete its write — the
    /// point is that the engine regains control and can requeue.
    private func withTimeout<T: Sendable>(
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let seconds = timeout
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await _Concurrency.Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw SyncError.timedOut
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }

    /// Runs a pass, then runs another if anything asked for one while it was in
    /// flight.
    ///
    /// Overlapping calls still never run concurrently — two passes over one
    /// outbox would race to drain the same entries. But they must not be thrown
    /// away either: a request arriving mid-pass usually means something changed
    /// *after* that pass had already pulled, so dropping it loses the change
    /// until the next trigger. That is the shape of a sync that silently goes
    /// missing and needs a manual one to recover.
    ///
    /// Bounded, because a device being actively edited elsewhere could otherwise
    /// keep this going indefinitely; leftovers wait for the next trigger.
    func sync() async {
        guard !isSyncing else {
            needsAnotherPass = true
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        for _ in 1...Self.maxSyncPasses {
            needsAnotherPass = false
            await runPass()
            guard needsAnotherPass else { return }
            await log("A change arrived while syncing, running another pass")
        }
    }

    private static let maxSyncPasses = 3

    /// Pull, diff, resolve, push. Resolving before pushing is the point: it stops
    /// a write that was already superseded from going up.
    private func runPass() async {
        let remoteTasks: [Task]
        let remoteArchived: [ArchivedTask]
        do {
            let remote = self.remote
            remoteTasks = try await withTimeout { try await remote.fetchTasks() }
            remoteArchived = try await withTimeout { try await remote.fetchArchived() }
        } catch {
            // Nothing drained, nothing marked failed: the queue is untouched.
            await log("Sync pull failed: \(error)", level: .error)
            return
        }

        // Archived last, so a record the server somehow holds in both
        // collections resolves to archived rather than to whichever the
        // dictionary happened to keep.
        var serverByID = [UUID: RemoteRecord]()
        for task in remoteTasks { serverByID[task.id] = .task(task) }
        for archived in remoteArchived { serverByID[archived.id] = .archived(archived) }

        let pending = repository.pendingOutboxEntries()
        let queuedTaskIDs = Set(pending.map(\.taskId))

        await log("Sync pulled \(remoteTasks.count) remote task(s) and \(remoteArchived.count) archived, \(pending.count) queued locally")

        applyUncontestedRemoteChanges(serverByID, skipping: queuedTaskIDs)
        resolveConflicts(for: pending, against: serverByID)
        await push()

        await log("Sync finished, \(repository.pendingOutboxEntries().count) entr(ies) still queued")
    }

    func hasConflict(baseUpdatedAt: Date, serverUpdatedAt: Date) -> Bool {
        serverUpdatedAt > baseUpdatedAt
    }

    // MARK: Steps

    /// A record as the server holds it. Which collection it came from is itself
    /// state to reconcile — a task moving to `archived` is how another device's
    /// archive reaches this one.
    private enum RemoteRecord {
        case task(Task)
        case archived(ArchivedTask)

        var updatedAt: Date {
            switch self {
            case .task(let task): return task.updatedAt
            case .archived(let archived): return archived.updatedAt
            }
        }

        /// A tombstone in the task collection. Archived records are not deleted
        /// — they live in the other collection precisely so they stay findable.
        var isDeleted: Bool {
            switch self {
            case .task(let task): return task.deletedAt != nil
            case .archived: return false
            }
        }
    }

    private func apply(_ record: RemoteRecord) {
        switch record {
        case .task(let task): repository.applyRemote(task)
        case .archived(let archived): repository.applyRemoteArchive(archived)
        }
    }

    /// Remote rows with no queued write of ours. Nothing to reconcile.
    private func applyUncontestedRemoteChanges(_ serverByID: [UUID: RemoteRecord], skipping queued: Set<UUID>) {
        for (id, record) in serverByID where !queued.contains(id) {
            apply(record)
        }
    }

    /// Resolves queued writes against what the server holds, in two tiers.
    ///
    /// **A remote delete always wins**, whatever the timestamps say. Comparing
    /// versions is how two competing *edits* are settled, but a deletion isn't
    /// an edit — it says the record should not exist. Letting a newer local
    /// edit win that race would push an `update`, and since an update writes
    /// `deletedAt: nil`, it would resurrect a task the server had deleted. The
    /// local edit is discarded and the tombstone applied, so the task leaves
    /// this board too.
    ///
    /// **Everything else is last-write-wins.** A newer server version overwrites
    /// locally and drops the queued entry; a newer local version is left for the
    /// push to carry up.
    ///
    /// The local side is looked up in both tables, since a queued `.archive` has
    /// already moved its row across.
    private func resolveConflicts(for pending: [OutboxEntry], against serverByID: [UUID: RemoteRecord]) {
        var serverWon = Set<UUID>()

        for entry in pending {
            guard let record = serverByID[entry.taskId] else { continue }

            // An earlier entry for this task already resolved in the server's
            // favour, so every remaining entry describes a change that has been
            // superseded. Dropping them matters: applying the server's state
            // makes local and server equal, so the version check below would no
            // longer fire and the push would send the server's own state back.
            if serverWon.contains(entry.taskId) {
                repository.removeOutboxEntry(id: entry.id)
                continue
            }

            if record.isDeleted {
                apply(record)
                repository.removeOutboxEntry(id: entry.id)
                serverWon.insert(entry.taskId)
                continue
            }

            guard hasConflict(baseUpdatedAt: entry.baseUpdatedAt, serverUpdatedAt: record.updatedAt),
                  let localUpdatedAt = localUpdatedAt(for: entry.taskId)
            else { continue }

            if record.updatedAt > localUpdatedAt {
                apply(record)
                repository.removeOutboxEntry(id: entry.id)
                serverWon.insert(entry.taskId)
            }
        }
    }

    private func localUpdatedAt(for id: UUID) -> Date? {
        repository.fetchTask(id: id)?.updatedAt ?? repository.fetchArchivedTask(id: id)?.updatedAt
    }

    /// Keeps draining until the outbox is empty, a push fails, or the pass limit
    /// is hit.
    ///
    /// A single pass over one snapshot would leave anything queued *while* that
    /// pass was in flight sitting until the next trigger. That was tolerable
    /// when every trigger was a user or system event; now that another device's
    /// write starts a sync, a queue that only half-drains is much more visible.
    ///
    /// The limit exists because each pass can legitimately find new work —
    /// someone editing while the queue drains would otherwise keep this running.
    /// Whatever is left over waits for the next trigger, as before.
    private func push() async {
        for pass in 1...Self.maxPushPasses {
            let pending = repository.pendingOutboxEntries()
            guard !pending.isEmpty else { return }

            guard await drain(pending) else { return }   // stopped on a failure

            if pass == Self.maxPushPasses, !repository.pendingOutboxEntries().isEmpty {
                await log("Outbox still has entries after \(pass) push passes, leaving them queued", level: .warning)
            }
        }
    }

    private static let maxPushPasses = 5

    /// Drains oldest-first and stops on the first failure. Skipping ahead would
    /// reorder writes against the same task, so a stuck entry blocks the queue.
    /// Returns false when it stopped early.
    private func drain(_ pending: [OutboxEntry]) async -> Bool {
        for entry in pending {
            let sent: Bool
            do {
                sent = try await perform(entry)
            } catch {
                repository.markSyncStatus(.failed, for: entry.taskId)
                await log("Sync push failed for \(entry.taskId): \(error)", level: .error)
                return false
            }

            // A deleted task keeps its soft-deleted row rather than being erased.
            // The server now holds a tombstone, so erasing locally only means the
            // next pull recreates the row from it.
            if sent { repository.markSyncStatus(.synced, for: entry.taskId) }
            repository.removeOutboxEntry(id: entry.id)
        }
        return true
    }

    /// Sends one entry, reading its payload from whichever table now holds the
    /// record. Returns false when that table has none — an archive queued and
    /// then restored while offline leaves an entry describing a row that has
    /// since moved on, and replaying it would undo the newer intent. Dropping it
    /// is how archive/restore churn collapses to the final state.
    private func perform(_ entry: OutboxEntry) async throws -> Bool {
        let remote = self.remote

        switch entry.op {
        case .create, .update, .delete:
            guard let task = repository.fetchTask(id: entry.taskId) else { return false }
            switch entry.op {
            case .create: try await withTimeout { try await remote.create(task) }
            case .update: try await withTimeout { try await remote.update(task) }
            default:      try await withTimeout { try await remote.delete(task) }
            }

        case .archive:
            guard let archived = repository.fetchArchivedTask(id: entry.taskId) else { return false }
            try await withTimeout { try await remote.archive(archived) }

        case .restore:
            guard let task = repository.fetchTask(id: entry.taskId) else { return false }
            try await withTimeout { try await remote.restore(task) }
        }

        return true
    }

    private func log(_ message: String, level: LogLevel = .info) async {
        await Logger.shared.log(message, level: level)
    }
}
