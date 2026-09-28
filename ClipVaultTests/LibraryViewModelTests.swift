import XCTest

@testable import SlateBox

@MainActor
final class LibraryViewModelTests: XCTestCase {
  private var folder: URL!

  override func setUpWithError() throws {
    folder = FileManager.default.temporaryDirectory
      .appendingPathComponent("clipvault-library-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    UserDefaults.standard.set(false, forKey: "autoAdvanceAfterRating")
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: folder)
  }

  private func makeClip(_ name: String, copied: Bool = true) -> Clip {
    var clip = Clip(
      originalSourcePath: "/Volumes/CARD/\(name)",
      originalFilename: name,
      currentPath: folder.appendingPathComponent(name).path,
      currentFilename: name,
      relativePath: name,
      fileSize: 1024
    )
    clip.copyStatus = copied ? .copied : .pending
    clip.verificationStatus = copied ? .verified : .pending
    return clip
  }

  private func makeViewModel(_ clips: [Clip]) -> LibraryViewModel {
    let project = ClipVaultProject(name: "Test", projectFolderPath: folder.path, clips: clips)
    return LibraryViewModel(project: project)
  }

  // MARK: - Rating / cull status sync

  func testSetRatingKeepsCullStatusInSync() {
    let clip = makeClip("A.mp4")
    let vm = makeViewModel([clip])
    vm.selectedClipID = clip.id
    vm.selectedClipIDs = [clip.id]

    let expectations: [(Int, CullStatus)] = [(1, .reject), (3, .maybe), (5, .keep), (0, .unrated)]
    for (rating, status) in expectations {
      vm.setRating(rating)
      XCTAssertEqual(vm.selectedClip?.rating, rating)
      XCTAssertEqual(vm.selectedClip?.cullStatus, status)
    }
  }

  func testSetStatusAppliesToWholeMultiSelection() {
    let a = makeClip("A.mp4")
    let b = makeClip("B.mp4")
    let c = makeClip("C.mp4")
    let vm = makeViewModel([a, b, c])
    vm.selectedClipID = a.id
    vm.selectedClipIDs = [a.id, b.id]

    vm.setStatus(.keep)

    XCTAssertEqual(vm.project.clips.first { $0.id == a.id }?.cullStatus, .keep)
    XCTAssertEqual(vm.project.clips.first { $0.id == b.id }?.cullStatus, .keep)
    XCTAssertEqual(vm.project.clips.first { $0.id == c.id }?.cullStatus, .unrated)
  }

  func testRatingChangesArePersistedToProjectFile() throws {
    let clip = makeClip("A.mp4")
    let vm = makeViewModel([clip])
    vm.selectedClipID = clip.id
    vm.selectedClipIDs = [clip.id]
    vm.setRating(4)

    let reloaded = try ProjectStore().load(from: folder)
    XCTAssertEqual(reloaded.clips.first?.rating, 4)
    XCTAssertEqual(reloaded.clips.first?.cullStatus, .keep)
  }

  // MARK: - Filters

  func testStatusAndStarFilters() {
    var keep = makeClip("K.mp4"); keep.applyRating(5)
    var maybe = makeClip("M.mp4"); maybe.applyRating(3)
    var reject = makeClip("R.mp4"); reject.applyRating(1)
    let unrated = makeClip("U.mp4")
    let vm = makeViewModel([keep, maybe, reject, unrated])

    func names(_ filter: String) -> Set<String> {
      vm.filter = filter
      return Set(vm.filteredClips.map(\.currentFilename))
    }

    XCTAssertEqual(names("All Clips").count, 4)
    XCTAssertEqual(names("Keep"), ["K.mp4"])
    XCTAssertEqual(names("Maybe"), ["M.mp4"])
    XCTAssertEqual(names("Reject"), ["R.mp4"])
    XCTAssertEqual(names("Unrated"), ["U.mp4"])
    XCTAssertEqual(names("4+ Stars"), ["K.mp4"])
    XCTAssertEqual(names("Favorites (5-Star)"), ["K.mp4"])
    XCTAssertEqual(vm.clipCount(for: "Keep"), 1)
  }

  func testSortByFilenameDescending() {
    let vm = makeViewModel([makeClip("B.mp4"), makeClip("A.mp4"), makeClip("C.mp4")])
    vm.sortOption = .filename
    vm.sortAscending = false
    XCTAssertEqual(vm.filteredClips.map(\.currentFilename), ["C.mp4", "B.mp4", "A.mp4"])
  }

  // MARK: - Export scopes

  func testExportableClipsPerScopeUseOnlyCopiedClips() {
    var keep = makeClip("K.mp4"); keep.applyRating(5)
    var maybe = makeClip("M.mp4"); maybe.applyRating(3)
    var four = makeClip("F.mp4"); four.applyRating(4)
    var pendingKeep = makeClip("P.mp4", copied: false); pendingKeep.applyRating(5)
    let vm = makeViewModel([keep, maybe, four, pendingKeep])
    let coordinator = vm.exportCoordinator
    let url: (Clip) -> URL? = { URL(fileURLWithPath: $0.currentPath) }

    func names(_ scope: EditFolderExportScope, selection: Set<UUID> = []) -> Set<String> {
      Set(
        coordinator.exportableClips(
          for: scope, project: vm.project, activeSelectionIDs: selection, resolvedMediaURL: url
        ).map(\.currentFilename))
    }

    XCTAssertEqual(names(.keeps), ["K.mp4", "F.mp4"])
    XCTAssertEqual(names(.keepsAndMaybes), ["K.mp4", "F.mp4", "M.mp4"])
    XCTAssertEqual(names(.fourPlusStars), ["K.mp4", "F.mp4"])
    XCTAssertEqual(names(.selected, selection: [maybe.id, pendingKeep.id]), ["M.mp4"])
  }
}
