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
}
