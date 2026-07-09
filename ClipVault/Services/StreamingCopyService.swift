import Foundation

final class StreamingCopyService {
  var isCancelled: () -> Bool = { false }
  var isPaused: () -> Bool = { false }
  private let chunkSize = 8 * 1024 * 1024

  func copy(
    from source: URL, to destination: URL, alreadyCopiedBytes: Int64, totalBytes: Int64,
    progress: @escaping @MainActor (Int64) -> Void
  ) async throws -> Int64 {
    try await Task.detached(priority: .userInitiated) { [chunkSize, isCancelled, isPaused] in
      let partialDestination = destination.deletingLastPathComponent()
        .appendingPathComponent(destination.lastPathComponent + ".clipvault-partial")
      let fm = FileManager.default
      let start = Date()
      let sourceValues = try source.resourceValues(forKeys: [.fileSizeKey])
      let sourceSize = Int64(sourceValues.fileSize ?? 0)
      var copied: Int64 = 0

      if fm.fileExists(atPath: partialDestination.path) {
        let partialSize = Int64((try? partialDestination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        if partialSize > 0 && partialSize < sourceSize {
          copied = partialSize
        } else {
          try? fm.removeItem(at: partialDestination)
        }
      }

      if !fm.fileExists(atPath: partialDestination.path) {
        fm.createFile(atPath: partialDestination.path, contents: nil)
      }

      let input = try FileHandle(forReadingFrom: source)
      defer { try? input.close() }
      let output = try FileHandle(forWritingTo: partialDestination)
      defer { try? output.close() }
      try input.seek(toOffset: UInt64(copied))
      try output.seekToEnd()

      while true {
        if isCancelled() || Task.isCancelled { throw CancellationError() }
        while isPaused() {
          try output.synchronize()
          try await Task.sleep(nanoseconds: 200_000_000)
          if isCancelled() || Task.isCancelled { throw CancellationError() }
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
      PerformanceLogger.shared.transfer(kind: "copy", bytes: copied, duration: Date().timeIntervalSince(start))
      return copied
    }.value
  }
}
