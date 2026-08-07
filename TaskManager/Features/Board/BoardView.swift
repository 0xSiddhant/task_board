//
//  BoardView.swift
//  TaskManager
//
//  Created by Siddhant Kumar on 08/08/26.
//

import SwiftUI

struct BoardView: View {
    @StateObject private var viewModel: BoardViewModel
    @Namespace private var cardNamespace

    init(useCases: TaskUseCases) {
        _viewModel = StateObject(wrappedValue: BoardViewModel(useCases: useCases))
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(TaskStatus.allCases, id: \.self) { status in
                    TaskColumnView(
                        status: status,
                        tasks: viewModel.tasks(in: status),
                        namespace: cardNamespace,
                        onDrop: { id, index in drop(id, into: status, at: index) },
                        onSelect: { _ in
                            // Plan 05: presents TaskFormSheet in edit mode.
                        },
                        onDelete: { task in
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                viewModel.delete(task)
                            }
                        }
                    )
                }
            }
            .padding(12)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .navigationTitle("Board")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    // Plan 05: presents TaskFormSheet in create mode.
                } label: {
                    Label("New Task", systemImage: "plus")
                }
            }
        }
    }

    private func drop(_ id: UUID, into status: TaskStatus, at index: Int) {
        guard let task = viewModel.tasksByStatus.values.flatMap({ $0 }).first(where: { $0.id == id }) else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            viewModel.move(task, to: status, insertingAt: index)
        }
    }
}
