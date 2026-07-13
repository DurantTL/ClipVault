import XCTest

@testable import SlateBox

final class PreflightMediaCheckTests: XCTestCase {
  private var root: URL!

  override func setUpWithError() throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("slatebox-preflight-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: root)
  }

  func testExactDestinationMatchIsAlreadyImported() async throws {
    let modified = Date(timeIntervalSince1970: 1_700_000_000)
    let existing = root.appendingPathComponent("Project/C0001.MP4")
    try writeFile(existing, bytes: 256, modifiedAt: modified)

    let sourceID = UUID()
    let results = await PreflightMediaCheckService().check(
      sourceFiles: [
        PreflightSourceFile(
          id: sourceID,
          filename: "C0001.MP4",
          fileSize: 256,
          modifiedAt: modified,
          duration: nil
        )
      ],
      knownCandidates: [],
      scanLocations: [
        PreflightScanLocation(
          rootURL: root,
          kind: .destination,
          label: "Destination"
        )
      ]
    )

    XCTAssertEqual(results[sourceID]?.status, .alreadyInDestination)
    XCTAssertEqual(results[sourceID]?.matchedPath, existing.path)
  }

  func testSameNameDifferentSizeRequiresReview() async throws {
    let modified = Date(timeIntervalSince1970: 1_700_000_000)
    try writeFile(
      root.appendingPathComponent("C0002.MP4"),
      bytes: 128,
      modifiedAt: modified
    )

    let sourceID = UUID()
    let results = await PreflightMediaCheckService().check(
      sourceFiles: [
        PreflightSourceFile(
          id: sourceID,
          filename: "C0002.MP4",
          fileSize: 512,
          modifiedAt: modified,
          duration: nil
        )
      ],
      knownCandidates: [],
      scanLocations: [
        PreflightScanLocation(
          rootURL: root,
          kind: .destination,
          label: "Destination"
        )
      ]
    )

    XCTAssertEqual(results[sourceID]?.status, .sameNameDifferentSize)
    XCTAssertTrue(results[sourceID]?.status.needsReview == true)
  }

  func testRecentProjectAndBackupMatchesUseSpecificStatuses() async throws {
    let modified = Date(timeIntervalSince1970: 1_700_000_100)
    let projectSourceID = UUID()
    let backupSourceID = UUID()

    let backupRoot = root.appendingPathComponent("Backup", isDirectory: true)
    let backupFile = backupRoot.appendingPathComponent("B0001.MOV")
    try writeFile(backupFile, bytes: 300, modifiedAt: modified)

    let results = await PreflightMediaCheckService().check(
      sourceFiles: [
        PreflightSourceFile(
          id: projectSourceID,
          filename: "A0001.MP4",
          fileSize: 200,
          modifiedAt: modified,
          duration: 12
        ),
        PreflightSourceFile(
          id: backupSourceID,
          filename: "B0001.MOV",
          fileSize: 300,
          modifiedAt: modified,
          duration: nil
        )
      ],
      knownCandidates: [
        PreflightCandidate(
          filename: "A0001.MP4",
          fileSize: 200,
          modifiedAt: modified,
          duration: 12,
          path: "/Volumes/Archive/Project/A0001.MP4",
          kind: .project,
          locationLabel: "Earlier Project"
        )
      ],
      scanLocations: [
        PreflightScanLocation(
          rootURL: backupRoot,
          kind: .backup,
          label: "Backup 1"
        )
      ]
    )

    XCTAssertEqual(results[projectSourceID]?.status, .alreadyInAnotherProject)
    XCTAssertEqual(results[projectSourceID]?.matchedLocationLabel, "Earlier Project")
    XCTAssertEqual(results[backupSourceID]?.status, .alreadyOnBackup)
  }

  func testUnmatchedMediaIsNewAndSameSizeMetadataCanBePossibleDuplicate() async {
    let newID = UUID()
    let possibleID = UUID()
    let modified = Date(timeIntervalSince1970: 1_700_000_200)

    let results = await PreflightMediaCheckService().check(
      sourceFiles: [
        PreflightSourceFile(
          id: newID,
          filename: "NEW0001.MP4",
          fileSize: 999,
          modifiedAt: modified,
          duration: 10
        ),
        PreflightSourceFile(
          id: possibleID,
          filename: "RENAMED.MP4",
          fileSize: 400,
          modifiedAt: modified,
          duration: 20
        )
      ],
      knownCandidates: [
        PreflightCandidate(
          filename: "ORIGINAL.MP4",
          fileSize: 400,
          modifiedAt: modified,
          duration: 20,
          path: "/Volumes/Media/ORIGINAL.MP4",
          kind: .project,
          locationLabel: "Project"
        )
      ],
      scanLocations: []
    )

    XCTAssertEqual(results[newID]?.status, .newMedia)
    XCTAssertEqual(results[possibleID]?.status, .possibleDuplicate)

    let summary = PreflightSummary(results: results)
    XCTAssertEqual(summary.newCount, 1)
    XCTAssertEqual(summary.reviewCount, 1)
  }

  private func writeFile(
    _ url: URL,
    bytes: Int,
    modifiedAt: Date
  ) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data(repeating: 0x2A, count: bytes).write(to: url)
    try FileManager.default.setAttributes(
      [.modificationDate: modifiedAt],
      ofItemAtPath: url.path
    )
  }
}
