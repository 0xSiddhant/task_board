//
//  RootView.swift
//  TaskBoard
//
//  Created by Siddhant Kumar on 08/08/26.
//

import SwiftUI

struct RootView: View {
    @ObservedObject var environment: AppEnvironment

    var body: some View {
        ZStack(alignment: .top) {
            NavigationStack {
                BoardView(useCases: environment.taskUseCases)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            NavigationLink {
                                SettingsView(
                                    controls: environment.remoteDebugControls,
                                    uploadService: environment.logUploadService,
                                    policy: environment.syncPolicy,
                                    sync: { await environment.syncNow() }
                                )
                            } label: {
                                Label("Settings", systemImage: "gearshape")
                            }
                        }

                        ToolbarItem(placement: .topBarLeading) {
                            NavigationLink {
                                ArchiveView(useCases: environment.taskUseCases)
                            } label: {
                                Label("Archive", systemImage: "archivebox")
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
