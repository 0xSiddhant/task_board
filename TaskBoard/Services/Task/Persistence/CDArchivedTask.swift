import CoreData

/// A separate table from `CDTask` rather than an `archivedAt` flag on it: the
/// board's fetch predicates, the outbox, and the sync engine all key off
/// `CDTask`, and none of them should have to learn about a second reason a row
/// might be hidden.
@objc(CDArchivedTask)
nonisolated final class CDArchivedTask: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var title: String
    @NSManaged var taskDescription: String
    /// The column the task was archived from. Restoring reads this, which is
    /// what puts the card back where it came from instead of in To Do.
    @NSManaged var status: String
    /// The slot it held in that column, reused on restore when still free.
    @NSManaged var position: Double
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date
    @NSManaged var archivedAt: Date
    /// Carried across so restoring a parent rebuilds the hierarchy rather than
    /// returning a flat set of tasks.
    @NSManaged var parentId: UUID?
}

nonisolated extension CDArchivedTask {
    @nonobjc static func typedFetchRequest() -> NSFetchRequest<CDArchivedTask> {
        NSFetchRequest<CDArchivedTask>(entityName: "CDArchivedTask")
    }
}
