import SwiftUI

struct SettingsView: View {
  @EnvironmentObject var settings: AppSettings

  var body: some View {
    Form {
      Section("Ingest") {
        Picker("Default verification mode", selection: $settings.verificationModeRaw) {
          ForEach(VerificationMode.allCases) { Text($0.label).tag($0.rawValue) }
        }
        Toggle("Preserve source folder structure", isOn: $settings.preserveSourceStructure)
        Toggle("Include Sony proxies by default", isOn: $settings.includeProxyFiles)
        Picker("Thumbnail quality", selection: $settings.thumbnailQualityRaw) {
          ForEach(ThumbnailQuality.allCases) { Text($0.rawValue.capitalized).tag($0.rawValue) }
        }
      }

      Section("Culling") {
        Toggle("Auto-advance after rating", isOn: $settings.autoAdvanceAfterRating)
        Toggle("Skip already rated clips", isOn: $settings.skipAlreadyRatedClips)
        Toggle("Loop at end", isOn: $settings.loopAtEnd)
        Toggle("Advance direction: Previous", isOn: $settings.advanceDirectionPrevious)
      }

      Section("Performance") {
        Picker("Performance mode", selection: $settings.performanceModeRaw) {
          ForEach(PerformanceMode.allCases) { Text($0.rawValue).tag($0.rawValue) }
        }
        Text("Automatic tunes thumbnail and analysis concurrency from Apple Silicon, memory, and Metal availability.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section("Analysis and Export") {
        Picker("Local analysis mode", selection: $settings.localAnalysisMode) {
          ForEach(["Off", "Fast", "Balanced", "Detailed"], id: \.self) { Text($0).tag($0) }
        }
      }
    }
    .padding()
    .frame(width: 500)
  }
}
