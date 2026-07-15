import XCTest

@testable import SlateBox

final class FileMoveServiceTests: XCTestCase {
  private var projectFolder: URL!

  override func setUpWithError() throws {
    projectFolder = FileManager.default.temporaryDirectory
      .appendingPathComponent("clipvault-move-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: projectFolder, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: projectFolder)
  }

  private func makeClip(named filename: String, bytes: Int = 64) throws -> Clip {
    let url = projectFolder.appendingPathComponent(filename)
    try Data(repeating: 0x7, count: bytes).write(to: url)
    return Clip(
      originalSourcePath: "/Volumes/CARD/\(filename)",
      originalFilename: filename,
      currentPath: url.path,
      currentFilename: filename,
      relativePath: filename,
      fileSize: Int64(bytes)
    )
  }

  private func makeProject(clips: [Clip]) -> ClipVaultProject {
    ClipVaultProject(
      name: "Move Test",
      projectFolderPath: projectFolder.path,
      clips: clips
    )
  }

  func testMoveRelocatesFileAndUpdatesClipMetadata() throws {
    var clip = try makeClip(named: "A001.MP4")
    let mover = FileMoveService()

    try mover.move(clip: &clip, to: "Sermon", projectFolder: projectFolder)

    let moved = projectFolder.appendingPathComponent("Sermon/A001.MP4")
    XCTAssertTrue(FileManager.default.fileExists(atPath: moved.path))
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: projectFolder.appendingPathComponent("A001.MP4").path)
    )
    XCTAssertEqual(clip.currentPath, moved.path)
    XCTAssertEqual(clip.currentFilename, "A001.MP4")
    XCTAssertEqual(clip.assignedFolder, "Sermon")
    XCTAssertEqual(clip.relativePath, "Sermon/A001.MP4")
  }

  func testMoveNeverOverwritesExistingDestinationFile() throws {
    let occupied = projectFolder.appendingPathComponent("Sermon/A001.MP4")
    try FileManager.default.createDirectory(
      at: occupied.deletingLastPathComponent(), withIntermediateDirectories: true)
    let existingData = Data(repeating: 0xEE, count: 32)
    try existingData.write(to: occupied)

    var clip = try makeClip(named: "A001.MP4")
    let mover = FileMoveService()

    try mover.move(clip: &clip, to: "Sermon", projectFolder: projectFolder)

    XCTAssertEqual(clip.currentFilename, "A001_1.MP4")
    XCTAssertTrue(FileManager.default.fileExists(atPath: clip.currentPath))
    XCTAssertEqual(try Data(contentsOf: occupied), existingData)
  }

  func testUndoRestoresLastMoveAndClearsRecord() throws {
    var clip = try makeClip(named: "A001.MP4")
    let originalPath = clip.currentPath
    let mover = FileMoveService()
    try mover.move(clip: &clip, to: "Sermon", projectFolder: projectFolder)

    var project = makeProject(clips: [clip])
    try mover.undo(project: &project)

    XCTAssertEqual(project.clips[0].currentPath, originalPath)
    XCTAssertTrue(FileManager.default.fileExists(atPath: originalPath))
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: projectFolder.appendingPathComponent("Sermon/A001.MP4").path))
    XCTAssertNil(project.clips[0].assignedFolder)
    XCTAssertNil(mover.lastMove)
  }

  func testUndoWithoutRecordedMoveLeavesProjectUntouched() throws {
    let clip = try makeClip(named: "A001.MP4")
    var project = makeProject(clips: [clip])
    let mover = FileMoveService()

    try mover.undo(project: &project)

    XCTAssertEqual(project.clips[0].currentPath, clip.currentPath)
    XCTAssertNil(project.clips[0].assignedFolder)
  }

  func testMoveFailureLeavesClipMetadataUnchanged() throws {
    var clip = try makeClip(named: "A001.MP4")
    try FileManager.default.removeItem(at: URL(fileURLWithPath: clip.currentPath))
    let before = clip
    let mover = FileMoveService()

    XCTAssertThrowsError(
      try mover.move(clip: &clip, to: "Sermon", projectFolder: projectFolder)
    )
    XCTAssertEqual(clip.currentPath, before.currentPath)
    XCTAssertEqual(clip.currentFilename, before.currentFilename)
    XCTAssertNil(clip.assignedFolder)
  }
}
