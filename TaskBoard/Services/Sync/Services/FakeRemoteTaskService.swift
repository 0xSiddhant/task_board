//
//  FakeRemoteTaskService.swift
//  TaskBoard
//
//  Created by Siddhant Kumar on 08/08/26.
//

import Foundation

/// The default backend, used whenever no Firebase project is configured — which
/// includes every fresh clone, since GoogleService-Info.plist is gitignored.
///
/// Deliberately a plain in-memory store with no knobs: fault injection lives in
/// `SimulatedFaultsRemoteService` so it applies to a real backend too.
actor FakeRemoteTaskService: RemoteTaskService {
    private var storage: [UUID: Task] = [:]
    /// The stand-in for the second collection, kept separate for the same reason
    /// it is separate in Firestore.
    private var archiveStorage: [UUID: ArchivedTask] = [:]

    func fetchTasks() async throws -> [Task] {
        Array(storage.values)
    }

    func create(_ task: Task) async throws {
        storage[task.id] = task
    }

    func update(_ task: Task) async throws {
        storage[task.id] = task
    }

    /// Clears the archive copy too — a delete outranks an archive.
    func delete(_ task: Task) async throws {
        storage[task.id] = task.tombstone
        archiveStorage[task.id] = nil
    }

    // MARK: Archive

    func fetchArchived() async throws -> [ArchivedTask] {
        Array(archiveStorage.values)
    }

    /// Both sides in one step, matching the batched write the Firestore
    /// implementation uses.
    func archive(_ archived: ArchivedTask) async throws {
        archiveStorage[archived.id] = archived
        storage[archived.id] = nil
    }

    func restore(_ task: Task) async throws {
        storage[task.id] = task
        archiveStorage[task.id] = nil
    }
}
