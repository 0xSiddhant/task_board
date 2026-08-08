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

    private let stack: CoreDataStack
    private let repository: CoreDataTaskRepository
    private let syncEngine: SyncEngine

    private var cancellables = Set<AnyCancellable>()
    private var dismissTask: _Concurrency.Task<Void, Never>?

    init(inMemory: Bool = false) {
        stack = CoreDataStack(inMemory: inMemory)
        repository = CoreDataTaskRepository(stack: stack)
        taskUseCases = TaskUseCases(repository: repository)

        let usesFirebase = FirebaseBootstrap.isConfigured

        #if canImport(FirebaseFirestore)
        if usesFirebase {
            remote = FirebaseRemoteTaskService()
            remoteDebugControls = nil   // a real backend has no fault-injection knobs
        } else {
            let fake = FakeRemoteTaskService()
            remote = fake
            remoteDebugControls = fake
        }
        #else
        let fake = FakeRemoteTaskService()
        remote = fake
        remoteDebugControls = fake
        #endif

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

        let reporter = Self.makeCrashReporter(usesFirebase: usesFirebase)
        _Concurrency.Task { await Logger.shared.attach(crashReporter: reporter) }
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
        Logger.record("App started, backend: \(remoteDebugControls == nil ? "Firebase" : "in-memory fake")")
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
