import AppKit
import Foundation

/// Export / report / edit-folder collaborator for `LibraryViewModel`.
/// Exports read copied project media only, copy instead of move, and never overwrite.
@MainActor
final class LibraryExportCoordinator {
  private let exporter = ClipExportService()
  private let aliases = AliasService()
  private let security: SecurityScopedBookmarkManager

  init(security: SecurityScopedBookmarkManager) {
    self.security = security
  }

  func exportableClips(
    for scope: EditFolderExportScope,
    project: ClipVaultProject,
    activeSelectionIDs: Set<UUID>,
    resolvedMediaURL: (Clip) -> URL?
  ) -> [Clip] {
    let eligible = project.clips.filter { clip in
      (clip.copyStatus == .copied || clip.verificationStatus == .verified) && resolvedMediaURL(clip) != nil
    }
    switch scope {
    case .keeps: return eligible.filter { $0.cullStatus == .keep }
    case .keepsAndMaybes: return eligible.filter { $0.cullStatus == .keep || $0.cullStatus == .maybe }
    case .fourPlusStars: return eligible.filter { $0.rating >= 4 }
    case .selected: return eligible.filter { activeSelectionIDs.contains($0.id) }
    }
  }

  func copyToEditFolder(
    _ scope: EditFolderExportScope,
    project: ClipVaultProject,
    activeSelectionIDs: Set<UUID>,
    resolvedMediaURL: @escaping (Clip) -> URL?,
    setProgress: @escaping (ClipExportProgress?) -> Void,
    setSummary: @escaping (ClipExportSummary?) -> Void
  ) {
    let clips = exportableClips(
      for: scope,
      project: project,
      activeSelectionIDs: activeSelectionIDs,
      resolvedMediaURL: resolvedMediaURL
    )
    guard !clips.isEmpty else {
      let alert = NSAlert()
      alert.messageText = "No clips to copy"
      alert.informativeText = "No copied clips match \(scope.label). Rate or select clips first, and make sure they finished copying."
      alert.runModal()
      return
    }
    let panel = NSOpenPanel()
    panel.title = "Choose Edit Folder"
    panel.message = "\(AppBrand.appName) will copy \(clips.count) clip\(clips.count == 1 ? "" : "s") (\(scope.label)) into this folder. Nothing is moved or overwritten."
    panel.prompt = "Copy Here"
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true
    guard panel.runModal() == .OK, let destination = panel.url else { return }

    let items = clips.compactMap { clip -> (clip: Clip, mediaURL: URL)? in
      guard let url = resolvedMediaURL(clip) else { return nil }
      return (clip, url)
    }
    setSummary(nil)
    setProgress(ClipExportProgress(completed: 0, total: items.count, currentFilename: ""))
    Task {
      let summary = await exporter.copyClips(items, to: destination) { progress in
        setProgress(progress)
      }
      setProgress(nil)
      setSummary(summary)
      NSWorkspace.shared.activateFileViewerSelecting([destination])
    }
  }

  func createAliases(
    named folderName: String,
    project: ClipVaultProject,
    activeSelectionIDs: Set<UUID>,
    resolvedMediaURL: (Clip) -> URL?
  ) -> AliasCreationSummary? {
    let items = activeSelectionIDs.compactMap { id -> (clip: Clip, mediaURL: URL)? in
      guard let clip = project.clips.first(where: { $0.id == id }),
        (clip.copyStatus == .copied || clip.verificationStatus == .verified),
        let mediaURL = resolvedMediaURL(clip) else { return nil }
      return (clip, mediaURL)
    }
    guard !items.isEmpty else { return nil }
    return aliases.createAliases(
      named: folderName,
      for: items,
      projectFolder: security.projectFolderURL(for: project)
    )
  }

  func revealAliases(in project: ClipVaultProject) {
    NSWorkspace.shared.activateFileViewerSelecting([
      aliases.aliasesFolder(in: security.projectFolderURL(for: project))
    ])
  }

  func handOffEditFolder(to applicationIdentifier: String?) {
    let panel = NSOpenPanel()
    panel.title = "Choose Edit Folder"
    panel.message = "Choose the folder \(AppBrand.appName) should reveal or open in your editor."
    panel.prompt = applicationIdentifier == nil ? "Reveal" : "Open"
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let folder = panel.url else { return }

    guard let applicationIdentifier else {
      NSWorkspace.shared.activateFileViewerSelecting([folder])
      return
    }
    guard let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: applicationIdentifier) else {
      let alert = NSAlert()
      alert.messageText = "Editor not found"
      alert.informativeText = "Install the selected editor, then try the handoff again."
      alert.runModal()
      return
    }
    NSWorkspace.shared.open([folder], withApplicationAt: applicationURL, configuration: NSWorkspace.OpenConfiguration())
  }

  func exportClipReport(
    _ kind: ClipReportKind,
    project: ClipVaultProject,
    setError: (String) -> Void
  ) {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = kind.defaultFilename
    guard panel.runModal() == .OK, let url = panel.url else { return }
    let clips: [Clip]
    switch kind {
    case .keeps: clips = project.clips.filter { $0.cullStatus == .keep }
    case .rejects: clips = project.clips.filter { $0.cullStatus == .reject }
    case .allClips, .verification, .analysis: clips = project.clips
    }
    do {
      try csv(for: clips, kind: kind).write(to: url, atomically: true, encoding: .utf8)
    } catch {
      setError(StorageRecovery.message(for: error, operation: .export))
    }
  }

  func exportProjectMetadata(project: ClipVaultProject, setError: (String) -> Void) {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "\(AppBrand.appName)-Project-Metadata.json"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      try JSONEncoder().encode(project).write(to: url, options: .atomic)
    } catch {
      setError(StorageRecovery.message(for: error, operation: .export))
    }
  }

  private struct CSVColumn {
    let title: String
    let value: (Clip) -> String

    init(_ title: String, _ value: @escaping (Clip) -> String) {
      self.title = title
      self.value = value
    }
  }

  private func csv(for clips: [Clip], kind: ClipReportKind = .allClips) -> String {
    let columns = csvColumns(for: kind)
    let header = columns.map(\.title).joined(separator: ",")
    let rows = clips.map { clip in
      columns.map { escapeCSV($0.value(clip)) }.joined(separator: ",")
    }
    return ([header] + rows).joined(separator: "\n")
  }

  private func csvColumns(for kind: ClipReportKind) -> [CSVColumn] {
    func score(_ value: Double?) -> String { value.map { String(format: "%.0f", $0) } ?? "" }
    let identity: [CSVColumn] = [
      CSVColumn("filename", { $0.currentFilename }),
      CSVColumn("original filename", { $0.originalFilename })
    ]
    let cull: [CSVColumn] = [
      CSVColumn("cull status", { $0.cullStatus.label }),
      CSVColumn("rating", { String($0.rating) })
    ]
    let technical: [CSVColumn] = [
      CSVColumn("duration", { DurationFormatterUtil.string($0.duration) }),
      CSVColumn("file size", { FileSizeFormatterUtil.string($0.fileSize) }),
      CSVColumn("resolution", { "\($0.width.map(String.init) ?? "?")x\($0.height.map(String.init) ?? "?")" }),
      CSVColumn("frame rate", { $0.frameRate.map { String(format: "%.2f", $0) } ?? "" }),
      CSVColumn("codec", { $0.codec ?? "" }),
      CSVColumn("shot time", { $0.effectiveShotTime.map { DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .medium) } ?? "" }),
      CSVColumn("shot time source", { $0.manualShotTime == nil ? $0.shotTimeSource.label : ShotTimeSource.manual.label })
    ]
    let production: [CSVColumn] = [
      CSVColumn("tags", { $0.productionTags.joined(separator: "; ") }),
      CSVColumn("people", { $0.people.joined(separator: "; ") }),
      CSVColumn("location", { $0.location }),
      CSVColumn("scene", { $0.scene }),
      CSVColumn("shot type", { $0.shotType }),
      CSVColumn("notes", { $0.customNotes }),
      CSVColumn("automatic tags", { $0.automaticTags.joined(separator: "; ") })
    ]
    let analysis: [CSVColumn] = [
      CSVColumn("analysis status", { $0.analysisStatus.label }),
      CSVColumn("quality score", { score($0.analysisQualityScore) }),
      CSVColumn("suggested rating", { $0.suggestedRating.map(String.init) ?? "" }),
      CSVColumn("focus score", { score($0.focusScore) }),
      CSVColumn("stability score", { score($0.stabilityScore) }),
      CSVColumn("brightness", { score($0.brightnessScore) }),
      CSVColumn("contrast", { score($0.contrastScore) }),
      CSVColumn("white balance estimate", { $0.whiteBalanceKelvin.map { "\($0)K" } ?? "" }),
      CSVColumn("face count", { $0.maxFaceCount.map(String.init) ?? "" }),
      CSVColumn("face visibility", { score($0.faceVisibilityScore) })
    ]
    let paths: [CSVColumn] = [
      CSVColumn("source path", { $0.originalSourcePath }),
      CSVColumn("destination path", { $0.currentPath })
    ]
    let status: [CSVColumn] = [
      CSVColumn("verification status", { $0.verificationStatus.rawValue }),
      CSVColumn("thumbnail status", { $0.thumbnailStatus.rawValue })
    ]
    switch kind {
    case .verification:
      return identity + [
        CSVColumn("expected size", { FileSizeFormatterUtil.string($0.expectedFileSize) }),
        CSVColumn("copied size", { FileSizeFormatterUtil.string($0.fileSize) }),
        CSVColumn("checksum", { $0.checksum ?? "" }),
        CSVColumn("copy status", { $0.copyStatus.rawValue }),
        CSVColumn("verification status", { $0.verificationStatus.rawValue }),
        CSVColumn("error", { $0.errorMessage ?? "" })
      ] + paths
    case .analysis:
      return identity + cull + analysis + [CSVColumn("sampled frames", { $0.sampledFrameCount.map(String.init) ?? "" })]
    case .allClips, .keeps, .rejects:
      return identity + cull + technical + production + analysis + paths + status
    }
  }

  private func escapeCSV(_ value: String) -> String {
    "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
  }
}
