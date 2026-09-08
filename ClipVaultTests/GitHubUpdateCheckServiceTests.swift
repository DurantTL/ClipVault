import XCTest
@testable import SlateBox

final class GitHubUpdateCheckServiceTests: XCTestCase {
  func testNormalizeVersionStripsVPrefix() {
    XCTAssertEqual(GitHubReleaseDTO.normalizeVersion("v1.2.3"), "1.2.3")
    XCTAssertEqual(GitHubReleaseDTO.normalizeVersion("1.0.0"), "1.0.0")
  }

  func testCompareVersions() {
    XCTAssertEqual(GitHubUpdateCheckService.compareVersions("1.2.3", "1.2.3"), .orderedSame)
    XCTAssertEqual(GitHubUpdateCheckService.compareVersions("1.2.4", "1.2.3"), .orderedDescending)
    XCTAssertEqual(GitHubUpdateCheckService.compareVersions("1.2.0", "1.2.3"), .orderedAscending)
    XCTAssertEqual(GitHubUpdateCheckService.compareVersions("2.0", "1.9.9"), .orderedDescending)
  }
}
