import XCTest
@testable import SlateBox

final class ClipCodableTests: XCTestCase {
  private func encoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }

  private func decoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }

  func testFullClipRoundTripPreservesMetadataAndAnalysis() throws {
    let capturedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let shotStartTime = Date(timeIntervalSince1970: 1_700_000_010)
    let manualShotTime = Date(timeIntervalSince1970: 1_700_000_020)
    var clip = Clip(
      originalSourcePath: "/Volumes/CARD/PRIVATE/A001.MP4",
      originalFilename: "A001.MP4",
      currentPath: "/Projects/Event/A001.MP4",
      currentFilename: "A001.MP4",
      relativePath: "Camera A/A001.MP4",
      fileSize: 4096,
      createdAt: capturedAt,
      modifiedAt: shotStartTime
    )
    clip.duration = 12.5
    clip.cullStatus = .keep
    clip.verificationStatus = .verified
    clip.capturedAt = capturedAt
    clip.shotStartTime = shotStartTime
    clip.manualShotTime = manualShotTime
    clip.shotTimeSource = .manual
    clip.productionTags = ["sermon"]
    clip.cameraLabel = "A-Cam"
    clip.camera = "Sony a7R V"
    clip.cameraOperator = "Caleb"
    clip.shootDay = capturedAt
    clip.automaticTags = ["face", "stable"]
    clip.customNotes = "Use this clip"
    clip.analysisStatus = .complete
    clip.focusScore = 0.91
    clip.hasFaces = true
    clip.motionScore = 0.3

    let decoded = try decoder().decode(Clip.self, from: try encoder().encode(clip))

    XCTAssertEqual(decoded.originalFilename, "A001.MP4")
    XCTAssertEqual(decoded.currentPath, "/Projects/Event/A001.MP4")
    XCTAssertEqual(decoded.duration, 12.5)
    XCTAssertEqual(decoded.fileSize, 4096)
    XCTAssertEqual(decoded.cullStatus, .keep)
    XCTAssertEqual(decoded.verificationStatus, .verified)
    XCTAssertEqual(decoded.capturedAt, capturedAt)
    XCTAssertEqual(decoded.shotStartTime, shotStartTime)
    XCTAssertEqual(decoded.manualShotTime, manualShotTime)
    XCTAssertEqual(decoded.shotTimeSource, .manual)
    XCTAssertEqual(decoded.productionTags, ["sermon"])
    XCTAssertEqual(decoded.cameraLabel, "A-Cam")
    XCTAssertEqual(decoded.camera, "Sony a7R V")
    XCTAssertEqual(decoded.cameraOperator, "Caleb")
    XCTAssertEqual(decoded.shootDay, capturedAt)
    XCTAssertEqual(decoded.automaticTags, ["face", "stable"])
    XCTAssertEqual(decoded.customNotes, "Use this clip")
    XCTAssertEqual(decoded.analysisStatus, .complete)
    XCTAssertEqual(decoded.focusScore, 0.91)
    XCTAssertTrue(decoded.hasFaces)
    XCTAssertEqual(decoded.motionScore, 0.3)
  }

  func testMinimalOldClipJSONDecodesWithSafeDefaults() throws {
    let json = """
    {
      "id": "33333333-3333-3333-3333-333333333333",
      "originalSourcePath": "/Volumes/CARD/A002.MP4",
      "originalFilename": "A002.MP4",
      "relativePath": "A002.MP4",
      "fileSize": 8192
    }
    """.data(using: .utf8)!

    let decoded = try decoder().decode(Clip.self, from: json)

    XCTAssertEqual(decoded.originalFilename, "A002.MP4")
    XCTAssertEqual(decoded.currentPath, "")
    XCTAssertEqual(decoded.copyStatus, .pending)
    XCTAssertEqual(decoded.verificationStatus, .pending)
    XCTAssertEqual(decoded.shotTimeSource, .unavailable)
    XCTAssertEqual(decoded.analysisStatus, .notAnalyzed)
    XCTAssertEqual(decoded.productionTags, [])
    XCTAssertEqual(decoded.automaticTags, [])
    XCTAssertEqual(decoded.customNotes, "")
  }

  // MARK: - Per-destination records

  private func verifiedClip(checksum: String?) -> Clip {
    var clip = Clip(
      originalSourcePath: "/Volumes/CARD/A001.MP4", originalFilename: "A001.MP4",
      currentPath: "/Projects/Event/A001.MP4", currentFilename: "A001.MP4",
      relativePath: "A001.MP4", fileSize: 4096)
    clip.copyStatus = .copied
    clip.verificationStatus = .verified
    clip.checksum = checksum
    return clip
  }

  func testDestinationRecordsRoundTrip() throws {
    var clip = verifiedClip(checksum: "abc123")
    clip.refreshPrimaryRecord(destinationPath: "/Projects/Event", method: .sha256)
    var backup = DestinationCopyRecord(role: .backup1)
    backup.destinationPath = "/Volumes/Backup"
    backup.copyState = .copied
    backup.verificationState = .verified
    backup.verificationMethod = .sizeCheck
    backup.byteSize = 4096
    clip.setDestinationRecord(backup)
    // Project JSON stores dates to the whole second (ISO 8601), so pin the
    // timestamps instead of comparing sub-second `Date()` values.
    let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
    clip.destinationRecords = clip.destinationRecords.map { record in
      var pinned = record
      pinned.updatedAt = fixedDate
      return pinned
    }

    let decoded = try decoder().decode(Clip.self, from: try encoder().encode(clip))

    XCTAssertEqual(decoded.destinationRecords, clip.destinationRecords)
    XCTAssertEqual(decoded.destinationRecord(for: .primary)?.verificationMethod, .sha256)
    XCTAssertEqual(decoded.destinationRecord(for: .backup1)?.verificationMethod, .sizeCheck)
    XCTAssertEqual(decoded.verifiedDestinationCount, 2)
  }

  func testLegacyVerifiedClipWithChecksumDerivesShaPrimaryOnly() throws {
    let json = """
    {
      "id": "44444444-4444-4444-4444-444444444444",
      "originalSourcePath": "/Volumes/CARD/A003.MP4",
      "originalFilename": "A003.MP4",
      "currentPath": "/Projects/Event/A003.MP4",
      "relativePath": "A003.MP4",
      "fileSize": 2048,
      "copyStatus": "copied",
      "verificationStatus": "verified",
      "checksum": "deadbeef"
    }
    """.data(using: .utf8)!

    let decoded = try decoder().decode(Clip.self, from: json)

    XCTAssertEqual(decoded.destinationRecords.count, 1)
    let primary = try XCTUnwrap(decoded.destinationRecord(for: .primary))
    XCTAssertTrue(primary.isVerified)
    XCTAssertEqual(primary.verificationMethod, .sha256)
    XCTAssertEqual(primary.checksum, "deadbeef")
    XCTAssertEqual(primary.byteSize, 2048)
    XCTAssertNil(decoded.destinationRecord(for: .backup1), "No backup state is invented for old projects")
    // Aggregate fields are untouched by the migration.
    XCTAssertEqual(decoded.verificationStatus, .verified)
    XCTAssertEqual(decoded.checksum, "deadbeef")
  }

  func testLegacyVerifiedClipWithoutChecksumIsLabeledSizeCheck() throws {
    let json = """
    {
      "originalSourcePath": "/Volumes/CARD/A004.MP4",
      "originalFilename": "A004.MP4",
      "currentPath": "/Projects/Event/A004.MP4",
      "relativePath": "A004.MP4",
      "fileSize": 1024,
      "verificationStatus": "verified"
    }
    """.data(using: .utf8)!

    let primary = try XCTUnwrap(try decoder().decode(Clip.self, from: json).destinationRecord(for: .primary))

    XCTAssertTrue(primary.isVerified)
    XCTAssertEqual(primary.verificationMethod, .sizeCheck)
    XCTAssertNil(primary.checksum)
  }

  func testLegacyClipWithNoDestinationPathHasNoRecords() throws {
    let json = """
    { "originalSourcePath": "/Volumes/CARD/A005.MP4", "relativePath": "A005.MP4", "fileSize": 1 }
    """.data(using: .utf8)!

    XCTAssertTrue(try decoder().decode(Clip.self, from: json).destinationRecords.isEmpty)
  }

  func testBackupFailureNeverDowngradesVerifiedPrimary() {
    var clip = verifiedClip(checksum: nil)
    clip.refreshPrimaryRecord(destinationPath: "/Projects/Event", method: .sizeCheck)

    let failed = BackupCopyResult(role: .backup1, rootPath: "/Volumes/Backup", warning: "Backup 1 is unavailable.")
    clip.setDestinationRecord(failed.record())

    XCTAssertEqual(clip.destinationRecord(for: .primary)?.verificationState, .verified)
    XCTAssertEqual(clip.destinationRecord(for: .backup1)?.verificationState, .failed)
    XCTAssertEqual(clip.destinationRecord(for: .backup1)?.errorMessage, "Backup 1 is unavailable.")
    XCTAssertEqual(clip.verifiedDestinationCount, 1)
  }

  func testVerifiedPrimaryDoesNotImplyVerifiedBackup() {
    var clip = verifiedClip(checksum: "abc")
    clip.refreshPrimaryRecord(destinationPath: "/Projects/Event")
    XCTAssertNil(clip.destinationRecord(for: .backup1))
    XCTAssertEqual(clip.verifiedDestinationCount, 1)
  }

  func testBackupRecordNeverLabelsSizeCheckAsChecksum() {
    let outcome = VerificationOutcome(mode: .fast, bytes: 10, checksum: nil)
    let record = BackupCopyResult(role: .backup2, rootPath: "/B", byteSize: 10, outcome: outcome).record()
    XCTAssertEqual(record.verificationMethod, .sizeCheck)
    XCTAssertNil(record.checksum)

    let strong = VerificationOutcome(mode: .strong, bytes: 10, checksum: "ff")
    let strongRecord = BackupCopyResult(role: .backup2, rootPath: "/B", byteSize: 10, outcome: strong).record()
    XCTAssertEqual(strongRecord.verificationMethod, .sha256)
    XCTAssertEqual(strongRecord.checksum, "ff")
  }

  func testBackupWarningIsNotStoredAsPrimaryError() {
    var clip = verifiedClip(checksum: nil)
    clip.errorMessage = "Primary verified. Backup warning: Backup 1 is unavailable."
    clip.refreshPrimaryRecord(destinationPath: "/Projects/Event")
    XCTAssertNil(clip.destinationRecord(for: .primary)?.errorMessage)
  }

  func testRefreshPrimaryRecordFollowsFailure() {
    var clip = verifiedClip(checksum: nil)
    clip.copyStatus = .failed
    clip.verificationStatus = .failed
    clip.errorMessage = "The destination is full."
    clip.refreshPrimaryRecord(destinationPath: "/Projects/Event")
    let primary = clip.destinationRecord(for: .primary)
    XCTAssertEqual(primary?.copyState, .failed)
    XCTAssertEqual(primary?.verificationState, .failed)
    XCTAssertEqual(primary?.verificationMethod, VerificationMethod.none)
    XCTAssertEqual(primary?.errorMessage, "The destination is full.")
  }
}
