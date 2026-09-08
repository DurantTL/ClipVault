import AppKit
import Foundation

extension LibraryViewModel {
  func createAliases(named folderName: String) {
    aliasSummary = exportCoordinator.createAliases(
      named: folderName,
      project: project,
      activeSelectionIDs: activeSelectionIDs,
      resolvedMediaURL: { [weak self] clip in self?.resolvedMediaURL(for: clip) }
    )
  }

  func revealAliases() {
    exportCoordinator.revealAliases(in: project)
  }

  func handOffEditFolder(to applicationIdentifier: String?) {
    exportCoordinator.handOffEditFolder(to: applicationIdentifier)
  }

  func addProductionTagToSelection(_ tag: String) {
    let clean = tag.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return }
    updateSelected { clip in
      if !clip.productionTags.contains(clean) { clip.productionTags.append(clean) }
    }
  }

  func removeProductionTagFromSelection(_ tag: String) {
    updateSelected { clip in
      clip.productionTags.removeAll { $0 == tag }
    }
  }

  var productionTagsInSelection: [String] {
    let ids = activeSelectionIDs
    let tags = project.clips.filter { ids.contains($0.id) }.flatMap(\.productionTags)
    return Array(Set(tags)).sorted()
  }

  func applyBatchMetadata(_ edit: BatchMetadataEdit) {
    let tags = edit.parsedTags
    let people = edit.parsedPeople
    updateSelected { clip in
      switch edit.tagMode {
      case .append:
        for tag in tags where !clip.productionTags.contains(tag) { clip.productionTags.append(tag) }
      case .replace:
        if !tags.isEmpty { clip.productionTags = tags }
      case .remove:
        clip.productionTags.removeAll { tags.contains($0) }
      }
      for person in people where !clip.people.contains(person) { clip.people.append(person) }
      if !edit.location.isEmpty { clip.location = edit.location }
      if !edit.scene.isEmpty { clip.scene = edit.scene }
      if !edit.shotType.isEmpty { clip.shotType = edit.shotType }
      if !edit.notes.isEmpty { clip.customNotes = edit.notes }
      apply(edit.favorite, to: &clip.favorite)
      apply(edit.broll, to: &clip.isBroll)
      apply(edit.sermon, to: &clip.isSermon)
      apply(edit.interview, to: &clip.isInterview)
      apply(edit.socialClipCandidate, to: &clip.isSocialClipCandidate)
    }
  }

  func apply(_ action: BatchMetadataEdit.FlagAction, to flag: inout Bool) {
    switch action {
    case .leave: break
    case .set: flag = true
    case .clear: flag = false
    }
  }

  func copyToEditFolder(_ scope: EditFolderExportScope) {
    exportCoordinator.copyToEditFolder(
      scope,
      project: project,
      activeSelectionIDs: activeSelectionIDs,
      resolvedMediaURL: { [weak self] clip in self?.resolvedMediaURL(for: clip) },
      setProgress: { [weak self] progress in self?.exportProgress = progress },
      setSummary: { [weak self] summary in self?.exportSummary = summary }
    )
  }

  /// Fast, non-destructive duplicate detection for a large project. Candidates
  /// share an original filename and byte size; no media is read or altered.
  func findDuplicateCandidates() {
    let copied = project.clips.filter { $0.verificationStatus == .verified }
    let groups = Dictionary(grouping: copied) { clip in
      "\(clip.originalFilename.localizedLowercase)|\(clip.fileSize)"
    }
    let candidateIDs = Set(groups.values.filter { $0.count > 1 }.flatMap { $0.map(\.id) })
    for index in project.clips.indices {
      project.clips[index].automaticTags.removeAll { $0 == "Duplicate Candidate" }
      if candidateIDs.contains(project.clips[index].id) {
        project.clips[index].automaticTags.append("Duplicate Candidate")
      }
    }
    filter = candidateIDs.isEmpty ? "All Clips" : "Duplicate Candidates"
    save()
  }

  func analyzeLocally(mode: LocalAnalysisMode = LocalAnalysisMode(rawValue: UserDefaults.standard.string(forKey: "localAnalysisMode") ?? "Off") ?? .off) {
    analyzeClips(ids: Array(activeSelectionIDs), requestedMode: mode)
  }

  func analyzeVisibleClips() {
    let ids = filteredClips.map(\.id)
    let mode = LocalAnalysisMode(rawValue: UserDefaults.standard.string(forKey: "localAnalysisMode") ?? "Fast") ?? .fast
    analyzeClips(ids: ids, requestedMode: mode)
  }

  func analyzeSelectedClip() {
    guard let selectedClipID else { return }
    let mode = LocalAnalysisMode(rawValue: UserDefaults.standard.string(forKey: "localAnalysisMode") ?? "Fast") ?? .fast
    analyzeClips(ids: [selectedClipID], requestedMode: mode)
  }

  func cancelAnalysis() {
    analysisCoordinator.cancel()
  }

  func analyzeClips(ids: [UUID], requestedMode: LocalAnalysisMode) {
    analysisCoordinator.analyzeClips(
      ids: ids,
      requestedMode: requestedMode,
      activeSelectionIDs: activeSelectionIDs,
      project: { [weak self] in self?.project ?? ClipVaultProject(name: "", projectFolderPath: "") },
      resolvedMediaURL: { [weak self] clip in self?.resolvedMediaURL(for: clip) },
      replaceClip: { [weak self] id, analyzed in
        guard let self, let updatedIndex = self.project.clips.firstIndex(where: { $0.id == id }) else { return }
        self.project.clips[updatedIndex] = analyzed
      },
      save: { [weak self] in self?.save() }
    )
  }

  func exportClipReport(_ kind: ClipReportKind = .allClips) {
    exportCoordinator.exportClipReport(kind, project: project) { [weak self] message in
      self?.operationError = message
      self?.canRetryProjectSave = false
    }
  }

  func exportProjectMetadata() {
    exportCoordinator.exportProjectMetadata(project: project) { [weak self] message in
      self?.operationError = message
      self?.canRetryProjectSave = false
    }
  }

}
