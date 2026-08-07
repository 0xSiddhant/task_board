//
//  TaskRepository.swift
//  TaskManager
//
//  Created by Siddhant Kumar on 08/08/26.
//

import Combine
import Foundation

protocol TaskRepository {
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
    /// Applies remote state locally, marked `.synced`. Inserts if absent.
    func applyRemote(_ task: Task)
    /// Removes the row for real, after a confirmed remote ack.
    func hardDelete(id: UUID)
}
