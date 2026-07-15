import AppKit
import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
  case system = "System"
  case light = "Light"
  case dark = "Dark"

  var id: String { rawValue }

  var colorScheme: ColorScheme? {
    switch self {
    case .system: return nil
    case .light: return .light
    case .dark: return .dark
    }
  }
}

enum AppAccentColor: String, CaseIterable, Identifiable {
  case system = "System"
  case blue = "Blue"
  case purple = "Purple"
  case teal = "Teal"
  case green = "Green"
  case orange = "Orange"

  var id: String { rawValue }

  var color: Color {
    switch self {
    case .system: return Color(nsColor: .controlAccentColor)
    case .blue: return .blue
    case .purple: return .purple
    case .teal: return .teal
    case .green: return .green
    case .orange: return .orange
    }
  }
}

struct SettingsView: View {
  @EnvironmentObject var settings: AppSettings
  @AppStorage("settingsSelectedTab") private var selectedTabRaw = SettingsTab.storage.rawValue
  @AppStorage("appAppearance") private var appAppearanceRaw = AppAppearance.system.rawValue
  @AppStorage("appAccentColor") private var appAccentColorRaw = AppAccentColor.system.rawValue
  @AppStorage("showFullStoragePaths") private var showFullStoragePaths = true

  @State private var localPreviewUsage: Int64 = 0
  @State private var internalAvailable: Int64?
  @State private var storageMessage = ""
  @State private var isApplyingStoragePreset = false

  private enum SettingsTab: String {
    case ingest
    case storage
    case workflow
    case performance
    case appearance
  }

  private enum FolderKind {
    case sourcePreview
    case projectThumbnails
    case backup1
    case backup2
  }

  private var appAppearance: AppAppearance {
    AppAppearance(rawValue: appAppearanceRaw) ?? .system
  }

  private var appAccentColor: AppAccentColor {
    AppAccentColor(rawValue: appAccentColorRaw) ?? .system
  }

  var body: some View {
    TabView(selection: $selectedTabRaw) {
      ingestPage
        .tabItem { Label("Ingest", systemImage: "tray.and.arrow.down") }
        .tag(SettingsTab.ingest.rawValue)

      storagePage
        .tabItem { Label("Storage", systemImage: "externaldrive") }
        .tag(SettingsTab.storage.rawValue)

      workflowPage
        .tabItem { Label("Workflow", systemImage: "film.stack") }
        .tag(SettingsTab.workflow.rawValue)

      performancePage
        .tabItem { Label("Performance", systemImage: "gauge.with.dots.needle.67percent") }
        .tag(SettingsTab.performance.rawValue)

      appearancePage
        .tabItem { Label("Appearance", systemImage: "paintpalette") }
        .tag(SettingsTab.appearance.rawValue)
    }
    .frame(minWidth: 780, idealWidth: 900, minHeight: 560, idealHeight: 700)
    .tint(appAccentColor.color)
    .preferredColorScheme(appAppearance.colorScheme)
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
        Text("Choose a recommended setup. The cards stay in place while SlateBox updates the individual storage controls.")
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)

        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: 175), spacing: 12)],
          alignment: .leading,
          spacing: 12
        ) {
          ForEach(StoragePreset.allCases) { preset in
            storagePresetButton(preset)
          }
        }

        HStack(spacing: 8) {
          if isApplyingStoragePreset {
            ProgressView()
              .controlSize(.small)
          } else {
            Image(systemName: "checkmark.circle.fill")
              .foregroundStyle(appAccentColor.color)
          }
          Text(isApplyingStoragePreset
            ? "Applying \(settings.storagePreset.rawValue)…"
            : storagePresetSummary(settings.storagePreset))
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
      }

      settingsCard("Where SlateBox Stores Things") {
        storageMapRow("Original video files", "Selected ingest destination")
        rowDivider
        storageMapRow(
          "Partial/resume video files",
          "Beside the final video on the same destination — fixed for safety"
        )
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

        rowDivider

        folderChooser(
          label: "Custom source preview folder",
          path: settings.sourcePreviewCustomFolderPath,
          enabled: settings.sourcePreviewStorageLocation == .customFolder,
          hint: "Available when Source preview thumbnails is set to Custom Folder.",
          choose: { chooseFolder(.sourcePreview) },
          clear: {
            settings.sourcePreviewCustomFolderPath = ""
            settings.sourcePreviewCustomFolderBookmarkBase64 = ""
          }
        )

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

        rowDivider

        folderChooser(
          label: "Custom project thumbnail folder",
          path: settings.projectThumbnailCustomFolderPath,
          enabled: settings.projectThumbnailStorageLocation == .customFolder,
          hint: "Available when Project/library thumbnails is set to Custom Folder.",
          choose: { chooseFolder(.projectThumbnails) },
          clear: {
            settings.projectThumbnailCustomFolderPath = ""
            settings.projectThumbnailCustomFolderBookmarkBase64 = ""
          }
        )
      }

      settingsCard("Preview Cache") {
        settingRow(
          "Cache limit",
          description: "Fine-tune the maximum source-preview JPEG cache from 100 MB to 10 GB."
        ) {
          Stepper(
            value: previewLimitBinding,
            in: 100...10_240,
            step: 50
          ) {
            Text(formatCacheLimit(settings.sourcePreviewCacheLimitMB))
              .monospacedDigit()
          }
          .frame(maxWidth: 240)
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
            Text(
              "Using \(FileSizeFormatterUtil.string(localPreviewUsage)) • "
              + "\(internalAvailable.map { FileSizeFormatterUtil.string($0) } ?? "Unavailable") available"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
          }
          Spacer(minLength: 16)
          Button("Reveal") { reveal(StoragePreferences.internalSourcePreviewDirectory) }
          Button("Clear Cache") { clearMacPreviewCache() }
        }

        Text(storageMessage.isEmpty ? "Cache information refreshes when Settings opens." : storageMessage)
          .font(.caption)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
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
          enabled: true,
          hint: "Choose an external drive, NAS share, or another folder.",
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
          enabled: true,
          hint: "Choose a second independent backup destination.",
          choose: { chooseFolder(.backup2) },
          clear: {
            settings.backupDestination2Path = ""
            settings.backupDestination2BookmarkBase64 = ""
          }
        )

        Text(
          "Each backup can use a different external drive or NAS folder. "
          + "SlateBox remembers access with a macOS security-scoped bookmark."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      }

      settingsCard("Storage Display") {
        settingRow(
          "Show full paths",
          description: "Turn this off to abbreviate your home folder as ~ and shorten very long paths."
        ) {
          Toggle("", isOn: $showFullStoragePaths)
            .labelsHidden()
        }
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

  private var appearancePage: some View {
    settingsScrollPage {
      settingsCard("Theme") {
        settingRow(
          "Appearance",
          description: "Follow macOS automatically or keep SlateBox in Light or Dark mode."
        ) {
          Picker("", selection: $appAppearanceRaw) {
            ForEach(AppAppearance.allCases) { Text($0.rawValue).tag($0.rawValue) }
          }
          .labelsHidden()
          .pickerStyle(.segmented)
          .frame(maxWidth: 320)
        }
      }

      settingsCard("Accent Color") {
        Text("Choose the color used for selections, active controls, and highlights.")
          .font(.caption)
          .foregroundStyle(.secondary)

        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: 125), spacing: 12)],
          alignment: .leading,
          spacing: 12
        ) {
          ForEach(AppAccentColor.allCases) { option in
            Button {
              appAccentColorRaw = option.rawValue
            } label: {
              HStack(spacing: 10) {
                Circle()
                  .fill(option.color)
                  .frame(width: 18, height: 18)
                  .overlay(Circle().stroke(.primary.opacity(0.15), lineWidth: 1))
                Text(option.rawValue)
                Spacer(minLength: 0)
                if option == appAccentColor {
                  Image(systemName: "checkmark")
                    .fontWeight(.semibold)
                }
              }
              .padding(.horizontal, 12)
              .frame(height: 40)
              .background(
                RoundedRectangle(cornerRadius: 10)
                  .fill(option == appAccentColor
                    ? option.color.opacity(0.14)
                    : Color(nsColor: .controlBackgroundColor))
              )
              .overlay(
                RoundedRectangle(cornerRadius: 10)
                  .stroke(
                    option == appAccentColor ? option.color : Color.secondary.opacity(0.18),
                    lineWidth: option == appAccentColor ? 2 : 1
                  )
              )
            }
            .buttonStyle(.plain)
          }
        }
      }

      settingsCard("Reset Appearance") {
        settingRow(
          "Use macOS defaults",
          description: "Return to the system appearance and system accent color."
        ) {
          Button("Reset") {
            appAppearanceRaw = AppAppearance.system.rawValue
            appAccentColorRaw = AppAccentColor.system.rawValue
          }
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

  private func storagePresetButton(_ preset: StoragePreset) -> some View {
    let selected = settings.storagePreset == preset
    return Button {
      applyStoragePreset(preset)
    } label: {
      VStack(alignment: .leading, spacing: 7) {
        HStack {
          Image(systemName: storagePresetIcon(preset))
            .foregroundStyle(selected ? appAccentColor.color : .secondary)
          Spacer(minLength: 8)
          if selected {
            Image(systemName: "checkmark.circle.fill")
              .foregroundStyle(appAccentColor.color)
          }
        }

        Text(preset.rawValue)
          .fontWeight(.semibold)
          .foregroundStyle(.primary)

        Text(storagePresetShortDescription(preset))
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
          .frame(maxWidth: .infinity, minHeight: 32, alignment: .topLeading)
      }
      .padding(12)
      .frame(maxWidth: .infinity, minHeight: 106, alignment: .topLeading)
      .background(
        RoundedRectangle(cornerRadius: 12)
          .fill(selected
            ? appAccentColor.color.opacity(0.12)
            : Color(nsColor: .controlBackgroundColor))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 12)
          .stroke(
            selected ? appAccentColor.color : Color.secondary.opacity(0.18),
            lineWidth: selected ? 2 : 1
          )
      )
    }
    .buttonStyle(.plain)
    .disabled(isApplyingStoragePreset)
    .animation(.easeInOut(duration: 0.18), value: selected)
  }

  private func applyStoragePreset(_ preset: StoragePreset) {
    guard !isApplyingStoragePreset else { return }

    isApplyingStoragePreset = true
    storageMessage = ""

    var transaction = Transaction()
    transaction.animation = .easeInOut(duration: 0.18)
    withTransaction(transaction) {
      settings.applyStoragePreset(preset)
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
      refreshStorageInformation()
      storageMessage = "\(preset.rawValue) preset applied."
      isApplyingStoragePreset = false
    }
  }

  private func storagePresetIcon(_ preset: StoragePreset) -> String {
    switch preset {
    case .balanced: return "slider.horizontal.3"
    case .minimizeMacStorage: return "internaldrive"
    case .maximumPerformance: return "bolt.fill"
    case .custom: return "wrench.and.screwdriver"
    }
  }

  private func storagePresetShortDescription(_ preset: StoragePreset) -> String {
    switch preset {
    case .balanced:
      return "Recommended mix of speed and cleanup."
    case .minimizeMacStorage:
      return "Keep previews and thumbnails with projects."
    case .maximumPerformance:
      return "Use fast local caches and retain previews."
    case .custom:
      return "Choose every location and cache rule."
    }
  }

  private func storagePresetSummary(_ preset: StoragePreset) -> String {
    switch preset {
    case .balanced:
      return "Balanced keeps source previews on the Mac, project thumbnails with each project, and clears previews after ingest."
    case .minimizeMacStorage:
      return "Minimize Mac Storage keeps generated media support files with the project destination."
    case .maximumPerformance:
      return "Maximum Performance uses larger local caches for faster browsing and reopening."
    case .custom:
      return "Custom uses the individual storage locations and cleanup rules shown below."
    }
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
      Text(displayPath(location))
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
        .lineLimit(showFullStoragePaths ? nil : 2)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func folderChooser(
    label: String,
    path: String,
    enabled: Bool,
    hint: String,
    choose: @escaping () -> Void,
    clear: @escaping () -> Void
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .center, spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
          Text(label)
            .fontWeight(.medium)
          Text(hint)
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer(minLength: 16)

        if !path.isEmpty {
          Button("Reveal") { reveal(URL(fileURLWithPath: path, isDirectory: true)) }
          Button("Reset") { clear() }
        }
        Button("Choose Folder…") { choose() }
      }

      Text(path.isEmpty ? "Not selected" : displayPath(path))
        .font(.caption)
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
        .lineLimit(showFullStoragePaths ? nil : 2)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
    }
    .disabled(!enabled)
    .opacity(enabled ? 1 : 0.55)
  }

  private func displayPath(_ path: String) -> String {
    guard !showFullStoragePaths, path.hasPrefix("/") else { return path }

    let abbreviated = (path as NSString).abbreviatingWithTildeInPath
    guard abbreviated.count > 82 else { return abbreviated }

    let prefix = abbreviated.prefix(38)
    let suffix = abbreviated.suffix(38)
    return "\(prefix)…\(suffix)"
  }

  private func formatCacheLimit(_ megabytes: Int) -> String {
    if megabytes >= 1_024 {
      let gigabytes = Double(megabytes) / 1_024
      return gigabytes.rounded() == gigabytes
        ? "\(Int(gigabytes)) GB"
        : String(format: "%.1f GB", gigabytes)
    }
    return "\(megabytes) MB"
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

    // Never overwrite a stored bookmark with a failed creation; nil leaves the
    // previously persisted bookmark untouched.
    let bookmark =
      (try? SecurityScopedBookmarkManager().bookmark(for: url))?.base64EncodedString()

    switch kind {
    case .sourcePreview:
      settings.sourcePreviewCustomFolderPath = url.path
      if let bookmark { settings.sourcePreviewCustomFolderBookmarkBase64 = bookmark }
      settings.sourcePreviewStorageLocationRaw = SourcePreviewStorageLocation.customFolder.rawValue
      settings.storagePresetRaw = StoragePreset.custom.rawValue
    case .projectThumbnails:
      settings.projectThumbnailCustomFolderPath = url.path
      if let bookmark { settings.projectThumbnailCustomFolderBookmarkBase64 = bookmark }
      settings.projectThumbnailStorageLocationRaw =
        ProjectThumbnailStorageLocation.customFolder.rawValue
      settings.storagePresetRaw = StoragePreset.custom.rawValue
    case .backup1:
      settings.backupDestination1Path = url.path
      if let bookmark { settings.backupDestination1BookmarkBase64 = bookmark }
    case .backup2:
      settings.backupDestination2Path = url.path
      if let bookmark { settings.backupDestination2BookmarkBase64 = bookmark }
    }

    StoragePreferences.activateConfiguredBookmarks()
    refreshStorageInformation()
  }

  private func clearMacPreviewCache() {
    let result = StoragePreferences.clearFolderContents(
      at: StoragePreferences.internalSourcePreviewDirectory
    )
    storageMessage =
      "Cleared \(result.files) item(s), freeing \(FileSizeFormatterUtil.string(result.bytes))."
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
