import AppKit
import Foundation
import SwiftUI

extension LibraryViewModel {
  func previewSelected() {
    guard let clip = selectedClip else { return }
    if canPreview(clip) {
      previewClip = clip
    } else {
      logPreviewFailure(for: clip, reason: previewFailureMessage(for: clip))
      previewClip = clip
    }
  }

  func resolvedMediaURL(for clip: Clip, in project: ClipVaultProject? = nil) -> URL? {
    let project = project ?? self.project
    let candidates = mediaURLCandidates(for: clip, in: project)
    return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
  }

  func thumbnailURL(for clip: Clip, in project: ClipVaultProject? = nil) -> URL {
    thumbnailCoordinator.thumbnailURL(for: clip, in: project ?? self.project)
  }

  func existingThumbnailURL(for clip: Clip, in project: ClipVaultProject? = nil) -> URL? {
    thumbnailCoordinator.existingThumbnailURL(for: clip, in: project ?? self.project)
  }

  func queueThumbnailGenerationIfNeeded(for clip: Clip) {
    guard clip.copyStatus != .pending, clip.copyStatus != .copying else { return }
    guard existingThumbnailURL(for: clip) == nil else { return }
    guard resolvedMediaURL(for: clip) != nil else { return }
    guard clip.thumbnailStatus != .generating else { return }
    queueThumbnailGeneration(for: [clip.id], force: false)
  }

  func generateMissingThumbnails() {
    let ids = project.clips.filter { clip in
      clip.copyStatus != .pending &&
        clip.copyStatus != .copying &&
        existingThumbnailURL(for: clip) == nil &&
        resolvedMediaURL(for: clip) != nil
    }.map(\.id)
    queueThumbnailGeneration(for: ids, force: false)
  }

  func regenerateThumbnailForSelectedClip() {
    guard let selectedClipID else { return }
    queueThumbnailGeneration(for: [selectedClipID], force: true)
  }

  func regenerateThumbnailsForSelectedClips() {
    queueThumbnailGeneration(for: Array(activeSelectionIDs), force: true)
  }

  func canPreview(_ clip: Clip) -> Bool {
    guard clip.copyStatus == .copied || clip.verificationStatus == .copied || clip.verificationStatus == .verified || clip.copyStatus == .failed else {
      return false
    }
    return resolvedMediaURL(for: clip) != nil
  }

  func previewFailureMessage(for clip: Clip) -> String {
    if clip.copyStatus == .pending || clip.copyStatus == .copying || clip.copyStatus == .skipped {
      return "Could not preview this clip. It is pending/not copied yet."
    }
    let candidates = mediaURLCandidates(for: clip, in: project)
    if candidates.isEmpty {
      return "Could not preview this clip. No destination path is stored."
    }
    if candidates.contains(where: { !FileManager.default.isReadableFile(atPath: $0.path) && FileManager.default.fileExists(atPath: $0.path) }) {
      return "Could not preview this clip. Permission denied."
    }
    return "Could not preview this clip. The file is missing or uses an unsupported codec."
  }

  func logPreviewFailure(for clip: Clip, reason: String, avPlayerError: Error? = nil) {
    let url = resolvedMediaURL(for: clip)
    let exists = url.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    print("""
    Preview failure: filename=\(clip.currentFilename), reason=\(reason), resolvedURL=\(url?.path ?? "nil"), fileExists=\(exists), copyStatus=\(clip.copyStatus.rawValue), verificationStatus=\(clip.verificationStatus.rawValue), thumbnailStatus=\(clip.thumbnailStatus.rawValue), avPlayerError=\(avPlayerError?.localizedDescription ?? "none")
    """)
  }

  func closePreview() { previewClip = nil }
}
