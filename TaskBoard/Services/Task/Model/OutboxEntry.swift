//
//  OutboxEntry.swift
//  TaskBoard
//
//  Created by Siddhant Kumar on 08/08/26.
//

import Foundation

/// The remote operation an outbox entry replays. A move is an `update` — the
/// remote service has no separate move call, only the changed task.
///
/// `archive` and `restore` are their own ops rather than a delete/create pair
/// because they move a record between two collections, and the remote does both
/// halves in one batch. Replaying them as delete-then-create would leave a
/// window where the record exists in neither.
nonisolated enum OutboxOp: String {
    case create
    case update
    case delete
    case archive
    case restore
}

/// Domain view of a queued outbox row, so the sync engine never touches Core Data.
nonisolated struct OutboxEntry: Identifiable, Equatable {
    let id: UUID
    let op: OutboxOp
    let taskId: UUID
    /// The task's `updatedAt` before the mutation this entry represents.
    let baseUpdatedAt: Date
    let createdAt: Date
}
