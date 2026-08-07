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

/// The default backend. In-memory, so the app builds and runs with no external
/// configuration — and the knobs make the offline and failure paths reachable
/// without unplugging anything.
actor FakeRemoteTaskService: RemoteTaskService {
    private var storage: [UUID: Task] = [:]

    private(set) var simulatedLatency: TimeInterval = 0.3
    private(set) var forceOffline = false
    private(set) var failureRate: Double = 0

    // Settable rather than public `var`s because actor state can't be assigned
    // from outside the actor. Settings (plan 06) calls these.
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

    /// Latency first, then failure — a call that fails still costs time, which is
    /// what makes the pending state visible in the UI.
    private func simulateRoundTrip() async throws {
        if simulatedLatency > 0 {
            try? await _Concurrency.Task.sleep(nanoseconds: UInt64(simulatedLatency * 1_000_000_000))
        }
        if forceOffline { throw RemoteError.offline }
        if failureRate > 0, Double.random(in: 0..<1) < failureRate { throw RemoteError.injectedFailure }
    }
}
