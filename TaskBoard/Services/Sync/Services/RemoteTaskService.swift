//
//  RemoteTaskService.swift
//  TaskBoard
//
//  Created by Siddhant Kumar on 08/08/26.
//

import Foundation

protocol RemoteTaskService: Sendable {
    func fetchTasks() async throws -> [Task]
    func create(_ task: Task) async throws
    func update(_ task: Task) async throws
    func delete(id: UUID) async throws
}

enum RemoteError: Error {
    case offline
    case injectedFailure
}

struct RemoteDebugSettings: Equatable {
    var simulatedLatency: TimeInterval
    var forceOffline: Bool
    var failureRate: Double
}

/// Fault-injection knobs, deliberately kept off `RemoteTaskService` — a real
/// backend has no failure rate. Only test doubles conform, which lets the
/// composition root hold the protocol and still swap in a live implementation.
protocol RemoteTaskDebugControls: Sendable {
    func debugSettings() async -> RemoteDebugSettings
    func setSimulatedLatency(_ value: TimeInterval) async
    func setForceOffline(_ value: Bool) async
    func setFailureRate(_ value: Double) async
}
