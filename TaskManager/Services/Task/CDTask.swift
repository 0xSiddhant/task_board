import CoreData

/// Hand-written because the model uses Manual/None codegen. The attributes here
/// mirror `TaskManager.xcdatamodeld` exactly — non-optional in the model means
/// non-optional here, which is safe only because the repository sets every field
/// at insert time and is the sole writer.
@objc(CDTask)
final class CDTask: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var title: String
    @NSManaged var taskDescription: String
    @NSManaged var status: String
    @NSManaged var position: Double
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date
    @NSManaged var syncStatus: String
    @NSManaged var deletedAt: Date?
}

extension CDTask {
    @nonobjc static func typedFetchRequest() -> NSFetchRequest<CDTask> {
        NSFetchRequest<CDTask>(entityName: "CDTask")
    }
}
