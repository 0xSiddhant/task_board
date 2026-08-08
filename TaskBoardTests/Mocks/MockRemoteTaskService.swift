//
//  MockRemoteTaskService.swift
//  TaskBoardTests
//
//  Created by Siddhant Kumar on 08/08/26.
//

import Foundation
@testable import TaskBoard

/// Same surface as `FakeRemoteTaskService`, but responses and errors are queued
/// per operation instead of injected at random, so a test can say "fail the next
/// create" and assert on exactly what the engine did afterwards.
actor MockRemoteTaskService: RemoteTaskService {
    enum Operation: String, Hashable {
        case fetch, create, update, delete
    }

    struct StubbedError: Error, Equatable {
        let label: String
    }

    private(set) var serverTasks: [UUID: Task] = [:]
    /// Every attempted call, in order — the record that proves a failed push
    /// stopped the queue instead of skipping ahead.
    private(set) var attempts: [Operation] = []

    private var queuedErrors: [Operation: [Error]] = [:]

    // MARK: Test control

    func seed(_ tasks: [Task]) {
        for task in tasks { serverTasks[task.id] = task }
    }

    func queueError(_ error: Error, for operation: Operation) {
        queuedErrors[operation, default: []].append(error)
    }

    func attempts(of operation: Operation) -> Int {
        attempts.filter { $0 == operation }.count
    }

    // MARK: RemoteTaskService

    func fetchTasks() async throws -> [Task] {
        try record(.fetch)
        return Array(serverTasks.values)
    }

    func create(_ task: Task) async throws {
        try record(.create)
        serverTasks[task.id] = task
    }

    func update(_ task: Task) async throws {
        try record(.update)
        serverTasks[task.id] = task
    }

    func delete(id: UUID) async throws {
        try record(.delete)
        serverTasks[id] = nil
    }

    /// Logs the attempt before throwing, so a failed call still counts as tried.
    private func record(_ operation: Operation) throws {
        attempts.append(operation)
        guard var errors = queuedErrors[operation], !errors.isEmpty else { return }
        let error = errors.removeFirst()
        queuedErrors[operation] = errors
        throw error
    }
}
