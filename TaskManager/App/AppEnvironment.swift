//
//  AppEnvironment.swift
//  TaskManager
//
//  Created by Siddhant Kumar on 08/08/26.
//

import Combine
import Foundation

/// Composition root. Owns the object graph and the one place that decides which
/// banner is showing — that decision deliberately lives here rather than inside
/// StatusBanner, which stays pure presentation.
@MainActor
final class AppEnvironment: ObservableObject {
    @Published private(set) var banner: BannerMessage?

    let taskUseCases: TaskUseCases
    let networkMonitor = NetworkMonitor()
    let remote: FakeRemoteTaskService

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

        // dropFirst so the initial `.online` value at launch doesn't fire the
        // "back online" banner at someone who never went offline.
        networkMonitor.$status
            .dropFirst()
            .removeDuplicates()
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
            // Reconnecting almost always triggers a sync, so showing "back
            // online" and then "all synced" a moment later reads as a flicker.
            // Whether anything was queued at this instant decides which one wins.
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
