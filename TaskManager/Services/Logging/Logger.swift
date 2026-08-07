import Foundation

enum LogLevel: String {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
}

/// App-wide logger: writes to console (debug builds only) and to a rotating pair of
/// on-disk files. Safe to call from anywhere — the actor serializes concurrent writes,
/// so SyncEngine, use cases, and ViewModels can all log without coordinating.
actor Logger {
    static let shared = Logger()

    private let currentURL: URL
    private let previousURL: URL
    private let maxFileSizeBytes: Int
    private var fileHandle: FileHandle?

    private init(maxFileSizeBytes: Int = 2_000_000) {   // ~2 MB per generation, ~4 MB retained max
        let dir = Logger.logsDirectory()
        currentURL = dir.appendingPathComponent("current.log")
        previousURL = dir.appendingPathComponent("previous.log")
        self.maxFileSizeBytes = maxFileSizeBytes
        openHandle()
    }

    // MARK: Public API

    func log(_ message: String, level: LogLevel = .info) {
        let line = "[\(Self.timestamp())] [\(level.rawValue)] \(message)\n"

        #if DEBUG
        print(line, terminator: "")
        #endif

        write(line)
        rotateIfNeeded()
    }

    /// Combined bytes across both generations — what gets handed to the upload service.
    func exportData() -> Data {
        let previous = (try? Data(contentsOf: previousURL)) ?? Data()
        let current = (try? Data(contentsOf: currentURL)) ?? Data()
        return previous + current
    }

    /// Called after a confirmed successful upload — never before, so a failed
    /// upload never loses data.
    func reset() {
        fileHandle?.closeFile()
        fileHandle = nil
        try? FileManager.default.removeItem(at: currentURL)
        try? FileManager.default.removeItem(at: previousURL)
        openHandle()
    }

    // MARK: File handling

    private func write(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }
        if fileHandle == nil { openHandle() }
        fileHandle?.seekToEndOfFile()
        fileHandle?.write(data)
    }

    /// Two-generation rotation instead of trimming lines in place: cheap (a rename,
    /// not a read-modify-rewrite of the whole file), and it's what "truncate old data
    /// past a threshold" means here — once `current` fills up, whatever was in
    /// `previous` before is discarded, and `current` becomes the new `previous`.
    private func rotateIfNeeded() {
        guard let size = try? currentURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size > maxFileSizeBytes else { return }

        fileHandle?.closeFile()
        fileHandle = nil
        try? FileManager.default.removeItem(at: previousURL)
        try? FileManager.default.moveItem(at: currentURL, to: previousURL)
        openHandle()
    }

    private func openHandle() {
        if !FileManager.default.fileExists(atPath: currentURL.path) {
            FileManager.default.createFile(atPath: currentURL.path, contents: nil)
        }
        fileHandle = try? FileHandle(forWritingTo: currentURL)
    }

    // MARK: Setup

    private static func logsDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var mutableDir = dir
        var values = URLResourceValues()
        values.isExcludedFromBackup = true   // logs shouldn't ride along in iCloud/iTunes backups
        try? mutableDir.setResourceValues(values)

        return dir
    }

    private static func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
