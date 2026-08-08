//
//  NetworkMonitor.swift
//  TaskBoard
//
//  Created by Siddhant Kumar on 08/08/26.
//

import Network
import Combine

@MainActor
final class NetworkMonitor: ObservableObject {
    enum Status: Equatable {
        case online
        case offline
    }

    @Published private(set) var status: Status = .online

    /// Emits only for changes during the session. The first real path update sets
    /// the baseline silently, so launching offline is a starting condition rather
    /// than something that just happened.
    let statusChanges = PassthroughSubject<Status, Never>()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    // Qualified because the domain's `Task` model shadows the concurrency type here.
    private var debounceTask: _Concurrency.Task<Void, Never>?
    /// `status` starts at `.online` as a placeholder, before NWPathMonitor has
    /// reported anything.
    private var hasBaseline = false

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let newStatus: Status = path.status == .satisfied ? .online : .offline
            _Concurrency.Task { @MainActor in
                self?.handle(newStatus)
            }
        }
        monitor.start(queue: queue)
    }

    private func handle(_ newStatus: Status) {
        guard hasBaseline else {
            hasBaseline = true
            status = newStatus   // silent: nothing changed, we just found out where we started
            return
        }

        guard newStatus != status else { return }
        debounceTask?.cancel()

        if newStatus == .offline {
            // Debounced so a brief wifi/cellular handoff doesn't flash the banner.
            // Coming back online is reported instantly.
            debounceTask = _Concurrency.Task { [weak self] in
                try? await _Concurrency.Task.sleep(nanoseconds: 500_000_000)
                guard !_Concurrency.Task.isCancelled else { return }
                self?.publish(.offline)
            }
        } else {
            publish(.online)
        }
    }

    private func publish(_ newStatus: Status) {
        status = newStatus
        statusChanges.send(newStatus)
    }

    deinit {
        monitor.cancel()
    }
}
