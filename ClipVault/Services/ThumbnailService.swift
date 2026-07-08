import Foundation
import AVFoundation
import AppKit

final class ThumbnailService {
    func generate(for clip: Clip, projectFolder: URL, quality: ThumbnailQuality) async throws -> String {
        let cache = projectFolder.appendingPathComponent(".clipvault-cache/thumbnails", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let dest = cache.appendingPathComponent(clip.id.uuidString).appendingPathExtension("jpg")
        if FileManager.default.fileExists(atPath: dest.path) { return dest.path }
        let asset = AVURLAsset(url: URL(fileURLWithPath: clip.currentPath))
        let gen = AVAssetImageGenerator(asset: asset); gen.appliesPreferredTrackTransform = true; gen.maximumSize = CGSize(width: quality.maxPixelSize, height: quality.maxPixelSize)
        let dur = (try? await asset.load(.duration).seconds) ?? 10
        let time = CMTime(seconds: max(1, dur * 0.10), preferredTimescale: 600)
        let cg = try await gen.image(at: time).image
        guard let data = NSBitmapImageRep(cgImage: cg).representation(using: .jpeg, properties: [.compressionFactor: 0.82]) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: dest, options: .atomic)
        return dest.path
    }
}
