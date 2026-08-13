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
actor FirebaseRemoteTaskService: RemoteTaskService {
    private let firestore: Firestore
    private let collection: CollectionReference
    private let archiveCollection: CollectionReference

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
        try await collection.document(task.id.uuidString).setData(task.firestoreData)
    }

    func update(_ task: Task) async throws {
        try await collection.document(task.id.uuidString).setData(task.firestoreData, merge: true)
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
    /// one batch, so the record is never in both or neither.
    private func commitAcrossBothCollections(
        id: UUID,
        _ build: (WriteBatch, DocumentReference, DocumentReference) -> Void
    ) async throws {
        let batch = firestore.batch()
        build(batch, collection.document(id.uuidString), archiveCollection.document(id.uuidString))
        try await batch.commit()
    }

    // MARK: Live updates

    /// Buffers the newest signal only. The payload is empty, so ten changes
    /// arriving during one sync mean the same thing as one: pull again.
    func remoteChanges() async -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            listeners.append(listen(to: collection, yielding: continuation))
            listeners.append(listen(to: archiveCollection, yielding: continuation))
        }
    }

    /// Our own writes are filtered by `hasPendingWrites` alone.
    ///
    /// `includeMetadataChanges` stays off, so a local write raises exactly one
    /// callback — the latency-compensated one, before the server acknowledges,
    /// where that flag is true. The acknowledgement changes only metadata and
    /// raises nothing. So a local write is never seen with the flag clear, and
    /// anything reaching us without it came from somewhere else.
    private func listen(
        to collection: CollectionReference,
        yielding continuation: AsyncStream<Void>.Continuation
    ) -> ListenerRegistration {
        var hasLoadedInitialSnapshot = false
        let path = collection.path

        return collection.addSnapshotListener { snapshot, error in
            if let error {
                // Firestore tears a listener down on a permissions failure and
                // it does not come back, which would silently end live updates.
                // Worth a line in the log rather than a mystery.
                Logger.record("Snapshot listener on \(path) failed: \(error)", level: .error)
                return
            }
            guard let snapshot else { return }

            // The first callback is just the collection's current contents,
            // which the sync at launch already covers.
            guard hasLoadedInitialSnapshot else {
                hasLoadedInitialSnapshot = true
                return
            }

            let isFromAnotherDevice = snapshot.documentChanges.contains {
                !$0.document.metadata.hasPendingWrites
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
