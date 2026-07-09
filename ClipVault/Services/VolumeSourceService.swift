import Foundation

enum SourceVolumeKind: String, CaseIterable, Identifiable {
  case removableCard = "Camera Card"
  case externalDrive = "External Drive"
  case internalDrive = "Internal Drive"
  case networkVolume = "Network Volume"
  case cloudDrive = "Cloud Drive"
  case folder = "Folder"
  case unknown = "Unknown"

  var id: String { rawValue }

  var iconName: String {
    switch self {
    case .removableCard: return "sdcard"
    case .externalDrive: return "externaldrive"
    case .internalDrive: return "internaldrive"
    case .networkVolume: return "network"
    case .cloudDrive: return "cloud"
    case .folder: return "folder"
    case .unknown: return "questionmark.folder"
    }
  }
}

enum SourceStructureBadge: String, Codable, Hashable {
  case sony = "Sony Card"
  case canonDCF = "Canon/DCF"
  case genericVideoFolder = "Generic Video Folder"
  case noVideosFound = "No Videos Found"
  case unchecked = "Not Checked"
}

struct SourceVolumeOption: Identifiable, Hashable {
  var id: String
  var name: String
  var url: URL
  var displayPath: String
  var totalCapacity: Int64?
  var availableCapacity: Int64?
  var isRemovable: Bool
  var isEjectable: Bool
  var isInternal: Bool
  var isNetwork: Bool
  var isCloudSyncedGuess: Bool
  var volumeKind: SourceVolumeKind
  var iconName: String
  var structureBadge: SourceStructureBadge
  var isAvailable: Bool
  var bookmarkData: Data?

  var capacitySummary: String {
    if let totalCapacity {
      return FileSizeFormatterUtil.string(totalCapacity)
    }
    if let availableCapacity {
      return "Available: \(FileSizeFormatterUtil.string(availableCapacity))"
    }
    return displayPath
  }
}

struct DestinationSuggestionModel: Identifiable, Hashable {
  let id = UUID()
  var primaryDestination: URL?
  var backupDestination1: URL?
  var backupDestination2: URL?
  var recentDestinations: [URL] = []
  var mountedDestinationSuggestions: [SourceVolumeOption] = []
}

final class VolumeSourceService {
  private let fileManager: FileManager

  init(fileManager: FileManager = .default) {
    self.fileManager = fileManager
  }

  func scanMountedSources() -> [SourceVolumeOption] {
    let keys: [URLResourceKey] = [
      .volumeNameKey,
      .volumeTotalCapacityKey,
      .volumeAvailableCapacityKey,
      .volumeIsRemovableKey,
      .volumeIsEjectableKey,
      .volumeIsInternalKey,
      .volumeIsLocalKey
    ]
    let urls = fileManager.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
    return urls.map { option(for: $0, manualKind: nil) }
      .sorted { lhs, rhs in
        if lhs.volumeKind.rawValue != rhs.volumeKind.rawValue { return lhs.volumeKind.rawValue < rhs.volumeKind.rawValue }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
      }
  }

  func manualSource(for url: URL) -> SourceVolumeOption {
    option(for: url, manualKind: .folder)
  }

  private func option(for url: URL, manualKind: SourceVolumeKind?) -> SourceVolumeOption {
    let standardized = url.standardizedFileURL
    let values = try? standardized.resourceValues(forKeys: [
      .volumeNameKey,
      .volumeTotalCapacityKey,
      .volumeAvailableCapacityKey,
      .volumeIsRemovableKey,
      .volumeIsEjectableKey,
      .volumeIsInternalKey,
      .volumeIsLocalKey
    ])
    let name = values?.volumeName ?? standardized.lastPathComponent.nonEmpty ?? standardized.path
    let isRemovable = values?.volumeIsRemovable ?? false
    let isEjectable = values?.volumeIsEjectable ?? false
    let isInternal = values?.volumeIsInternal ?? false
    let isLocal = values?.volumeIsLocal ?? true
    let isNetwork = !isLocal || standardized.path.hasPrefix("/Network/")
    let cloud = isCloudSyncedPath(standardized.path)
    let kind = manualKind ?? classify(url: standardized, name: name, isRemovable: isRemovable, isEjectable: isEjectable, isInternal: isInternal, isNetwork: isNetwork, isCloud: cloud, totalCapacity: values?.volumeTotalCapacity.map(Int64.init))

    // Mount discovery runs whenever the ingest window opens or the app becomes
    // active. Recursively probing a NAS or cloud-synced volume here can block the
    // window before the user has chosen that source, so defer inspection until it
    // is explicitly selected.
    let badge: SourceStructureBadge = isNetwork || cloud
      ? .unchecked
      : quickStructureBadge(for: standardized)

    return SourceVolumeOption(
      id: standardized.path,
      name: name,
      url: standardized,
      displayPath: standardized.path,
      totalCapacity: values?.volumeTotalCapacity.map(Int64.init),
      availableCapacity: values?.volumeAvailableCapacity.map(Int64.init),
      isRemovable: isRemovable,
      isEjectable: isEjectable,
      isInternal: isInternal,
      isNetwork: isNetwork,
      isCloudSyncedGuess: cloud,
      volumeKind: kind,
      iconName: kind.iconName,
      structureBadge: badge,
      isAvailable: fileManager.fileExists(atPath: standardized.path),
      bookmarkData: nil
    )
  }

  private func classify(url: URL, name: String, isRemovable: Bool, isEjectable: Bool, isInternal: Bool, isNetwork: Bool, isCloud: Bool, totalCapacity: Int64?) -> SourceVolumeKind {
    if isCloud { return .cloudDrive }
    if isNetwork { return .networkVolume }
    if looksLikeCameraCard(url: url, name: name) || isRemovable || (isEjectable && (totalCapacity ?? 0) < 512_000_000_000) { return .removableCard }
    if isInternal { return .internalDrive }
    if isEjectable || url.path.hasPrefix("/Volumes/") { return .externalDrive }
    return .unknown
  }

  private func looksLikeCameraCard(url: URL, name: String) -> Bool {
    let upper = name.uppercased()
    let cameraNames = ["UNTITLED", "NO NAME", "SONY", "CANON", "EOS_DIGITAL", "NIKON", "LUMIX", "FUJIFILM", "PRIVATE"]
    if cameraNames.contains(where: { upper.contains($0) }) { return true }
    return fileManager.fileExists(atPath: url.appendingPathComponent("PRIVATE/M4ROOT/CLIP").path)
      || fileManager.fileExists(atPath: url.appendingPathComponent("DCIM").path)
  }

  private func isCloudSyncedPath(_ path: String) -> Bool {
    let lower = path.lowercased()
    return ["google drive", "onedrive", "dropbox", "icloud drive", "mobile documents", "box", "synology drive"].contains { lower.contains($0) }
  }

  private func quickStructureBadge(for url: URL) -> SourceStructureBadge {
    if fileManager.fileExists(atPath: url.appendingPathComponent("PRIVATE/M4ROOT/CLIP").path) { return .sony }
    if fileManager.fileExists(atPath: url.appendingPathComponent("DCIM").path) { return .canonDCF }
    if containsVideoShallow(in: url) { return .genericVideoFolder }
    return .noVideosFound
  }

  private func containsVideoShallow(in url: URL) -> Bool {
    guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return false }
    var checked = 0
    for case let child as URL in enumerator {
      checked += 1
      if SourceScanner.supported.contains(child.pathExtension.lowercased()) { return true }
      if checked > 300 { return false }
    }
    return false
  }
}

private extension String {
  var nonEmpty: String? { isEmpty ? nil : self }
}
