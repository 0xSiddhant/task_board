//
//  RemoteTaskService.swift
//  TaskManager
//
//  Created by Siddhant Kumar on 08/08/26.
//

import Foundation

protocol RemoteTaskService {
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

/// The default backend. In-memory, so the app runs with no external
/// configuration, and the knobs make the offline and failure paths reachable.
actor FakeRemoteTaskService: RemoteTaskService, RemoteTaskDebugControls {
    private var storage: [UUID: Task] = [:]

    private(set) var simulatedLatency: TimeInterval = 0.3
    private(set) var forceOffline = false
    private(set) var failureRate: Double = 0

    // MARK: RemoteTaskDebugControls

    // Methods rather than settable `var`s: actor state can't be assigned from
    // outside the actor.
    func debugSettings() -> RemoteDebugSettings {
        RemoteDebugSettings(
            simulatedLatency: simulatedLatency,
            forceOffline: forceOffline,
            failureRate: failureRate
        )
    }

    func setSimulatedLatency(_ value: TimeInterval) { simulatedLatency = value }
    func setForceOffline(_ value: Bool) { forceOffline = value }
    func setFailureRate(_ value: Double) { failureRate = min(max(value, 0), 1) }

    // MARK: RemoteTaskService

    func fetchTasks() async throws -> [Task] {
        try await simulateRoundTrip()
        return Array(storage.values)
    }

    func create(_ task: Task) async throws {
        try await simulateRoundTrip()
        storage[task.id] = task
    }

    func update(_ task: Task) async throws {
        try await simulateRoundTrip()
        storage[task.id] = task
    }

    func delete(id: UUID) async throws {
        try await simulateRoundTrip()
        storage[id] = nil
    }

    // MARK: Simulation

    /// Latency before failure, so a failing call still costs time and the pending
    /// state stays visible.
    private func simulateRoundTrip() async throws {
        if simulatedLatency > 0 {
            try? await _Concurrency.Task.sleep(nanoseconds: UInt64(simulatedLatency * 1_000_000_000))
        }
        if forceOffline { throw RemoteError.offline }
        if failureRate > 0, Double.random(in: 0..<1) < failureRate { throw RemoteError.injectedFailure }
    }
}
