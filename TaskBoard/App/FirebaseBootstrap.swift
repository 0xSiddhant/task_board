//
//  FirebaseBootstrap.swift
//  TaskBoard
//
//  Created by Siddhant Kumar on 08/08/26.
//

import Foundation
#if canImport(FirebaseCore)
import FirebaseCore
#endif

/// Firebase is opt-in at runtime rather than compile time. Once the SDK is a
/// package dependency `canImport` is always true, so it can no longer tell a
/// configured project from an unconfigured one — the plist in the bundle can.
/// `FirebaseApp.configure()` traps when it's missing, so this must be checked
/// before configuring, not after.
enum FirebaseBootstrap {
    /// Lazily evaluated once, so configure() runs at most one time.
    static let isConfigured: Bool = {
        guard Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil else {
            return false
        }
        #if canImport(FirebaseCore)
        FirebaseApp.configure()
        return true
        #else
        return false
        #endif
    }()
}
