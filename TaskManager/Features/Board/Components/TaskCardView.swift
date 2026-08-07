//
//  TaskCardView.swift
//  TaskManager
//
//  Created by Siddhant Kumar on 08/08/26.
//

import SwiftUI

extension SyncStatus {
    var symbolName: String {
        switch self {
        case .pending: return "clock"
        case .syncing: return "arrow.triangle.2.circlepath"
        case .synced: return "checkmark.circle"
        case .failed: return "exclamationmark.triangle"
        }
    }

    var tint: Color {
        switch self {
        case .pending: return .orange
        case .syncing: return .blue
        case .synced: return .green
        case .failed: return .red
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .pending: return "Waiting to sync"
        case .syncing: return "Syncing"
        case .synced: return "Synced"
        case .failed: return "Sync failed"
        }
    }
}

struct TaskCardView: View {
    let task: Task

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(task.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)

                Spacer(minLength: 0)

                Image(systemName: task.syncStatus.symbolName)
                    .font(.caption)
                    .foregroundStyle(task.syncStatus.tint)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityLabel(task.syncStatus.accessibilityLabel)
            }

            if !task.description.isEmpty {
                Text(task.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
        .animation(.default, value: task.syncStatus)
    }
}
