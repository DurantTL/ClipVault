import SwiftUI

struct SettingsView: View {
  @EnvironmentObject var settings: AppSettings
  var body: some View {
    Form {
      Picker("Verification mode", selection: $settings.verificationModeRaw) {
        ForEach(VerificationMode.allCases) { Text($0.label).tag($0.rawValue) }
      }
      Text(
        "Fast size check is the default and avoids rereading the SD card after copy. Strong SHA256 is safer, but much slower for large Sony a7R V 4K60 4:2:2 10-bit footage because it hashes both source and destination."
      ).font(.caption).foregroundStyle(.secondary)
      Toggle("Preserve source folder structure", isOn: $settings.preserveSourceStructure)
      Picker("Thumbnail quality", selection: $settings.thumbnailQualityRaw) {
        ForEach(ThumbnailQuality.allCases) { Text($0.rawValue.capitalized).tag($0.rawValue) }
      }
      Toggle("Show hidden technical details", isOn: $settings.showTechnicalDetails)
      Toggle("Include Proxy Files", isOn: $settings.includeProxyFiles)
    }.padding().frame(width: 420)
  }
}
