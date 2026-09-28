import XCTest

@testable import SlateBox

final class PathValidationTests: XCTestCase {
  private var root: URL!

  override func setUpWithError() throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("clipvault-path-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: root)
  }

  func testAcceptsOrdinaryNames() throws {
    XCTAssertEqual(try SafeFilename.validatedComponent("2026-09-28 Video Ingest"), "2026-09-28 Video Ingest")
    XCTAssertEqual(try SafeFilename.validatedComponent("  Camp Meeting  "), "Camp Meeting")
  }

  func testRejectsTraversalAndSeparators() {
    for bad in ["..", ".", "../x", "a/b", "a\\b", "/abs", "~", "~/x", "a:b", "", "   ", "...", "a\u{0}b", "a\nb"] {
      XCTAssertThrowsError(try SafeFilename.validatedComponent(bad), "should reject \(bad.debugDescription)")
    }
  }

  func testTrimsTrailingDotsAndSpaces() throws {
    XCTAssertEqual(try SafeFilename.validatedComponent("Shoot. "), "Shoot")
  }

  func testRejectsOverlongNames() {
    XCTAssertThrowsError(try SafeFilename.validatedComponent(String(repeating: "a", count: 300)))
  }

  func testUnicodeNormalizedToComposedForm() throws {
    let decomposed = "Cafe\u{0301}"
    XCTAssertEqual(try SafeFilename.validatedComponent(decomposed), "Caf\u{00E9}")
  }

  func testSafeFolderNameNeverYieldsTraversal() {
    XCTAssertEqual(SafeFilename.safeFolderName(".."), "")
    XCTAssertEqual(SafeFilename.safeFolderName("a/../b"), "a-..-b")
    XCTAssertEqual(SafeFilename.safeFolderName("a\\b:c"), "a-b-c")
  }

  func testContainment() throws {
    XCTAssertTrue(SafeFilename.isContained(root.appendingPathComponent("Project/clip.mp4"), in: root))
    XCTAssertTrue(SafeFilename.isContained(root, in: root))
    XCTAssertFalse(SafeFilename.isContained(root.appendingPathComponent("../elsewhere"), in: root))
    XCTAssertFalse(SafeFilename.isContained(root.appendingPathComponent("Project/../../elsewhere"), in: root))
    // Sibling with a shared prefix must not count as contained.
    XCTAssertFalse(SafeFilename.isContained(URL(fileURLWithPath: root.path + "-sibling/x"), in: root))
  }

  func testAssertContainedThrowsWhenEscaping() {
    XCTAssertNoThrow(try SafeFilename.assertContained(root.appendingPathComponent("a/b"), in: root))
    XCTAssertThrowsError(try SafeFilename.assertContained(root.appendingPathComponent("../b"), in: root)) {
      XCTAssertEqual($0 as? PathValidationError, .escapesDestination)
    }
  }

  func testAliasFolderNameCannotEscapeAliasesFolder() throws {
    let media = root.appendingPathComponent("clip.mp4")
    try Data([1]).write(to: media)
    let clip = Clip(
      originalSourcePath: "/src/clip.mp4", originalFilename: "clip.mp4",
      currentPath: media.path, currentFilename: "clip.mp4", relativePath: "clip.mp4", fileSize: 1)
    let summary = AliasService().createAliases(
      named: "../../escape", for: [(clip: clip, mediaURL: media)], projectFolder: root)
    XCTAssertTrue(SafeFilename.isContained(summary.aliasesFolder, in: root.appendingPathComponent("Aliases")))
    XCTAssertFalse(FileManager.default.fileExists(atPath: root.deletingLastPathComponent().appendingPathComponent("escape").path))
  }

  // MARK: - Destination vs. source guard

  func testDestinationInsideSourceIsRefused() {
    let card = URL(fileURLWithPath: "/ClipVaultTestVolume/CARD")
    XCTAssertEqual(
      SourceDestinationGuard.conflict(
        source: card, destination: card.appendingPathComponent("PRIVATE/Out"), sourceLooksLikeCard: false),
      .destinationOnSource)
    XCTAssertEqual(
      SourceDestinationGuard.conflict(source: card, destination: card, sourceLooksLikeCard: false),
      .destinationOnSource, "The source folder itself is not a valid destination")
  }

  func testUnrelatedDestinationIsAllowed() {
    let card = URL(fileURLWithPath: "/ClipVaultTestVolume/CARD")
    XCTAssertNil(SourceDestinationGuard.conflict(
      source: card, destination: URL(fileURLWithPath: "/ClipVaultTestVolume/Projects"), sourceLooksLikeCard: false))
    // A sibling that merely shares a name prefix is not inside the source.
    XCTAssertNil(SourceDestinationGuard.conflict(
      source: card, destination: URL(fileURLWithPath: "/ClipVaultTestVolume/CARD2/Out"), sourceLooksLikeCard: false))
  }

  func testNonexistentVolumesNeverCountAsSharedRemovableVolume() {
    XCTAssertFalse(SourceDestinationGuard.sharesRemovableVolume(
      source: URL(fileURLWithPath: "/ClipVaultTestVolume/A"),
      destination: URL(fileURLWithPath: "/ClipVaultTestVolume/B")))
  }

  func testGuardMessageIsActionable() {
    XCTAssertEqual(
      PathValidationError.destinationOnSource.errorDescription,
      "The destination is on the source card. Choose a folder on a different drive so nothing is ever written to the card.")
  }

  // Uses a made-up top-level path so the result does not depend on which
  // directories exist (or are symlinked) on the machine running the tests.
  func testContainmentIsCaseInsensitive() {
    let volume = URL(fileURLWithPath: "/ClipVaultTestVolume/Project")
    XCTAssertTrue(SafeFilename.isContained(URL(fileURLWithPath: "/CLIPVAULTTESTVOLUME/project/Clip.mp4"), in: volume))
    XCTAssertFalse(SafeFilename.isContained(URL(fileURLWithPath: "/ClipVaultTestVolume/Project2/Clip.mp4"), in: volume))
  }

  func testContainmentTreatsComposedAndDecomposedNamesAsEqual() {
    let composed = URL(fileURLWithPath: "/ClipVaultTestVolume/Caf\u{00E9}")
    let decomposed = URL(fileURLWithPath: "/ClipVaultTestVolume/Cafe\u{0301}/Clip.mp4")
    XCTAssertTrue(SafeFilename.isContained(decomposed, in: composed))
  }

  func testThumbnailDirectoriesStayInsideTheirAccessRoot() {
    let projectFolder = URL(fileURLWithPath: "/ClipVaultTestVolume/Project")
    let custom = URL(fileURLWithPath: "/ClipVaultTestVolume/Thumbs")
    for location in ProjectThumbnailStorageLocation.allCases {
      let resolved = StoragePreferences.projectThumbnailDirectory(
        location: location, projectID: UUID(), projectFolder: projectFolder, customFolder: custom)
      XCTAssertTrue(
        SafeFilename.isContained(resolved.directoryURL, in: resolved.accessURL),
        "\(location) thumbnails escape their access root")
    }
  }

  func testContainmentFollowsSymlinks() throws {
    let outside = FileManager.default.temporaryDirectory
      .appendingPathComponent("clipvault-outside-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: outside) }
    let link = root.appendingPathComponent("link")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
    XCTAssertFalse(SafeFilename.isContained(link.appendingPathComponent("clip.mp4"), in: root))
  }

  func testRecentProjectSummaryIdentityIsPathBased() {
    let a = RecentProjectSummary(path: "/Volumes/X/P/.clipvault-project.json", project: nil)
    let b = RecentProjectSummary(path: "/Volumes/X/P/.clipvault-project.json", project: nil)
    XCTAssertEqual(a.id, b.id)
    XCTAssertNotEqual(a.id, RecentProjectSummary(path: "/Volumes/X/Q/.clipvault-project.json", project: nil).id)
  }
}
