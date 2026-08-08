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
    private let collection: CollectionReference

    init(collectionPath: String = "tasks") {
        let firestore = Firestore.firestore()

        // Firestore's own offline queue is switched off deliberately. This app
        // already has an outbox; leaving both on means two queues replaying the
        // same writes under different conflict rules.
        let settings = firestore.settings
        settings.cacheSettings = MemoryCacheSettings()
        firestore.settings = settings

        collection = firestore.collection(collectionPath)
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
}

// MARK: - Mapping
//
// Lives here rather than on `Task`, for the same reason the Core Data mapping
// lives in the repository: the domain type stays free of its storage.

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
            "deletedAt": deletedAt.map { Timestamp(date: $0) } as Any
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
            deletedAt: (data["deletedAt"] as? Timestamp)?.dateValue()
        )
    }
}
#endif
