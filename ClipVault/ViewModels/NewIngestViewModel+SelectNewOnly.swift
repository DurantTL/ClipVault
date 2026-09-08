import Foundation

extension NewIngestViewModel {
  func selectAllSessions() {
    prefersNewOnlySelection = false
    for index in sessions.indices { setSession(at: index, selected: true) }
  }

  func clearSessionSelection() {
    prefersNewOnlySelection = false
    for index in sessions.indices { setSession(at: index, selected: false) }
  }

  func selectTodaySessions() {
    prefersNewOnlySelection = false
    for index in sessions.indices { setSession(at: index, selected: Calendar.current.isDateInToday(sessions[index].date)) }
  }

  func selectSessions(on date: Date) {
    prefersNewOnlySelection = false
    for index in sessions.indices { setSession(at: index, selected: Calendar.current.isDate(sessions[index].date, inSameDayAs: date)) }
  }

  /// Select New Only requires Preflight results. Prefer
  /// `PreflightMediaCheckViewModel.applyNewOnlySelection(to:)` once results exist.
  /// Without results this clears selection rather than silently selecting everything.
  func selectNewOnlySessions() {
    prefersNewOnlySelection = true
    // Intentional: do not fall back to Select All. New-only is gated on preflight.
    clearSessionSelectionPreservingNewOnlyPreference()
  }

  /// Apply preflight statuses: only `.newMedia` is selected.
  /// Already-imported and review statuses stay visible but unselected.
  func applyNewOnlySelection(from results: [UUID: PreflightClipResult]) {
    prefersNewOnlySelection = true
    guard !results.isEmpty else {
      clearSessionSelectionPreservingNewOnlyPreference()
      return
    }
    for sessionIndex in sessions.indices {
      for clipIndex in sessions[sessionIndex].clips.indices {
        let clipID = sessions[sessionIndex].clips[clipIndex].id
        // Only explicit New is selected. Missing results are not treated as New.
        sessions[sessionIndex].clips[clipIndex].selected = results[clipID]?.status.isNew == true
      }
      sessions[sessionIndex].selected =
        sessions[sessionIndex].clips.contains(where: { $0.selected })
    }
  }

  private func clearSessionSelectionPreservingNewOnlyPreference() {
    let keepPreference = prefersNewOnlySelection
    for index in sessions.indices { setSession(at: index, selected: false) }
    prefersNewOnlySelection = keepPreference
  }

  func setSession(_ session: IngestSession, selected: Bool) {
    prefersNewOnlySelection = false
    guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
    setSession(at: index, selected: selected)
  }

  func toggleSession(_ session: IngestSession) {
    prefersNewOnlySelection = false
    guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
    setSession(at: index, selected: !sessions[index].selected)
  }

}
