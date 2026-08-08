//
//  OutboxEntry.swift
//  TaskBoard
//
//  Created by Siddhant Kumar on 08/08/26.
//

import Foundation

/// The remote operation an outbox entry replays. A move is an `update` — the
/// remote service has no separate move call, only the changed task.
enum OutboxOp: String {
    case create
    case update
    case delete
}

/// Domain view of a queued outbox row, so the sync engine never touches Core Data.
struct OutboxEntry: Identifiable, Equatable {
    let id: UUID
    let op: OutboxOp
    let taskId: UUID
    /// The task's `updatedAt` before the mutation this entry represents.
    let baseUpdatedAt: Date
    let createdAt: Date
}
