import Foundation

/// Local analysis collaborator for `LibraryViewModel`.
/// Analysis runs only on copied project media and never auto-applies
/// suggested ratings over a human decision.
@MainActor
final class LibraryAnalysisCoordinator {
  let analysis = LocalAnalysisService()
  nonisolated(unsafe) private var analysisTask: Task<Void, Never>?

  /// `nonisolated` so `LibraryViewModel.deinit` (always nonisolated, even for
  /// a @MainActor-owning class) can cancel in-flight work synchronously.
  /// Safe because by the time deinit runs, no other reference to this
  /// coordinator remains to race with the task-handle mutation.
  nonisolated func cancel() {
    analysisTask?.cancel()
    analysisTask = nil
  }

  func applyAutomaticTags(project: inout ClipVaultProject) {
    for index in project.clips.indices {
      project.clips[index].automaticTags = analysis.tags(for: project.clips[index])
    }
  }

  /// Applies analysis-suggested ratings, but only to clips the user has not
  /// rated yet. Suggestions never overwrite a human decision.
  func applySuggestedRatingsToUnrated(project: inout ClipVaultProject) {
    for index in project.clips.indices {
      let clip = project.clips[index]
      guard clip.rating == 0, clip.cullStatus == .unrated, let suggested = clip.suggestedRating else { continue }
      project.clips[index].applyRating(suggested)
    }
  }

  func analyzeClips(
    ids: [UUID],
    requestedMode: LocalAnalysisMode,
    activeSelectionIDs: Set<UUID>,
    project: @escaping () -> ClipVaultProject,
    resolvedMediaURL: @escaping (Clip) -> URL?,
    replaceClip: @escaping (UUID, Clip) -> Void,
    save: @escaping () -> Void
  ) {
    let tuning = AppSettings().performanceTuning()
    let mode = requestedMode == .off ? tuning.analysisMode : requestedMode
    guard mode != .off else { return }
    analysisTask?.cancel()
    let orderedIDs = prioritize(ids: ids, activeSelectionIDs: activeSelectionIDs)
    analysisTask = Task(priority: tuning.backgroundPriority) { [weak self] in
      guard let self else { return }
      for id in orderedIDs {
        if Task.isCancelled { break }
        let current = project()
        guard let clip = current.clips.first(where: { $0.id == id }) else { continue }
        guard clip.copyStatus != .pending, clip.copyStatus != .copying else { continue }
        guard resolvedMediaURL(clip) != nil else { continue }
        let workID = await BackgroundWorkCoordinator.shared.begin(kind: .localAnalysis, label: clip.currentFilename)
        let start = Date()
        let analyzed = await self.analysis.analyzed(clip, mode: mode)
        await BackgroundWorkCoordinator.shared.finish(workID)
        PerformanceLogger.shared.analysis(
          duration: Date().timeIntervalSince(start),
          filename: clip.currentFilename,
          failed: analyzed.analysisStatus == .failed
        )
        replaceClip(id, analyzed)
        save()
      }
    }
  }

  private func prioritize(ids: [UUID], activeSelectionIDs: Set<UUID>) -> [UUID] {
    var seen = Set<UUID>()
    var ordered: [UUID] = []
    for id in Array(activeSelectionIDs) + ids {
      if seen.insert(id).inserted { ordered.append(id) }
    }
    return ordered
  }
}
