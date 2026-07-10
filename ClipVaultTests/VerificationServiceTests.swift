import XCTest

@testable import SlateBox

final class VerificationServiceTests: XCTestCase {
  private var directory: URL!
  private let service = VerificationService()

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("clipvault-verify-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
  }

  private func write(_ data: Data, to name: String) throws -> URL {
    let url = directory.appendingPathComponent(name)
    try data.write(to: url)
    return url
  }

  func testFastPassesOnEqualSize() async throws {
    // Fast mode only compares sizes, so equal-size files with different bytes
    // pass. That trade-off is the documented default for large 4K files.
    let source = try write(Data(repeating: 0xAA, count: 2048), to: "src.mp4")
    let destination = try write(Data(repeating: 0xBB, count: 2048), to: "dst.mp4")
    try await service.verify(source: source, destination: destination, mode: .fast)
  }

  func testFastFailsOnSizeMismatch() async throws {
    let source = try write(Data(repeating: 0xAA, count: 2048), to: "src.mp4")
    let destination = try write(Data(repeating: 0xAA, count: 1024), to: "dst.mp4")
    do {
      try await service.verify(source: source, destination: destination, mode: .fast)
      XCTFail("expected size-mismatch error")
    } catch let error as NSError {
      XCTAssertEqual(error.code, 1)
      XCTAssertEqual(error.localizedDescription, "File size mismatch after copy.")
    }
  }

  func testStrongPassesOnIdenticalContent() async throws {
    // 3 MB exercises the chunked SHA256 loop (1 MB reads) across chunks.
    let data = Data((0..<3_000_000).map { UInt8($0 % 253) })
    let source = try write(data, to: "src.mp4")
    let destination = try write(data, to: "dst.mp4")
    try await service.verify(source: source, destination: destination, mode: .strong)
  }

  func testStrongFailsOnSameSizeDifferentContent() async throws {
    var corrupted = Data((0..<2048).map { UInt8($0 % 253) })
    let source = try write(corrupted, to: "src.mp4")
    corrupted[1024] ^= 0xFF
    let destination = try write(corrupted, to: "dst.mp4")
    do {
      try await service.verify(source: source, destination: destination, mode: .strong)
      XCTFail("expected checksum-mismatch error")
    } catch let error as NSError {
      XCTAssertEqual(error.code, 2)
      XCTAssertEqual(error.localizedDescription, "SHA256 checksum mismatch.")
    }
  }

  func testFailsWhenDestinationMissing() async throws {
    let source = try write(Data(repeating: 0xAA, count: 128), to: "src.mp4")
    let destination = directory.appendingPathComponent("missing.mp4")
    do {
      try await service.verify(source: source, destination: destination, mode: .fast)
      XCTFail("expected fileNoSuchFile")
    } catch let error as CocoaError {
      XCTAssertEqual(error.code, .fileNoSuchFile)
    }
  }
}
