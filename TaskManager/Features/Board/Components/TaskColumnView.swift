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
    /// Already excludes the card being dragged, so indices here and the insertion
    /// index the board computes are in the same space.
    let tasks: [Task]
    let insertionIndex: Int?
    let onSelect: (Task) -> Void
    let onDelete: (Task) -> Void
    let onDragChanged: (Task, CGSize, CGPoint) -> Void
    let onDragEnded: () -> Void

    private var isTargeted: Bool { insertionIndex != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                        if insertionIndex == index { insertionIndicator }
                        card(task)
                    }

                    if insertionIndex == tasks.count { insertionIndicator }

                    if tasks.isEmpty && insertionIndex == nil { emptyState }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 8)
            }
        }
        .padding(10)
        .frame(width: 300)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(columnBackground)
        // The whole column reports its frame, so the entire height is a valid drop
        // area rather than just a short zone under the last card.
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ColumnFramesKey.self,
                    value: [ColumnFrame(status: status, frame: proxy.frame(in: .named(BoardLayout.coordinateSpace)))]
                )
            }
        }
        .animation(.smooth(duration: 0.28), value: insertionIndex)
        .animation(.smooth(duration: 0.28), value: tasks.map(\.id))
    }

    private var columnBackground: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(.quaternary.opacity(isTargeted ? 0.55 : 0.35))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.accentColor.opacity(isTargeted ? 0.5 : 0), lineWidth: 1.5)
            }
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

    private var insertionIndicator: some View {
        Capsule()
            .fill(Color.accentColor)
            .frame(height: 3)
            .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
    }

    private var emptyState: some View {
        Text("Nothing here yet")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 24)
    }

    private func card(_ task: Task) -> some View {
        TaskCardView(
            task: task,
            onDragChanged: { translation, location in
                onDragChanged(task, translation, location)
            },
            onDragEnded: onDragEnded
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect(task) }
        .contextMenu {
            Button(role: .destructive) { onDelete(task) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: CardFramesKey.self,
                    value: [CardFrame(
                        id: task.id,
                        status: status,
                        frame: proxy.frame(in: .named(BoardLayout.coordinateSpace))
                    )]
                )
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }
}
