//
//  AppEnvironment.swift
//  TaskManager
//
//  Created by Siddhant Kumar on 08/08/26.
//

import Combine
import Foundation

/// Composition root, and the single place that decides which banner is showing.
@MainActor
final class AppEnvironment: ObservableObject {
    @Published private(set) var banner: BannerMessage?

    let taskUseCases: TaskUseCases
    let networkMonitor = NetworkMonitor()
    let remote: FakeRemoteTaskService
    /// No-op by default so the app runs with no Firebase project configured.
    let logUploadService: LogUploadService = NoOpLogUploadService()

    private let stack: CoreDataStack
    private let repository: TaskRepositoryImpl
    private let syncEngine: SyncEngine

    private var cancellables = Set<AnyCancellable>()
    private var dismissTask: _Concurrency.Task<Void, Never>?

    init(inMemory: Bool = false) {
        stack = CoreDataStack(inMemory: inMemory)
        repository = TaskRepositoryImpl(stack: stack)
        remote = FakeRemoteTaskService()
        taskUseCases = TaskUseCases(repository: repository)
        syncEngine = SyncEngine(repository: repository, remote: remote)

        // statusChanges rather than $status: it only fires for fluctuations during
        // the session, so opening the app with no connection shows nothing.
        networkMonitor.statusChanges
            .sink { [weak self] status in
                self?.connectivityChanged(to: status)
            }
            .store(in: &cancellables)
    }

    func start() {
        _Concurrency.Task { await syncEngine.sync() }
    }

    // MARK: Banner

    private func connectivityChanged(to status: NetworkMonitor.Status) {
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
