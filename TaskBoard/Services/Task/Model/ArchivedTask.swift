import Foundation

/// Domain view of an archived row. Like `Task`, deliberately free of Core Data
/// so the archive screen and its tests run without a store.
///
/// Carries `status` and `position` because that is the whole point of the
/// archive: restoring returns the card to the column and slot it left, not to
/// the top of To Do.
nonisolated struct ArchivedTask: Identifiable, Equatable {
    let id: UUID
    var title: String
    var description: String
    var status: TaskStatus
    var position: Double
    let createdAt: Date
    var updatedAt: Date
    var archivedAt: Date
    /// Preserved so restoring a parent puts its subtasks back as subtasks.
    var parentId: UUID?
}
