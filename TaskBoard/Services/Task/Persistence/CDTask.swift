import CoreData

@objc(CDTask)
nonisolated final class CDTask: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var title: String
    @NSManaged var taskDescription: String
    @NSManaged var status: String
    @NSManaged var position: Double
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date
    @NSManaged var syncStatus: String
    @NSManaged var deletedAt: Date?
    /// Non-nil on a subtask. One level only — a task with a parent never has
    /// children of its own, which is what keeps cascades non-recursive.
    @NSManaged var parentId: UUID?
}

nonisolated extension CDTask {
    @nonobjc static func typedFetchRequest() -> NSFetchRequest<CDTask> {
        NSFetchRequest<CDTask>(entityName: "CDTask")
    }
}
