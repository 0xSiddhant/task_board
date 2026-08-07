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
        ZStack(alignment: .top) {
            NavigationStack {
                BoardView(useCases: environment.taskUseCases)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            NavigationLink {
                                SettingsView(
                                    remote: environment.remote,
                                    uploadService: environment.logUploadService
                                )
                            } label: {
                                Label("Settings", systemImage: "gearshape")
                            }
                        }
                    }
            }

            // Layered over the stack, not stacked above it: as a sibling in the
            // layout it pushes the board down and tints the navigation bar.
            StatusBanner(message: environment.banner)
                .allowsHitTesting(false)
                .zIndex(1)
        }
        .task { environment.start() }
    }
}
