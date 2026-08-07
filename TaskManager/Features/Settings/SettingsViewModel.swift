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

    private let controls: RemoteTaskDebugControls?
    private let uploadService: LogUploadService

    private var cancellables = Set<AnyCancellable>()
    /// Set while `load()` seeds these values, so pulling state in doesn't
    /// immediately push it back out.
    private var isLoading = false

    /// `controls` is nil against a real backend, which has no knobs to expose.
    var canConfigureBackend: Bool { controls != nil }

    init(controls: RemoteTaskDebugControls?, uploadService: LogUploadService) {
        self.controls = controls
        self.uploadService = uploadService

        $forceOffline
            .dropFirst()
            .sink { [weak self] value in
                guard let self, !self.isLoading else { return }
                _Concurrency.Task { await self.controls?.setForceOffline(value) }
            }
            .store(in: &cancellables)

        $failureRate
            .dropFirst()
            .sink { [weak self] value in
                guard let self, !self.isLoading else { return }
                _Concurrency.Task { await self.controls?.setFailureRate(value) }
            }
            .store(in: &cancellables)

        $simulatedLatency
            .dropFirst()
            .sink { [weak self] value in
                guard let self, !self.isLoading else { return }
                _Concurrency.Task { await self.controls?.setSimulatedLatency(value) }
            }
            .store(in: &cancellables)
    }

    func load() async {
        guard let settings = await controls?.debugSettings() else { return }
        isLoading = true
        forceOffline = settings.forceOffline
        failureRate = settings.failureRate
        simulatedLatency = settings.simulatedLatency
        isLoading = false
    }

    // MARK: Log upload

    func uploadLogs() async {
        uploadState = .uploading

        let data = await Logger.shared.exportData()
        do {
            try await uploadService.upload(logData: data, metadata: .current())
            // Only after a confirmed upload — resetting earlier discards logs
            // that never made it anywhere.
            await Logger.shared.reset()
            uploadState = .success
        } catch {
            // After the reset above would be pointless; this one survives.
            Logger.record("Log upload failed: \(error)", level: .error)
            uploadState = .failed(error.localizedDescription)
        }
    }
}
