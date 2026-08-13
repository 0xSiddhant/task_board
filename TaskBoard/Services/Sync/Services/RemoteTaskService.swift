//
//  RemoteTaskService.swift
//  TaskBoard
//
//  Created by Siddhant Kumar on 08/08/26.
//

import Foundation

nonisolated protocol RemoteTaskService: Sendable {
    func fetchTasks() async throws -> [Task]
    func create(_ task: Task) async throws
    func update(_ task: Task) async throws
    func delete(_ task: Task) async throws

    // MARK: Archive
    //
    // Archived records live in their own collection, not behind a flag on the
    // task. Both calls move a record between the two and must do it atomically:
    // a record that briefly exists in neither collection would look deleted to
    // any device that pulled in between.

    func fetchArchived() async throws -> [ArchivedTask]
    func archive(_ archived: ArchivedTask) async throws
    func restore(_ task: Task) async throws
}

enum RemoteError: Error {
    case offline
    case injectedFailure
}

nonisolated struct RemoteDebugSettings: Equatable {
    var simulatedLatency: TimeInterval
    var forceOffline: Bool
    var failureRate: Double
}

/// Fault-injection knobs, deliberately kept off `RemoteTaskService` — a real
/// backend has no failure rate. Only test doubles conform, which lets the
/// composition root hold the protocol and still swap in a live implementation.
nonisolated protocol RemoteTaskDebugControls: Sendable {
    func debugSettings() async -> RemoteDebugSettings
    func setSimulatedLatency(_ value: TimeInterval) async
    func setForceOffline(_ value: Bool) async
    func setFailureRate(_ value: Double) async
}
