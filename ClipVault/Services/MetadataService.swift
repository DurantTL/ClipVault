import AVFoundation
import Foundation

final class MetadataService {
  private let security = SecurityScopedBookmarkManager()

  func enrich(_ clip: inout Clip) async {
    let url = URL(fileURLWithPath: clip.currentPath)
    await security.withAccessAsync(to: url) {
      let asset = AVURLAsset(url: url)
      do {
        let duration = try await asset.load(.duration)
        clip.duration = (duration.isValid && !duration.isIndefinite && duration.seconds.isFinite) ? duration.seconds : nil
        if let creationDateItem = try? await asset.load(.creationDate),
          let metadataDate = creationDateItem.dateValue {
          clip.capturedAt = metadataDate
          clip.shotStartTime = metadataDate
          if clip.manualShotTime == nil {
            clip.shotTimeSource = .cameraMetadata
          }
        } else if let createdAt = clip.createdAt {
          clip.shotStartTime = createdAt
          if clip.manualShotTime == nil { clip.shotTimeSource = .fileCreationDate }
        } else if let modifiedAt = clip.modifiedAt {
          clip.shotStartTime = modifiedAt
          if clip.manualShotTime == nil { clip.shotTimeSource = .fileModifiedDate }
        }
        if let duration = clip.duration, duration > 0 {
          clip.estimatedBitrate = Double(clip.fileSize * 8) / duration
        }
      } catch {
        clip.previewUnavailable = true
        clip.errorMessage = "Copied and verified — preview unavailable on this Mac."
      }
      do {
        let tracks = try await asset.loadTracks(withMediaType: .video)
        if let track = tracks.first {
          let size = try await track.load(.naturalSize).applying(try await track.load(.preferredTransform))
          clip.width = Int(abs(size.width))
          clip.height = Int(abs(size.height))
          clip.frameRate = Double(try await track.load(.nominalFrameRate))
          if let desc = try await track.load(.formatDescriptions).first {
            clip.codec = CMFormatDescriptionGetMediaSubType(desc).fourCC
          }
          clip.orientation = abs(size.height) > abs(size.width) ? "Portrait" : "Landscape"
        }
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        clip.hasAudio = !audioTracks.isEmpty
        if let audioDescription = try await audioTracks.first?.load(.formatDescriptions).first,
          let layout = CMAudioFormatDescriptionGetStreamBasicDescription(audioDescription) {
          clip.audioChannelCount = Int(layout.pointee.mChannelsPerFrame)
        }
      } catch {
        clip.previewUnavailable = true
      }
      clip.automaticTags = automaticTags(for: clip)
    }
  }

  private func automaticTags(for clip: Clip) -> [String] {
    var tags: [String] = []
    if clip.sonyCardFolderPath != nil || clip.originalSourcePath.contains("PRIVATE/M4ROOT") { tags.append("Sony") }
    if (clip.width ?? 0) >= 3840 || (clip.height ?? 0) >= 2160 { tags.append("4K") }
    if let frameRate = clip.frameRate, frameRate >= 59, frameRate <= 61 { tags.append("60p") }
    if clip.hasAudio == false { tags.append("No Audio") }
    if clip.fileSize > 4 * 1024 * 1024 * 1024 { tags.append("Large File") }
    if let duration = clip.duration, duration < 15 { tags.append("Short Clip") }
    if let duration = clip.duration, duration > 10 * 60 { tags.append("Long Clip") }
    return Array(Set(tags)).sorted()
  }
}

extension FourCharCode {
  var fourCC: String {
    String(
      bytes: [
        UInt8((self >> 24) & 0xff), UInt8((self >> 16) & 0xff), UInt8((self >> 8) & 0xff),
        UInt8(self & 0xff),
      ], encoding: .macOSRoman) ?? "----"
  }
}
