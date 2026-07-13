import XCTest

@testable import SlateBox

final class SourceScannerTests: XCTestCase {
  private var card: URL!
  private let scanner = SourceScanner()

  override func setUpWithError() throws {
    card = FileManager.default.temporaryDirectory
      .appendingPathComponent("clipvault-scan-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: card, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: card)
  }

  private func addFile(_ relativePath: String, bytes: Int = 64) throws {
    let url = card.appendingPathComponent(relativePath)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 0x1, count: bytes).write(to: url)
  }

  func testDetectsSonyLayoutAndScansOnlyClipFolder() throws {
    try addFile("PRIVATE/M4ROOT/CLIP/C0001.MP4")
    try addFile("PRIVATE/M4ROOT/CLIP/C0002.MP4")
    try addFile("stray-root-video.mp4")

    XCTAssertEqual(scanner.detectCardType(source: card), .sony)
    let videos = try scanner.scan(source: card, includeProxyFiles: false)

    XCTAssertEqual(videos.map(\.relativePath), [
      "PRIVATE/M4ROOT/CLIP/C0001.MP4",
      "PRIVATE/M4ROOT/CLIP/C0002.MP4"
    ], "a Sony card scans only PRIVATE/M4ROOT/CLIP, not the card root")
    XCTAssertTrue(videos.allSatisfy { $0.cardType == DetectedCardType.sony.rawValue })
    XCTAssertTrue(videos.allSatisfy { $0.sonyCardFolderPath != nil })
  }

  func testSonyProxySubExcludedByDefaultIncludedOnOptIn() throws {
    try addFile("PRIVATE/M4ROOT/CLIP/C0001.MP4")
    try addFile("PRIVATE/M4ROOT/SUB/C0001S03.MP4")

    let withoutProxies = try scanner.scan(source: card, includeProxyFiles: false)
    XCTAssertEqual(withoutProxies.map(\.relativePath), ["PRIVATE/M4ROOT/CLIP/C0001.MP4"])

    let withProxies = try scanner.scan(source: card, includeProxyFiles: true)
    XCTAssertEqual(withProxies.map(\.relativePath), [
      "PRIVATE/M4ROOT/CLIP/C0001.MP4",
      "PRIVATE/M4ROOT/SUB/C0001S03.MP4"
    ])
  }

  func testDetectsCanonDCIMAndIgnoresPhotoSidecars() throws {
    try addFile("DCIM/100CANON/MVI_0001.MP4")
    try addFile("DCIM/100CANON/IMG_0002.CR3")
    try addFile("DCIM/100CANON/MVI_0001.THM")
    try addFile("DCIM/100CANON/MVI_0001.XML")

    XCTAssertEqual(scanner.detectCardType(source: card), .canonDCF)
    let videos = try scanner.scan(source: card, includeProxyFiles: false)

    XCTAssertEqual(videos.map(\.relativePath), ["DCIM/100CANON/MVI_0001.MP4"],
      "photo and sidecar formats must be ignored on Canon/DCF cards")
    XCTAssertTrue(videos.allSatisfy { $0.cardType == DetectedCardType.canonDCF.rawValue })
  }

  func testGenericRecursiveScanWithRelativePathsAndNaturalSort() throws {
    try addFile("shoot/A10.mp4")
    try addFile("shoot/A2.mp4")
    try addFile("extra/B1.MOV")

    XCTAssertEqual(scanner.detectCardType(source: card), .generic)
    let videos = try scanner.scan(source: card, includeProxyFiles: false)

    XCTAssertEqual(videos.map(\.relativePath), [
      "extra/B1.MOV",
      "shoot/A2.mp4",
      "shoot/A10.mp4"
    ], "generic scans recurse and sort naturally, so A2 comes before A10")
    XCTAssertTrue(videos.allSatisfy { $0.size == 64 })
  }

  func testSkipsHiddenAndUnsupportedExtensions() throws {
    try addFile("clips/A001.mp4")
    try addFile("clips/.hidden.mp4")
    try addFile("clips/notes.txt")
    try addFile("clips/photo.jpg")

    let videos = try scanner.scan(source: card, includeProxyFiles: false)
    XCTAssertEqual(videos.map(\.relativePath), ["clips/A001.mp4"])
  }

  func testNetworkCapacityDoesNotUseImportantUsageEstimate() {
    XCTAssertEqual(
      VolumeCapacity.preferredAvailableCapacity(
        isLocal: false,
        important: 900,
        regular: 400,
        fileSystem: 300
      ),
      400
    )
  }

  func testLocalCapacityPrefersImportantUsageEstimate() {
    XCTAssertEqual(
      VolumeCapacity.preferredAvailableCapacity(
        isLocal: true,
        important: 900,
        regular: 400,
        fileSystem: 300
      ),
      900
    )
  }

  func testCapacityFallsBackToFilesystemValue() {
    XCTAssertEqual(
      VolumeCapacity.preferredAvailableCapacity(
        isLocal: false,
        important: nil,
        regular: nil,
        fileSystem: 300
      ),
      300
    )
  }

  func testProjectDestinationPreviewPathStaysInsideProject() {
    let destination = URL(fileURLWithPath: "/Volumes/NAS/Project", isDirectory: true)
    let storage = StoragePreferences.sourcePreviewDirectory(
      location: .projectDestination,
      destinationRoot: destination,
      customFolder: nil
    )

    XCTAssertEqual(
      storage?.directoryURL.path,
      "/Volumes/NAS/Project/.clipvault-cache/ingest-previews"
    )
    XCTAssertEqual(storage?.accessURL.path, destination.path)
  }

  func testDisabledSourcePreviewsHaveNoStorageDirectory() {
    XCTAssertNil(
      StoragePreferences.sourcePreviewDirectory(
        location: .disabled,
        destinationRoot: nil,
        customFolder: nil
      )
    )
  }

  func testCustomProjectThumbnailPathUsesProjectSpecificFolder() {
    let projectID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    let custom = URL(fileURLWithPath: "/Volumes/Cache", isDirectory: true)
    let project = URL(fileURLWithPath: "/Volumes/NAS/Project", isDirectory: true)
    let storage = StoragePreferences.projectThumbnailDirectory(
      location: .customFolder,
      projectID: projectID,
      projectFolder: project,
      customFolder: custom
    )

    XCTAssertEqual(
      storage.directoryURL.path,
      "/Volumes/Cache/SlateBox/ProjectThumbnails/11111111-2222-3333-4444-555555555555"
    )
    XCTAssertEqual(storage.accessURL.path, custom.path)
  }

  func testProjectThumbnailDefaultStaysInsideProject() {
    let projectID = UUID()
    let project = URL(fileURLWithPath: "/Volumes/NAS/Project", isDirectory: true)
    let storage = StoragePreferences.projectThumbnailDirectory(
      location: .projectFolder,
      projectID: projectID,
      projectFolder: project,
      customFolder: nil
    )

    XCTAssertEqual(
      storage.directoryURL.path,
      "/Volumes/NAS/Project/.clipvault-cache/thumbnails"
    )
  }

  // MARK: Preflight media check

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
