import SwiftUI

final class AppSettings: ObservableObject {
  @AppStorage("verificationMode") var verificationModeRaw = VerificationMode.fast.rawValue
  @AppStorage("preserveSourceStructure") var preserveSourceStructure = true
  @AppStorage("thumbnailQuality") var thumbnailQualityRaw = ThumbnailQuality.balanced.rawValue
  @AppStorage("showTechnicalDetails") var showTechnicalDetails = false
  @AppStorage("includeProxyFiles") var includeProxyFiles = false
  var verificationMode: VerificationMode {
    VerificationMode(rawValue: verificationModeRaw) ?? .fast
  }
  var thumbnailQuality: ThumbnailQuality {
    ThumbnailQuality(rawValue: thumbnailQualityRaw) ?? .balanced
  }
}
