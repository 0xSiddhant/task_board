import Foundation
import UIKit
#if canImport(FirebaseStorage)
import FirebaseStorage
#endif

struct DeviceMetadata {
    let deviceModel: String
    let systemVersion: String
    let appVersion: String
    let buildNumber: String
    let uploadedAt: Date

    static func current() -> DeviceMetadata {
        DeviceMetadata(
            deviceModel: UIDevice.current.model,
            systemVersion: UIDevice.current.systemVersion,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            buildNumber: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
            uploadedAt: Date()
        )
    }
}

protocol LogUploadService {
    func upload(logData: Data, metadata: DeviceMetadata) async throws
}

/// Default, used out of the box — proves the upload → reset flow works end to end
/// without requiring a Firebase project to be configured just to build and run.
final class NoOpLogUploadService: LogUploadService {
    func upload(logData: Data, metadata: DeviceMetadata) async throws {
        try await _Concurrency.Task.sleep(nanoseconds: 300_000_000)   // simulate the round trip for the UI
    }
}

/// Real implementation — swap in via AppEnvironment once a Firebase project is configured.
/// Metadata rides as custom metadata on the blob, so one upload call covers both the
/// log content and the device info — no separate Firestore write needed.
final class FirebaseLogUploadService: LogUploadService {
    func upload(logData: Data, metadata: DeviceMetadata) async throws {
        #if canImport(FirebaseStorage)
        let filename = "\(metadata.deviceModel)-\(Int(metadata.uploadedAt.timeIntervalSince1970)).log"
        let ref = Storage.storage().reference().child("logs/\(filename)")

        let storageMetadata = StorageMetadata()
        storageMetadata.customMetadata = [
            "deviceModel": metadata.deviceModel,
            "systemVersion": metadata.systemVersion,
            "appVersion": metadata.appVersion,
            "buildNumber": metadata.buildNumber,
            "uploadedAt": ISO8601DateFormatter().string(from: metadata.uploadedAt)
        ]
        _ = try await ref.putDataAsync(logData, metadata: storageMetadata)
        #endif
    }
}
