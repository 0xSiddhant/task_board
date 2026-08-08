//
//  FakeRemoteTaskService.swift
//  TaskBoard
//
//  Created by Siddhant Kumar on 08/08/26.
//

import Foundation

/// The default backend, used whenever no Firebase project is configured — which
/// includes every fresh clone, since GoogleService-Info.plist is gitignored. The
/// knobs also make the offline and failure paths reachable without unplugging
/// anything.
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

    func delete(_ task: Task) async throws {
        try await simulateRoundTrip()
        storage[task.id] = task.tombstone
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
