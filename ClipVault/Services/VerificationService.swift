import Foundation
import CryptoKit

final class VerificationService {
    func verify(source: URL, destination: URL, mode: VerificationMode) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: destination.path) else { throw CocoaError(.fileNoSuchFile) }
        let s = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? -1
        let d = try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? -2
        guard s == d else { throw NSError(domain: "ClipVault", code: 1, userInfo: [NSLocalizedDescriptionKey: "File size mismatch after copy."]) }
        if mode == .strong {
            guard try sha256(source) == sha256(destination) else { throw NSError(domain: "ClipVault", code: 2, userInfo: [NSLocalizedDescriptionKey: "SHA256 checksum mismatch."]) }
        }
    }
    private func sha256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var hasher = SHA256(); while autoreleasepool(invoking: { let d = handle.readData(ofLength: 1024*1024); if d.isEmpty { return false }; hasher.update(data: d); return true }) {}
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
