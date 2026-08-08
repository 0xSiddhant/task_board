//
//  BackgroundSync.swift
//  TaskBoard
//
//  Created by Siddhant Kumar on 08/08/26.
//

import BackgroundTasks
import Foundation

nonisolated enum BackgroundSync {
    /// Must match BGTaskSchedulerPermittedIdentifiers in Info.plist, or
    /// registration traps at launch.
    static let identifier = "com.siddhant.TaskBoard.sync"

    /// Registration has to finish before the app finishes launching, which rules
    /// out calling this from a view's `.task` or `.onAppear` — by then it's too
    /// late and the system throws.
    nonisolated static func registerHandler(_ handler: @escaping @Sendable () async -> Void) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            // Re-submit first. The system runs one request per submission, so
            // skipping this means background sync fires once and never again.
            schedule()

            let work = _Concurrency.Task {
                await handler()
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    /// The system treats the date as "no earlier than", not a promise — actual
    /// timing depends on usage patterns, battery, and network.
    nonisolated static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            Logger.record("Could not schedule background sync: \(error)", level: .error)
        }
    }
}
