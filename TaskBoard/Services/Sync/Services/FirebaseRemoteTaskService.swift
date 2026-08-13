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

    func delete(_ task: Task) async throws {
        try await collection.document(task.id.uuidString).setData(task.tombstone.firestoreData)
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
        let batch = firestore.batch()
        batch.setData(archived.firestoreData, forDocument: archiveCollection.document(archived.id.uuidString))
        batch.deleteDocument(collection.document(archived.id.uuidString))
        try await batch.commit()
    }

    func restore(_ task: Task) async throws {
        let batch = firestore.batch()
        batch.setData(task.firestoreData, forDocument: collection.document(task.id.uuidString))
        batch.deleteDocument(archiveCollection.document(task.id.uuidString))
        try await batch.commit()
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
