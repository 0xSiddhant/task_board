//
//  BoardView.swift
//  TaskManager
//
//  Created by Siddhant Kumar on 08/08/26.
//

import SwiftUI

enum BoardLayout {
    /// Shared coordinate space so card frames and the drag gesture's location are
    /// expressed in the same terms and can be compared directly.
    static let coordinateSpace = "board"
}

/// Where a dragged card would land, expressed as a neighbour rather than an
/// index. An index would have to be counted against the column *without* the
/// dragged card, while the column still displays it — the anchor sidesteps that
/// mismatch entirely.
enum DropAnchor: Equatable {
    case before(UUID)
    case endOfColumn
}

struct DropTarget: Equatable {
    let status: TaskStatus
    let anchor: DropAnchor
}

struct CardFrame: Equatable {
    let id: UUID
    let status: TaskStatus
    let frame: CGRect
}

struct ColumnFrame: Equatable {
    let status: TaskStatus
    let frame: CGRect
}

struct CardFramesKey: PreferenceKey {
    static let defaultValue: [CardFrame] = []
    static func reduce(value: inout [CardFrame], nextValue: () -> [CardFrame]) {
        value.append(contentsOf: nextValue())
    }
}

struct ColumnFramesKey: PreferenceKey {
    static let defaultValue: [ColumnFrame] = []
    static func reduce(value: inout [ColumnFrame], nextValue: () -> [ColumnFrame]) {
        value.append(contentsOf: nextValue())
    }
}

struct BoardView: View {
    @StateObject private var viewModel: BoardViewModel
    @State private var formMode: TaskFormMode?

    @State private var draggingTask: Task?
    @State private var dragTranslation: CGSize = .zero
    @State private var dragOrigin: CGRect = .zero
    @State private var dropTarget: DropTarget?

    @State private var cardFrames: [CardFrame] = []
    @State private var columnFrames: [ColumnFrame] = []

    private let useCases: TaskUseCases

    init(useCases: TaskUseCases) {
        self.useCases = useCases
        _viewModel = StateObject(wrappedValue: BoardViewModel(useCases: useCases))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            columns
            liftedCard
        }
        .coordinateSpace(name: BoardLayout.coordinateSpace)
        .onPreferenceChange(CardFramesKey.self) { cardFrames = $0 }
        .onPreferenceChange(ColumnFramesKey.self) { columnFrames = $0 }
        .navigationTitle("Board")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    formMode = .create
                } label: {
                    Label("New Task", systemImage: "plus")
                }
            }
        }
        .sheet(item: $formMode) { mode in
            TaskFormSheet(mode: mode, useCases: useCases)
        }
    }

    private var columns: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(TaskStatus.allCases, id: \.self) { status in
                    TaskColumnView(
                        status: status,
                        tasks: viewModel.tasks(in: status),
                        draggingTaskID: draggingTask?.id,
                        dropAnchor: dropTarget?.status == status ? dropTarget?.anchor : nil,
                        onSelect: { formMode = .edit($0) },
                        onDragChanged: dragChanged,
                        onDragEnded: dragEnded
                    )
                }
            }
            .padding(12)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        // Scrolling mid-drag would move the columns out from under the finger.
        .scrollDisabled(draggingTask != nil)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// A copy that follows the finger. The original stays dimmed in place, so the
    /// column keeps its layout and its header count until a drop actually commits.
    @ViewBuilder
    private var liftedCard: some View {
        if let task = draggingTask {
            TaskCardView(task: task, isLifted: true)
                .frame(width: dragOrigin.width)
                .offset(
                    x: dragOrigin.minX + dragTranslation.width,
                    y: dragOrigin.minY + dragTranslation.height
                )
                .allowsHitTesting(false)
                .transition(.identity)
        }
    }

    // MARK: Drag

    private func dragChanged(_ task: Task, _ translation: CGSize, _ location: CGPoint) {
        if draggingTask == nil {
            guard let origin = cardFrames.first(where: { $0.id == task.id })?.frame else { return }
            dragOrigin = origin
            withAnimation(.smooth(duration: 0.2)) { draggingTask = task }
        }

        dragTranslation = translation
        withAnimation(.smooth(duration: 0.22)) {
            dropTarget = target(at: location)
        }
    }

    private func dragEnded() {
        defer {
            draggingTask = nil
            dragTranslation = .zero
            dropTarget = nil
        }

        // A tap on the handle is a zero-distance drag; committing it would write a
        // position change for a card that never moved. The view model separately
        // ignores a drop onto the slot the card already occupies.
        let moved = abs(dragTranslation.width) > 6 || abs(dragTranslation.height) > 6
        guard moved, let task = draggingTask, let target = dropTarget else { return }

        let anchorID: UUID? = if case .before(let id) = target.anchor { id } else { nil }
        withAnimation(.smooth(duration: 0.3)) {
            viewModel.move(task, to: target.status, before: anchorID)
        }
    }

    /// Columns run the full height, so a hit anywhere in the column's horizontal
    /// band counts. The anchor is the first card whose midpoint the finger is
    /// above; past the last one, the drop appends.
    private func target(at point: CGPoint) -> DropTarget? {
        guard let column = columnFrames.first(where: {
            point.x >= $0.frame.minX && point.x <= $0.frame.maxX
        }) else { return nil }

        let cards = cardFrames
            .filter { $0.status == column.status && $0.id != draggingTask?.id }
            .sorted { $0.frame.minY < $1.frame.minY }

        if let hit = cards.first(where: { point.y < $0.frame.midY }) {
            return DropTarget(status: column.status, anchor: .before(hit.id))
        }
        return DropTarget(status: column.status, anchor: .endOfColumn)
    }
}
