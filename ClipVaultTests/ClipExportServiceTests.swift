import XCTest

@testable import SlateBox

final class ClipExportServiceTests: XCTestCase {
  private var directory: URL!
  private var destination: URL!
  private let service = ClipExportService()

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("clipvault-clipexport-test-\(UUID().uuidString)", isDirectory: true)
    destination = directory.appendingPathComponent("Exports", isDirectory: true)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
  }

  private func makeMedia(named name: String, content: String) throws -> (clip: Clip, mediaURL: URL) {
    let url = directory.appendingPathComponent(name)
    let data = Data(content.utf8)
    try data.write(to: url)
    let clip = Clip(
      originalSourcePath: "/Volumes/CARD/PRIVATE/M4ROOT/CLIP/\(name)",
      originalFilename: name,
      currentPath: url.path,
      currentFilename: name,
      relativePath: name,
      fileSize: Int64(data.count)
    )
    return (clip, url)
  }

  func testExportCopiesAllFilesAndLeavesSourcesIntact() async throws {
    let first = try makeMedia(named: "A001.MP4", content: "first clip")
    let second = try makeMedia(named: "A002.MP4", content: "second clip")

    let summary = await service.copyClips([first, second], to: destination) { _ in }

    XCTAssertEqual(summary.copiedCount, 2)
    XCTAssertEqual(summary.failedCount, 0)
    XCTAssertEqual(summary.skippedCount, 0)
    XCTAssertEqual(summary.totalBytesCopied, first.clip.fileSize + second.clip.fileSize)
    XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("A001.MP4")), "first clip")
    XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("A002.MP4")), "second clip")
    XCTAssertEqual(try String(contentsOf: first.mediaURL), "first clip", "export copies, never moves")
    XCTAssertEqual(try String(contentsOf: second.mediaURL), "second clip", "export copies, never moves")
  }

  func testExportNeverOverwritesExistingDestinations() async throws {
    let item = try makeMedia(named: "A001.MP4", content: "new export")
    let existing = destination.appendingPathComponent("A001.MP4")
    try Data("older export".utf8).write(to: existing)

    let summary = await service.copyClips([item], to: destination) { _ in }

    XCTAssertEqual(summary.copiedCount, 1)
    XCTAssertEqual(try String(contentsOf: existing), "older export", "existing files must never be overwritten")
    XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("A001_1.MP4")), "new export")
  }

  func testExportSkipsMissingSourceAndRecordsFailureMessage() async throws {
    let present = try makeMedia(named: "A001.MP4", content: "present")
    let missing = try makeMedia(named: "GONE.MP4", content: "will vanish")
    try FileManager.default.removeItem(at: missing.mediaURL)

    let summary = await service.copyClips([present, missing], to: destination) { _ in }

    XCTAssertEqual(summary.copiedCount, 1)
    XCTAssertEqual(summary.skippedCount, 1)
    XCTAssertEqual(summary.failures, ["GONE.MP4: file is missing"])
  }

  func testSummaryMessageIncludesCounts() async throws {
    let item = try makeMedia(named: "A001.MP4", content: "clip")
    let missing = try makeMedia(named: "GONE.MP4", content: "gone")
    try FileManager.default.removeItem(at: missing.mediaURL)

    let summary = await service.copyClips([item, missing], to: destination) { _ in }

    XCTAssertTrue(summary.message.contains("1 copied"))
    XCTAssertTrue(summary.message.contains("1 skipped"))
    XCTAssertTrue(summary.message.contains(destination.path))
  }
}
