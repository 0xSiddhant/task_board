//
//  Task.swift
//  TaskBoard
//
//  Created by Siddhant Kumar on 08/08/26.
//

import Foundation

nonisolated enum TaskStatus: String, CaseIterable {
    case todo
    case inProgress
    case done
}

nonisolated enum SyncStatus: String {
    case pending
    case syncing
    case synced
    case failed
}

/// Deliberately free of Core Data: everything above the repository uses this
/// type, so use cases and ViewModels stay testable without a store.
nonisolated struct Task: Identifiable, Equatable {
    let id: UUID
    var title: String
    var description: String
    var status: TaskStatus
    var position: Double
    let createdAt: Date
    var updatedAt: Date
    var syncStatus: SyncStatus
    var deletedAt: Date?

    /// The form a deleted task takes on the wire. Both backends write this rather
    /// than removing the record, so other devices can tell a deletion apart from
    /// a task they've simply never seen.
    var tombstone: Task {
        guard deletedAt == nil else { return self }
        var copy = self
        copy.deletedAt = Date()
        return copy
    }
}
