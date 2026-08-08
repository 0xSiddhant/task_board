//
//  SimulatedFaultsRemoteService.swift
//  TaskBoard
//
//  Created by Siddhant Kumar on 08/08/26.
//

import Foundation

/// Adds latency, forced-offline, and random-failure injection on top of whatever
/// backend it wraps.
///
/// These knobs used to live inside `FakeRemoteTaskService`, which meant that
/// configuring a real Firebase project silently removed the only way to exercise
/// the offline queue and the retry path — the paths most worth testing against a
/// real backend. Wrapping instead of embedding keeps them available either way.
actor SimulatedFaultsRemoteService: RemoteTaskService, RemoteTaskDebugControls {
    private let wrapped: RemoteTaskService

    private var simulatedLatency: TimeInterval
    private var forceOffline = false
    private var failureRate: Double = 0

    init(wrapping wrapped: RemoteTaskService, simulatedLatency: TimeInterval = 0) {
        self.wrapped = wrapped
        self.simulatedLatency = simulatedLatency
    }

    // MARK: RemoteTaskDebugControls

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
        try await simulate()
        return try await wrapped.fetchTasks()
    }

    func create(_ task: Task) async throws {
        try await simulate()
        try await wrapped.create(task)
    }

    func update(_ task: Task) async throws {
        try await simulate()
        try await wrapped.update(task)
    }

    func delete(_ task: Task) async throws {
        try await simulate()
        try await wrapped.delete(task)
    }

    /// Latency before failure, so a failing call still costs time and the pending
    /// state stays visible. Throwing here means the wrapped backend is never
    /// reached — an injected outage looks like a real one.
    private func simulate() async throws {
        if simulatedLatency > 0 {
            try? await _Concurrency.Task.sleep(nanoseconds: UInt64(simulatedLatency * 1_000_000_000))
        }
        if forceOffline { throw RemoteError.offline }
        if failureRate > 0, Double.random(in: 0..<1) < failureRate { throw RemoteError.injectedFailure }
    }
}
