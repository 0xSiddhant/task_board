//
//  TaskCardView.swift
//  TaskBoard
//
//  Created by Siddhant Kumar on 08/08/26.
//

import SwiftUI

extension TaskStatus {
    var symbolName: String {
        switch self {
        case .todo: return "circle"
        case .inProgress: return "circle.lefthalf.filled"
        case .done: return "checkmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .todo: return .secondary
        case .inProgress: return .blue
        case .done: return .green
        }
    }
}

struct TaskCardView: View {
    let task: Task
    var isLifted = false
    var onDragChanged: ((CGSize, CGPoint) -> Void)?
    var onDragEnded: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: task.status.symbolName)
                .font(.subheadline)
                .foregroundStyle(task.status.tint)
                .contentTransition(.symbolEffect(.replace))
                .accessibilityLabel(task.status.displayName)

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if !task.description.isEmpty {
                    Text(task.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 4)

            dragHandle
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isLifted ? AnyShapeStyle(Color.accentColor.opacity(0.6)) : AnyShapeStyle(.quaternary),
                    lineWidth: isLifted ? 1.5 : 1
                )
        }
        .shadow(color: .black.opacity(isLifted ? 0.22 : 0), radius: isLifted ? 14 : 0, y: isLifted ? 8 : 0)
        .scaleEffect(isLifted ? 1.03 : 1)
        .animation(.smooth(duration: 0.25), value: isLifted)
        .animation(.smooth(duration: 0.25), value: task.status)
    }

    private var dragHandle: some View {
        VStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 3) {
                    Circle().frame(width: 3.5, height: 3.5)
                    Circle().frame(width: 3.5, height: 3.5)
                }
            }
        }
        .foregroundStyle(isLifted ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
        .padding(.vertical, 14)
        .padding(.leading, 10)
        .padding(.trailing, 2)
        .contentShape(Rectangle())
            .accessibilityLabel("Drag to move task")
            .gesture(
                // minimumDistance 0 so the drag starts on touch-down rather than
                // after the system's long-press delay.
                DragGesture(minimumDistance: 0, coordinateSpace: .named(BoardLayout.coordinateSpace))
                    .onChanged { onDragChanged?($0.translation, $0.location) }
                    .onEnded { _ in onDragEnded?() }
            )
    }
}
