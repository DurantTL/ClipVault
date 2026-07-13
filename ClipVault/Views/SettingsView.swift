import AppKit
import SwiftUI

struct SettingsView: View {
  @EnvironmentObject var settings: AppSettings
  @State private var selectedTab: SettingsTab = .storage
  @State private var localPreviewUsage: Int64 = 0
  @State private var internalAvailable: Int64?
  @State private var storageMessage = ""

  private enum SettingsTab: Hashable {
    case ingest
    case storage
    case workflow
    case performance
  }

  private enum FolderKind {
    case sourcePreview
    case projectThumbnails
    case backup1
    case backup2
  }

  var body: some View {
    TabView(selection: $selectedTab) {
      ingestPage
        .tabItem { Label("Ingest", systemImage: "tray.and.arrow.down") }
        .tag(SettingsTab.ingest)

      storagePage
        .tabItem { Label("Storage", systemImage: "externaldrive") }
        .tag(SettingsTab.storage)

      workflowPage
        .tabItem { Label("Workflow", systemImage: "film.stack") }
        .tag(SettingsTab.workflow)

      performancePage
        .tabItem { Label("Performance", systemImage: "gauge.with.dots.needle.67percent") }
        .tag(SettingsTab.performance)
    }
    .frame(minWidth: 780, idealWidth: 900, minHeight: 560, idealHeight: 700)
    .onAppear { refreshStorageInformation() }
  }

  private var ingestPage: some View {
    settingsScrollPage {
      settingsCard("Ingest Defaults") {
        settingRow(
          "Verification mode",
          description: "Fast compares file sizes. Strong verification also checks file contents."
        ) {
          Picker("", selection: $settings.verificationModeRaw) {
            ForEach(VerificationMode.allCases) { Text($0.label).tag($0.rawValue) }
          }
          .labelsHidden()
          .frame(maxWidth: 260)
        }

        rowDivider

        settingRow(
          "Preserve source folders",
          description: "Keep the camera card's folder structure inside the project destination."
        ) {
          Toggle("", isOn: $settings.preserveSourceStructure)
            .labelsHidden()
        }

        rowDivider

        settingRow(
          "Include Sony proxies",
          description: "Include files from Sony proxy folders when scanning a card."
        ) {
          Toggle("", isOn: $settings.includeProxyFiles)
            .labelsHidden()
        }

        rowDivider

        settingRow(
          "Thumbnail quality",
          description: "Controls the quality and processing cost of newly generated thumbnails."
        ) {
          Picker("", selection: $settings.thumbnailQualityRaw) {
            ForEach(ThumbnailQuality.allCases) {
              Text($0.rawValue.capitalized).tag($0.rawValue)
            }
          }
          .labelsHidden()
          .frame(maxWidth: 260)
        }
      }
    }
  }

  private var storagePage: some View {
    settingsScrollPage {
      settingsCard("Storage Preset") {
        settingRow(
          "Preset",
          description: "Choose a recommended setup or select Custom to control each location separately."
        ) {
          Picker("", selection: storagePresetBinding) {
            ForEach(StoragePreset.allCases) { Text($0.rawValue).tag($0.rawValue) }
          }
          .labelsHidden()
          .frame(maxWidth: 300)
        }
      }

      settingsCard("Where SlateBox Stores Things") {
        storageMapRow("Original video files", "Selected ingest destination")
        rowDivider
        storageMapRow("Partial/resume video files", "Beside the final video on the same destination — fixed for safety")
        rowDivider
        storageMapRow("Project metadata", "Inside the project folder — fixed")
        rowDivider
        storageMapRow("Source preview JPEGs", sourcePreviewLocationDescription)
        rowDivider
        storageMapRow("Project/library thumbnails", projectThumbnailLocationDescription)
        rowDivider
        storageMapRow("Exports and edit handoff", "Ask every time")
        rowDivider
        storageMapRow("Diagnostic logging", "macOS unified log")
      }

      settingsCard("Preview and Thumbnail Locations") {
        settingRow(
          "Source preview thumbnails",
          description: "Small JPEGs shown before ingest. They never contain full-resolution video."
        ) {
          Picker("", selection: sourcePreviewLocationBinding) {
            ForEach(SourcePreviewStorageLocation.allCases) {
              Text($0.rawValue).tag($0.rawValue)
            }
          }
          .labelsHidden()
          .frame(maxWidth: 320)
        }

        if settings.sourcePreviewStorageLocation == .customFolder {
          rowDivider
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

        rowDivider

        settingRow(
          "Project/library thumbnails",
          description: "Controls where newly generated library thumbnails are stored."
        ) {
          Picker("", selection: projectThumbnailLocationBinding) {
            ForEach(ProjectThumbnailStorageLocation.allCases) {
              Text($0.rawValue).tag($0.rawValue)
            }
          }
          .labelsHidden()
          .frame(maxWidth: 320)
        }

        if settings.projectThumbnailStorageLocation == .customFolder {
          rowDivider
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
      }

      settingsCard("Preview Cache") {
        settingRow(
          "Cache limit",
          description: "SlateBox removes the oldest source-preview JPEGs when the selected limit is exceeded."
        ) {
          Picker("", selection: previewLimitBinding) {
            ForEach([100, 250, 500, 1_024, 2_048, 5_120], id: \.self) { value in
              Text(value >= 1_024 ? "\(value / 1_024) GB" : "\(value) MB").tag(value)
            }
          }
          .labelsHidden()
          .frame(maxWidth: 220)
        }

        rowDivider

        settingRow(
          "Automatic cleanup",
          description: "Choose when source-preview JPEGs are removed."
        ) {
          Picker("", selection: previewCleanupBinding) {
            ForEach(SourcePreviewCleanupPolicy.allCases) {
              Text($0.rawValue).tag($0.rawValue)
            }
          }
          .labelsHidden()
          .frame(maxWidth: 300)
        }

        rowDivider

        HStack(alignment: .center, spacing: 16) {
          VStack(alignment: .leading, spacing: 4) {
            Text("Mac preview cache")
              .fontWeight(.medium)
            Text("Using \(FileSizeFormatterUtil.string(localPreviewUsage)) • \(internalAvailable.map { FileSizeFormatterUtil.string($0) } ?? "Unavailable") available")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer(minLength: 16)
          Button("Reveal") { reveal(StoragePreferences.internalSourcePreviewDirectory) }
          Button("Clear Cache") { clearMacPreviewCache() }
        }

        if !storageMessage.isEmpty {
          Text(storageMessage)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }

      settingsCard("Backup Destinations") {
        settingRow(
          "Copy during ingest",
          description: "Create verified backup copies after the primary destination copy is complete."
        ) {
          Picker("", selection: $settings.backupTransferMode) {
            ForEach([
              "Primary only",
              "Primary + Backup 1",
              "Primary + Backup 1 + Backup 2"
            ], id: \.self) {
              Text($0).tag($0)
            }
          }
          .labelsHidden()
          .frame(maxWidth: 340)
        }

        rowDivider

        folderChooser(
          label: "Backup 1",
          path: settings.backupDestination1Path,
          choose: { chooseFolder(.backup1) },
          clear: {
            settings.backupDestination1Path = ""
            settings.backupDestination1BookmarkBase64 = ""
          }
        )

        rowDivider

        folderChooser(
          label: "Backup 2",
          path: settings.backupDestination2Path,
          choose: { chooseFolder(.backup2) },
          clear: {
            settings.backupDestination2Path = ""
            settings.backupDestination2BookmarkBase64 = ""
          }
        )

        Text("Each backup can use a different external drive or NAS folder. SlateBox remembers access with a macOS security-scoped bookmark.")
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private var workflowPage: some View {
    settingsScrollPage {
      settingsCard("Culling") {
        settingRow(
          "Auto-advance after rating",
          description: "Move to the next clip after assigning a rating or cull status."
        ) {
          Toggle("", isOn: $settings.autoAdvanceAfterRating)
            .labelsHidden()
        }

        rowDivider

        settingRow(
          "Skip already rated clips",
          description: "When advancing, bypass clips that already have a rating."
        ) {
          Toggle("", isOn: $settings.skipAlreadyRatedClips)
            .labelsHidden()
        }

        rowDivider

        settingRow(
          "Loop at end",
          description: "Return to the first clip after reaching the end of the current view."
        ) {
          Toggle("", isOn: $settings.loopAtEnd)
            .labelsHidden()
        }

        rowDivider

        settingRow(
          "Advance direction",
          description: "Use Previous instead of Next when auto-advancing."
        ) {
          Picker("", selection: $settings.advanceDirectionPrevious) {
            Text("Next").tag(false)
            Text("Previous").tag(true)
          }
          .labelsHidden()
          .frame(maxWidth: 180)
        }
      }
    }
  }

  private var performancePage: some View {
    settingsScrollPage {
      settingsCard("Performance") {
        settingRow(
          "Performance mode",
          description: "Automatic tunes thumbnail and analysis work using the Mac's processor, memory, and Metal support."
        ) {
          Picker("", selection: $settings.performanceModeRaw) {
            ForEach(PerformanceMode.allCases) { Text($0.rawValue).tag($0.rawValue) }
          }
          .labelsHidden()
          .frame(maxWidth: 240)
        }
      }

      settingsCard("Analysis") {
        settingRow(
          "Local analysis mode",
          description: "Choose how much on-device clip analysis SlateBox performs."
        ) {
          Picker("", selection: $settings.localAnalysisMode) {
            ForEach(["Off", "Fast", "Balanced", "Detailed"], id: \.self) {
              Text($0).tag($0)
            }
          }
          .labelsHidden()
          .frame(maxWidth: 240)
        }
      }
    }
  }

  private func settingsScrollPage<Content: View>(
    @ViewBuilder content: () -> Content
  ) -> some View {
    ScrollView(.vertical) {
      VStack(alignment: .leading, spacing: 18) {
        content()
      }
      .padding(24)
      .frame(maxWidth: 920, alignment: .topLeading)
      .frame(maxWidth: .infinity, alignment: .top)
    }
    .scrollIndicators(.visible)
  }

  private func settingsCard<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 14) {
        content()
      }
      .padding(.vertical, 6)
      .frame(maxWidth: .infinity, alignment: .leading)
    } label: {
      Text(title)
        .font(.headline)
    }
  }

  private func settingRow<Content: View>(
    _ title: String,
    description: String? = nil,
    @ViewBuilder control: () -> Content
  ) -> some View {
    HStack(alignment: .top, spacing: 24) {
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .fontWeight(.medium)
        if let description {
          Text(description)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .frame(width: 250, alignment: .leading)

      control()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var rowDivider: some View {
    Divider()
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

  private func storageMapRow(_ name: String, _ location: String) -> some View {
    HStack(alignment: .top, spacing: 24) {
      Text(name)
        .fontWeight(.medium)
        .frame(width: 220, alignment: .leading)
      Text(location)
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func folderChooser(
    label: String,
    path: String,
    choose: @escaping () -> Void,
    clear: @escaping () -> Void
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .center, spacing: 12) {
        Text(label)
          .fontWeight(.medium)
        Spacer(minLength: 16)
        if !path.isEmpty {
          Button("Reveal") { reveal(URL(fileURLWithPath: path, isDirectory: true)) }
          Button("Reset") { clear() }
        }
        Button("Choose Folder…") { choose() }
      }

      Text(path.isEmpty ? "Not selected" : path)
        .font(.caption)
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
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
    StoragePreferences.activateConfiguredBookmarks()
    refreshStorageInformation()
  }

  private func clearMacPreviewCache() {
    let result = StoragePreferences.clearFolderContents(
      at: StoragePreferences.internalSourcePreviewDirectory
    )
    storageMessage = "Cleared \(result.files) item(s), freeing \(FileSizeFormatterUtil.string(result.bytes))."
    refreshStorageInformation()
  }

  private func refreshStorageInformation() {
    localPreviewUsage = StoragePreferences.folderUsage(
      at: StoragePreferences.internalSourcePreviewDirectory
    )
    internalAvailable = VolumeCapacity.availableCapacity(
      for: StoragePreferences.internalCacheRoot
    )
  }

  private func reveal(_ url: URL) {
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }
}
