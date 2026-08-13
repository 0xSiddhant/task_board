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

/// How a card relates to the current search. `inactive` is the resting state, so
/// nothing changes when no one is searching.
enum CardSearchState {
    case inactive
    case match
    case nonMatch
}

struct TaskCardView: View {
    let task: Task
    var isLifted = false
    var searchState: CardSearchState = .inactive
    /// Set on a subtask, to show which task it belongs to. Absent when the
    /// parent hasn't been pulled down yet, which reads as an ordinary card.
    var parentTitle: String?
    /// Set on a parent, to show how much of its checklist is finished.
    var progress: SubtaskProgress?
    var onDragChanged: ((CGSize, CGPoint) -> Void)?
    var onDragEnded: (() -> Void)?

    private var isMatch: Bool { searchState == .match }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: task.status.symbolName)
                .font(.subheadline)
                .foregroundStyle(task.status.tint)
                .contentTransition(.symbolEffect(.replace))
                .accessibilityLabel(task.status.displayName)

            VStack(alignment: .leading, spacing: 4) {
                if let parentTitle {
                    breadcrumb(parentTitle)
                }

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

                if let progress, progress.total > 0 {
                    subtaskProgress(progress)
                }
            }

            Spacer(minLength: 4)

            dragHandle
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.background)
                // A tint rather than a glow. A shadow behind a card sitting in a
                // tight stack reads as a hard band against the card below it,
                // especially in light mode.
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.accentColor.opacity(isMatch ? 0.1 : 0))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(borderStyle, lineWidth: isMatch ? 2 : (isLifted ? 1.5 : 1))
        }
        .shadow(color: .black.opacity(isLifted ? 0.22 : 0), radius: isLifted ? 14 : 0, y: isLifted ? 8 : 0)
        // Only the dragged card scales. Scaling a match too made it overlap its
        // neighbour's spacing and clipped the border.
        .scaleEffect(isLifted ? 1.03 : 1)
        .opacity(searchState == .nonMatch ? 0.35 : 1)
        .animation(.smooth(duration: 0.25), value: isLifted)
        .animation(.smooth(duration: 0.25), value: task.status)
        .animation(.smooth(duration: 0.3), value: searchState)
    }

    /// Sits above the title rather than below it, so the card reads
    /// "belongs to X" before it reads its own name.
    private func breadcrumb(_ parentTitle: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.turn.down.right")
                .font(.caption2)
            Text(parentTitle)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
        }
        .foregroundStyle(.tertiary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Subtask of \(parentTitle)")
    }

    private func subtaskProgress(_ progress: SubtaskProgress) -> some View {
        let fraction = Double(progress.done) / Double(progress.total)
        let isComplete = progress.done == progress.total

        return HStack(spacing: 6) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(isComplete ? AnyShapeStyle(Color.green) : AnyShapeStyle(Color.accentColor))
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 3)

            Text("\(progress.done)/\(progress.total)")
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(isComplete ? AnyShapeStyle(Color.green) : AnyShapeStyle(.secondary))
                .contentTransition(.numericText())
        }
        .padding(.top, 3)
        .animation(.smooth(duration: 0.3), value: progress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(progress.done) of \(progress.total) subtasks done")
    }

    private var borderStyle: AnyShapeStyle {
        if isLifted { return AnyShapeStyle(Color.accentColor.opacity(0.6)) }
        if isMatch { return AnyShapeStyle(Color.accentColor) }
        return AnyShapeStyle(.quaternary)
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
