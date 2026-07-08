import SwiftUI

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
}
