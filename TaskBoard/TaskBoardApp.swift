//
//  TaskBoardApp.swift
//  TaskBoard
//
//  Created by Siddhant Kumar on 08/08/26.
//

import SwiftUI

@main
struct TaskBoardApp: App {
    @StateObject private var environment: AppEnvironment

    init() {
        let environment = AppEnvironment()
        _environment = StateObject(wrappedValue: environment)

        // Built here rather than in RootView so the background task handler can
        // be registered against it while the app is still launching.
        BackgroundSync.registerHandler { await environment.syncNow() }
    }

    var body: some Scene {
        WindowGroup {
            RootView(environment: environment)
        }
    }
}
