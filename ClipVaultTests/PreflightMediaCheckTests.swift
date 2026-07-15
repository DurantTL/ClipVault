import XCTest

@testable import SlateBox

final class PreflightMediaCheckTests: XCTestCase {
  private var card: URL!

  override func setUpWithError() throws {
    card = FileManager.default.temporaryDirectory
      .appendingPathComponent("clipvault-preflight-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: card, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: card)
  }

  func testPreflightExactDestinationMatchIsAlreadyImported() async throws {
    let modified = Date(timeIntervalSince1970: 1_700_000_000)
    let existing = card.appendingPathComponent("Project/C0001.MP4")
    try writePreflightFile(existing, bytes: 256, modifiedAt: modified)

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
          rootURL: card,
          kind: .destination,
          label: "Destination"
        )
      ]
    )

    XCTAssertEqual(results[sourceID]?.status, .alreadyInDestination)
    XCTAssertEqual(results[sourceID]?.matchedPath, existing.path)
  }

  func testPreflightSameNameDifferentSizeRequiresReview() async throws {
    let modified = Date(timeIntervalSince1970: 1_700_000_000)
    try writePreflightFile(
      card.appendingPathComponent("C0002.MP4"),
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
          rootURL: card,
          kind: .destination,
          label: "Destination"
        )
      ]
    )

    XCTAssertEqual(results[sourceID]?.status, .sameNameDifferentSize)
    XCTAssertTrue(results[sourceID]?.status.needsReview == true)
  }

  func testPreflightRecentProjectAndBackupStatuses() async throws {
    let modified = Date(timeIntervalSince1970: 1_700_000_100)
    let projectSourceID = UUID()
    let backupSourceID = UUID()

    let backupRoot = card.appendingPathComponent("Backup", isDirectory: true)
    let backupFile = backupRoot.appendingPathComponent("B0001.MOV")
    try writePreflightFile(backupFile, bytes: 300, modifiedAt: modified)

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

  func testPreflightNewAndPossibleDuplicateSummary() async {
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

  private func writePreflightFile(
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
