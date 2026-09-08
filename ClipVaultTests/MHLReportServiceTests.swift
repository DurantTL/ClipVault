import CryptoKit
import XCTest

@testable import SlateBox

final class MHLReportServiceTests: XCTestCase {
  private var directory: URL!
  private var projectFolder: URL!
  private var sourceCard: URL!
  private var reportsDir: URL!
  private let service = MHLReportService()

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("clipvault-mhl-test-\(UUID().uuidString)", isDirectory: true)
    projectFolder = directory.appendingPathComponent("Project", isDirectory: true)
    sourceCard = directory.appendingPathComponent("Volumes").appendingPathComponent("CARD", isDirectory: true)
    reportsDir = projectFolder
      .appendingPathComponent(AppBrand.cacheFolderName, isDirectory: true)
      .appendingPathComponent("reports", isDirectory: true)
    try FileManager.default.createDirectory(at: projectFolder, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: sourceCard, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: reportsDir, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
  }

  private func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private func makeClip(
    name: String,
    content: String,
    status: VerificationStatus,
    checksum: String?,
    underSource: Bool = false
  ) throws -> Clip {
    let projectFolder = try XCTUnwrap(self.projectFolder)
    let sourceCard = try XCTUnwrap(self.sourceCard)
    let mediaParent = underSource ? sourceCard : projectFolder
    let mediaURL = mediaParent.appendingPathComponent(name)
    let data = Data(content.utf8)
    try data.write(to: mediaURL)
    var clip = Clip(
      originalSourcePath: sourceCard.appendingPathComponent(name).path,
      originalFilename: name,
      currentPath: mediaURL.path,
      currentFilename: name,
      relativePath: name,
      fileSize: Int64(data.count)
    )
    clip.sourcePath = sourceCard.appendingPathComponent(name).path
    clip.destinationRelativePath = name
    clip.verificationStatus = status
    clip.checksum = checksum
    let copied = (status == VerificationStatus.verified || status == VerificationStatus.copied)
    clip.copyStatus = copied ? ClipCopyStatus.copied : ClipCopyStatus.pending
    return clip
  }

  private func makeProject(clips: [Clip]) throws -> ClipVaultProject {
    let projectFolder = try XCTUnwrap(self.projectFolder)
    return ClipVaultProject(
      name: "MHL Demo",
      projectFolderPath: projectFolder.path,
      clips: clips
    )
  }

  func testXMLContainsExpectedSHA256AndExcludesFailedPending() throws {
    let payload = "hello-mhl-bytes"
    let digest = sha256Hex(Data(payload.utf8))
    let verified = try makeClip(name: "A001.MP4", content: payload, status: .verified, checksum: digest)
    let failed = try makeClip(name: "BAD.MP4", content: "bad", status: .failed, checksum: nil)
    var pending = try makeClip(name: "WAIT.MP4", content: "wait", status: .pending, checksum: nil)
    pending.checksum = nil
    // Honesty: even a leftover checksum on a failed clip must not appear.
    var failedWithJunk = failed
    failedWithJunk.checksum = "deadbeef"

    let xml = MHLReportService.buildClassicMHLXML(
      projectName: "MHL Demo",
      destinationLabel: "Primary",
      clips: [verified, failedWithJunk, pending],
      destinationRoot: projectFolder,
      createdAt: Date(timeIntervalSince1970: 1_800_000_000),
      hostname: "test-host",
      appVersion: "1.0"
    )

    XCTAssertTrue(xml.contains("<hashlist version=\"1.1\">"))
    XCTAssertTrue(xml.contains("<name>\(AppBrand.appName)</name>"))
    XCTAssertTrue(xml.contains("<file>A001.MP4</file>"))
    XCTAssertTrue(xml.contains("<hash>\(digest)</hash>"))
    XCTAssertTrue(xml.contains("<hashformat>sha256</hashformat>"))
    XCTAssertTrue(xml.contains("<size>\(payload.utf8.count)</size>"))
    XCTAssertFalse(xml.contains("BAD.MP4"))
    XCTAssertFalse(xml.contains("WAIT.MP4"))
    XCTAssertFalse(xml.contains("deadbeef"))
  }

  func testRefusesWhenOnlyFastVerifyDataExists() async {
    // Verified via fast mode: status verified but checksum absent.
    let clip: Clip
    do {
      clip = try makeClip(name: "FAST.MP4", content: "fast-only", status: .verified, checksum: nil)
    } catch {
      return XCTFail("setup failed: \(error)")
    }
    let project: ClipVaultProject
    do {
      project = try makeProject(clips: [clip])
    } catch {
      return XCTFail("setup failed: \(error)")
    }
    let destinations = [MHLDestination(label: "Primary", rootURL: projectFolder)]

    do {
      _ = try await service.generate(
        project: project,
        clips: project.clips,
        destinations: destinations,
        options: MHLExportOptions(now: Date(), outputDirectory: reportsDir, hostname: "test", appVersion: "1.0")
      )
      XCTFail("expected noEligibleClips")
    } catch let error as MHLReportError {
      XCTAssertEqual(error, .noEligibleClips)
    } catch {
      XCTFail("unexpected error: \(error)")
    }

    let written = (try? FileManager.default.contentsOfDirectory(atPath: reportsDir.path)) ?? []
    XCTAssertTrue(written.filter { $0.hasSuffix(".mhl") }.isEmpty, "must not write a fake success MHL")
  }

  func testGenerateWritesMHLUnderProjectReportsNotSourceCard() async throws {
    let payload = "primary-copy"
    let digest = sha256Hex(Data(payload.utf8))
    let clip = try makeClip(name: "A001.MP4", content: payload, status: .verified, checksum: digest)
    let project = try makeProject(clips: [clip])
    let destinations = [
      MHLDestination(label: "Primary", rootURL: projectFolder),
      MHLDestination(label: "Backup 1", rootURL: projectFolder),
    ]

    let summary = try await service.generate(
      project: project,
      clips: project.clips,
      destinations: destinations,
      options: MHLExportOptions(
        now: Date(timeIntervalSince1970: 1_800_000_000),
        outputDirectory: reportsDir,
        hostname: "test-host",
        appVersion: "1.0"
      )
    )

    XCTAssertEqual(summary.writtenFiles.count, 2)
    XCTAssertEqual(summary.includedClipCount, 1)
    XCTAssertEqual(summary.skippedClipCount, 0)
    for file in summary.writtenFiles {
      XCTAssertTrue(file.url.path.hasPrefix(reportsDir.path))
      XCTAssertFalse(file.url.path.hasPrefix(sourceCard.path), "must never write onto source card")
      let xml = try String(contentsOf: file.url, encoding: .utf8)
      XCTAssertTrue(xml.contains(digest))
      XCTAssertTrue(xml.contains("<file>A001.MP4</file>"))
    }

    // Explicit refuse when targeting the source card directory.
    do {
      try MHLReportService.assertSafeOutputDirectory(sourceCard, clips: [clip])
      XCTFail("expected forbiddenSourceWrite")
    } catch let error as MHLReportError {
      guard case .forbiddenSourceWrite = error else {
        return XCTFail("wrong error \(error)")
      }
    }
  }

  func testZeroEligibleClipsFailsWithoutWriting() async throws {
    let pending = try makeClip(name: "P.MP4", content: "p", status: .pending, checksum: nil)
    let project = try makeProject(clips: [pending])
    do {
      _ = try await service.generate(
        project: project,
        clips: project.clips,
        destinations: [MHLDestination(label: "Primary", rootURL: projectFolder)],
        options: MHLExportOptions(outputDirectory: reportsDir)
      )
      XCTFail("expected failure")
    } catch MHLReportError.noEligibleClips {
      // expected
    }
    let written = try FileManager.default.contentsOfDirectory(atPath: reportsDir.path)
    XCTAssertTrue(written.filter { $0.hasSuffix(".mhl") }.isEmpty)
  }
}
