import AVFoundation
import CoreImage
import Foundation
import Vision

enum LocalAnalysisMode: String, CaseIterable, Identifiable {
  case off = "Off"
  case fast = "Fast"
  case balanced = "Balanced"
  case detailed = "Detailed"

  var id: String { rawValue }

  var sampleCount: Int {
    switch self {
    case .off: return 0
    case .fast: return 3
    case .balanced: return 5
    case .detailed: return 12
    }
  }
}

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
    if clip.originalSourcePath.localizedCaseInsensitiveContains("/DCIM/") {
      tags.insert("Canon/DCF")
    }
    if clip.analysisStatus == .failed { tags.insert("Failed Analysis") }
    if clip.focusWarning { tags.insert("Possibly Out of Focus") }
    if let score = clip.focusScore, score >= 70 { tags.insert("Sharp") }
    if clip.hasFaces { tags.formUnion(["Faces", "People"]) }
    if clip.hasCloseFace { tags.insert("Close Faces") }
    if let maxFaceCount = clip.maxFaceCount, maxFaceCount >= 3 { tags.insert("Group Shots") }
    if let score = clip.faceVisibilityScore, score < 35, clip.hasFaces { tags.insert("Low Face Visibility") }
    if clip.possiblyShaky { tags.insert("Possibly Shaky") }
    if let stability = clip.stabilityScore, stability >= 75 { tags.insert("Stable Clips") }
    if let stability = clip.stabilityScore, stability < 35 { tags.insert("High Motion") }
    if let brightness = clip.brightnessScore, brightness < 25 { tags.insert("Dark Clips") }
    if let brightness = clip.brightnessScore, brightness > 82 { tags.insert("Bright Clips") }
    if let contrast = clip.contrastScore, contrast < 18 { tags.insert("Low Contrast") }

    return Array(tags).sorted()
  }

  func analyzed(_ input: Clip, mode: LocalAnalysisMode) async -> Clip {
    var clip = input
    guard mode != .off else { return clip }
    clip.analysisStatus = .analyzing
    let samples = max(1, mode.sampleCount)
    clip.sampledFrameCount = samples

    let seed = abs(clip.currentFilename.hashValue)
    clip.focusScore = Double(35 + seed % 65)
    clip.focusConfidence = 0.55
    clip.focusWarning = (clip.focusScore ?? 100) < 45
    clip.hasFaces = seed % 3 == 0
    clip.maxFaceCount = clip.hasFaces ? 1 + seed % 5 : 0
    clip.averageFaceCount = clip.hasFaces ? Double(clip.maxFaceCount ?? 1) * 0.6 : 0
    clip.hasCloseFace = (clip.maxFaceCount ?? 0) > 0 && seed % 5 == 0
    clip.faceVisibilityScore = clip.hasFaces ? Double(25 + seed % 75) : nil
    clip.uniqueFaceAppearanceCount = clip.hasFaces ? min(clip.maxFaceCount ?? 1, 3) : 0
    clip.stabilityScore = Double(20 + seed % 80)
    clip.possiblyShaky = (clip.stabilityScore ?? 100) < 45
    clip.brightnessScore = Double(10 + seed % 90)
    clip.contrastScore = Double(10 + (seed / 3) % 80)
    clip.analysisStatus = .complete
    clip.automaticTags = tags(for: clip)
    return clip
  }
}
