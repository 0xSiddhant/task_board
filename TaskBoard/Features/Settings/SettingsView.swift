//
//  SettingsView.swift
//  TaskBoard
//
//  Created by Siddhant Kumar on 08/08/26.
//

import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel: SettingsViewModel
    @ObservedObject var policy: SyncPolicy

    init(
        controls: RemoteTaskDebugControls?,
        uploadService: LogUploadService,
        policy: SyncPolicy,
        sync: @escaping @Sendable () async -> Void
    ) {
        self.policy = policy
        _viewModel = StateObject(
            wrappedValue: SettingsViewModel(
                controls: controls,
                uploadService: uploadService,
                sync: sync
            )
        )
    }

    var body: some View {
        Form {
            Section {
                Button {
                    _Concurrency.Task { await viewModel.syncNow() }
                } label: {
                    HStack {
                        Text("Sync now")
                        Spacer()
                        syncStatus
                    }
                }
                .disabled(viewModel.syncState == .syncing)

                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent("Sync after", value: pendingThresholdLabel)
                    Slider(
                        value: thresholdBinding,
                        in: Double(SyncPolicy.thresholdRange.lowerBound)...Double(SyncPolicy.thresholdRange.upperBound),
                        step: 1
                    )
                }
            } header: {
                Text("Sync")
            } footer: {
                Text("Also syncs at launch, on reconnect, on returning to the foreground, and via background refresh. The threshold covers a long session that hits none of those.")
            }

            if viewModel.canConfigureBackend {
                Section {
                    Toggle("Force offline", isOn: $viewModel.forceOffline)

                    VStack(alignment: .leading, spacing: 4) {
                        LabeledContent("Failure rate", value: "\(Int(viewModel.failureRate * 100))%")
                        Slider(value: $viewModel.failureRate, in: 0...1, step: 0.05)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        LabeledContent("Latency", value: String(format: "%.1fs", viewModel.simulatedLatency))
                        Slider(value: $viewModel.simulatedLatency, in: 0...3, step: 0.1)
                    }
                } header: {
                    Text("Network Simulation")
                } footer: {
                    Text("Injected in front of whichever backend is active, real or fake. Applies to the next sync attempt.")
                }
            }

            Section("Logs") {
                Button {
                    _Concurrency.Task { await viewModel.uploadLogs() }
                } label: {
                    HStack {
                        Text("Upload logs")
                        Spacer()
                        uploadStatus
                    }
                }
                .disabled(viewModel.uploadState == .uploading)

                if case .failed(let message) = viewModel.uploadState {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
    }

    private var pendingThresholdLabel: String {
        let count = policy.pendingThreshold
        return count == 1 ? "1 pending change" : "\(count) pending changes"
    }

    private var thresholdBinding: Binding<Double> {
        Binding(
            get: { Double(policy.pendingThreshold) },
            set: { policy.pendingThreshold = Int($0.rounded()) }
        )
    }

    @ViewBuilder
    private var syncStatus: some View {
        switch viewModel.syncState {
        case .idle:
            EmptyView()
        case .syncing:
            ProgressView()
        case .finished:
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.green)
                .contentTransition(.symbolEffect(.replace))
        }
    }

    @ViewBuilder
    private var uploadStatus: some View {
        switch viewModel.uploadState {
        case .idle:
            EmptyView()
        case .uploading:
            ProgressView()
        case .success:
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.green)
                .contentTransition(.symbolEffect(.replace))
        case .failed:
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.red)
                .contentTransition(.symbolEffect(.replace))
        }
    }
}
