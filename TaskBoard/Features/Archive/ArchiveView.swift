//
//  ArchiveView.swift
//  TaskBoard
//

import SwiftUI

struct ArchiveView: View {
    @StateObject private var viewModel: ArchiveViewModel

    init(useCases: TaskUseCases) {
        _viewModel = StateObject(wrappedValue: ArchiveViewModel(useCases: useCases))
    }

    var body: some View {
        Group {
            if viewModel.isEmpty {
                ContentUnavailableView(
                    "Nothing archived",
                    systemImage: "archivebox",
                    description: Text("Archived tasks come off the board and wait here. Restoring one returns it to the column it left.")
                )
            } else {
                list
            }
        }
        .navigationTitle("Archive")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.smooth(duration: 0.3), value: viewModel.tasks.map(\.id))
    }

    private var list: some View {
        List {
            Section {
                ForEach(viewModel.tasks) { task in
                    row(task)
                        // Swipe is the shortcut; the row's own button is the
                        // discoverable version of the same action.
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                viewModel.restore(task)
                            } label: {
                                Label("Restore", systemImage: "arrow.uturn.backward")
                            }
                            .tint(.accentColor)
                        }
                }
            } footer: {
                Text("Archived tasks sync in their own collection, separate from the board. Restoring one returns it to the column it left, on every device.")
            }
        }
    }

    private func row(_ task: ArchivedTask) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                // A subtask archived alongside its parent keeps the link, so
                // the archive names the group rather than reading as a flat
                // list of identical "Subtask" labels.
                if task.parentId != nil {
                    Label(
                        viewModel.parentTitle(for: task).map { "Subtask (\($0))" } ?? "Subtask",
                        systemImage: "arrow.turn.down.right"
                    )
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                }

                Text(task.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)

                if !task.description.isEmpty {
                    Text(task.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 6) {
                    Label(task.status.displayName, systemImage: task.status.symbolName)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(task.status.tint)

                    Text("·")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    Text(task.archivedAt, format: .relative(presentation: .named))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, 2)
            }

            Spacer(minLength: 0)

            Button {
                viewModel.restore(task)
            } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
                    .labelStyle(.iconOnly)
                    .font(.subheadline)
                    .padding(8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .accessibilityLabel("Restore \(task.title) to \(task.status.displayName)")
        }
        .padding(.vertical, 4)
    }
}
