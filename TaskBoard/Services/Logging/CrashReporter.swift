//
//  CrashReporter.swift
//  TaskBoard
//
//  Created by Siddhant Kumar on 08/08/26.
//

import Foundation
#if canImport(FirebaseCrashlytics)
import FirebaseCrashlytics
#endif

nonisolated protocol CrashReporter: Sendable {
    /// Context carried into the next crash report.
    func breadcrumb(_ message: String)
    /// A handled failure worth reporting without crashing the app.
    func record(_ message: String)
}

/// The default, so the app runs with no Firebase project configured.
nonisolated struct NoOpCrashReporter: CrashReporter {
    func breadcrumb(_ message: String) {}
    func record(_ message: String) {}
}

#if canImport(FirebaseCrashlytics)
nonisolated struct FirebaseCrashReporter: CrashReporter {
    func breadcrumb(_ message: String) {
        Crashlytics.crashlytics().log(message)
    }

    /// Recorded as a non-fatal. The app keeps running; the report shows up
    /// alongside crashes with the preceding breadcrumbs attached.
    func record(_ message: String) {
        Crashlytics.crashlytics().record(
            error: NSError(
                domain: "TaskBoard",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        )
    }
}
#endif
