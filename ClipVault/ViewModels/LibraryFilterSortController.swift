import Foundation

/// Filter and sort collaborator for `LibraryViewModel`.
@MainActor
final class LibraryFilterSortController {
  var smartFolders: [String] {
    ["Unrated", "Keep", "Maybe", "Reject", "Needs Review"]
  }

  func matchesFilter(_ clip: Clip, filter: String) -> Bool {
    switch filter {
    case "All Clips": return true
    case "Unrated": return clip.cullStatus == .unrated
    case "Keep": return clip.cullStatus == .keep
    case "Maybe": return clip.cullStatus == .maybe
    case "Reject": return clip.cullStatus == .reject
    case "Needs Review":
      return clip.cullStatus == .unrated
        || clip.analysisStatus == .failed
        || clip.verificationStatus == .failed
        || clip.errorMessage != nil
    case "Favorites (5-Star)": return clip.rating == 5
    case "4+ Stars": return clip.rating >= 4
    case "Top Pick Suggestions": return clip.automaticTags.contains("Top Pick Suggestion")
    case "Social Pick Suggestions": return clip.automaticTags.contains("Social Pick Suggestion")
    case "Verified": return clip.verificationStatus == .verified
    case "Failed", "Failed Verification": return clip.verificationStatus == .failed
    case "Has Audio": return clip.hasAudio == true || clip.automaticTags.contains("Has Audio")
    case "No Audio": return clip.hasAudio == false || clip.automaticTags.contains("No Audio")
    case "Short Clip", "Short Clips": return (clip.duration ?? .infinity) < 30 || clip.automaticTags.contains("Short Clip")
    case "Long Clip", "Long Clips": return (clip.duration ?? 0) >= 300 || clip.automaticTags.contains("Long Clip")
    case "Large Files": return clip.fileSize >= 5_000_000_000 || clip.automaticTags.contains("Large File")
    case "Recently Ingested": return clip.ingestDate.map { Calendar.current.dateComponents([.day], from: $0, to: Date()).day ?? 99 <= 7 } ?? false
    case "Failed Preview": return clip.previewUnavailable || clip.thumbnailPath == nil
    case "Canon/DCF": return clip.automaticTags.contains("Canon/DCF") || clip.originalSourcePath.localizedCaseInsensitiveContains("/DCIM/")
    case "Possibly Out of Focus", "Faces", "Group Shots", "Close Faces", "Low Face Visibility", "Possibly Shaky", "Stable Clips", "High Motion", "Dark Clips", "Bright Clips", "Low Contrast", "Sharp Clips", "Balanced Exposure", "Warm Color", "Cool Color", "Approx. WB", "Failed Analysis":
      return clip.automaticTags.contains(filter)
    case "Social Candidates": return clip.isSocialClipCandidate
    case "Interviews": return clip.isInterview
    case "B-Roll": return clip.isBroll || clip.assignedFolder == filter
    case "Sermon": return clip.isSermon || clip.assignedFolder == filter
    case "Duplicate Candidates": return clip.automaticTags.contains("Duplicate Candidate")
    default:
      return clip.assignedFolder == filter || clip.productionTags.contains(filter) || clip.automaticTags.contains(filter)
    }
  }

  func sorted(_ clips: [Clip], option: ClipSortOption, ascending: Bool) -> [Clip] {
    let sorted: [Clip]
    switch option {
    case .ingestOrder: sorted = clips.sorted { ($0.ingestDate ?? .distantPast) < ($1.ingestDate ?? .distantPast) }
    case .shotTime: sorted = clips.sorted { ($0.effectiveShotTime ?? $0.ingestDate ?? .distantPast) < ($1.effectiveShotTime ?? $1.ingestDate ?? .distantPast) }
    case .filename: sorted = clips.sorted { $0.currentFilename.localizedStandardCompare($1.currentFilename) == .orderedAscending }
    case .createdDate: sorted = clips.sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
    case .modifiedDate: sorted = clips.sorted { ($0.modifiedAt ?? .distantPast) < ($1.modifiedAt ?? .distantPast) }
    case .duration: sorted = clips.sorted { ($0.duration ?? 0) < ($1.duration ?? 0) }
    case .fileSize: sorted = clips.sorted { $0.fileSize < $1.fileSize }
    case .cullStatus: sorted = clips.sorted { $0.cullStatus.rawValue < $1.cullStatus.rawValue }
    case .ratingKeepStatus, .rating: sorted = clips.sorted { ($0.rating, $0.cullStatus.rawValue) < ($1.rating, $1.cullStatus.rawValue) }
    case .qualityScore: sorted = clips.sorted { ($0.analysisQualityScore ?? -1) < ($1.analysisQualityScore ?? -1) }
    case .cameraType: sorted = clips.sorted { ($0.cardVolumeName ?? "").localizedStandardCompare($1.cardVolumeName ?? "") == .orderedAscending }
    }
    return ascending ? sorted : Array(sorted.reversed())
  }

  func filteredClips(
    from project: ClipVaultProject,
    filter: String,
    sortOption: ClipSortOption,
    ascending: Bool
  ) -> [Clip] {
    let clips = project.clips.filter { matchesFilter($0, filter: filter) }
    return sorted(clips, option: sortOption, ascending: ascending)
  }

  func clipCount(in project: ClipVaultProject, filter: String) -> Int {
    project.clips.filter { matchesFilter($0, filter: filter) }.count
  }
}
