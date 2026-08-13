//
//  MockTaskRepository.swift
//  TaskBoardTests
//
//  Created by Siddhant Kumar on 08/08/26.
//

import Combine
import Foundation
@testable import TaskBoard

/// In-memory stand-in for `CoreDataTaskRepository`, mirroring its outbox semantics:
/// every mutation queues exactly one entry carrying the pre-mutation
/// `updatedAt`, and deletes are soft — the row survives as a tombstone.
final class MockTaskRepository: TaskRepository {
    private(set) var storage: [UUID: Task] = [:]
    private(set) var archiveStorage: [UUID: ArchivedTask] = [:]
    private(set) var outbox: [OutboxEntry] = []

    /// Injectable so tests can order `updatedAt` values deliberately rather than
    /// hoping two `Date()` calls land far enough apart.
    var now: () -> Date = Date.init

    private let subject = CurrentValueSubject<[Task], Never>([])
    private let outboxCount = CurrentValueSubject<Int, Never>(0)
    private let archived = CurrentValueSubject<[ArchivedTask], Never>([])

    // MARK: Test helpers

    func seed(_ task: Task) {
        storage[task.id] = task
        publish()
    }

    func clearOutbox() {
        outbox.removeAll()
    }

    // MARK: TaskRepository

    func createTask(title: String, description: String, parentId: UUID? = nil) -> Task {
        let timestamp = now()
        let task = Task(
            id: UUID(),
            title: title,
            description: description,
            status: .todo,
            position: nextPosition(in: .todo),
            createdAt: timestamp,
            updatedAt: timestamp,
            syncStatus: .pending,
            deletedAt: nil,
            // Mirrors the real repository: only a top-level task may be a parent.
            parentId: parentId.flatMap { candidate in
                guard let parent = storage[candidate], parent.deletedAt == nil, parent.parentId == nil
                else { return nil }
                return candidate
            }
        )
        storage[task.id] = task
        enqueue(.create, taskId: task.id, baseUpdatedAt: timestamp)
        publish()
        return task
    }

    func updateTask(id: UUID, title: String?, description: String?) -> Task? {
        guard var task = storage[id] else { return nil }
        let baseUpdatedAt = task.updatedAt

        if let title { task.title = title }
        if let description { task.description = description }
        task.updatedAt = now()
        task.syncStatus = .pending

        storage[id] = task
        enqueue(.update, taskId: id, baseUpdatedAt: baseUpdatedAt)
        publish()
        return task
    }

    func moveTask(id: UUID, to status: TaskStatus, position: Double) -> Task? {
        guard var task = storage[id] else { return nil }
        let baseUpdatedAt = task.updatedAt

        task.status = status
        task.position = position
        task.updatedAt = now()
        task.syncStatus = .pending

        storage[id] = task
        enqueue(.update, taskId: id, baseUpdatedAt: baseUpdatedAt)

        // Only Done cascades, matching the real repository.
        if status == .done {
            var nextDone = nextPosition(in: .done)
            for var child in descendants(of: id) where child.status != .done {
                let childBase = child.updatedAt
                child.status = .done
                child.position = nextDone
                child.updatedAt = now()
                child.syncStatus = .pending
                storage[child.id] = child
                enqueue(.update, taskId: child.id, baseUpdatedAt: childBase)
                nextDone += 1
            }
        }

        publish()
        return task
    }

    func deleteTask(id: UUID) {
        guard storage[id] != nil else { return }
        for child in descendants(of: id) { softDelete(child.id) }
        softDelete(id)
        publish()
    }

    private func softDelete(_ id: UUID) {
        guard var task = storage[id] else { return }
        let baseUpdatedAt = task.updatedAt

        task.deletedAt = now()
        task.updatedAt = now()
        task.syncStatus = .pending

        storage[id] = task
        enqueue(.delete, taskId: id, baseUpdatedAt: baseUpdatedAt)
    }

    // MARK: Hierarchy

    @discardableResult
    func setParent(id: UUID, parentId: UUID?) -> Task? {
        guard var task = storage[id], task.deletedAt == nil else { return nil }

        if let parentId {
            guard parentId != id,
                  let parent = storage[parentId],
                  parent.deletedAt == nil,
                  parent.parentId == nil,
                  children(of: id).isEmpty,
                  // Archived subtasks count too, or restoring them later would
                  // build a three-level chain.
                  archivedChildren(of: id).isEmpty
            else { return nil }
        }

        let baseUpdatedAt = task.updatedAt
        task.parentId = parentId
        task.updatedAt = now()
        task.syncStatus = .pending

        storage[id] = task
        enqueue(.update, taskId: id, baseUpdatedAt: baseUpdatedAt)
        publish()
        return task
    }

    func childTasks(of id: UUID) -> [Task] {
        children(of: id)
    }

    private func children(of id: UUID) -> [Task] {
        storage.values
            .filter { $0.deletedAt == nil && $0.parentId == id }
            .sorted { $0.position < $1.position }
    }

    private func archivedChildren(of id: UUID) -> [ArchivedTask] {
        archiveStorage.values
            .filter { $0.parentId == id }
            .sorted { $0.position < $1.position }
    }

    /// Whole subtree, parents ahead of their descendants — cascades walk this
    /// rather than one level, matching the real repository.
    private func descendants(of id: UUID) -> [Task] {
        var result: [Task] = []
        var seen: Set<UUID> = [id]
        var frontier = [id]

        while let current = frontier.popLast() {
            for child in children(of: current) where seen.insert(child.id).inserted {
                result.append(child)
                frontier.append(child.id)
            }
        }
        return result
    }

    private func archivedDescendants(of id: UUID) -> [ArchivedTask] {
        var result: [ArchivedTask] = []
        var seen: Set<UUID> = [id]
        var frontier = [id]

        while let current = frontier.popLast() {
            for child in archivedChildren(of: current) where seen.insert(child.id).inserted {
                result.append(child)
                frontier.append(child.id)
            }
        }
        return result
    }

    func fetchTasks(status: TaskStatus?) -> [Task] {
        storage.values
            .filter { $0.deletedAt == nil && (status == nil || $0.status == status) }
            .sorted { $0.position < $1.position }
    }

    func tasksPublisher() -> AnyPublisher<[Task], Never> {
        subject.eraseToAnyPublisher()
    }

    // MARK: Archive

    func archiveTask(id: UUID) {
        guard storage[id] != nil else { return }
        for child in descendants(of: id) { archive(child.id) }
        archive(id)
        publish()
    }

    private func archive(_ id: UUID) {
        guard let task = storage[id], task.deletedAt == nil else { return }

        archiveStorage[id] = ArchivedTask(
            id: task.id,
            title: task.title,
            description: task.description,
            status: task.status,
            position: task.position,
            createdAt: task.createdAt,
            updatedAt: now(),
            archivedAt: now(),
            parentId: task.parentId
        )
        enqueue(.archive, taskId: id, baseUpdatedAt: task.updatedAt)
        storage[id] = nil
    }

    @discardableResult
    func restoreTask(id: UUID) -> Task? {
        guard archiveStorage[id] != nil else { return nil }
        // Parent first, so its subtasks find it present and keep their link.
        let restored = restore(id)
        for child in archivedDescendants(of: id) { _ = restore(child.id) }
        publish()
        return restored
    }

    private func restore(_ id: UUID) -> Task? {
        guard let entry = archiveStorage[id] else { return nil }

        let task = Task(
            id: entry.id,
            title: entry.title,
            description: entry.description,
            status: entry.status,
            position: entry.position,
            createdAt: entry.createdAt,
            updatedAt: now(),
            syncStatus: .pending,
            deletedAt: nil,
            // Dropped when the parent isn't on the board, so a subtask restored
            // alone comes back top-level rather than dangling.
            parentId: entry.parentId.flatMap { candidate in
                guard let parent = storage[candidate], parent.deletedAt == nil else { return nil }
                return candidate
            }
        )
        storage[id] = task
        enqueue(.restore, taskId: id, baseUpdatedAt: entry.updatedAt)
        archiveStorage[id] = nil
        return task
    }

    func archivedTasksPublisher() -> AnyPublisher<[ArchivedTask], Never> {
        archived.eraseToAnyPublisher()
    }

    func fetchArchivedTask(id: UUID) -> ArchivedTask? {
        archiveStorage[id]
    }

    func applyRemoteArchive(_ archived: ArchivedTask) {
        archiveStorage[archived.id] = archived
        storage[archived.id] = nil   // a record lives in one table, never both
        publish()
    }

    // MARK: Sync support

    func pendingOutboxEntries() -> [OutboxEntry] {
        outbox   // appended in order, so already oldest-first
    }

    func pendingOutboxCountPublisher() -> AnyPublisher<Int, Never> {
        outboxCount.removeDuplicates().eraseToAnyPublisher()
    }

    func removeOutboxEntry(id: UUID) {
        outbox.removeAll { $0.id == id }
    }

    func fetchTask(id: UUID) -> Task? {
        storage[id]   // includes soft-deleted, matching the real repository
    }

    func markSyncStatus(_ status: SyncStatus, for taskId: UUID) {
        storage[taskId]?.syncStatus = status
        publish()
    }

    func applyRemote(_ task: Task) {
        var incoming = task
        incoming.syncStatus = .synced
        storage[task.id] = incoming
        archiveStorage[task.id] = nil   // live on the server means no longer archived
        publish()
    }

    // MARK: Internals

    private func enqueue(_ op: OutboxOp, taskId: UUID, baseUpdatedAt: Date) {
        outbox.append(
            OutboxEntry(id: UUID(), op: op, taskId: taskId, baseUpdatedAt: baseUpdatedAt, createdAt: now())
        )
    }

    private func nextPosition(in status: TaskStatus) -> Double {
        let highest = storage.values
            .filter { $0.deletedAt == nil && $0.status == status }
            .map(\.position)
            .max()
        return (highest ?? -1) + 1
    }

    private func publish() {
        subject.send(fetchTasks(status: nil))
        outboxCount.send(outbox.count)
        archived.send(archiveStorage.values.sorted { $0.archivedAt > $1.archivedAt })
    }
}
