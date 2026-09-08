import CryptoKit
import Foundation

/// Result of a successful verify. Strong mode returns the lowercase hex SHA256;
/// fast mode never invents a checksum (MHL must refuse incomplete hash data).
struct VerificationOutcome: Equatable, Sendable {
  var mode: VerificationMode
  var bytes: Int64
  /// Present only after a successful strong (SHA256) verification.
  var checksum: String?
}

final class VerificationService {
  private let security = SecurityScopedBookmarkManager()

  @discardableResult
  func verify(source: URL, destination: URL, mode: VerificationMode) async throws -> VerificationOutcome {
    try await Task.detached(priority: .utility) { [security] in
      try security.withAccess(to: source) {
        try security.withAccess(to: destination) {
          let fm = FileManager.default
          let start = Date()
          guard fm.fileExists(atPath: destination.path) else { throw CocoaError(.fileNoSuchFile) }
          let s = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? -1
          let d = try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? -2
          guard s == d else {
            throw NSError(
              domain: "ClipVault", code: 1,
              userInfo: [NSLocalizedDescriptionKey: "File size mismatch after copy."])
          }
          var checksum: String?
          if mode == .strong {
            let sourceDigest = try Self.sha256(source)
            let destinationDigest = try Self.sha256(destination)
            guard sourceDigest == destinationDigest else {
              throw NSError(
                domain: "ClipVault", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "SHA256 checksum mismatch."])
            }
            checksum = destinationDigest
          }
          PerformanceLogger.shared.verification(
            mode: mode,
            bytes: Int64(d),
            duration: Date().timeIntervalSince(start)
          )
          return VerificationOutcome(mode: mode, bytes: Int64(d), checksum: checksum)
        }
      }
    }.value
  }

  private static func sha256(_ url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hasher = SHA256()
    while true {
      let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
      if data.isEmpty { break }
      hasher.update(data: data)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }
}
