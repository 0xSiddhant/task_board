//
//  SettingsViewModel.swift
//  TaskManager
//
//  Created by Siddhant Kumar on 08/08/26.
//

import Combine
import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    enum UploadState: Equatable {
        case idle
        case uploading
        case success
        case failed(String)
    }

    @Published var forceOffline = false
    @Published var failureRate: Double = 0
    @Published var simulatedLatency: TimeInterval = 0.3

    @Published private(set) var uploadState: UploadState = .idle

    private let remote: FakeRemoteTaskService
    private let uploadService: LogUploadService

    private var cancellables = Set<AnyCancellable>()
    /// Set while `load()` seeds the published values from the actor, so pulling
    /// state in doesn't immediately push the same values back out.
    private var isLoading = false

    init(remote: FakeRemoteTaskService, uploadService: LogUploadService) {
        self.remote = remote
        self.uploadService = uploadService

        $forceOffline
            .dropFirst()
            .sink { [weak self] value in
                guard let self, !self.isLoading else { return }
                _Concurrency.Task { await self.remote.setForceOffline(value) }
            }
            .store(in: &cancellables)

        $failureRate
            .dropFirst()
            .sink { [weak self] value in
                guard let self, !self.isLoading else { return }
                _Concurrency.Task { await self.remote.setFailureRate(value) }
            }
            .store(in: &cancellables)

        $simulatedLatency
            .dropFirst()
            .sink { [weak self] value in
                guard let self, !self.isLoading else { return }
                _Concurrency.Task { await self.remote.setSimulatedLatency(value) }
            }
            .store(in: &cancellables)
    }

    /// Reads the knobs back out of the actor so the screen opens showing what's
    /// actually in effect rather than the defaults.
    func load() async {
        isLoading = true
        forceOffline = await remote.forceOffline
        failureRate = await remote.failureRate
        simulatedLatency = await remote.simulatedLatency
        isLoading = false
    }

    // MARK: Log upload

    func uploadLogs() async {
        uploadState = .uploading

        let data = await Logger.shared.exportData()
        do {
            try await uploadService.upload(logData: data, metadata: .current())
            // Only here — resetting before a confirmed upload would discard logs
            // that never made it anywhere.
            await Logger.shared.reset()
            uploadState = .success
        } catch {
            uploadState = .failed(error.localizedDescription)
        }
    }
}
