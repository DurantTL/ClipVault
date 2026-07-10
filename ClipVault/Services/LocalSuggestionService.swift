import Foundation

protocol LocalSuggestionService {
  func suggestedTags(for clip: Clip) -> [String]
  func projectDescription(for project: ClipVaultProject) -> String
  func suggestedFolderName(for clips: [Clip]) -> String?
}

struct RuleBasedSuggestionService: LocalSuggestionService {
  func suggestedTags(for clip: Clip) -> [String] {
    var tags = clip.automaticTags
    if clip.favorite { tags.append("Favorite") }
    if clip.isSocialClipCandidate { tags.append("Social Candidate") }
    return Array(Set(tags)).sorted()
  }

  func projectDescription(for project: ClipVaultProject) -> String {
    "Local \(AppBrand.appName) project with \(project.clips.count) clips."
  }

  func suggestedFolderName(for clips: [Clip]) -> String? {
    clips.first?.effectiveShotTime.map {
      let formatter = DateFormatter()
      formatter.dateFormat = "yyyy-MM-dd"
      return formatter.string(from: $0)
    }
  }
}

struct FoundationModelSuggestionService: LocalSuggestionService {
  private let fallback = RuleBasedSuggestionService()

  func suggestedTags(for clip: Clip) -> [String] {
    if #available(macOS 26.0, *) {
      return fallback.suggestedTags(for: clip)
    }
    return fallback.suggestedTags(for: clip)
  }

  func projectDescription(for project: ClipVaultProject) -> String {
    if #available(macOS 26.0, *) {
      return fallback.projectDescription(for: project)
    }
    return fallback.projectDescription(for: project)
  }

  func suggestedFolderName(for clips: [Clip]) -> String? {
    fallback.suggestedFolderName(for: clips)
  }
}
