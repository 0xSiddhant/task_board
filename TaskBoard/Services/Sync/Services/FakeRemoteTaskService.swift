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

    func fetchTasks() async throws -> [Task] {
        Array(storage.values)
    }

    func create(_ task: Task) async throws {
        storage[task.id] = task
    }

    func update(_ task: Task) async throws {
        storage[task.id] = task
    }

    func delete(_ task: Task) async throws {
        storage[task.id] = task.tombstone
    }
}
