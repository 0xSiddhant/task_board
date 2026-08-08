//
//  SyncPolicy.swift
//  TaskBoard
//
//  Created by Siddhant Kumar on 08/08/26.
//

import Combine
import Foundation

/// How much unsent work is allowed to pile up before a sync is forced.
///
/// The other triggers — launch, reconnect, foreground, background refresh — all
/// depend on the app changing state. Someone working continuously in the
/// foreground hits none of them, so their queue grows unbounded until they
/// happen to background the app.
@MainActor
final class SyncPolicy: ObservableObject {
    static let thresholdRange = 1...25
    static let defaultThreshold = 5

    @Published var pendingThreshold: Int {
        didSet { defaults.set(pendingThreshold, forKey: Self.storageKey) }
    }

    private let defaults: UserDefaults
    private static let storageKey = "sync.pendingThreshold"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.integer(forKey: Self.storageKey)
        pendingThreshold = Self.thresholdRange.contains(stored) ? stored : Self.defaultThreshold
    }
}
