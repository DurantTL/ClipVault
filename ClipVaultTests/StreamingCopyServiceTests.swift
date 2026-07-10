import XCTest

@testable import SlateBox

final class StreamingCopyServiceTests: XCTestCase {
  private var directory: URL!

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("clipvault-copy-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
  }

  private func makeSource(named name: String = "A001.MP4", bytes: Int) throws -> (url: URL, data: Data) {
    let data = Data((0..<bytes).map { UInt8($0 % 251) })
    let url = directory.appendingPathComponent(name)
    try data.write(to: url)
    return (url, data)
  }

  private func partialURL(for destination: URL) -> URL {
    destination.deletingLastPathComponent()
      .appendingPathComponent(destination.lastPathComponent + AppBrand.partialFileSuffix)
  }

  func testCopyProducesIdenticalBytesAndRemovesPartial() async throws {
    let (source, data) = try makeSource(bytes: 10_240)
    let destination = directory.appendingPathComponent("out/A001.MP4")
    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)

    let service = StreamingCopyService(chunkSize: 1024)
    let copied = try await service.copy(
      from: source, to: destination, alreadyCopiedBytes: 0, totalBytes: Int64(data.count)
    ) { _ in }

    XCTAssertEqual(copied, Int64(data.count))
    XCTAssertEqual(try Data(contentsOf: destination), data)
    XCTAssertFalse(FileManager.default.fileExists(atPath: partialURL(for: destination).path))
    XCTAssertEqual(try Data(contentsOf: source), data, "source must never be modified")
  }

  func testMultiChunkCopyReportsMonotonicProgressUpToTotal() async throws {
    let (source, data) = try makeSource(bytes: 10_240)
    let destination = directory.appendingPathComponent("B001.MP4")

    let progressLog = ProgressLog()
    let service = StreamingCopyService(chunkSize: 1024)
    _ = try await service.copy(
      from: source, to: destination, alreadyCopiedBytes: 0, totalBytes: Int64(data.count)
    ) { progressLog.record($0) }

    let values = progressLog.values
    XCTAssertGreaterThanOrEqual(values.count, 10, "1 KB chunks over 10 KB should report repeatedly")
    XCTAssertEqual(values, values.sorted(), "progress must be monotonic")
    XCTAssertEqual(values.last, Int64(data.count))
  }

  func testCancelLeavesPartialAndSourceUntouchedAndNoDestination() async throws {
    let (source, data) = try makeSource(bytes: 10_240)
    let destination = directory.appendingPathComponent("C001.MP4")

    let cancelFlag = Flag()
    let service = StreamingCopyService(chunkSize: 1024)
    service.isCancelled = { cancelFlag.value }

    do {
      _ = try await service.copy(
        from: source, to: destination, alreadyCopiedBytes: 0, totalBytes: Int64(data.count)
      ) { _ in cancelFlag.value = true }
      XCTFail("expected CancellationError")
    } catch is CancellationError {
      // expected
    }

    XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path), "canceled copy must not produce a destination file")
    XCTAssertTrue(FileManager.default.fileExists(atPath: partialURL(for: destination).path), "canceled copy leaves its partial for resume")
    XCTAssertEqual(try Data(contentsOf: source), data, "source must never be modified")
  }

  func testResumeFromPartialCompletesFileCorrectly() async throws {
    let (source, data) = try makeSource(bytes: 10_240)
    let destination = directory.appendingPathComponent("D001.MP4")
    try data.prefix(4096).write(to: partialURL(for: destination))

    let service = StreamingCopyService(chunkSize: 1024)
    let copied = try await service.copy(
      from: source, to: destination, alreadyCopiedBytes: 0, totalBytes: Int64(data.count)
    ) { _ in }

    XCTAssertEqual(copied, Int64(data.count), "resumed copy reports the full file size")
    XCTAssertEqual(try Data(contentsOf: destination), data, "resumed file must be byte-identical to the source")
    XCTAssertFalse(FileManager.default.fileExists(atPath: partialURL(for: destination).path))
  }

  func testStalePartialAtOrAboveSourceSizeIsDiscardedAndRecopied() async throws {
    let (source, data) = try makeSource(bytes: 4096)
    let destination = directory.appendingPathComponent("E001.MP4")
    try Data(repeating: 0xFF, count: 4096).write(to: partialURL(for: destination))

    let service = StreamingCopyService(chunkSize: 1024)
    _ = try await service.copy(
      from: source, to: destination, alreadyCopiedBytes: 0, totalBytes: Int64(data.count)
    ) { _ in }

    XCTAssertEqual(try Data(contentsOf: destination), data, "a stale partial must be discarded, not trusted")
  }

  func testExistingDestinationIsNeverOverwritten() async throws {
    let (source, data) = try makeSource(bytes: 2048)
    let destination = directory.appendingPathComponent("F001.MP4")
    let existing = Data("existing file".utf8)
    try existing.write(to: destination)

    let service = StreamingCopyService(chunkSize: 1024)
    do {
      _ = try await service.copy(
        from: source, to: destination, alreadyCopiedBytes: 0, totalBytes: Int64(data.count)
      ) { _ in }
      XCTFail("expected fileWriteFileExists")
    } catch let error as CocoaError {
      XCTAssertEqual(error.code, .fileWriteFileExists)
    }

    XCTAssertEqual(try Data(contentsOf: destination), existing, "destination must never be overwritten")
    XCTAssertEqual(try Data(contentsOf: source), data, "source must never be modified")
  }
}

/// The copy loop reads these from a detached task while the test writes them
/// from the main-actor progress callback, so guard the value with a lock.
private final class Flag: @unchecked Sendable {
  private let lock = NSLock()
  private var stored = false
  var value: Bool {
    get { lock.withLock { stored } }
    set { lock.withLock { stored = newValue } }
  }
}

private final class ProgressLog: @unchecked Sendable {
  private let lock = NSLock()
  private var stored: [Int64] = []
  func record(_ value: Int64) { lock.withLock { stored.append(value) } }
  var values: [Int64] { lock.withLock { stored } }
}
