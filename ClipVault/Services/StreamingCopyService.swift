import CryptoKit
import Foundation

final class StreamingCopyService {
  var isCancelled: () -> Bool = { false }
  var isPaused: () -> Bool = { false }
  private let chunkSize: Int

  init(chunkSize: Int = 8 * 1024 * 1024) {
    self.chunkSize = chunkSize
  }

  static func partialURL(for destination: URL) -> URL {
    destination.deletingLastPathComponent()
      .appendingPathComponent(destination.lastPathComponent + AppBrand.partialFileSuffix)
  }

  static func partialManifestURL(for destination: URL) -> URL {
    destination.deletingLastPathComponent()
      .appendingPathComponent(destination.lastPathComponent + AppBrand.partialManifestSuffix)
  }

  static func hasPartial(for destination: URL) -> Bool {
    FileManager.default.fileExists(atPath: partialURL(for: destination).path)
  }

  func copy(
    from source: URL, to destination: URL, alreadyCopiedBytes: Int64, totalBytes: Int64,
    progress: @escaping @MainActor (Int64) -> Void
  ) async throws -> Int64 {
    try await Task.detached(priority: .userInitiated) { [chunkSize, isCancelled, isPaused] in
      let partialDestination = Self.partialURL(for: destination)
      let manifestURL = Self.partialManifestURL(for: destination)
      let fm = FileManager.default
      let start = Date()

      guard !fm.fileExists(atPath: destination.path) else {
        throw CocoaError(.fileWriteFileExists)
      }

      let sourceValues = try source.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
      let sourceSize = Int64(sourceValues.fileSize ?? 0)
      let expectedManifest = PartialManifest(
        version: 1,
        sourceSize: sourceSize,
        sourceModificationTime: sourceValues.contentModificationDate?.timeIntervalSince1970,
        sourceFingerprint: try Self.sampledSHA256(of: source, size: sourceSize)
      )
      var copied: Int64 = 0

      if fm.fileExists(atPath: partialDestination.path) {
        let partialSize = Int64((try? partialDestination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        let existingManifest = try? Self.readManifest(at: manifestURL)
        if partialSize > 0,
           partialSize < sourceSize,
           let existingManifest,
           Self.matches(existingManifest, expectedManifest) {
          copied = partialSize
        } else {
          try? fm.removeItem(at: partialDestination)
          try? fm.removeItem(at: manifestURL)
        }
      } else {
        try? fm.removeItem(at: manifestURL)
      }

      if !fm.fileExists(atPath: partialDestination.path) {
        guard fm.createFile(atPath: partialDestination.path, contents: nil) else {
          throw CocoaError(.fileWriteUnknown)
        }
        try Self.writeManifest(expectedManifest, to: manifestURL)
      }

      let input = try FileHandle(forReadingFrom: source)
      defer { try? input.close() }
      let output = try FileHandle(forWritingTo: partialDestination)
      defer { try? output.close() }
      try input.seek(toOffset: UInt64(copied))
      try output.seekToEnd()

      while true {
        if isCancelled() || Task.isCancelled { throw CancellationError() }
        if isPaused() {
          try output.synchronize()
          repeat {
            try await Task.sleep(nanoseconds: 200_000_000)
            if isCancelled() || Task.isCancelled { throw CancellationError() }
          } while isPaused()
        }
        let data = try input.read(upToCount: chunkSize) ?? Data()
        if data.isEmpty { break }
        try output.write(contentsOf: data)
        copied += Int64(data.count)
        let absolute = alreadyCopiedBytes + copied
        await MainActor.run { progress(min(absolute, totalBytes)) }
      }
      try output.synchronize()
      if fm.fileExists(atPath: destination.path) {
        throw CocoaError(.fileWriteFileExists)
      }
      try fm.moveItem(at: partialDestination, to: destination)
      try? fm.removeItem(at: manifestURL)
      PerformanceLogger.shared.transfer(kind: "copy", bytes: copied, duration: Date().timeIntervalSince(start))
      return copied
    }.value
  }

  private struct PartialManifest: Codable {
    let version: Int
    let sourceSize: Int64
    let sourceModificationTime: TimeInterval?
    let sourceFingerprint: String
  }

  private static func readManifest(at url: URL) throws -> PartialManifest {
    try JSONDecoder().decode(PartialManifest.self, from: Data(contentsOf: url))
  }

  private static func writeManifest(_ manifest: PartialManifest, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    try encoder.encode(manifest).write(to: url, options: .atomic)
  }

  private static func matches(_ existing: PartialManifest, _ expected: PartialManifest) -> Bool {
    guard existing.version == expected.version,
          existing.sourceSize == expected.sourceSize,
          existing.sourceFingerprint == expected.sourceFingerprint else {
      return false
    }
    switch (existing.sourceModificationTime, expected.sourceModificationTime) {
    case (nil, nil):
      return true
    case let (lhs?, rhs?):
      return abs(lhs - rhs) < 1
    default:
      return false
    }
  }

  private static func sampledSHA256(of url: URL, size: Int64) throws -> String {
    let sampleSize = 1024 * 1024
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hasher = SHA256()

    let first = try handle.read(upToCount: sampleSize) ?? Data()
    hasher.update(data: first)

    if size > Int64(sampleSize) {
      let tailOffset = UInt64(max(0, size - Int64(sampleSize)))
      try handle.seek(toOffset: tailOffset)
      let tail = try handle.read(upToCount: sampleSize) ?? Data()
      hasher.update(data: tail)
    }

    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }
}
