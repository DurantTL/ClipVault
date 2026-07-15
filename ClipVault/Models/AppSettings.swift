import Foundation
import SwiftUI

enum PerformanceMode: String, CaseIterable, Identifiable {
  case automatic = "Automatic"
  case fast = "Fast"
  case balanced = "Balanced"
  case quality = "Quality"

  var id: String { rawValue }
}

enum StoragePreset: String, CaseIterable, Identifiable {
  case balanced = "Balanced"
  case minimizeMacStorage = "Minimize Mac Storage"
  case maximumPerformance = "Maximum Performance"
  case custom = "Custom"

  var id: String { rawValue }
}

enum SourcePreviewStorageLocation: String, CaseIterable, Identifiable {
  case macInternal = "Mac Internal Cache"
  case projectDestination = "Project Destination"
  case customFolder = "Custom Folder"
  case disabled = "Disabled"

  var id: String { rawValue }
}

enum ProjectThumbnailStorageLocation: String, CaseIterable, Identifiable {
  case projectFolder = "Inside Each Project"
  case macInternal = "Mac Internal Cache"
  case customFolder = "Custom Folder"

  var id: String { rawValue }
}

enum SourcePreviewCleanupPolicy: String, CaseIterable, Identifiable {
  case afterSuccessfulIngest = "After Successful Ingest"
  case whenIngestWindowCloses = "When Ingest Window Closes"
  case manualOnly = "Manual Only"

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

struct ResolvedStorageDirectory {
  let accessURL: URL
  let directoryURL: URL
}

private final class StorageAccessRegistry: @unchecked Sendable {
  private let lock = NSLock()
  private var retainedURLs: [String: URL] = [:]

  func retain(_ url: URL) {
    let path = url.standardizedFileURL.path
    lock.lock()
    defer { lock.unlock() }
    guard retainedURLs[path] == nil else { return }
    if url.startAccessingSecurityScopedResource() {
      retainedURLs[path] = url
    }
  }

  deinit {
    for url in retainedURLs.values {
      url.stopAccessingSecurityScopedResource()
    }
  }
}

enum StoragePreferences {
  static let sourcePreviewLocationKey = "sourcePreviewStorageLocation"
  static let projectThumbnailLocationKey = "projectThumbnailStorageLocation"
  static let sourcePreviewCustomPathKey = "sourcePreviewCustomFolderPath"
  static let sourcePreviewCustomBookmarkKey = "sourcePreviewCustomFolderBookmarkBase64"
  static let projectThumbnailCustomPathKey = "projectThumbnailCustomFolderPath"
  static let projectThumbnailCustomBookmarkKey = "projectThumbnailCustomFolderBookmarkBase64"
  static let backup1PathKey = "backupDestination1Path"
  static let backup2PathKey = "backupDestination2Path"
  static let backup1BookmarkKey = "backupDestination1BookmarkBase64"
  static let backup2BookmarkKey = "backupDestination2BookmarkBase64"
  static let previewLimitKey = "sourcePreviewCacheLimitMB"
  static let previewCleanupKey = "sourcePreviewCleanupPolicy"
  private static let accessRegistry = StorageAccessRegistry()

  static var internalCacheRoot: URL {
    let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    return base.appendingPathComponent(AppBrand.previewCacheFolderName, isDirectory: true)
  }

  static var internalSourcePreviewDirectory: URL {
    internalCacheRoot.appendingPathComponent("IngestPreviewThumbnails", isDirectory: true)
  }

  /// Warms up the configured storage bookmarks (custom cache folders and backup
  /// destinations) so their security-scoped access is retained for later use.
  ///
  /// Runs on a background queue and resolves without mounting, so a configured
  /// folder on a disconnected network drive or external volume can never stall
  /// app launch — it is simply skipped and re-resolved on demand once the
  /// volume is available again.
  static func activateConfiguredBookmarks() {
    DispatchQueue.global(qos: .utility).async {
      _ = resolvedFolder(
        pathKey: sourcePreviewCustomPathKey,
        bookmarkKey: sourcePreviewCustomBookmarkKey,
        mountIfNeeded: false
      )
      _ = resolvedFolder(
        pathKey: projectThumbnailCustomPathKey,
        bookmarkKey: projectThumbnailCustomBookmarkKey,
        mountIfNeeded: false
      )
      let defaults = UserDefaults.standard
      _ = backupURL(
        path: defaults.string(forKey: backup1PathKey) ?? "",
        bookmarkBase64: defaults.string(forKey: backup1BookmarkKey) ?? "",
        mountIfNeeded: false
      )
      _ = backupURL(
        path: defaults.string(forKey: backup2PathKey) ?? "",
        bookmarkBase64: defaults.string(forKey: backup2BookmarkKey) ?? "",
        mountIfNeeded: false
      )
    }
  }

  static func sourcePreviewDirectory(destinationRoot: URL?) -> ResolvedStorageDirectory? {
    let raw = UserDefaults.standard.string(forKey: sourcePreviewLocationKey)
      ?? SourcePreviewStorageLocation.macInternal.rawValue
    let location = SourcePreviewStorageLocation(rawValue: raw) ?? .macInternal
    return sourcePreviewDirectory(
      location: location,
      destinationRoot: destinationRoot,
      customFolder: resolvedFolder(
        pathKey: sourcePreviewCustomPathKey,
        bookmarkKey: sourcePreviewCustomBookmarkKey
      )
    )
  }

  static func sourcePreviewDirectory(
    location: SourcePreviewStorageLocation,
    destinationRoot: URL?,
    customFolder: URL?
  ) -> ResolvedStorageDirectory? {
    switch location {
    case .macInternal:
      return ResolvedStorageDirectory(
        accessURL: internalSourcePreviewDirectory,
        directoryURL: internalSourcePreviewDirectory
      )
    case .projectDestination:
      guard let destinationRoot else { return nil }
      return ResolvedStorageDirectory(
        accessURL: destinationRoot,
        directoryURL: destinationRoot
          .appendingPathComponent(AppBrand.cacheFolderName, isDirectory: true)
          .appendingPathComponent("ingest-previews", isDirectory: true)
      )
    case .customFolder:
      guard let customFolder else { return nil }
      return ResolvedStorageDirectory(
        accessURL: customFolder,
        directoryURL: customFolder
          .appendingPathComponent(AppBrand.appName, isDirectory: true)
          .appendingPathComponent("IngestPreviewThumbnails", isDirectory: true)
      )
    case .disabled:
      return nil
    }
  }

  static func projectThumbnailDirectory(for project: ClipVaultProject) -> ResolvedStorageDirectory {
    let raw = UserDefaults.standard.string(forKey: projectThumbnailLocationKey)
      ?? ProjectThumbnailStorageLocation.projectFolder.rawValue
    let location = ProjectThumbnailStorageLocation(rawValue: raw) ?? .projectFolder
    let projectFolder = SecurityScopedBookmarkManager().projectFolderURL(for: project)
    let customFolder = resolvedFolder(
      pathKey: projectThumbnailCustomPathKey,
      bookmarkKey: projectThumbnailCustomBookmarkKey
    )
    return projectThumbnailDirectory(
      location: location,
      projectID: project.id,
      projectFolder: projectFolder,
      customFolder: customFolder
    )
  }

  static func projectThumbnailDirectory(
    location: ProjectThumbnailStorageLocation,
    projectID: UUID,
    projectFolder: URL,
    customFolder: URL?
  ) -> ResolvedStorageDirectory {
    switch location {
    case .projectFolder:
      return ResolvedStorageDirectory(
        accessURL: projectFolder,
        directoryURL: projectFolder
          .appendingPathComponent(AppBrand.cacheFolderName, isDirectory: true)
          .appendingPathComponent("thumbnails", isDirectory: true)
      )
    case .macInternal:
      let directory = internalCacheRoot
        .appendingPathComponent("ProjectThumbnails", isDirectory: true)
        .appendingPathComponent(projectID.uuidString, isDirectory: true)
      return ResolvedStorageDirectory(accessURL: directory, directoryURL: directory)
    case .customFolder:
      guard let customFolder else {
        return ResolvedStorageDirectory(
          accessURL: projectFolder,
          directoryURL: projectFolder
            .appendingPathComponent(AppBrand.cacheFolderName, isDirectory: true)
            .appendingPathComponent("thumbnails", isDirectory: true)
        )
      }
      let directory = customFolder
        .appendingPathComponent(AppBrand.appName, isDirectory: true)
        .appendingPathComponent("ProjectThumbnails", isDirectory: true)
        .appendingPathComponent(projectID.uuidString, isDirectory: true)
      return ResolvedStorageDirectory(accessURL: customFolder, directoryURL: directory)
    }
  }

  static var sourcePreviewCacheLimitBytes: Int64 {
    let stored = UserDefaults.standard.integer(forKey: previewLimitKey)
    let megabytes = stored > 0 ? stored : 500
    return Int64(megabytes) * 1_048_576
  }

  static var sourcePreviewCleanupPolicy: SourcePreviewCleanupPolicy {
    let raw = UserDefaults.standard.string(forKey: previewCleanupKey)
      ?? SourcePreviewCleanupPolicy.afterSuccessfulIngest.rawValue
    return SourcePreviewCleanupPolicy(rawValue: raw) ?? .afterSuccessfulIngest
  }

  static var projectThumbnailCustomBookmarkData: Data? {
    bookmarkData(forKey: projectThumbnailCustomBookmarkKey)
  }

  static func backupURL(path: String, bookmarkBase64: String, mountIfNeeded: Bool = true) -> URL? {
    if let data = Data(base64Encoded: bookmarkBase64),
      let resolved = try? SecurityScopedBookmarkManager().resolve(data, mountIfNeeded: mountIfNeeded) {
      accessRegistry.retain(resolved)
      return resolved
    }
    guard !path.isEmpty else { return nil }
    return URL(fileURLWithPath: path, isDirectory: true)
  }

  static func folderUsage(at url: URL) -> Int64 {
    guard let enumerator = FileManager.default.enumerator(
      at: url,
      includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
      options: [.skipsHiddenFiles]
    ) else { return 0 }
    var total: Int64 = 0
    for case let fileURL as URL in enumerator {
      let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
      if values?.isRegularFile == true { total += Int64(values?.fileSize ?? 0) }
    }
    return total
  }

  @discardableResult
  static func clearFolderContents(at url: URL) -> (files: Int, bytes: Int64) {
    let contents = (try? FileManager.default.contentsOfDirectory(
      at: url,
      includingPropertiesForKeys: [.fileSizeKey],
      options: [.skipsHiddenFiles]
    )) ?? []
    var files = 0
    var bytes: Int64 = 0
    for child in contents {
      let childBytes = folderUsage(at: child) + Int64((try? child.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
      if (try? FileManager.default.removeItem(at: child)) != nil {
        files += 1
        bytes += childBytes
      }
    }
    return (files, bytes)
  }

  private static func resolvedFolder(
    pathKey: String, bookmarkKey: String, mountIfNeeded: Bool = true
  ) -> URL? {
    if let data = bookmarkData(forKey: bookmarkKey),
      let resolved = try? SecurityScopedBookmarkManager().resolve(data, mountIfNeeded: mountIfNeeded) {
      accessRegistry.retain(resolved)
      return resolved
    }
    let path = UserDefaults.standard.string(forKey: pathKey) ?? ""
    return path.isEmpty ? nil : URL(fileURLWithPath: path, isDirectory: true)
  }

  private static func bookmarkData(forKey key: String) -> Data? {
    guard let encoded = UserDefaults.standard.string(forKey: key), !encoded.isEmpty else { return nil }
    return Data(base64Encoded: encoded)
  }
}

final class AppSettings: ObservableObject {
  @AppStorage("verificationMode") var verificationModeRaw = VerificationMode.fast.rawValue
  @AppStorage("preserveSourceStructure") var preserveSourceStructure = false
  @AppStorage("thumbnailQuality") var thumbnailQualityRaw = ThumbnailQuality.balanced.rawValue
  // Not yet implemented — no UI exposed until a feature consumes it.
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
  @AppStorage("backupDestination1BookmarkBase64") var backupDestination1BookmarkBase64 = ""
  @AppStorage("backupDestination2BookmarkBase64") var backupDestination2BookmarkBase64 = ""
  // Not yet implemented — no UI exposed until the export writers exist.
  @AppStorage("finderTagsExport") var finderTagsExport = false
  @AppStorage("xmpSidecarExport") var xmpSidecarExport = false
  @AppStorage("renameFilesDuringIngest") var renameFilesDuringIngest = false
  @AppStorage("generateThumbnailsDuringIngest") var generateThumbnailsDuringIngest = true
  // Not yet implemented — no UI exposed until post-ingest analysis/contact
  // sheet generation is wired up.
  @AppStorage("runAnalysisAfterIngest") var runAnalysisAfterIngest = false
  @AppStorage("generateContactSheetsAfterIngest") var generateContactSheetsAfterIngest = false
  @AppStorage("performanceMode") var performanceModeRaw = PerformanceMode.automatic.rawValue

  @AppStorage("storagePreset") var storagePresetRaw = StoragePreset.balanced.rawValue
  @AppStorage("sourcePreviewStorageLocation") var sourcePreviewStorageLocationRaw = SourcePreviewStorageLocation.macInternal.rawValue
  @AppStorage("projectThumbnailStorageLocation") var projectThumbnailStorageLocationRaw = ProjectThumbnailStorageLocation.projectFolder.rawValue
  @AppStorage("sourcePreviewCacheLimitMB") var sourcePreviewCacheLimitMB = 500
  @AppStorage("sourcePreviewCleanupPolicy") var sourcePreviewCleanupPolicyRaw = SourcePreviewCleanupPolicy.afterSuccessfulIngest.rawValue
  @AppStorage("sourcePreviewCustomFolderPath") var sourcePreviewCustomFolderPath = ""
  @AppStorage("sourcePreviewCustomFolderBookmarkBase64") var sourcePreviewCustomFolderBookmarkBase64 = ""
  @AppStorage("projectThumbnailCustomFolderPath") var projectThumbnailCustomFolderPath = ""
  @AppStorage("projectThumbnailCustomFolderBookmarkBase64") var projectThumbnailCustomFolderBookmarkBase64 = ""

  init() {
    StoragePreferences.activateConfiguredBookmarks()
  }

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

  var storagePreset: StoragePreset {
    StoragePreset(rawValue: storagePresetRaw) ?? .balanced
  }

  var sourcePreviewStorageLocation: SourcePreviewStorageLocation {
    SourcePreviewStorageLocation(rawValue: sourcePreviewStorageLocationRaw) ?? .macInternal
  }

  var projectThumbnailStorageLocation: ProjectThumbnailStorageLocation {
    ProjectThumbnailStorageLocation(rawValue: projectThumbnailStorageLocationRaw) ?? .projectFolder
  }

  var sourcePreviewCleanupPolicy: SourcePreviewCleanupPolicy {
    SourcePreviewCleanupPolicy(rawValue: sourcePreviewCleanupPolicyRaw) ?? .afterSuccessfulIngest
  }

  func applyStoragePreset(_ preset: StoragePreset) {
    storagePresetRaw = preset.rawValue
    switch preset {
    case .balanced:
      sourcePreviewStorageLocationRaw = SourcePreviewStorageLocation.macInternal.rawValue
      projectThumbnailStorageLocationRaw = ProjectThumbnailStorageLocation.projectFolder.rawValue
      sourcePreviewCacheLimitMB = 500
      sourcePreviewCleanupPolicyRaw = SourcePreviewCleanupPolicy.afterSuccessfulIngest.rawValue
    case .minimizeMacStorage:
      sourcePreviewStorageLocationRaw = SourcePreviewStorageLocation.projectDestination.rawValue
      projectThumbnailStorageLocationRaw = ProjectThumbnailStorageLocation.projectFolder.rawValue
      sourcePreviewCacheLimitMB = 250
      sourcePreviewCleanupPolicyRaw = SourcePreviewCleanupPolicy.afterSuccessfulIngest.rawValue
    case .maximumPerformance:
      sourcePreviewStorageLocationRaw = SourcePreviewStorageLocation.macInternal.rawValue
      projectThumbnailStorageLocationRaw = ProjectThumbnailStorageLocation.macInternal.rawValue
      sourcePreviewCacheLimitMB = 2_048
      sourcePreviewCleanupPolicyRaw = SourcePreviewCleanupPolicy.manualOnly.rawValue
    case .custom:
      break
    }
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
