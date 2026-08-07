//
//  RootView.swift
//  TaskManager
//
//  Created by Siddhant Kumar on 08/08/26.
//

import SwiftUI

struct RootView: View {
    @StateObject private var environment = AppEnvironment()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                StatusBanner(message: environment.banner)
                BoardView(useCases: environment.taskUseCases)
            }
        }
        .task { environment.start() }
    }
}
