import Foundation

final class StreamingCopyService {
    var isCancelled: () -> Bool = { false }
    private let chunkSize = 8 * 1024 * 1024

    func copy(from source: URL, to destination: URL, alreadyCopiedBytes: Int64, totalBytes: Int64, progress: @escaping @MainActor (Int64) -> Void) async throws -> Int64 {
        try await Task.detached(priority: .userInitiated) { [chunkSize, isCancelled] in
            let input = try FileHandle(forReadingFrom: source)
            defer { try? input.close() }
            FileManager.default.createFile(atPath: destination.path, contents: nil)
            let output = try FileHandle(forWritingTo: destination)
            defer { try? output.close() }
            var copied: Int64 = 0
            while true {
                if isCancelled() || Task.isCancelled { throw CancellationError() }
                let data = try input.read(upToCount: chunkSize) ?? Data()
                if data.isEmpty { break }
                try output.write(contentsOf: data)
                copied += Int64(data.count)
                let absolute = alreadyCopiedBytes + copied
                await MainActor.run { progress(min(absolute, totalBytes)) }
            }
            try output.synchronize()
            return copied
        }.value
    }
}
