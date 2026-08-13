//
//  FirebaseRemoteTaskService.swift
//  TaskBoard
//
//  Created by Siddhant Kumar on 08/08/26.
//

import Foundation
#if canImport(FirebaseFirestore)
import FirebaseFirestore

/// Firestore-backed remote. Documents are keyed by the task's own UUID, so an
/// outbox entry replayed twice overwrites the same document instead of creating
/// a duplicate.
/// Document paths this device has written and not yet seen echoed back by the
/// snapshot listeners.
///
/// A snapshot listener reports local writes as well as remote ones, so without
/// this every push would echo back as a "remote change" and start another sync.
/// Keyed by full document path, not by task id, because `archive`, `restore`,
/// and `delete` each touch both collections — consuming one id once would leave
/// the second collection's listener treating its half as foreign.
///
/// Entries expire: a batch that deletes a document which never existed produces
/// no change event, so its path would otherwise sit here forever and swallow a
/// genuine change to that path much later.
/// `nonisolated` and `@unchecked`, not because the project defaults to
/// MainActor but because this is reached from Firestore's callback queue: the
/// lock is what makes it safe, and main-actor isolation would defeat the point.
private nonisolated final class LocalEchoTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [String: Date] = [:]
    private let lifetime: TimeInterval = 30

    func note(_ path: String) {
        lock.lock()
        defer { lock.unlock() }
        prune()
        pending[path] = Date()
    }

    /// True when this change is the echo of our own write, consuming it so a
    /// later change to the same document is treated as foreign.
    func consume(_ path: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        prune()
        return pending.removeValue(forKey: path) != nil
    }

    private func prune() {
        let cutoff = Date().addingTimeInterval(-lifetime)
        pending = pending.filter { $0.value > cutoff }
    }
}

actor FirebaseRemoteTaskService: RemoteTaskService {
    private let firestore: Firestore
    private let collection: CollectionReference
    private let archiveCollection: CollectionReference

    /// nonisolated because both the actor's writes and the snapshot callbacks —
    /// which arrive on Firestore's own queue — have to reach it.
    private nonisolated let echoes = LocalEchoTracker()

    /// Held so the registrations outlive `remoteChanges()`. They run for the
    /// process lifetime, which matches the single `AppEnvironment` that consumes
    /// them.
    private var listeners: [ListenerRegistration] = []

    init(collectionPath: String = "tasks", archivePath: String = "archivedTasks") {
        let firestore = Firestore.firestore()

        // Firestore's own offline queue is switched off deliberately. This app
        // already has an outbox; leaving both on means two queues replaying the
        // same writes under different conflict rules.
        let settings = firestore.settings
        settings.cacheSettings = MemoryCacheSettings()
        firestore.settings = settings

        self.firestore = firestore
        collection = firestore.collection(collectionPath)
        archiveCollection = firestore.collection(archivePath)
    }

    func fetchTasks() async throws -> [Task] {
        try await collection.getDocuments().documents.compactMap(Task.init(document:))
    }

    func create(_ task: Task) async throws {
        let document = collection.document(task.id.uuidString)
        echoes.note(document.path)
        try await document.setData(task.firestoreData)
    }

    func update(_ task: Task) async throws {
        let document = collection.document(task.id.uuidString)
        echoes.note(document.path)
        try await document.setData(task.firestoreData, merge: true)
    }

    /// Writes the tombstone and clears any archive document for the same id, in
    /// one batch. A delete outranks an archive, so leaving the archived copy
    /// behind would let the next pull — which applies the archive collection
    /// last — bring the task back.
    func delete(_ task: Task) async throws {
        try await commitAcrossBothCollections(id: task.id) { batch, taskDocument, archiveDocument in
            batch.setData(task.tombstone.firestoreData, forDocument: taskDocument)
            batch.deleteDocument(archiveDocument)
        }
    }

    // MARK: Archive

    func fetchArchived() async throws -> [ArchivedTask] {
        try await archiveCollection.getDocuments().documents.compactMap(ArchivedTask.init(document:))
    }

    /// A batch, so the record is never in both collections or neither. The task
    /// document is removed outright rather than tombstoned — unlike a delete,
    /// the record still exists for other devices to find, just in the archive
    /// collection, so nothing about the move is invisible to them.
    func archive(_ archived: ArchivedTask) async throws {
        try await commitAcrossBothCollections(id: archived.id) { batch, taskDocument, archiveDocument in
            batch.setData(archived.firestoreData, forDocument: archiveDocument)
            batch.deleteDocument(taskDocument)
        }
    }

    func restore(_ task: Task) async throws {
        try await commitAcrossBothCollections(id: task.id) { batch, taskDocument, archiveDocument in
            batch.setData(task.firestoreData, forDocument: taskDocument)
            batch.deleteDocument(archiveDocument)
        }
    }

    /// Every operation that moves a record between the two collections runs as
    /// one batch, and notes both document paths so neither listener mistakes
    /// its half of the move for another device's work.
    private func commitAcrossBothCollections(
        id: UUID,
        _ build: (WriteBatch, DocumentReference, DocumentReference) -> Void
    ) async throws {
        let taskDocument = collection.document(id.uuidString)
        let archiveDocument = archiveCollection.document(id.uuidString)

        echoes.note(taskDocument.path)
        echoes.note(archiveDocument.path)

        let batch = firestore.batch()
        build(batch, taskDocument, archiveDocument)
        try await batch.commit()
    }

    // MARK: Live updates

    func remoteChanges() async -> AsyncStream<Void> {
        AsyncStream { continuation in
            listeners.append(listen(to: collection, yielding: continuation))
            listeners.append(listen(to: archiveCollection, yielding: continuation))
        }
    }

    /// `includeMetadataChanges` stays off, so a local write produces exactly one
    /// callback rather than a second when the server acknowledges it — which is
    /// what lets one noted path match one consumed echo.
    private func listen(
        to collection: CollectionReference,
        yielding continuation: AsyncStream<Void>.Continuation
    ) -> ListenerRegistration {
        var hasLoadedInitialSnapshot = false

        return collection.addSnapshotListener { [echoes] snapshot, error in
            guard let snapshot, error == nil else { return }

            // The first callback is just the collection's current contents,
            // which the sync at launch already covers.
            guard hasLoadedInitialSnapshot else {
                hasLoadedInitialSnapshot = true
                return
            }

            // Every change is consumed, not just those up to the first foreign
            // one — short-circuiting would leave our own echoes queued and make
            // the *next* change look foreign.
            var isFromAnotherDevice = false
            for change in snapshot.documentChanges {
                if change.document.metadata.hasPendingWrites { continue }
                if echoes.consume(change.document.reference.path) { continue }
                isFromAnotherDevice = true
            }

            if isFromAnotherDevice { continuation.yield() }
        }
    }
}

// MARK: - Mapping
//
// Lives here rather than on `Task`, for the same reason the Core Data mapping
// lives in the repository: the domain type stays free of its storage.

private nonisolated extension ArchivedTask {
    /// No `deletedAt`: an archived record isn't deleted, and the collection it
    /// sits in is what marks it archived.
    var firestoreData: [String: Any] {
        [
            "id": id.uuidString,
            "title": title,
            "description": description,
            "status": status.rawValue,
            "position": position,
            "createdAt": Timestamp(date: createdAt),
            "updatedAt": Timestamp(date: updatedAt),
            "archivedAt": Timestamp(date: archivedAt),
            "parentId": parentId?.uuidString as Any
        ]
    }

    init?(document: QueryDocumentSnapshot) {
        let data = document.data()
        guard let id = UUID(uuidString: document.documentID),
              let title = data["title"] as? String,
              let statusRaw = data["status"] as? String,
              let status = TaskStatus(rawValue: statusRaw),
              let createdAt = (data["createdAt"] as? Timestamp)?.dateValue(),
              let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue(),
              let archivedAt = (data["archivedAt"] as? Timestamp)?.dateValue()
        else { return nil }

        self.init(
            id: id,
            title: title,
            description: data["description"] as? String ?? "",
            status: status,
            position: data["position"] as? Double ?? 0,
            createdAt: createdAt,
            updatedAt: updatedAt,
            archivedAt: archivedAt,
            parentId: (data["parentId"] as? String).flatMap(UUID.init(uuidString:))
        )
    }
}

private nonisolated extension Task {
    /// `syncStatus` is deliberately absent — it describes this device's progress
    /// pushing the task, and means nothing to another client.
    var firestoreData: [String: Any] {
        [
            "id": id.uuidString,
            "title": title,
            "description": description,
            "status": status.rawValue,
            "position": position,
            "createdAt": Timestamp(date: createdAt),
            "updatedAt": Timestamp(date: updatedAt),
            "deletedAt": deletedAt.map { Timestamp(date: $0) } as Any,
            "parentId": parentId?.uuidString as Any
        ]
    }

    /// Returns nil for a document that can't be read as a task, so one malformed
    /// row doesn't fail the whole pull.
    init?(document: QueryDocumentSnapshot) {
        let data = document.data()
        guard let id = UUID(uuidString: document.documentID),
              let title = data["title"] as? String,
              let statusRaw = data["status"] as? String,
              let status = TaskStatus(rawValue: statusRaw),
              let createdAt = (data["createdAt"] as? Timestamp)?.dateValue(),
              let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()
        else { return nil }

        self.init(
            id: id,
            title: title,
            description: data["description"] as? String ?? "",
            status: status,
            position: data["position"] as? Double ?? 0,
            createdAt: createdAt,
            updatedAt: updatedAt,
            syncStatus: .synced,   // anything arriving from the server is, by definition
            deletedAt: (data["deletedAt"] as? Timestamp)?.dateValue(),
            parentId: (data["parentId"] as? String).flatMap(UUID.init(uuidString:))
        )
    }
}
#endif
