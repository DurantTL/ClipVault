import CryptoKit
import Foundation

final class VerificationService {
  private let security = SecurityScopedBookmarkManager()
  func verify(source: URL, destination: URL, mode: VerificationMode) async throws {
    try await Task.detached(priority: .utility) { [security] in
      try security.withAccess(to: source) {
        try security.withAccess(to: destination) {
          let fm = FileManager.default
          guard fm.fileExists(atPath: destination.path) else { throw CocoaError(.fileNoSuchFile) }
          let s = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? -1
          let d = try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? -2
          guard s == d else {
            throw NSError(
              domain: "ClipVault", code: 1,
              userInfo: [NSLocalizedDescriptionKey: "File size mismatch after copy."])
          }
          if mode == .strong {
            guard try self.sha256(source) == self.sha256(destination) else {
              throw NSError(
                domain: "ClipVault", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "SHA256 checksum mismatch."])
            }
          }
        }
      }
    }.value
  }
  private func sha256(_ url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hasher = SHA256()
    while autoreleasepool(invoking: {
      let d = handle.readData(ofLength: 1024 * 1024)
      if d.isEmpty { return false }
      hasher.update(data: d)
      return true
    }) {}
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }
}
