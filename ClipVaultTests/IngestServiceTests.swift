import XCTest

@testable import SlateBox

final class IngestServiceTests: XCTestCase {
  private var directory: URL!
  private var sourceRoot: URL!
  private var destinationRoot: URL!

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("clipvault-ingest-test-\(UUID().uuidString)", isDirectory: true)
    sourceRoot = directory.appendingPathComponent("Source", isDirectory: true)
    destinationRoot = directory.appendingPathComponent("Destination", isDirectory: true)
    try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
  }

  private func makeSettings() -> AppSettings {
    let settings = AppSettings()
    settings.verificationModeRaw = VerificationMode.fast.rawValue
    settings.generateThumbnailsDuringIngest = false
    settings.renameFilesDuringIngest = false
    settings.preserveSourceStructure = false
    settings.backupTransferMode = "Primary only"
    return settings
  }

  private func addSourceVideo(
    _ relativePath: String, bytes: Int = 128, exists: Bool = true
  ) throws -> SourceVideo {
    let url = sourceRoot.appendingPathComponent(relativePath)
    if exists {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data((0..<bytes).map { UInt8($0 % 251) }).write(to: url)
    }
    return SourceVideo(
      url: url,
      relativePath: relativePath,
      size: Int64(bytes),
      createdAt: nil,
      modifiedAt: nil,
      sonyCardFolderPath: nil,
      cardType: DetectedCardType.generic.rawValue
    )
  }

  private func ingest(
    _ videos: [SourceVideo],
    settings: AppSettings,
    progress: @escaping @MainActor (IngestProgress) -> Void = { _ in }
  ) async throws -> (ClipVaultProject, IngestService) {
    let service = IngestService()
    let project = try await service.ingest(
      name: "Ingest Test",
      shootName: "",
      source: sourceRoot,
      destination: destinationRoot,
      videos: videos,
      bookmarks: (nil, nil),
      settings: settings,
      cameraCardMetadata: IngestCameraCardMetadata(),
      progress: progress
    )
    return (project, service)
  }

  func testIngestCopiesVerifiesAndStaysReopenable() async throws {
    let videos = [
      try addSourceVideo("C0001.MP4"),
      try addSourceVideo("C0002.MP4", bytes: 256),
    ]

    let (project, _) = try await ingest(videos, settings: makeSettings())

    XCTAssertEqual(project.ingestStatus, .complete)
    XCTAssertFalse(project.ingestIncomplete)
    XCTAssertEqual(project.copiedClipCount, 2)
    XCTAssertEqual(project.verifiedClipCount, 2)
    XCTAssertEqual(project.failedClipCount, 0)
    XCTAssertEqual(project.pendingClipCount, 0)

    for clip in project.clips {
      XCTAssertEqual(clip.verificationStatus, .verified)
      XCTAssertTrue(FileManager.default.fileExists(atPath: clip.currentPath))
      XCTAssertEqual(
        try Data(contentsOf: URL(fileURLWithPath: clip.currentPath)),
        try Data(contentsOf: URL(fileURLWithPath: clip.sourcePath))
      )
      XCTAssertTrue(FileManager.default.fileExists(atPath: clip.sourcePath), "source must remain")
    }

    let metadataFile = URL(fileURLWithPath: project.projectFolderPath)
      .appendingPathComponent(AppBrand.metadataFileName)
    XCTAssertTrue(FileManager.default.fileExists(atPath: metadataFile.path))
  }

  func testIngestIsolatesPerClipFailuresAndContinues() async throws {
    let videos = [
      try addSourceVideo("C0001.MP4"),
      try addSourceVideo("MISSING.MP4", exists: false),
      try addSourceVideo("C0003.MP4"),
    ]

    let (project, _) = try await ingest(videos, settings: makeSettings())

    XCTAssertEqual(project.ingestStatus, .incomplete)
    XCTAssertTrue(project.ingestIncomplete)
    XCTAssertTrue(project.canResumeIngest)
    XCTAssertEqual(project.failedClipCount, 1)
    XCTAssertEqual(project.copiedClipCount, 2)
    XCTAssertEqual(project.pendingClipCount, 0)

    let failed = project.clips.first { $0.originalFilename == "MISSING.MP4" }
    XCTAssertEqual(failed?.copyStatus, .failed)
    XCTAssertNotNil(failed?.errorMessage)

    let survivors = project.clips.filter { $0.originalFilename != "MISSING.MP4" }
    XCTAssertTrue(survivors.allSatisfy { $0.verificationStatus == .verified })
  }

  func testIngestUsesSafeNamesForCollidingFlatFilenames() async throws {
    let videos = [
      try addSourceVideo("DAY1/C0001.MP4"),
      try addSourceVideo("DAY2/C0001.MP4", bytes: 256),
    ]

    let (project, _) = try await ingest(videos, settings: makeSettings())

    XCTAssertEqual(project.verifiedClipCount, 2)
    let filenames = Set(project.clips.map(\.currentFilename))
    XCTAssertEqual(filenames, ["C0001.MP4", "C0001_1.MP4"])
    for clip in project.clips {
      XCTAssertEqual(
        try Data(contentsOf: URL(fileURLWithPath: clip.currentPath)),
        try Data(contentsOf: URL(fileURLWithPath: clip.sourcePath))
      )
    }
  }

  func testCancelDuringIngestLeavesResumableProject() async throws {
    let videos = [
      try addSourceVideo("C0001.MP4"),
      try addSourceVideo("C0002.MP4"),
      try addSourceVideo("C0003.MP4"),
    ]

    var service: IngestService!
    service = IngestService()
    let project = try await service.ingest(
      name: "Cancel Test",
      shootName: "",
      source: sourceRoot,
      destination: destinationRoot,
      videos: videos,
      bookmarks: (nil, nil),
      settings: makeSettings(),
      cameraCardMetadata: IngestCameraCardMetadata(),
      progress: { update in
        if update.currentIndex >= 2 { service.cancel() }
      }
    )

    XCTAssertEqual(project.ingestStatus, .canceled)
    XCTAssertTrue(project.ingestIncomplete)
    XCTAssertTrue(project.canResumeIngest)
    XCTAssertGreaterThanOrEqual(project.copiedClipCount, 1)
    XCTAssertGreaterThanOrEqual(project.pendingClipCount, 1)

    // The project metadata file exists on disk, so the partial ingest can be reopened.
    let metadataFile = URL(fileURLWithPath: project.projectFolderPath)
      .appendingPathComponent(AppBrand.metadataFileName)
    XCTAssertTrue(FileManager.default.fileExists(atPath: metadataFile.path))

    // Sources are untouched by cancellation.
    for video in videos {
      XCTAssertTrue(FileManager.default.fileExists(atPath: video.url.path))
    }
  }

  func testDestinationCapacityPreflightBlocksOnlyKnownInsufficientSpace() {
    XCTAssertEqual(
      VolumeCapacity.preflightStatus(requiredBytes: 2_000, availableBytes: nil),
      .unknown
    )
    XCTAssertEqual(
      VolumeCapacity.preflightStatus(
        requiredBytes: 2_000,
        availableBytes: 1_999,
        reserveBytes: 500
      ),
      .insufficient
    )
    XCTAssertEqual(
      VolumeCapacity.preflightStatus(
        requiredBytes: 2_000,
        availableBytes: 2_200,
        reserveBytes: 500
      ),
      .lowAfterIngest
    )
    XCTAssertEqual(
      VolumeCapacity.preflightStatus(
        requiredBytes: 2_000,
        availableBytes: 2_500,
        reserveBytes: 500
      ),
      .sufficient
    )
  }

  func testStorageRecoveryProducesActionableMessages() {
    let outOfSpace = CocoaError(.fileWriteOutOfSpace)
    XCTAssertEqual(StorageRecovery.classify(outOfSpace), .outOfSpace)
    XCTAssertTrue(
      StorageRecovery.message(for: outOfSpace, operation: .ingest)
        .localizedCaseInsensitiveContains("resume")
    )

    let permission = CocoaError(.fileWriteNoPermission)
    XCTAssertEqual(StorageRecovery.classify(permission), .permissionLost)
    XCTAssertTrue(
      StorageRecovery.message(for: permission, operation: .projectSave)
        .localizedCaseInsensitiveContains("retry")
    )

    let unavailable = CocoaError(.fileReadNoSuchFile)
    XCTAssertEqual(StorageRecovery.classify(unavailable), .unavailable)
    XCTAssertTrue(
      StorageRecovery.message(for: unavailable, operation: .resumeIngest)
        .localizedCaseInsensitiveContains("reconnect")
    )
  }
}
