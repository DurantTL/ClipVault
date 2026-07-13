import AppKit
import SwiftUI

struct SettingsView: View {
  @EnvironmentObject var settings: AppSettings
  @State private var localPreviewUsage: Int64 = 0
  @State private var internalAvailable: Int64?
  @State private var storageMessage = ""

  private enum FolderKind {
    case sourcePreview
    case projectThumbnails
    case backup1
    case backup2
  }

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

      Section("Storage & Cache") {
        Picker("Storage preset", selection: storagePresetBinding) {
          ForEach(StoragePreset.allCases) { Text($0.rawValue).tag($0.rawValue) }
        }

        GroupBox("Where SlateBox Stores Things") {
          Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
            storageMapRow("Original video files", "Selected ingest destination")
            storageMapRow("Partial/resume video files", "Beside the final video — fixed for safety")
            storageMapRow("Project metadata", "Inside the project folder — fixed")
            storageMapRow("Source preview JPEGs", sourcePreviewLocationDescription)
            storageMapRow("Project/library thumbnails", projectThumbnailLocationDescription)
            storageMapRow("Exports and edit handoff", "Ask every time")
            storageMapRow("Diagnostic logging", "macOS unified log")
          }
          .padding(.vertical, 4)
        }

        Picker("Source preview thumbnails", selection: sourcePreviewLocationBinding) {
          ForEach(SourcePreviewStorageLocation.allCases) { Text($0.rawValue).tag($0.rawValue) }
        }
        Text("These are small JPEGs shown before ingest. Choosing Project Destination or Custom Folder avoids storing them on the Mac.")
          .font(.caption)
          .foregroundStyle(.secondary)

        if settings.sourcePreviewStorageLocation == .customFolder {
          folderChooser(
            label: "Source preview folder",
            path: settings.sourcePreviewCustomFolderPath,
            choose: { chooseFolder(.sourcePreview) },
            clear: {
              settings.sourcePreviewCustomFolderPath = ""
              settings.sourcePreviewCustomFolderBookmarkBase64 = ""
            }
          )
        }

        Picker("Project/library thumbnails", selection: projectThumbnailLocationBinding) {
          ForEach(ProjectThumbnailStorageLocation.allCases) { Text($0.rawValue).tag($0.rawValue) }
        }
        Text("This controls newly generated library thumbnails. Existing project thumbnails remain usable in their current location.")
          .font(.caption)
          .foregroundStyle(.secondary)

        if settings.projectThumbnailStorageLocation == .customFolder {
          folderChooser(
            label: "Project thumbnail folder",
            path: settings.projectThumbnailCustomFolderPath,
            choose: { chooseFolder(.projectThumbnails) },
            clear: {
              settings.projectThumbnailCustomFolderPath = ""
              settings.projectThumbnailCustomFolderBookmarkBase64 = ""
            }
          )
        }

        Picker("Source preview cache limit", selection: previewLimitBinding) {
          ForEach([100, 250, 500, 1_024, 2_048, 5_120], id: \.self) { value in
            Text(value >= 1_024 ? "\(value / 1_024) GB" : "\(value) MB").tag(value)
          }
        }

        Picker("Clear source previews", selection: previewCleanupBinding) {
          ForEach(SourcePreviewCleanupPolicy.allCases) { Text($0.rawValue).tag($0.rawValue) }
        }

        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text("Mac preview cache: \(FileSizeFormatterUtil.string(localPreviewUsage))")
            Text("Available on Mac: \(internalAvailable.map(FileSizeFormatterUtil.string) ?? "Unavailable")")
              .foregroundStyle(.secondary)
          }
          Spacer()
          Button("Reveal") { reveal(StoragePreferences.internalSourcePreviewDirectory) }
          Button("Clear Mac Preview Cache") { clearMacPreviewCache() }
        }

        if !storageMessage.isEmpty {
          Text(storageMessage)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      Section("Backup Destinations") {
        Picker("Copy during ingest", selection: $settings.backupTransferMode) {
          ForEach(["Primary only", "Primary + Backup 1", "Primary + Backup 1 + Backup 2"], id: \.self) {
            Text($0).tag($0)
          }
        }

        folderChooser(
          label: "Backup 1",
          path: settings.backupDestination1Path,
          choose: { chooseFolder(.backup1) },
          clear: {
            settings.backupDestination1Path = ""
            settings.backupDestination1BookmarkBase64 = ""
          }
        )

        folderChooser(
          label: "Backup 2",
          path: settings.backupDestination2Path,
          choose: { chooseFolder(.backup2) },
          clear: {
            settings.backupDestination2Path = ""
            settings.backupDestination2BookmarkBase64 = ""
          }
        )

        Text("Each backup can be a different external drive or NAS folder. SlateBox remembers access using a macOS security-scoped bookmark.")
          .font(.caption)
          .foregroundStyle(.secondary)
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
    .frame(width: 720, minHeight: 720)
    .onAppear { refreshStorageInformation() }
  }

  private var storagePresetBinding: Binding<String> {
    Binding(
      get: { settings.storagePresetRaw },
      set: { raw in
        settings.applyStoragePreset(StoragePreset(rawValue: raw) ?? .custom)
        refreshStorageInformation()
      }
    )
  }

  private var sourcePreviewLocationBinding: Binding<String> {
    Binding(
      get: { settings.sourcePreviewStorageLocationRaw },
      set: { value in
        settings.sourcePreviewStorageLocationRaw = value
        settings.storagePresetRaw = StoragePreset.custom.rawValue
      }
    )
  }

  private var projectThumbnailLocationBinding: Binding<String> {
    Binding(
      get: { settings.projectThumbnailStorageLocationRaw },
      set: { value in
        settings.projectThumbnailStorageLocationRaw = value
        settings.storagePresetRaw = StoragePreset.custom.rawValue
      }
    )
  }

  private var previewLimitBinding: Binding<Int> {
    Binding(
      get: { settings.sourcePreviewCacheLimitMB },
      set: { value in
        settings.sourcePreviewCacheLimitMB = value
        settings.storagePresetRaw = StoragePreset.custom.rawValue
      }
    )
  }

  private var previewCleanupBinding: Binding<String> {
    Binding(
      get: { settings.sourcePreviewCleanupPolicyRaw },
      set: { value in
        settings.sourcePreviewCleanupPolicyRaw = value
        settings.storagePresetRaw = StoragePreset.custom.rawValue
      }
    )
  }

  private var sourcePreviewLocationDescription: String {
    switch settings.sourcePreviewStorageLocation {
    case .macInternal:
      return StoragePreferences.internalSourcePreviewDirectory.path
    case .projectDestination:
      return "Selected project/.clipvault-cache/ingest-previews"
    case .customFolder:
      return settings.sourcePreviewCustomFolderPath.isEmpty
        ? "Custom folder not selected"
        : settings.sourcePreviewCustomFolderPath
    case .disabled:
      return "Disabled"
    }
  }

  private var projectThumbnailLocationDescription: String {
    switch settings.projectThumbnailStorageLocation {
    case .projectFolder:
      return "Each project/.clipvault-cache/thumbnails"
    case .macInternal:
      return StoragePreferences.internalCacheRoot
        .appendingPathComponent("ProjectThumbnails", isDirectory: true).path
    case .customFolder:
      return settings.projectThumbnailCustomFolderPath.isEmpty
        ? "Custom folder not selected"
        : settings.projectThumbnailCustomFolderPath
    }
  }

  @ViewBuilder
  private func storageMapRow(_ name: String, _ location: String) -> some View {
    GridRow {
      Text(name).fontWeight(.medium)
      Text(location)
        .foregroundStyle(.secondary)
        .lineLimit(2)
        .textSelection(.enabled)
    }
  }

  @ViewBuilder
  private func folderChooser(
    label: String,
    path: String,
    choose: @escaping () -> Void,
    clear: @escaping () -> Void
  ) -> some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text(label).fontWeight(.medium)
        Text(path.isEmpty ? "Not selected" : path)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
          .textSelection(.enabled)
      }
      Spacer()
      if !path.isEmpty {
        Button("Reveal") { reveal(URL(fileURLWithPath: path, isDirectory: true)) }
        Button("Reset") { clear() }
      }
      Button("Choose Folder…") { choose() }
    }
  }

  private func chooseFolder(_ kind: FolderKind) {
    let panel = NSOpenPanel()
    panel.title = "Choose Storage Folder"
    panel.message = "Choose an external drive, NAS folder, or a folder on this Mac."
    panel.prompt = "Use This Folder"
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true
    guard panel.runModal() == .OK, let url = panel.url else { return }

    let bookmark = (try? SecurityScopedBookmarkManager().bookmark(for: url))?.base64EncodedString() ?? ""
    switch kind {
    case .sourcePreview:
      settings.sourcePreviewCustomFolderPath = url.path
      settings.sourcePreviewCustomFolderBookmarkBase64 = bookmark
      settings.sourcePreviewStorageLocationRaw = SourcePreviewStorageLocation.customFolder.rawValue
      settings.storagePresetRaw = StoragePreset.custom.rawValue
    case .projectThumbnails:
      settings.projectThumbnailCustomFolderPath = url.path
      settings.projectThumbnailCustomFolderBookmarkBase64 = bookmark
      settings.projectThumbnailStorageLocationRaw = ProjectThumbnailStorageLocation.customFolder.rawValue
      settings.storagePresetRaw = StoragePreset.custom.rawValue
    case .backup1:
      settings.backupDestination1Path = url.path
      settings.backupDestination1BookmarkBase64 = bookmark
    case .backup2:
      settings.backupDestination2Path = url.path
      settings.backupDestination2BookmarkBase64 = bookmark
    }
    refreshStorageInformation()
  }

  private func clearMacPreviewCache() {
    let result = StoragePreferences.clearFolderContents(at: StoragePreferences.internalSourcePreviewDirectory)
    storageMessage = "Cleared \(result.files) item(s), freeing \(FileSizeFormatterUtil.string(result.bytes))."
    refreshStorageInformation()
  }

  private func refreshStorageInformation() {
    localPreviewUsage = StoragePreferences.folderUsage(at: StoragePreferences.internalSourcePreviewDirectory)
    internalAvailable = VolumeCapacity.availableCapacity(for: StoragePreferences.internalCacheRoot)
  }

  private func reveal(_ url: URL) {
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }
}
