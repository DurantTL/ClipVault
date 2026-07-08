import XCTest
@testable import ClipVault

final class ProjectCodableTests: XCTestCase {
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

  private func clip(
    id: UUID = UUID(),
    filename: String,
    currentPath: String,
    copyStatus: ClipCopyStatus = .copied,
    verificationStatus: VerificationStatus = .verified,
    errorMessage: String? = nil
  ) -> Clip {
    var clip = Clip(
      id: id,
      originalSourcePath: "/Volumes/CARD/PRIVATE/\(filename)",
      originalFilename: filename,
      currentPath: currentPath,
      currentFilename: filename,
      relativePath: filename,
      fileSize: 1024,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000),
      modifiedAt: Date(timeIntervalSince1970: 1_700_000_100),
      ingestDate: Date(timeIntervalSince1970: 1_700_000_200)
    )
    clip.copyStatus = copyStatus
    clip.verificationStatus = verificationStatus
    clip.errorMessage = errorMessage
    return clip
  }

  func testProjectRoundTripPreservesSchemaAndIngestFields() throws {
    let sessionID = UUID()
    var project = ClipVaultProject(
      id: UUID(),
      name: "Sunday Service",
      createdAt: Date(timeIntervalSince1970: 1_700_000_000),
      projectFolderPath: "/Users/test/ClipVault/Sunday Service",
      ingestStatus: .complete,
      totalSelectedClips: 2,
      copiedClipCount: 2,
      verifiedClipCount: 2,
      failedClipCount: 0,
      pendingClipCount: 0,
      selectedSessionIDs: [sessionID],
      clips: [
        clip(filename: "A001.MP4", currentPath: "/Projects/Sunday/A001.MP4"),
        clip(filename: "A002.MP4", currentPath: "/Projects/Sunday/A002.MP4")
      ]
    )
    project.projectTitle = "Service Edit"
    project.productionName = "Weekend"
    project.defaultTags = ["sermon", "wide"]

    let data = try encoder().encode(project)
    let decoded = try decoder().decode(ClipVaultProject.self, from: data)

    XCTAssertEqual(decoded.schemaVersion, ClipVaultProject.currentSchemaVersion)
    XCTAssertEqual(decoded.id, project.id)
    XCTAssertEqual(decoded.name, project.name)
    XCTAssertEqual(decoded.clips.count, 2)
    XCTAssertEqual(decoded.ingestStatus, .complete)
    XCTAssertEqual(decoded.copiedClipCount, 2)
    XCTAssertEqual(decoded.verifiedClipCount, 2)
    XCTAssertEqual(decoded.pendingClipCount, 0)
    XCTAssertEqual(decoded.selectedSessionIDs, [sessionID])
    XCTAssertEqual(decoded.projectTitle, "Service Edit")
    XCTAssertEqual(decoded.defaultTags, ["sermon", "wide"])
  }

  func testOldProjectJSONMissingNewerFieldsDecodesWithSafeDefaults() throws {
    let json = """
    {
      "id": "11111111-1111-1111-1111-111111111111",
      "name": "Legacy Project",
      "createdAt": "2024-01-02T03:04:05Z",
      "projectFolderPath": "/Projects/Legacy",
      "customFolders": ["Sermon"],
      "clips": [
        {
          "id": "22222222-2222-2222-2222-222222222222",
          "originalSourcePath": "/Volumes/CARD/A001.MP4",
          "originalFilename": "A001.MP4",
          "currentPath": "/Projects/Legacy/A001.MP4",
          "currentFilename": "A001.MP4",
          "relativePath": "A001.MP4",
          "fileSize": 2048,
          "verified": true
        }
      ]
    }
    """.data(using: .utf8)!

    let decoded = try decoder().decode(ClipVaultProject.self, from: json)

    XCTAssertEqual(decoded.schemaVersion, 0)
    XCTAssertEqual(decoded.name, "Legacy Project")
    XCTAssertEqual(decoded.ingestStatus, .complete)
    XCTAssertEqual(decoded.selectedSessionIDs, [])
    XCTAssertEqual(decoded.sourceSessions, [])
    XCTAssertEqual(decoded.projectTitle, "")
    XCTAssertEqual(decoded.defaultTags, [])
    XCTAssertEqual(decoded.totalSelectedClips, 1)
    XCTAssertEqual(decoded.verifiedClipCount, 1)
    XCTAssertEqual(decoded.clips.count, 1)
  }

  func testPartialIngestProjectRoundTripKeepsResumeStateAndClipFailures() throws {
    let copied = clip(filename: "A001.MP4", currentPath: "/Projects/Partial/A001.MP4")
    var pending = clip(filename: "A002.MP4", currentPath: "", copyStatus: .pending, verificationStatus: .pending)
    pending.currentFilename = "A002.MP4"
    var failed = clip(filename: "A003.MP4", currentPath: "", copyStatus: .failed, verificationStatus: .failed, errorMessage: "Copy failed")
    failed.currentFilename = "A003.MP4"

    let project = ClipVaultProject(
      name: "Partial Ingest",
      projectFolderPath: "/Projects/Partial",
      ingestStatus: .incomplete,
      totalSelectedClips: 3,
      copiedClipCount: 1,
      verifiedClipCount: 1,
      failedClipCount: 1,
      pendingClipCount: 2,
      canResumeIngest: true,
      clips: [copied, pending, failed]
    )

    let decoded = try decoder().decode(ClipVaultProject.self, from: try encoder().encode(project))

    XCTAssertEqual(decoded.ingestStatus, .incomplete)
    XCTAssertEqual(decoded.copiedClipCount, 1)
    XCTAssertEqual(decoded.pendingClipCount, 2)
    XCTAssertTrue(decoded.canResumeIngest)
    XCTAssertEqual(decoded.clips[1].currentPath, "")
    XCTAssertEqual(decoded.clips[1].copyStatus, .pending)
    XCTAssertEqual(decoded.clips[2].errorMessage, "Copy failed")
  }
}
