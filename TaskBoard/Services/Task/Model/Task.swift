//
//  Task.swift
//  TaskBoard
//
//  Created by Siddhant Kumar on 08/08/26.
//

import Foundation

enum TaskStatus: String, CaseIterable {
    case todo
    case inProgress
    case done
}

enum SyncStatus: String {
    case pending
    case syncing
    case synced
    case failed
}

/// Deliberately free of Core Data: everything above the repository uses this
/// type, so use cases and ViewModels stay testable without a store.
struct Task: Identifiable, Equatable {
    let id: UUID
    var title: String
    var description: String
    var status: TaskStatus
    var position: Double
    let createdAt: Date
    var updatedAt: Date
    var syncStatus: SyncStatus
    var deletedAt: Date?
}
