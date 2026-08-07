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
            // Navigation lives here rather than in BoardView so the board doesn't
            // need to know about the fake backend or the upload service.
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
        .task { environment.start() }
    }
}
