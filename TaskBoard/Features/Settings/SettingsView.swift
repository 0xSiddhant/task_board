//
//  SettingsView.swift
//  TaskBoard
//
//  Created by Siddhant Kumar on 08/08/26.
//

import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel: SettingsViewModel

    init(controls: RemoteTaskDebugControls?, uploadService: LogUploadService) {
        _viewModel = StateObject(
            wrappedValue: SettingsViewModel(controls: controls, uploadService: uploadService)
        )
    }

    var body: some View {
        Form {
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
                    Text("Fake Backend")
                } footer: {
                    Text("Applies to the next sync attempt.")
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
