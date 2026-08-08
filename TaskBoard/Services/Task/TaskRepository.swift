//
//  TaskRepository.swift
//  TaskBoard
//
//  Created by Siddhant Kumar on 08/08/26.
//

import Combine
import Foundation

nonisolated protocol TaskRepository: Sendable {
    func createTask(title: String, description: String) -> Task
    func updateTask(id: UUID, title: String?, description: String?) -> Task?
    func moveTask(id: UUID, to status: TaskStatus, position: Double) -> Task?
    func deleteTask(id: UUID)
    func fetchTasks(status: TaskStatus?) -> [Task]

    /// Live, ordered view of non-deleted tasks, re-emitting on any store change
    /// including background sync writes. Observing here is what keeps Core Data
    /// out of the ViewModels.
    func tasksPublisher() -> AnyPublisher<[Task], Never>

    // MARK: Sync support

    /// Oldest first — the order the sync engine must drain them in.
    func pendingOutboxEntries() -> [OutboxEntry]
    func removeOutboxEntry(id: UUID)
    /// Includes soft-deleted rows; sync still needs the row a delete refers to.
    func fetchTask(id: UUID) -> Task?
    func markSyncStatus(_ status: SyncStatus, for taskId: UUID)
    /// Applies remote state locally, marked `.synced`. Inserts if absent, and
    /// carries `deletedAt` across, which is how a tombstone from another device
    /// removes a task from this one's board.
    func applyRemote(_ task: Task)
}
