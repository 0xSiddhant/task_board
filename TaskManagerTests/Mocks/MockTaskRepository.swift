//
//  MockTaskRepository.swift
//  TaskManagerTests
//
//  Created by Siddhant Kumar on 08/08/26.
//

import Combine
import Foundation
@testable import TaskManager

/// In-memory stand-in for `CoreDataTaskRepository`, mirroring its outbox semantics:
/// every mutation queues exactly one entry carrying the pre-mutation
/// `updatedAt`, and deletes are soft until `hardDelete`.
final class MockTaskRepository: TaskRepository {
    private(set) var storage: [UUID: Task] = [:]
    private(set) var outbox: [OutboxEntry] = []

    /// Injectable so tests can order `updatedAt` values deliberately rather than
    /// hoping two `Date()` calls land far enough apart.
    var now: () -> Date = Date.init

    private let subject = CurrentValueSubject<[Task], Never>([])

    // MARK: Test helpers

    func seed(_ task: Task) {
        storage[task.id] = task
        publish()
    }

    func clearOutbox() {
        outbox.removeAll()
    }

    // MARK: TaskRepository

    func createTask(title: String, description: String) -> Task {
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
            deletedAt: nil
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
        publish()
        return task
    }

    func deleteTask(id: UUID) {
        guard var task = storage[id] else { return }
        let baseUpdatedAt = task.updatedAt

        task.deletedAt = now()
        task.updatedAt = now()
        task.syncStatus = .pending

        storage[id] = task
        enqueue(.delete, taskId: id, baseUpdatedAt: baseUpdatedAt)
        publish()
    }

    func fetchTasks(status: TaskStatus?) -> [Task] {
        storage.values
            .filter { $0.deletedAt == nil && (status == nil || $0.status == status) }
            .sorted { $0.position < $1.position }
    }

    func tasksPublisher() -> AnyPublisher<[Task], Never> {
        subject.eraseToAnyPublisher()
    }

    // MARK: Sync support

    func pendingOutboxEntries() -> [OutboxEntry] {
        outbox   // appended in order, so already oldest-first
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
        publish()
    }

    func hardDelete(id: UUID) {
        storage[id] = nil
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
    }
}
