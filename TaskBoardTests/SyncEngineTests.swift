//
//  SyncEngineTests.swift
//  TaskBoardTests
//
//  Created by Siddhant Kumar on 08/08/26.
//

import Testing
import Foundation
@testable import TaskBoard

@MainActor
struct SyncEngineTests {

    /// Fixed clock so `updatedAt` ordering is deliberate rather than incidental.
    private let base = Date(timeIntervalSince1970: 1_000_000)

    private func makeSubject() -> (SyncEngine, MockTaskRepository, MockRemoteTaskService) {
        let repository = MockTaskRepository()
        let remote = MockRemoteTaskService()
        return (SyncEngine(repository: repository, remote: remote), repository, remote)
    }

    private func task(
        id: UUID = UUID(),
        title: String,
        updatedAt: Date,
        status: TaskStatus = .todo,
        syncStatus: SyncStatus = .pending,
        deletedAt: Date? = nil
    ) -> Task {
        Task(
            id: id,
            title: title,
            description: "",
            status: status,
            position: 0,
            createdAt: base,
            updatedAt: updatedAt,
            syncStatus: syncStatus,
            deletedAt: deletedAt
        )
    }

    // MARK: No conflict

    @Test func matchingBaseVersionPushesCleanly() async {
        let (engine, repository, remote) = makeSubject()
        repository.now = { self.base }

        let created = repository.createTask(title: "A", description: "")
        #expect(repository.pendingOutboxEntries().count == 1)

        await engine.sync()

        #expect(repository.pendingOutboxEntries().isEmpty)
        #expect(repository.fetchTask(id: created.id)?.syncStatus == .synced)
        #expect(await remote.attempts(of: .create) == 1)
        #expect(await remote.serverTasks[created.id]?.title == "A")
    }

    @Test func remoteChangeWithNoQueuedWriteIsAppliedLocally() async {
        let (engine, repository, remote) = makeSubject()
        let incoming = task(title: "from another device", updatedAt: base, syncStatus: .synced)
        await remote.seed([incoming])

        await engine.sync()

        #expect(repository.fetchTask(id: incoming.id)?.title == "from another device")
        #expect(repository.fetchTask(id: incoming.id)?.syncStatus == .synced)
        #expect(await remote.attempts(of: .create) == 0)
    }

    // MARK: Conflict, server wins

    @Test func serverNewerThanLocalDiscardsTheLocalEditWithoutPushing() async {
        let (engine, repository, remote) = makeSubject()

        // Local task edited at base+10, queued against base.
        let id = UUID()
        repository.seed(task(id: id, title: "local", updatedAt: base, syncStatus: .synced))
        repository.now = { self.base.addingTimeInterval(10) }
        _ = repository.updateTask(id: id, title: "local edit", description: nil)

        // Server moved further still, at base+100.
        await remote.seed([task(id: id, title: "server", updatedAt: base.addingTimeInterval(100))])

        await engine.sync()

        #expect(repository.fetchTask(id: id)?.title == "server")
        #expect(repository.fetchTask(id: id)?.syncStatus == .synced)
        #expect(repository.pendingOutboxEntries().isEmpty)
        // The discarded edit was never sent.
        #expect(await remote.attempts(of: .update) == 0)
        #expect(await remote.serverTasks[id]?.title == "server")
    }

    // MARK: Conflict, local wins

    @Test func localNewerThanServerPushesDespiteStaleBaseVersion() async {
        let (engine, repository, remote) = makeSubject()

        let id = UUID()
        repository.seed(task(id: id, title: "local", updatedAt: base, syncStatus: .synced))
        repository.now = { self.base.addingTimeInterval(100) }
        _ = repository.updateTask(id: id, title: "local edit", description: nil)

        // Server moved after the base version, but before the local edit — a real
        // conflict that last-write-wins resolves our way.
        await remote.seed([task(id: id, title: "server", updatedAt: base.addingTimeInterval(10))])

        await engine.sync()

        #expect(repository.fetchTask(id: id)?.title == "local edit")
        #expect(repository.fetchTask(id: id)?.syncStatus == .synced)
        #expect(repository.pendingOutboxEntries().isEmpty)
        #expect(await remote.attempts(of: .update) == 1)
        #expect(await remote.serverTasks[id]?.title == "local edit")
    }

    // MARK: Failed push

    @Test func failedPushKeepsTheEntryAndStopsTheQueue() async {
        let (engine, repository, remote) = makeSubject()
        repository.now = { self.base }

        let first = repository.createTask(title: "A", description: "")
        let second = repository.createTask(title: "B", description: "")
        #expect(repository.pendingOutboxEntries().count == 2)

        await remote.queueError(MockRemoteTaskService.StubbedError(label: "boom"), for: .create)

        await engine.sync()

        #expect(repository.pendingOutboxEntries().count == 2)
        #expect(repository.fetchTask(id: first.id)?.syncStatus == .failed)
        // The second entry was never attempted — the queue stops, it doesn't skip.
        #expect(await remote.attempts(of: .create) == 1)
        #expect(repository.fetchTask(id: second.id)?.syncStatus == .pending)
        #expect(await remote.serverTasks.isEmpty)
    }

    @Test func failedPullLeavesTheQueueCompletelyUntouched() async {
        let (engine, repository, remote) = makeSubject()
        repository.now = { self.base }

        let created = repository.createTask(title: "A", description: "")
        await remote.queueError(MockRemoteTaskService.StubbedError(label: "offline"), for: .fetch)

        await engine.sync()

        #expect(repository.pendingOutboxEntries().count == 1)
        // Not even marked failed — nothing was attempted after the pull died.
        #expect(repository.fetchTask(id: created.id)?.syncStatus == .pending)
        #expect(await remote.attempts(of: .create) == 0)
    }

    @Test func recoversOnTheNextSyncAfterAFailure() async {
        let (engine, repository, remote) = makeSubject()
        repository.now = { self.base }

        let created = repository.createTask(title: "A", description: "")
        await remote.queueError(MockRemoteTaskService.StubbedError(label: "boom"), for: .create)

        await engine.sync()
        #expect(repository.fetchTask(id: created.id)?.syncStatus == .failed)

        // Only one error was queued, so the retry succeeds.
        await engine.sync()

        #expect(repository.pendingOutboxEntries().isEmpty)
        #expect(repository.fetchTask(id: created.id)?.syncStatus == .synced)
        #expect(await remote.attempts(of: .create) == 2)
    }

    // MARK: Delete

    @Test func deleteHardDeletesOnlyAfterTheRemoteAcknowledges() async {
        let (engine, repository, remote) = makeSubject()
        repository.now = { self.base }

        let created = repository.createTask(title: "A", description: "")
        await engine.sync()

        repository.deleteTask(id: created.id)
        #expect(repository.fetchTask(id: created.id)?.deletedAt != nil)

        // First attempt fails: the row must survive so the delete stays replayable.
        await remote.queueError(MockRemoteTaskService.StubbedError(label: "boom"), for: .delete)
        await engine.sync()

        #expect(repository.fetchTask(id: created.id) != nil)
        #expect(repository.pendingOutboxEntries().count == 1)

        await engine.sync()

        #expect(repository.fetchTask(id: created.id) == nil)
        #expect(repository.pendingOutboxEntries().isEmpty)
        #expect(await remote.serverTasks.isEmpty)
    }

    // MARK: Timeouts
    //
    // A backend that neither answers nor errors must not hang the engine — that
    // is exactly what a misconfigured Firestore does, since it retries a rejected
    // write stream indefinitely instead of failing.

    @Test func aPullThatNeverAnswersTimesOutAndLeavesTheQueueIntact() async {
        let repository = MockTaskRepository()
        let remote = MockRemoteTaskService()
        let engine = SyncEngine(repository: repository, remote: remote, timeout: 0.2)
        repository.now = { self.base }

        let created = repository.createTask(title: "A", description: "")
        await remote.setDelay(30, for: .fetch)

        await engine.sync()

        #expect(repository.pendingOutboxEntries().count == 1)
        #expect(repository.fetchTask(id: created.id)?.syncStatus == .pending)
        #expect(await remote.attempts(of: .create) == 0)
    }

    @Test func aPushThatNeverAnswersMarksFailedAndKeepsTheEntry() async {
        let repository = MockTaskRepository()
        let remote = MockRemoteTaskService()
        let engine = SyncEngine(repository: repository, remote: remote, timeout: 0.2)
        repository.now = { self.base }

        let first = repository.createTask(title: "A", description: "")
        _ = repository.createTask(title: "B", description: "")
        await remote.setDelay(30, for: .create)

        await engine.sync()

        #expect(repository.pendingOutboxEntries().count == 2)
        #expect(repository.fetchTask(id: first.id)?.syncStatus == .failed)
        // Stopped at the stalled entry rather than running the whole queue into
        // one timeout after another.
        #expect(await remote.attempts(of: .create) == 1)
    }

    @Test func aCallThatAnswersInTimeIsUnaffected() async {
        let repository = MockTaskRepository()
        let remote = MockRemoteTaskService()
        let engine = SyncEngine(repository: repository, remote: remote, timeout: 2)
        repository.now = { self.base }

        let created = repository.createTask(title: "A", description: "")
        await remote.setDelay(0.05, for: .create)

        await engine.sync()

        #expect(repository.pendingOutboxEntries().isEmpty)
        #expect(repository.fetchTask(id: created.id)?.syncStatus == .synced)
    }

    // MARK: hasConflict

    @Test func hasConflictComparesServerAgainstTheBaseVersion() async {
        let (engine, _, _) = makeSubject()

        #expect(await engine.hasConflict(baseUpdatedAt: base, serverUpdatedAt: base.addingTimeInterval(1)))
        #expect(await engine.hasConflict(baseUpdatedAt: base, serverUpdatedAt: base) == false)
        #expect(await engine.hasConflict(baseUpdatedAt: base, serverUpdatedAt: base.addingTimeInterval(-1)) == false)
    }
}
