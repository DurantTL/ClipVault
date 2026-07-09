import SwiftUI

enum PerformanceMode: String, CaseIterable, Identifiable {
  case automatic = "Automatic"
  case fast = "Fast"
  case balanced = "Balanced"
  case quality = "Quality"

  var id: String { rawValue }
}

struct PerformanceTuning {
  let ingestPreviewThumbnailConcurrency: Int
  let libraryThumbnailConcurrency: Int
  let analysisConcurrency: Int
  let analysisMode: LocalAnalysisMode
  let contactSheetEnabled: Bool
  let backgroundPriority: TaskPriority
}

final class AppSettings: ObservableObject {
  @AppStorage("verificationMode") var verificationModeRaw = VerificationMode.fast.rawValue
  @AppStorage("preserveSourceStructure") var preserveSourceStructure = false
  @AppStorage("thumbnailQuality") var thumbnailQualityRaw = ThumbnailQuality.balanced.rawValue
  @AppStorage("showTechnicalDetails") var showTechnicalDetails = false
  @AppStorage("includeProxyFiles") var includeProxyFiles = false
  @AppStorage("autoAdvanceAfterRating") var autoAdvanceAfterRating = false
  @AppStorage("skipAlreadyRatedClips") var skipAlreadyRatedClips = false
  @AppStorage("loopAtEnd") var loopAtEnd = false
  @AppStorage("advanceDirectionPrevious") var advanceDirectionPrevious = false
  @AppStorage("localAnalysisMode") var localAnalysisMode = "Off"
  @AppStorage("backupTransferMode") var backupTransferMode = "Primary only"
  @AppStorage("backupDestination1Path") var backupDestination1Path = ""
  @AppStorage("backupDestination2Path") var backupDestination2Path = ""
  @AppStorage("finderTagsExport") var finderTagsExport = false
  @AppStorage("xmpSidecarExport") var xmpSidecarExport = false
  @AppStorage("renameFilesDuringIngest") var renameFilesDuringIngest = false
  @AppStorage("generateThumbnailsDuringIngest") var generateThumbnailsDuringIngest = true
  @AppStorage("runAnalysisAfterIngest") var runAnalysisAfterIngest = false
  @AppStorage("generateContactSheetsAfterIngest") var generateContactSheetsAfterIngest = false
  @AppStorage("performanceMode") var performanceModeRaw = PerformanceMode.automatic.rawValue

  static var autoAdvanceAfterRating: Bool {
    UserDefaults.standard.bool(forKey: "autoAdvanceAfterRating")
  }

  static var advanceDirectionPrevious: Bool {
    UserDefaults.standard.bool(forKey: "advanceDirectionPrevious")
  }

  var verificationMode: VerificationMode {
    VerificationMode(rawValue: verificationModeRaw) ?? .fast
  }

  var thumbnailQuality: ThumbnailQuality {
    ThumbnailQuality(rawValue: thumbnailQualityRaw) ?? .balanced
  }

  var performanceMode: PerformanceMode {
    PerformanceMode(rawValue: performanceModeRaw) ?? .automatic
  }

  func performanceTuning(profile: SystemPerformanceProfile = .current()) -> PerformanceTuning {
    switch performanceMode {
    case .automatic:
      return PerformanceTuning(
        ingestPreviewThumbnailConcurrency: profile.recommendedThumbnailConcurrency,
        libraryThumbnailConcurrency: profile.recommendedThumbnailConcurrency,
        analysisConcurrency: profile.recommendedAnalysisConcurrency,
        analysisMode: profile.supportsHeavyAnalysis ? .balanced : .fast,
        contactSheetEnabled: profile.supportsHeavyAnalysis,
        backgroundPriority: .utility
      )
    case .fast:
      return PerformanceTuning(
        ingestPreviewThumbnailConcurrency: max(1, min(2, profile.recommendedThumbnailConcurrency)),
        libraryThumbnailConcurrency: max(1, min(2, profile.recommendedThumbnailConcurrency)),
        analysisConcurrency: 1,
        analysisMode: .fast,
        contactSheetEnabled: false,
        backgroundPriority: .background
      )
    case .balanced:
      return PerformanceTuning(
        ingestPreviewThumbnailConcurrency: max(2, profile.recommendedThumbnailConcurrency),
        libraryThumbnailConcurrency: max(2, profile.recommendedThumbnailConcurrency),
        analysisConcurrency: profile.recommendedAnalysisConcurrency,
        analysisMode: .balanced,
        contactSheetEnabled: generateContactSheetsAfterIngest,
        backgroundPriority: .utility
      )
    case .quality:
      return PerformanceTuning(
        ingestPreviewThumbnailConcurrency: profile.recommendedThumbnailConcurrency,
        libraryThumbnailConcurrency: profile.recommendedThumbnailConcurrency,
        analysisConcurrency: profile.recommendedAnalysisConcurrency,
        analysisMode: .detailed,
        contactSheetEnabled: true,
        backgroundPriority: .utility
      )
    }
  }
}
