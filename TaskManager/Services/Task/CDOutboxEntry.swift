import CoreData

/// The remote operation an outbox entry replays. A move is an `update` — the
/// remote service has no separate move call, only the changed task.
enum OutboxOp: String {
    case create
    case update
    case delete
}

@objc(CDOutboxEntry)
final class CDOutboxEntry: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var op: String
    @NSManaged var taskId: UUID
    /// The task's `updatedAt` *before* the mutation this entry represents.
    /// Plan 02's conflict check compares it against the server's version.
    @NSManaged var baseUpdatedAt: Date
    @NSManaged var createdAt: Date
}

extension CDOutboxEntry {
    @nonobjc static func typedFetchRequest() -> NSFetchRequest<CDOutboxEntry> {
        NSFetchRequest<CDOutboxEntry>(entityName: "CDOutboxEntry")
    }
}
