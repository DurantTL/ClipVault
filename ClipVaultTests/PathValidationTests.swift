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
