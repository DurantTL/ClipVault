import Foundation

/// Focused selection collaborator for `LibraryViewModel`.
/// Owns multi-select / range / navigation helpers while the shell ViewModel
/// keeps the `@Published` UI bindings Views already observe.
@MainActor
final class LibrarySelectionController {
  private(set) var selectionAnchorID: UUID?

  func activeSelectionIDs(selectedClipID: UUID?, selectedClipIDs: Set<UUID>) -> Set<UUID> {
    selectedClipIDs.isEmpty ? Set(selectedClipID.map { [$0] } ?? []) : selectedClipIDs
  }

  func select(
    _ clip: Clip,
    extending: Bool,
    selectedClipID: inout UUID?,
    selectedClipIDs: inout Set<UUID>
  ) {
    selectedClipID = clip.id
    if extending {
      if selectedClipIDs.contains(clip.id) {
        selectedClipIDs.remove(clip.id)
      } else {
        selectedClipIDs.insert(clip.id)
      }
    } else {
      selectedClipIDs = [clip.id]
      selectionAnchorID = clip.id
    }
  }

  /// Shift-click: selects every visible clip between the selection anchor
  /// (the last plain click) and the clicked clip.
  func selectRange(
    to clip: Clip,
    filteredClips: [Clip],
    selectedClipID: inout UUID?,
    selectedClipIDs: inout Set<UUID>
  ) {
    guard let clickedIndex = filteredClips.firstIndex(where: { $0.id == clip.id }) else { return }
    let anchorID = selectionAnchorID ?? selectedClipID
    guard let anchorIndex = anchorID.flatMap({ id in filteredClips.firstIndex { $0.id == id } }) else {
      select(clip, extending: false, selectedClipID: &selectedClipID, selectedClipIDs: &selectedClipIDs)
      return
    }
    let range = min(anchorIndex, clickedIndex)...max(anchorIndex, clickedIndex)
    selectedClipIDs.formUnion(filteredClips[range].map(\.id))
    selectedClipID = clip.id
  }

  func selectAllVisible(
    filteredClips: [Clip],
    selectedClipID: inout UUID?,
    selectedClipIDs: inout Set<UUID>
  ) {
    selectedClipIDs = Set(filteredClips.map(\.id))
    if selectedClipID == nil { selectedClipID = filteredClips.first?.id }
  }

  /// Escape: collapses a multi-selection back to the focused clip.
  func clearMultiSelection(selectedClipID: UUID?, selectedClipIDs: inout Set<UUID>) {
    selectedClipIDs = Set(selectedClipID.map { [$0] } ?? [])
  }

  func select(
    offset: Int,
    filteredClips: [Clip],
    selectedClipID: inout UUID?,
    selectedClipIDs: inout Set<UUID>
  ) {
    guard !filteredClips.isEmpty else { return }
    let current = selectedClipID.flatMap { id in filteredClips.firstIndex { $0.id == id } } ?? 0
    let nextIndex = min(max(current + offset, 0), filteredClips.count - 1)
    select(
      filteredClips[nextIndex],
      extending: false,
      selectedClipID: &selectedClipID,
      selectedClipIDs: &selectedClipIDs
    )
  }

  func advanceAfterRating(
    previous: Bool,
    filteredClips: [Clip],
    selectedClipID: inout UUID?,
    selectedClipIDs: inout Set<UUID>
  ) {
    select(
      offset: previous ? -1 : 1,
      filteredClips: filteredClips,
      selectedClipID: &selectedClipID,
      selectedClipIDs: &selectedClipIDs
    )
  }
}
