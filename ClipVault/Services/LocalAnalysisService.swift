import Foundation

struct LocalAnalysisService {
  func tags(for clip: Clip) -> [String] {
    var tags = Set(clip.automaticTags)

    if let width = clip.width, width >= 3840 { tags.insert("4K") }
    if let frameRate = clip.frameRate, frameRate >= 59.0 { tags.insert("60p") }
    if clip.hasAudio == true { tags.insert("Has Audio") }
    if clip.hasAudio == false { tags.insert("No Audio") }
    if let duration = clip.duration, duration < 30 { tags.insert("Short Clip") }
    if let duration = clip.duration, duration >= 300 { tags.insert("Long Clip") }
    if clip.fileSize >= 5_000_000_000 { tags.insert("Large File") }
    if clip.originalSourcePath.localizedCaseInsensitiveContains("PRIVATE/M4ROOT") || clip.sonyCardFolderPath != nil {
      tags.insert("Sony")
    }

    return Array(tags).sorted()
  }
}

struct CoreImageAnalysisService {}
struct VisionAnalysisService {}
