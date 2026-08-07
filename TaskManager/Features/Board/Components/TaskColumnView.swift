//
//  TaskColumnView.swift
//  TaskManager
//
//  Created by Siddhant Kumar on 08/08/26.
//

import SwiftUI

extension TaskStatus {
    var displayName: String {
        switch self {
        case .todo: return "To Do"
        case .inProgress: return "In Progress"
        case .done: return "Done"
        }
    }
}

struct TaskColumnView: View {
    let status: TaskStatus
    let tasks: [Task]
    let namespace: Namespace.ID
    /// Called with the dragged task's id and the slot it should land in.
    let onDrop: (UUID, Int) -> Void
    let onSelect: (Task) -> Void
    let onDelete: (Task) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    if tasks.isEmpty {
                        emptyState
                    } else {
                        ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                            card(task, at: index)
                        }
                    }

                    // Dropping below the last card appends. The min height is what
                    // keeps an empty column droppable.
                    Color.clear
                        .frame(minHeight: 60)
                        .contentShape(Rectangle())
                        .dropDestination(for: String.self) { items, _ in
                            handleDrop(items, at: tasks.count)
                        }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .frame(width: 260)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
    }

    private var header: some View {
        HStack {
            Text(status.displayName)
                .font(.headline)
            Text("\(tasks.count)")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
                .contentTransition(.numericText())
        }
        .animation(.default, value: tasks.count)
    }

    private var emptyState: some View {
        Text("Nothing here yet")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 16)
    }

    private func card(_ task: Task, at index: Int) -> some View {
        TaskCardView(task: task)
            // Keyed on the task id so a card crossing columns travels there.
            .matchedGeometryEffect(id: task.id, in: namespace)
            .contentShape(Rectangle())
            .onTapGesture { onSelect(task) }
            .contextMenu {
                Button(role: .destructive) { onDelete(task) } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .draggable(task.id.uuidString)
            // Each card is its own drop target, inserting above itself — steadier
            // than deriving an index from raw drop coordinates.
            .dropDestination(for: String.self) { items, _ in
                handleDrop(items, at: index)
            }
    }

    private func handleDrop(_ items: [String], at index: Int) -> Bool {
        guard let id = items.first.flatMap(UUID.init(uuidString:)) else { return false }
        onDrop(id, index)
        return true
    }
}
