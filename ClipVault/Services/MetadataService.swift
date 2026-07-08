import Foundation
import AVFoundation

final class MetadataService {
    func enrich(_ clip: inout Clip) async {
        let asset = AVURLAsset(url: URL(fileURLWithPath: clip.currentPath))
        do { clip.duration = try await asset.load(.duration).seconds } catch { clip.previewUnavailable = true; clip.errorMessage = error.localizedDescription }
        do {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            if let t = tracks.first {
                let size = try await t.load(.naturalSize).applying(try await t.load(.preferredTransform))
                clip.width = Int(abs(size.width)); clip.height = Int(abs(size.height)); clip.frameRate = Double(try await t.load(.nominalFrameRate))
                if let desc = try await t.load(.formatDescriptions).first { clip.codec = CMFormatDescriptionGetMediaSubType(desc).fourCC }
            }
            clip.hasAudio = !(try await asset.loadTracks(withMediaType: .audio)).isEmpty
        } catch { clip.previewUnavailable = true }
    }
}
extension FourCharCode { var fourCC: String { String(bytes: [UInt8((self>>24)&0xff),UInt8((self>>16)&0xff),UInt8((self>>8)&0xff),UInt8(self&0xff)], encoding: .macOSRoman) ?? "----" } }
