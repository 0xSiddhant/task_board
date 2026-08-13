//
//  TaskRepository.swift
//  TaskBoard
//
//  Created by Siddhant Kumar on 08/08/26.
//

import Combine
import Foundation

nonisolated protocol TaskRepository: Sendable {
    /// `parentId` makes the new task a subtask of that task. It still lands in
    /// To Do like any other creation — a subtask is an ordinary board card.
    func createTask(title: String, description: String, parentId: UUID?) -> Task
    func updateTask(id: UUID, title: String?, description: String?) -> Task?

    /// Moving a parent into Done carries its subtasks with it, one queued entry
    /// each. Moves to any other column affect only the task itself, so ordinary
    /// board shuffling never resets a finished subtask.
    func moveTask(id: UUID, to status: TaskStatus, position: Double) -> Task?

    /// Cascades: a parent's subtasks are deleted alongside it.
    func deleteTask(id: UUID)
    func fetchTasks(status: TaskStatus?) -> [Task]

    // MARK: Hierarchy

    /// Links `id` under `parentId`, or unlinks it when that is nil. Rejects
    /// anything that would break the one-level rule — linking a task to itself,
    /// to a task that is already a subtask, or linking a task that has subtasks
    /// of its own — and returns nil in those cases.
    @discardableResult
    func setParent(id: UUID, parentId: UUID?) -> Task?

    /// Live subtasks of a task, excluding deleted ones.
    func childTasks(of id: UUID) -> [Task]

    /// Live, ordered view of non-deleted tasks, re-emitting on any store change
    /// including background sync writes. Observing here is what keeps Core Data
    /// out of the ViewModels.
    func tasksPublisher() -> AnyPublisher<[Task], Never>

    // MARK: Archive

    /// Moves the task out of the task table and into the archive table, keeping
    /// the column and slot it held, and queues one `.archive` entry. A record
    /// lives in exactly one of the two tables at any moment.
    ///
    /// Cascades: a parent's subtasks are archived with it, each getting its own
    /// archive row and entry, so the whole group leaves the board together.
    func archiveTask(id: UUID)

    /// The reverse move, back into the column the task was archived from, and
    /// one `.restore` entry. Restoring a parent restores its archived subtasks
    /// too; restoring a subtask whose parent is still archived clears its link
    /// so it comes back as a top-level card rather than a dangling reference.
    @discardableResult
    func restoreTask(id: UUID) -> Task?

    /// Live view of the archive, newest first.
    func archivedTasksPublisher() -> AnyPublisher<[ArchivedTask], Never>

    /// The archived counterpart of `fetchTask` — what an `.archive` entry needs
    /// to push, since by then the row has left the task table.
    func fetchArchivedTask(id: UUID) -> ArchivedTask?

    /// Applies remote archive state locally, dropping the task row if present.
    /// The counterpart of `applyRemote`, which drops the archive row.
    func applyRemoteArchive(_ archived: ArchivedTask)

    // MARK: Sync support

    /// Oldest first — the order the sync engine must drain them in.
    func pendingOutboxEntries() -> [OutboxEntry]

    /// Emits the queue depth, and only when it actually changes. Deliberately not
    /// derived from `tasksPublisher`: marking a task `.failed` writes to the task,
    /// so a queue-depth trigger built on task changes would re-fire after every
    /// failed push and retry forever.
    func pendingOutboxCountPublisher() -> AnyPublisher<Int, Never>
    func removeOutboxEntry(id: UUID)
    /// Includes soft-deleted rows; sync still needs the row a delete refers to.
    func fetchTask(id: UUID) -> Task?
    func markSyncStatus(_ status: SyncStatus, for taskId: UUID)
    /// Applies remote state locally, marked `.synced`. Inserts if absent, and
    /// carries `deletedAt` across, which is how a tombstone from another device
    /// removes a task from this one's board.
    func applyRemote(_ task: Task)
}
