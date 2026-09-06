//
//  Signposts.swift
//  TaskBoard
//
//  Created by Siddhant Kumar on 08/08/26.
//

import os

/// os_signpost intervals for Instruments' Points of Interest / os_signpost
/// tracks — separate from `Logger`, which persists lines to disk. One
/// `OSSignposter` per area, so each shows up as its own lane in Instruments.
enum Signposts {
    private static let subsystem = "com.siddhant.TaskBoard"

    static let useCase = OSSignposter(subsystem: subsystem, category: "UseCase")
    static let persistence = OSSignposter(subsystem: subsystem, category: "Persistence")
    static let sync = OSSignposter(subsystem: subsystem, category: "Sync")
    static let upload = OSSignposter(subsystem: subsystem, category: "Upload")

    /// Wraps a synchronous operation in a begin/end interval. Each call gets
    /// its own signpost ID, so overlapping calls to the same named operation
    /// (e.g. two saves in flight) show as distinct intervals rather than
    /// merging into one.
    static func span<T>(
        _ signposter: OSSignposter,
        _ name: StaticString,
        _ operation: () throws -> T
    ) rethrows -> T {
        let id = signposter.makeSignpostID()
        let state = signposter.beginInterval(name, id: id)
        defer { signposter.endInterval(name, state) }
        return try operation()
    }

    /// Same, for `async` work.
    static func span<T>(
        _ signposter: OSSignposter,
        _ name: StaticString,
        _ operation: () async throws -> T
    ) async rethrows -> T {
        let id = signposter.makeSignpostID()
        let state = signposter.beginInterval(name, id: id)
        defer { signposter.endInterval(name, state) }
        return try await operation()
    }
}
