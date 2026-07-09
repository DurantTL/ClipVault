import XCTest

@testable import ClipVault

final class RatingAndSuggestionTests: XCTestCase {
  private func makeClip() -> Clip {
    Clip(
      originalSourcePath: "/Volumes/CARD/PRIVATE/A001.MP4",
      originalFilename: "A001.MP4",
      currentPath: "/Projects/Event/A001.MP4",
      currentFilename: "A001.MP4",
      relativePath: "A001.MP4",
      fileSize: 4096
    )
  }

  // MARK: - Rating ↔ cull status mapping

  func testApplyRatingMapsToCullStatus() {
    var clip = makeClip()
    let expectations: [(Int, CullStatus)] = [
      (0, .unrated), (1, .reject), (2, .maybe), (3, .maybe), (4, .keep), (5, .keep)
    ]
    for (rating, status) in expectations {
      clip.applyRating(rating)
      XCTAssertEqual(clip.rating, rating)
      XCTAssertEqual(clip.cullStatus, status, "rating \(rating) should map to \(status)")
    }
  }

  func testApplyRatingClampsOutOfRangeValues() {
    var clip = makeClip()
    clip.applyRating(9)
    XCTAssertEqual(clip.rating, 5)
    XCTAssertEqual(clip.cullStatus, .keep)
    clip.applyRating(-2)
    XCTAssertEqual(clip.rating, 0)
    XCTAssertEqual(clip.cullStatus, .unrated)
  }

  func testApplyCullStatusPreservesConsistentRating() {
    var clip = makeClip()
    clip.applyRating(5)
    clip.applyCullStatus(.keep)
    XCTAssertEqual(clip.rating, 5, "keep must not downgrade an existing 5-star rating")
    clip.applyRating(2)
    clip.applyCullStatus(.maybe)
    XCTAssertEqual(clip.rating, 2, "maybe must not overwrite a consistent 2-star rating")
  }

  func testApplyCullStatusFixesInconsistentRating() {
    var clip = makeClip()
    clip.applyRating(5)
    clip.applyCullStatus(.reject)
    XCTAssertEqual(clip.rating, 1)
    clip.applyCullStatus(.keep)
    XCTAssertEqual(clip.rating, 4)
    clip.applyCullStatus(.unrated)
    XCTAssertEqual(clip.rating, 0)
  }

  // MARK: - Codable compatibility

  func testRatingRoundTrips() throws {
    var clip = makeClip()
    clip.applyRating(4)
    let decoded = try JSONDecoder().decode(Clip.self, from: try JSONEncoder().encode(clip))
    XCTAssertEqual(decoded.rating, 4)
    XCTAssertEqual(decoded.cullStatus, .keep)
  }

  func testOldClipJSONWithoutRatingDerivesRatingFromCullStatus() throws {
    let expectations: [(CullStatus, Int)] = [
      (.unrated, 0), (.reject, 1), (.maybe, 3), (.keep, 4)
    ]
    for (status, expectedRating) in expectations {
      let json = """
        {"originalSourcePath":"/src/A.MP4","currentPath":"/dst/A.MP4","cullStatus":"\(status.rawValue)"}
        """
      let decoded = try JSONDecoder().decode(Clip.self, from: Data(json.utf8))
      XCTAssertEqual(decoded.cullStatus, status)
      XCTAssertEqual(decoded.rating, expectedRating, "old \(status.rawValue) project should surface as \(expectedRating) stars")
    }
  }

  // MARK: - Analysis quality and suggestions

  func testQualityScoreIsNilBeforeAnalysisCompletes() {
    var clip = makeClip()
    clip.focusScore = 90
    clip.analysisStatus = .notAnalyzed
    XCTAssertNil(clip.analysisQualityScore)
    XCTAssertNil(clip.suggestedRating)
  }

  func testHighQualityClipSuggestsTopRating() {
    var clip = makeClip()
    clip.analysisStatus = .complete
    clip.focusScore = 92
    clip.stabilityScore = 90
    clip.brightnessScore = 55
    clip.contrastScore = 45
    guard let quality = clip.analysisQualityScore else { return XCTFail("expected a quality score") }
    XCTAssertGreaterThanOrEqual(quality, 78)
    XCTAssertEqual(clip.suggestedRating, 5)
  }

  func testBlurryShakyClipSuggestsReject() {
    var clip = makeClip()
    clip.analysisStatus = .complete
    clip.focusScore = 20
    clip.focusWarning = true
    clip.stabilityScore = 25
    clip.possiblyShaky = true
    clip.brightnessScore = 30
    clip.contrastScore = 12
    XCTAssertEqual(clip.suggestedRating, 1)
  }

  func testSocialPickRequiresFacesShortDurationAndStability() {
    var clip = makeClip()
    clip.analysisStatus = .complete
    clip.focusScore = 85
    clip.stabilityScore = 85
    clip.brightnessScore = 55
    clip.contrastScore = 45
    clip.duration = 45
    clip.hasFaces = true
    XCTAssertTrue(clip.isSuggestedSocialPick)

    clip.duration = 600
    XCTAssertFalse(clip.isSuggestedSocialPick, "long clips are not social picks")
    clip.duration = 45
    clip.hasFaces = false
    XCTAssertFalse(clip.isSuggestedSocialPick, "social picks need someone in frame")
  }

  // MARK: - Export naming safety

  func testUniqueURLNeverOverwritesExistingFiles() throws {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("clipvault-export-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let desired = dir.appendingPathComponent("A001.MP4")
    XCTAssertEqual(SafeFilename.uniqueURL(for: desired), desired)

    try Data("first".utf8).write(to: desired)
    let second = SafeFilename.uniqueURL(for: desired)
    XCTAssertEqual(second.lastPathComponent, "A001_1.MP4")

    try Data("second".utf8).write(to: second)
    XCTAssertEqual(SafeFilename.uniqueURL(for: desired).lastPathComponent, "A001_2.MP4")
  }

  func testAliasesPointOnlyAtCopiedMediaAndNeverReplaceIt() throws {
    let project = FileManager.default.temporaryDirectory
      .appendingPathComponent("clipvault-alias-test-\(UUID().uuidString)", isDirectory: true)
    let ingest = project.appendingPathComponent("Original Ingest", isDirectory: true)
    try FileManager.default.createDirectory(at: ingest, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: project) }

    let media = ingest.appendingPathComponent("A001.MP4")
    try Data("copied media".utf8).write(to: media)
    var clip = makeClip()
    clip.currentPath = media.path
    clip.currentFilename = media.lastPathComponent

    let service = AliasService()
    let first = service.createAliases(named: "Keep", for: [(clip, media)], projectFolder: project)
    XCTAssertEqual(first.createdCount, 1)
    let alias = first.aliasesFolder.appendingPathComponent("A001.MP4")
    XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: alias.path), media.path)
    XCTAssertTrue(FileManager.default.fileExists(atPath: media.path))

    let second = service.createAliases(named: "Keep", for: [(clip, media)], projectFolder: project)
    XCTAssertEqual(second.createdCount, 0)
    XCTAssertEqual(second.skippedCount, 1)
    XCTAssertEqual(try String(contentsOf: media), "copied media")
  }
}
