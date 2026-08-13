//
//  AppEnvironment.swift
//  TaskBoard
//
//  Created by Siddhant Kumar on 08/08/26.
//

import Combine
import Foundation
import UIKit

/// Composition root, and the single place that decides which banner is showing.
@MainActor
final class AppEnvironment: ObservableObject {
    @Published private(set) var banner: BannerMessage?

    let taskUseCases: TaskUseCases
    let networkMonitor = NetworkMonitor()
    let remote: RemoteTaskService
    /// Non-nil only when the backend is a test double, so Settings can hide its
    /// fault-injection controls against a real one.
    let remoteDebugControls: RemoteTaskDebugControls?
    let logUploadService: LogUploadService
    let syncPolicy = SyncPolicy()

    private let backendName: String
    private let stack: CoreDataStack
    private let repository: CoreDataTaskRepository
    private let syncEngine: SyncEngine

    private var cancellables = Set<AnyCancellable>()
    private var dismissTask: _Concurrency.Task<Void, Never>?
    private var remoteChangeTask: _Concurrency.Task<Void, Never>?

    init(inMemory: Bool = false) {
        stack = CoreDataStack(inMemory: inMemory)
        repository = CoreDataTaskRepository(stack: stack)
        taskUseCases = TaskUseCases(repository: repository)

        let usesFirebase = FirebaseBootstrap.isConfigured
        backendName = usesFirebase ? "Firebase" : "in-memory fake"

        let backend: RemoteTaskService
        #if canImport(FirebaseFirestore)
        backend = usesFirebase ? FirebaseRemoteTaskService() : FakeRemoteTaskService()
        #else
        backend = FakeRemoteTaskService()
        #endif

        let simulated = SimulatedFaultsRemoteService(
            wrapping: backend,
            simulatedLatency: usesFirebase ? 0 : 0.3
        )
        remote = simulated
        remoteDebugControls = simulated

        logUploadService = usesFirebase ? FirebaseLogUploadService() : NoOpLogUploadService()
        syncEngine = SyncEngine(repository: repository, remote: remote)

        // statusChanges rather than $status: it only fires for fluctuations during
        // the session, so opening the app with no connection shows nothing.
        networkMonitor.statusChanges
            .sink { [weak self] status in
                self?.connectivityChanged(to: status)
            }
            .store(in: &cancellables)

        // This does fire during launch as well as on a real foreground, so it
        // overlaps the sync `start()` kicks off. SyncEngine drops the duplicate.
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                Logger.record("Returned to foreground, syncing")
                _Concurrency.Task { await self?.syncNow() }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { _ in
                BackgroundSync.schedule()
            }
            .store(in: &cancellables)

        // The queue depth, not the task list. A failed push marks the task
        // `.failed`, which changes the task but not the queue — keying off tasks
        // would re-trigger on that write and retry in a loop.
        repository.pendingOutboxCountPublisher()
            .debounce(for: .milliseconds(400), scheduler: DispatchQueue.main)
            .sink { [weak self] pending in
                self?.syncIfQueueHasBuiltUp(pending: pending)
            }
            .store(in: &cancellables)

        // The sixth trigger, and the only one that isn't about this device: the
        // backend reporting that another device wrote something. Our own pushes
        // are filtered out inside the remote service, so a local sync doesn't
        // feed itself. `SyncEngine` drops overlapping syncs, so a signal that
        // lands mid-sync is ignored rather than queued.
        let remote = self.remote
        remoteChangeTask = _Concurrency.Task { [weak self] in
            for await _ in await remote.remoteChanges() {
                Logger.record("Another device changed the backend, syncing")
                await self?.syncNow()
            }
        }

        let reporter = Self.makeCrashReporter(usesFirebase: usesFirebase)
        _Concurrency.Task { await Logger.shared.attach(crashReporter: reporter) }
    }

    deinit {
        remoteChangeTask?.cancel()
    }

    /// The trigger that covers someone working continuously in the foreground,
    /// who never hits launch, reconnect, foreground, or background refresh.
    private func syncIfQueueHasBuiltUp(pending: Int) {
        guard pending >= syncPolicy.pendingThreshold else { return }

        Logger.record("Outbox reached \(pending) pending, threshold is \(syncPolicy.pendingThreshold) — syncing")
        _Concurrency.Task { await syncNow() }
    }

    /// The one entry point for a sync from outside — used by the foreground
    /// observer and by the background task handler.
    func syncNow() async {
        await syncEngine.sync()
    }

    private static func makeCrashReporter(usesFirebase: Bool) -> CrashReporter {
        #if canImport(FirebaseCrashlytics)
        if usesFirebase { return FirebaseCrashReporter() }
        #endif
        return NoOpCrashReporter()
    }

    func start() {
        Logger.record("App started, backend: \(backendName)")
        _Concurrency.Task { await syncEngine.sync() }
    }

    // MARK: Banner

    private func connectivityChanged(to status: NetworkMonitor.Status) {
        Logger.record("Connectivity changed to \(status)", level: .warning)

        switch status {
        case .offline:
            show(.offline)

        case .online:
            // Reconnecting triggers a sync, so showing "back online" and then
            // "all synced" a moment later reads as a flicker. Only one fires.
            let hadPendingWork = !repository.pendingOutboxEntries().isEmpty
            if !hadPendingWork { show(.backOnline) }

            _Concurrency.Task { [weak self] in
                guard let self else { return }
                await self.syncEngine.sync()
                if hadPendingWork { self.show(.syncSuccess) }
            }
        }
    }

    private func show(_ message: BannerMessage) {
        dismissTask?.cancel()
        banner = message

        guard let interval = message.autoDismissAfter else { return }
        dismissTask = _Concurrency.Task { [weak self] in
            try? await _Concurrency.Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            guard !_Concurrency.Task.isCancelled else { return }
            self?.banner = nil
        }
    }
}
